import '../../core/utils/shift_utils.dart';
import 'geo_point.dart';
import 'user.dart';

/// Sección 4.2. Turnos en formato "HH:mm"; pueden cruzar medianoche.
class GuardProfile {
  const GuardProfile({
    required this.userId,
    required this.shiftStart,
    required this.shiftEnd,
    required this.coverageCenter,
    required this.coverageRadiusMeters,
    this.lastLocation,
    this.lastLocationAt,
  });

  final String userId;
  final String shiftStart;
  final String shiftEnd;
  final GeoPoint? coverageCenter;
  final int? coverageRadiusMeters;
  final GeoPoint? lastLocation;
  final DateTime? lastLocationAt;

  bool isOnShiftAt(DateTime localNow) => ShiftUtils.isWithinShift(shiftStart, shiftEnd, localNow);

  bool get hasCoverage => coverageCenter != null && (coverageRadiusMeters ?? 0) > 0;

  GuardProfile copyWith({
    String? shiftStart,
    String? shiftEnd,
    GeoPoint? coverageCenter,
    int? coverageRadiusMeters,
    GeoPoint? lastLocation,
  }) =>
      GuardProfile(
        userId: userId,
        shiftStart: shiftStart ?? this.shiftStart,
        shiftEnd: shiftEnd ?? this.shiftEnd,
        coverageCenter: coverageCenter ?? this.coverageCenter,
        coverageRadiusMeters: coverageRadiusMeters ?? this.coverageRadiusMeters,
        lastLocation: lastLocation ?? this.lastLocation,
        lastLocationAt: lastLocation != null ? DateTime.now() : lastLocationAt,
      );
}

/// Usuario guardia + su perfil, como lo devuelve `/admin/guards`.
class Guard {
  const Guard({required this.user, required this.profile});

  final AppUser user;
  final GuardProfile profile;

  /// Disponible = activo + en turno + con radio (sección 4.2).
  bool isAvailableAt(DateTime localNow) =>
      user.isActive && profile.hasCoverage && profile.isOnShiftAt(localNow);
}
