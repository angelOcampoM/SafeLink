// CAPA: PRESENTACIÓN — View
// A-08 (vista del usuario) — Cuenta bloqueada por falsas alarmas
// Solo lee la sesión (no carga datos propios, por eso no tiene ViewModel aparte).

import 'package:flutter/material.dart';

import '../comun/formato.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import '../sesion/sesion_view_model.dart';

class BloqueadoPage extends StatelessWidget {
  const BloqueadoPage({super.key, required this.sesion});
  final SesionViewModel sesion;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SafeLink')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: sesion,
          builder: (context, _) {
            final hasta = sesion.usuario?.bloqueadoHasta;
            return CenteredContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: SlChip(label: 'Protección temporalmente limitada', color: AppColors.warning, icon: Icons.lock_outline_rounded),
                  ),
                  AppSpacing.gapLg,
                  const Center(child: StatusHalo(icon: Icons.lock_clock_rounded, color: AppColors.warning)),
                  AppSpacing.gapLg,
                  Text('Tu cuenta está bloqueada', style: context.text.headlineMedium, textAlign: TextAlign.center),
                  AppSpacing.gapXs,
                  Text(
                    'Detectamos falsas alarmas repetidas. El botón de alerta estará deshabilitado durante este periodo para proteger el servicio.',
                    style: context.text.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.gapLg,
                  if (hasta != null) ...[
                    SlCard(
                      accent: AppColors.warning,
                      child: Row(
                        children: [
                          const Icon(Icons.event_available_outlined, color: AppColors.warning, size: AppSizes.iconLg),
                          AppSpacing.gapMd,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('EL BLOQUEO TERMINA', style: context.text.labelSmall?.copyWith(letterSpacing: 1.2)),
                                AppSpacing.gapXxs,
                                Text('${Fmt.date(hasta)}, ${Fmt.time(hasta)}', style: context.text.titleMedium),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppSpacing.gapLg,
                  ],
                  const SlBanner(
                    message: 'En una emergencia real llama al 911. Si crees que es un error, contacta al administrador.',
                  ),
                  AppSpacing.gapMd,
                  SlButton(label: 'Cerrar sesión', variant: SlButtonVariant.secondary, onPressed: sesion.cerrarSesion),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
