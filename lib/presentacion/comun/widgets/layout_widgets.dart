// CAPA: PRESENTACIÓN — sistema de diseño (componente compartido)
// SectionHeader, EmptyState, InfoRow, InitialsAvatar, MetricTile, LoadingView. No hace: no carga datos.

import 'package:flutter/material.dart';

import '../tema/theme.dart';

/// Título de sección con acción opcional a la derecha ("Ver todo").
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: context.text.labelSmall?.copyWith(letterSpacing: 1.2),
            ),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// Estado vacío: listado sin alertas, búsqueda sin resultados, etc.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.color = AppColors.textSecondary,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(color: AppColors.tint(color), shape: BoxShape.circle),
              child: Icon(icon, size: AppSizes.iconXl, color: color),
            ),
            AppSpacing.gapLg,
            Text(title, style: context.text.titleLarge, textAlign: TextAlign.center),
            if (message != null) ...[
              AppSpacing.gapXs,
              Text(message!, style: context.text.bodyMedium, textAlign: TextAlign.center),
            ],
            if (action != null) ...[AppSpacing.gapLg, action!],
          ],
        ),
      ),
    );
  }
}

/// Fila "ícono · etiqueta · valor" para detalles (hora, método, distancia).
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.label, required this.value, this.valueColor});

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: AppSizes.iconSm, color: AppColors.textSecondary),
          AppSpacing.gapSm,
          Text(label, style: context.text.bodyMedium),
          AppSpacing.gapSm,
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: context.text.titleSmall?.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar circular con iniciales.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.initials, {super.key, this.color = AppColors.info, this.size = AppSizes.avatar});

  final String initials;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.tint(color), shape: BoxShape.circle),
      child: Text(initials, style: context.text.titleSmall?.copyWith(color: color)),
    );
  }
}

/// Tarjeta de una métrica: cifra grande + etiqueta.
class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.label, required this.value, this.icon, this.color = AppColors.info});

  final String label;
  final String value;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.card,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[Icon(icon, color: color, size: AppSizes.iconMd), AppSpacing.gapSm],
          Text(value, style: context.text.displaySmall?.copyWith(fontSize: 28)),
          AppSpacing.gapXxs,
          Text(label, style: context.text.bodySmall),
        ],
      ),
    );
  }
}

/// Indicador de carga centrado con texto opcional.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[AppSpacing.gapMd, Text(message!, style: context.text.bodyMedium)],
        ],
      ),
    );
  }
}
