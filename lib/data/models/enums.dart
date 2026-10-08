/// Enums del dominio. El valor `json` es el que viaja en la API (sección 4).
library;

enum UserRole {
  protectedUser('protected_user', 'Usuario protegido'),
  guard('guard', 'Guardia'),
  admin('admin', 'Administrador');

  const UserRole(this.json, this.label);
  final String json;
  final String label;

  static UserRole fromJson(String v) => values.firstWhere((e) => e.json == v);
}

/// Estados de la alerta (sección 4.5). El color/ícono vive en
/// `core/theme/alert_status_style.dart` para no mezclar UI con datos.
enum AlertStatus {
  pendingLocation('pending_location', 'Pendiente de ubicación'),
  searching('searching', 'Buscando guardia'),
  inProgress('in_progress', 'En atención'),
  guardArrived('guard_arrived', 'Guardia en el lugar'),
  closed('closed', 'Atendida'),
  noResponse('no_response', 'Sin respuesta'),
  escalated('escalated', 'Escalada'),
  resolvedByAdmin('resolved_by_admin', 'Resuelta por administrador');

  const AlertStatus(this.json, this.label);
  final String json;
  final String label;

  static AlertStatus fromJson(String v) => values.firstWhere((e) => e.json == v);

  /// La alerta sigue requiriendo atención del usuario o del guardia.
  bool get isActive => this == pendingLocation || this == searching || this == inProgress || this == guardArrived;

  /// La alerta terminó (con o sin intervención del admin).
  bool get isFinished => this == closed || this == resolvedByAdmin;
}

enum TriggerMethod {
  tap('tap', 'Toque'),
  hold('hold', 'Mantener presionado'),
  shake('shake', 'Agitación');

  const TriggerMethod(this.json, this.label);
  final String json;
  final String label;

  static TriggerMethod fromJson(String v) => values.firstWhere((e) => e.json == v);
}

enum EscalationReason {
  noResponse('no_response', 'Nadie aceptó a tiempo'),
  noConfirmation('no_confirmation', 'El usuario no confirmó');

  const EscalationReason(this.json, this.label);
  final String json;
  final String label;

  static EscalationReason? fromJson(String? v) =>
      v == null ? null : values.firstWhere((e) => e.json == v);
}

enum Resolution {
  resolved('resolved', 'Resuelta'),
  falseAlarm('false_alarm', 'Falsa alarma'),
  serviceIncident('service_incident', 'Incidencia del servicio');

  const Resolution(this.json, this.label);
  final String json;
  final String label;

  static Resolution? fromJson(String? v) =>
      v == null ? null : values.firstWhere((e) => e.json == v);
}
