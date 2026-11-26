// CAPA: PRESENTACIÓN — ViewModel
// G-06 Ruta hacia el usuario · G-07 Registro de llegada · Esperando confirmación
// Escucha la alerta asignada, guarda la ubicación del guardia y pregunta a
// ReglaGeocerca si "Llegué" está permitido. No importa material.dart.
// Con la API real la posición sale del GPS ([SeguimientoGuardia], CR-F03); en la
// demo sale del perfil y la mueve "Simular acercamiento".
// "Abrir en Google Maps" (CR-F04) pasa por [AbridorEnlaces]; aquí solo se arma la dirección.

import 'dart:async';

import '../../datos/abridor_enlaces.dart';
import '../../datos/alerta_guardia_repository.dart';
import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/formato.dart';
import '../comun/view_model.dart';
import 'seguimiento_guardia.dart';

class NavegacionViewModel extends ViewModel {
  NavegacionViewModel(
    this._alertas,
    this.alertaId, {
    required this.config,
    SeguimientoGuardia? seguimiento,
    AbridorEnlaces? enlaces,
  })  : _seguimiento = seguimiento,
        _enlaces = enlaces ?? AbridorEnlacesSimulado();

  final AlertaGuardiaRepository _alertas;
  final String alertaId;
  final Configuracion config;

  /// GPS real del guardia; `null` en la demo.
  final SeguimientoGuardia? _seguimiento;
  StreamSubscription<PuntoGeo>? _subPosicion;

  /// CR-F04: abre la ruta en Google Maps.
  final AbridorEnlaces _enlaces;

  EstadoVista<Alerta> estado = const Cargando();
  PuntoGeo? miUbicacion;
  bool llegando = false;
  String? mensaje;

  StreamSubscription<Alerta>? _sub;

  Alerta? get alerta => estado.datos;
  bool get modoDemo => config.modoDemo;
  int get radio => config.radioGeocercaMetros;

  double? get distancia {
    final a = alerta?.ubicacion;
    final yo = miUbicacion;
    return a == null || yo == null ? null : ReglaGeocerca.distanciaMetros(yo, a);
  }

  bool get dentroDeGeocerca => ReglaGeocerca.validarLlegada(miUbicacion, alerta?.ubicacion, radio) == null;

  double get metrosRestantes {
    final a = alerta?.ubicacion;
    final yo = miUbicacion;
    return a == null || yo == null ? double.infinity : ReglaGeocerca.metrosRestantes(yo, a, radio);
  }

  /// G-06: tiempo estimado de llegada, con la misma regla que ve el usuario (U-08).
  int? get segundosEstimados {
    final d = distancia;
    return d == null ? null : ReglaEta.segundos(distanciaMetros: d, metrosPorMinutoGuardia: config.metrosPorMinutoGuardia);
  }

  /// G-06: ruta en Google Maps hacia el punto de la alerta. Sin origen: Maps usa el GPS del
  /// teléfono, que es más fresco que el último que tenemos aquí.
  static Uri urlRuta(PuntoGeo destino) => Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': '${destino.lat},${destino.lng}',
      });

  /// G-07: solo con la alerta en atención y dentro de la geocerca.
  bool get puedeMarcarLlegada => alerta?.estado == EstadoAlerta.enAtencion && dentroDeGeocerca && !llegando;

  Future<void> iniciar() async {
    estado = const Cargando();
    notifyListeners();
    try {
      miUbicacion = (await _alertas.obtenerMiPerfil()).perfil.ultimaUbicacion;
    } catch (e) {
      estado = ErrorVista(ViewModel.mensajeDe(e));
      notifyListeners();
      return;
    }
    if (desechado) return; // se salió de la pantalla mientras cargaba: nada que escuchar
    // Con GPS real manda lo último que leyó el sensor; el perfil queda de respaldo
    // mientras llega la primera lectura.
    final gps = _seguimiento;
    if (gps != null) {
      miUbicacion = gps.ultimaPosicion ?? miUbicacion;
      _subPosicion?.cancel();
      _subPosicion = gps.posiciones.listen((p) {
        miUbicacion = p;
        notifyListeners();
      });
    }
    _sub?.cancel();
    _sub = _alertas.escucharAlerta(alertaId).listen(
      (a) {
        estado = Listo(a);
        notifyListeners();
      },
      onError: (Object e) {
        estado = ErrorVista(ViewModel.mensajeDe(e));
        notifyListeners();
      },
    );
  }

  /// Solo en demo: avanza el 60 % de la distancia restante.
  Future<void> simularAcercamiento() async {
    if (!modoDemo) return; // con la API real mandaría una posición falsa al servidor
    final destino = alerta?.ubicacion;
    final yo = miUbicacion;
    if (destino == null || yo == null) return;
    final siguiente = ReglaGeocerca.avanzar(yo, destino, 0.6);
    try {
      await _alertas.actualizarMiUbicacion(siguiente);
      miUbicacion = siguiente;
    } catch (e) {
      mensaje = ViewModel.mensajeDe(e);
    }
    notifyListeners();
  }

  /// CR-F04: abre la ruta hacia la posición más reciente del usuario.
  Future<void> abrirEnGoogleMaps() async {
    final destino = alerta?.ubicacion;
    if (destino == null) {
      mensaje = 'Aún no hay ubicación del usuario para trazar la ruta';
    } else if (!await _enlaces.abrir(urlRuta(destino))) {
      mensaje = 'No se pudo abrir Google Maps. Revisa que esté instalado.';
    }
    if (mensaje != null) notifyListeners();
  }

  Future<void> marcarLlegada() async {
    final motivo = ReglaGeocerca.validarLlegada(miUbicacion, alerta?.ubicacion, radio);
    if (motivo != null || alerta?.estado != EstadoAlerta.enAtencion) {
      mensaje = motivo ?? 'Esta alerta ya no está en atención';
      notifyListeners();
      return;
    }
    llegando = true;
    notifyListeners();
    try {
      // El servidor valida la geocerca con la última posición que recibió, que puede ir
      // hasta un intervalo atrás del GPS: se le manda la de ahora antes de pedir la llegada.
      // Es un envío extra fuera del espaciado; el límite de la API admite 3 por ventana.
      final yo = miUbicacion;
      if (_seguimiento != null && yo != null) {
        try {
          await _alertas.actualizarMiUbicacion(yo);
        } on Object {
          // Si falla, la llegada se intenta igual con la última posición guardada.
        }
      }
      await _alertas.marcarLlegada(alertaId);
    } on FueraDeGeocercaError catch (e) {
      mensaje = '${e.mensaje}. Faltan ${Fmt.distance(e.metrosRestantes)}.';
    } catch (e) {
      mensaje = ViewModel.mensajeDe(e);
    } finally {
      llegando = false;
      notifyListeners();
    }
  }

  void consumirMensaje() => mensaje = null;

  @override
  void dispose() {
    _sub?.cancel();
    _subPosicion?.cancel();
    super.dispose();
  }
}
