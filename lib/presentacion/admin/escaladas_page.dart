// CAPA: PRESENTACIÓN — View
// A-04 Bandeja de escaladas
// Lista en tiempo real con pull-to-refresh; al tocar una alerta se abre su
// pantalla de detalle para revisarla y resolverla. No carga datos.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/dominio.dart';
import '../comun/rutas/app_routes.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'escaladas_view_model.dart';

class EscaladasPage extends StatefulWidget {
  const EscaladasPage({super.key, required this.viewModel});
  final EscaladasViewModel viewModel;

  @override
  State<EscaladasPage> createState() => _EscaladasPageState();
}

class _EscaladasPageState extends State<EscaladasPage> {
  late final EscaladasViewModel vm = widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.iniciar();
  }

  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escaladas')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => SlStateView<List<Alerta>>(
          estado: vm.estado,
          onRetry: vm.iniciar,
          onRefresh: vm.recargar,
          empty: const EmptyState(
            icon: Icons.inbox_outlined,
            color: AppColors.success,
            title: 'Bandeja vacía',
            message: 'No hay alertas escaladas por revisar.',
          ),
          builder: (context, lista) => ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.screen,
            itemCount: lista.length,
            separatorBuilder: (_, __) => AppSpacing.gapSm,
            itemBuilder: (_, i) => AlertCard(
              alert: lista[i],
              now: vm.ahora,
              onTap: () => context.push(AppRoutes.adminEscalatedDetail(lista[i].id)),
            ),
          ),
        ),
      ),
    );
  }
}
