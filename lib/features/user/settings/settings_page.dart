// U-05 — Configuración (activar/desactivar agitación).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/widgets.dart';
import '../../auth/session_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final user = session.user!;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(AppRoutes.userHome)),
        title: const Text('Configuración'),
      ),
      body: ListView(
        padding: AppSpacing.screen,
        children: [
          SlCard(
            child: Row(
              children: [
                InitialsAvatar(user.initials, size: 52),
                AppSpacing.gapMd,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: context.text.titleMedium),
                      Text(user.email, style: context.text.bodyMedium),
                      Text(Fmt.phone(user.phone), style: context.text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.gapLg,
          const SectionHeader('Métodos de alerta'),
          SlCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              value: user.shakeEnabled,
              onChanged: session.setShakeEnabled,
              secondary: const Icon(Icons.vibration_rounded),
              title: const Text('Alerta por agitación'),
              subtitle: const Text('Funciona con la pantalla bloqueada. Mostrará una notificación permanente.'),
            ),
          ),
          AppSpacing.gapLg,
          SlButton(
            label: 'Cerrar sesión',
            icon: Icons.logout_rounded,
            variant: SlButtonVariant.secondary,
            onPressed: session.logout,
          ),
        ],
      ),
    );
  }
}
