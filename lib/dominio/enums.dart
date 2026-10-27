// CAPA: DOMINIO — vocabulario del negocio (sección 4)
// Roles, estados de la alerta, métodos de disparo, razones de escalamiento y
// resoluciones. Cada valor trae su etiqueta en español.
// No hace: no sabe cómo viajan en la API (eso lo traduce datos/nube_mapeadores)
// ni qué color o ícono llevan (eso es presentacion/comun/tema/alert_status_style).
library;

enum RolUsuario {
  usuarioProtegido('Usuario protegido'),
  guardia('Guardia'),
  admin('Administrador');

  const RolUsuario(this.etiqueta);
  final String etiqueta;
}

/// Estados de la alerta (sección 4.5).
enum EstadoAlerta {
  pendienteUbicacion('Pendiente de ubicación'),
  buscando('Buscando guardia'),
  enAtencion('En atención'),
  guardiaEnLugar('Guardia en el lugar'),
  cerrada('Atendida'),
  sinRespuesta('Sin respuesta'),
  escalada('Escalada'),
  resueltaPorAdmin('Resuelta por administrador');

  const EstadoAlerta(this.etiqueta);
  final String etiqueta;

  /// La alerta sigue requiriendo atención del usuario o del guardia.
  bool get activa => this == pendienteUbicacion || this == buscando || this == enAtencion || this == guardiaEnLugar;

  /// La alerta terminó (con o sin intervención del admin).
  bool get terminada => this == cerrada || this == resueltaPorAdmin;
}

enum MetodoDisparo {
  toque('Toque'),
  mantener('Mantener presionado'),
  agitacion('Agitación');

  const MetodoDisparo(this.etiqueta);
  final String etiqueta;
}

enum RazonEscalamiento {
  sinRespuesta('Nadie aceptó a tiempo'),
  sinConfirmacion('El usuario no confirmó');

  const RazonEscalamiento(this.etiqueta);
  final String etiqueta;
}

enum Resolucion {
  resuelta('Resuelta'),
  falsaAlarma('Falsa alarma'),
  incidenciaServicio('Incidencia del servicio');

  const Resolucion(this.etiqueta);
  final String etiqueta;
}
