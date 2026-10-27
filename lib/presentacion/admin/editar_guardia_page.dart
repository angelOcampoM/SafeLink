// CAPA: PRESENTACIÓN — View
// A-01 Alta de guardia · A-02 Edición de guardia
// Formulario; los errores por campo los da el ViewModel. No valida ni guarda.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/guardia.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'editar_guardia_view_model.dart';

class EditarGuardiaPage extends StatefulWidget {
  const EditarGuardiaPage({super.key, required this.viewModel});
  final EditarGuardiaViewModel viewModel;

  @override
  State<EditarGuardiaPage> createState() => _EditarGuardiaPageState();
}

class _EditarGuardiaPageState extends State<EditarGuardiaPage> {
  late final EditarGuardiaViewModel vm = widget.viewModel;
  final _nombre = TextEditingController();
  final _correo = TextEditingController();
  final _telefono = TextEditingController();
  var _rellenado = false;

  @override
  void initState() {
    super.initState();
    vm.cargar();
  }

  @override
  void dispose() {
    for (final c in [_nombre, _correo, _telefono]) {
      c.dispose();
    }
    vm.dispose();
    super.dispose();
  }

  void _rellenar(Guardia? g) {
    if (_rellenado || g == null) return;
    _rellenado = true;
    _nombre.text = g.usuario.nombre;
    _correo.text = g.usuario.correo;
    _telefono.text = g.usuario.telefono;
  }

  Future<void> _alGuardar() async {
    final ok = await vm.guardar(nombre: _nombre.text, correo: _correo.text, telefono: _telefono.text);
    if (!ok || !mounted) return;
    context.showSnack(vm.esEdicion ? 'Datos actualizados' : 'Guardia dado de alta. Contraseña inicial: SafeLink1');
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(vm.esEdicion ? 'Editar guardia' : 'Nuevo guardia')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => SlStateView<Guardia?>(
          estado: vm.estado,
          onRetry: vm.cargar,
          builder: (context, g) {
            _rellenar(g);
            return ListView(
              padding: AppSpacing.screen,
              children: [
                if (vm.error != null) ...[SlBanner(message: vm.error!, type: SlBannerType.danger), AppSpacing.gapMd],
                SlTextField(label: 'Nombre completo', controller: _nombre, icon: Icons.person_outline_rounded, errorText: vm.errorNombre),
                AppSpacing.gapMd,
                SlTextField(label: 'Correo', controller: _correo, icon: Icons.mail_outline_rounded, keyboardType: TextInputType.emailAddress, errorText: vm.errorCorreo),
                AppSpacing.gapMd,
                SlTextField(label: 'Teléfono', controller: _telefono, icon: Icons.phone_outlined, keyboardType: TextInputType.phone, digitsOnly: true, maxLength: 10, errorText: vm.errorTelefono),
                AppSpacing.gapLg,
                SlButton(label: 'Guardar', icon: Icons.save_outlined, loading: vm.guardando, onPressed: _alGuardar),
              ],
            );
          },
        ),
      ),
    );
  }
}
