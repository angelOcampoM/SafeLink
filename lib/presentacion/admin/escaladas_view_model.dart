// CAPA: PRESENTACIÓN — ViewModel
// A-04 Bandeja de escaladas · A-08 Falsas alarmas
// Escucha la bandeja en tiempo real y pide la resolución al repositorio (que
// aplica ReglaAlerta.aplicarFalsaAlarma). No importa material.dart.

import 'dart:async';

import '../../datos/admin_repository.dart';
import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/view_model.dart';

class EscaladasViewModel extends ViewModel {
  EscaladasViewModel(this._admin, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final AdminRepository _admin;
  final DateTime Function() _reloj;

  EstadoVista<List<Alerta>> estado = const Cargando();
  String? resolviendo;
  String? mensaje;

  StreamSubscription<List<Alerta>>? _sub;

  DateTime get ahora => _reloj();

  void iniciar() {
    _sub?.cancel();
    estado = const Cargando();
    notifyListeners();
    _sub = _admin.escucharEscaladas().listen(
      (lista) {
        estado = EstadoVista.deLista(lista);
        notifyListeners();
      },
      onError: (Object e) {
        estado = ErrorVista(ViewModel.mensajeDe(e));
        notifyListeners();
      },
    );
  }

  Future<void> recargar() async => iniciar();

  Future<bool> resolver(Alerta a, Resolucion resolucion) async {
    final motivo = ReglaAlerta.validarResolucion(a);
    if (motivo != null) {
      mensaje = motivo;
      notifyListeners();
      return false;
    }
    resolviendo = a.id;
    notifyListeners();
    try {
      await _admin.resolverAlerta(a.id, resolucion);
      mensaje = 'Alerta marcada como "${resolucion.etiqueta}"';
      return true;
    } catch (e) {
      mensaje = ViewModel.mensajeDe(e);
      return false;
    } finally {
      resolviendo = null;
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
