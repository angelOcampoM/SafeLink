// U-02 · G-01 — Inicio de sesión (compartida por los tres roles).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_config.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/validators.dart';
import '../../data/mock/mock_seed.dart';
import '../../data/repositories/repository_exceptions.dart';
import '../../shared/widgets/widgets.dart';
import 'session_controller.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<SessionController>().login(_email.text, _password.text);
      // El router redirige solo según el rol.
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fill(String email) {
    _email.text = email;
    _password.text = MockSeed.password;
  }

  @override
  Widget build(BuildContext context) {
    final isMock = context.read<AppConfig>().useMockData;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Logo(),
                    AppSpacing.gapXl,
                    Text('Inicia sesión', style: context.text.headlineMedium),
                    AppSpacing.gapXs,
                    Text('Ayuda cerca de ti, cuando la necesitas.', style: context.text.bodyMedium),
                    AppSpacing.gapLg,
                    if (_error != null) ...[
                      SlBanner(message: _error!, type: SlBannerType.danger),
                      AppSpacing.gapMd,
                    ],
                    SlTextField(
                      label: 'Correo electrónico',
                      controller: _email,
                      icon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      validator: Validators.email,
                    ),
                    AppSpacing.gapMd,
                    SlTextField(
                      label: 'Contraseña',
                      controller: _password,
                      icon: Icons.lock_outline_rounded,
                      obscure: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      validator: (v) => Validators.required(v, message: 'Escribe tu contraseña'),
                    ),
                    AppSpacing.gapLg,
                    SlButton(label: 'Entrar', icon: Icons.login_rounded, loading: _loading, onPressed: _submit),
                    AppSpacing.gapSm,
                    SlButton(
                      label: 'Crear cuenta',
                      variant: SlButtonVariant.secondary,
                      onPressed: () => context.go(AppRoutes.register),
                    ),
                    if (isMock) ...[
                      AppSpacing.gapXl,
                      const SectionHeader('Cuentas de prueba (mock)'),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (final (label, email) in const [
                            ('Usuario', 'usuario@safelink.mx'),
                            ('Bloqueado', 'bloqueado@safelink.mx'),
                            ('Guardia', 'guardia@safelink.mx'),
                            ('Admin', 'admin@safelink.mx'),
                          ])
                            ActionChip(label: Text(label), onPressed: () => _fill(email)),
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
          decoration: BoxDecoration(color: AppColors.tint(AppColors.emergency), borderRadius: AppRadius.brMd),
          child: const Icon(Icons.shield_rounded, color: AppColors.emergency, size: AppSizes.iconLg),
        ),
        AppSpacing.gapSm,
        Text('SafeLink', style: context.text.headlineMedium),
      ],
    );
  }
}
