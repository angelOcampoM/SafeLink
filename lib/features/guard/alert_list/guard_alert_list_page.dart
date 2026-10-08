// G-02 Recepción · G-03 Listado por cercanía y prioridad · Fuera de turno
//
// TODO(G-02): pantalla completa de "Alerta entrante" al recibir push FCM.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/alert_sorting.dart';
import '../../../data/models/guard_profile.dart';
import '../../../data/repositories/guard_alert_repository.dart';
import '../../../shared/widgets/widgets.dart';
import '../../auth/session_controller.dart';

class GuardAlertListPage extends StatefulWidget {
  const GuardAlertListPage({super.key});

  @override
  State<GuardAlertListPage> createState() => _GuardAlertListPageState();
}

class _GuardAlertListPageState extends State<GuardAlertListPage> {
  late final _repo = context.read<GuardAlertRepository>();
  late final Future<Guard> _profile = _repo.getMyProfile();
  late final Stream<List<RankedAlert>> _alerts = _repo.watchAvailableAlerts();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alertas cercanas'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_rounded),
            onPressed: context.read<SessionController>().logout,
          ),
        ],
      ),
      body: FutureBuilder<Guard>(
        future: _profile,
        builder: (context, profileSnap) {
          final guard = profileSnap.data;
          if (guard == null) return const LoadingView();

          if (!guard.isAvailableAt(DateTime.now())) {
            return EmptyState(
              icon: Icons.bedtime_outlined,
              title: 'Estás fuera de turno',
              message: 'Tu turno es de ${guard.profile.shiftStart} a ${guard.profile.shiftEnd}. No recibirás alertas hasta entonces.',
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                child: _ShiftBar(guard: guard),
              ),
              Expanded(
                child: StreamBuilder<List<RankedAlert>>(
                  stream: _alerts,
                  builder: (context, snap) {
                    final list = snap.data;
                    if (list == null) return const LoadingView();
                    if (list.isEmpty) {
                      return const EmptyState(
                        icon: Icons.shield_outlined,
                        color: AppColors.success,
                        title: 'Todo tranquilo',
                        message: 'No hay alertas en tu zona. Te avisaremos en cuanto llegue una.',
                      );
                    }
                    final now = DateTime.now();
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => AppSpacing.gapSm,
                      itemBuilder: (_, i) => AlertCard(
                        alert: list[i].alert,
                        now: now,
                        distanceMeters: list[i].distanceMeters,
                        showStatus: false,
                        onTap: () => context.push(AppRoutes.guardAlertDetail(list[i].alert.id)),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ShiftBar extends StatelessWidget {
  const _ShiftBar({required this.guard});
  final Guard guard;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SlChip(label: 'En turno', color: AppColors.success, icon: Icons.circle),
        AppSpacing.gapXs,
        Text('${guard.profile.shiftStart} – ${guard.profile.shiftEnd}', style: context.text.bodySmall),
        const Spacer(),
        Text('Radio ${(guard.profile.coverageRadiusMeters! / 1000).toStringAsFixed(1)} km', style: context.text.bodySmall),
      ],
    );
  }
}
