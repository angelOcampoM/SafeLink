// CAPA: PRESENTACIÓN — View
// A-04 Detalle de una alerta escalada (pantalla completa)
// Muestra el motivo, el detalle completo con evidencia, el apartado de nota
// administrativa y la confirmación de revisión que habilita resolver.
// No carga datos ni conoce repositorios.

import 'package:flutter/material.dart';

import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'detalle_escalada_view_model.dart';

class DetalleEscaladaPage extends StatefulWidget {
  const DetalleEscaladaPage({super.key, required this.viewModel});
  final DetalleEscaladaViewModel viewModel;

  @override
  State<DetalleEscaladaPage> createState() => _DetalleEscaladaPageState();
}

class _DetalleEscaladaPageState extends State<DetalleEscaladaPage> {
  late final DetalleEscaladaViewModel vm = widget.viewModel;
  final _nota = TextEditingController();

  @override
  void initState() {
    super.initState();
    vm.cargar();
  }

  @override
  void dispose() {
    _nota.dispose();
    vm.dispose();
    super.dispose();
  }

  Future<void> _resolver(Resolucion resolucion) async {
    final ok = await vm.resolver(resolucion, nota: _nota.text);
    if (!mounted) return;
    final mensaje = vm.mensaje;
    if (ok) {
      context.showSnack(mensaje ?? '');
      Navigator.of(context).pop();
    } else if (mensaje != null && mensaje.isNotEmpty) {
      context.showSnack(mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alerta escalada')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => switch (vm.estado) {
          Cargando() => const LoadingView(),
          Vacio() => const Padding(
              padding: AppSpacing.screen,
              child: SlBanner(message: 'No encontramos la alerta.'),
            ),
          ErrorVista(:final mensaje) => Padding(
              padding: AppSpacing.screen,
              child: SlBanner(
                type: SlBannerType.danger,
                message: mensaje,
                action: TextButton.icon(onPressed: vm.cargar, icon: const Icon(Icons.refresh_rounded), label: const Text('Reintentar')),
              ),
            ),
          Listo(datos: final a) => _Detalle(vm: vm, alerta: a, nota: _nota, onResolver: _resolver),
        },
      ),
    );
  }
}

class _Detalle extends StatelessWidget {
  const _Detalle({required this.vm, required this.alerta, required this.nota, required this.onResolver});

  final DetalleEscaladaViewModel vm;
  final Alerta alerta;
  final TextEditingController nota;
  final Future<void> Function(Resolucion) onResolver;

  @override
  Widget build(BuildContext context) {
    final habilitado = vm.puedeResolver;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: SlBanner(
              type: SlBannerType.warning,
              message: alerta.razonEscalamiento == null ? 'Alerta escalada' : 'Motivo: ${alerta.razonEscalamiento!.etiqueta}',
            ),
          ),
          AppSpacing.gapSm,
          AlertDetailSheet(alert: alerta),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader('Nota administrativa'),
                SlTextField(
                  label: 'Nota administrativa',
                  hint: 'Describe lo que revisaste y cómo se atendió',
                  controller: nota,
                  maxLines: 4,
                  minLines: 3,
                  maxLength: ReglaAlerta.maxNota,
                  errorText: vm.errorNota,
                  enabled: !vm.resolviendo,
                ),
                AppSpacing.gapSm,
                CheckboxListTile(
                  value: vm.confirmoRevision,
                  onChanged: vm.resolviendo ? null : (v) => vm.cambiarRevision(v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Confirmo que revisé y atendí esta alerta', style: context.text.bodyMedium),
                ),
                AppSpacing.gapSm,
                SlButton(
                  label: 'Resuelta',
                  icon: Icons.check_rounded,
                  variant: SlButtonVariant.success,
                  onPressed: habilitado ? () => onResolver(Resolucion.resuelta) : null,
                ),
                AppSpacing.gapSm,
                SlButton(
                  label: 'Incidencia del servicio',
                  icon: Icons.build_circle_outlined,
                  variant: SlButtonVariant.secondary,
                  onPressed: habilitado ? () => onResolver(Resolucion.incidenciaServicio) : null,
                ),
                AppSpacing.gapSm,
                SlButton(
                  label: 'Falsa alarma',
                  icon: Icons.report_outlined,
                  variant: SlButtonVariant.danger,
                  onPressed: habilitado ? () => onResolver(Resolucion.falsaAlarma) : null,
                ),
                AppSpacing.gapLg,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
