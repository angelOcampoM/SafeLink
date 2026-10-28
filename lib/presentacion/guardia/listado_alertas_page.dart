// CAPA: PRESENTACIÓN — View
// G-02 Recepción (banner "Alerta entrante") · G-03 Listado por cercanía y prioridad · Fuera de turno
// Pinta el turno, el banner de alerta entrante y el listado con pull-to-refresh.
// No escucha streams, no ordena y no sabe de dónde vienen las alertas.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/dominio.dart';
import '../comun/formato.dart';
import '../comun/rutas/app_routes.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'listado_alertas_view_model.dart';

class ListadoAlertasPage extends StatefulWidget {
  const ListadoAlertasPage({super.key, required this.viewModel});
  final ListadoAlertasViewModel viewModel;

  @override
  State<ListadoAlertasPage> createState() => _ListadoAlertasPageState();
}

class _ListadoAlertasPageState extends State<ListadoAlertasPage> {
  late final ListadoAlertasViewModel vm = widget.viewModel;

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
      appBar: AppBar(
        title: const Text('Alertas cercanas'),
        actions: [
          IconButton(
            tooltip: 'Alertas atendidas',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => context.push(AppRoutes.guardHistory),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_rounded),
            onPressed: vm.cerrarSesion,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => SlStateView<Guardia>(
          estado: vm.perfil,
          onRetry: vm.recargar,
          onRefresh: vm.recargar,
          builder: (context, guardia) {
            final motivo = vm.motivoNoDisponible;
            if (motivo != null) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  EmptyState(icon: Icons.bedtime_outlined, title: 'No estás recibiendo alertas', message: motivo),
                ],
              );
            }
            final entrante = vm.entrante;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                  child: _BarraTurno(guardia: guardia),
                ),
                if (entrante != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                    child: SlBanner(
                      type: entrante.alerta.esUrgente ? SlBannerType.warning : SlBannerType.info,
                      icon: Icons.notifications_active_rounded,
                      title: 'Alerta entrante',
                      message: '${entrante.alerta.nombreUsuario ?? 'Usuario'} · ${Fmt.distance(entrante.distanciaMetros)} · ${entrante.alerta.metodo.etiqueta}',
                      action: Wrap(
                        spacing: AppSpacing.xs,
                        children: [
                          TextButton(onPressed: () => _verEntrante(entrante.alerta.id), child: const Text('Ver')),
                          TextButton(onPressed: vm.descartarEntrante, child: const Text('Ocultar aviso')),
                        ],
                      ),
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
                    builder: (context, lista) => ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
                      itemCount: lista.length,
                      separatorBuilder: (_, __) => AppSpacing.gapSm,
                      itemBuilder: (_, i) => AlertCard(
                        alert: lista[i].alerta,
                        now: vm.ahora,
                        distanceMeters: lista[i].distanciaMetros,
                        showStatus: false,
                        onTap: () => context.push(AppRoutes.guardAlertDetail(lista[i].alerta.id)),
                      ),
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

class _BarraTurno extends StatelessWidget {
  const _BarraTurno({required this.guardia});
  final Guardia guardia;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SlChip(label: 'En turno', color: AppColors.success, icon: Icons.circle),
        AppSpacing.gapXs,
        Text('${guardia.perfil.inicioTurno} – ${guardia.perfil.finTurno}', style: context.text.bodySmall),
        const Spacer(),
        Text('Radio ${Fmt.distance(guardia.perfil.radioCoberturaMetros!)}', style: context.text.bodySmall),
      ],
    );
  }
}
