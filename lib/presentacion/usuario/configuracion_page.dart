// CAPA: PRESENTACIÓN — View
// U-05 Configuración (activar/desactivar agitación)
// Pinta el perfil y el interruptor; le pasa las intenciones al ViewModel.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../comun/formato.dart';
import '../comun/rutas/app_routes.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'configuracion_view_model.dart';

class ConfiguracionPage extends StatefulWidget {
  const ConfiguracionPage({super.key, required this.viewModel});
  final ConfiguracionViewModel viewModel;

  @override
  State<ConfiguracionPage> createState() => _ConfiguracionPageState();
}

class _ConfiguracionPageState extends State<ConfiguracionPage> {
  late final ConfiguracionViewModel vm = widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.addListener(_alCambiar);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(AppRoutes.userHome)),
        title: const Text('Configuración'),
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          final user = vm.usuario;
          if (user == null) return const LoadingView();
          return ListView(
            padding: AppSpacing.screen,
            children: [
              SlCard(
                child: Row(
                  children: [
                    InitialsAvatar(user.iniciales, size: 52),
                    AppSpacing.gapMd,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.nombre, style: context.text.titleMedium),
                          Text(user.correo, style: context.text.bodyMedium),
                          Text(Fmt.phone(user.telefono), style: context.text.bodySmall),
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
                  value: user.agitacionActiva,
                  onChanged: vm.guardando ? null : vm.cambiarAgitacion,
                  secondary: const Icon(Icons.vibration_rounded),
                  title: const Text('Alerta por agitación'),
                  subtitle: const Text('Funciona con la pantalla bloqueada. Mostrará una notificación permanente.'),
                ),
              ),
              AppSpacing.gapLg,
              SlButton(
                label: 'Mis alertas',
                icon: Icons.history_rounded,
                variant: SlButtonVariant.secondary,
                onPressed: () => context.go(AppRoutes.userHistory),
              ),
              AppSpacing.gapSm,
              SlButton(
                label: 'Cerrar sesión',
                icon: Icons.logout_rounded,
                variant: SlButtonVariant.secondary,
                onPressed: vm.cerrarSesion,
              ),
            ],
          );
        },
      ),
    );
  }
}
