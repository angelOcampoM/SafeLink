// CAPA: PRESENTACIÓN — widgets del guardia
// G-04 Detalle de alerta: foto de evidencia, mapa y tarjeta de datos.
// Solo pintan la alerta que reciben.
// No hacen: no aceptan la alerta, no validan disponibilidad ni cargan datos.
//
// TODO(G-06): sustituir MapPlaceholder por GoogleMap con la misma altura.

import 'package:flutter/material.dart';

import '../../../dominio/dominio.dart';
import '../../comun/formato.dart';
import '../../comun/tema/theme.dart';
import '../../comun/widgets/widgets.dart';

/// Alto de la foto y del mapa del detalle (aún no hay token en AppSizes).
const _altoMedio = 200.0;

/// Foto de evidencia o aviso de "evidencia incompleta".
class FotoEvidencia extends StatelessWidget {
  const FotoEvidencia({super.key, required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      height: _altoMedio,
      color: AppColors.surface,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined, color: AppColors.textMuted, size: AppSizes.iconLg),
          AppSpacing.gapXs,
          Text(url == null ? 'Evidencia incompleta: sin foto' : 'No se pudo cargar la foto', style: context.text.bodyMedium),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: AppRadius.brMd,
      child: url == null
          ? placeholder
          : Image.network(
              url!,
              height: _altoMedio,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
              loadingBuilder: (_, child, p) => p == null ? child : const SizedBox(height: _altoMedio, child: LoadingView()),
            ),
    );
  }
}

/// Mapa simulado con el guardia y el usuario (con el cono de rumbo de la cámara).
class MapaDetalleAlerta extends StatelessWidget {
  const MapaDetalleAlerta({super.key, this.rumbo});
  final int? rumbo;

  @override
  Widget build(BuildContext context) {
    return MapPlaceholder(
      height: _altoMedio,
      markers: [
        const MapMarker(offset: Offset(-0.5, 0.5), color: AppColors.info, icon: Icons.shield_rounded),
        MapMarker(offset: Offset.zero, color: AppColors.emergency, icon: Icons.person_pin_circle_rounded, heading: rumbo),
      ],
    );
  }
}

/// Hora, distancia, rumbo y método de disparo.
class TarjetaDatosAlerta extends StatelessWidget {
  const TarjetaDatosAlerta({super.key, required this.alerta, required this.ahora, this.distancia});
  final Alerta alerta;
  final DateTime ahora;
  final double? distancia;

  @override
  Widget build(BuildContext context) {
    final a = alerta;
    return SlCard(
      child: Column(
        children: [
          InfoRow(icon: Icons.schedule_rounded, label: 'Hora', value: '${Fmt.time(a.disparadaEn)} · ${Fmt.ago(a.disparadaEn, ahora)}'),
          if (distancia != null)
            InfoRow(icon: Icons.near_me_outlined, label: 'Distancia', value: Fmt.distance(distancia!), valueColor: AppColors.info),
          if (a.rumbo != null)
            InfoRow(icon: Icons.explore_outlined, label: 'Rumbo de la cámara', value: '${a.rumbo}° ${ReglaGeocerca.puntoCardinal(a.rumbo!)}'),
          InfoRow(icon: a.metodo.style.icon, label: 'Método', value: a.metodo.etiqueta),
        ],
      ),
    );
  }
}
