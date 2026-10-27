// CAPA: PRESENTACIÓN — View
// U-02 Inicio de sesión · G-01 Login del guardia
// Lee el estado del ViewModel y le pasa intenciones (entrar).
// No valida, no llama repositorios y no sabe si hay memoria o nube.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../comun/rutas/app_routes.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'login_view_model.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.viewModel});
  final LoginViewModel viewModel;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final LoginViewModel vm = widget.viewModel;
  final _correo = TextEditingController();
  final _contrasena = TextEditingController();

  @override
  void dispose() {
    _correo.dispose();
    _contrasena.dispose();
    vm.dispose();
    super.dispose();
  }

  // El router redirige solo según el rol.
  Future<void> _alEntrar() => vm.entrar(_correo.text, _contrasena.text);

  void _rellenar(String correo) {
    _correo.text = correo;
    _contrasena.text = vm.contrasenaDemo;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ListenableBuilder(
                listenable: vm,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Logo(),
                    AppSpacing.gapXl,
                    Text('Inicia sesión', style: context.text.headlineMedium),
                    AppSpacing.gapXs,
                    Text('Ayuda cerca de ti, cuando la necesitas.', style: context.text.bodyMedium),
                    AppSpacing.gapLg,
                    if (vm.error != null) ...[
                      SlBanner(message: vm.error!, type: SlBannerType.danger),
                      AppSpacing.gapMd,
                    ],
                    SlTextField(
                      label: 'Correo electrónico',
                      controller: _correo,
                      icon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      errorText: vm.errorCorreo,
                    ),
                    AppSpacing.gapMd,
                    SlTextField(
                      label: 'Contraseña',
                      controller: _contrasena,
                      icon: Icons.lock_outline_rounded,
                      obscure: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _alEntrar(),
                      errorText: vm.errorContrasena,
                    ),
                    AppSpacing.gapLg,
                    SlButton(label: 'Entrar', icon: Icons.login_rounded, loading: vm.cargando, onPressed: _alEntrar),
                    AppSpacing.gapSm,
                    SlButton(
                      label: 'Crear cuenta',
                      variant: SlButtonVariant.secondary,
                      onPressed: () => context.go(AppRoutes.register),
                    ),
                    if (vm.modoDemo) ...[
                      AppSpacing.gapXl,
                      const SectionHeader('Cuentas de prueba (demo)'),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (final (etiqueta, correo) in vm.cuentasDemo)
                            ActionChip(label: Text(etiqueta), onPressed: () => _rellenar(correo)),
                        ],
                      ),
                    ],
                    if (kDebugMode) ...[
                      AppSpacing.gapMd,
                      SlButton(
                        label: 'Ver guía de estilos',
                        icon: Icons.palette_outlined,
                        variant: SlButtonVariant.ghost,
                        onPressed: () => context.push(AppRoutes.styleGuide),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(color: AppColors.tint(AppColors.info), borderRadius: AppRadius.brMd),
          child: const Icon(Icons.shield_rounded, color: AppColors.info, size: AppSizes.iconLg),
        ),
        AppSpacing.gapSm,
        Text('SafeLink', style: context.text.headlineMedium),
      ],
    );
  }
}
