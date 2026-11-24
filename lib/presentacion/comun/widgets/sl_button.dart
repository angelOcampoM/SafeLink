// CAPA: PRESENTACIÓN — sistema de diseño (componente compartido)
// Botón estándar con variantes y estado de carga. No hace: no valida ni llama repositorios.

import 'package:flutter/material.dart';

import '../tema/theme.dart';

enum SlButtonVariant {
  /// Acción principal (azul info). Login, Aceptar alerta, Guardar.
  primary,

  /// Acción positiva/confirmación (verde). "Ya fui atendido", "Llegué".
  success,

  /// SOLO para disparar o reforzar una emergencia (rojo emergency).
  emergency,

  /// Acción destructiva no urgente (rojo apagado). Dar de baja, Falsa alarma.
  danger,

  /// Alternativa secundaria con borde. Cancelar, Abrir en Google Maps.
  secondary,

  /// Acción terciaria sin fondo. "¿Olvidaste tu contraseña?"
  ghost,
}

/// Botón estándar de SafeLink: 56 px de alto, radio 16, estado de carga.
///
/// ```dart
/// SlButton(label: 'Aceptar alerta', icon: Icons.check, onPressed: _accept)
/// SlButton(label: 'Cancelar', variant: SlButtonVariant.secondary, onPressed: ...)
/// SlButton(label: 'Guardar', loading: _saving, onPressed: _save)
/// ```
class SlButton extends StatelessWidget {
  const SlButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = SlButtonVariant.primary,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final SlButtonVariant variant;
  final bool loading;

  /// Ocupa todo el ancho disponible (por defecto `true`).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final callback = enabled ? onPressed : null;

    final fg = switch (variant) {
      SlButtonVariant.secondary => AppColors.textPrimary,
      SlButtonVariant.ghost => AppColors.info,
      _ => AppColors.onAccent,
    };

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: AppSizes.iconSm,
            height: AppSizes.iconSm,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
          )
        else if (icon != null)
          Icon(icon, size: AppSizes.iconMd),
        if (loading || icon != null) AppSpacing.gapXs,
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );

    final Widget button = switch (variant) {
      SlButtonVariant.secondary => OutlinedButton(onPressed: callback, child: content),
      SlButtonVariant.ghost => TextButton(onPressed: callback, child: content),
      _ => FilledButton(
          onPressed: callback,
          style: FilledButton.styleFrom(backgroundColor: _solidColor, foregroundColor: fg),
          child: content,
        ),
    };

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }

  Color get _solidColor => switch (variant) {
        SlButtonVariant.success => AppColors.success,
        SlButtonVariant.emergency => AppColors.emergency,
        SlButtonVariant.danger => AppColors.danger,
        _ => AppColors.info,
      };
}
