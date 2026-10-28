// CAPA: PRESENTACIÓN — View
// U-01 Registro de usuario protegido
// Pinta el formulario y pasa los textos al ViewModel. No valida ni registra.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../comun/rutas/app_routes.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'registro_view_model.dart';

class RegistroPage extends StatefulWidget {
  const RegistroPage({super.key, required this.viewModel});
  final RegistroViewModel viewModel;

  @override
  State<RegistroPage> createState() => _RegistroPageState();
}

class _RegistroPageState extends State<RegistroPage> {
  late final RegistroViewModel vm = widget.viewModel;
  final _nombre = TextEditingController();
  final _correo = TextEditingController();
  final _telefono = TextEditingController();
  final _contrasena = TextEditingController();
  final _confirmacion = TextEditingController();

  @override
  void dispose() {
    for (final c in [_nombre, _correo, _telefono, _contrasena, _confirmacion]) {
      c.dispose();
    }
    vm.dispose();
    super.dispose();
  }

  Future<void> _alRegistrar() => vm.registrar(
        nombre: _nombre.text,
        correo: _correo.text,
        telefono: _telefono.text,
        contrasena: _contrasena.text,
        confirmacion: _confirmacion.text,
      );

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
          child: ListenableBuilder(
            listenable: vm,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tus datos se comparten con el guardia solo cuando envías una alerta.',
                  style: context.text.bodyMedium,
                ),
                AppSpacing.gapLg,
                if (vm.error != null) ...[SlBanner(message: vm.error!, type: SlBannerType.danger), AppSpacing.gapMd],
                SlTextField(label: 'Nombre completo', controller: _nombre, icon: Icons.person_outline_rounded, errorText: vm.errorNombre, textInputAction: TextInputAction.next),
                AppSpacing.gapMd,
                SlTextField(label: 'Correo electrónico', controller: _correo, icon: Icons.mail_outline_rounded, keyboardType: TextInputType.emailAddress, errorText: vm.errorCorreo, textInputAction: TextInputAction.next),
                AppSpacing.gapMd,
                SlTextField(label: 'Teléfono (10 dígitos)', controller: _telefono, icon: Icons.phone_outlined, keyboardType: TextInputType.phone, digitsOnly: true, maxLength: 10, errorText: vm.errorTelefono, textInputAction: TextInputAction.next),
                AppSpacing.gapMd,
                SlTextField(label: 'Contraseña', controller: _contrasena, icon: Icons.lock_outline_rounded, obscure: true, errorText: vm.errorContrasena),
                AppSpacing.gapMd,
                SlTextField(label: 'Confirmar contraseña', controller: _confirmacion, icon: Icons.lock_outline_rounded, obscure: true, errorText: vm.errorConfirmacion),
                AppSpacing.gapLg,
                SlButton(label: 'Registrarme', loading: vm.cargando, onPressed: _alRegistrar),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
