// CAPA: PRESENTACIÓN — View
// G-06 Ruta hacia el usuario · G-07 Registro de llegada · Esperando confirmación
// Pinta mapa, distancia y el botón "Llegué" según lo que diga el ViewModel.
// No calcula geocercas ni llama repositorios.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/dominio.dart';
import '../comun/formato.dart';
import '../comun/rutas/app_routes.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'navegacion_view_model.dart';
import 'widgets/widgets_guardia.dart';

class NavegacionPage extends StatefulWidget {
  const NavegacionPage({super.key, required this.viewModel});
  final NavegacionViewModel viewModel;

  @override
  State<NavegacionPage> createState() => _NavegacionPageState();
}

class _NavegacionPageState extends State<NavegacionPage> {
  late final NavegacionViewModel vm = widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.addListener(_alCambiar);
    vm.iniciar();
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

  void _volverAlListado() => context.go(AppRoutes.guardAlerts);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('En camino')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => SlStateView<Alerta>(
          estado: vm.estado,
          onRetry: vm.iniciar,
          builder: (context, a) {
            if (a.estado == EstadoAlerta.guardiaEnLugar) return const EsperandoConfirmacionView();
            if (a.estado == EstadoAlerta.cerrada) return AlertaAtendidaView(alerta: a, onVolver: _volverAlListado);
            if (a.estado == EstadoAlerta.escalada) return AlertaEscaladaView(alerta: a, onVolver: _volverAlListado);

            final distancia = vm.distancia ?? 0;
            final dentro = vm.dentroDeGeocerca;
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: AppSpacing.screen,
                    children: [
                      MapaRutaGuardia(distancia: distancia),
                      AppSpacing.gapMd,
                      TarjetaUsuarioDistancia(alerta: a, distancia: distancia, dentro: dentro),
                      AppSpacing.gapMd,
                      SlButton(
                        label: 'Abrir en Google Maps',
                        icon: Icons.map_outlined,
                        variant: SlButtonVariant.secondary,
                        onPressed: () => context.showSnack('Pendiente (G-06): abrir Google Maps'),
                      ),
                      if (vm.modoDemo) ...[
                        AppSpacing.gapSm,
                        SlButton(
                          label: 'Simular acercamiento (demo)',
                          icon: Icons.directions_walk_rounded,
                          variant: SlButtonVariant.ghost,
                          onPressed: dentro ? null : vm.simularAcercamiento,
                        ),
                      ],
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: AppSpacing.screen,
                    child: SlButton(
                      label: dentro ? 'Llegué' : 'Llegué · faltan ${Fmt.distance(vm.metrosRestantes)}',
                      icon: Icons.where_to_vote_rounded,
                      variant: SlButtonVariant.success,
                      loading: vm.llegando,
                      onPressed: vm.puedeMarcarLlegada ? vm.marcarLlegada : null,
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
