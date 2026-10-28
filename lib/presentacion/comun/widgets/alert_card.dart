// CAPA: PRESENTACIÓN — sistema de diseño (componente compartido)
// Tarjeta de alerta (G-03 listado · A-04 escaladas · A-05 historial). No hace: no navega ni carga datos.

import 'package:flutter/material.dart';

import '../tema/theme.dart';
import '../formato.dart';
import '../../../dominio/dominio.dart';
import 'layout_widgets.dart';
import 'sl_card.dart';
import 'sl_chip.dart';

/// Tarjeta de alerta reutilizada en el listado del guardia (G-03), la
/// bandeja de escaladas (A-04) y el historial (A-05).
class AlertCard extends StatelessWidget {
  const AlertCard({
    super.key,
    required this.alert,
    required this.now,
    this.distanceMeters,
    this.onTap,
    this.showStatus = true,
  });

  final Alerta alert;
  final DateTime now;
  final double? distanceMeters;
  final VoidCallback? onTap;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final accent = alert.esUrgente
        ? AppColors.warning
        : (alert.estado.activa ? AppColors.emergency : null);

    return SlCard(
      accent: accent,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(Usuario.inicialesDe(alert.nombreUsuario), color: accent ?? AppColors.info),
              AppSpacing.gapSm,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(alert.nombreUsuario ?? 'Usuario', style: context.text.titleMedium),
                    Text(
                      '${Fmt.dateTime(alert.disparadaEn)} · ${Fmt.ago(alert.disparadaEn, now)}',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              if (distanceMeters != null)
                Text(Fmt.distance(distanceMeters!), style: context.text.titleMedium?.copyWith(color: AppColors.info)),
            ],
          ),
          AppSpacing.gapSm,
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              TriggerChip(alert.metodo),
              if (showStatus) StatusChip(alert.estado),
              if (alert.evidenciaIncompleta)
                const SlChip(label: 'Sin foto', color: AppColors.textSecondary, icon: Icons.no_photography_outlined),
              if (alert.razonEscalamiento != null)
                SlChip(label: alert.razonEscalamiento!.etiqueta, color: AppColors.warning, icon: Icons.schedule_rounded),
              if (alert.resolucion != null) SlChip.fromStyle(alert.resolucion!.style),
            ],
          ),
        ],
      ),
    );
  }
}
