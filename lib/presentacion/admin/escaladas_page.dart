// CAPA: PRESENTACIÓN — View
// A-04 Bandeja de escaladas · A-08 Falsas alarmas
// Lista en tiempo real con pull-to-refresh y hoja para elegir la resolución.

import 'package:flutter/material.dart';

import '../../dominio/dominio.dart';
import '../comun/formato.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'escaladas_view_model.dart';

class EscaladasPage extends StatefulWidget {
  const EscaladasPage({super.key, required this.viewModel});
  final EscaladasViewModel viewModel;

  @override
  State<EscaladasPage> createState() => _EscaladasPageState();
}

class _EscaladasPageState extends State<EscaladasPage> {
  late final EscaladasViewModel vm = widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.addListener(_alCambiar);
    vm.iniciar();
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

  Future<void> _abrir(Alerta a) async {
    final resolucion = await showModalBottomSheet<Resolucion>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HojaResolver(alerta: a),
    );
    if (resolucion != null) await vm.resolver(a, resolucion);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escaladas')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => SlStateView<List<Alerta>>(
          estado: vm.estado,
          onRetry: vm.iniciar,
          onRefresh: vm.recargar,
          empty: const EmptyState(
            icon: Icons.inbox_outlined,
            color: AppColors.success,
            title: 'Bandeja vacía',
            message: 'No hay alertas escaladas por revisar.',
          ),
          builder: (context, lista) => ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.screen,
            itemCount: lista.length,
            separatorBuilder: (_, __) => AppSpacing.gapSm,
            itemBuilder: (_, i) => AlertCard(
              alert: lista[i],
              now: vm.ahora,
              onTap: vm.resolviendo == null ? () => _abrir(lista[i]) : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _HojaResolver extends StatelessWidget {
  const _HojaResolver({required this.alerta});
  final Alerta alerta;

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
            SlBanner(type: SlBannerType.warning, message: alerta.razonEscalamiento?.etiqueta ?? 'Escalada'),
            AppSpacing.gapSm,
            InfoRow(icon: Icons.person_outline_rounded, label: 'Usuario', value: alerta.nombreUsuario ?? '—'),
            InfoRow(icon: Icons.phone_outlined, label: 'Teléfono', value: alerta.telefonoUsuario == null ? '—' : Fmt.phone(alerta.telefonoUsuario!)),
            InfoRow(icon: Icons.shield_outlined, label: 'Guardia', value: alerta.nombreGuardia ?? 'Sin asignar'),
            InfoRow(icon: Icons.schedule_rounded, label: 'Disparada', value: Fmt.dateTime(alerta.disparadaEn)),
            AppSpacing.gapLg,
            SlButton(label: 'Resuelta', icon: Icons.check_rounded, variant: SlButtonVariant.success, onPressed: () => Navigator.pop(context, Resolucion.resuelta)),
            AppSpacing.gapSm,
            SlButton(label: 'Incidencia del servicio', icon: Icons.build_circle_outlined, variant: SlButtonVariant.secondary, onPressed: () => Navigator.pop(context, Resolucion.incidenciaServicio)),
            AppSpacing.gapSm,
            SlButton(label: 'Falsa alarma', icon: Icons.report_outlined, variant: SlButtonVariant.danger, onPressed: () => Navigator.pop(context, Resolucion.falsaAlarma)),
          ],
        ),
      ),
    );
  }
}
