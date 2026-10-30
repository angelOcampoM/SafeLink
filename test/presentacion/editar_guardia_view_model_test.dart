// A-01 Alta de guardia · A-02 Edición — validación de campos, contraseña
// inicial que elige el admin y correo repetido. Con memoria para el guardado
// real (el login posterior prueba que la contraseña se guardó).
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/memoria_admin_repository.dart';
import 'package:safelink/datos/memoria_auth_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/admin/editar_guardia_view_model.dart';

import 'espias.dart';

void main() {
  late MemoriaBaseDatos db;

  setUp(() {
    db = MemoriaBaseDatos(reloj: () => ahoraPrueba, latencia: Duration.zero);
  });

  tearDown(() => db.dispose());

  test('en alta valida todos los campos obligatorios', () async {
    final vm = EditarGuardiaViewModel(MemoriaAdminRepository(db));
    await vm.cargar();

    final ok = await vm.guardar(nombre: '', correo: 'mal', telefono: '12', contrasena: '');

    expect(ok, isFalse);
    expect(vm.errorNombre, isNotNull);
    expect(vm.errorCorreo, isNotNull);
    expect(vm.errorTelefono, isNotNull);
    expect(vm.errorContrasena, isNotNull);
    vm.dispose();
  });

  test('la contraseña inicial exige 8 caracteres y un número', () async {
    final vm = EditarGuardiaViewModel(MemoriaAdminRepository(db));
    await vm.cargar();

    var ok = await vm.guardar(nombre: 'Ana Pérez', correo: 'ana@safelink.mx', telefono: '7771234567', contrasena: 'corta');
    expect(ok, isFalse);
    expect(vm.errorContrasena, 'Mínimo 8 caracteres');

    ok = await vm.guardar(nombre: 'Ana Pérez', correo: 'ana@safelink.mx', telefono: '7771234567', contrasena: 'sinnumero');
    expect(ok, isFalse);
    expect(vm.errorContrasena, 'Incluye al menos un número');
    vm.dispose();
  });

  test('el guardia creado entra con la contraseña que eligió el admin', () async {
    final vm = EditarGuardiaViewModel(MemoriaAdminRepository(db));
    await vm.cargar();

    final ok = await vm.guardar(nombre: 'Ana Pérez Lugo', correo: 'ana@safelink.mx', telefono: '7771234567', contrasena: 'Guardia123');

    expect(ok, isTrue);
    final u = await MemoriaAuthRepository(db).iniciarSesion(correo: 'ana@safelink.mx', contrasena: 'Guardia123');
    expect(u.rol, RolUsuario.guardia);
    vm.dispose();
  });

  test('el correo repetido se rechaza', () async {
    final vm = EditarGuardiaViewModel(MemoriaAdminRepository(db));
    await vm.cargar();

    final ok = await vm.guardar(nombre: 'Otra Persona', correo: 'guardia@safelink.mx', telefono: '7770000000', contrasena: 'Guardia123');

    expect(ok, isFalse);
    expect(vm.error, isNotNull);
    vm.dispose();
  });

  test('en edición no se pide contraseña y se actualizan los datos', () async {
    final vm = EditarGuardiaViewModel(MemoriaAdminRepository(db), guardiaId: 'grd-1');
    await vm.cargar();
    expect(vm.estado.datos, isNotNull);

    final ok = await vm.guardar(nombre: 'Carlos H. López', correo: 'guardia@safelink.mx', telefono: '7772345611');

    expect(ok, isTrue);
    expect(vm.errorContrasena, isNull);
    final g = await MemoriaAdminRepository(db).obtenerGuardia('grd-1');
    expect(g.usuario.nombre, 'Carlos H. López');
    expect(g.usuario.telefono, '7772345611');
    vm.dispose();
  });
}
