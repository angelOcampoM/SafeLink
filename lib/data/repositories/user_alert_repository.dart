import '../models/alert.dart';
import '../models/enums.dart';
import '../models/geo_point.dart';

/// Alertas desde el punto de vista del usuario protegido (U-03 a U-09).
abstract interface class UserAlertRepository {
  /// `POST /alerts`. Si [location] es null queda en `pending_location`.
  /// Si [photoPath] es null se marca `evidenceIncomplete`.
  Future<Alert> createAlert({
    required TriggerMethod triggerMethod,
    required DateTime triggeredAt,
    GeoPoint? location,
    int? heading,
    String? photoPath,
  });

  /// Alerta activa del usuario, actualizada en tiempo real
  /// (eventos `alert.accepted`, `alert.eta`, `alert.arrived`).
  /// Emite `null` cuando no hay alerta activa.
  Stream<Alert?> watchActiveAlert();

  /// `POST /alerts/{id}/locations` (U-07).
  Future<void> sendLocation(String alertId, GeoPoint location);

  /// `POST /alerts/{id}/confirm` (U-09). Solo en `guard_arrived`.
  Future<Alert> confirmAttention(String alertId);
}
