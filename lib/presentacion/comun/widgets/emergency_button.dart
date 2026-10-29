// CAPA: PRESENTACIÓN — sistema de diseño (componente compartido)
// Botón circular de alerta (U-03 · U-04): solo visual + gestos. La lógica vive en InicioViewModel.

import 'package:flutter/material.dart';

import '../tema/theme.dart';

/// Botón circular de emergencia (pantalla de inicio del usuario protegido).
///
/// Solo es la parte VISUAL + gestos crudos. La lógica de cada método
/// (cuenta regresiva U-03, zona de descarte U-04) vive en su feature, que
/// recibe estos callbacks.
class EmergencyButton extends StatefulWidget {
  const EmergencyButton({
    super.key,
    this.onTap,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
    this.label = 'ALERTA',
    this.sublabel,
    this.caption = 'Toca o mantén presionado',
    this.enabled = true,
    this.pressed = false,
  });

  final VoidCallback? onTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;
  final String label;

  /// Texto pequeño bajo la etiqueta ("ENVIAR AYUDA").
  final String? sublabel;
  final String caption;
  final bool enabled;

  /// Muestra el estado "presionado" (escala y brillo) mientras se mantiene.
  final bool pressed;

  @override
  State<EmergencyButton> createState() => _EmergencyButtonState();
}

class _EmergencyButtonState extends State<EmergencyButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: AppDurations.pulse)
    ..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = AppSizes.emergencyButton;
    final color = widget.enabled ? AppColors.emergency : AppColors.surfaceElevated;

    return Semantics(
      button: true,
      label: 'Botón de alerta. ${widget.caption}',
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        onLongPressStart: widget.enabled ? widget.onLongPressStart : null,
        onLongPressMoveUpdate: widget.enabled ? widget.onLongPressMoveUpdate : null,
        onLongPressEnd: widget.enabled ? widget.onLongPressEnd : null,
        child: SizedBox(
          width: size * 1.4,
          height: size * 1.4,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.enabled)
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final t = _pulse.value;
                    return Container(
                      width: size * (1 + 0.4 * t),
                      height: size * (1 + 0.4 * t),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.emergency.withValues(alpha: 0.25 * (1 - t)),
                      ),
                    );
                  },
                ),
              AnimatedScale(
                scale: widget.pressed ? 0.94 : 1,
                duration: AppDurations.fast,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: !widget.enabled
                          ? [color, color]
                          : widget.pressed
                              ? [AppColors.emergencyDark, AppColors.emergencyDark]
                              : [AppColors.emergency, AppColors.emergencyDark],
                    ),
                    boxShadow: widget.enabled
                        ? [BoxShadow(color: AppColors.emergency.withValues(alpha: 0.5), blurRadius: widget.pressed ? 64 : 40, spreadRadius: widget.pressed ? 12 : 4)]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.sos_rounded, size: AppSizes.iconXl, color: AppColors.onAccent),
                      AppSpacing.gapXs,
                      Text(
                        widget.label,
                        style: context.text.headlineMedium?.copyWith(color: AppColors.onAccent, letterSpacing: 2),
                      ),
                      if (widget.sublabel != null)
                        Text(
                          widget.sublabel!,
                          style: context.text.labelSmall?.copyWith(color: AppColors.onAccent, letterSpacing: 1.2),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
