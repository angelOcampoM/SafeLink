// CAPA: PRESENTACIÓN — View
// U-06 Evidencia · U-07 Ubicación en tiempo real · U-08 Guardia asignado y ETA · U-09 Confirmación
// Pinta el estado de la alerta activa y pasa la intención "Ya fui atendido".
// No escucha streams ni decide si se puede confirmar.
// U-08: el usuario NO ve la ubicación del guardia, por eso aquí no hay mapa.

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
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => context.go(AppRoutes.userHome)),
          title: Text(
            switch (vm.alerta?.estado) {
              EstadoAlerta.enAtencion => 'Ayuda en camino',
              EstadoAlerta.guardiaEnLugar => 'Atención en sitio',
              null => 'Mi alerta',
              _ => 'Alerta enviada',
            },
          ),
        ),
        body: SafeArea(
          child: SlStateView<Alerta>(
            estado: vm.estado,
            onRetry: vm.reintentar,
            empty: EmptyState(
              icon: Icons.verified_user_outlined,
              color: AppColors.success,
              title: 'Sin alertas activas',
              message: 'Cuando envíes una alerta, aquí verás al guardia que va en camino.',
              action: SlButton(label: 'Volver al inicio', expand: false, onPressed: () => context.go(AppRoutes.userHome)),
            ),
            builder: (context, a) => CenteredContent(
              child: switch (a.estado) {
                EstadoAlerta.enAtencion => _EnCamino(alerta: a),
                EstadoAlerta.guardiaEnLugar => _GuardiaLlego(
                    alerta: a,
                    confirmando: vm.confirmando,
                    onConfirmar: vm.puedeConfirmar ? vm.confirmar : null,
                  ),
                _ => _Buscando(alerta: a),
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Encabezado común: halo, chip de estado, título y descripción, centrados.
class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.halo, required this.chip, required this.titulo, required this.texto});

  final Widget halo;
  final Widget? chip;
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        halo,
        AppSpacing.gapLg,
        if (chip != null) ...[chip!, AppSpacing.gapSm],
        Text(titulo, style: context.text.headlineMedium, textAlign: TextAlign.center),
        AppSpacing.gapXs,
        Text(texto, style: context.text.bodyMedium, textAlign: TextAlign.center),
      ],
    );
  }
}

/// U-07: indicador visible de que la ubicación se comparte.
class _ChipUbicacion extends StatelessWidget {
  const _ChipUbicacion();

  @override
  Widget build(BuildContext context) =>
      const SlChip(label: 'Compartiendo ubicación en tiempo real', color: AppColors.success, icon: Icons.my_location_rounded);
}

// ── Buscando guardia / pendiente de ubicación (U-06 · U-08) ──
class _Buscando extends StatelessWidget {
  const _Buscando({required this.alerta});
  final Alerta alerta;

  @override
  Widget build(BuildContext context) {
    final sinUbicacion = alerta.estado == EstadoAlerta.pendienteUbicacion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sinUbicacion
            ? const _Encabezado(
                halo: StatusHalo(icon: Icons.location_disabled_rounded, color: AppColors.warning),
                chip: null,
                titulo: 'Esperando ubicación',
                texto: 'Activa el GPS. Tu alerta se publicará en cuanto tengamos tu ubicación.',
              )
            : const _Encabezado(
                halo: StatusHalo(icon: Icons.sensors_rounded, color: AppColors.emergency),
                chip: _ChipUbicacion(),
                titulo: 'Buscando guardia',
                texto: 'Tu alerta está activa. Mantén el teléfono contigo mientras asignamos ayuda.',
              ),
        AppSpacing.gapXl,
        SlCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Información enviada', style: context.text.titleMedium),
              AppSpacing.gapXs,
              _Dato(
                ok: !alerta.evidenciaIncompleta,
                icon: Icons.photo_camera_outlined,
                texto: alerta.evidenciaIncompleta ? 'Foto no disponible (evidencia incompleta)' : 'Foto capturada',
              ),
              _Dato(
                ok: alerta.ubicacion != null && !sinUbicacion,
                icon: Icons.location_on_outlined,
                texto: sinUbicacion ? 'Ubicación pendiente' : 'Ubicación precisa',
              ),
              _Dato(
                ok: alerta.rumbo != null,
                icon: Icons.explore_outlined,
                texto: alerta.rumbo != null ? 'Rumbo detectado' : 'Rumbo no disponible',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fila de "Información enviada": palomita verde o aviso ámbar.
class _Dato extends StatelessWidget {
  const _Dato({required this.ok, required this.icon, required this.texto});

  final bool ok;
  final IconData icon;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.success : AppColors.warning;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded, size: AppSizes.iconSm, color: color),
          AppSpacing.gapSm,
          Icon(icon, size: AppSizes.iconSm, color: AppColors.textSecondary),
          AppSpacing.gapXs,
          Expanded(child: Text(texto, style: context.text.bodyMedium)),
        ],
      ),
    );
  }
}

// ── Guardia asignado, en camino (U-08) ──
class _EnCamino extends StatelessWidget {
  const _EnCamino({required this.alerta});
  final Alerta alerta;

  @override
  Widget build(BuildContext context) {
    final nombre = alerta.nombreGuardia ?? 'Tu guardia';
    final eta = alerta.etaSegundos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: _ChipUbicacion()),
        AppSpacing.gapLg,
        SlCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              InitialsAvatar(Usuario.inicialesDe(nombre), color: AppColors.info, size: 88),
              AppSpacing.gapMd,
              Text(nombre, style: context.text.headlineSmall, textAlign: TextAlign.center),
              AppSpacing.gapXxs,
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.verified_outlined, size: AppSizes.iconSm, color: AppColors.info),
                  AppSpacing.gapXxs,
                  Text('Guardia verificado', style: context.text.bodySmall?.copyWith(color: AppColors.info)),
                ],
              ),
              AppSpacing.gapLg,
              Container(
                width: double.infinity,
                padding: AppSpacing.card,
                decoration: BoxDecoration(
                  color: AppColors.tint(AppColors.warning),
                  borderRadius: AppRadius.brMd,
                  border: Border.all(color: AppColors.tintBorder(AppColors.warning)),
                ),
                child: Column(
                  children: [
                    Text('ACTUALIZANDO EN VIVO', style: context.text.labelSmall?.copyWith(color: AppColors.warning, letterSpacing: 1.2)),
                    AppSpacing.gapXxs,
                    Text(
                      eta == null ? 'Calculando llegada…' : 'Llega en ${Fmt.duration(eta)}',
                      style: context.text.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        AppSpacing.gapMd,
        SlBanner(message: '${_primerNombre(nombre)} se dirige a tu ubicación. No necesitas compartir indicaciones adicionales.'),
        if (alerta.evidenciaIncompleta) ...[
          AppSpacing.gapSm,
          const SlBanner(type: SlBannerType.warning, message: 'No se pudo tomar la foto. Tu alerta se envió con evidencia incompleta.'),
        ],
      ],
    );
  }
}

// ── Guardia llegó: confirmar atención (U-09) ──
class _GuardiaLlego extends StatelessWidget {
  const _GuardiaLlego({required this.alerta, required this.confirmando, required this.onConfirmar});

  final Alerta alerta;
  final bool confirmando;
  final VoidCallback? onConfirmar;

  @override
  Widget build(BuildContext context) {
    final nombre = alerta.nombreGuardia ?? 'Tu guardia';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Encabezado(
          halo: const StatusHalo(icon: Icons.verified_user_outlined, color: AppColors.success),
          chip: const SlChip(label: 'Guardia en tu ubicación', color: AppColors.success, icon: Icons.check_circle_outline_rounded),
          titulo: '${_primerNombre(nombre)} ya llegó',
          texto: 'El guardia confirmó su llegada. Verifica su nombre y credencial antes de finalizar la alerta.',
        ),
        AppSpacing.gapXl,
        SlCard(
          accent: AppColors.success,
          child: Row(
            children: [
              InitialsAvatar(Usuario.inicialesDe(nombre), color: AppColors.success, size: 52),
              AppSpacing.gapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nombre, style: context.text.titleMedium),
                    Text('Guardia SafeLink', style: context.text.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.check_circle_outline_rounded, color: AppColors.success),
            ],
          ),
        ),
        AppSpacing.gapXl,
        SlButton(
          label: 'Ya fui atendido',
          icon: Icons.check_circle_outline_rounded,
          variant: SlButtonVariant.success,
          loading: confirmando,
          onPressed: onConfirmar,
        ),
        AppSpacing.gapSm,
        Text(
          'Al confirmar, dejaremos de compartir tu ubicación.',
          style: context.text.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

String _primerNombre(String nombreCompleto) => nombreCompleto.trim().split(RegExp(r'\s+')).first;
