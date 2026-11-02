// CAPA: PRESENTACIÓN — widgets del guardia
// G-06 Ruta hacia el usuario · G-07 Llegada · Esperando confirmación / atendida / escalada
// Mapa de la ruta, tarjeta de usuario y distancia, y los estados finales de la atención.
// No hacen: no calculan geocercas, no marcan la llegada ni navegan; avisan con callbacks.
//
// TODO(G-06): sustituir MapPlaceholder por GoogleMap con la misma altura.

import 'package:flutter/material.dart';

import '../../../dominio/dominio.dart';
import '../../comun/formato.dart';
import '../../comun/tema/theme.dart';
import '../../comun/widgets/widgets.dart';

/// Alto del mapa de la ruta (aún no hay token en AppSizes).
const _altoMapaRuta = 300.0;

/// Distancia que representa el borde del mapa simulado y radio de la geocerca.
const _metrosBordeMapa = 3000.0;
const _fraccionGeocerca = 0.08;

/// Mapa simulado: el guardia se acerca al centro (usuario) conforme baja la distancia.
class MapaRutaGuardia extends StatelessWidget {
  const MapaRutaGuardia({super.key, required this.distancia});
  final double distancia;

  @override
  Widget build(BuildContext context) {
    final f = (distancia / _metrosBordeMapa).clamp(_fraccionGeocerca, 0.9).toDouble();
    return MapPlaceholder(
      height: _altoMapaRuta,
      showRoute: true,
      radiusFraction: _fraccionGeocerca,
      markers: [
        MapMarker(offset: Offset(-f, f), color: AppColors.info, icon: Icons.shield_rounded),
        const MapMarker(offset: Offset.zero, color: AppColors.emergency, icon: Icons.person_pin_circle_rounded),
      ],
    );
  }
}

/// Nombre y teléfono del usuario con la distancia restante.
class TarjetaUsuarioDistancia extends StatelessWidget {
  const TarjetaUsuarioDistancia({super.key, required this.alerta, required this.distancia, required this.dentro});
  final Alerta alerta;
  final double distancia;
  final bool dentro;

  @override
  Widget build(BuildContext context) {
    return SlCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(alerta.nombreUsuario ?? 'Usuario', style: context.text.titleMedium),
                Text(alerta.telefonoUsuario == null ? '' : Fmt.phone(alerta.telefonoUsuario!), style: context.text.bodySmall),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Fmt.distance(distancia), style: context.text.displaySmall?.copyWith(color: dentro ? AppColors.success : AppColors.info)),
              Text(dentro ? 'Dentro de la zona' : 'restantes', style: context.text.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

/// El guardia ya llegó; falta que el usuario confirme.
class EsperandoConfirmacionView extends StatelessWidget {
  const EsperandoConfirmacionView({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.hourglass_top_rounded,
      color: AppColors.info,
      title: 'Esperando confirmación',
      message: 'Registramos tu llegada. El usuario debe confirmar que fue atendido para cerrar la alerta.',
    );
  }
}

/// El usuario confirmó la atención.
class AlertaAtendidaView extends StatelessWidget {
  const AlertaAtendidaView({super.key, required this.alerta, required this.onVolver});
  final Alerta alerta;
  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.check_circle_rounded,
      color: AppColors.success,
      title: 'Alerta atendida',
      message: '${alerta.nombreUsuario ?? 'El usuario'} confirmó la atención. ¡Buen trabajo!',
      action: SlButton(label: 'Volver al listado', expand: false, onPressed: onVolver),
    );
  }
}

/// La alerta pasó al administrador.
class AlertaEscaladaView extends StatelessWidget {
  const AlertaEscaladaView({super.key, required this.alerta, required this.onVolver});
  final Alerta alerta;
  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.priority_high_rounded,
      color: AppColors.warning,
      title: 'Alerta escalada',
      message: 'El administrador revisará esta alerta (${alerta.razonEscalamiento?.etiqueta ?? 'escalada'}).',
      action: SlButton(label: 'Volver al listado', expand: false, onPressed: onVolver),
    );
  }
}
