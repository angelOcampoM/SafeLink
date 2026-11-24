// CAPA: PRESENTACIÓN — View
// Historial de mis alertas (usuario protegido)
// Lista con StatusChip, pull-to-refresh y detalle simple en hoja inferior.
// No carga datos por su cuenta: todo viene del ViewModel.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/alerta.dart';
import '../comun/rutas/app_routes.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'historial_usuario_view_model.dart';

class HistorialUsuarioPage extends StatefulWidget {
  const HistorialUsuarioPage({super.key, required this.viewModel});
  final HistorialUsuarioViewModel viewModel;

  @override
  State<HistorialUsuarioPage> createState() => _HistorialUsuarioPageState();
}

class _HistorialUsuarioPageState extends State<HistorialUsuarioPage> {
  late final HistorialUsuarioViewModel vm = widget.viewModel;

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

  void _abrir(Alerta a) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => AlertDetailSheet(alert: a),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(AppRoutes.userHome)),
        title: const Text('Mis alertas'),
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => SlStateView<List<Alerta>>(
          estado: vm.estado,
          onRetry: vm.cargar,
          onRefresh: vm.cargar,
          empty: const EmptyState(
            icon: Icons.history_toggle_off_rounded,
            title: 'Aún no tienes alertas',
            message: 'Aquí verás cada alerta que envíes y cómo terminó.',
          ),
          builder: (context, alertas) => ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.screen,
            itemCount: alertas.length,
            separatorBuilder: (_, __) => AppSpacing.gapSm,
            itemBuilder: (_, i) => AlertCard(alert: alertas[i], now: vm.ahora, onTap: () => _abrir(alertas[i])),
          ),
        ),
      ),
    );
  }
}

