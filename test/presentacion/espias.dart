// Repositorios espía para probar ViewModels sin abrir pantallas y sin red.
// Cada espía cumple el contrato real, guarda lo que le pidieron y devuelve
// lo que la prueba configuró.
import 'package:safelink/datos/admin_repository.dart';
import 'package:safelink/datos/alerta_guardia_repository.dart';
import 'package:safelink/datos/alerta_usuario_repository.dart';
import 'package:safelink/datos/auth_repository.dart';
import 'package:safelink/dominio/dominio.dart';

final ahoraPrueba = DateTime(2026, 10, 26, 13, 0);
const puntoAlerta = PuntoGeo(18.8400, -99.1800);

Usuario usuarioPrueba({RolUsuario rol = RolUsuario.usuarioProtegido, DateTime? bloqueadoHasta}) => Usuario(
      id: 'u-1',
      nombre: 'Fernanda Morales Gil',
      correo: 'usuario@safelink.mx',
      telefono: '7771234567',
      rol: rol,
      creadoEn: ahoraPrueba,
      bloqueadoHasta: bloqueadoHasta,
    );

Alerta alertaPrueba({EstadoAlerta estado = EstadoAlerta.buscando, PuntoGeo? ubicacion = puntoAlerta}) => Alerta(
      id: 'alt-1',
      usuarioId: 'u-1',
      nombreUsuario: 'Fernanda Morales Gil',
      estado: estado,
      metodo: MetodoDisparo.toque,
      disparadaEn: ahoraPrueba,
      ubicacion: ubicacion,
    );

Guardia guardiaPrueba({PuntoGeo? ubicacion, int radio = 4000}) => Guardia(
      usuario: usuarioPrueba(rol: RolUsuario.guardia),
      perfil: PerfilGuardia(
        usuarioId: 'u-1',
        inicioTurno: '08:00',
        finTurno: '16:00',
        centroCobertura: puntoAlerta,
        radioCoberturaMetros: radio,
        ultimaUbicacion: ubicacion,
      ),
    );

class AuthEspia implements AuthRepository {
  AuthEspia({this.usuarioActual, this.falla});

  @override
  Usuario? usuarioActual;
  ErrorDominio? falla;
  int llamadasLogin = 0;

  @override
  Future<Usuario> iniciarSesion({required String correo, required String contrasena}) async {
    llamadasLogin++;
    if (falla != null) throw falla!;
    return usuarioActual = usuarioPrueba();
  }

  @override
  Future<Usuario> registrar({required String nombre, required String correo, required String telefono, required String contrasena}) async =>
      usuarioActual = usuarioPrueba();

  @override
  Future<void> cerrarSesion() async => usuarioActual = null;

  @override
  Future<Usuario> refrescarSesion() async => usuarioActual!;

  @override
  Future<Usuario> actualizarAgitacion({required bool activa}) async =>
      usuarioActual = usuarioActual!.copyWith(agitacionActiva: activa);
}

class AlertaUsuarioEspia implements AlertaUsuarioRepository {
  final creadas = <MetodoDisparo>[];

  @override
  Future<Alerta> crearAlerta({required MetodoDisparo metodo, required DateTime disparadaEn, PuntoGeo? ubicacion, int? rumbo, String? rutaFoto}) async {
    creadas.add(metodo);
    return alertaPrueba();
  }

  @override
  Stream<Alerta?> escucharAlertaActiva() => Stream.value(null);

  @override
  Future<void> enviarUbicacion(String alertaId, PuntoGeo ubicacion) async {}

  @override
  Future<Alerta> confirmarAtencion(String alertaId) async => alertaPrueba(estado: EstadoAlerta.cerrada);

  @override
  Future<List<Alerta>> obtenerHistorial() async => [];
}

class AlertaGuardiaEspia implements AlertaGuardiaRepository {
  AlertaGuardiaEspia({required this.alerta, required this.guardia, this.fallaAceptar});

  Alerta alerta;
  Guardia guardia;
  ErrorDominio? fallaAceptar;
  final aceptadas = <String>[];
  final llegadas = <String>[];
  final ubicaciones = <PuntoGeo>[];

  @override
  Future<Guardia> obtenerMiPerfil() async => guardia;

  @override
  Stream<List<AlertaPriorizada>> escucharAlertasDisponibles() => Stream.value(const []);

  @override
  Future<Alerta> obtenerAlerta(String alertaId) async => alerta;

  @override
  Stream<Alerta> escucharAlerta(String alertaId) => Stream.value(alerta);

  @override
  Future<Alerta> aceptarAlerta(String alertaId) async {
    aceptadas.add(alertaId);
    if (fallaAceptar != null) throw fallaAceptar!;
    return alerta = alerta.copyWith(estado: EstadoAlerta.enAtencion);
  }

  @override
  Future<void> ignorarAlerta(String alertaId) async {}

  @override
  Future<void> actualizarMiUbicacion(PuntoGeo ubicacion) async => ubicaciones.add(ubicacion);

  @override
  Future<Alerta> marcarLlegada(String alertaId) async {
    llegadas.add(alertaId);
    return alerta.copyWith(estado: EstadoAlerta.guardiaEnLugar);
  }

  @override
  Future<List<Alerta>> obtenerMiHistorial() async => [];

  @override
  Future<MetricasGuardia> obtenerMisMetricas() async => MetricasGuardia.vacias;
}

typedef CoberturaGuardada = ({String id, String inicio, String fin, PuntoGeo centro, int radio});

class AdminEspia implements AdminRepository {
  AdminEspia({required this.guardia});

  Guardia guardia;
  final coberturas = <CoberturaGuardada>[];

  @override
  Future<Guardia> obtenerGuardia(String guardiaId) async => guardia;

  @override
  Future<Guardia> actualizarCobertura(String guardiaId, {required String inicioTurno, required String finTurno, required PuntoGeo centro, required int radioMetros}) async {
    coberturas.add((id: guardiaId, inicio: inicioTurno, fin: finTurno, centro: centro, radio: radioMetros));
    return guardia;
  }

  @override
  Future<List<Guardia>> obtenerGuardias({String busqueda = ''}) async => [guardia];

  @override
  Future<Guardia> crearGuardia({required String nombre, required String correo, required String telefono}) async => guardia;

  @override
  Future<Guardia> actualizarGuardia(String guardiaId, {String? nombre, String? correo, String? telefono}) async => guardia;

  @override
  Future<void> darDeBajaGuardia(String guardiaId) async {}

  @override
  Stream<List<Alerta>> escucharEscaladas() => Stream.value(const []);

  @override
  Future<Alerta> resolverAlerta(String alertaId, Resolucion resolucion) async => alertaPrueba(estado: EstadoAlerta.resueltaPorAdmin);

  @override
  Future<List<Alerta>> obtenerHistorial(FiltroHistorial filtro) async => [];

  @override
  Future<MetricasGenerales> obtenerMetricas({DateTime? desde, DateTime? hasta}) async => MetricasGenerales.vacias;

  @override
  Future<MetricasGuardia> obtenerMetricasGuardia(String guardiaId, {DateTime? desde, DateTime? hasta}) async => MetricasGuardia.vacias;

  @override
  Future<List<Usuario>> obtenerUsuariosBloqueados() async => [];

  @override
  Future<void> desbloquearUsuario(String usuarioId) async {}
}
