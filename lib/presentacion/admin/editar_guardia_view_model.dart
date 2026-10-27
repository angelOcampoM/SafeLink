// CAPA: PRESENTACIÓN — ViewModel
// A-01 Alta de guardia · A-02 Edición de guardia
// Sin [guardiaId] es alta; con él, carga los datos y edita. Las reglas de
// nombre, correo y teléfono vienen de ReglaRegistro (dominio).
// No importa material.dart y no navega (devuelve si guardó).

import '../../datos/admin_repository.dart';
import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/view_model.dart';

class EditarGuardiaViewModel extends ViewModel {
  EditarGuardiaViewModel(this._admin, {this.guardiaId});

  final AdminRepository _admin;
  final String? guardiaId;

  /// En alta queda `Listo(null)` de inmediato.
  EstadoVista<Guardia?> estado = const Cargando();
  bool guardando = false;
  String? error;
  String? errorNombre;
  String? errorCorreo;
  String? errorTelefono;

  bool get esEdicion => guardiaId != null;

  Future<void> cargar() async {
    if (!esEdicion) {
      estado = const Listo(null);
      notifyListeners();
      return;
    }
    estado = const Cargando();
    notifyListeners();
    try {
      estado = Listo(await _admin.obtenerGuardia(guardiaId!));
    } catch (e) {
      estado = ErrorVista(ViewModel.mensajeDe(e));
    }
    notifyListeners();
  }

  Future<bool> guardar({required String nombre, required String correo, required String telefono}) async {
    errorNombre = ReglaRegistro.nombre(nombre);
    errorCorreo = ReglaRegistro.correo(correo);
    errorTelefono = ReglaRegistro.telefono(telefono);
    error = null;
    if (errorNombre != null || errorCorreo != null || errorTelefono != null) {
      notifyListeners();
      return false;
    }
    guardando = true;
    notifyListeners();
    try {
      if (esEdicion) {
        await _admin.actualizarGuardia(guardiaId!, nombre: nombre.trim(), correo: correo.trim(), telefono: telefono.trim());
      } else {
        await _admin.crearGuardia(nombre: nombre.trim(), correo: correo.trim(), telefono: telefono.trim());
      }
      return true;
    } catch (e) {
      error = ViewModel.mensajeDe(e);
      return false;
    } finally {
      guardando = false;
      notifyListeners();
    }
  }
}
