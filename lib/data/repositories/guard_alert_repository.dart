import '../../core/utils/alert_sorting.dart';
import '../models/alert.dart';
import '../models/geo_point.dart';
import '../models/guard_profile.dart';

/// Alertas desde el punto de vista del guardia (G-02 a G-07).
abstract interface class GuardAlertRepository {
  /// Perfil del guardia en sesión (turno, radio, última ubicación).
  Future<Guard> getMyProfile();

  /// `GET /guard/alerts` ya ordenadas (sección 6.3). Se vuelve a emitir con
  /// `alert.created` / `alert.taken`.
  Stream<List<RankedAlert>> watchAvailableAlerts();

  /// `GET /guard/alerts/{id}`
  Future<Alert> getAlert(String alertId);

  /// Seguimiento de la alerta asignada (estado + ubicación del usuario).
  Stream<Alert> watchAlert(String alertId);

  /// `POST /guard/alerts/{id}/accept`. Lanza `AlertTakenException`.
  Future<Alert> acceptAlert(String alertId);

  /// `PUT /guard/location`
  Future<void> updateMyLocation(GeoPoint location);

  /// `POST /guard/alerts/{id}/arrive`. Lanza `OutsideGeofenceException`.
  Future<Alert> markArrived(String alertId);
}
