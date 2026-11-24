// CAPA: PRESENTACIÓN — sistema de diseño (componente compartido)
// Pinta un EstadoVista: Cargando → LoadingView · Vacío → EmptyState ·
// Error → SlBanner con "Reintentar" · Listo → [builder]. Con [onRefresh]
// agrega pull-to-refresh en los cuatro estados.
// No hace: no carga datos ni decide el estado (eso es del ViewModel).
//
// ```dart
// SlStateView<List<Alerta>>(
//   estado: vm.estado,
//   onRetry: vm.recargar,
//   onRefresh: vm.recargar,
//   empty: const EmptyState(icon: Icons.inbox_outlined, title: 'Sin alertas'),
//   builder: (context, alertas) => ListView(physics: const AlwaysScrollableScrollPhysics(), ...),
// )
// ```

import 'package:flutter/material.dart';

import '../estado_vista.dart';
import '../tema/theme.dart';
import 'layout_widgets.dart';
import 'sl_banner.dart';

class SlStateView<T> extends StatelessWidget {
  const SlStateView({
    super.key,
    required this.estado,
    required this.builder,
    this.empty,
    this.onRetry,
    this.onRefresh,
    this.loadingMessage,
  });

  final EstadoVista<T> estado;

  /// Contenido en `Listo`. Si hay [onRefresh], usa `AlwaysScrollableScrollPhysics`.
  final Widget Function(BuildContext context, T datos) builder;
  final Widget? empty;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;
  final String? loadingMessage;

  @override
  Widget build(BuildContext context) {
    final contenido = switch (estado) {
      Cargando() => _relleno(LoadingView(message: loadingMessage)),
      Vacio() => _relleno(empty ?? const EmptyState(icon: Icons.inbox_outlined, title: 'Sin datos por ahora')),
      ErrorVista(:final mensaje) => _relleno(
          Padding(
            padding: AppSpacing.screen,
            child: SlBanner(
              type: SlBannerType.danger,
              title: 'No pudimos cargar la información',
              message: mensaje,
              action: onRetry == null
                  ? null
                  : TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reintentar'),
                    ),
            ),
          ),
          alinear: Alignment.topCenter,
        ),
      Listo(:final datos) => builder(context, datos),
    };
    if (onRefresh == null) return contenido;
    return RefreshIndicator(onRefresh: onRefresh!, child: contenido);
  }

  /// Los estados sin lista necesitan un scrollable para que funcione el pull-to-refresh.
  Widget _relleno(Widget hijo, {Alignment alinear = Alignment.center}) {
    if (onRefresh == null) return Align(alignment: alinear, child: hijo);
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Align(alignment: alinear, child: hijo),
        ),
      ),
    );
  }
}
