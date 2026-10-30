// CAPA: PRESENTACIÓN — ViewModel
// A-04 Bandeja de escaladas
// Escucha la bandeja en tiempo real; el detalle y la resolución viven en
// DetalleEscaladaViewModel. No importa material.dart.

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

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
