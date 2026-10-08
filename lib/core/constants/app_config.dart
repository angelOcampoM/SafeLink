/// Valores configurables (sección 5). Los marcados como provisionales aún no
/// los define el equipo: cámbialos SOLO aquí, nunca en las vistas.
class AppConfig {
  const AppConfig({
    this.tapCountdownSeconds = 3,
    this.geofenceRadiusMeters = 50, // provisional
    this.acceptanceTimeoutMinutes = 5, // provisional
    this.confirmationTimeoutMinutes = 15, // provisional
    this.falseAlarmLimit = 3, // provisional
    this.blockDurationDays = 7, // provisional
    this.locationUpdateIntervalSeconds = 5, // provisional
    this.priorityMetersPerWaitingMinute = 100, // provisional (sección 6.3)
    this.useMockData = true,
  });

  final int tapCountdownSeconds;
  final int geofenceRadiusMeters;
  final int acceptanceTimeoutMinutes;
  final int confirmationTimeoutMinutes;
  final int falseAlarmLimit;
  final int blockDurationDays;
  final int locationUpdateIntervalSeconds;
  final int priorityMetersPerWaitingMinute;

  /// `true` mientras no exista la API. Se puede forzar con
  /// `flutter run --dart-define=USE_MOCK=false`.
  final bool useMockData;

  static const defaults = AppConfig(
    useMockData: bool.fromEnvironment('USE_MOCK', defaultValue: true),
  );
}
