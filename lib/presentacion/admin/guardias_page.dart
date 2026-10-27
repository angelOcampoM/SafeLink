// CAPA: PRESENTACIÓN — View
// A-01 Alta · A-02 Edición y baja · A-03 Turnos y radios · A-07 Métricas por guardia
// Buscador, listado con pull-to-refresh y hoja de detalle con acciones.
// No valida, no calcula disponibilidad y no llama repositorios.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/formato.dart';
import '../comun/rutas/app_routes.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'guardias_view_model.dart';

class GuardiasPage extends StatefulWidget {
  const GuardiasPage({super.key, required this.viewModel});
  final GuardiasViewModel viewModel;

  @override
  State<GuardiasPage> createState() => _GuardiasPageState();
}

class _GuardiasPageState extends State<GuardiasPage> {
  late final GuardiasViewModel vm = widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.addListener(_alCambiar);
    vm.cargar();
  }

  @override
  void dispose() {
    vm.removeListener(_alCambiar);
    vm.dispose();
    super.dispose();
  }

  void _alCambiar() {
    if (vm.mensaje != null) context.showSnack(vm.mensaje!);
    vm.consumirMensaje();
  }

  Future<void> _ir(String ruta) async {
    await context.push(ruta);
    vm.cargar();
  }

  Future<void> _abrirDetalle(Guardia g) async {
    vm.seleccionar(g);
    final ruta = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DetalleGuardiaSheet(vm: vm, guardia: g),
    );
    if (ruta != null && mounted) _ir(ruta);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guardias')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _ir(AppRoutes.adminGuardNew),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Nuevo guardia'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Buscar por nombre o correo', prefixIcon: Icon(Icons.search_rounded)),
              onChanged: vm.buscar,
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: vm,
              builder: (context, _) => SlStateView<List<Guardia>>(
                estado: vm.estado,
                onRetry: vm.cargar,
                onRefresh: vm.cargar,
                empty: const EmptyState(icon: Icons.search_off_rounded, title: 'Sin resultados'),
                builder: (context, lista) => ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 96),
                  itemCount: lista.length,
                  separatorBuilder: (_, __) => AppSpacing.gapSm,
                  itemBuilder: (_, i) => _TarjetaGuardia(vm: vm, guardia: lista[i], onTap: () => _abrirDetalle(lista[i])),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaGuardia extends StatelessWidget {
  const _TarjetaGuardia({required this.vm, required this.guardia, required this.onTap});
  final GuardiasViewModel vm;
  final Guardia guardia;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = vm.estadoDe(guardia);
    final color = !e.activo ? AppColors.textMuted : (e.enTurno ? AppColors.success : AppColors.textSecondary);
    final p = guardia.perfil;

    return SlCard(
      onTap: onTap,
      child: Opacity(
        opacity: e.activo ? 1 : 0.55,
        child: Row(
          children: [
            InitialsAvatar(guardia.usuario.iniciales),
            AppSpacing.gapSm,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(guardia.usuario.nombre, style: context.text.titleMedium),
                  Text('${p.inicioTurno} – ${p.finTurno} · ${p.tieneCobertura ? Fmt.distance(p.radioCoberturaMetros!) : 'sin radio'}', style: context.text.bodySmall),
                ],
              ),
            ),
            SlChip(label: e.etiqueta, color: color),
          ],
        ),
      ),
    );
  }
}

/// Hoja de detalle. Devuelve la ruta a abrir (editar / cobertura) o `null`.
class _DetalleGuardiaSheet extends StatelessWidget {
  const _DetalleGuardiaSheet({required this.vm, required this.guardia});
  final GuardiasViewModel vm;
  final Guardia guardia;

  Future<void> _confirmarBaja(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Dar de baja?'),
        content: Text('${guardia.usuario.nombre} dejará de recibir alertas. Su historial se conserva.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Dar de baja')),
        ],
      ),
    );
    if (ok != true) return;
    await vm.darDeBaja(guardia);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final id = guardia.usuario.id;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(guardia.usuario.nombre, style: context.text.titleLarge),
            Text('${guardia.usuario.correo} · ${Fmt.phone(guardia.usuario.telefono)}', style: context.text.bodyMedium),
            AppSpacing.gapMd,
            ListenableBuilder(
              listenable: vm,
              builder: (context, _) => switch (vm.metricasSeleccion) {
                Listo(datos: final m) => Row(
                    children: [
                      Expanded(child: MetricTile(label: 'Atendidas', value: '${m.atendidas}')),
                      AppSpacing.gapSm,
                      Expanded(child: MetricTile(label: 'Aceptación', value: Fmt.duration(m.promedioAceptacionSeg))),
                      AppSpacing.gapSm,
                      Expanded(child: MetricTile(label: 'Escaladas', value: '${m.escaladas}', color: AppColors.warning)),
                    ],
                  ),
                ErrorVista(:final mensaje) => SlBanner(type: SlBannerType.danger, message: mensaje),
                _ => const SizedBox(height: 100, child: LoadingView()),
              },
            ),
            AppSpacing.gapLg,
            SlButton(
              label: 'Editar datos',
              icon: Icons.edit_outlined,
              variant: SlButtonVariant.secondary,
              onPressed: () => Navigator.pop(context, AppRoutes.adminGuardEdit(id)),
            ),
            AppSpacing.gapSm,
            SlButton(
              label: 'Editar turno y radio',
              icon: Icons.edit_location_alt_outlined,
              variant: SlButtonVariant.secondary,
              onPressed: () => Navigator.pop(context, AppRoutes.adminGuardCoverage(id)),
            ),
            if (guardia.usuario.activo) ...[
              AppSpacing.gapSm,
              SlButton(
                label: 'Dar de baja',
                icon: Icons.person_off_outlined,
                variant: SlButtonVariant.danger,
                onPressed: () => _confirmarBaja(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
