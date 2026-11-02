// RAÍZ DE COMPOSICIÓN — SafeLink en tres capas + MVVM
//
// Este archivo es el ÚNICO lugar que conoce las implementaciones concretas.
// "¿Qué hay que editar para pasar de memoria a la nube?" → la línea `usarNube`.
// Nada más: los ViewModels y las Views solo conocen los contratos.
//
// Regla de dependencias: presentacion → datos → dominio (dominio no depende de nadie).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'datos/admin_repository.dart';
import 'datos/alerta_guardia_repository.dart';
import 'datos/alerta_usuario_repository.dart';
import 'datos/auth_repository.dart';
import 'datos/datos_semilla.dart';
import 'datos/memoria_admin_repository.dart';
import 'datos/memoria_alerta_guardia_repository.dart';
import 'datos/memoria_alerta_usuario_repository.dart';
import 'datos/memoria_auth_repository.dart';
import 'datos/dispositivo_sesion_guardada.dart';
import 'datos/memoria_base_datos.dart';
import 'datos/memoria_sesion_guardada.dart';
import 'datos/nube_admin_repository.dart';
import 'datos/nube_alerta_guardia_repository.dart';
import 'datos/nube_alerta_usuario_repository.dart';
import 'datos/nube_auth_repository.dart';
import 'datos/safelink_service.dart';
import 'datos/sensores.dart';
import 'datos/sensores_simulados.dart';
import 'datos/servicio_disparo_rapido.dart';
import 'datos/servicio_disparo_rapido_simulado.dart';
import 'datos/sesion_guardada.dart';
import 'dominio/configuracion.dart';
import 'presentacion/comun/rutas/app_router.dart';
import 'presentacion/comun/rutas/fabrica_view_models.dart';
import 'presentacion/comun/tema/theme.dart';
import 'presentacion/sesion/sesion_view_model.dart';
import 'presentacion/usuario/captura_evidencia.dart';
import 'presentacion/usuario/disparo_rapido.dart';

const usarNube = false; // cámbialo a true y haz hot restart.

/// Solo con `usarNube = true`: probabilidad de que falle cada petición (0.0–1.0).
const tasaFallo = 0.0;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencias = Dependencias.crear(
    usarNube: usarNube,
    tasaFallo: tasaFallo,
    sesionGuardada: DispositivoSesionGuardada(),
  );
  // U-02: si quedó una sesión abierta, se entra directo sin pasar por el login.
  await dependencias.sesion.restaurar();
  runApp(SafeLinkApp(dependencias: dependencias));
}

/// Los cuatro contratos ya armados, más la fábrica de ViewModels.
class Dependencias {
  Dependencias({
    required this.auth,
    required this.alertasUsuario,
    required this.alertasGuardia,
    required this.admin,
    this.config = Configuracion.porDefecto,
    SesionGuardada? sesionGuardada,
    Camara? camara,
    Ubicacion? ubicacion,
    Brujula? brujula,
    ServicioDisparoRapido? servicioDisparoRapido,
    Vibrador? vibrador,
    void Function()? iniciarSimulaciones,
  })  : sesionGuardada = sesionGuardada ?? MemoriaSesionGuardada(),
        camara = camara ?? CamaraSimulada(),
        ubicacion = ubicacion ?? UbicacionSimulada(inicial: DatosSemilla.ubicacionDispositivoUsuario),
        brujula = brujula ?? BrujulaSimulada(),
        servicioDisparoRapido = servicioDisparoRapido ?? ServicioDisparoRapidoSimulado(),
        vibrador = vibrador ?? VibradorSimulado(),
        iniciarSimulaciones = iniciarSimulaciones ?? _nada {
    sesion = SesionViewModel(auth, this.sesionGuardada);
    disparoRapido = DisparoRapido(
      servicio: this.servicioDisparoRapido,
      vibrador: this.vibrador,
      alertas: alertasUsuario,
      evidencia: CapturaEvidencia(camara: this.camara, ubicacion: this.ubicacion, brujula: this.brujula),
    );
    fabrica = FabricaViewModels(
      sesion: sesion,
      alertasUsuario: alertasUsuario,
      alertasGuardia: alertasGuardia,
      admin: admin,
      config: config,
      disparoRapido: disparoRapido,
      camara: this.camara,
      ubicacion: this.ubicacion,
      brujula: this.brujula,
      centroPorDefecto: DatosSemilla.centroEmilianoZapata,
      cuentasDemo: DatosSemilla.cuentasDemo,
      contrasenaDemo: DatosSemilla.contrasena,
    );
  }

  /// Arma memoria o nube. Las simulaciones de tiempo real (alertas nuevas,
  /// escalamiento) se arrancan desde [SafeLinkApp], nunca en las pruebas.
  factory Dependencias.crear({
    required bool usarNube,
    double tasaFallo = 0.0,
    Configuracion config = Configuracion.porDefecto,
    SesionGuardada? sesionGuardada,
  }) {
    if (usarNube) {
      final servicio = SafeLinkService(servidor: MemoriaBaseDatos(config: config, latencia: Duration.zero), tasaFallo: tasaFallo);
      return Dependencias(
        auth: NubeAuthRepository(servicio),
        alertasUsuario: NubeAlertaUsuarioRepository(servicio),
        alertasGuardia: NubeAlertaGuardiaRepository(servicio),
        admin: NubeAdminRepository(servicio),
        config: config,
        sesionGuardada: sesionGuardada,
        iniciarSimulaciones: servicio.iniciarSimulaciones,
      );
    }
    final db = MemoriaBaseDatos(config: config);
    return Dependencias(
      auth: MemoriaAuthRepository(db),
      alertasUsuario: MemoriaAlertaUsuarioRepository(db),
      alertasGuardia: MemoriaAlertaGuardiaRepository(db),
      admin: MemoriaAdminRepository(db),
      config: config,
      sesionGuardada: sesionGuardada,
      iniciarSimulaciones: db.iniciarSimulaciones,
    );
  }

  final AuthRepository auth;
  final AlertaUsuarioRepository alertasUsuario;
  final AlertaGuardiaRepository alertasGuardia;
  final AdminRepository admin;
  final Configuracion config;
  final SesionGuardada sesionGuardada;

  /// U-06 · U-07: sensores. Hoy simulados; al enchufar los plugins reales
  /// solo cambian estas tres líneas.
  final Camara camara;
  final Ubicacion ubicacion;
  final Brujula brujula;

  /// U-05: servicio en segundo plano y vibración, hoy simulados.
  final ServicioDisparoRapido servicioDisparoRapido;
  final Vibrador vibrador;
  late final DisparoRapido disparoRapido;
  final void Function() iniciarSimulaciones;
  late final SesionViewModel sesion;
  late final FabricaViewModels fabrica;

  static void _nada() {}
}

class SafeLinkApp extends StatefulWidget {
  const SafeLinkApp({super.key, required this.dependencias, this.simular = true});
  final Dependencias dependencias;

  /// `false` en pruebas de interfaz: sin timers de fondo.
  final bool simular;

  @override
  State<SafeLinkApp> createState() => _SafeLinkAppState();
}

class _SafeLinkAppState extends State<SafeLinkApp> {
  late final GoRouter _router = crearRouter(widget.dependencias.sesion, widget.dependencias.fabrica);

  @override
  void initState() {
    super.initState();
    if (widget.simular) widget.dependencias.iniciarSimulaciones();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SafeLink',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      locale: const Locale('es', 'MX'),
      supportedLocales: const [Locale('es', 'MX'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: _router,
    );
  }
}
