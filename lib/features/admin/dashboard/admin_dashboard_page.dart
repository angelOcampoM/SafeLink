// A-06 Métricas generales · A-08 Usuarios bloqueados
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../shared/widgets/widgets.dart';
import '../../auth/session_controller.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  late final _repo = context.read<AdminRepository>();
  late Future<GeneralMetrics> _metrics = _repo.getMetrics();
  late Future<List<AppUser>> _blocked = _repo.getBlockedUsers();

  Future<void> _reload() async {
    setState(() {
      _metrics = _repo.getMetrics();
      _blocked = _repo.getBlockedUsers();
    });
    await _metrics;
  }

  Future<void> _unblock(AppUser u) async {
    await _repo.unblockUser(u.id);
    if (!mounted) return;
    context.showSnack('Se retiró el bloqueo de ${u.name}');
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel general'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_rounded),
            onPressed: context.read<SessionController>().logout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: AppSpacing.screen,
          children: [
            FutureBuilder<GeneralMetrics>(
              future: _metrics,
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox(height: 240, child: LoadingView());
                final m = snap.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeader('Últimos 30 días'),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: AppSpacing.sm,
                      crossAxisSpacing: AppSpacing.sm,
                      childAspectRatio: 1.25,
                      children: [
                        MetricTile(label: 'Alertas totales', value: '${m.totalAlerts}', icon: Icons.notifications_rounded),
                        MetricTile(label: 'Aceptación promedio', value: Fmt.duration(m.avgAcceptanceSeconds), icon: Icons.timer_outlined),
                        MetricTile(label: 'Llegada promedio', value: Fmt.duration(m.avgArrivalSeconds), icon: Icons.directions_run_rounded, color: AppColors.success),
                        MetricTile(label: 'Sin respuesta', value: Fmt.percent(m.noResponseRate), icon: Icons.timer_off_outlined, color: AppColors.warning),
                      ],
                    ),
                    AppSpacing.gapLg,
                    const SectionHeader('Alertas por hora'),
                    SlCard(child: _HourChart(values: m.alertsByHour)),
                  ],
                );
              },
            ),
            AppSpacing.gapLg,
            const SectionHeader('Usuarios bloqueados'),
            FutureBuilder<List<AppUser>>(
              future: _blocked,
              builder: (context, snap) {
                final list = snap.data;
                if (list == null) return const LoadingView();
                if (list.isEmpty) {
                  return const SlBanner(type: SlBannerType.success, message: 'No hay usuarios bloqueados.');
                }
                return Column(
                  children: [
                    for (final u in list) ...[
                      SlCard(
                        child: Row(
                          children: [
                            InitialsAvatar(u.initials, color: AppColors.warning),
                            AppSpacing.gapSm,
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(u.name, style: context.text.titleMedium),
                                  Text('${u.falseAlarmCount} falsas alarmas · hasta ${Fmt.date(u.blockedUntil!)}', style: context.text.bodySmall),
                                ],
                              ),
                            ),
                            TextButton(onPressed: () => _unblock(u), child: const Text('Desbloquear')),
                          ],
                        ),
                      ),
                      AppSpacing.gapSm,
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Gráfica de barras mínima (24 h) sin dependencias.
/// TODO(A-06): si el equipo decide usar fl_chart, reemplazar aquí.
class _HourChart extends StatelessWidget {
  const _HourChart({required this.values});
  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final max = values.fold<int>(1, (a, b) => b > a ? b : a);
    return Column(
      children: [
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var h = 0; h < 24; h++)
                Expanded(
                  child: Tooltip(
                    message: '${h.toString().padLeft(2, '0')}:00 · ${values[h]} alertas',
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      height: 4 + 116 * values[h] / max,
                      decoration: BoxDecoration(
                        color: (h >= 20 || h < 6) ? AppColors.warning : AppColors.info,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        AppSpacing.gapXs,
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final l in ['00', '06', '12', '18', '23']) Text(l, style: context.text.labelSmall),
          ],
        ),
      ],
    );
  }
}
