// CAPA: PRESENTACIÓN — View
// U-03 Toque simple · U-04 Mantener presionado · U-05 Agitación · U-06 Evidencia
// Pinta el botón de emergencia y le pasa los gestos al ViewModel. Solo calcula
// si el dedo está sobre "Descartar" y cuánto se arrastró el botón (geometría de pantalla).
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

  /// U-04: el botón sigue al dedo mientras se mantiene presionado.
  Offset _arrastre = Offset.zero;

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

  String get _titulo {
    if (vm.cuentaRegresiva != null) return 'Enviando alerta';
    if (vm.manteniendo) return vm.sobreDescarte ? 'Descartar alerta' : 'Alerta activa';
    return 'SafeLink';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(_titulo),
          actions: [
            IconButton(
              tooltip: 'Mi alerta activa',
              icon: const Icon(Icons.notifications_active_outlined),
              onPressed: () => context.go(AppRoutes.userAlert),
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
                    _ChipEstado(vm: vm),
                    if (vm.config.modoDemo && vm.agitacionActiva && !vm.manteniendo)
                      TextButton.icon(
                        onPressed: vm.botonHabilitado ? vm.agitar : null,
                        icon: const Icon(Icons.vibration_rounded),
                        label: const Text('Simular agitación (demo)'),
                      ),
                    const Spacer(),
                    Transform.translate(
                      offset: vm.manteniendo ? _arrastre : Offset.zero,
                      child: EmergencyButton(
                        enabled: vm.botonHabilitado,
                        pressed: vm.manteniendo,
                        sublabel: 'ENVIAR AYUDA',
                        caption: 'Toca o mantén presionado',
                        onTap: vm.tocar,
                        onLongPressStart: (_) {
                          setState(() => _arrastre = Offset.zero);
                          vm.empezarMantener();
                        },
                        onLongPressMoveUpdate: (d) {
                          setState(() => _arrastre = d.offsetFromOrigin);
                          vm.moverMantener(sobreDescarte: _sobreDescarte(d.globalPosition));
                        },
                        onLongPressEnd: (d) {
                          vm.moverMantener(sobreDescarte: _sobreDescarte(d.globalPosition));
                          vm.soltarMantener();
                          setState(() => _arrastre = Offset.zero);
                        },
                      ),
                    ),
                    AppSpacing.gapLg,
                    Text(
                      vm.manteniendo ? 'Suelta para enviar la alerta' : 'Toca o mantén presionado',
                      style: context.text.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    AppSpacing.gapXs,
                    Text(
                      vm.manteniendo
                          ? 'También puedes arrastrar el botón hacia abajo para cancelar.'
                          : 'Un toque inicia una cuenta regresiva de ${vm.config.segundosCuentaRegresiva} s. '
                              'Mantén presionado para enviar al soltar.',
                      style: context.text.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(),
                    // Ambos ocupan el mismo lugar: la zona aparece solo mientras se mantiene.
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedOpacity(
                          opacity: vm.manteniendo ? 0 : 1,
                          duration: AppDurations.fast,
                          child: Text('Listo para protegerte', style: context.text.bodySmall),
                        ),
                        AnimatedOpacity(
                          opacity: vm.manteniendo ? 1 : 0,
                          duration: AppDurations.fast,
                          child: _ZonaDescarte(key: _zonaDescarte, activa: vm.sobreDescarte),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (vm.cuentaRegresiva != null)
                _CuentaRegresiva(
                  segundos: vm.cuentaRegresiva!,
                  total: vm.config.segundosCuentaRegresiva,
                  onCancel: vm.cancelarCuenta,
                ),
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

/// Chip superior: qué está pasando con el botón en este momento.
class _ChipEstado extends StatelessWidget {
  const _ChipEstado({required this.vm});
  final InicioViewModel vm;

  @override
  Widget build(BuildContext context) {
    final chip = switch (vm) {
      InicioViewModel(manteniendo: true, sobreDescarte: true) =>
        const SlChip(label: 'Arrastrando para descartar', color: AppColors.warning, icon: Icons.south_rounded),
      InicioViewModel(manteniendo: true) =>
        const SlChip(label: 'Manteniendo presionado', color: AppColors.emergency, icon: Icons.touch_app_outlined),
      InicioViewModel(agitacionActiva: true) =>
        const SlChip(label: 'Detección por agitación activa', color: AppColors.success, icon: Icons.vibration_rounded),
      _ => null,
    };
    // Altura fija: el botón no "salta" cuando el chip aparece o desaparece.
    return SizedBox(height: AppSizes.touchTarget / 2, child: chip == null ? null : Center(child: chip));
  }
}

class _ZonaDescarte extends StatelessWidget {
  const _ZonaDescarte({super.key, required this.activa});
  final bool activa;

  @override
  Widget build(BuildContext context) {
    final color = activa ? AppColors.warning : AppColors.textSecondary;
    return AnimatedContainer(
      duration: AppDurations.fast,
      width: double.infinity,
      height: 96,
      decoration: BoxDecoration(
        color: activa ? AppColors.tint(AppColors.warning) : AppColors.surface,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: activa ? AppColors.warning : AppColors.border, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.delete_outline_rounded, color: color),
          AppSpacing.gapXxs,
          Text(
            activa ? 'Suelta para descartar' : 'Arrastra aquí para descartar',
            style: context.text.labelLarge?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _CuentaRegresiva extends StatelessWidget {
  const _CuentaRegresiva({required this.segundos, required this.total, required this.onCancel});
  final int segundos;
  final int total;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    const diametro = 200.0;
    return Container(
      color: AppColors.background,
      padding: AppSpacing.screen,
      child: Column(
        children: [
          const SlChip(label: 'Alerta pendiente', color: AppColors.warning, icon: Icons.schedule_rounded),
          const Spacer(),
          SizedBox(
            width: diametro,
            height: diametro,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: total == 0 ? 0 : segundos / total,
                    strokeWidth: 6,
                    color: AppColors.emergency,
                    backgroundColor: AppColors.border,
                  ),
                ),
                Container(
                  width: diametro - AppSpacing.xl,
                  height: diametro - AppSpacing.xl,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.emergency),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.timer_outlined, color: AppColors.onAccent),
                      Text('$segundos', style: context.text.displayLarge?.copyWith(color: AppColors.onAccent)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.gapXl,
          Text('La alerta se enviará', style: context.text.headlineSmall, textAlign: TextAlign.center),
          AppSpacing.gapXs,
          Text(
            'Preparando foto, ubicación y rumbo para solicitar ayuda.',
            style: context.text.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          SlButton(label: 'Cancelar', icon: Icons.close_rounded, variant: SlButtonVariant.secondary, onPressed: onCancel),
          AppSpacing.gapMd,
        ],
      ),
    );
  }
}
