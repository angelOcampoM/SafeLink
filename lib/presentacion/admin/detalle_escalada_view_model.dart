// CAPA: PRESENTACIÓN — ViewModel
// A-04 Detalle de una alerta escalada
// Carga la alerta por id y orquesta la resolución: exige la confirmación del
// admin y la nota administrativa (ReglaAlerta) antes de llamar al repositorio.
// No importa material.dart y no navega (devuelve si resolvió).

import '../../datos/admin_repository.dart';
import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/view_model.dart';

class DetalleEscaladaViewModel extends ViewModel {
  DetalleEscaladaViewModel(this._admin, this.alertaId);

  final AdminRepository _admin;
  final String alertaId;

  EstadoVista<Alerta> estado = const Cargando();
  bool confirmoRevision = false;
  bool resolviendo = false;
  String? errorNota;
  String? mensaje;

  Alerta? get alerta => estado.datos;
  bool get puedeResolver => confirmoRevision && !resolviendo;

  void cambiarRevision(bool valor) {
    confirmoRevision = valor;
    notifyListeners();
  }

  Future<void> cargar() async {
    estado = const Cargando();
    notifyListeners();
    try {
      final historial = await _admin.obtenerHistorial(const FiltroHistorial());
      final alerta = historial.where((a) => a.id == alertaId).firstOrNull;
      estado = alerta == null ? const Vacio<Alerta>() : Listo(alerta);
    } catch (e) {
      estado = ErrorVista(ViewModel.mensajeDe(e));
    }
    notifyListeners();
  }

  Future<bool> resolver(Resolucion resolucion, {required String nota}) async {
    final a = alerta;
    if (a == null) return false;
    mensaje = null;
    if (!confirmoRevision) {
      mensaje = 'Confirma que revisaste y atendiste la alerta antes de resolver';
      notifyListeners();
      return false;
    }
    errorNota = ReglaAlerta.nota(nota);
    mensaje = ReglaAlerta.validarResolucion(a);
    if (errorNota != null || mensaje != null) {
      notifyListeners();
      return false;
    }
    resolviendo = true;
    notifyListeners();
    try {
      await _admin.resolverAlerta(a.id, resolucion, nota: nota.trim());
      mensaje = 'Alerta marcada como "${resolucion.etiqueta}"';
      return true;
    } catch (e) {
      mensaje = ViewModel.mensajeDe(e);
      return false;
    } finally {
      resolviendo = false;
      notifyListeners();
    }
  }
}
