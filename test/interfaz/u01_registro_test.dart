// U-01 — el formulario muestra sus errores junto a cada campo y no envía; la
// cuenta se crea con el rol de usuario protegido y no se duplican correos.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/memoria_admin_repository.dart';
import 'package:safelink/datos/memoria_alerta_guardia_repository.dart';
import 'package:safelink/datos/memoria_alerta_usuario_repository.dart';
import 'package:safelink/datos/memoria_auth_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/datos/memoria_sesion_guardada.dart';
import 'package:safelink/dominio/enums.dart';
import 'package:safelink/main.dart';
import 'package:safelink/presentacion/comun/tema/theme.dart';

void main() {
  setUpAll(AppTypography.useSystemFontForTests);

  late MemoriaBaseDatos db;
  late Dependencias deps;

  Future<void> abrirRegistro(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    db = MemoriaBaseDatos(latencia: Duration.zero);
    addTearDown(db.dispose);
    deps = Dependencias(
      auth: MemoriaAuthRepository(db),
      alertasUsuario: MemoriaAlertaUsuarioRepository(db),
      alertasGuardia: MemoriaAlertaGuardiaRepository(db),
      admin: MemoriaAdminRepository(db),
      sesionGuardada: MemoriaSesionGuardada(),
    );
    await tester.pumpWidget(SafeLinkApp(dependencias: deps, simular: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();
  }

  Future<void> llenar(WidgetTester tester, List<String> datos) async {
    for (var i = 0; i < datos.length; i++) {
      await tester.enterText(find.byType(TextFormField).at(i), datos[i]);
    }
  }

  Future<void> registrar(WidgetTester tester) async {
    await tester.tap(find.text('Registrarme'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  testWidgets('con campos vacíos cada uno muestra su error y no se envía', (tester) async {
    await abrirRegistro(tester);
    await registrar(tester);

    expect(find.text('Escribe tu nombre'), findsOneWidget);
    expect(find.text('Escribe tu correo'), findsOneWidget);
    expect(find.text('Escribe tu teléfono'), findsOneWidget);
    expect(find.text('Escribe tu contraseña'), findsOneWidget);
    expect(deps.sesion.haySesion, isFalse, reason: 'el formulario no se envió');
  });

  testWidgets('con formato inválido el error sale junto al campo que falla', (tester) async {
    await abrirRegistro(tester);
    await llenar(tester, ['Ana López Ruiz', 'correo-sin-arroba', '123', 'corta', 'otra']);
    await registrar(tester);

    expect(find.text('Correo no válido'), findsOneWidget);
    expect(find.text('Debe tener 10 dígitos'), findsOneWidget);
    expect(find.text('Mínimo 8 caracteres'), findsOneWidget);
    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
    expect(find.text('Escribe tu nombre'), findsNothing, reason: 'el nombre sí era válido');
    expect(deps.sesion.haySesion, isFalse);
  });

  testWidgets('la cuenta nueva se crea con el rol de usuario protegido', (tester) async {
    await abrirRegistro(tester);
    await llenar(tester, ['Ana López Ruiz', 'ana@safelink.mx', '7771234567', 'SafeLink1', 'SafeLink1']);
    await registrar(tester);

    expect(deps.sesion.usuario?.correo, 'ana@safelink.mx');
    expect(deps.sesion.usuario?.rol, RolUsuario.usuarioProtegido);
    expect(find.text('Permisos para protegerte'), findsOneWidget, reason: 'entra a la app');
  });

  testWidgets('un correo ya registrado muestra error y no crea la cuenta', (tester) async {
    await abrirRegistro(tester);
    final antes = db.usuarios.length;

    await llenar(tester, ['Otra Persona Más', 'usuario@safelink.mx', '7779998877', 'SafeLink1', 'SafeLink1']);
    await registrar(tester);

    expect(find.text('Ese correo ya está registrado'), findsOneWidget);
    expect(deps.sesion.haySesion, isFalse);
    expect(db.usuarios.length, antes, reason: 'no se creó ninguna cuenta');
  });
}
