import 'enums.dart';

/// Sección 4.1. Se llama `AppUser` para no chocar con otras clases `User`.
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.createdAt,
    this.isActive = true,
    this.shakeEnabled = false,
    this.falseAlarmCount = 0,
    this.blockedUntil,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final bool isActive;
  final bool shakeEnabled;
  final int falseAlarmCount;
  final DateTime? blockedUntil;
  final DateTime createdAt;

  bool isBlockedAt(DateTime now) => blockedUntil != null && blockedUntil!.isAfter(now);

  /// "Laura Méndez" → "LM"
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.take(2).map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join();
  }

  AppUser copyWith({
    String? name,
    String? email,
    String? phone,
    bool? isActive,
    bool? shakeEnabled,
    int? falseAlarmCount,
    DateTime? blockedUntil,
    bool clearBlock = false,
  }) =>
      AppUser(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        role: role,
        createdAt: createdAt,
        isActive: isActive ?? this.isActive,
        shakeEnabled: shakeEnabled ?? this.shakeEnabled,
        falseAlarmCount: falseAlarmCount ?? this.falseAlarmCount,
        blockedUntil: clearBlock ? null : (blockedUntil ?? this.blockedUntil),
      );

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        name: j['name'] as String,
        email: j['email'] as String,
        phone: j['phone'] as String,
        role: UserRole.fromJson(j['role'] as String),
        isActive: j['isActive'] as bool? ?? true,
        shakeEnabled: j['shakeEnabled'] as bool? ?? false,
        falseAlarmCount: j['falseAlarmCount'] as int? ?? 0,
        blockedUntil: j['blockedUntil'] == null ? null : DateTime.parse(j['blockedUntil'] as String),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}
