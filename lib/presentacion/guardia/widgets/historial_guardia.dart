// CAPA: PRESENTACIÓN — widgets del guardia
// G-03 Historial de alertas atendidas: filtros y resumen de lo filtrado.
// Fila 1: rango de fechas y método de disparo + "Limpiar"; fila 2: resultado (estado).
// No hacen: no filtran, no calculan métricas ni abren selectores; avisan con callbacks.

import 'package:flutter/material.dart';

import '../../../dominio/dominio.dart';
import '../../comun/formato.dart';
import '../../comun/tema/theme.dart';
import 'filtros_listado.dart';

class FiltrosHistorialGuardia extends StatelessWidget {
  const FiltrosHistorialGuardia({
    super.key,
    required this.desde,
    required this.hasta,
    required this.metodo,
    required this.estado,
    required this.estados,
    required this.hayFiltros,
    required this.onRango,
    required this.onMetodo,
    required this.onEstado,
    required this.onLimpiar,
  });

  final DateTime? desde;
  final DateTime? hasta;
  final MetodoDisparo? metodo;
  final EstadoAlerta? estado;

  /// Resultados que aparecen en el historial.
  final List<EstadoAlerta> estados;
  final bool hayFiltros;
  final VoidCallback onRango;
  final VoidCallback onMetodo;
  final ValueChanged<EstadoAlerta?> onEstado;
  final VoidCallback onLimpiar;

  static const _margen = EdgeInsets.symmetric(horizontal: AppSpacing.md);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: _margen,
          child: Row(
            children: [
              ActionChip(
                avatar: const Icon(Icons.date_range_rounded, size: AppSizes.iconSm),
                label: Text(desde == null ? 'Todas las fechas' : '${Fmt.date(desde!)} – ${Fmt.date(hasta!)}'),
                onPressed: onRango,
              ),
              AppSpacing.gapXs,
              ActionChip(
                avatar: const Icon(Icons.touch_app_outlined, size: AppSizes.iconSm),
                label: Text(metodo == null ? 'Cualquier método' : etiquetaMetodo(metodo!)),
                onPressed: onMetodo,
              ),
              if (hayFiltros) ...[
                AppSpacing.gapXs,
                ActionChip(
                  avatar: const Icon(Icons.filter_alt_off_outlined, size: AppSizes.iconSm),
                  label: const Text('Limpiar'),
                  onPressed: onLimpiar,
                ),
              ],
            ],
          ),
        ),
        AppSpacing.gapXs,
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: _margen,
          child: Row(
            children: [
              ChoiceChip(label: const Text('Todas'), selected: estado == null, onSelected: (_) => onEstado(null)),
              for (final e in estados) ...[
                AppSpacing.gapXs,
                ChoiceChip(label: Text(e.etiqueta), selected: estado == e, onSelected: (_) => onEstado(e)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Conteo y llegada promedio de lo que se ve ("12 alertas · llegada promedio 7 min").
class ResumenHistorialGuardia extends StatelessWidget {
  const ResumenHistorialGuardia({super.key, required this.conteo, required this.promedioLlegadaSeg});
  final int conteo;
  final double promedioLlegadaSeg;

  @override
  Widget build(BuildContext context) {
    final llegada = conteo == 0 ? '' : ' · llegada promedio ${Fmt.duration(promedioLlegadaSeg)}';
    return Text('$conteo ${conteo == 1 ? 'alerta' : 'alertas'}$llegada', style: context.text.bodySmall);
  }
}
