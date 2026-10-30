// CAPA: PRESENTACIÓN — View
// A-05 Detalle de una alerta del historial del admin (pantalla completa)
// Reutiliza AlertDetailSheet para mostrar evidencia, aceptación, llegada y
// cierre. No carga datos ni conoce repositorios.

import 'package:flutter/material.dart';

import '../comun/estado_vista.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'detalle_alerta_admin_view_model.dart';

class DetalleAlertaAdminPage extends StatefulWidget {
  const DetalleAlertaAdminPage({super.key, required this.viewModel});
  final DetalleAlertaAdminViewModel viewModel;

  @override
  State<DetalleAlertaAdminPage> createState() => _DetalleAlertaAdminPageState();
}

class _DetalleAlertaAdminPageState extends State<DetalleAlertaAdminPage> {
  late final DetalleAlertaAdminViewModel vm = widget.viewModel;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de la alerta')),
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
          Listo(datos: final a) => SingleChildScrollView(child: AlertDetailSheet(alert: a)),
        },
      ),
    );
  }
}
