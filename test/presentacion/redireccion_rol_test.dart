// U-02 · G-01 (unitaria) — "la función de navegación devuelve la pantalla del
// botón de alerta para el usuario protegido y nunca la de otro rol".
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/enums.dart';
import 'package:safelink/presentacion/comun/rutas/app_router.dart';
import 'package:safelink/presentacion/comun/rutas/app_routes.dart';

void main() {
  test('el usuario protegido entra al botón de alerta', () {
    expect(inicioPara(RolUsuario.usuarioProtegido), AppRoutes.userHome);
  });

  test('el guardia entra a su listado de alertas', () {
    expect(inicioPara(RolUsuario.guardia), AppRoutes.guardHome);
  });

  test('el administrador entra al panel de métricas', () {
    expect(inicioPara(RolUsuario.admin), AppRoutes.adminDashboard);
  });

  test('cada rol tiene un destino propio y ninguno cae en el de otro', () {
    final destinos = RolUsuario.values.map(inicioPara).toList();
    expect(destinos.toSet(), hasLength(RolUsuario.values.length));
  });
}
