// G-07 Registro de llegada — "Llegué" solo dentro de la geocerca.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/abridor_enlaces.dart';
import 'package:safelink/datos/memoria_sesion_guardada.dart';
import 'package:safelink/datos/sensores_simulados.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/comun/estado_vista.dart';
import 'package:safelink/presentacion/guardia/navegacion_view_model.dart';
import 'package:safelink/presentacion/guardia/seguimiento_guardia.dart';
import 'package:safelink/presentacion/sesion/sesion_view_model.dart';

import 'espias.dart';

void main() {
  const config = Configuracion(radioGeocercaMetros: 50);
  const lejos = PuntoGeo(18.8500, -99.1800); // ~1.1 km
  const cerca = PuntoGeo(18.8403, -99.1800); // ~33 m

  Future<(NavegacionViewModel, AlertaGuardiaEspia)> crear(PuntoGeo ubicacion) async {
    final repo = AlertaGuardiaEspia(alerta: alertaPrueba(estado: EstadoAlerta.enAtencion), guardia: guardiaPrueba(ubicacion: ubicacion));
    final vm = NavegacionViewModel(repo, 'alt-1', config: config);
    await vm.iniciar();
    await Future<void>.delayed(Duration.zero); // primer evento del stream
    return (vm, repo);
  }

  test('"Llegué" deshabilitado fuera de la geocerca y no llama al repositorio', () async {
    final (vm, repo) = await crear(lejos);

    expect(vm.dentroDeGeocerca, isFalse);
    expect(vm.puedeMarcarLlegada, isFalse);
    expect(vm.metrosRestantes, greaterThan(1000));

    await vm.marcarLlegada();
    expect(repo.llegadas, isEmpty);
    expect(vm.mensaje, 'Aún no estás en el punto de la alerta');
    vm.dispose();
  });

  test('dentro de la geocerca se habilita y registra la llegada', () async {
    final (vm, repo) = await crear(cerca);

    expect(vm.puedeMarcarLlegada, isTrue);
    await vm.marcarLlegada();
    expect(repo.llegadas, ['alt-1']);
    vm.dispose();
  });

  test('simular acercamiento avanza la ubicación hacia la alerta', () async {
    final (vm, repo) = await crear(lejos);
    final antes = vm.distancia!;

    await vm.simularAcercamiento();

    expect(repo.ubicaciones, hasLength(1));
    expect(vm.distancia, closeTo(antes * 0.4, 5));
    vm.dispose();
  });

  group('CR-F03 · con la API real la posición sale del GPS', () {
    const configReal = Configuracion(radioGeocercaMetros: 50, modoDemo: false);
    const afuera = PuntoGeo(18.8390, -99.1800); // ~111 m al sur de la alerta
    late UbicacionSimulada gps;
    late SeguimientoGuardia seguimiento;

    SesionViewModel sesionGuardia() =>
        SesionViewModel(AuthEspia(usuarioActual: usuarioPrueba(rol: RolUsuario.guardia)), MemoriaSesionGuardada());

    Future<(NavegacionViewModel, AlertaGuardiaEspia)> crearReal({required PuntoGeo perfil}) async {
      final repo = AlertaGuardiaEspia(
        alerta: alertaPrueba(estado: EstadoAlerta.enAtencion),
        guardia: guardiaPrueba(ubicacion: perfil),
      );
      gps = UbicacionSimulada(inicial: afuera, paso: 0.0008); // un paso = ~89 m al norte
      seguimiento = SeguimientoGuardia(alertas: repo, ubicacion: gps, sesion: sesionGuardia())..iniciar();
      await Future<void>.delayed(const Duration(milliseconds: 10)); // lectura inicial del GPS
      final vm = NavegacionViewModel(repo, 'alt-1', config: configReal, seguimiento: seguimiento);
      await vm.iniciar();
      await Future<void>.delayed(Duration.zero);
      return (vm, repo);
    }

    tearDown(() {
      seguimiento.dispose();
      gps.dispose();
    });

    test('manda el GPS sobre la última ubicación guardada en el servidor', () async {
      final (vm, _) = await crearReal(perfil: cerca); // el servidor cree que ya está cerca

      expect(vm.miUbicacion, afuera);
      expect(vm.puedeMarcarLlegada, isFalse, reason: 'la geocerca usa la posición real, no la guardada');
      vm.dispose();
    });

    test('al caminar hacia la alerta se habilita "Llegué"', () async {
      final (vm, repo) = await crearReal(perfil: lejos);
      expect(vm.puedeMarcarLlegada, isFalse);

      gps.mover();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(vm.distancia, lessThan(50));
      expect(vm.puedeMarcarLlegada, isTrue);
      final enviadasAntes = repo.ubicaciones.length;
      await vm.marcarLlegada();
      expect(repo.llegadas, ['alt-1']);
      expect(
        repo.ubicaciones,
        hasLength(enviadasAntes + 1),
        reason: 'antes de la llegada se manda la posición de ahora: el servidor valida con esa',
      );
      expect(repo.ubicaciones.last, vm.miUbicacion);
      vm.dispose();
    });

    test('si la pantalla se cierra mientras carga, no queda escuchando el GPS', () async {
      final repo = AlertaGuardiaEspia(
        alerta: alertaPrueba(estado: EstadoAlerta.enAtencion),
        guardia: guardiaPrueba(ubicacion: lejos),
      );
      gps = UbicacionSimulada(inicial: afuera, paso: 0.0008);
      seguimiento = SeguimientoGuardia(alertas: repo, ubicacion: gps, sesion: sesionGuardia())..iniciar();
      final vm = NavegacionViewModel(repo, 'alt-1', config: configReal, seguimiento: seguimiento);

      final carga = vm.iniciar();
      vm.dispose(); // se salió antes de que respondiera el perfil
      await carga;
      final antes = vm.miUbicacion;
      gps.mover();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(vm.miUbicacion, antes, reason: 'el ViewModel desechado ya no recibe posiciones');
    });

    test('"Simular acercamiento" no hace nada fuera del modo demo', () async {
      final (vm, repo) = await crearReal(perfil: lejos);
      final enviadasAntes = repo.ubicaciones.length;
      final antes = vm.miUbicacion;

      await vm.simularAcercamiento();

      expect(vm.miUbicacion, antes);
      expect(repo.ubicaciones, hasLength(enviadasAntes), reason: 'no manda una posición falsa al servidor');
      vm.dispose();
    });
  });

  group('G-06 · ruta y tiempo estimado (CR-F04)', () {
    test('la dirección de Google Maps lleva el punto de la alerta como destino', () {
      final url = NavegacionViewModel.urlRuta(const PuntoGeo(18.84, -99.18));

      expect(url.toString(), 'https://www.google.com/maps/dir/?api=1&destination=18.84%2C-99.18');
    });

    test('"Abrir en Google Maps" abre la ruta hacia la alerta', () async {
      final enlaces = AbridorEnlacesSimulado();
      final repo = AlertaGuardiaEspia(alerta: alertaPrueba(estado: EstadoAlerta.enAtencion), guardia: guardiaPrueba(ubicacion: lejos));
      final vm = NavegacionViewModel(repo, 'alt-1', config: config, enlaces: enlaces);
      await vm.iniciar();
      await Future<void>.delayed(Duration.zero);

      await vm.abrirEnGoogleMaps();

      expect(enlaces.abiertos, [NavegacionViewModel.urlRuta(puntoAlerta)]);
      expect(vm.mensaje, isNull);
      vm.dispose();
    });

    test('si no se puede abrir, avisa en español y la pantalla sigue', () async {
      final repo = AlertaGuardiaEspia(alerta: alertaPrueba(estado: EstadoAlerta.enAtencion), guardia: guardiaPrueba(ubicacion: lejos));
      final vm = NavegacionViewModel(repo, 'alt-1', config: config, enlaces: AbridorEnlacesSimulado(falla: true));
      await vm.iniciar();
      await Future<void>.delayed(Duration.zero);

      await vm.abrirEnGoogleMaps();

      expect(vm.mensaje, 'No se pudo abrir Google Maps. Revisa que esté instalado.');
      expect(vm.estado, isA<Listo<Alerta>>());
      vm.dispose();
    });

    test('sin ubicación del usuario no intenta abrir nada', () async {
      final enlaces = AbridorEnlacesSimulado();
      final repo = AlertaGuardiaEspia(
        alerta: alertaPrueba(estado: EstadoAlerta.enAtencion, ubicacion: null),
        guardia: guardiaPrueba(ubicacion: lejos),
      );
      final vm = NavegacionViewModel(repo, 'alt-1', config: config, enlaces: enlaces);
      await vm.iniciar();
      await Future<void>.delayed(Duration.zero);

      await vm.abrirEnGoogleMaps();

      expect(enlaces.abiertos, isEmpty);
      expect(vm.mensaje, isNotNull);
      vm.dispose();
    });

    test('el tiempo estimado baja con la distancia y usa la velocidad configurada', () async {
      const conVelocidad = Configuracion(radioGeocercaMetros: 50, metrosPorMinutoGuardia: 250);
      final repo = AlertaGuardiaEspia(alerta: alertaPrueba(estado: EstadoAlerta.enAtencion), guardia: guardiaPrueba(ubicacion: lejos));
      final vm = NavegacionViewModel(repo, 'alt-1', config: conVelocidad);
      expect(vm.segundosEstimados, isNull, reason: 'sin posiciones todavía no hay estimado');
      await vm.iniciar();
      await Future<void>.delayed(Duration.zero);

      final esperado = ReglaEta.segundos(distanciaMetros: vm.distancia!, metrosPorMinutoGuardia: 250);
      expect(vm.segundosEstimados, esperado);
      expect(vm.segundosEstimados, greaterThan(0));
      vm.dispose();
    });
  });
}
