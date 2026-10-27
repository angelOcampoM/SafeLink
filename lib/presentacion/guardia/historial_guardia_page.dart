// CAPA: PRESENTACIÓN — View
// Historial de alertas atendidas por el guardia + métricas personales
// Métricas arriba, lista abajo, pull-to-refresh y detalle en hoja inferior.

import 'package:flutter/material.dart';

import '../comun/formato.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'historial_guardia_view_model.dart';

class HistorialGuardiaPage extends StatefulWidget {
  const HistorialGuardiaPage({super.key, required this.viewModel});
  final HistorialGuardiaViewModel viewModel;

  @override
  State<HistorialGuardiaPage> createState() => _HistorialGuardiaPageState();
}

class _HistorialGuardiaPageState extends State<HistorialGuardiaPage> {
  late final HistorialGuardiaViewModel vm = widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.cargar();
  }

  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alertas atendidas')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => SlStateView<HistorialGuardia>(
          estado: vm.estado,
          onRetry: vm.cargar,
          onRefresh: vm.cargar,
          empty: const EmptyState(
            icon: Icons.history_toggle_off_rounded,
            title: 'Aún no atiendes alertas',
            message: 'Cuando cierres tu primera alerta aparecerá aquí con tus tiempos.',
          ),
          builder: (context, h) {
            final m = h.metricas;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppSpacing.screen,
              children: [
                const SectionHeader('Mis métricas'),
                Row(
                  children: [
                    Expanded(child: MetricTile(label: 'Atendidas', value: '${m.atendidas}', icon: Icons.verified_rounded, color: AppColors.success)),
                    AppSpacing.gapSm,
                    Expanded(child: MetricTile(label: 'Aceptación', value: Fmt.duration(m.promedioAceptacionSeg), icon: Icons.timer_outlined)),
                  ],
                ),
                AppSpacing.gapSm,
                Row(
                  children: [
                    Expanded(child: MetricTile(label: 'Llegada', value: Fmt.duration(m.promedioLlegadaSeg), icon: Icons.directions_run_rounded)),
                    AppSpacing.gapSm,
                    Expanded(child: MetricTile(label: 'Escaladas', value: '${m.escaladas}', icon: Icons.priority_high_rounded, color: AppColors.warning)),
                  ],
                ),
                AppSpacing.gapLg,
                SectionHeader('Historial (${h.alertas.length})'),
                for (final a in h.alertas) ...[
                  AlertCard(
                    alert: a,
                    now: vm.ahora,
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => AlertDetailSheet(alert: a),
                    ),
                  ),
                  AppSpacing.gapSm,
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
