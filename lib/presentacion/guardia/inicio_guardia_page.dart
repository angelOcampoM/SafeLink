// CAPA: PRESENTACIÓN — View
// G-03 Dashboard de Inicio del guardia: turno, alertas disponibles, mis métricas por periodo,
// alertas por hora y última alerta atendida. Logout en el AppBar (como el panel del admin).
// Pinta lo que expone InicioGuardiaViewModel con pull-to-refresh.
// No calcula nada ni llama repositorios.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/rutas/app_routes.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'inicio_guardia_view_model.dart';
import 'widgets/widgets_guardia.dart';

class InicioGuardiaPage extends StatefulWidget {
  const InicioGuardiaPage({super.key, required this.viewModel});
  final InicioGuardiaViewModel viewModel;

  @override
  State<InicioGuardiaPage> createState() => _InicioGuardiaPageState();
}

class _InicioGuardiaPageState extends State<InicioGuardiaPage> {
  late final InicioGuardiaViewModel vm = widget.viewModel;

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

  Widget _error(String mensaje) => SlBanner(
        type: SlBannerType.danger,
        message: mensaje,
        action: TextButton.icon(onPressed: vm.cargar, icon: const Icon(Icons.refresh_rounded), label: const Text('Reintentar')),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inicio'),
        actions: [
          IconButton(tooltip: 'Cerrar sesión', icon: const Icon(Icons.logout_rounded), onPressed: vm.cerrarSesion),
        ],
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => SlStateView<Guardia>(
          estado: vm.perfil,
          onRetry: vm.cargar,
          onRefresh: vm.cargar,
          builder: (context, guardia) {
            final motivo = vm.motivoNoDisponible;
            final enTurno = vm.estadoTurno == EstadoTurno.enTurno;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppSpacing.screen,
              children: [
                if (motivo != null) ...[
                  SlBanner(type: SlBannerType.warning, title: 'No estás recibiendo alertas', message: motivo),
                  AppSpacing.gapMd,
                ],
                const SectionHeader('Mi turno'),
                TarjetaTurno(
                  guardia: guardia,
                  estado: vm.estadoTurno!.etiqueta,
                  enTurno: enTurno,
                  ahora: vm.ahora,
                  minutosRestantes: vm.minutosRestantesTurno,
                  minutosParaIniciar: vm.minutosParaIniciarTurno,
                ),
                if (enTurno) ...[
                  AppSpacing.gapLg,
                  SectionHeader('Alertas disponibles', actionLabel: 'Ver alertas', onAction: () => context.go(AppRoutes.guardAlerts)),
                  switch (vm.disponibles) {
                    ErrorVista(:final mensaje) => _error(mensaje),
                    _ => ResumenDisponibles(total: vm.totalDisponibles, urgentes: vm.urgentesDisponibles),
                  },
                ],
                AppSpacing.gapLg,
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    for (final p in PeriodoInicio.values)
                      ChoiceChip(label: Text(p.etiqueta), selected: vm.periodo == p, onSelected: (_) => vm.cambiarPeriodo(p)),
                  ],
                ),
                AppSpacing.gapMd,
                SectionHeader('Mis métricas · ${vm.periodo.etiqueta}'),
                ...switch (vm.metricas) {
                  Listo(datos: final m) => [
                      MetricasPeriodoGuardia(metricas: m.guardia, tasaCierreConfirmado: m.tasaCierreConfirmado),
                      AppSpacing.gapLg,
                      const SectionHeader('Mis alertas por hora'),
                      SlCard(child: GraficaHorasGuardia(valores: m.alertasPorHora)),
                    ],
                  ErrorVista(:final mensaje) => [_error(mensaje)],
                  _ => [const LoadingView()],
                },
                AppSpacing.gapLg,
                SectionHeader('Última alerta atendida', actionLabel: 'Ver historial', onAction: () => context.go(AppRoutes.guardHistory)),
                switch (vm.ultima) {
                  Listo(datos: final a) => AlertCard(
                      alert: a,
                      now: vm.ahora,
                      onTap: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => AlertDetailSheet(alert: a),
                      ),
                    ),
                  Vacio() => const SlBanner(message: 'Aún no atiendes alertas. Aquí verás la más reciente.'),
                  ErrorVista(:final mensaje) => _error(mensaje),
                  Cargando() => const LoadingView(),
                },
              ],
            );
          },
        ),
      ),
    );
  }
}
