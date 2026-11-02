// CAPA: PRESENTACIÓN — ViewModel
// A-03 Turnos y radios de cobertura
// Guarda el turno, la zona y el radio elegidos, pregunta a ReglaTurno y
// ReglaGeocerca si son válidos y pide el guardado al repositorio.
// No importa material.dart.

import '../../datos/admin_repository.dart';
import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/view_model.dart';

class CoberturaGuardiaViewModel extends ViewModel {
  CoberturaGuardiaViewModel(this._admin, this.guardiaId, {required this.config, required this.centroPorDefecto});

  final AdminRepository _admin;
  final String guardiaId;
  final Configuracion config;
  final PuntoGeo centroPorDefecto;

  EstadoVista<Guardia> estado = const Cargando();
  String inicioTurno = '08:00';
  String finTurno = '16:00';
  String zona = '';
  int radioMetros = 3000;
  PuntoGeo? _centro;
  bool guardando = false;
  String? error;
  String? errorZona;

  int get radioMin => config.radioCoberturaMinMetros;
  int get radioMax => config.radioCoberturaMaxMetros;
  PuntoGeo get centro => _centro ?? centroPorDefecto;

  /// Para el MapPlaceholder: el radio máximo ocupa casi medio mapa.
  double get radioFraccion => 0.45 * radioMetros / radioMax;

  int get duracionMinutos => ReglaTurno.duracionMinutos(inicioTurno, finTurno);
  bool get cruzaMedianoche => ReglaTurno.aMinutos(finTurno) <= ReglaTurno.aMinutos(inicioTurno);

  Future<void> cargar() async {
    estado = const Cargando();
    notifyListeners();
    try {
      final g = await _admin.obtenerGuardia(guardiaId);
      inicioTurno = g.perfil.inicioTurno;
      finTurno = g.perfil.finTurno;
      zona = g.perfil.zona ?? '';
      radioMetros = (g.perfil.radioCoberturaMetros ?? 3000).clamp(radioMin, radioMax);
      _centro = g.perfil.centroCobertura;
      estado = Listo(g);
    } catch (e) {
      estado = ErrorVista(ViewModel.mensajeDe(e));
    }
    notifyListeners();
  }

  void cambiarInicio(int hora, int minuto) {
    inicioTurno = ReglaTurno.deHoraMinuto(hora, minuto);
    notifyListeners();
  }

  void cambiarFin(int hora, int minuto) {
    finTurno = ReglaTurno.deHoraMinuto(hora, minuto);
    notifyListeners();
  }

  /// El Slider entrega double; se redondea a múltiplos de 100 m.
  void cambiarRadio(double metros) {
    radioMetros = ((metros / 100).round() * 100).clamp(radioMin, radioMax);
    notifyListeners();
  }

  void cambiarZona(String valor) {
    zona = valor;
    notifyListeners();
  }

  Future<bool> guardar() async {
    errorZona = ReglaGeocerca.validarZona(zona);
    error = ReglaTurno.validar(inicioTurno, finTurno) ??
        ReglaGeocerca.validarRadio(radioMetros, minimo: radioMin, maximo: radioMax);
    if (error != null || errorZona != null) {
      notifyListeners();
      return false;
    }
    guardando = true;
    notifyListeners();
    try {
      final g = await _admin.actualizarCobertura(
        guardiaId,
        inicioTurno: inicioTurno,
        finTurno: finTurno,
        centro: centro,
        radioMetros: radioMetros,
        zona: zona,
      );
      estado = Listo(g);
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
