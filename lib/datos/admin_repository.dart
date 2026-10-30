// CAPA: DATOS — el contrato de administración
// A-01 Alta · A-02 Edición y baja · A-03 Turnos y radios · A-04 Escaladas
// A-05 Historial · A-06/A-07 Métricas · A-08 Usuarios bloqueados
// Habla en lenguaje del dominio. No sabe de endpoints ni de tablas.

import '../dominio/alerta.dart';
import '../dominio/enums.dart';
import '../dominio/filtro_historial.dart';
import '../dominio/guardia.dart';
import '../dominio/metricas.dart';
import '../dominio/punto_geo.dart';
import '../dominio/usuario.dart';

abstract interface class AdminRepository {
  /// Incluye a los dados de baja al final.
  Future<List<Guardia>> obtenerGuardias({String busqueda = ''});

  Future<Guardia> obtenerGuardia(String guardiaId);

  /// Lanza `CorreoRegistradoError`. La [contrasena] inicial la elige el
  /// administrador (A-01); nunca se fija en el código.
  Future<Guardia> crearGuardia({required String nombre, required String correo, required String telefono, required String contrasena});

  /// Lanza `CorreoRegistradoError`.
  Future<Guardia> actualizarGuardia(String guardiaId, {String? nombre, String? correo, String? telefono});

  /// Baja lógica.
  Future<void> darDeBajaGuardia(String guardiaId);

  /// A-06: la [zona] de cobertura etiqueta al guardia para las métricas.
  Future<Guardia> actualizarCobertura(
    String guardiaId, {
    required String inicioTurno,
    required String finTurno,
    required PuntoGeo centro,
    required int radioMetros,
    required String zona,
  });

  /// Bandeja de escaladas en tiempo real, las más antiguas primero.
  Stream<List<Alerta>> escucharEscaladas();

  /// A-04/A-08: exige la nota administrativa; `falsaAlarma` suma al contador
  /// del usuario y lo bloquea al llegar al límite.
  Future<Alerta> resolverAlerta(String alertaId, Resolucion resolucion, {required String nota});

  Future<List<Alerta>> obtenerHistorial(FiltroHistorial filtro);

  Future<MetricasGenerales> obtenerMetricas({DateTime? desde, DateTime? hasta});

  Future<MetricasGuardia> obtenerMetricasGuardia(String guardiaId, {DateTime? desde, DateTime? hasta});

  /// A-05: usuarios protegidos para el filtro del historial.
  Future<List<Usuario>> obtenerUsuarios();

  Future<List<Usuario>> obtenerUsuariosBloqueados();

  Future<void> desbloquearUsuario(String usuarioId);
}
