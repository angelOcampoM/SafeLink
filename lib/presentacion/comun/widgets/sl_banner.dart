// CAPA: PRESENTACIÓN — sistema de diseño (componente compartido)
// Mensaje en línea (info, éxito, aviso, error) con acción opcional. No hace: no decide cuándo mostrarse.

import 'package:flutter/material.dart';

import '../tema/theme.dart';

enum SlBannerType { info, success, warning, danger }

/// Mensaje en línea dentro de una pantalla (no un SnackBar).
/// Ej.: "Sin foto: la alerta se envió con evidencia incompleta".
class SlBanner extends StatelessWidget {
  const SlBanner({
    super.key,
    required this.message,
    this.title,
    this.type = SlBannerType.info,
    this.icon,
    this.action,
  });

  final String message;
  final String? title;
  final SlBannerType type;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final (color, defaultIcon) = switch (type) {
      SlBannerType.info => (AppColors.info, Icons.info_outline_rounded),
      SlBannerType.success => (AppColors.success, Icons.check_circle_outline_rounded),
      SlBannerType.warning => (AppColors.warning, Icons.warning_amber_rounded),
      SlBannerType.danger => (AppColors.danger, Icons.error_outline_rounded),
    };

    return Container(
      padding: AppSpacing.card,
      decoration: BoxDecoration(
        color: AppColors.tint(color),
        borderRadius: AppRadius.brMd,
        border: Border.all(color: AppColors.tintBorder(color)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, color: color),
          AppSpacing.gapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: context.text.titleSmall?.copyWith(color: color)),
                  AppSpacing.gapXxs,
                ],
                Text(message, style: context.text.bodyMedium?.copyWith(color: AppColors.textPrimary)),
                if (action != null) ...[AppSpacing.gapXs, action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
