// CAPA: PRESENTACIÓN — View
// G-04 Detalle de alerta · G-05 Aceptación
// Pinta foto, mapa y datos; pasa la intención "Aceptar" y navega según el resultado.
// No valida si la alerta sigue disponible ni llama repositorios.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/dominio.dart';
import '../comun/rutas/app_routes.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'detalle_alerta_view_model.dart';
import 'widgets/widgets_guardia.dart';

class DetalleAlertaPage extends StatefulWidget {
  const DetalleAlertaPage({super.key, required this.viewModel});
  final DetalleAlertaViewModel viewModel;

  @override
  State<DetalleAlertaPage> createState() => _DetalleAlertaPageState();
}

class _DetalleAlertaPageState extends State<DetalleAlertaPage> {
  late final DetalleAlertaViewModel vm = widget.viewModel;

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

  Future<void> _alAceptar() async {
    final ok = await vm.aceptar();
    if (!mounted) return;
    if (ok) {
      context.pushReplacement(AppRoutes.guardNavigation(vm.alertaId));
    } else if (vm.error != null) {
      context.showSnack(vm.error!);
      if (vm.alertaTomada) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de alerta')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => SlStateView<DetalleAlerta>(
          estado: vm.estado,
          onRetry: vm.cargar,
          builder: (context, d) {
            final a = d.alerta;
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: AppSpacing.screen,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(a.nombreUsuario ?? 'Usuario', style: context.text.headlineSmall)),
                          TriggerChip(a.metodo),
                        ],
                      ),
                      AppSpacing.gapMd,
                      FotoEvidencia(url: a.fotoUrl),
                      AppSpacing.gapMd,
                      MapaDetalleAlerta(rumbo: a.rumbo),
                      AppSpacing.gapMd,
                      TarjetaDatosAlerta(alerta: a, ahora: vm.ahora, distancia: vm.distancia),
                      if (a.estado != EstadoAlerta.buscando) ...[
                        AppSpacing.gapMd,
                        SlBanner(type: SlBannerType.warning, message: 'Esta alerta ya está ${a.estado.etiqueta.toLowerCase()}.'),
                      ],
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: AppSpacing.screen,
                    child: SlButton(
                      label: 'Aceptar alerta',
                      icon: Icons.check_rounded,
                      loading: vm.aceptando,
                      onPressed: vm.puedeAceptar ? _alAceptar : null,
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
