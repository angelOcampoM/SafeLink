// CAPA: PRESENTACIÓN — View
// G-04 Detalle de alerta · G-05 Aceptación
// Pinta foto, mapa y datos; pasa la intención "Aceptar" y navega según el resultado.
// No valida si la alerta sigue disponible ni llama repositorios.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/dominio.dart';
import '../comun/formato.dart';
import '../comun/rutas/app_routes.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'detalle_alerta_view_model.dart';

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
            final distancia = vm.distancia;
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
                      _FotoEvidencia(url: a.fotoUrl),
                      AppSpacing.gapMd,
                      MapPlaceholder(
                        height: 200,
                        markers: [
                          const MapMarker(offset: Offset(-0.5, 0.5), color: AppColors.info, icon: Icons.shield_rounded),
                          MapMarker(offset: Offset.zero, color: AppColors.emergency, icon: Icons.person_pin_circle_rounded, heading: a.rumbo),
                        ],
                      ),
                      AppSpacing.gapMd,
                      SlCard(
                        child: Column(
                          children: [
                            InfoRow(icon: Icons.schedule_rounded, label: 'Hora', value: '${Fmt.time(a.disparadaEn)} · ${Fmt.ago(a.disparadaEn, vm.ahora)}'),
                            if (distancia != null)
                              InfoRow(icon: Icons.near_me_outlined, label: 'Distancia', value: Fmt.distance(distancia), valueColor: AppColors.info),
                            if (a.rumbo != null)
                              InfoRow(icon: Icons.explore_outlined, label: 'Rumbo de la cámara', value: '${a.rumbo}° ${ReglaGeocerca.puntoCardinal(a.rumbo!)}'),
                            InfoRow(icon: a.metodo.style.icon, label: 'Método', value: a.metodo.etiqueta),
                          ],
                        ),
                      ),
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

class _FotoEvidencia extends StatelessWidget {
  const _FotoEvidencia({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      height: 200,
      color: AppColors.surface,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined, color: AppColors.textMuted, size: AppSizes.iconLg),
          AppSpacing.gapXs,
          Text(url == null ? 'Evidencia incompleta: sin foto' : 'No se pudo cargar la foto', style: context.text.bodyMedium),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: AppRadius.brMd,
      child: url == null
          ? placeholder
          : Image.network(
              url!,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
              loadingBuilder: (_, child, p) => p == null ? child : const SizedBox(height: 200, child: LoadingView()),
            ),
    );
  }
}
