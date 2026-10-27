// CAPA: PRESENTACIÓN — ViewModel
// G-06 Ruta hacia el usuario · G-07 Registro de llegada · Esperando confirmación
// Escucha la alerta asignada, guarda la ubicación del guardia y pregunta a
// ReglaGeocerca si "Llegué" está permitido. No importa material.dart.
//
// TODO(G-06): leer el GPS real cada `segundosActualizacionUbicacion` y abrir
// Google Maps con url_launcher (https://www.google.com/maps/dir/?api=1&destination=lat,lng).

import 'dart:async';

import '../../datos/alerta_guardia_repository.dart';
import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/formato.dart';
import '../comun/view_model.dart';

class NavegacionViewModel extends ViewModel {
  NavegacionViewModel(this._alertas, this.alertaId, {required this.config});

  final AlertaGuardiaRepository _alertas;
  final String alertaId;
  final Configuracion config;

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
    super.dispose();
  }
}
