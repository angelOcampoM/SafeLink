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

/// Tarjeta con el estado del turno, horario, tiempo del turno, radio y última ubicación.
class TarjetaTurno extends StatelessWidget {
  const TarjetaTurno({
    super.key,
    required this.guardia,
    required this.estado,
    required this.enTurno,
    required this.ahora,
    this.minutosRestantes,
    this.minutosParaIniciar,
  });
  final Guardia guardia;

  /// Etiqueta ya decidida: "En turno", "Fuera de turno" o "Sin zona".
  final String estado;
  final bool enTurno;
  final DateTime ahora;
  final int? minutosRestantes;
  final int? minutosParaIniciar;

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
          if (minutosRestantes != null)
            InfoRow(icon: Icons.hourglass_bottom_rounded, label: 'Termina en', value: Fmt.duration(minutosRestantes! * 60)),
          if (minutosParaIniciar != null)
            InfoRow(icon: Icons.hourglass_top_rounded, label: 'Empieza en', value: Fmt.duration(minutosParaIniciar! * 60)),
          InfoRow(
            icon: Icons.radar_rounded,
            label: 'Radio de cobertura',
            value: p.radioCoberturaMetros == null ? 'Sin asignar' : Fmt.distance(p.radioCoberturaMetros!),
          ),
          InfoRow(
            icon: Icons.my_location_rounded,
            label: 'Ubicación actualizada',
            value: p.ultimaUbicacionEn == null ? 'Sin registro' : Fmt.ago(p.ultimaUbicacionEn!, ahora),
          ),
        ],
      ),
    );
  }
}
