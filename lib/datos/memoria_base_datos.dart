// CAPA: DATOS — estado compartido en memoria
// "Servidor" de la demo: lo comparten todos los repositorios `memoria_` (y el
// servicio falso de la nube) para que lo que hace un rol se vea en los otros.
// Incluye las simulaciones de tiempo real:
//   G-02 alertas nuevas cerca del guardia · U-08 respuesta del guardia (ETA)
//   U-09 confirmación del usuario · A-04 escalamiento por tiempo
// Se reinicia al cerrar la app. No hace: no valida reglas (las pide al dominio)
// ni sabe de pantallas.

import 'dart:async';
import 'dart:math';

import '../dominio/dominio.dart';
import 'datos_semilla.dart';

class MemoriaBaseDatos {
  MemoriaBaseDatos({
    this.config = Configuracion.porDefecto,
    DateTime Function()? reloj,
    Random? azar,
    this.latencia = const Duration(milliseconds: 450),
  })  : reloj = reloj ?? DateTime.now,
        _azar = azar ?? Random() {
    final semilla = DatosSemilla(this.reloj()).construir();
    for (final u in semilla.usuarios) {
      usuarios[u.id] = u;
      contrasenas[u.id] = DatosSemilla.contrasena;
    }
    for (final p in semilla.perfiles) {
      perfiles[p.usuarioId] = p;
    }
    alertas.addAll(semilla.alertas);
  }

  final Configuracion config;
  final DateTime Function() reloj;
  final Random _azar;

  /// Latencia simulada, para ver estados de carga en la UI. Cero en pruebas.
  Duration latencia;

  final usuarios = <String, Usuario>{};
  final contrasenas = <String, String>{};
  final perfiles = <String, PerfilGuardia>{};
  final alertas = <Alerta>[];

  /// Alertas que cada guardia decidió ignorar (G-02).
  final ignoradas = <String, Set<String>>{};

  String? usuarioActualId;

  var _secuencia = 0;
  String nuevoId(String prefijo) => '$prefijo-n${++_secuencia}';

  final _cambios = StreamController<void>.broadcast();

  /// Emite el valor actual y lo vuelve a emitir cada vez que cambian datos.
  Stream<T> observar<T>(T Function() leer) async* {
    yield leer();
    await for (final _ in _cambios.stream) {
      yield leer();
    }
  }

  void avisar() {
    if (!_cambios.isClosed) _cambios.add(null);
  }

  Future<void> esperar() => latencia == Duration.zero ? Future<void>.value() : Future<void>.delayed(latencia);

  Usuario get yo {
    final id = usuarioActualId;
    if (id == null) throw const SinSesionError();
    return usuarios[id]!;
  }

  Alerta alertaPorId(String id) {
    final a = alertas.where((a) => a.id == id).firstOrNull;
    if (a == null) throw const NoEncontradoError('La alerta ya no existe');
    return a;
  }

  void reemplazarAlerta(Alerta actualizada) {
    final i = alertas.indexWhere((a) => a.id == actualizada.id);
    alertas[i] = actualizada;
    avisar();
  }

  Guardia guardiaPorId(String id) {
    final u = usuarios[id];
    final p = perfiles[id];
    if (u == null || p == null) throw const NoEncontradoError('No encontramos a ese guardia');
    return Guardia(usuario: u, perfil: p);
  }

  // ── Simulaciones de tiempo real ───────────────────────────────────
  final _timers = <String, Timer>{};
  Timer? _timerEscalamiento;
  Timer? _timerNuevaAlerta;

  /// En qué momento observamos cada alerta en su estado actual (A-04).
  final _desde = <String, DateTime>{};

  /// U-08: un guardia acepta, se acerca (baja la ETA) y llega.
  void simularRespuestaGuardia(String alertaId) {
    _timers[alertaId]?.cancel();
    var ticks = 0;
    _timers[alertaId] = Timer.periodic(const Duration(seconds: 2), (t) {
      ticks++;
      final a = alertas.where((x) => x.id == alertaId).firstOrNull;
      if (a == null) return t.cancel();
      if (a.estado == EstadoAlerta.buscando && ticks >= 2) {
        final g = guardiaPorId('grd-1');
        reemplazarAlerta(a.copyWith(
          estado: EstadoAlerta.enAtencion,
          guardiaId: g.usuario.id,
          nombreGuardia: g.usuario.nombre,
          aceptadaEn: reloj(),
          etaSegundos: 300,
        ),);
      } else if (a.estado == EstadoAlerta.enAtencion) {
        final eta = (a.etaSegundos ?? 0) - 40;
        if (eta <= 0) {
          reemplazarAlerta(a.copyWith(estado: EstadoAlerta.guardiaEnLugar, llegadaEn: reloj(), etaSegundos: 0));
          t.cancel();
        } else {
          reemplazarAlerta(a.copyWith(etaSegundos: eta));
        }
      } else if (!a.estado.activa) {
        t.cancel();
      }
    });
  }

  /// U-09: el usuario confirma la atención unos segundos después de "Llegué".
  void simularConfirmacionUsuario(String alertaId) {
    _timers[alertaId]?.cancel();
    _timers[alertaId] = Timer(const Duration(seconds: 8), () {
      final a = alertas.where((x) => x.id == alertaId).firstOrNull;
      if (a != null && a.estado == EstadoAlerta.guardiaEnLugar) {
        reemplazarAlerta(a.copyWith(estado: EstadoAlerta.cerrada, cerradaEn: reloj()));
      }
    });
  }

  /// Arranca las simulaciones de fondo (las llama main.dart, nunca las pruebas).
  void iniciarSimulaciones() {
    _timerEscalamiento ??= Timer.periodic(const Duration(seconds: 5), (_) => revisarEscalamientos());
    _programarNuevaAlerta();
  }

  void detenerSimulaciones() {
    _timerEscalamiento?.cancel();
    _timerEscalamiento = null;
    _timerNuevaAlerta?.cancel();
    _timerNuevaAlerta = null;
  }

  /// A-04: escala lo que lleva demasiado tiempo sin respuesta o sin confirmación.
  void revisarEscalamientos() {
    final ahora = reloj();
    final limite = Duration(seconds: config.segundosEscalamientoDemo);
    var cambio = false;
    for (var i = 0; i < alertas.length; i++) {
      final a = alertas[i];
      final desde = _desde.putIfAbsent('${a.id}:${a.estado.name}', () => ahora);
      final razon = ReglaAlerta.razonParaEscalar(a, desde: desde, ahora: ahora, limite: limite);
      if (razon != null) {
        alertas[i] = a.copyWith(estado: EstadoAlerta.escalada, razonEscalamiento: razon);
        cambio = true;
      }
    }
    if (cambio) avisar();
  }

  void _programarNuevaAlerta() {
    _timerNuevaAlerta?.cancel();
    final min = config.segundosNuevaAlertaMin;
    final rango = max(1, config.segundosNuevaAlertaMax - min);
    _timerNuevaAlerta = Timer(Duration(seconds: min + _azar.nextInt(rango)), () {
      simularNuevaAlerta();
      _programarNuevaAlerta();
    });
  }

  /// G-02: aparece una alerta `buscando` cerca del guardia en sesión.
  /// Devuelve la alerta creada, o `null` si no hay un guardia disponible.
  Alerta? simularNuevaAlerta() {
    final id = usuarioActualId;
    final yoUsuario = id == null ? null : usuarios[id];
    if (yoUsuario == null || yoUsuario.rol != RolUsuario.guardia) return null;
    final g = guardiaPorId(yoUsuario.id);
    final ahora = reloj();
    if (!g.disponibleA(ahora)) return null;

    final base = g.perfil.ultimaUbicacion ?? g.perfil.centroCobertura!;
    // Hasta ~1.5 km del guardia (0.0135° ≈ 1.5 km), siempre dentro de su radio.
    final alcance = min(0.0135, g.perfil.radioCoberturaMetros! / 111000 * 0.5);
    final punto = PuntoGeo(
      base.lat + (_azar.nextDouble() * 2 - 1) * alcance,
      base.lng + (_azar.nextDouble() * 2 - 1) * alcance,
    );
    if (!ReglaGeocerca.dentroDeCobertura(g.perfil.centroCobertura!, g.perfil.radioCoberturaMetros!, punto)) {
      return null;
    }
    final candidatos = usuarios.values
        .where((u) => u.rol == RolUsuario.usuarioProtegido && u.id != 'usr-1' && !u.bloqueadoEn(ahora))
        .toList();
    final u = candidatos[_azar.nextInt(candidatos.length)];
    final metodo = _azar.nextInt(5) == 0 ? MetodoDisparo.agitacion : MetodoDisparo.values[_azar.nextInt(2)];
    final sinFoto = _azar.nextInt(6) == 0;
    final alertaId = nuevoId('alt');
    final alerta = Alerta(
      id: alertaId,
      usuarioId: u.id,
      nombreUsuario: u.nombre,
      telefonoUsuario: u.telefono,
      estado: EstadoAlerta.buscando,
      metodo: metodo,
      disparadaEn: ahora,
      ubicacion: punto,
      rumbo: _azar.nextInt(360),
      fotoUrl: sinFoto ? null : 'https://picsum.photos/seed/$alertaId/640/420',
      evidenciaIncompleta: sinFoto,
    );
    alertas.add(alerta);
    avisar();
    return alerta;
  }

  void dispose() {
    detenerSimulaciones();
    for (final t in _timers.values) {
      t.cancel();
    }
    _cambios.close();
  }
}
