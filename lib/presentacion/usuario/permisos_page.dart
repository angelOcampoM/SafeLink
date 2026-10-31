// CAPA: PRESENTACIÓN — View
// U-01 · U-02 Permisos — se muestra la primera vez que el usuario protegido entra
// (al terminar el registro o en su primer inicio de sesión) y desde Configuración.
// Solo explica para qué se usa cada acceso y avisa a la sesión que ya se vieron;
// el router decide cuándo mostrarla (igual que la pantalla de bloqueo).
// Sin ViewModel propio: no carga datos ni guarda estado.
//
// TODO(U-06): pedir los permisos reales del sistema al tocar "Continuar"
// (cámara, ubicación en segundo plano y notificaciones).

import 'package:flutter/material.dart';

import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import '../sesion/sesion_view_model.dart';

class PermisosPage extends StatelessWidget {
  const PermisosPage({super.key, required this.sesion});
  final SesionViewModel sesion;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CenteredContent(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BrandMark(),
              AppSpacing.gapLg,
              Text(
                'Permisos para protegerte',
                style: context.text.headlineMedium,
                textAlign: TextAlign.center,
              ),
              AppSpacing.gapXs,
              Text(
                'SafeLink solo usa estos accesos cuando son necesarios para atender una alerta.',
                style: context.text.bodyMedium,
                textAlign: TextAlign.center,
              ),
              AppSpacing.gapLg,
              const _Permiso(
                icon: Icons.photo_camera_outlined,
                title: 'Cámara',
                message: 'Captura una foto al enviar la alerta para dar contexto inmediato al guardia.',
              ),
              AppSpacing.gapSm,
              const _Permiso(
                icon: Icons.location_on_outlined,
                title: 'Ubicación',
                message: 'Comparte tu ubicación y rumbo en tiempo real mientras recibes ayuda.',
              ),
              AppSpacing.gapSm,
              const _Permiso(
                icon: Icons.notifications_none_rounded,
                title: 'Notificaciones',
                message: 'Recibe actualizaciones importantes sobre la llegada del guardia.',
              ),
              AppSpacing.gapLg,
              SlButton(label: 'Continuar', onPressed: sesion.permisosVistos),
              AppSpacing.gapSm,
              Text(
                'Puedes cambiar estos permisos después desde Configuración.',
                style: context.text.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fila de la lista de permisos: símbolo, nombre y razón de uso.
class _Permiso extends StatelessWidget {
  const _Permiso({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SlCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(color: AppColors.tint(AppColors.info), borderRadius: AppRadius.brMd),
            child: Icon(icon, color: AppColors.info, size: AppSizes.iconMd),
          ),
          AppSpacing.gapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleMedium),
                AppSpacing.gapXxs,
                Text(message, style: context.text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
