// CAPA: PRESENTACIÓN — sistema de diseño (componente compartido)
// Hoja inferior con el detalle de una alerta del historial (usuario, guardia y admin).
// No hace: no carga datos ni resuelve la alerta.

import 'package:flutter/material.dart';

import '../../../dominio/dominio.dart';
import '../formato.dart';
import '../tema/theme.dart';
import 'layout_widgets.dart';
import 'sl_banner.dart';
import 'sl_chip.dart';

/// Detalle simple de una alerta del historial (reutilizable por cualquier rol).
class AlertDetailSheet extends StatelessWidget {
  const AlertDetailSheet({super.key, required this.alert});
  final Alerta alert;

  @override
  Widget build(BuildContext context) {
    final a = alert;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(Fmt.dateTime(a.disparadaEn), style: context.text.titleLarge)),
                StatusChip(a.estado),
              ],
            ),
            AppSpacing.gapSm,
            InfoRow(icon: a.metodo.style.icon, label: 'Método', value: a.metodo.etiqueta),
            InfoRow(icon: Icons.person_outline_rounded, label: 'Usuario', value: a.nombreUsuario ?? '—'),
            InfoRow(icon: Icons.shield_outlined, label: 'Guardia', value: a.nombreGuardia ?? 'Sin asignar'),
            if (a.aceptadaEn != null)
              InfoRow(
                icon: Icons.timer_outlined,
                label: 'Aceptación',
                value: '${Fmt.dateTime(a.aceptadaEn!)} · ${Fmt.duration(a.aceptadaEn!.difference(a.disparadaEn).inSeconds)}',
              ),
            if (a.llegadaEn != null)
              InfoRow(
                icon: Icons.directions_run_rounded,
                label: 'Llegada',
                value: '${Fmt.dateTime(a.llegadaEn!)} · ${Fmt.duration(a.llegadaEn!.difference(a.aceptadaEn ?? a.disparadaEn).inSeconds)}',
              ),
            if (a.cerradaEn != null)
              InfoRow(icon: Icons.check_circle_outline_rounded, label: 'Cierre', value: Fmt.dateTime(a.cerradaEn!)),
            if (a.razonEscalamiento != null)
              InfoRow(icon: Icons.priority_high_rounded, label: 'Escalada', value: a.razonEscalamiento!.etiqueta, valueColor: AppColors.warning),
            if (a.resolucion != null)
              InfoRow(icon: a.resolucion!.style.icon, label: 'Resolución', value: a.resolucion!.etiqueta, valueColor: a.resolucion!.style.color),
            if (a.fotoUrl != null) ...[
              AppSpacing.gapSm,
              ClipRRect(
                borderRadius: AppRadius.brMd,
                child: Image.network(
                  a.fotoUrl!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 160,
                    color: AppColors.surfaceElevated,
                    alignment: Alignment.center,
                    child: Text('No se pudo cargar la evidencia', style: context.text.bodySmall),
                  ),
                ),
              ),
            ],
            if (a.evidenciaIncompleta) ...[
              AppSpacing.gapSm,
              const SlBanner(type: SlBannerType.warning, message: 'Evidencia incompleta: se envió sin foto.'),
            ],
            if (a.notaAdmin != null) ...[
              AppSpacing.gapSm,
              Text('NOTA ADMINISTRATIVA', style: context.text.labelSmall?.copyWith(letterSpacing: 1.2)),
              AppSpacing.gapXs,
              Container(
                width: double.infinity,
                padding: AppSpacing.card,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: AppRadius.brMd,
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(a.notaAdmin!, style: context.text.bodyMedium),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
