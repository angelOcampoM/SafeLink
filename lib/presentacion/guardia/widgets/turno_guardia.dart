// CAPA: PRESENTACIÓN — widgets del guardia
// G-03 Estado del turno: barra compacta (listado) y tarjeta (Inicio).
// Solo pintan el perfil que reciben y el estado ya decidido por el ViewModel.
// No hacen: no calculan si el guardia está en turno ni cargan datos.

import 'package:flutter/material.dart';

import '../../../dominio/dominio.dart';
import '../../comun/formato.dart';
import '../../comun/tema/theme.dart';
import '../../comun/widgets/widgets.dart';

/// Fila "En turno · horario · radio" arriba del listado de alertas.
class BarraTurno extends StatelessWidget {
  const BarraTurno({super.key, required this.guardia});
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

/// Tarjeta con el estado del turno, horario y radio de cobertura.
class TarjetaTurno extends StatelessWidget {
  const TarjetaTurno({super.key, required this.guardia, required this.estado, required this.enTurno});
  final Guardia guardia;

  /// Etiqueta ya decidida: "En turno", "Fuera de turno" o "Sin zona".
  final String estado;
  final bool enTurno;

  @override
  Widget build(BuildContext context) {
    final p = guardia.perfil;
    return SlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SlChip(label: estado, color: enTurno ? AppColors.success : AppColors.warning, icon: Icons.circle),
          AppSpacing.gapSm,
          InfoRow(icon: Icons.schedule_rounded, label: 'Horario', value: '${p.inicioTurno} – ${p.finTurno}'),
          InfoRow(
            icon: Icons.radar_rounded,
            label: 'Radio de cobertura',
            value: p.radioCoberturaMetros == null ? 'Sin asignar' : Fmt.distance(p.radioCoberturaMetros!),
          ),
        ],
      ),
    );
  }
}
