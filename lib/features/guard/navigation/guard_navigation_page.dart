// G-06 Ruta hacia el usuario · G-07 Registro de llegada · Esperando confirmación
//
// TODO(G-06): sustituir MapPlaceholder por GoogleMap y abrir Google Maps
// con url_launcher (https://www.google.com/maps/dir/?api=1&destination=lat,lng).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/guard_alert_repository.dart';
import '../../../data/repositories/repository_exceptions.dart';
import '../../../shared/widgets/widgets.dart';

class GuardNavigationPage extends StatefulWidget {
  const GuardNavigationPage({super.key, required this.alertId});
  final String alertId;

  @override
  State<GuardNavigationPage> createState() => _GuardNavigationPageState();
}

class _GuardNavigationPageState extends State<GuardNavigationPage> {
  late final _repo = context.read<GuardAlertRepository>();
  late final Stream<Alert> _alert = _repo.watchAlert(widget.alertId);
  GeoPoint? _me;
  bool _arriving = false;

  @override
  void initState() {
    super.initState();
    _repo.getMyProfile().then((g) {
      if (mounted) setState(() => _me = g.profile.lastLocation);
    });
  }

  /// Solo en modo mock: avanza el 60 % de la distancia restante.
  Future<void> _simulateMove(GeoPoint target) async {
    final me = _me!;
    final next = GeoPoint(me.lat + (target.lat - me.lat) * 0.6, me.lng + (target.lng - me.lng) * 0.6);
    await _repo.updateMyLocation(next);
    setState(() => _me = next);
  }

  Future<void> _arrive() async {
    setState(() => _arriving = true);
    try {
      await _repo.markArrived(widget.alertId);
    } on OutsideGeofenceException catch (e) {
      if (mounted) context.showSnack('${e.message}. Faltan ${Fmt.distance(e.remainingMeters)}.');
    } on AppException catch (e) {
      if (mounted) context.showSnack(e.message);
    } finally {
      if (mounted) setState(() => _arriving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = context.read<AppConfig>();

    return Scaffold(
      appBar: AppBar(title: const Text('En camino')),
      body: StreamBuilder<Alert>(
        stream: _alert,
        builder: (context, snap) {
          final a = snap.data;
          if (a == null || _me == null) return const LoadingView();

          if (a.status == AlertStatus.guardArrived) return const _WaitingConfirmation();
          if (a.status == AlertStatus.closed) {
            return EmptyState(
              icon: Icons.check_circle_rounded,
              color: AppColors.success,
              title: 'Alerta atendida',
              message: '${a.userName ?? 'El usuario'} confirmó la atención. ¡Buen trabajo!',
              action: SlButton(label: 'Volver al listado', expand: false, onPressed: () => context.go(AppRoutes.guardHome)),
            );
          }

          final distance = GeoUtils.distanceMeters(_me!, a.location!);
          final inside = distance <= config.geofenceRadiusMeters;
          // Posición relativa del guardia en el mapa simulado (se acerca al centro).
          final f = (distance / 3000).clamp(0.08, 0.9).toDouble();

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: AppSpacing.screen,
                  children: [
                    MapPlaceholder(
                      height: 300,
                      showRoute: true,
                      radiusFraction: 0.08,
                      markers: [
                        MapMarker(offset: Offset(-f, f), color: AppColors.info, icon: Icons.shield_rounded),
                        const MapMarker(offset: Offset.zero, color: AppColors.emergency, icon: Icons.person_pin_circle_rounded),
                      ],
                    ),
                    AppSpacing.gapMd,
                    SlCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.userName ?? 'Usuario', style: context.text.titleMedium),
                                Text(a.userPhone == null ? '' : Fmt.phone(a.userPhone!), style: context.text.bodySmall),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(Fmt.distance(distance), style: context.text.displaySmall?.copyWith(color: inside ? AppColors.success : AppColors.info)),
                              Text(inside ? 'Dentro de la zona' : 'restantes', style: context.text.bodySmall),
                            ],
                          ),
                        ],
                      ),
                    ),
                    AppSpacing.gapMd,
                    SlButton(
                      label: 'Abrir en Google Maps',
                      icon: Icons.map_outlined,
                      variant: SlButtonVariant.secondary,
                      onPressed: () => context.showSnack('Pendiente (G-06): abrir Google Maps'),
                    ),
                    if (config.useMockData) ...[
                      AppSpacing.gapSm,
                      SlButton(
                        label: 'Simular acercamiento (mock)',
                        icon: Icons.directions_walk_rounded,
                        variant: SlButtonVariant.ghost,
                        onPressed: inside ? null : () => _simulateMove(a.location!),
                      ),
                    ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: AppSpacing.screen,
                  child: SlButton(
                    label: inside ? 'Llegué' : 'Llegué · faltan ${Fmt.distance(distance - config.geofenceRadiusMeters)}',
                    icon: Icons.where_to_vote_rounded,
                    variant: SlButtonVariant.success,
                    loading: _arriving,
                    onPressed: inside ? _arrive : null,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WaitingConfirmation extends StatelessWidget {
  const _WaitingConfirmation();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.hourglass_top_rounded,
      color: AppColors.info,
      title: 'Esperando confirmación',
      message: 'Registramos tu llegada. El usuario debe confirmar que fue atendido para cerrar la alerta.',
    );
  }
}
