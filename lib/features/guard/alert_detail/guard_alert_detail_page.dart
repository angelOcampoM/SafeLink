// G-04 Detalle de alerta · G-05 Aceptación
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/guard_alert_repository.dart';
import '../../../data/repositories/repository_exceptions.dart';
import '../../../shared/widgets/widgets.dart';

class GuardAlertDetailPage extends StatefulWidget {
  const GuardAlertDetailPage({super.key, required this.alertId});
  final String alertId;

  @override
  State<GuardAlertDetailPage> createState() => _GuardAlertDetailPageState();
}

class _GuardAlertDetailPageState extends State<GuardAlertDetailPage> {
  late final _repo = context.read<GuardAlertRepository>();
  late final Future<(Alert, Guard)> _data = Future.wait([
    _repo.getAlert(widget.alertId),
    _repo.getMyProfile(),
  ]).then((r) => (r[0] as Alert, r[1] as Guard));
  bool _accepting = false;

  Future<void> _accept() async {
    setState(() => _accepting = true);
    try {
      await _repo.acceptAlert(widget.alertId);
      if (mounted) context.pushReplacement(AppRoutes.guardNavigation(widget.alertId));
    } on AlertTakenException catch (e) {
      if (!mounted) return;
      context.showSnack(e.message);
      context.pop();
    } on AppException catch (e) {
      if (mounted) context.showSnack(e.message);
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de alerta')),
      body: FutureBuilder<(Alert, Guard)>(
        future: _data,
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          final (a, guard) = snap.data!;
          final here = guard.profile.lastLocation;
          final distance = (here != null && a.location != null) ? GeoUtils.distanceMeters(here, a.location!) : null;

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: AppSpacing.screen,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(a.userName ?? 'Usuario', style: context.text.headlineSmall)),
                        TriggerChip(a.triggerMethod),
                      ],
                    ),
                    AppSpacing.gapMd,
                    _EvidencePhoto(url: a.photoUrl),
                    AppSpacing.gapMd,
                    MapPlaceholder(
                      height: 200,
                      markers: [
                        const MapMarker(offset: Offset(-0.5, 0.5), color: AppColors.info, icon: Icons.shield_rounded),
                        MapMarker(offset: Offset.zero, color: AppColors.emergency, icon: Icons.person_pin_circle_rounded, heading: a.heading),
                      ],
                    ),
                    AppSpacing.gapMd,
                    SlCard(
                      child: Column(
                        children: [
                          InfoRow(icon: Icons.schedule_rounded, label: 'Hora', value: '${Fmt.time(a.triggeredAt)} · ${Fmt.ago(a.triggeredAt, DateTime.now())}'),
                          if (distance != null)
                            InfoRow(icon: Icons.near_me_outlined, label: 'Distancia', value: Fmt.distance(distance), valueColor: AppColors.info),
                          if (a.heading != null)
                            InfoRow(icon: Icons.explore_outlined, label: 'Rumbo de la cámara', value: '${a.heading}° ${GeoUtils.cardinal(a.heading!)}'),
                          InfoRow(icon: a.triggerMethod.style.icon, label: 'Método', value: a.triggerMethod.label),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: AppSpacing.screen,
                  child: SlButton(
                    label: 'Aceptar alerta',
                    icon: Icons.check_rounded,
                    loading: _accepting,
                    onPressed: a.status == AlertStatus.searching ? _accept : null,
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

class _EvidencePhoto extends StatelessWidget {
  const _EvidencePhoto({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      height: 200,
      color: AppColors.surface,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined, color: AppColors.textMuted, size: AppSizes.iconLg),
          AppSpacing.gapXs,
          Text(url == null ? 'Evidencia incompleta: sin foto' : 'No se pudo cargar la foto', style: context.text.bodyMedium),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: AppRadius.brMd,
      child: url == null
          ? placeholder
          : Image.network(
              url!,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
              loadingBuilder: (_, child, p) => p == null ? child : const SizedBox(height: 200, child: LoadingView()),
            ),
    );
  }
}
