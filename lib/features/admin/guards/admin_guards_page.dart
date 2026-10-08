// A-01 Alta · A-02 Edición y baja · A-03 Turnos y radios · A-07 Métricas por guardia
//
// TODO(A-03): pantalla de turno y radio sobre el mapa.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../data/repositories/repository_exceptions.dart';
import '../../../shared/widgets/widgets.dart';

class AdminGuardsPage extends StatefulWidget {
  const AdminGuardsPage({super.key});

  @override
  State<AdminGuardsPage> createState() => _AdminGuardsPageState();
}

class _AdminGuardsPageState extends State<AdminGuardsPage> {
  late final _repo = context.read<AdminRepository>();
  String _search = '';
  late Future<List<Guard>> _guards = _repo.getGuards();

  void _reload() => setState(() => _guards = _repo.getGuards(search: _search));

  Future<void> _openCreate() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _GuardForm(),
    );
    if (created == true) _reload();
  }

  Future<void> _openDetail(Guard g) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GuardDetailSheet(guard: g),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guardias')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Nuevo guardia'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Buscar por nombre o correo', prefixIcon: Icon(Icons.search_rounded)),
              onChanged: (v) {
                _search = v;
                _reload();
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Guard>>(
              future: _guards,
              builder: (context, snap) {
                final list = snap.data;
                if (list == null) return const LoadingView();
                if (list.isEmpty) {
                  return const EmptyState(icon: Icons.search_off_rounded, title: 'Sin resultados');
                }
                final now = DateTime.now();
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => AppSpacing.gapSm,
                  itemBuilder: (_, i) => _GuardTile(guard: list[i], now: now, onTap: () => _openDetail(list[i])),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GuardTile extends StatelessWidget {
  const _GuardTile({required this.guard, required this.now, required this.onTap});
  final Guard guard;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, color) = !guard.user.isActive
        ? ('Dado de baja', AppColors.textMuted)
        : guard.isAvailableAt(now)
            ? ('En turno', AppColors.success)
            : ('Fuera de turno', AppColors.textSecondary);

    return SlCard(
      onTap: onTap,
      child: Opacity(
        opacity: guard.user.isActive ? 1 : 0.55,
        child: Row(
          children: [
            InitialsAvatar(guard.user.initials),
            AppSpacing.gapSm,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(guard.user.name, style: context.text.titleMedium),
                  Text('${guard.profile.shiftStart} – ${guard.profile.shiftEnd} · ${guard.profile.hasCoverage ? Fmt.distance(guard.profile.coverageRadiusMeters!) : 'sin radio'}', style: context.text.bodySmall),
                ],
              ),
            ),
            SlChip(label: label, color: color),
          ],
        ),
      ),
    );
  }
}

class _GuardDetailSheet extends StatelessWidget {
  const _GuardDetailSheet({required this.guard});
  final Guard guard;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AdminRepository>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(guard.user.name, style: context.text.titleLarge),
            Text('${guard.user.email} · ${Fmt.phone(guard.user.phone)}', style: context.text.bodyMedium),
            AppSpacing.gapMd,
            FutureBuilder<GuardMetrics>(
              future: repo.getGuardMetrics(guard.user.id),
              builder: (context, snap) {
                final m = snap.data;
                if (m == null) return const SizedBox(height: 100, child: LoadingView());
                return Row(
                  children: [
                    Expanded(child: MetricTile(label: 'Atendidas', value: '${m.attendedCount}')),
                    AppSpacing.gapSm,
                    Expanded(child: MetricTile(label: 'Aceptación', value: Fmt.duration(m.avgAcceptanceSeconds))),
                    AppSpacing.gapSm,
                    Expanded(child: MetricTile(label: 'Escaladas', value: '${m.escalatedCount}', color: AppColors.warning)),
                  ],
                );
              },
            ),
            AppSpacing.gapLg,
            SlButton(
              label: 'Editar turno y radio',
              icon: Icons.edit_location_alt_outlined,
              variant: SlButtonVariant.secondary,
              onPressed: () => context.showSnack('Pendiente (A-03)'),
            ),
            if (guard.user.isActive) ...[
              AppSpacing.gapSm,
              SlButton(
                label: 'Dar de baja',
                icon: Icons.person_off_outlined,
                variant: SlButtonVariant.danger,
                onPressed: () async {
                  await repo.deactivateGuard(guard.user.id);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GuardForm extends StatefulWidget {
  const _GuardForm();

  @override
  State<_GuardForm> createState() => _GuardFormState();
}

class _GuardFormState extends State<_GuardForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await context.read<AdminRepository>().createGuard(name: _name.text.trim(), email: _email.text.trim(), phone: _phone.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nuevo guardia', style: context.text.titleLarge),
            AppSpacing.gapMd,
            if (_error != null) ...[SlBanner(message: _error!, type: SlBannerType.danger), AppSpacing.gapMd],
            SlTextField(label: 'Nombre completo', controller: _name, validator: Validators.name),
            AppSpacing.gapMd,
            SlTextField(label: 'Correo', controller: _email, keyboardType: TextInputType.emailAddress, validator: Validators.email),
            AppSpacing.gapMd,
            SlTextField(label: 'Teléfono', controller: _phone, keyboardType: TextInputType.phone, digitsOnly: true, maxLength: 10, validator: Validators.phone),
            AppSpacing.gapLg,
            SlButton(label: 'Guardar', loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
