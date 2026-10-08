import 'enums.dart';
import 'geo_point.dart';

/// Sección 4.3. Incluye campos "de lectura" que la API agrega para la UI
/// (`userName`, `guardName`, `etaSeconds`) y que no existen en la tabla.
class Alert {
  const Alert({
    required this.id,
    required this.userId,
    required this.status,
    required this.triggerMethod,
    required this.triggeredAt,
    this.userName,
    this.userPhone,
    this.guardId,
    this.guardName,
    this.photoUrl,
    this.evidenceIncomplete = false,
    this.location,
    this.heading,
    this.acceptedAt,
    this.arrivedAt,
    this.closedAt,
    this.escalationReason,
    this.resolution,
    this.etaSeconds,
  });

  final String id;
  final String userId;
  final String? userName;
  final String? userPhone;
  final String? guardId;
  final String? guardName;
  final AlertStatus status;
  final TriggerMethod triggerMethod;
  final String? photoUrl;
  final bool evidenceIncomplete;
  final GeoPoint? location;
  final int? heading;
  final DateTime triggeredAt;
  final DateTime? acceptedAt;
  final DateTime? arrivedAt;
  final DateTime? closedAt;
  final EscalationReason? escalationReason;
  final Resolution? resolution;
  final int? etaSeconds;

  bool get isUrgent => triggerMethod == TriggerMethod.shake;

  Duration waitingAt(DateTime now) => now.difference(triggeredAt);

  Alert copyWith({
    AlertStatus? status,
    String? guardId,
    String? guardName,
    DateTime? acceptedAt,
    DateTime? arrivedAt,
    DateTime? closedAt,
    EscalationReason? escalationReason,
    Resolution? resolution,
    GeoPoint? location,
    int? etaSeconds,
  }) =>
      Alert(
        id: id,
        userId: userId,
        userName: userName,
        userPhone: userPhone,
        guardId: guardId ?? this.guardId,
        guardName: guardName ?? this.guardName,
        status: status ?? this.status,
        triggerMethod: triggerMethod,
        photoUrl: photoUrl,
        evidenceIncomplete: evidenceIncomplete,
        location: location ?? this.location,
        heading: heading,
        triggeredAt: triggeredAt,
        acceptedAt: acceptedAt ?? this.acceptedAt,
        arrivedAt: arrivedAt ?? this.arrivedAt,
        closedAt: closedAt ?? this.closedAt,
        escalationReason: escalationReason ?? this.escalationReason,
        resolution: resolution ?? this.resolution,
        etaSeconds: etaSeconds ?? this.etaSeconds,
      );

  factory Alert.fromJson(Map<String, dynamic> j) {
    DateTime? d(String k) => j[k] == null ? null : DateTime.parse(j[k] as String);
    return Alert(
      id: j['id'] as String,
      userId: j['userId'] as String,
      userName: j['userName'] as String?,
      userPhone: j['userPhone'] as String?,
      guardId: j['guardId'] as String?,
      guardName: j['guardName'] as String?,
      status: AlertStatus.fromJson(j['status'] as String),
      triggerMethod: TriggerMethod.fromJson(j['triggerMethod'] as String),
      photoUrl: j['photoUrl'] as String?,
      evidenceIncomplete: j['evidenceIncomplete'] as bool? ?? false,
      location: j['location'] == null ? null : GeoPoint.fromJson(j['location'] as Map<String, dynamic>),
      heading: j['heading'] as int?,
      triggeredAt: DateTime.parse(j['triggeredAt'] as String),
      acceptedAt: d('acceptedAt'),
      arrivedAt: d('arrivedAt'),
      closedAt: d('closedAt'),
      escalationReason: EscalationReason.fromJson(j['escalationReason'] as String?),
      resolution: Resolution.fromJson(j['resolution'] as String?),
      etaSeconds: j['etaSeconds'] as int?,
    );
  }
}
