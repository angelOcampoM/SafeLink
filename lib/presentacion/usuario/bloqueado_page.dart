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
      body: SafeArea(
        child: ListenableBuilder(
          listenable: sesion,
          builder: (context, _) {
            final hasta = sesion.usuario?.bloqueadoHasta;
            return Padding(
              padding: AppSpacing.screen,
              child: Column(
                children: [
                  Expanded(
                    child: EmptyState(
                      icon: Icons.lock_clock_rounded,
                      color: AppColors.warning,
                      title: 'Tu cuenta está bloqueada',
                      message: hasta == null
                          ? 'Por varias falsas alarmas no puedes enviar alertas por ahora.'
                          : 'Por varias falsas alarmas no puedes enviar alertas hasta el ${Fmt.date(hasta)} a las ${Fmt.time(hasta)}.',
                    ),
                  ),
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
