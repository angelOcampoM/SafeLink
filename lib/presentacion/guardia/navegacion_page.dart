// CAPA: PRESENTACIÓN — View
// G-06 Ruta hacia el usuario · G-07 Registro de llegada · Esperando confirmación
// Pinta mapa, distancia y el botón "Llegué" según lo que diga el ViewModel.
// No calcula geocercas ni llama repositorios.
//
// TODO(G-06): sustituir MapPlaceholder por GoogleMap.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/dominio.dart';
import '../comun/formato.dart';
import '../comun/rutas/app_routes.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'navegacion_view_model.dart';

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
            if (a.estado == EstadoAlerta.guardiaEnLugar) return const _EsperandoConfirmacion();
            if (a.estado == EstadoAlerta.cerrada) {
              return EmptyState(
                icon: Icons.check_circle_rounded,
                color: AppColors.success,
                title: 'Alerta atendida',
                message: '${a.nombreUsuario ?? 'El usuario'} confirmó la atención. ¡Buen trabajo!',
                action: SlButton(label: 'Volver al listado', expand: false, onPressed: () => context.go(AppRoutes.guardHome)),
              );
            }
            if (a.estado == EstadoAlerta.escalada) {
              return EmptyState(
                icon: Icons.priority_high_rounded,
                color: AppColors.warning,
                title: 'Alerta escalada',
                message: 'El administrador revisará esta alerta (${a.razonEscalamiento?.etiqueta ?? 'escalada'}).',
                action: SlButton(label: 'Volver al listado', expand: false, onPressed: () => context.go(AppRoutes.guardHome)),
              );
            }

            final distancia = vm.distancia ?? 0;
            final dentro = vm.dentroDeGeocerca;
            // Posición relativa del guardia en el mapa simulado (se acerca al centro).
            final f = (distancia / 3000).clamp(0.08, 0.9).toDouble();

            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: AppSpacing.screen,
                    children: [
                      MapPlaceholder(
                        height: 300,
                        showRoute: true,
                        radiusFraction: 0.08,
                        markers: [
                          MapMarker(offset: Offset(-f, f), color: AppColors.info, icon: Icons.shield_rounded),
                          const MapMarker(offset: Offset.zero, color: AppColors.emergency, icon: Icons.person_pin_circle_rounded),
                        ],
                      ),
                      AppSpacing.gapMd,
                      SlCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a.nombreUsuario ?? 'Usuario', style: context.text.titleMedium),
                                  Text(a.telefonoUsuario == null ? '' : Fmt.phone(a.telefonoUsuario!), style: context.text.bodySmall),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(Fmt.distance(distancia), style: context.text.displaySmall?.copyWith(color: dentro ? AppColors.success : AppColors.info)),
                                Text(dentro ? 'Dentro de la zona' : 'restantes', style: context.text.bodySmall),
                              ],
                            ),
                          ],
                        ),
                      ),
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

class _EsperandoConfirmacion extends StatelessWidget {
  const _EsperandoConfirmacion();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.hourglass_top_rounded,
      color: AppColors.info,
      title: 'Esperando confirmación',
      message: 'Registramos tu llegada. El usuario debe confirmar que fue atendido para cerrar la alerta.',
    );
  }
}
