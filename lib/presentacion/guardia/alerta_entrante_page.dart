// CAPA: PRESENTACIÓN — View
// G-02 Recepción de alerta (pantalla "Alerta entrante")
// Info básica de la alerta con "Ver detalle" e "Ignorar". No decide nada.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../comun/formato.dart';
import '../comun/rutas/app_routes.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'alerta_entrante_view_model.dart';

class AlertaEntrantePage extends StatefulWidget {
  const AlertaEntrantePage({super.key, required this.viewModel});
  final AlertaEntranteViewModel viewModel;

  @override
  State<AlertaEntrantePage> createState() => _AlertaEntrantePageState();
}

class _AlertaEntrantePageState extends State<AlertaEntrantePage> {
  late final AlertaEntranteViewModel vm = widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.cargar();
  }

  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  Future<void> _alIgnorar() async {
    final ok = await vm.ignorar();
    if (!mounted) return;
    if (ok) {
      context.showSnack('Alerta ignorada');
      context.pop();
    } else if (vm.mensaje != null) {
      context.showSnack(vm.mensaje!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alerta entrante')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => SlStateView<AlertaEntrante>(
          estado: vm.estado,
          onRetry: vm.cargar,
          empty: EmptyState(
            icon: Icons.check_circle_outline_rounded,
            color: AppColors.success,
            title: 'Ya no está disponible',
            message: 'Otro guardia la tomó o la alerta cambió de estado.',
            action: SlButton(label: 'Volver al listado', expand: false, onPressed: () => context.go(AppRoutes.guardHome)),
          ),
          builder: (context, d) {
            final a = d.alerta;
            final color = a.esUrgente ? AppColors.warning : AppColors.emergency;
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: AppSpacing.screen,
                    children: [
                      SlCard(
                        accent: color,
                        child: Row(
                          children: [
                            Icon(Icons.notifications_active_rounded, color: color, size: AppSizes.iconLg),
                            AppSpacing.gapMd,
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a.nombreUsuario ?? 'Usuario', style: context.text.headlineSmall),
                                  Text(Fmt.ago(a.disparadaEn, vm.ahora), style: context.text.bodyMedium),
                                ],
                              ),
                            ),
                            if (d.distancia != null)
                              Text(Fmt.distance(d.distancia!), style: context.text.displaySmall?.copyWith(color: AppColors.info)),
                          ],
                        ),
                      ),
                      AppSpacing.gapMd,
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          TriggerChip(a.metodo),
                          if (a.evidenciaIncompleta)
                            const SlChip(label: 'Sin foto', color: AppColors.textSecondary, icon: Icons.no_photography_outlined),
                        ],
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: AppSpacing.screen,
                    child: Column(
                      children: [
                        SlButton(
                          label: 'Ver detalle',
                          icon: Icons.visibility_outlined,
                          onPressed: () => context.pushReplacement(AppRoutes.guardAlertDetail(a.id)),
                        ),
                        AppSpacing.gapSm,
                        SlButton(
                          label: 'Ignorar',
                          icon: Icons.close_rounded,
                          variant: SlButtonVariant.secondary,
                          loading: vm.ignorando,
                          onPressed: _alIgnorar,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
