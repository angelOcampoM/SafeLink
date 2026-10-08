import 'dart:math';

import '../models/models.dart';

/// Datos ficticios de Morelos (Emiliano Zapata / Cuernavaca) – sección 9.
///
/// Cuentas de prueba (contraseña de todas: `SafeLink1`):
/// | Correo                     | Rol                 | Notas                         |
/// |----------------------------|---------------------|-------------------------------|
/// | usuario@safelink.mx        | Usuario protegido   | Sin alertas activas           |
/// | rosa.diaz@mail.com         | Usuario protegido   | 2 falsas alarmas              |
/// | bloqueado@safelink.mx      | Usuario protegido   | Bloqueado 5 días más          |
/// | guardia@safelink.mx        | Guardia             | En turno, con alertas cerca   |
/// | guardia.noche@safelink.mx  | Guardia             | Turno 22:00 → 06:00           |
/// | admin@safelink.mx          | Administrador       |                               |
class MockSeed {
  MockSeed(this.now);

  final DateTime now;
  final _rnd = Random(7);

  static const password = 'SafeLink1';
  static const center = GeoPoint(18.8400, -99.1800);

  /// Ubicación simulada del teléfono del usuario protegido.
  static const userDeviceLocation = GeoPoint(18.8452, -99.1771);

  final users = <AppUser>[];
  final guards = <GuardProfile>[];
  final alerts = <Alert>[];

  MockSeed build() {
    _users();
    _guards();
    _alerts();
    return this;
  }

  // ── Usuarios ──────────────────────────────────────────────────────
  void _users() {
    final created = now.subtract(const Duration(days: 60));
    users.addAll([
      AppUser(id: 'adm-1', name: 'Mariana Ortega Ruiz', email: 'admin@safelink.mx', phone: '7771002030', role: UserRole.admin, createdAt: created),
      // Guardias
      AppUser(id: 'grd-1', name: 'Carlos Hernández López', email: 'guardia@safelink.mx', phone: '7772345610', role: UserRole.guard, createdAt: created),
      AppUser(id: 'grd-2', name: 'Daniela Salgado Pérez', email: 'daniela.salgado@safelink.mx', phone: '7773456721', role: UserRole.guard, createdAt: created),
      AppUser(id: 'grd-3', name: 'Jorge Ocampo Bahena', email: 'jorge.ocampo@safelink.mx', phone: '7774567832', role: UserRole.guard, createdAt: created),
      AppUser(id: 'grd-4', name: 'Ramiro Villalobos Cruz', email: 'guardia.noche@safelink.mx', phone: '7775678943', role: UserRole.guard, createdAt: created),
      AppUser(id: 'grd-5', name: 'Luis Arturo Nava Díaz', email: 'luis.nava@safelink.mx', phone: '7776789054', role: UserRole.guard, isActive: false, createdAt: created),
      // Usuarios protegidos
      AppUser(id: 'usr-1', name: 'Fernanda Morales Gil', email: 'usuario@safelink.mx', phone: '7771234567', role: UserRole.protectedUser, shakeEnabled: true, createdAt: created),
      AppUser(id: 'usr-2', name: 'Rosa María Díaz Toledo', email: 'rosa.diaz@mail.com', phone: '7772233445', role: UserRole.protectedUser, falseAlarmCount: 2, createdAt: created),
      AppUser(id: 'usr-3', name: 'Héctor Jaimes Rosales', email: 'hector.jaimes@mail.com', phone: '7773344556', role: UserRole.protectedUser, createdAt: created),
      AppUser(id: 'usr-4', name: 'Iván Castañeda Soto', email: 'bloqueado@safelink.mx', phone: '7774455667', role: UserRole.protectedUser, falseAlarmCount: 3, blockedUntil: now.add(const Duration(days: 5)), createdAt: created),
    ]);
  }

  // ── Guardias ──────────────────────────────────────────────────────
  void _guards() {
    String hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    // Turnos relativos a "ahora" para que la demo siempre tenga guardias en turno.
    final onStart = hhmm(now.subtract(const Duration(hours: 2)));
    final onEnd = hhmm(now.add(const Duration(hours: 6)));
    final offStart = hhmm(now.add(const Duration(hours: 3)));
    final offEnd = hhmm(now.add(const Duration(hours: 11)));

    guards.addAll([
      GuardProfile(userId: 'grd-1', shiftStart: onStart, shiftEnd: onEnd, coverageCenter: center, coverageRadiusMeters: 4000, lastLocation: const GeoPoint(18.8385, -99.1835), lastLocationAt: now),
      GuardProfile(userId: 'grd-2', shiftStart: onStart, shiftEnd: onEnd, coverageCenter: const GeoPoint(18.9186, -99.2342), coverageRadiusMeters: 5000, lastLocation: const GeoPoint(18.9150, -99.2300), lastLocationAt: now),
      GuardProfile(userId: 'grd-3', shiftStart: onStart, shiftEnd: onEnd, coverageCenter: const GeoPoint(18.8600, -99.1950), coverageRadiusMeters: 3000, lastLocation: const GeoPoint(18.8590, -99.1940), lastLocationAt: now),
      // Turno nocturno que cruza medianoche (fuera de turno en horario diurno).
      const GuardProfile(userId: 'grd-4', shiftStart: '22:00', shiftEnd: '06:00', coverageCenter: center, coverageRadiusMeters: 4000),
      GuardProfile(userId: 'grd-5', shiftStart: offStart, shiftEnd: offEnd, coverageCenter: center, coverageRadiusMeters: 2000),
    ]);
  }

  // ── Alertas ───────────────────────────────────────────────────────
  void _alerts() {
    GeoPoint near(double dLat, double dLng) => GeoPoint(center.lat + dLat, center.lng + dLng);
    DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));
    String photo(String seed) => 'https://picsum.photos/seed/$seed/640/420';

    // Disponibles para el guardia grd-1 (searching)
    alerts.addAll([
      Alert(id: 'alt-101', userId: 'usr-3', userName: 'Héctor Jaimes Rosales', userPhone: '7773344556', status: AlertStatus.searching, triggerMethod: TriggerMethod.shake, triggeredAt: ago(1), location: near(0.0110, 0.0060), heading: 40, photoUrl: photo('sl101')),
      Alert(id: 'alt-102', userId: 'usr-2', userName: 'Rosa María Díaz Toledo', userPhone: '7772233445', status: AlertStatus.searching, triggerMethod: TriggerMethod.tap, triggeredAt: ago(2), location: near(-0.0020, 0.0015), heading: 185, photoUrl: photo('sl102')),
      Alert(id: 'alt-103', userId: 'usr-3', userName: 'Héctor Jaimes Rosales', userPhone: '7773344556', status: AlertStatus.searching, triggerMethod: TriggerMethod.hold, triggeredAt: ago(4), location: near(0.0140, -0.0120), heading: 300, evidenceIncomplete: true),
      Alert(id: 'alt-104', userId: 'usr-2', userName: 'Rosa María Díaz Toledo', userPhone: '7772233445', status: AlertStatus.searching, triggerMethod: TriggerMethod.tap, triggeredAt: ago(0), location: near(0.0050, 0.0040), heading: 90, photoUrl: photo('sl104')),
    ]);

    // Resto de estados activos
    alerts.addAll([
      Alert(id: 'alt-201', userId: 'usr-3', userName: 'Héctor Jaimes Rosales', status: AlertStatus.pendingLocation, triggerMethod: TriggerMethod.tap, triggeredAt: ago(1), photoUrl: photo('sl201')),
      Alert(id: 'alt-202', userId: 'usr-2', userName: 'Rosa María Díaz Toledo', guardId: 'grd-2', guardName: 'Daniela Salgado Pérez', status: AlertStatus.inProgress, triggerMethod: TriggerMethod.hold, triggeredAt: ago(9), acceptedAt: ago(8), location: near(0.0700, -0.0500), heading: 120, photoUrl: photo('sl202'), etaSeconds: 240),
      Alert(id: 'alt-203', userId: 'usr-3', userName: 'Héctor Jaimes Rosales', guardId: 'grd-3', guardName: 'Jorge Ocampo Bahena', status: AlertStatus.guardArrived, triggerMethod: TriggerMethod.tap, triggeredAt: ago(14), acceptedAt: ago(13), arrivedAt: ago(3), location: near(0.0190, -0.0140), heading: 15, photoUrl: photo('sl203')),
      Alert(id: 'alt-204', userId: 'usr-2', userName: 'Rosa María Díaz Toledo', status: AlertStatus.noResponse, triggerMethod: TriggerMethod.tap, triggeredAt: ago(6), location: near(0.0900, 0.0400), heading: 220, photoUrl: photo('sl204')),
    ]);

    // Escaladas (las dos razones) y resuelta por admin
    alerts.addAll([
      Alert(id: 'alt-301', userId: 'usr-3', userName: 'Héctor Jaimes Rosales', userPhone: '7773344556', status: AlertStatus.escalated, escalationReason: EscalationReason.noResponse, triggerMethod: TriggerMethod.shake, triggeredAt: ago(22), location: near(0.0300, 0.0250), heading: 75, photoUrl: photo('sl301')),
      Alert(id: 'alt-302', userId: 'usr-2', userName: 'Rosa María Díaz Toledo', userPhone: '7772233445', guardId: 'grd-1', guardName: 'Carlos Hernández López', status: AlertStatus.escalated, escalationReason: EscalationReason.noConfirmation, triggerMethod: TriggerMethod.tap, triggeredAt: ago(48), acceptedAt: ago(47), arrivedAt: ago(38), location: near(-0.0060, 0.0080), heading: 260, photoUrl: photo('sl302')),
      Alert(id: 'alt-303', userId: 'usr-4', userName: 'Iván Castañeda Soto', guardId: 'grd-1', guardName: 'Carlos Hernández López', status: AlertStatus.resolvedByAdmin, escalationReason: EscalationReason.noConfirmation, resolution: Resolution.falseAlarm, triggerMethod: TriggerMethod.tap, triggeredAt: ago(60 * 26), acceptedAt: ago(60 * 26 - 1), arrivedAt: ago(60 * 26 - 9), closedAt: ago(60 * 25), location: near(0.0020, -0.0030), heading: 0, photoUrl: photo('sl303')),
    ]);

    // Historial: 36 alertas cerradas en distintas horas de los últimos 30 días.
    const guardNames = {'grd-1': 'Carlos Hernández López', 'grd-2': 'Daniela Salgado Pérez', 'grd-3': 'Jorge Ocampo Bahena'};
    const userNames = {'usr-1': 'Fernanda Morales Gil', 'usr-2': 'Rosa María Díaz Toledo', 'usr-3': 'Héctor Jaimes Rosales'};
    // Más alertas en la noche para que la gráfica por hora tenga forma.
    const hours = [0, 1, 2, 7, 8, 12, 14, 17, 18, 19, 20, 20, 21, 21, 22, 22, 23, 23];
    for (var i = 0; i < 36; i++) {
      final g = guardNames.keys.elementAt(i % 3);
      final u = userNames.keys.elementAt(_rnd.nextInt(3));
      final day = now.subtract(Duration(days: 1 + _rnd.nextInt(29)));
      final t = DateTime(day.year, day.month, day.day, hours[i % hours.length], _rnd.nextInt(60));
      final accept = 20 + _rnd.nextInt(160); // segundos
      final arrive = 240 + _rnd.nextInt(600); // segundos
      alerts.add(Alert(
        id: 'alt-h${i.toString().padLeft(2, '0')}',
        userId: u,
        userName: userNames[u],
        guardId: g,
        guardName: guardNames[g],
        status: AlertStatus.closed,
        triggerMethod: TriggerMethod.values[i % 3],
        triggeredAt: t,
        acceptedAt: t.add(Duration(seconds: accept)),
        arrivedAt: t.add(Duration(seconds: accept + arrive)),
        closedAt: t.add(Duration(seconds: accept + arrive + 180)),
        location: near((_rnd.nextDouble() - 0.5) * 0.06, (_rnd.nextDouble() - 0.5) * 0.06),
        heading: _rnd.nextInt(360),
        photoUrl: i % 7 == 0 ? null : photo('slh$i'),
        evidenceIncomplete: i % 7 == 0,
      ));
    }
  }
}
