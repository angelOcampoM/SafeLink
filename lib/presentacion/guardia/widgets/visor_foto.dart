// CAPA: PRESENTACIÓN — widgets del guardia
// G-04 Visor de la foto de evidencia a pantalla completa.
// Solo muestra la imagen que recibe: no guarda, no comparte ni descarga (D23).

import 'package:flutter/material.dart';

import '../../comun/tema/theme.dart';
import '../../comun/widgets/widgets.dart';

/// Foto de evidencia a pantalla completa, con zoom y botón de cerrar.
///
/// Se abre como ruta propia con [abrir]; no está en `go_router` porque no tiene
/// enlace ni debe abrirse desde una notificación.
class VisorFoto extends StatefulWidget {
  const VisorFoto({super.key, required this.url, required this.etiqueta, this.heroTag});

  final String url;

  /// Texto para lectores de pantalla: "Fotografía del entorno de la alerta".
  final String etiqueta;

  /// Mismo tag que la miniatura de `FotoEvidencia`, para la transición.
  final String? heroTag;

  /// Abre el visor encima de la pantalla actual.
  static Future<void> abrir(
    BuildContext context, {
    required String url,
    required String etiqueta,
    String? heroTag,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => VisorFoto(url: url, etiqueta: etiqueta, heroTag: heroTag),
      ),
    );
  }

  @override
  State<VisorFoto> createState() => _VisorFotoState();
}

class _VisorFotoState extends State<VisorFoto> {
  final _transformacion = TransformationController();

  /// Escala del doble toque: alterna entre la foto completa y el doble.
  static const _zoom = 2.0;

  @override
  void dispose() {
    _transformacion.dispose();
    super.dispose();
  }

  void _alternarZoom() {
    final escala = _transformacion.value.getMaxScaleOnAxis();
    _transformacion.value = escala > 1.0
        ? Matrix4.identity()
        : Matrix4.diagonal3Values(_zoom, _zoom, 1);
  }

  @override
  Widget build(BuildContext context) {
    final foto = Image.network(
      widget.url,
      fit: BoxFit.contain,
      semanticLabel: widget.etiqueta,
      errorBuilder: (_, __, ___) => Text(
        'No se pudo cargar la foto',
        style: context.text.bodyMedium,
        textAlign: TextAlign.center,
      ),
      loadingBuilder: (_, child, progreso) => progreso == null ? child : const LoadingView(),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: _alternarZoom,
              child: InteractiveViewer(
                transformationController: _transformacion,
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: widget.heroTag == null ? foto : Hero(tag: widget.heroTag!, child: foto),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: IconButton(
                  tooltip: 'Cerrar',
                  icon: const Icon(Icons.close_rounded),
                  color: AppColors.textPrimary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
