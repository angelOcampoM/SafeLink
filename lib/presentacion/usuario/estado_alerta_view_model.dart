// CAPA: PRESENTACIÓN — ViewModel
// U-07 Ubicación en tiempo real · U-08 Guardia asignado y ETA · U-09 Confirmación
// Escucha la alerta activa (Observer sobre el Stream del repositorio), guarda
// el EstadoVista y pregunta al dominio si el usuario ya puede confirmar.
// No importa material.dart y no navega (emite `irAInicio`).

import 'dart:async';

import '../../datos/alerta_usuario_repository.dart';
import '../../dominio/alerta.dart';
import '../../dominio/regla_alerta.dart';
import '../comun/estado_vista.dart';
import '../comun/view_model.dart';

class EstadoAlertaViewModel extends ViewModel {
  EstadoAlertaViewModel(this._alertas);
  final AlertaUsuarioRepository _alertas;

  EstadoVista<Alerta> estado = const Cargando();
  bool confirmando = false;
  String? mensaje;
  bool irAInicio = false;

  StreamSubscription<Alerta?>? _sub;

  Alerta? get alerta => estado.datos;
  bool get puedeConfirmar => alerta != null && ReglaAlerta.puedeConfirmarUsuario(alerta!) && !confirmando;

  void iniciar() {
    _sub?.cancel();
    estado = const Cargando();
    notifyListeners();
    try {
      _sub = _alertas.escucharAlertaActiva().listen(
        (a) {
          estado = a == null ? const Vacio() : Listo(a);
          notifyListeners();
        },
        onError: (Object e) {
          estado = ErrorVista(ViewModel.mensajeDe(e));
          notifyListeners();
        },
      );
    } catch (e) {
      estado = ErrorVista(ViewModel.mensajeDe(e));
      notifyListeners();
    }
  }

  void reintentar() => iniciar();

  Future<void> confirmar() async {
    final a = alerta;
    if (a == null) return;
    final motivo = ReglaAlerta.validarConfirmacion(a);
    if (motivo != null) {
      mensaje = motivo;
      notifyListeners();
      return;
    }
    confirmando = true;
    notifyListeners();
    try {
      await _alertas.confirmarAtencion(a.id);
      mensaje = 'Gracias. Tu alerta quedó cerrada.';
      irAInicio = true;
    } catch (e) {
      mensaje = ViewModel.mensajeDe(e);
    } finally {
      confirmando = false;
      notifyListeners();
    }
  }

  void consumirEventos() {
    mensaje = null;
    irAInicio = false;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
