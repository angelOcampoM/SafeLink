// CAPA: PRESENTACIÓN — ViewModel
// U-03 Toque simple · U-04 Mantener presionado · U-05 Doble clic de volumen · U-06 Evidencia
// Guarda el estado del botón (cuenta regresiva, manteniendo, enviando) y
// delega en una estrategia por método de disparo. Al enviar, pide al dominio
// si el usuario puede y al repositorio que cree la alerta.
// No importa material.dart: no calcula la zona de descarte en pantalla (la View
// le dice si el dedo está encima) ni navega (emite `irAMiAlerta`).
//
// U-06: la evidencia (foto, coordenada y rumbo) se captura sola en el instante
// del disparo, a través de los contratos Camara/Ubicacion/Brujula. Hoy los
// cumplen implementaciones simuladas; mañana, los plugins reales.


import '../../datos/alerta_usuario_repository.dart';
import '../../datos/sensores.dart';
import '../../dominio/dominio.dart';
import '../comun/view_model.dart';
import '../sesion/sesion_view_model.dart';
import 'estrategias_disparo.dart';

class InicioViewModel extends ViewModel implements ControlDisparo {
  InicioViewModel(
    this._alertas,
    this._sesion, {
    required this.config,
    required Camara camara,
    required Ubicacion ubicacion,
    required Brujula brujula,
    DateTime Function()? reloj,
    Duration intervaloCuenta = const Duration(seconds: 1),
  })  : _camara = camara,
        _ubicacion = ubicacion,
        _brujula = brujula,
        _reloj = reloj ?? DateTime.now,
        toque = ToqueConCuentaRegresiva(segundos: config.segundosCuentaRegresiva, intervalo: intervaloCuenta);

  final AlertaUsuarioRepository _alertas;
  final SesionViewModel _sesion;
  final Configuracion config;
  final Camara _camara;
  final Ubicacion _ubicacion;
  final Brujula _brujula;
  final DateTime Function() _reloj;

  // Estrategias intercambiables (Strategy).
  final ToqueConCuentaRegresiva toque;
  final mantener = MantenerConDescarte();
  final dobleClic = DobleClicVolumen();

  bool enviando = false;

  /// Mensaje de un solo uso para un SnackBar.
  String? mensaje;

  /// Evento de un solo uso: la alerta se creó y hay que ir a "Mi alerta".
  bool irAMiAlerta = false;

  String get primerNombre => _sesion.usuario?.primerNombre ?? '';
  bool get dobleClicVolumenActivo => _sesion.usuario?.dobleClicVolumenActivo ?? false;
  int? get cuentaRegresiva => toque.restante;
  bool get manteniendo => mantener.manteniendo;
  bool get sobreDescarte => mantener.sobreDescarte;
  bool get botonHabilitado => !enviando && !toque.activa;

  // ── Intenciones de la View ──
  void tocar() {
    if (botonHabilitado) toque.iniciar(this);
  }

  void cancelarCuenta() {
    toque.cancelar();
    notifyListeners();
  }

  void empezarMantener() {
    if (botonHabilitado) mantener.iniciar(this);
  }

  void moverMantener({required bool sobreDescarte}) => mantener.mover(sobreDescarte: sobreDescarte);

  void soltarMantener() => mantener.soltar();

  /// Solo en demo: simula que el servicio detectó el doble clic de volumen.
  void simularDobleClic() {
    if (dobleClicVolumenActivo && botonHabilitado) dobleClic.iniciar(this);
  }

  void consumirEventos() {
    mensaje = null;
    irAMiAlerta = false;
  }

  // ── ControlDisparo ──
  @override
  void cambio() => notifyListeners();

  @override
  void descartar() {
    mensaje = 'Alerta descartada';
    notifyListeners();
  }

  @override
  Future<void> enviar(MetodoDisparo metodo) async {
    final usuario = _sesion.usuario;
    final motivo = usuario == null ? 'Tu sesión terminó' : ReglaAlerta.validarCreacion(usuario, _reloj());
    if (motivo != null) {
      mensaje = motivo;
      notifyListeners();
      return;
    }
    enviando = true;
    notifyListeners();
    try {
      // U-06: una sola foto automática, con la coordenada y el rumbo del
      // mismo instante. Los tres sensores se leen a la vez; si alguno falla
      // devuelve null y la alerta viaja igual, marcada por el repositorio.
      final disparadaEn = _reloj().toUtc();
      final evidencia = await Future.wait([
        _camara.tomarFoto(),
        _ubicacion.posicionActual(),
        _brujula.rumbo(),
      ]);
      await _alertas.crearAlerta(
        metodo: metodo,
        disparadaEn: disparadaEn,
        rutaFoto: evidencia[0] as String?,
        ubicacion: evidencia[1] as PuntoGeo?,
        rumbo: evidencia[2] as int?,
      );
      irAMiAlerta = true;
    } catch (e) {
      mensaje = ViewModel.mensajeDe(e);
    } finally {
      enviando = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    toque.cancelar();
    mantener.cancelar();
    super.dispose();
  }
}
