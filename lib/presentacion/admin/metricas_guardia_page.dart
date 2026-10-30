// CAPA: PRESENTACIÓN — View
// A-07 Métricas por guardia (filtro por rango de fechas)
// Chip de rango con DateRangePicker, mosaico 2×2 de métricas y los cuatro
// estados de vista. No calcula métricas ni llama repositorios.

import 'package:flutter/material.dart';

import '../comun/estado_vista.dart';
import '../comun/formato.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'metricas_guardia_view_model.dart';

class MetricasGuardiaPage extends StatefulWidget {
  const MetricasGuardiaPage({super.key, required this.viewModel});
  final MetricasGuardiaViewModel viewModel;

  @override
  State<MetricasGuardiaPage> createState() => _MetricasGuardiaPageState();
}

class _MetricasGuardiaPageState extends State<MetricasGuardiaPage> {
  late final MetricasGuardiaViewModel vm = widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.iniciar();
  }

  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  Future<void> _elegirRango() async {
    final hoy = vm.ahora;
    final r = await showDateRangePicker(
      context: context,
      firstDate: hoy.subtract(const Duration(days: 365)),
      lastDate: hoy,
      initialDateRange: vm.desde == null ? null : DateTimeRange(start: vm.desde!, end: vm.hasta!),
      helpText: 'Rango de fechas',
    );
    if (r != null) vm.cambiarRango(r.start, r.end);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ListenableBuilder(
          listenable: vm,
          builder: (_, __) => Text(vm.nombreGuardia.isEmpty ? 'Métricas del guardia' : 'Métricas de ${vm.nombreGuardia}'),
        ),
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => RefreshIndicator(
          onRefresh: vm.cargar,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.screen,
            children: [
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.date_range_rounded, size: AppSizes.iconSm),
                    label: Text(vm.desde == null ? 'Todas las fechas' : '${Fmt.date(vm.desde!)} – ${Fmt.date(vm.hasta!)}'),
                    onPressed: _elegirRango,
                  ),
                  if (vm.desde != null)
                    ActionChip(
                      avatar: const Icon(Icons.filter_alt_off_outlined, size: AppSizes.iconSm),
                      label: const Text('Limpiar'),
                      onPressed: vm.limpiarRango,
                    ),
                ],
              ),
              AppSpacing.gapMd,
              switch (vm.estado) {
                Cargando() => const SizedBox(height: 240, child: LoadingView()),
                Vacio() => const SlBanner(message: 'Sin alertas en este periodo para este guardia.'),
                ErrorVista(:final mensaje) => SlBanner(
                    type: SlBannerType.danger,
                    message: mensaje,
                    action: TextButton.icon(onPressed: vm.cargar, icon: const Icon(Icons.refresh_rounded), label: const Text('Reintentar')),
                  ),
                Listo(datos: final m) => GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: AppSpacing.sm,
                    crossAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 1.25,
                    children: [
                      MetricTile(label: 'Alertas atendidas', value: '${m.atendidas}', icon: Icons.notifications_rounded),
                      MetricTile(label: 'Aceptación promedio', value: Fmt.duration(m.promedioAceptacionSeg), icon: Icons.timer_outlined),
                      MetricTile(label: 'Llegada promedio', value: Fmt.duration(m.promedioLlegadaSeg), icon: Icons.directions_run_rounded, color: AppColors.success),
                      MetricTile(label: 'Alertas escaladas', value: '${m.escaladas}', icon: Icons.warning_amber_rounded, color: AppColors.warning),
                    ],
                  ),
              },
            ],
          ),
        ),
      ),
    );
  }
}
