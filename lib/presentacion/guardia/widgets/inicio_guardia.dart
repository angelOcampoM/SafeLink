// CAPA: PRESENTACIÓN — widgets del guardia
// G-03 Dashboard de Inicio: alertas disponibles, mis métricas del periodo y alertas por hora.
// Solo pintan los valores que reciben.
// No hacen: no calculan métricas, no escuchan alertas ni navegan; avisan con callbacks.

import 'package:flutter/material.dart';

import '../../../dominio/dominio.dart';
import '../../comun/formato.dart';
import '../../comun/tema/theme.dart';
import '../../comun/widgets/widgets.dart';

/// Cuántas alertas hay ahora en la zona y cuántas son urgentes.
class ResumenDisponibles extends StatelessWidget {
  const ResumenDisponibles({super.key, required this.total, required this.urgentes});
  final int total;
  final int urgentes;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: MetricTile(label: 'Disponibles ahora', value: '$total', icon: Icons.notifications_rounded)),
        AppSpacing.gapSm,
        Expanded(
          child: MetricTile(
            label: 'Urgentes',
            value: '$urgentes',
            icon: Icons.vibration_rounded,
            color: urgentes > 0 ? AppColors.warning : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Mosaicos de mis métricas en el periodo elegido.
class MetricasPeriodoGuardia extends StatelessWidget {
  const MetricasPeriodoGuardia({super.key, required this.metricas, required this.tasaCierreConfirmado});
  final MetricasGuardia metricas;
  final double tasaCierreConfirmado;

  @override
  Widget build(BuildContext context) {
    final m = metricas;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: MetricTile(label: 'Atendidas', value: '${m.atendidas}', icon: Icons.verified_rounded, color: AppColors.success)),
            AppSpacing.gapSm,
            Expanded(child: MetricTile(label: 'Aceptación promedio', value: Fmt.duration(m.promedioAceptacionSeg), icon: Icons.timer_outlined)),
          ],
        ),
        AppSpacing.gapSm,
        Row(
          children: [
            Expanded(
              child: MetricTile(label: 'Llegada promedio', value: Fmt.duration(m.promedioLlegadaSeg), icon: Icons.directions_run_rounded),
            ),
            AppSpacing.gapSm,
            Expanded(child: MetricTile(label: 'Escaladas', value: '${m.escaladas}', icon: Icons.priority_high_rounded, color: AppColors.warning)),
          ],
        ),
        AppSpacing.gapSm,
        MetricTile(
          label: 'Cerradas con confirmación',
          value: Fmt.percent(tasaCierreConfirmado),
          icon: Icons.task_alt_rounded,
          color: AppColors.success,
        ),
      ],
    );
  }
}

/// Gráfica de barras de 24 h sin paquetes. La noche (20:00–05:59) va en ámbar.
class GraficaHorasGuardia extends StatelessWidget {
  const GraficaHorasGuardia({super.key, required this.valores});

  /// Exactamente 24 posiciones (0 = 00:00–00:59).
  final List<int> valores;

  static const _altoGrafica = AppSpacing.xxl * 2;
  static const _altoMinimo = AppSpacing.xxs;
  static const _separacion = EdgeInsets.symmetric(horizontal: AppSpacing.xxs / 2);
  static const _esquinas = BorderRadius.vertical(top: Radius.circular(AppRadius.sm / 2));
  static const _marcas = ['00', '06', '12', '18', '23'];

  static bool _esNoche(int h) => h >= 20 || h < 6;

  @override
  Widget build(BuildContext context) {
    final max = valores.fold<int>(1, (a, b) => b > a ? b : a);
    return Column(
      children: [
        SizedBox(
          height: _altoGrafica,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var h = 0; h < 24; h++)
                Expanded(
                  child: Tooltip(
                    message: '${ReglaTurno.deHoraMinuto(h, 0)} · ${valores[h]} ${valores[h] == 1 ? 'alerta' : 'alertas'}',
                    child: Container(
                      margin: _separacion,
                      height: _altoMinimo + (_altoGrafica - _altoMinimo) * valores[h] / max,
                      decoration: BoxDecoration(
                        color: _esNoche(h) ? AppColors.warning : AppColors.info,
                        borderRadius: _esquinas,
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
          children: [for (final l in _marcas) Text(l, style: context.text.labelSmall)],
        ),
      ],
    );
  }
}
