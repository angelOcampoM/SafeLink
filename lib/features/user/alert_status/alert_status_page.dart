// U-07 Ubicación en tiempo real · U-08 Guardia asignado y ETA · U-09 Confirmación
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/alert_rules.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/repository_exceptions.dart';
import '../../../data/repositories/user_alert_repository.dart';
import '../../../shared/widgets/widgets.dart';

class AlertStatusPage extends StatefulWidget {
  const AlertStatusPage({super.key});

  @override
  State<AlertStatusPage> createState() => _AlertStatusPageState();
}

class _AlertStatusPageState extends State<AlertStatusPage> {
  late final Stream<Alert?> _stream = context.read<UserAlertRepository>().watchActiveAlert();
  bool _confirming = false;

  Future<void> _confirm(Alert a) async {
    setState(() => _confirming = true);
    try {
      await context.read<UserAlertRepository>().confirmAttention(a.id);
      if (!mounted) return;
      context.showSnack('Gracias. Tu alerta quedó cerrada.');
      context.go(AppRoutes.userHome);
    } on AppException catch (e) {
      if (mounted) context.showSnack(e.message);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(AppRoutes.userHome)),
        title: const Text('Mi alerta'),
      ),
      body: StreamBuilder<Alert?>(
        stream: _stream,
        builder: (context, snap) {
          if (!snap.hasData && snap.connectionState == ConnectionState.waiting) return const LoadingView();
          final a = snap.data;
          if (a == null) {
            return EmptyState(
              icon: Icons.verified_user_outlined,
              color: AppColors.success,
              title: 'Sin alertas activas',
              message: 'Cuando envíes una alerta, aquí verás al guardia que va en camino.',
              action: SlButton(label: 'Volver al inicio', expand: false, onPressed: () => context.go(AppRoutes.userHome)),
            );
          }
          return ListView(
            padding: AppSpacing.screen,
            children: [
              _StatusHeader(alert: a),
              AppSpacing.gapLg,
              if (a.evidenceIncomplete) ...[
                const SlBanner(type: SlBannerType.warning, message: 'No se pudo tomar la foto. Tu alerta se envió con evidencia incompleta.'),
                AppSpacing.gapMd,
              ],
              if (a.status == AlertStatus.pendingLocation) ...[
                const SlBanner(
                  type: SlBannerType.warning,
                  title: 'Esperando ubicación',
                  message: 'Activa el GPS. Tu alerta se publicará en cuanto tengamos tu ubicación.',
                ),
                AppSpacing.gapMd,
              ],
              if (a.guardName != null) ...[
                _GuardCard(alert: a),
                AppSpacing.gapMd,
              ],
              MapPlaceholder(
                markers: [
                  if (a.status == AlertStatus.inProgress)
                    MapMarker(offset: Offset(-0.6, 0.5 - (300 - (a.etaSeconds ?? 300)) / 600), color: AppColors.info, icon: Icons.shield_rounded),
                  const MapMarker(offset: Offset(0.3, -0.2), color: AppColors.emergency, icon: Icons.person_pin_circle_rounded),
                ],
                showRoute: a.status == AlertStatus.inProgress,
              ),
              AppSpacing.gapMd,
              Text(
                'Tu ubicación se comparte en tiempo real mientras la alerta esté activa.',
                style: context.text.bodySmall,
                textAlign: TextAlign.center,
              ),
              AppSpacing.gapLg,
              SlButton(
                label: 'Ya fui atendido',
                icon: Icons.check_circle_outline_rounded,
                variant: SlButtonVariant.success,
                loading: _confirming,
                // U-09: solo habilitado tras la llegada del guardia.
                onPressed: AlertRules.canUserConfirm(a) ? () => _confirm(a) : null,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.alert});
  final Alert alert;

  @override
  Widget build(BuildContext context) {
    final s = alert.status.style;
    final subtitle = switch (alert.status) {
      AlertStatus.searching => 'Notificamos a los guardias cercanos.',
      AlertStatus.inProgress => 'Un guardia va en camino.',
      AlertStatus.guardArrived => 'El guardia llegó a tu ubicación.',
      AlertStatus.pendingLocation => 'Aún no se publica.',
      _ => '',
    };
    return SlCard(
      accent: s.color,
      child: Row(
        children: [
          Icon(s.icon, color: s.color, size: AppSizes.iconLg),
          AppSpacing.gapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.label, style: context.text.headlineSmall),
                Text(subtitle, style: context.text.bodyMedium),
              ],
            ),
          ),
          if (alert.status == AlertStatus.searching)
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.emergency)),
        ],
      ),
    );
  }
}

class _GuardCard extends StatelessWidget {
  const _GuardCard({required this.alert});
  final Alert alert;

  @override
  Widget build(BuildContext context) {
    final initials = alert.guardName!.split(' ').take(2).map((p) => p[0]).join();
    return SlCard(
      child: Row(
        children: [
          InitialsAvatar(initials, color: AppColors.info, size: 52),
          AppSpacing.gapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tu guardia', style: context.text.bodySmall),
                Text(alert.guardName!, style: context.text.titleMedium),
              ],
            ),
          ),
          if (alert.status == AlertStatus.inProgress && alert.etaSeconds != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Fmt.duration(alert.etaSeconds!), style: context.text.displaySmall?.copyWith(color: AppColors.info)),
                Text('llegada aprox.', style: context.text.bodySmall),
              ],
            ),
        ],
      ),
    );
  }
}
