// U-03 Toque simple · U-04 Mantener presionado · U-06 Evidencia
//
// Versión base funcional con mocks. Pendiente por historia:
// TODO(U-06): tomar la foto real con la cámara y leer GPS/brújula.
// TODO(U-05): mostrar indicador del servicio de agitación activo.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme.dart';
import '../../../data/mock/mock_seed.dart';
import '../../../data/models/enums.dart';
import '../../../data/repositories/repository_exceptions.dart';
import '../../../data/repositories/user_alert_repository.dart';
import '../../../shared/widgets/widgets.dart';
import '../../auth/session_controller.dart';

class UserHomePage extends StatefulWidget {
  const UserHomePage({super.key});

  @override
  State<UserHomePage> createState() => _UserHomePageState();
}

class _UserHomePageState extends State<UserHomePage> {
  // Cuenta regresiva (U-03)
  Timer? _timer;
  int? _countdown;

  // Mantener presionado (U-04)
  bool _holding = false;
  bool _overDiscard = false;
  final _discardKey = GlobalKey();

  bool _sending = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ── U-03 ──
  void _startCountdown() {
    final seconds = context.read<AppConfig>().tapCountdownSeconds;
    setState(() => _countdown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown! <= 1) {
        t.cancel();
        setState(() => _countdown = null);
        _send(TriggerMethod.tap);
      } else {
        setState(() => _countdown = _countdown! - 1);
      }
    });
  }

  void _cancelCountdown() {
    _timer?.cancel();
    setState(() => _countdown = null);
  }

  // ── U-04 ──
  bool _isOverDiscard(Offset global) {
    final box = _discardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    return rect.inflate(AppSpacing.md).contains(global);
  }

  void _onHoldEnd(Offset global) {
    final discard = _isOverDiscard(global);
    setState(() {
      _holding = false;
      _overDiscard = false;
    });
    if (discard) {
      context.showSnack('Alerta descartada');
    } else {
      _send(TriggerMethod.hold);
    }
  }

  Future<void> _send(TriggerMethod method) async {
    setState(() => _sending = true);
    try {
      await context.read<UserAlertRepository>().createAlert(
            triggerMethod: method,
            triggeredAt: DateTime.now().toUtc(),
            location: MockSeed.userDeviceLocation, // TODO(U-06): GPS real
            heading: 35, // TODO(U-06): brújula real
            photoPath: 'mock.jpg', // TODO(U-06): foto real
          );
      if (mounted) context.go(AppRoutes.userAlert);
    } on AppException catch (e) {
      if (mounted) context.showSnack(e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().user!;

    return Scaffold(
      appBar: AppBar(
        title: Text('Hola, ${user.name.split(' ').first}'),
        actions: [
          IconButton(
            tooltip: 'Mi alerta activa',
            icon: const Icon(Icons.notifications_active_outlined),
            onPressed: () => context.go(AppRoutes.userAlert),
          ),
          IconButton(
            tooltip: 'Configuración',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go(AppRoutes.userSettings),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: AppSpacing.screen,
              child: Column(
                children: [
                  if (user.shakeEnabled)
                    const SlBanner(
                      type: SlBannerType.success,
                      icon: Icons.vibration_rounded,
                      message: 'Agitación activa: puedes enviar una alerta agitando el teléfono.',
                    ),
                  const Spacer(),
                  EmergencyButton(
                    enabled: !_sending && _countdown == null,
                    pressed: _holding,
                    caption: 'Toca o mantén presionado',
                    onTap: _startCountdown,
                    onLongPressStart: (_) => setState(() => _holding = true),
                    onLongPressMoveUpdate: (d) => setState(() => _overDiscard = _isOverDiscard(d.globalPosition)),
                    onLongPressEnd: (d) => _onHoldEnd(d.globalPosition),
                  ),
                  AppSpacing.gapLg,
                  Text(
                    _holding
                        ? 'Suelta para enviar · Arrastra a Descartar para cancelar'
                        : 'Toca para enviar en ${context.read<AppConfig>().tapCountdownSeconds} s o mantén presionado',
                    style: context.text.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: _holding ? 1 : 0,
                    duration: AppDurations.fast,
                    child: _DiscardZone(key: _discardKey, active: _overDiscard),
                  ),
                  AppSpacing.gapMd,
                ],
              ),
            ),
            if (_countdown != null) _CountdownOverlay(seconds: _countdown!, onCancel: _cancelCountdown),
            if (_sending) Container(color: AppColors.background.withValues(alpha: 0.8), child: const LoadingView(message: 'Enviando alerta…')),
          ],
        ),
      ),
    );
  }
}

class _DiscardZone extends StatelessWidget {
  const _DiscardZone({super.key, required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.danger : AppColors.textSecondary;
    return AnimatedContainer(
      duration: AppDurations.fast,
      width: 180,
      height: 72,
      decoration: BoxDecoration(
        color: active ? AppColors.tint(AppColors.danger) : AppColors.surface,
        borderRadius: AppRadius.brPill,
        border: Border.all(color: active ? AppColors.danger : AppColors.border, width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.delete_outline_rounded, color: color),
          AppSpacing.gapXs,
          Text('Descartar', style: context.text.labelLarge?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _CountdownOverlay extends StatelessWidget {
  const _CountdownOverlay({required this.seconds, required this.onCancel});
  final int seconds;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background.withValues(alpha: 0.94),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Enviando alerta en', style: context.text.titleLarge),
          AppSpacing.gapLg,
          Container(
            width: 160,
            height: 160,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.emergency, width: 6),
            ),
            child: Text('$seconds', style: context.text.displayLarge?.copyWith(color: AppColors.emergency)),
          ),
          AppSpacing.gapXl,
          SlButton(label: 'Cancelar', icon: Icons.close_rounded, variant: SlButtonVariant.secondary, onPressed: onCancel),
        ],
      ),
    );
  }
}
