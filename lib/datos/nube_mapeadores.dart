// CAPA: DATOS — Adapter / Mapper de la nube
// Traduce entidad <-> JSON con las claves y códigos de la API (sección 4, en inglés).
// Cada mapeador tiene su fábrica `desdeJson` y su `aJson`. Los usan los `nube_*`
// y el servicio falso (que responde con el mismo contrato JSON).
// No hace: no pide nada a la red. El dominio nunca importa este archivo.

import '../dominio/dominio.dart';

typedef Json = Map<String, Object?>;

/// Códigos que viajan en la API para cada enum del dominio.
abstract final class CodigosJson {
  static const rol = {
    RolUsuario.usuarioProtegido: 'protected_user',
    RolUsuario.guardia: 'guard',
    RolUsuario.admin: 'admin',
  };
  static const estado = {
    EstadoAlerta.pendienteUbicacion: 'pending_location',
    EstadoAlerta.buscando: 'searching',
    EstadoAlerta.enAtencion: 'in_progress',
    EstadoAlerta.guardiaEnLugar: 'guard_arrived',
    EstadoAlerta.cerrada: 'closed',
    EstadoAlerta.sinRespuesta: 'no_response',
    EstadoAlerta.escalada: 'escalated',
    EstadoAlerta.resueltaPorAdmin: 'resolved_by_admin',
  };
  static const metodo = {
    MetodoDisparo.toque: 'tap',
    MetodoDisparo.mantener: 'hold',
    MetodoDisparo.agitacion: 'shake',
  };
  static const razon = {
    RazonEscalamiento.sinRespuesta: 'no_response',
    RazonEscalamiento.sinConfirmacion: 'no_confirmation',
  };
  static const resolucion = {
    Resolucion.resuelta: 'resolved',
    Resolucion.falsaAlarma: 'false_alarm',
    Resolucion.incidenciaServicio: 'service_incident',
  };

  static T desde<T>(Map<T, String> codigos, Object? valor) => codigos.entries.firstWhere((e) => e.value == valor).key;

  static T? desdeOpcional<T>(Map<T, String> codigos, Object? valor) => valor == null ? null : desde(codigos, valor);
}

DateTime? _fecha(Object? v) => v == null ? null : DateTime.parse(v as String);
String? _iso(DateTime? d) => d?.toIso8601String();

abstract final class PuntoGeoJson {
  static PuntoGeo desdeJson(Json j) => PuntoGeo((j['lat']! as num).toDouble(), (j['lng']! as num).toDouble());
  static Json aJson(PuntoGeo p) => {'lat': p.lat, 'lng': p.lng};

  static PuntoGeo? opcional(Object? j) => j == null ? null : desdeJson(j as Json);
}

abstract final class UsuarioJson {
  static Usuario desdeJson(Json j) => Usuario(
        id: j['id']! as String,
        nombre: j['name']! as String,
        correo: j['email']! as String,
        telefono: j['phone']! as String,
        rol: CodigosJson.desde(CodigosJson.rol, j['role']),
        activo: j['isActive'] as bool? ?? true,
        agitacionActiva: j['shakeEnabled'] as bool? ?? false,
        falsasAlarmas: j['falseAlarmCount'] as int? ?? 0,
        bloqueadoHasta: _fecha(j['blockedUntil']),
        creadoEn: DateTime.parse(j['createdAt']! as String),
      );

  static Json aJson(Usuario u) => {
        'id': u.id,
        'name': u.nombre,
        'email': u.correo,
        'phone': u.telefono,
        'role': CodigosJson.rol[u.rol],
        'isActive': u.activo,
        'shakeEnabled': u.agitacionActiva,
        'falseAlarmCount': u.falsasAlarmas,
        'blockedUntil': _iso(u.bloqueadoHasta),
        'createdAt': _iso(u.creadoEn),
      };
}

abstract final class PerfilGuardiaJson {
  static PerfilGuardia desdeJson(Json j) => PerfilGuardia(
        usuarioId: j['userId']! as String,
        inicioTurno: j['shiftStart']! as String,
        finTurno: j['shiftEnd']! as String,
        centroCobertura: PuntoGeoJson.opcional(j['coverageCenter']),
        radioCoberturaMetros: j['coverageRadiusMeters'] as int?,
        ultimaUbicacion: PuntoGeoJson.opcional(j['lastLocation']),
        ultimaUbicacionEn: _fecha(j['lastLocationAt']),
      );

  static Json aJson(PerfilGuardia p) => {
        'userId': p.usuarioId,
        'shiftStart': p.inicioTurno,
        'shiftEnd': p.finTurno,
        'coverageCenter': p.centroCobertura == null ? null : PuntoGeoJson.aJson(p.centroCobertura!),
        'coverageRadiusMeters': p.radioCoberturaMetros,
        'lastLocation': p.ultimaUbicacion == null ? null : PuntoGeoJson.aJson(p.ultimaUbicacion!),
        'lastLocationAt': _iso(p.ultimaUbicacionEn),
      };
}

abstract final class GuardiaJson {
  static Guardia desdeJson(Json j) =>
      Guardia(usuario: UsuarioJson.desdeJson(j['user']! as Json), perfil: PerfilGuardiaJson.desdeJson(j['profile']! as Json));

  static Json aJson(Guardia g) => {'user': UsuarioJson.aJson(g.usuario), 'profile': PerfilGuardiaJson.aJson(g.perfil)};
}

abstract final class AlertaJson {
  static Alerta desdeJson(Json j) => Alerta(
        id: j['id']! as String,
        usuarioId: j['userId']! as String,
        nombreUsuario: j['userName'] as String?,
        telefonoUsuario: j['userPhone'] as String?,
        guardiaId: j['guardId'] as String?,
        nombreGuardia: j['guardName'] as String?,
        estado: CodigosJson.desde(CodigosJson.estado, j['status']),
        metodo: CodigosJson.desde(CodigosJson.metodo, j['triggerMethod']),
        fotoUrl: j['photoUrl'] as String?,
        evidenciaIncompleta: j['evidenceIncomplete'] as bool? ?? false,
        ubicacion: PuntoGeoJson.opcional(j['location']),
        rumbo: j['heading'] as int?,
        disparadaEn: DateTime.parse(j['triggeredAt']! as String),
        aceptadaEn: _fecha(j['acceptedAt']),
        llegadaEn: _fecha(j['arrivedAt']),
        cerradaEn: _fecha(j['closedAt']),
        razonEscalamiento: CodigosJson.desdeOpcional(CodigosJson.razon, j['escalationReason']),
        resolucion: CodigosJson.desdeOpcional(CodigosJson.resolucion, j['resolution']),
        etaSegundos: j['etaSeconds'] as int?,
      );

  static Json aJson(Alerta a) => {
        'id': a.id,
        'userId': a.usuarioId,
        'userName': a.nombreUsuario,
        'userPhone': a.telefonoUsuario,
        'guardId': a.guardiaId,
        'guardName': a.nombreGuardia,
        'status': CodigosJson.estado[a.estado],
        'triggerMethod': CodigosJson.metodo[a.metodo],
        'photoUrl': a.fotoUrl,
        'evidenceIncomplete': a.evidenciaIncompleta,
        'location': a.ubicacion == null ? null : PuntoGeoJson.aJson(a.ubicacion!),
        'heading': a.rumbo,
        'triggeredAt': _iso(a.disparadaEn),
        'acceptedAt': _iso(a.aceptadaEn),
        'arrivedAt': _iso(a.llegadaEn),
        'closedAt': _iso(a.cerradaEn),
        'escalationReason': CodigosJson.razon[a.razonEscalamiento],
        'resolution': CodigosJson.resolucion[a.resolucion],
        'etaSeconds': a.etaSegundos,
      };

  static List<Alerta> lista(Object? j) => [for (final x in j! as List) desdeJson(x as Json)];
}

abstract final class AlertaPriorizadaJson {
  static AlertaPriorizada desdeJson(Json j) => AlertaPriorizada(
        AlertaJson.desdeJson(j['alert']! as Json),
        (j['distanceMeters']! as num).toDouble(),
        (j['waitingMinutes']! as num).toDouble(),
        (j['score']! as num).toDouble(),
      );

  static Json aJson(AlertaPriorizada p) => {
        'alert': AlertaJson.aJson(p.alerta),
        'distanceMeters': p.distanciaMetros,
        'waitingMinutes': p.minutosEspera,
        'score': p.puntaje,
      };
}

abstract final class MetricasGeneralesJson {
  static MetricasGenerales desdeJson(Json j) => MetricasGenerales(
        totalAlertas: j['totalAlerts']! as int,
        promedioAceptacionSeg: (j['avgAcceptanceSeconds']! as num).toDouble(),
        promedioLlegadaSeg: (j['avgArrivalSeconds']! as num).toDouble(),
        tasaSinRespuesta: (j['noResponseRate']! as num).toDouble(),
        tasaCierreConfirmado: (j['confirmedCloseRate']! as num).toDouble(),
        alertasPorHora: [for (final n in j['alertsByHour']! as List) n as int],
      );

  static Json aJson(MetricasGenerales m) => {
        'totalAlerts': m.totalAlertas,
        'avgAcceptanceSeconds': m.promedioAceptacionSeg,
        'avgArrivalSeconds': m.promedioLlegadaSeg,
        'noResponseRate': m.tasaSinRespuesta,
        'confirmedCloseRate': m.tasaCierreConfirmado,
        'alertsByHour': m.alertasPorHora,
      };
}

abstract final class MetricasGuardiaJson {
  static MetricasGuardia desdeJson(Json j) => MetricasGuardia(
        atendidas: j['attendedCount']! as int,
        promedioAceptacionSeg: (j['avgAcceptanceSeconds']! as num).toDouble(),
        promedioLlegadaSeg: (j['avgArrivalSeconds']! as num).toDouble(),
        escaladas: j['escalatedCount']! as int,
      );

  static Json aJson(MetricasGuardia m) => {
        'attendedCount': m.atendidas,
        'avgAcceptanceSeconds': m.promedioAceptacionSeg,
        'avgArrivalSeconds': m.promedioLlegadaSeg,
        'escalatedCount': m.escaladas,
      };
}

abstract final class FiltroHistorialJson {
  /// El filtro viaja como query string.
  static Map<String, String> aQuery(FiltroHistorial f) => {
        if (f.desde != null) 'from': f.desde!.toIso8601String(),
        if (f.hasta != null) 'to': f.hasta!.toIso8601String(),
        if (f.guardiaId != null) 'guardId': f.guardiaId!,
        if (f.usuarioId != null) 'userId': f.usuarioId!,
        if (f.estado != null) 'status': CodigosJson.estado[f.estado]!,
      };

  static FiltroHistorial desdeQuery(Map<String, String> q) => FiltroHistorial(
        desde: _fecha(q['from']),
        hasta: _fecha(q['to']),
        guardiaId: q['guardId'],
        usuarioId: q['userId'],
        estado: CodigosJson.desdeOpcional(CodigosJson.estado, q['status']),
      );
}

/// `{ "error": { "code", "message", ... } }` <-> ErrorDominio.
abstract final class ErrorJson {
  static Json aJson(ErrorDominio e) => {
        'code': e.codigo,
        'message': e.mensaje,
        if (e is FueraDeGeocercaError) 'remainingMeters': e.metrosRestantes.isFinite ? e.metrosRestantes : null,
      };

  static ErrorDominio desdeJson(Json j) {
    final mensaje = j['message'] as String? ?? 'Ocurrió un error';
    return switch (j['code']) {
      'INVALID_CREDENTIALS' => const CredencialesInvalidasError(),
      'EMAIL_TAKEN' => const CorreoRegistradoError(),
      'USER_BLOCKED' => const UsuarioBloqueadoError(),
      'ALERT_TAKEN' => const AlertaTomadaError(),
      'OUTSIDE_GEOFENCE' => FueraDeGeocercaError((j['remainingMeters'] as num?)?.toDouble() ?? double.infinity),
      'INVALID_STATE' => EstadoInvalidoError(mensaje),
      'NOT_FOUND' => NoEncontradoError(mensaje),
      'UNAUTHORIZED' => const SinSesionError(),
      'SERVICE_UNAVAILABLE' => const ServicioNoDisponibleError(),
      final codigo => ErrorDominio('$codigo', mensaje),
    };
  }
}

/// Respuesta de la API: `{ "data": ... }` o `{ "error": ... }`.
abstract final class RespuestaJson {
  /// Devuelve `data` o lanza el ErrorDominio correspondiente.
  static Object? datos(Json respuesta) {
    final error = respuesta['error'];
    if (error != null) throw ErrorJson.desdeJson(error as Json);
    return respuesta['data'];
  }
}
