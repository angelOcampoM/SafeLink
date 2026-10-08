// A-08 (vista del usuario) — Cuenta bloqueada por falsas alarmas.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/widgets.dart';
import '../../auth/session_controller.dart';

class BlockedPage extends StatelessWidget {
  const BlockedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final until = session.user?.blockedUntil;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.screen,
          child: Column(
            children: [
              Expanded(
                child: EmptyState(
                  icon: Icons.lock_clock_rounded,
                  color: AppColors.warning,
                  title: 'Tu cuenta está bloqueada',
                  message: until == null
                      ? 'Por varias falsas alarmas no puedes enviar alertas por ahora.'
                      : 'Por varias falsas alarmas no puedes enviar alertas hasta el ${Fmt.date(until)} a las ${Fmt.time(until)}.',
                ),
              ),
              const SlBanner(
                message: 'En una emergencia real llama al 911. Si crees que es un error, contacta al administrador.',
              ),
              AppSpacing.gapMd,
              SlButton(label: 'Cerrar sesión', variant: SlButtonVariant.secondary, onPressed: session.logout),
            ],
          ),
        ),
      ),
    );
  }
}
