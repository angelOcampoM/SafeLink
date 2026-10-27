// CAPA: PRESENTACIÓN — ViewModel
// G-02 Recepción (banner "Alerta entrante") · G-03 Listado por cercanía y prioridad · Fuera de turno
// Carga el perfil, escucha las alertas disponibles (Observer sobre el Stream) y
// detecta las que llegan nuevas para avisar. El orden ya viene del dominio.
// No importa material.dart y no navega.
//
// TODO(G-02): pantalla completa de "Alerta entrante" al recibir push FCM.

import 'dart:async';

import '../../datos/alerta_guardia_repository.dart';
import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/view_model.dart';
import '../sesion/sesion_view_model.dart';

class ListadoAlertasViewModel extends ViewModel {
  ListadoAlertasViewModel(this._alertas, this._sesion, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final AlertaGuardiaRepository _alertas;
  final SesionViewModel _sesion;
  final DateTime Function() _reloj;

  EstadoVista<Guardia> perfil = const Cargando();
  EstadoVista<List<AlertaPriorizada>> estado = const Cargando();

  /// La alerta nueva de mayor prioridad que llegó desde la última vez (G-02).
  AlertaPriorizada? entrante;

  StreamSubscription<List<AlertaPriorizada>>? _sub;
  Set<String>? _vistas;

  DateTime get ahora => _reloj();
  Guardia? get guardia => perfil.datos;

  /// Por qué no recibe alertas, o `null` si está disponible.
  String? get motivoNoDisponible {
    final g = guardia;
    if (g == null) return null;
    if (!g.perfil.tieneCobertura) return 'Aún no tienes una zona asignada. Pide al administrador tu radio de cobertura.';
    if (!g.disponibleA(ahora)) {
      return 'Tu turno es de ${g.perfil.inicioTurno} a ${g.perfil.finTurno}. No recibirás alertas hasta entonces.';
    }
    return null;
  }

  Future<void> iniciar() async {
    if (perfil is! Listo) {
      perfil = const Cargando();
      notifyListeners();
    }
    try {
      perfil = Listo(await _alertas.obtenerMiPerfil());
    } catch (e) {
      perfil = ErrorVista(ViewModel.mensajeDe(e));
      notifyListeners();
      return;
    }
    notifyListeners();
    if (motivoNoDisponible == null) _escuchar();
  }

  Future<void> recargar() => iniciar();

  void _escuchar() {
    _sub?.cancel();
    _sub = _alertas.escucharAlertasDisponibles().listen(
      (lista) {
        final ids = {for (final p in lista) p.alerta.id};
        final previas = _vistas;
        if (previas != null) {
          final nuevas = lista.where((p) => !previas.contains(p.alerta.id));
          if (nuevas.isNotEmpty) entrante = nuevas.first;
        }
        if (entrante != null && !ids.contains(entrante!.alerta.id)) entrante = null;
        _vistas = {...?previas, ...ids};
        estado = EstadoVista.deLista(lista);
        notifyListeners();
      },
      onError: (Object e) {
        estado = ErrorVista(ViewModel.mensajeDe(e));
        notifyListeners();
      },
    );
  }

  void descartarEntrante() {
    entrante = null;
    notifyListeners();
  }

  Future<void> cerrarSesion() => _sesion.cerrarSesion();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
