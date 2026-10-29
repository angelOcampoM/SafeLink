// CAPA: PRESENTACIÓN — widgets del guardia
// G-02 Banner "Alerta entrante" · G-03 Listado de alertas disponibles · Fuera de turno
// Piezas del listado: el aviso de alerta nueva, el estado "no recibes alertas" y la lista.
// No hacen: no escuchan streams, no ordenan ni navegan; avisan con callbacks.

import 'package:flutter/material.dart';

import '../../../dominio/dominio.dart';
import '../../comun/formato.dart';
import '../../comun/tema/theme.dart';
import '../../comun/widgets/widgets.dart';

/// Aviso en línea de la alerta nueva de mayor prioridad (G-02).
class BannerAlertaEntrante extends StatelessWidget {
  const BannerAlertaEntrante({super.key, required this.entrante, required this.onVer, required this.onOcultar});
  final AlertaPriorizada entrante;
  final VoidCallback onVer;
  final VoidCallback onOcultar;

  @override
  Widget build(BuildContext context) {
    final a = entrante.alerta;
    return SlBanner(
      type: a.esUrgente ? SlBannerType.warning : SlBannerType.info,
      icon: Icons.notifications_active_rounded,
      title: 'Alerta entrante',
      message: '${a.nombreUsuario ?? 'Usuario'} · ${Fmt.distance(entrante.distanciaMetros)} · ${a.metodo.etiqueta}',
      action: Wrap(
        spacing: AppSpacing.xs,
        children: [
          TextButton(onPressed: onVer, child: const Text('Ver')),
          TextButton(onPressed: onOcultar, child: const Text('Ocultar aviso')),
        ],
      ),
    );
  }
}

/// Fuera de turno o sin zona: explica por qué no llegan alertas (con pull-to-refresh).
class SinRecibirAlertasView extends StatelessWidget {
  const SinRecibirAlertasView({super.key, required this.motivo});
  final String motivo;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        EmptyState(icon: Icons.bedtime_outlined, title: 'No estás recibiendo alertas', message: motivo),
      ],
    );
  }
}

/// Lista de alertas disponibles en el orden recibido, con un contador arriba ("3 de 4 alertas").
class ListaAlertasDisponibles extends StatelessWidget {
  const ListaAlertasDisponibles({super.key, required this.alertas, required this.contador, required this.ahora, required this.onAbrir});
  final List<AlertaPriorizada> alertas;
  final String contador;
  final DateTime ahora;
  final ValueChanged<String> onAbrir;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppSpacing.screen,
      itemCount: alertas.length + 1,
      separatorBuilder: (_, __) => AppSpacing.gapSm,
      itemBuilder: (_, i) => i == 0
          ? Text(contador, style: context.text.bodySmall)
          : AlertCard(
              alert: alertas[i - 1].alerta,
              now: ahora,
              distanceMeters: alertas[i - 1].distanciaMetros,
              showStatus: false,
              onTap: () => onAbrir(alertas[i - 1].alerta.id),
            ),
    );
  }
}
