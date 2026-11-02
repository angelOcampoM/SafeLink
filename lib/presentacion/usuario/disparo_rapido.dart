// CAPA: PRESENTACIÓN — coordinador del disparo con la pantalla bloqueada (U-05)
// Vive con la sesión, no con la pantalla de inicio: el usuario puede tener el
// teléfono bloqueado. Escucha las pulsaciones del servicio, le pregunta al
// dominio si fueron un doble clic y, si lo fueron, vibra y registra la alerta
// con la misma evidencia que el botón (U-06).
// No importa material.dart, no pinta y no navega.

import 'dart:async';

import '../../datos/alerta_usuario_repository.dart';
import '../../datos/servicio_disparo_rapido.dart';
import '../../dominio/enums.dart';
import '../../dominio/regla_doble_clic.dart';
import '../comun/view_model.dart';
import 'captura_evidencia.dart';

class DisparoRapido extends ViewModel {
  DisparoRapido({
    required ServicioDisparoRapido servicio,
    required Vibrador vibrador,
    required AlertaUsuarioRepository alertas,
    required CapturaEvidencia evidencia,
    ReglaDobleClic? regla,
    DateTime Function()? reloj,
  })  : _servicio = servicio,
        _vibrador = vibrador,
        _alertas = alertas,
        _evidencia = evidencia,
        _regla = regla ?? ReglaDobleClic(),
        _reloj = reloj ?? DateTime.now;

  final ServicioDisparoRapido _servicio;
  final Vibrador _vibrador;
  final AlertaUsuarioRepository _alertas;
  final CapturaEvidencia _evidencia;
  final ReglaDobleClic _regla;
  final DateTime Function() _reloj;

  StreamSubscription<DateTime>? _sub;

  /// Mensaje de un solo uso para un SnackBar.
  String? mensaje;

  bool get activo => _servicio.enEjecucion;

  /// La notificación permanente del servicio en segundo plano.
  bool get notificacionVisible => _servicio.notificacionVisible;

  /// Enciende el servicio y empieza a escuchar el botón.
  Future<void> activar() async {
    if (activo) return;
    await _servicio.iniciar();
    _regla.reiniciar();
    _sub ??= _servicio.pulsaciones.listen(_alPulsar);
    notifyListeners();
  }

  /// Apaga el servicio: ya no llegan pulsaciones ni se registran alertas.
  Future<void> desactivar() async {
    await _servicio.detener();
    _regla.reiniciar();
    await _sub?.cancel();
    _sub = null;
    notifyListeners();
  }

  Future<void> _alPulsar(DateTime cuando) async {
    if (!_regla.registrar(cuando)) return; // una sola pulsación no dispara
    await _vibrador.vibrar(); // confirma que salió, sin mirar la pantalla
    try {
      final e = await _evidencia.capturar();
      await _alertas.crearAlerta(
        metodo: MetodoDisparo.dobleClicVolumen,
        disparadaEn: _reloj().toUtc(),
        rutaFoto: e.foto,
        ubicacion: e.ubicacion,
        rumbo: e.rumbo,
      );
      mensaje = 'Alerta enviada por doble clic de volumen';
    } catch (err) {
      mensaje = ViewModel.mensajeDe(err);
    }
    notifyListeners();
  }

  void consumirMensaje() => mensaje = null;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
