// CAPA: PRESENTACIÓN — View
// Historial de alertas atendidas por el guardia (sus métricas viven en el dashboard de Inicio)
// G-03 Filtros (fechas, resultado y método), resumen de lo filtrado y detalle en hoja inferior.
// No filtra por su cuenta: solo pasa al ViewModel lo que se eligió.

import 'package:flutter/material.dart';

import '../../dominio/dominio.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'historial_guardia_view_model.dart';
import 'widgets/widgets_guardia.dart';

class HistorialGuardiaPage extends StatefulWidget {
  const HistorialGuardiaPage({super.key, required this.viewModel});
  final HistorialGuardiaViewModel viewModel;

  @override
  State<HistorialGuardiaPage> createState() => _HistorialGuardiaPageState();
}

class _HistorialGuardiaPageState extends State<HistorialGuardiaPage> {
  late final HistorialGuardiaViewModel vm = widget.viewModel;

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

  Future<void> _elegirRango() async {
    final hoy = vm.ahora;
    final r = await showDateRangePicker(
      context: context,
      firstDate: hoy.subtract(const Duration(days: 365)),
      lastDate: hoy,
      initialDateRange: vm.desde == null ? null : DateTimeRange(start: vm.desde!, end: vm.hasta!),
      helpText: 'Rango de fechas',
    );
    if (r != null) vm.cambiarRango(r.start, r.end);
  }

  Future<void> _elegirMetodo() async {
    const valores = <MetodoDisparo?>[null, ...MetodoDisparo.values];
    final i = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HojaOpciones(
        titulo: 'Método de disparo',
        opciones: [for (final m in valores) m == null ? 'Cualquier método' : etiquetaMetodo(m)],
        seleccionada: valores.indexOf(vm.metodo),
      ),
    );
    if (i != null) vm.cambiarMetodo(valores[i]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => SlStateView<List<Alerta>>(
          estado: vm.estado,
          onRetry: vm.cargar,
          onRefresh: vm.cargar,
          empty: const EmptyState(
            icon: Icons.history_toggle_off_rounded,
            title: 'Aún no atiendes alertas',
            message: 'Cuando cierres tu primera alerta aparecerá aquí con tus tiempos.',
          ),
          builder: (context, _) {
            final lista = vm.filtradas;
            final resumen = vm.resumen;
            return Column(
              children: [
                FiltrosHistorialGuardia(
                  desde: vm.desde,
                  hasta: vm.hasta,
                  metodo: vm.metodo,
                  estado: vm.estadoFiltro,
                  estados: vm.estadosDisponibles,
                  hayFiltros: vm.hayFiltros,
                  onRango: _elegirRango,
                  onMetodo: _elegirMetodo,
                  onEstado: vm.cambiarEstado,
                  onLimpiar: vm.limpiarFiltros,
                ),
                Expanded(
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: AppSpacing.screen,
                    children: [
                      const SectionHeader('Alertas atendidas'),
                      ResumenHistorialGuardia(conteo: resumen.conteo, promedioLlegadaSeg: resumen.promedioLlegadaSeg),
                      AppSpacing.gapSm,
                      if (lista.isEmpty)
                        EmptyState(
                          icon: Icons.filter_alt_off_outlined,
                          title: 'Sin alertas con estos filtros',
                          action: SlButton(label: 'Limpiar filtros', expand: false, variant: SlButtonVariant.secondary, onPressed: vm.limpiarFiltros),
                        ),
                      for (final a in lista) ...[
                        AlertCard(
                          alert: a,
                          now: vm.ahora,
                          onTap: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => AlertDetailSheet(alert: a),
                          ),
                        ),
                        AppSpacing.gapSm,
                      ],
                    ],
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
