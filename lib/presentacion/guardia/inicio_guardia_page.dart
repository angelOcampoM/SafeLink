// CAPA: PRESENTACIÓN — View
// G-03 Inicio del guardia (versión mínima): tarjeta de turno, acceso a Alertas y logout.
// Pinta lo que expone InicioGuardiaViewModel con pull-to-refresh.
// No calcula el turno ni llama repositorios. El dashboard completo llega en la Etapa 5.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/dominio.dart';
import '../comun/formato.dart';
import '../comun/rutas/app_routes.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'inicio_guardia_view_model.dart';

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
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppSpacing.screen,
              children: [
                const SectionHeader('Mi turno'),
                _TarjetaTurno(guardia: guardia, estado: vm.estadoTurno!),
                if (motivo != null) ...[
                  AppSpacing.gapSm,
                  SlBanner(type: SlBannerType.warning, title: 'No estás recibiendo alertas', message: motivo),
                ],
                AppSpacing.gapLg,
                SlButton(
                  label: 'Ver alertas',
                  icon: Icons.notifications_rounded,
                  onPressed: () => context.go(AppRoutes.guardAlerts),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TarjetaTurno extends StatelessWidget {
  const _TarjetaTurno({required this.guardia, required this.estado});
  final Guardia guardia;
  final EstadoTurno estado;

  @override
  Widget build(BuildContext context) {
    final p = guardia.perfil;
    final color = estado == EstadoTurno.enTurno ? AppColors.success : AppColors.warning;
    return SlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SlChip(label: estado.etiqueta, color: color, icon: Icons.circle),
          AppSpacing.gapSm,
          InfoRow(icon: Icons.schedule_rounded, label: 'Horario', value: '${p.inicioTurno} – ${p.finTurno}'),
          InfoRow(
            icon: Icons.radar_rounded,
            label: 'Radio de cobertura',
            value: p.radioCoberturaMetros == null ? 'Sin asignar' : Fmt.distance(p.radioCoberturaMetros!),
          ),
        ],
      ),
    );
  }
}
