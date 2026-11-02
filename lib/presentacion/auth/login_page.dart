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
        child: CenteredContent(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ListenableBuilder(
            listenable: vm,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BrandMark(tagline: 'Tu protección, siempre a tu alcance'),
                AppSpacing.gapXl,
                SlCard(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Bienvenido de nuevo', style: context.text.headlineSmall),
                      AppSpacing.gapXxs,
                      Text('Ingresa tus datos para continuar.', style: context.text.bodyMedium),
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
                      SlButton(label: 'Iniciar sesión', loading: vm.cargando, onPressed: _alEntrar),
                      AppSpacing.gapXs,
                      SlButton(
                        label: 'Crear cuenta',
                        variant: SlButtonVariant.ghost,
                        onPressed: () => context.go(AppRoutes.register),
                      ),
                    ],
                  ),
                ),
                AppSpacing.gapLg,
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: AppSizes.iconSm, color: AppColors.textSecondary),
                    AppSpacing.gapXs,
                    Flexible(
                      child: Text(
                        'Solo los usuarios protegidos pueden registrarse por sí mismos.',
                        style: context.text.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                if (vm.modoDemo) ...[
                  AppSpacing.gapXl,
                  const SectionHeader('Cuentas de prueba (demo)'),
                  Wrap(
                    alignment: WrapAlignment.center,
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
    );
  }
}
