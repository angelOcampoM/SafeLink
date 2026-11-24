// CAPA: PRESENTACIÓN — ViewModel
// G-04 Detalle de alerta · G-05 Aceptación
// Carga la alerta y el perfil, calcula la distancia con el dominio y orquesta
// la aceptación: primero pregunta a ReglaAlerta, luego al repositorio.
// No importa material.dart y no navega (devuelve el resultado).

import '../../datos/alerta_guardia_repository.dart';
import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/view_model.dart';

typedef DetalleAlerta = ({Alerta alerta, Guardia guardia});

class DetalleAlertaViewModel extends ViewModel {
  DetalleAlertaViewModel(this._alertas, this.alertaId, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final AlertaGuardiaRepository _alertas;
  final String alertaId;
  final DateTime Function() _reloj;

  EstadoVista<DetalleAlerta> estado = const Cargando();
  bool aceptando = false;
  String? error;

  /// `true` cuando otro guardia ganó la alerta: la View regresa al listado.
  bool alertaTomada = false;

  DateTime get ahora => _reloj();
  Alerta? get alerta => estado.datos?.alerta;
  bool get puedeAceptar => alerta != null && ReglaAlerta.validarAceptacion(alerta!) == null && !aceptando;

  double? get distancia {
    final d = estado.datos;
    final aqui = d?.guardia.perfil.ultimaUbicacion;
    if (d == null || aqui == null || d.alerta.ubicacion == null) return null;
    return ReglaGeocerca.distanciaMetros(aqui, d.alerta.ubicacion!);
  }

  Future<void> cargar() async {
    estado = const Cargando();
    notifyListeners();
    try {
      final r = await Future.wait<Object>([_alertas.obtenerAlerta(alertaId), _alertas.obtenerMiPerfil()]);
      estado = Listo((alerta: r[0] as Alerta, guardia: r[1] as Guardia));
    } catch (e) {
      estado = ErrorVista(ViewModel.mensajeDe(e));
    }
    notifyListeners();
  }

  /// Devuelve `true` si la alerta quedó asignada a este guardia.
  Future<bool> aceptar() async {
    final a = alerta;
    if (a == null) return false;
    error = ReglaAlerta.validarAceptacion(a);
    alertaTomada = error != null;
    if (error != null) {
      notifyListeners();
      return false;
    }
    aceptando = true;
    notifyListeners();
    try {
      await _alertas.aceptarAlerta(a.id);
      return true;
    } on AlertaTomadaError catch (e) {
      error = e.mensaje;
      alertaTomada = true;
      return false;
    } catch (e) {
      error = ViewModel.mensajeDe(e);
      return false;
    } finally {
      aceptando = false;
      notifyListeners();
    }
  }
}
