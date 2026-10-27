// CAPA: PRESENTACIÓN — View
// U-03 Toque simple · U-04 Mantener presionado · U-05 Agitación · U-06 Evidencia
// Pinta el botón de emergencia y le pasa los gestos al ViewModel. Solo calcula
// si el dedo está sobre "Descartar" (geometría de pantalla).
// No envía alertas, no valida y no sabe si hay memoria o nube.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../comun/rutas/app_routes.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'inicio_view_model.dart';

class InicioPage extends StatefulWidget {
  const InicioPage({super.key, required this.viewModel});
  final InicioViewModel viewModel;

  @override
  State<InicioPage> createState() => _InicioPageState();
}

class _InicioPageState extends State<InicioPage> {
  late final InicioViewModel vm = widget.viewModel;
  final _zonaDescarte = GlobalKey();

  @override
  void initState() {
    super.initState();
    vm.addListener(_alCambiar);
  }

  @override
  void dispose() {
    vm.removeListener(_alCambiar);
    vm.dispose();
    super.dispose();
  }

  void _alCambiar() {
    if (vm.mensaje != null) context.showSnack(vm.mensaje!);
    if (vm.irAMiAlerta) context.go(AppRoutes.userAlert);
    vm.consumirEventos();
  }

  bool _sobreDescarte(Offset global) {
    final box = _zonaDescarte.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    return rect.inflate(AppSpacing.md).contains(global);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text('Hola, ${vm.primerNombre}'),
          actions: [
            IconButton(
              tooltip: 'Mi alerta activa',
              icon: const Icon(Icons.notifications_active_outlined),
              onPressed: () => context.go(AppRoutes.userAlert),
            ),
            IconButton(
              tooltip: 'Mis alertas',
              icon: const Icon(Icons.history_rounded),
              onPressed: () => context.go(AppRoutes.userHistory),
            ),
            IconButton(
              tooltip: 'Configuración',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.go(AppRoutes.userSettings),
            ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: AppSpacing.screen,
                child: Column(
                  children: [
                    if (vm.agitacionActiva) ...[
                      SlBanner(
                        type: SlBannerType.success,
                        icon: Icons.vibration_rounded,
                        message: 'Agitación activa: puedes enviar una alerta agitando el teléfono.',
                        action: vm.config.modoDemo
                            ? TextButton.icon(
                                onPressed: vm.botonHabilitado ? vm.agitar : null,
                                icon: const Icon(Icons.vibration_rounded),
                                label: const Text('Simular agitación (demo)'),
                              )
                            : null,
                      ),
                    ],
                    const Spacer(),
                    EmergencyButton(
                      enabled: vm.botonHabilitado,
                      pressed: vm.manteniendo,
                      caption: 'Toca o mantén presionado',
                      onTap: vm.tocar,
                      onLongPressStart: (_) => vm.empezarMantener(),
                      onLongPressMoveUpdate: (d) => vm.moverMantener(sobreDescarte: _sobreDescarte(d.globalPosition)),
                      onLongPressEnd: (d) {
                        vm.moverMantener(sobreDescarte: _sobreDescarte(d.globalPosition));
                        vm.soltarMantener();
                      },
                    ),
                    AppSpacing.gapLg,
                    Text(
                      vm.manteniendo
                          ? 'Suelta para enviar · Arrastra a Descartar para cancelar'
                          : 'Toca para enviar en ${vm.config.segundosCuentaRegresiva} s o mantén presionado',
                      style: context.text.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(),
                    AnimatedOpacity(
                      opacity: vm.manteniendo ? 1 : 0,
                      duration: AppDurations.fast,
                      child: _ZonaDescarte(key: _zonaDescarte, activa: vm.sobreDescarte),
                    ),
                    AppSpacing.gapMd,
                  ],
                ),
              ),
              if (vm.cuentaRegresiva != null) _CuentaRegresiva(segundos: vm.cuentaRegresiva!, onCancel: vm.cancelarCuenta),
              if (vm.enviando)
                Container(
                  color: AppColors.background.withValues(alpha: 0.8),
                  child: const LoadingView(message: 'Enviando alerta…'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZonaDescarte extends StatelessWidget {
  const _ZonaDescarte({super.key, required this.activa});
  final bool activa;

  @override
  Widget build(BuildContext context) {
    final color = activa ? AppColors.danger : AppColors.textSecondary;
    return AnimatedContainer(
      duration: AppDurations.fast,
      width: 180,
      height: 72,
      decoration: BoxDecoration(
        color: activa ? AppColors.tint(AppColors.danger) : AppColors.surface,
        borderRadius: AppRadius.brPill,
        border: Border.all(color: activa ? AppColors.danger : AppColors.border, width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.delete_outline_rounded, color: color),
          AppSpacing.gapXs,
          Text('Descartar', style: context.text.labelLarge?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _CuentaRegresiva extends StatelessWidget {
  const _CuentaRegresiva({required this.segundos, required this.onCancel});
  final int segundos;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background.withValues(alpha: 0.94),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Enviando alerta en', style: context.text.titleLarge),
          AppSpacing.gapLg,
          Container(
            width: 160,
            height: 160,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.emergency, width: 6),
            ),
            child: Text('$segundos', style: context.text.displayLarge?.copyWith(color: AppColors.emergency)),
          ),
          AppSpacing.gapXl,
          SlButton(label: 'Cancelar', icon: Icons.close_rounded, variant: SlButtonVariant.secondary, onPressed: onCancel),
        ],
      ),
    );
  }
}
