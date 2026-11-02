// CAPA: PRESENTACIÓN — patrón Factory de ViewModels
// El router le pide a esta fábrica el ViewModel de cada ruta. Recibe por
// constructor los CONTRATOS de datos (nunca las implementaciones): main.dart
// decide si son de memoria o de la nube.
// No hace: no pinta, no navega y no guarda estado propio.

import '../../../datos/admin_repository.dart';
import '../../../datos/alerta_guardia_repository.dart';
import '../../../datos/alerta_usuario_repository.dart';
import '../../../dominio/configuracion.dart';
import '../../../dominio/punto_geo.dart';
import '../../admin/cobertura_guardia_view_model.dart';
import '../../admin/detalle_alerta_admin_view_model.dart';
import '../../admin/detalle_escalada_view_model.dart';
import '../../admin/editar_guardia_view_model.dart';
import '../../admin/escaladas_view_model.dart';
import '../../admin/guardias_view_model.dart';
import '../../admin/historial_view_model.dart';
import '../../admin/metricas_guardia_view_model.dart';
import '../../admin/panel_view_model.dart';
import '../../auth/login_view_model.dart';
import '../../auth/registro_view_model.dart';
import '../../guardia/alerta_entrante_view_model.dart';
import '../../guardia/detalle_alerta_view_model.dart';
import '../../guardia/historial_guardia_view_model.dart';
import '../../guardia/listado_alertas_view_model.dart';
import '../../guardia/navegacion_view_model.dart';
import '../../sesion/sesion_view_model.dart';
import '../../usuario/configuracion_view_model.dart';
import '../../usuario/estado_alerta_view_model.dart';
import '../../usuario/historial_usuario_view_model.dart';
import '../../usuario/inicio_view_model.dart';

class FabricaViewModels {
  FabricaViewModels({
    required this.sesion,
    required this.alertasUsuario,
    required this.alertasGuardia,
    required this.admin,
    required this.config,
    required this.ubicacionDispositivo,
    required this.centroPorDefecto,
    this.cuentasDemo = const [],
    this.contrasenaDemo = '',
    DateTime Function()? reloj,
  }) : reloj = reloj ?? DateTime.now;

  final SesionViewModel sesion;
  final AlertaUsuarioRepository alertasUsuario;
  final AlertaGuardiaRepository alertasGuardia;
  final AdminRepository admin;
  final Configuracion config;
  final DateTime Function() reloj;

  /// TODO(U-06): sustituir por el GPS real del teléfono.
  final PuntoGeo Function() ubicacionDispositivo;

  /// Centro de cobertura para guardias que aún no tienen zona (A-03).
  final PuntoGeo centroPorDefecto;

  /// Solo en demo: cuentas que el login ofrece rellenar.
  final List<(String, String)> cuentasDemo;
  final String contrasenaDemo;

  // ── Auth ──
  LoginViewModel login() => LoginViewModel(
        sesion,
        cuentasDemo: config.modoDemo ? cuentasDemo : const [],
        contrasenaDemo: contrasenaDemo,
      );
  RegistroViewModel registro() => RegistroViewModel(sesion);

  // ── Usuario protegido ──
  InicioViewModel inicio() =>
      InicioViewModel(alertasUsuario, sesion, config: config, ubicacionDispositivo: ubicacionDispositivo, reloj: reloj);
  EstadoAlertaViewModel estadoAlerta() => EstadoAlertaViewModel(alertasUsuario);
  ConfiguracionViewModel configuracion() => ConfiguracionViewModel(sesion);
  HistorialUsuarioViewModel historialUsuario() => HistorialUsuarioViewModel(alertasUsuario, reloj: reloj);

  // ── Guardia ──
  ListadoAlertasViewModel listadoAlertas() => ListadoAlertasViewModel(alertasGuardia, sesion, reloj: reloj);
  AlertaEntranteViewModel alertaEntrante(String id) => AlertaEntranteViewModel(alertasGuardia, id, reloj: reloj);
  DetalleAlertaViewModel detalleAlerta(String id) => DetalleAlertaViewModel(alertasGuardia, id, reloj: reloj);
  NavegacionViewModel navegacion(String id) => NavegacionViewModel(alertasGuardia, id, config: config);
  HistorialGuardiaViewModel historialGuardia() => HistorialGuardiaViewModel(alertasGuardia, reloj: reloj);

  // ── Administrador ──
  PanelViewModel panel() => PanelViewModel(admin, sesion, reloj: reloj);
  GuardiasViewModel guardias() => GuardiasViewModel(admin, reloj: reloj);
  EditarGuardiaViewModel editarGuardia({String? id}) => EditarGuardiaViewModel(admin, guardiaId: id);
  CoberturaGuardiaViewModel coberturaGuardia(String id) =>
      CoberturaGuardiaViewModel(admin, id, config: config, centroPorDefecto: centroPorDefecto);
  MetricasGuardiaViewModel metricasGuardia(String id) => MetricasGuardiaViewModel(admin, id, reloj: reloj);
  EscaladasViewModel escaladas() => EscaladasViewModel(admin, reloj: reloj);
  DetalleEscaladaViewModel detalleEscalada(String id) => DetalleEscaladaViewModel(admin, id);
  HistorialViewModel historial() => HistorialViewModel(admin, reloj: reloj);
  DetalleAlertaAdminViewModel detalleAlertaAdmin(String id) => DetalleAlertaAdminViewModel(admin, id, reloj: reloj);
}
