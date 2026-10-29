// CAPA: PRESENTACIÓN — ViewModel
// G-03 Dashboard de Inicio del guardia: turno, alertas disponibles, mis métricas por periodo,
// alertas por hora y última alerta atendida. Cada bloque tiene su propio EstadoVista.
// Todo se calcula con lo que ya da el contrato (perfil, historial y el stream de disponibles)
// usando FiltroHistorial, ReglaMetricas y ReglaTiempoTurno. Con 0 alertas todo vale 0.
// No importa material.dart y no navega.
//
// Pendiente: "Continuar atención" (el contrato no permite saber si hay una alerta en curso).

import 'dart:async';

import '../../datos/alerta_guardia_repository.dart';
import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/view_model.dart';
import '../sesion/sesion_view_model.dart';

enum EstadoTurno {
  enTurno('En turno'),
  fueraDeTurno('Fuera de turno'),
  sinZona('Sin zona');

  const EstadoTurno(this.etiqueta);
  final String etiqueta;
}

enum PeriodoInicio {
  hoy('Hoy'),
  dias7('7 días'),
  dias30('30 días');

  const PeriodoInicio(this.etiqueta);
  final String etiqueta;

  /// Inicio del periodo: medianoche de hoy, o N días antes de [ahora].
  DateTime desde(DateTime ahora) => switch (this) {
        PeriodoInicio.hoy => DateTime(ahora.year, ahora.month, ahora.day),
        PeriodoInicio.dias7 => ahora.subtract(const Duration(days: 7)),
        PeriodoInicio.dias30 => ahora.subtract(const Duration(days: 30)),
      };
}

/// Métricas personales de un periodo.
typedef MetricasInicio = ({MetricasGuardia guardia, double tasaCierreConfirmado, List<int> alertasPorHora});

class InicioGuardiaViewModel extends ViewModel {
  InicioGuardiaViewModel(this._alertas, this._sesion, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final AlertaGuardiaRepository _alertas;
  final SesionViewModel _sesion;
  final DateTime Function() _reloj;

  EstadoVista<Guardia> perfil = const Cargando();

  /// Mis métricas del periodo elegido (Listo con ceros si no hubo alertas).
  EstadoVista<MetricasInicio> metricas = const Cargando();

  /// Última alerta atendida (Vacío si aún no atiende ninguna).
  EstadoVista<Alerta> ultima = const Cargando();

  /// Alertas disponibles ahora; solo se escuchan si el guardia está disponible.
  EstadoVista<List<AlertaPriorizada>> disponibles = const Cargando();

  PeriodoInicio periodo = PeriodoInicio.hoy;

  List<Alerta>? _historial;
  StreamSubscription<List<AlertaPriorizada>>? _sub;

  DateTime get ahora => _reloj();

  // ── Turno ──
  /// `null` mientras no hay perfil.
  EstadoTurno? get estadoTurno {
    final g = perfil.datos;
    if (g == null) return null;
    if (!g.perfil.tieneCobertura) return EstadoTurno.sinZona;
    return g.disponibleA(ahora) ? EstadoTurno.enTurno : EstadoTurno.fueraDeTurno;
  }

  /// Por qué no recibe alertas, o `null` si está disponible.
  String? get motivoNoDisponible {
    final g = perfil.datos;
    return switch (estadoTurno) {
      EstadoTurno.sinZona => 'Aún no tienes una zona asignada. Pide al administrador tu radio de cobertura.',
      EstadoTurno.fueraDeTurno =>
        'Tu turno es de ${g!.perfil.inicioTurno} a ${g.perfil.finTurno}. No recibirás alertas hasta entonces.',
      _ => null,
    };
  }

  /// Minutos para que termine el turno (solo en turno).
  int? get minutosRestantesTurno {
    final p = perfil.datos?.perfil;
    if (p == null || estadoTurno != EstadoTurno.enTurno) return null;
    return ReglaTiempoTurno.minutosRestantes(p.inicioTurno, p.finTurno, ahora);
  }

  /// Minutos para que empiece el turno (solo fuera de turno).
  int? get minutosParaIniciarTurno {
    final p = perfil.datos?.perfil;
    if (p == null || estadoTurno != EstadoTurno.fueraDeTurno) return null;
    return ReglaTiempoTurno.minutosParaIniciar(p.inicioTurno, p.finTurno, ahora);
  }

  // ── Disponibles ──
  int get totalDisponibles => disponibles.datos?.length ?? 0;
  int get urgentesDisponibles => disponibles.datos?.where((p) => p.alerta.esUrgente).length ?? 0;

  // ── Carga ──
  Future<void> cargar() async {
    if (perfil is! Listo) {
      perfil = const Cargando();
      notifyListeners();
    }
    await Future.wait([_cargarPerfil(), _cargarHistorial()]);
    if (desechado) return;
    _calcularMetricas();
    if (estadoTurno == EstadoTurno.enTurno) {
      _escuchar();
    } else {
      _sub?.cancel();
      _sub = null;
    }
    notifyListeners();
  }

  Future<void> _cargarPerfil() async {
    try {
      perfil = Listo(await _alertas.obtenerMiPerfil());
    } catch (e) {
      perfil = ErrorVista(ViewModel.mensajeDe(e));
    }
  }

  Future<void> _cargarHistorial() async {
    try {
      _historial = await _alertas.obtenerMiHistorial();
      final h = _historial!;
      ultima = h.isEmpty ? const Vacio() : Listo(const FiltroHistorial().aplicar(h).first);
    } catch (e) {
      _historial = null;
      final mensaje = ViewModel.mensajeDe(e);
      metricas = ErrorVista(mensaje);
      ultima = ErrorVista(mensaje);
    }
  }

  void _calcularMetricas() {
    final h = _historial;
    final g = perfil.datos;
    if (h == null) return;
    final delPeriodo = FiltroHistorial(desde: periodo.desde(ahora)).aplicar(h);
    final generales = ReglaMetricas.generales(delPeriodo);
    final MetricasInicio m = (
      guardia: ReglaMetricas.deGuardia(g?.usuario.id ?? '', delPeriodo),
      tasaCierreConfirmado: generales.tasaCierreConfirmado,
      alertasPorHora: generales.alertasPorHora,
    );
    metricas = Listo(m);
  }

  void _escuchar() {
    _sub?.cancel();
    _sub = _alertas.escucharAlertasDisponibles().listen(
      (lista) {
        disponibles = EstadoVista.deLista(lista);
        notifyListeners();
      },
      onError: (Object e) {
        disponibles = ErrorVista(ViewModel.mensajeDe(e));
        notifyListeners();
      },
    );
  }

  void cambiarPeriodo(PeriodoInicio nuevo) {
    if (nuevo == periodo) return;
    periodo = nuevo;
    _calcularMetricas();
    notifyListeners();
  }

  Future<void> cerrarSesion() => _sesion.cerrarSesion();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
