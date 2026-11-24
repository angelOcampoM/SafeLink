// CAPA: PRESENTACIÓN — ViewModel
// G-02 Recepción (banner "Alerta entrante") · G-03 Listado por cercanía y prioridad, con filtros · Fuera de turno
// Carga el perfil, escucha las alertas disponibles (Observer sobre el Stream),
// detecta las que llegan nuevas para avisar y aplica los filtros elegidos.
// El orden por prioridad ya viene del dominio; el banner ignora los filtros.
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

  /// Todas las disponibles, SIN filtrar (Vacío = no hay ninguna en la zona).
  EstadoVista<List<AlertaPriorizada>> estado = const Cargando();

  FiltroAlertasDisponibles filtro = const FiltroAlertasDisponibles();

  /// La alerta nueva de mayor prioridad que llegó desde la última vez (G-02).
  AlertaPriorizada? entrante;

  StreamSubscription<List<AlertaPriorizada>>? _sub;
  Set<String>? _vistas;

  DateTime get ahora => _reloj();
  Guardia? get guardia => perfil.datos;

  // ── Filtros (G-03) ──
  /// Lo que se ve en la lista: las disponibles con el filtro y el orden aplicados.
  List<AlertaPriorizada> get filtradas => filtro.aplicar(estado.datos ?? const []);
  int get total => estado.datos?.length ?? 0;
  bool get hayFiltros => filtro.hayFiltros;

  void cambiarMetodo(MetodoDisparo? metodo) => _filtrar(
        FiltroAlertasDisponibles(metodo: metodo, distanciaMaxMetros: filtro.distanciaMaxMetros, evidencia: filtro.evidencia, orden: filtro.orden),
      );

  void cambiarDistancia(int? metros) => _filtrar(
        FiltroAlertasDisponibles(metodo: filtro.metodo, distanciaMaxMetros: metros, evidencia: filtro.evidencia, orden: filtro.orden),
      );

  void cambiarEvidencia(FiltroEvidencia evidencia) => _filtrar(
        FiltroAlertasDisponibles(metodo: filtro.metodo, distanciaMaxMetros: filtro.distanciaMaxMetros, evidencia: evidencia, orden: filtro.orden),
      );

  void cambiarOrden(OrdenAlertasDisponibles orden) => _filtrar(
        FiltroAlertasDisponibles(metodo: filtro.metodo, distanciaMaxMetros: filtro.distanciaMaxMetros, evidencia: filtro.evidencia, orden: orden),
      );

  void limpiarFiltros() => _filtrar(const FiltroAlertasDisponibles());

  void _filtrar(FiltroAlertasDisponibles nuevo) {
    filtro = nuevo;
    notifyListeners();
  }

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
