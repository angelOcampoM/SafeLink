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
              InfoRow(icon: Icons.timer_outlined, label: 'Aceptación', value: Fmt.duration(a.aceptadaEn!.difference(a.disparadaEn).inSeconds)),
            if (a.llegadaEn != null)
              InfoRow(
                icon: Icons.directions_run_rounded,
                label: 'Llegada',
                value: Fmt.duration(a.llegadaEn!.difference(a.aceptadaEn ?? a.disparadaEn).inSeconds),
              ),
            if (a.razonEscalamiento != null)
              InfoRow(icon: Icons.priority_high_rounded, label: 'Escalada', value: a.razonEscalamiento!.etiqueta, valueColor: AppColors.warning),
            if (a.resolucion != null)
              InfoRow(icon: a.resolucion!.style.icon, label: 'Resolución', value: a.resolucion!.etiqueta, valueColor: a.resolucion!.style.color),
            if (a.evidenciaIncompleta) ...[
              AppSpacing.gapSm,
              const SlBanner(type: SlBannerType.warning, message: 'Evidencia incompleta: se envió sin foto.'),
            ],
          ],
        ),
      ),
    );
  }
}
