// CAPA: PRESENTACIÓN — View
// G-02 Recepción (banner "Alerta entrante") · G-03 Listado por cercanía y prioridad, con filtros · Fuera de turno
// Pinta el turno, el banner de alerta entrante, los filtros y el listado con pull-to-refresh.
// No escucha streams, no filtra ni ordena y no sabe de dónde vienen las alertas.

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

  /// Hoja inferior con opciones; solo avisa si se eligió una (cerrarla no cambia nada).
  Future<void> _elegir<T>(String titulo, List<T> valores, String Function(T) etiqueta, T actual, ValueChanged<T> alElegir) async {
    final i = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HojaOpciones(titulo: titulo, opciones: [for (final v in valores) etiqueta(v)], seleccionada: valores.indexOf(actual)),
    );
    if (i != null) alElegir(valores[i]);
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
            final f = vm.filtro;
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
                FiltrosListado(
                  filtro: f,
                  onDistancia: () => _elegir<int?>(
                    'Distancia',
                    [null, ...FiltroAlertasDisponibles.distancias],
                    etiquetaDistancia,
                    f.distanciaMaxMetros,
                    vm.cambiarDistancia,
                  ),
                  onEvidencia: () => _elegir('Evidencia', FiltroEvidencia.values, (e) => e.etiqueta, f.evidencia, vm.cambiarEvidencia),
                  onOrden: () => _elegir('Ordenar por', OrdenAlertasDisponibles.values, (o) => o.etiqueta, f.orden, vm.cambiarOrden),
                  onMetodo: vm.cambiarMetodo,
                  onLimpiar: vm.limpiarFiltros,
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
                    builder: (context, _) {
                      final lista = vm.filtradas;
                      if (lista.isEmpty) return SinResultadosFiltrosView(onLimpiar: vm.limpiarFiltros);
                      return ListaAlertasDisponibles(
                        alertas: lista,
                        contador: f.filtraAlertas ? '${lista.length} de ${vm.total} alertas' : '${vm.total} alertas',
                        ahora: vm.ahora,
                        onAbrir: (id) => context.push(AppRoutes.guardAlertDetail(id)),
                      );
                    },
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
