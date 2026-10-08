// U-01 — Registro de usuario protegido.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/app_routes.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/validators.dart';
import '../../data/repositories/repository_exceptions.dart';
import '../../shared/widgets/widgets.dart';
import 'session_controller.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<SessionController>().register(
            name: _name.text,
            email: _email.text,
            phone: _phone.text,
            password: _password.text,
          );
      // TODO(U-01): mostrar pantalla de permisos (cámara, ubicación, notificaciones).
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(AppRoutes.login)),
        title: const Text('Crear cuenta'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.screen,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tus datos se comparten con el guardia solo cuando envías una alerta.',
                  style: context.text.bodyMedium,
                ),
                AppSpacing.gapLg,
                if (_error != null) ...[SlBanner(message: _error!, type: SlBannerType.danger), AppSpacing.gapMd],
                SlTextField(label: 'Nombre completo', controller: _name, icon: Icons.person_outline_rounded, validator: Validators.name, textInputAction: TextInputAction.next),
                AppSpacing.gapMd,
                SlTextField(label: 'Correo electrónico', controller: _email, icon: Icons.mail_outline_rounded, keyboardType: TextInputType.emailAddress, validator: Validators.email, textInputAction: TextInputAction.next),
                AppSpacing.gapMd,
                SlTextField(label: 'Teléfono (10 dígitos)', controller: _phone, icon: Icons.phone_outlined, keyboardType: TextInputType.phone, digitsOnly: true, maxLength: 10, validator: Validators.phone, textInputAction: TextInputAction.next),
                AppSpacing.gapMd,
                SlTextField(label: 'Contraseña', controller: _password, icon: Icons.lock_outline_rounded, obscure: true, validator: Validators.password),
                AppSpacing.gapMd,
                SlTextField(
                  label: 'Confirmar contraseña',
                  icon: Icons.lock_outline_rounded,
                  obscure: true,
                  validator: Validators.confirmPassword(() => _password.text),
                ),
                AppSpacing.gapLg,
                SlButton(label: 'Registrarme', loading: _loading, onPressed: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
