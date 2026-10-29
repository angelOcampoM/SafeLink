// CAPA: PRESENTACIÓN — View
// G-02 Recepción (banner "Alerta entrante") · G-03 Listado por cercanía y prioridad · Fuera de turno
// Pinta el turno, el banner de alerta entrante y el listado con pull-to-refresh.
// No escucha streams, no ordena y no sabe de dónde vienen las alertas.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/dominio.dart';
import '../comun/rutas/app_routes.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'listado_alertas_view_model.dart';
import 'widgets/widgets_guardia.dart';

class ListadoAlertasPage extends StatefulWidget {
  const ListadoAlertasPage({super.key, required this.viewModel});
  final ListadoAlertasViewModel viewModel;

  @override
  State<ListadoAlertasPage> createState() => _ListadoAlertasPageState();
}

class _ListadoAlertasPageState extends State<ListadoAlertasPage> {
  late final ListadoAlertasViewModel vm = widget.viewModel;

  static const _margenFila = EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm);

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

  void _verEntrante(String id) {
    vm.descartarEntrante();
    context.push(AppRoutes.guardIncoming(id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alertas cercanas')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => SlStateView<Guardia>(
          estado: vm.perfil,
          onRetry: vm.recargar,
          onRefresh: vm.recargar,
          builder: (context, guardia) {
            final motivo = vm.motivoNoDisponible;
            if (motivo != null) return SinRecibirAlertasView(motivo: motivo);
            final entrante = vm.entrante;
            return Column(
              children: [
                Padding(padding: _margenFila, child: BarraTurno(guardia: guardia)),
                if (entrante != null)
                  Padding(
                    padding: _margenFila,
                    child: BannerAlertaEntrante(
                      entrante: entrante,
                      onVer: () => _verEntrante(entrante.alerta.id),
                      onOcultar: vm.descartarEntrante,
                    ),
                  ),
                Expanded(
                  child: SlStateView<List<AlertaPriorizada>>(
                    estado: vm.estado,
                    onRetry: vm.recargar,
                    onRefresh: vm.recargar,
                    empty: const EmptyState(
                      icon: Icons.shield_outlined,
                      color: AppColors.success,
                      title: 'Todo tranquilo',
                      message: 'No hay alertas en tu zona. Te avisaremos en cuanto llegue una.',
                    ),
                    builder: (context, lista) => ListaAlertasDisponibles(
                      alertas: lista,
                      ahora: vm.ahora,
                      onAbrir: (id) => context.push(AppRoutes.guardAlertDetail(id)),
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
