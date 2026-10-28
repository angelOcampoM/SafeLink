// CAPA: PRESENTACIÓN — ViewModel
// U-03 Toque simple · U-04 Mantener presionado · U-05 Agitación · U-06 Evidencia
// Guarda el estado del botón (cuenta regresiva, manteniendo, enviando) y
// delega en una estrategia por método de disparo. Al enviar, pide al dominio
// si el usuario puede y al repositorio que cree la alerta.
// No importa material.dart: no calcula la zona de descarte en pantalla (la View
// le dice si el dedo está encima) ni navega (emite `irAMiAlerta`).
//
// TODO(U-06): tomar la foto real con la cámara y leer GPS/brújula.
// TODO(U-05): mostrar indicador del servicio de agitación activo.

import '../../datos/alerta_usuario_repository.dart';
import '../../dominio/dominio.dart';
import '../comun/view_model.dart';
import '../sesion/sesion_view_model.dart';
import 'estrategias_disparo.dart';

class InicioViewModel extends ViewModel implements ControlDisparo {
  InicioViewModel(
    this._alertas,
    this._sesion, {
    required this.config,
    required PuntoGeo Function() ubicacionDispositivo,
    DateTime Function()? reloj,
    Duration intervaloCuenta = const Duration(seconds: 1),
  })  : _ubicacion = ubicacionDispositivo,
        _reloj = reloj ?? DateTime.now,
        toque = ToqueConCuentaRegresiva(segundos: config.segundosCuentaRegresiva, intervalo: intervaloCuenta);

  final AlertaUsuarioRepository _alertas;
  final SesionViewModel _sesion;
  final Configuracion config;
  final PuntoGeo Function() _ubicacion;
  final DateTime Function() _reloj;

  // Estrategias intercambiables (Strategy).
  final ToqueConCuentaRegresiva toque;
  final mantener = MantenerConDescarte();
  final agitacion = Agitacion();

  bool enviando = false;

  /// Mensaje de un solo uso para un SnackBar.
  String? mensaje;

  /// Evento de un solo uso: la alerta se creó y hay que ir a "Mi alerta".
  bool irAMiAlerta = false;

  String get primerNombre => _sesion.usuario?.primerNombre ?? '';
  bool get agitacionActiva => _sesion.usuario?.agitacionActiva ?? false;
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

  /// Solo en demo: simula que el servicio de agitación detectó el gesto.
  void agitar() {
    if (agitacionActiva && botonHabilitado) agitacion.iniciar(this);
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
      await _alertas.crearAlerta(
        metodo: metodo,
        disparadaEn: _reloj().toUtc(),
        ubicacion: _ubicacion(), // TODO(U-06): GPS real
        rumbo: 35, // TODO(U-06): brújula real
        rutaFoto: 'demo.jpg', // TODO(U-06): foto real
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
