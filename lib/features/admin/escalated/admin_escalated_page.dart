// A-04 Bandeja de escaladas
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../shared/widgets/widgets.dart';

class AdminEscalatedPage extends StatefulWidget {
  const AdminEscalatedPage({super.key});

  @override
  State<AdminEscalatedPage> createState() => _AdminEscalatedPageState();
}

class _AdminEscalatedPageState extends State<AdminEscalatedPage> {
  late final _repo = context.read<AdminRepository>();
  late final Stream<List<Alert>> _stream = _repo.watchEscalatedAlerts();

  Future<void> _open(Alert a) async {
    final resolution = await showModalBottomSheet<Resolution>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ResolveSheet(alert: a),
    );
    if (resolution == null) return;
    await _repo.resolveAlert(a.id, resolution);
    if (mounted) context.showSnack('Alerta marcada como "${resolution.label}"');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escaladas')),
      body: StreamBuilder<List<Alert>>(
        stream: _stream,
        builder: (context, snap) {
          final list = snap.data;
          if (list == null) return const LoadingView();
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.inbox_outlined,
              color: AppColors.success,
              title: 'Bandeja vacía',
              message: 'No hay alertas escaladas por revisar.',
            );
          }
          final now = DateTime.now();
          return ListView.separated(
            padding: AppSpacing.screen,
            itemCount: list.length,
            separatorBuilder: (_, __) => AppSpacing.gapSm,
            itemBuilder: (_, i) => AlertCard(alert: list[i], now: now, onTap: () => _open(list[i])),
          );
        },
      ),
    );
  }
}

class _ResolveSheet extends StatelessWidget {
  const _ResolveSheet({required this.alert});
  final Alert alert;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Resolver alerta', style: context.text.titleLarge),
            AppSpacing.gapSm,
            SlBanner(type: SlBannerType.warning, message: alert.escalationReason?.label ?? 'Escalada'),
            AppSpacing.gapSm,
            InfoRow(icon: Icons.person_outline_rounded, label: 'Usuario', value: alert.userName ?? '—'),
            InfoRow(icon: Icons.phone_outlined, label: 'Teléfono', value: alert.userPhone == null ? '—' : Fmt.phone(alert.userPhone!)),
            InfoRow(icon: Icons.shield_outlined, label: 'Guardia', value: alert.guardName ?? 'Sin asignar'),
            InfoRow(icon: Icons.schedule_rounded, label: 'Disparada', value: Fmt.dateTime(alert.triggeredAt)),
            AppSpacing.gapLg,
            SlButton(label: 'Resuelta', icon: Icons.check_rounded, variant: SlButtonVariant.success, onPressed: () => Navigator.pop(context, Resolution.resolved)),
            AppSpacing.gapSm,
            SlButton(label: 'Incidencia del servicio', icon: Icons.build_circle_outlined, variant: SlButtonVariant.secondary, onPressed: () => Navigator.pop(context, Resolution.serviceIncident)),
            AppSpacing.gapSm,
            SlButton(label: 'Falsa alarma', icon: Icons.report_outlined, variant: SlButtonVariant.danger, onPressed: () => Navigator.pop(context, Resolution.falseAlarm)),
          ],
        ),
      ),
    );
  }
}
