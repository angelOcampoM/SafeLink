// CAPA: PRESENTACIÓN — View
// U-07 Ubicación en tiempo real · U-08 Guardia asignado y ETA · U-09 Confirmación
// Pinta el estado de la alerta activa y pasa la intención "Ya fui atendido".
// No escucha streams ni decide si se puede confirmar.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/dominio.dart';
import '../comun/formato.dart';
import '../comun/rutas/app_routes.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'estado_alerta_view_model.dart';

class EstadoAlertaPage extends StatefulWidget {
  const EstadoAlertaPage({super.key, required this.viewModel});
  final EstadoAlertaViewModel viewModel;

  @override
  State<EstadoAlertaPage> createState() => _EstadoAlertaPageState();
}

class _EstadoAlertaPageState extends State<EstadoAlertaPage> {
  late final EstadoAlertaViewModel vm = widget.viewModel;

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
    if (vm.irAInicio) context.go(AppRoutes.userHome);
    vm.consumirEventos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(AppRoutes.userHome)),
        title: const Text('Mi alerta'),
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => SlStateView<Alerta>(
          estado: vm.estado,
          onRetry: vm.reintentar,
          empty: EmptyState(
            icon: Icons.verified_user_outlined,
            color: AppColors.success,
            title: 'Sin alertas activas',
            message: 'Cuando envíes una alerta, aquí verás al guardia que va en camino.',
            action: SlButton(label: 'Volver al inicio', expand: false, onPressed: () => context.go(AppRoutes.userHome)),
          ),
          builder: (context, a) => ListView(
            padding: AppSpacing.screen,
            children: [
              _Encabezado(alerta: a),
              AppSpacing.gapLg,
              if (a.evidenciaIncompleta) ...[
                const SlBanner(type: SlBannerType.warning, message: 'No se pudo tomar la foto. Tu alerta se envió con evidencia incompleta.'),
                AppSpacing.gapMd,
              ],
              if (a.estado == EstadoAlerta.pendienteUbicacion) ...[
                const SlBanner(
                  type: SlBannerType.warning,
                  title: 'Esperando ubicación',
                  message: 'Activa el GPS. Tu alerta se publicará en cuanto tengamos tu ubicación.',
                ),
                AppSpacing.gapMd,
              ],
              if (a.nombreGuardia != null) ...[
                _TarjetaGuardia(alerta: a),
                AppSpacing.gapMd,
              ],
              MapPlaceholder(
                markers: [
                  if (a.estado == EstadoAlerta.enAtencion)
                    MapMarker(offset: Offset(-0.6, 0.5 - (300 - (a.etaSegundos ?? 300)) / 600), color: AppColors.info, icon: Icons.shield_rounded),
                  const MapMarker(offset: Offset(0.3, -0.2), color: AppColors.emergency, icon: Icons.person_pin_circle_rounded),
                ],
                showRoute: a.estado == EstadoAlerta.enAtencion,
              ),
              AppSpacing.gapMd,
              Text(
                'Tu ubicación se comparte en tiempo real mientras la alerta esté activa.',
                style: context.text.bodySmall,
                textAlign: TextAlign.center,
              ),
              AppSpacing.gapLg,
              SlButton(
                label: 'Ya fui atendido',
                icon: Icons.check_circle_outline_rounded,
                variant: SlButtonVariant.success,
                loading: vm.confirmando,
                // U-09: solo habilitado tras la llegada del guardia.
                onPressed: vm.puedeConfirmar ? vm.confirmar : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.alerta});
  final Alerta alerta;

  @override
  Widget build(BuildContext context) {
    final s = alerta.estado.style;
    final subtitulo = switch (alerta.estado) {
      EstadoAlerta.buscando => 'Notificamos a los guardias cercanos.',
      EstadoAlerta.enAtencion => 'Un guardia va en camino.',
      EstadoAlerta.guardiaEnLugar => 'El guardia llegó a tu ubicación.',
      EstadoAlerta.pendienteUbicacion => 'Aún no se publica.',
      _ => '',
    };
    return SlCard(
      accent: s.color,
      child: Row(
        children: [
          Icon(s.icon, color: s.color, size: AppSizes.iconLg),
          AppSpacing.gapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.label, style: context.text.headlineSmall),
                Text(subtitulo, style: context.text.bodyMedium),
              ],
            ),
          ),
          if (alerta.estado == EstadoAlerta.buscando)
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.emergency)),
        ],
      ),
    );
  }
}

class _TarjetaGuardia extends StatelessWidget {
  const _TarjetaGuardia({required this.alerta});
  final Alerta alerta;

  @override
  Widget build(BuildContext context) {
    return SlCard(
      child: Row(
        children: [
          InitialsAvatar(Usuario.inicialesDe(alerta.nombreGuardia), color: AppColors.info, size: 52),
          AppSpacing.gapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tu guardia', style: context.text.bodySmall),
                Text(alerta.nombreGuardia!, style: context.text.titleMedium),
              ],
            ),
          ),
          if (alerta.estado == EstadoAlerta.enAtencion && alerta.etaSegundos != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Fmt.duration(alerta.etaSegundos!), style: context.text.displaySmall?.copyWith(color: AppColors.info)),
                Text('llegada aprox.', style: context.text.bodySmall),
              ],
            ),
        ],
      ),
    );
  }
}
