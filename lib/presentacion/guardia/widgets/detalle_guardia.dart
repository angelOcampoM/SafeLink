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
import 'visor_foto.dart';

/// Alto de la foto y del mapa del detalle (aún no hay token en AppSizes).
const _altoMedio = 200.0;

/// G-04: la alerta no trae coordenadas. Lo reutiliza UI-01 en el mapa.
const String textoUbicacionNoDisponible = 'Ubicación no disponible';

/// Texto para lectores de pantalla de la foto ampliada.
const _etiquetaFoto = 'Fotografía del entorno de la alerta';

/// Foto de evidencia o aviso de "evidencia incompleta".
///
/// Con foto cargada se puede tocar para abrirla en [VisorFoto]. Sin foto o con
/// error de carga solo se muestra el aviso: no hay nada que ampliar.
class FotoEvidencia extends StatelessWidget {
  const FotoEvidencia({super.key, required this.url, this.heroTag});
  final String? url;

  /// Tag del `Hero` que comparte con el visor (por ejemplo, `foto-$alertaId`).
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    final placeholder = Container(
      height: _altoMedio,
      color: AppColors.surface,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined, color: AppColors.textMuted, size: AppSizes.iconLg),
          AppSpacing.gapXs,
          Text(url == null ? 'Fotografía no disponible' : 'No se pudo cargar la foto', style: context.text.bodyMedium),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: AppRadius.brMd,
      child: url == null
          ? placeholder
          : Image.network(
              url,
              height: _altoMedio,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
              loadingBuilder: (_, child, p) => p == null ? child : const SizedBox(height: _altoMedio, child: LoadingView()),
              // El toque solo se habilita cuando hay imagen: si falla la carga,
              // `errorBuilder` ya sustituyó todo y aquí no se llega.
              frameBuilder: (context, child, frame, sincrona) =>
                  frame == null && !sincrona ? child : _FotoAmpliable(url: url, heroTag: heroTag, child: child),
            ),
    );
  }
}

/// Miniatura tocable con el indicador de "se puede ampliar".
class _FotoAmpliable extends StatelessWidget {
  const _FotoAmpliable({required this.url, required this.heroTag, required this.child});

  final String url;
  final String? heroTag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    void abrir() => VisorFoto.abrir(context, url: url, etiqueta: _etiquetaFoto, heroTag: heroTag);
    final foto = heroTag == null ? child : Hero(tag: heroTag!, child: child);
    return Semantics(
      button: true,
      label: 'Ampliar fotografía',
      // Un solo nodo para el lector de pantalla: la etiqueta, el botón y el
      // toque accesible. Lo que haya dentro no se anuncia aparte.
      excludeSemantics: true,
      onTap: abrir,
      child: Stack(
        children: [
          foto,
          Positioned(
            right: AppSpacing.xs,
            bottom: AppSpacing.xs,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xxs),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.7),
                borderRadius: AppRadius.brSm,
              ),
              child: const Icon(Icons.open_in_full_rounded, size: AppSizes.iconSm, color: AppColors.textPrimary),
            ),
          ),
          // La capa del toque va al final: encima de la foto, para que el
          // efecto del InkWell se vea.
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: abrir),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mapa simulado con el guardia y el usuario. Si la alerta no trae rumbo no se
/// dibuja el cono: no hay hacia dónde apuntarlo (G-04).
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
          // G-04: sin coordenadas el guardia debe saberlo, no ver una fila menos.
          if (a.ubicacion == null)
            const InfoRow(
              icon: Icons.location_off_outlined,
              label: 'Ubicación',
              value: textoUbicacionNoDisponible,
              valueColor: AppColors.textMuted,
            )
          else if (distancia != null)
            InfoRow(icon: Icons.near_me_outlined, label: 'Distancia', value: Fmt.distance(distancia!), valueColor: AppColors.info),
          InfoRow(
            icon: Icons.explore_outlined,
            label: 'Rumbo de la cámara',
            // G-04: sin magnetómetro el guardia debe saberlo, no ver una fila menos.
            value: a.rumbo == null ? 'Rumbo no disponible' : '${a.rumbo}° ${ReglaGeocerca.puntoCardinal(a.rumbo!)}',
            valueColor: a.rumbo == null ? AppColors.textMuted : null,
          ),
          InfoRow(icon: a.metodo.style.icon, label: 'Método', value: a.metodo.etiqueta),
        ],
      ),
    );
  }
}
