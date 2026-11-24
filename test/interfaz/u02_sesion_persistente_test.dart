// U-02 — "La sesión permanece activa al cerrar y volver a abrir la aplicación".
// Arranca la app completa con y sin sesión guardada y comprueba dónde cae.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/memoria_admin_repository.dart';
import 'package:safelink/datos/memoria_alerta_guardia_repository.dart';
import 'package:safelink/datos/memoria_alerta_usuario_repository.dart';
import 'package:safelink/datos/memoria_auth_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/datos/memoria_sesion_guardada.dart';
import 'package:safelink/main.dart';
import 'package:safelink/presentacion/comun/tema/theme.dart';

void main() {
  setUpAll(AppTypography.useSystemFontForTests);

  /// Abre la app como lo hace `main()`: restaura la sesión guardada y pinta.
  Future<void> abrirApp(WidgetTester tester, MemoriaSesionGuardada almacen) async {
    tester.view.physicalSize = const Size(1800, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final db = MemoriaBaseDatos(latencia: Duration.zero);
    addTearDown(db.dispose);
    final deps = Dependencias(
      auth: MemoriaAuthRepository(db),
      alertasUsuario: MemoriaAlertaUsuarioRepository(db),
      alertasGuardia: MemoriaAlertaGuardiaRepository(db),
      admin: MemoriaAdminRepository(db),
      sesionGuardada: almacen,
    );

    await deps.sesion.restaurar();
    await tester.pumpWidget(SafeLinkApp(dependencias: deps, simular: false));
    // El inicio late en bucle: pumps fijos en vez de pumpAndSettle.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('con sesión guardada la app abre en el botón de alerta', (tester) async {
    await abrirApp(tester, MemoriaSesionGuardada(usuarioId: 'usr-1', permisosVistos: {'usr-1'}));

    expect(find.text('Toca o mantén presionado'), findsWidgets);
    expect(find.text('Bienvenido de nuevo'), findsNothing);
  });

  testWidgets('con sesión guardada pero sin ver los permisos, los explica primero', (tester) async {
    await abrirApp(tester, MemoriaSesionGuardada(usuarioId: 'usr-1'));

    expect(find.text('Permisos para protegerte'), findsOneWidget);
  });

  testWidgets('sin sesión guardada la app abre en el login', (tester) async {
    await abrirApp(tester, MemoriaSesionGuardada());

    expect(find.text('Bienvenido de nuevo'), findsOneWidget);
  });
}
