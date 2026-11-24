// CAPA: PRESENTACIÓN — View
// A-05 Historial con filtros (rango de fechas, guardia, usuario y estado, combinables)
// Chips de filtro, lista con pull-to-refresh y detalle en hoja inferior.
// No filtra por su cuenta: solo pasa al ViewModel lo que se eligió.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/dominio.dart';
import '../comun/formato.dart';
import '../comun/rutas/app_routes.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'historial_view_model.dart';

class HistorialPage extends StatefulWidget {
  const HistorialPage({super.key, required this.viewModel});
  final HistorialViewModel viewModel;

  @override
  State<HistorialPage> createState() => _HistorialPageState();
}

class _HistorialPageState extends State<HistorialPage> {
  late final HistorialViewModel vm = widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.iniciar();
  }

  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  Future<void> _elegirRango() async {
    final hoy = vm.ahora;
    final r = await showDateRangePicker(
      context: context,
      firstDate: hoy.subtract(const Duration(days: 365)),
      lastDate: hoy,
      initialDateRange: vm.desde == null ? null : DateTimeRange(start: vm.desde!, end: vm.hasta!),
      helpText: 'Rango de fechas',
    );
    if (r != null) vm.cambiarRango(r.start, r.end);
  }

  Future<void> _elegirGuardia() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(leading: const Icon(Icons.groups_outlined), title: const Text('Todos los guardias'), onTap: () => Navigator.pop(c, '')),
            for (final g in vm.guardias)
              ListTile(
                leading: InitialsAvatar(g.usuario.iniciales),
                title: Text(g.usuario.nombre),
                selected: g.usuario.id == vm.guardiaId,
                onTap: () => Navigator.pop(c, g.usuario.id),
              ),
          ],
        ),
      ),
    );
    if (id != null) vm.cambiarGuardia(id.isEmpty ? null : id);
  }

  Future<void> _elegirUsuario() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(leading: const Icon(Icons.person_outline_rounded), title: const Text('Todos los usuarios'), onTap: () => Navigator.pop(c, '')),
            for (final u in vm.usuarios)
              ListTile(
                leading: InitialsAvatar(u.iniciales),
                title: Text(u.nombre),
                selected: u.id == vm.usuarioId,
                onTap: () => Navigator.pop(c, u.id),
              ),
          ],
        ),
      ),
    );
    if (id != null) vm.cambiarUsuario(id.isEmpty ? null : id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.date_range_rounded, size: AppSizes.iconSm),
                    label: Text(vm.desde == null ? 'Todas las fechas' : '${Fmt.date(vm.desde!)} – ${Fmt.date(vm.hasta!)}'),
                    onPressed: _elegirRango,
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.shield_outlined, size: AppSizes.iconSm),
                    label: Text(vm.nombreGuardia ?? 'Todos los guardias'),
                    onPressed: _elegirGuardia,
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.person_outline_rounded, size: AppSizes.iconSm),
                    label: Text(vm.nombreUsuario ?? 'Todos los usuarios'),
                    onPressed: _elegirUsuario,
                  ),
                  if (vm.hayFiltros)
                    ActionChip(
                      avatar: const Icon(Icons.filter_alt_off_outlined, size: AppSizes.iconSm),
                      label: const Text('Limpiar'),
                      onPressed: vm.limpiarFiltros,
                    ),
                ],
              ),
            ),
            AppSpacing.gapXs,
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                children: [
                  ChoiceChip(label: const Text('Todas'), selected: vm.estadoFiltro == null, onSelected: (_) => vm.cambiarEstado(null)),
                  for (final s in EstadoAlerta.values) ...[
                    AppSpacing.gapXs,
                    ChoiceChip(label: Text(s.etiqueta), selected: vm.estadoFiltro == s, onSelected: (_) => vm.cambiarEstado(s)),
                  ],
                ],
              ),
            ),
            AppSpacing.gapXs,
            Expanded(
              child: SlStateView<List<Alerta>>(
                estado: vm.estado,
                onRetry: vm.cargar,
                onRefresh: vm.cargar,
                empty: const EmptyState(icon: Icons.filter_alt_off_outlined, title: 'Sin alertas con estos filtros'),
                builder: (context, lista) => ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: AppSpacing.screen,
                  itemCount: lista.length + 1,
                  separatorBuilder: (_, __) => AppSpacing.gapSm,
                  itemBuilder: (_, i) => i == 0
                      ? Text('${lista.length} alertas', style: context.text.bodySmall)
                      : AlertCard(
                          alert: lista[i - 1],
                          now: vm.ahora,
                          showGuardia: true,
                          onTap: () => context.push(AppRoutes.adminAlertDetail(lista[i - 1].id)),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
