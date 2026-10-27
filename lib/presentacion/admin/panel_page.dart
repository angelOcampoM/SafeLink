// CAPA: PRESENTACIÓN — View
// A-06 Métricas generales · A-08 Usuarios bloqueados
// Selector de periodo, mosaicos de métricas, gráfica por hora y bloqueados.
// No calcula métricas ni llama repositorios.

import 'package:flutter/material.dart';

import '../comun/estado_vista.dart';
import '../comun/formato.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'panel_view_model.dart';

class PanelPage extends StatefulWidget {
  const PanelPage({super.key, required this.viewModel});
  final PanelViewModel viewModel;

  @override
  State<PanelPage> createState() => _PanelPageState();
}

class _PanelPageState extends State<PanelPage> {
  late final PanelViewModel vm = widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.addListener(_alCambiar);
    vm.cargar();
  }

  @override
  void dispose() {
    vm.removeListener(_alCambiar);
    vm.dispose();
    super.dispose();
  }

  void _alCambiar() {
    if (vm.mensaje != null) context.showSnack(vm.mensaje!);
    vm.consumirMensaje();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel general'),
        actions: [
          IconButton(tooltip: 'Cerrar sesión', icon: const Icon(Icons.logout_rounded), onPressed: vm.cerrarSesion),
        ],
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
                  for (final p in PeriodoPanel.values)
                    ChoiceChip(label: Text(p.etiqueta), selected: vm.periodo == p, onSelected: (_) => vm.cambiarPeriodo(p)),
                ],
              ),
              AppSpacing.gapMd,
              SectionHeader('Últimos ${vm.periodo.etiqueta}'),
              _Metricas(vm: vm),
              AppSpacing.gapLg,
              const SectionHeader('Usuarios bloqueados'),
              _Bloqueados(vm: vm),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metricas extends StatelessWidget {
  const _Metricas({required this.vm});
  final PanelViewModel vm;

  @override
  Widget build(BuildContext context) {
    return switch (vm.metricas) {
      Cargando() => const SizedBox(height: 240, child: LoadingView()),
      Vacio() => const SlBanner(message: 'No hubo alertas en este periodo.'),
      ErrorVista(:final mensaje) => SlBanner(
          type: SlBannerType.danger,
          message: mensaje,
          action: TextButton.icon(onPressed: vm.cargar, icon: const Icon(Icons.refresh_rounded), label: const Text('Reintentar')),
        ),
      Listo(datos: final m) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 1.25,
              children: [
                MetricTile(label: 'Alertas totales', value: '${m.totalAlertas}', icon: Icons.notifications_rounded),
                MetricTile(label: 'Aceptación promedio', value: Fmt.duration(m.promedioAceptacionSeg), icon: Icons.timer_outlined),
                MetricTile(label: 'Llegada promedio', value: Fmt.duration(m.promedioLlegadaSeg), icon: Icons.directions_run_rounded, color: AppColors.success),
                MetricTile(label: 'Sin respuesta', value: Fmt.percent(m.tasaSinRespuesta), icon: Icons.timer_off_outlined, color: AppColors.warning),
              ],
            ),
            AppSpacing.gapSm,
            MetricTile(label: 'Cerradas con confirmación', value: Fmt.percent(m.tasaCierreConfirmado), icon: Icons.verified_rounded, color: AppColors.success),
            AppSpacing.gapLg,
            const SectionHeader('Alertas por hora'),
            SlCard(child: _GraficaHoras(valores: m.alertasPorHora)),
          ],
        ),
    };
  }
}

class _Bloqueados extends StatelessWidget {
  const _Bloqueados({required this.vm});
  final PanelViewModel vm;

  @override
  Widget build(BuildContext context) {
    return switch (vm.bloqueados) {
      Cargando() => const LoadingView(),
      Vacio() => const SlBanner(type: SlBannerType.success, message: 'No hay usuarios bloqueados.'),
      ErrorVista(:final mensaje) => SlBanner(
          type: SlBannerType.danger,
          message: mensaje,
          action: TextButton.icon(onPressed: vm.cargar, icon: const Icon(Icons.refresh_rounded), label: const Text('Reintentar')),
        ),
      Listo(datos: final lista) => Column(
          children: [
            for (final u in lista) ...[
              SlCard(
                child: Row(
                  children: [
                    InitialsAvatar(u.iniciales, color: AppColors.warning),
                    AppSpacing.gapSm,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(u.nombre, style: context.text.titleMedium),
                          Text('${u.falsasAlarmas} falsas alarmas · hasta ${Fmt.date(u.bloqueadoHasta!)}', style: context.text.bodySmall),
                        ],
                      ),
                    ),
                    TextButton(onPressed: () => vm.desbloquear(u), child: const Text('Desbloquear')),
                  ],
                ),
              ),
              AppSpacing.gapSm,
            ],
          ],
        ),
    };
  }
}

/// Gráfica de barras mínima (24 h) sin dependencias.
/// TODO(A-06): si el equipo decide usar fl_chart, reemplazar aquí.
class _GraficaHoras extends StatelessWidget {
  const _GraficaHoras({required this.valores});
  final List<int> valores;

  @override
  Widget build(BuildContext context) {
    final max = valores.fold<int>(1, (a, b) => b > a ? b : a);
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
                    message: '${h.toString().padLeft(2, '0')}:00 · ${valores[h]} alertas',
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      height: 4 + 116 * valores[h] / max,
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
