// CAPA: PRESENTACIÓN — widgets del guardia
// G-03 Filtros del listado de alertas (al estilo del historial del administrador).
// Fila 1: distancia, evidencia y orden (abren hoja inferior) + "Limpiar".
// Fila 2: tipo de disparo. También la hoja de opciones y el estado vacío con filtros.
// No hacen: no filtran ni guardan el filtro; avisan con callbacks.

import 'package:flutter/material.dart';

import '../../../dominio/dominio.dart';
import '../../comun/formato.dart';
import '../../comun/tema/theme.dart';
import '../../comun/widgets/widgets.dart';

/// Etiqueta de una distancia máxima ("≤ 500 m", "≤ 1 km") o "Cualquier distancia".
String etiquetaDistancia(int? metros) => switch (metros) {
      null => 'Cualquier distancia',
      final m when m >= 1000 && m % 1000 == 0 => '≤ ${m ~/ 1000} km',
      final m => '≤ ${Fmt.distance(m)}',
    };

/// Etiqueta del chip de tipo de disparo (agitación se muestra como "Urgentes").
String etiquetaMetodo(MetodoDisparo m) => m == MetodoDisparo.agitacion ? 'Urgentes' : m.etiqueta;

class FiltrosListado extends StatelessWidget {
  const FiltrosListado({
    super.key,
    required this.filtro,
    required this.onDistancia,
    required this.onEvidencia,
    required this.onOrden,
    required this.onMetodo,
    required this.onLimpiar,
  });

  final FiltroAlertasDisponibles filtro;
  final VoidCallback onDistancia;
  final VoidCallback onEvidencia;
  final VoidCallback onOrden;
  final ValueChanged<MetodoDisparo?> onMetodo;
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
                avatar: const Icon(Icons.near_me_outlined, size: AppSizes.iconSm),
                label: Text(etiquetaDistancia(filtro.distanciaMaxMetros)),
                onPressed: onDistancia,
              ),
              AppSpacing.gapXs,
              ActionChip(
                avatar: const Icon(Icons.photo_camera_outlined, size: AppSizes.iconSm),
                label: Text(filtro.evidencia == FiltroEvidencia.todas ? 'Evidencia' : filtro.evidencia.etiqueta),
                onPressed: onEvidencia,
              ),
              AppSpacing.gapXs,
              ActionChip(
                avatar: const Icon(Icons.sort_rounded, size: AppSizes.iconSm),
                label: Text(filtro.orden.etiqueta),
                onPressed: onOrden,
              ),
              if (filtro.hayFiltros) ...[
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
              ChoiceChip(label: const Text('Todas'), selected: filtro.metodo == null, onSelected: (_) => onMetodo(null)),
              for (final m in const [MetodoDisparo.agitacion, MetodoDisparo.toque, MetodoDisparo.mantener]) ...[
                AppSpacing.gapXs,
                ChoiceChip(label: Text(etiquetaMetodo(m)), selected: filtro.metodo == m, onSelected: (_) => onMetodo(m)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Contenido de la hoja inferior: lista de opciones; devuelve el índice elegido con `Navigator.pop`.
class HojaOpciones extends StatelessWidget {
  const HojaOpciones({super.key, required this.titulo, required this.opciones, required this.seleccionada});
  final String titulo;
  final List<String> opciones;
  final int seleccionada;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: AppSpacing.screen,
        children: [
          Text(titulo, style: context.text.titleLarge),
          AppSpacing.gapXs,
          for (var i = 0; i < opciones.length; i++)
            ListTile(
              title: Text(opciones[i]),
              selected: i == seleccionada,
              trailing: i == seleccionada ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(context, i),
            ),
        ],
      ),
    );
  }
}

/// Hay alertas en la zona, pero ninguna cumple los filtros.
class SinResultadosFiltrosView extends StatelessWidget {
  const SinResultadosFiltrosView({super.key, required this.onLimpiar});
  final VoidCallback onLimpiar;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        EmptyState(
          icon: Icons.filter_alt_off_outlined,
          title: 'Sin alertas con estos filtros',
          message: 'Hay alertas en tu zona que no coinciden con lo que elegiste.',
          action: SlButton(label: 'Limpiar filtros', expand: false, variant: SlButtonVariant.secondary, onPressed: onLimpiar),
        ),
      ],
    );
  }
}
