// CAPA: PRESENTACIÓN — View
// A-07 Métricas por guardia (filtro por rango de fechas)
// Tarjeta de perfil del guardia, chip de rango con DateRangePicker, mosaico
// 2×2 de métricas y sus últimas 3 alertas atendidas. No calcula ni llama repositorios.

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
      appBar: AppBar(title: const Text('Métricas del guardia')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => RefreshIndicator(
          onRefresh: vm.cargar,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.screen,
            children: [
              if (vm.guardia != null) ...[
                _TarjetaGuardia(vm: vm),
                AppSpacing.gapMd,
              ],
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
              AppSpacing.gapLg,
              const SectionHeader('Últimas alertas atendidas'),
              _UltimasAtendidas(vm: vm),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de perfil: nombre, correo, estado (chip) y turno.
class _TarjetaGuardia extends StatelessWidget {
  const _TarjetaGuardia({required this.vm});
  final MetricasGuardiaViewModel vm;

  @override
  Widget build(BuildContext context) {
    final g = vm.guardia!;
    final e = vm.estadoDe(g);
    final color = !e.activo ? AppColors.textMuted : (e.enTurno ? AppColors.success : AppColors.textSecondary);

    return SlCard(
      child: Row(
        children: [
          InitialsAvatar(g.usuario.iniciales),
          AppSpacing.gapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.usuario.nombre, style: context.text.titleMedium),
                Text(g.usuario.correo, style: context.text.bodySmall),
                AppSpacing.gapXs,
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SlChip(label: e.etiqueta, color: color),
                    Text('${g.perfil.inicioTurno} – ${g.perfil.finTurno}', style: context.text.bodySmall),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hasta 3 alertas con llegada del guardia, más recientes primero.
class _UltimasAtendidas extends StatelessWidget {
  const _UltimasAtendidas({required this.vm});
  final MetricasGuardiaViewModel vm;

  @override
  Widget build(BuildContext context) {
    final lista = vm.ultimasAtendidas;
    if (lista.isEmpty) return const SlBanner(message: 'Sin alertas atendidas todavía.');
    return Column(
      children: [
        for (final a in lista) ...[
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
  }
}
