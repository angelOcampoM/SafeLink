// CAPA: PRESENTACIÓN — View
// U-05 Configuración (activar/desactivar agitación) · U-02 Revisar permisos
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
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
              child: ListView(
                padding: AppSpacing.screen,
                children: [
                  const SectionHeader('Protección'),
                  SlCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: user.agitacionActiva,
                          onChanged: vm.guardando ? null : vm.cambiarAgitacion,
                          secondary: const _IconoOpcion(Icons.vibration_rounded),
                          title: const Text('Alerta por agitación'),
                          subtitle: Text(
                            user.agitacionActiva ? 'Activada' : 'Desactivada',
                            style: context.text.bodySmall?.copyWith(
                              color: user.agitacionActiva ? AppColors.success : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                          child: SlBanner(
                            icon: Icons.lock_outline_rounded,
                            message: 'Funciona incluso con la pantalla bloqueada. Mientras esté activa verás una notificación permanente.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  AppSpacing.gapLg,
                  const SectionHeader('Cuenta'),
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
                  AppSpacing.gapSm,
                  SlCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _Opcion(
                          icon: Icons.history_rounded,
                          title: 'Mis alertas',
                          subtitle: 'Alertas enviadas y cómo terminaron',
                          onTap: () => context.go(AppRoutes.userHistory),
                        ),
                        const Divider(height: 1),
                        _Opcion(
                          icon: Icons.privacy_tip_outlined,
                          title: 'Privacidad y permisos',
                          subtitle: 'Cámara, ubicación y notificaciones',
                          onTap: vm.revisarPermisos,
                        ),
                      ],
                    ),
                  ),
                  AppSpacing.gapLg,
                  SlButton(
                    label: 'Cerrar sesión',
                    icon: Icons.logout_rounded,
                    variant: SlButtonVariant.danger,
                    onPressed: vm.cerrarSesion,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _IconoOpcion extends StatelessWidget {
  const _IconoOpcion(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(color: AppColors.tint(AppColors.info), borderRadius: AppRadius.brSm),
      child: Icon(icon, color: AppColors.info, size: AppSizes.iconMd),
    );
  }
}

/// Fila tocable de la sección "Cuenta".
class _Opcion extends StatelessWidget {
  const _Opcion({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _IconoOpcion(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }
}
