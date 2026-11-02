// G-03 Pull-to-refresh del guardia: en cada estado de Alertas (y en Inicio e Historial)
// hay UN solo RefreshIndicator, y al arrastrar se ve un solo spinner que desaparece al terminar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/alerta_guardia_repository.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/comun/tema/theme.dart';
import 'package:safelink/presentacion/guardia/historial_guardia_page.dart';
import 'package:safelink/presentacion/guardia/historial_guardia_view_model.dart';
import 'package:safelink/presentacion/guardia/inicio_guardia_page.dart';
import 'package:safelink/presentacion/guardia/inicio_guardia_view_model.dart';
import 'package:safelink/presentacion/guardia/listado_alertas_page.dart';
import 'package:safelink/presentacion/guardia/listado_alertas_view_model.dart';
import 'package:safelink/presentacion/sesion/sesion_view_model.dart';

import '../presentacion/espias.dart';

/// Repositorio con respuestas configurables y una demora en cada carga del perfil.
class RepoControlado implements AlertaGuardiaRepository {
  RepoControlado({
    Guardia? guardia,
    this.fallaPerfil = false,
    this.disponibles = const [],
    this.fallaDisponibles = false,
    this.historial = const [],
    this.demora = const Duration(milliseconds: 500),
  }) : guardia = guardia ?? guardiaPrueba(ubicacion: puntoAlerta);

  final Guardia guardia;
  final bool fallaPerfil;
  final List<AlertaPriorizada> disponibles;
  final bool fallaDisponibles;
  final List<Alerta> historial;
  Duration demora;

  @override
  Future<Guardia> obtenerMiPerfil() async {
    await Future<void>.delayed(demora);
    if (fallaPerfil) throw const ServicioNoDisponibleError();
    return guardia;
  }

  @override
  Stream<List<AlertaPriorizada>> escucharAlertasDisponibles() =>
      fallaDisponibles ? Stream.error(const ServicioNoDisponibleError()) : Stream.value(disponibles);

  @override
  Future<List<Alerta>> obtenerMiHistorial() async {
    await Future<void>.delayed(demora);
    return historial;
  }

  @override
  Future<MetricasGuardia> obtenerMisMetricas() async => MetricasGuardia.vacias;

  @override
  Future<Alerta> obtenerAlerta(String alertaId) => throw UnimplementedError();
  @override
  Stream<Alerta> escucharAlerta(String alertaId) => throw UnimplementedError();
  @override
  Future<Alerta> aceptarAlerta(String alertaId) => throw UnimplementedError();
  @override
  Future<void> ignorarAlerta(String alertaId) async {}
  @override
  Future<void> actualizarMiUbicacion(PuntoGeo ubicacion) async {}
  @override
  Future<Alerta> marcarLlegada(String alertaId) => throw UnimplementedError();
}

AlertaPriorizada priorizada(String id, MetodoDisparo metodo, double metros) => AlertaPriorizada(
      Alerta(id: id, usuarioId: 'u-$id', nombreUsuario: 'Usuario $id', estado: EstadoAlerta.buscando, metodo: metodo, disparadaEn: ahoraPrueba, ubicacion: puntoAlerta),
      metros,
      0,
      metros,
    );

Alerta atendida(String id) => Alerta(
      id: id,
      usuarioId: 'u-1',
      nombreUsuario: 'Fernanda Morales Gil',
      guardiaId: 'u-1',
      estado: EstadoAlerta.cerrada,
      metodo: MetodoDisparo.toque,
      disparadaEn: ahoraPrueba.subtract(const Duration(hours: 1)),
      aceptadaEn: ahoraPrueba.subtract(const Duration(minutes: 59)),
      llegadaEn: ahoraPrueba.subtract(const Duration(minutes: 50)),
      cerradaEn: ahoraPrueba.subtract(const Duration(minutes: 45)),
      ubicacion: puntoAlerta,
    );

void main() {
  setUpAll(AppTypography.useSystemFontForTests);

  final sesion = SesionViewModel(AuthEspia());

  Future<void> montar(WidgetTester tester, Widget pagina, {bool esperarCarga = true}) async {
    tester.view.physicalSize = const Size(1800, 3600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark(), home: pagina));
    if (esperarCarga) await tester.pumpAndSettle();
  }

  Widget listado(RepoControlado repo, {void Function(ListadoAlertasViewModel)? antes}) {
    final vm = ListadoAlertasViewModel(repo, sesion, reloj: () => ahoraPrueba);
    antes?.call(vm);
    return ListadoAlertasPage(viewModel: vm);
  }

  /// Arrastra hacia abajo el contenido del único RefreshIndicator: debe verse un solo
  /// spinner mientras recarga y ninguno al terminar.
  Future<void> recargarConUnSpinner(WidgetTester tester) async {
    expect(find.byType(RefreshIndicator), findsOneWidget);
    final vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    final scroll = find.descendant(of: find.byType(RefreshIndicator), matching: vertical).first;
    await tester.fling(scroll, const Offset(0, 400), 1200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(RefreshProgressIndicator), findsOneWidget, reason: 'un solo spinner mientras recarga');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5)); // termina cualquier carga que siga en curso
    expect(find.byType(RefreshProgressIndicator), findsNothing, reason: 'el spinner desaparece al terminar');
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  group('Alertas: un solo indicador de recarga', () {
    testWidgets('cargando el perfil', (tester) async {
      final repo = RepoControlado(demora: const Duration(seconds: 3));
      await montar(tester, listado(repo), esperarCarga: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Alertas cercanas'), findsOneWidget);
      await recargarConUnSpinner(tester);
      expect(find.text('Usuario a'), findsNothing);
    });

    testWidgets('error al cargar el perfil', (tester) async {
      await montar(tester, listado(RepoControlado(fallaPerfil: true)));
      expect(find.text('No pudimos cargar la información'), findsOneWidget);
      await recargarConUnSpinner(tester);
    });

    testWidgets('fuera de turno', (tester) async {
      final g = guardiaPrueba(ubicacion: puntoAlerta);
      final fuera = Guardia(usuario: g.usuario, perfil: g.perfil.copyWith(inicioTurno: '20:00', finTurno: '22:00'));
      await montar(tester, listado(RepoControlado(guardia: fuera)));
      expect(find.text('No estás recibiendo alertas'), findsOneWidget);
      await recargarConUnSpinner(tester);
    });

    testWidgets('sin zona asignada', (tester) async {
      final g = guardiaPrueba();
      final sinZona = Guardia(
        usuario: g.usuario,
        perfil: const PerfilGuardia(usuarioId: 'u-1', inicioTurno: '08:00', finTurno: '16:00', centroCobertura: null, radioCoberturaMetros: null),
      );
      await montar(tester, listado(RepoControlado(guardia: sinZona)));
      expect(find.textContaining('zona asignada'), findsOneWidget);
      await recargarConUnSpinner(tester);
    });

    testWidgets('sin alertas en la zona', (tester) async {
      await montar(tester, listado(RepoControlado()));
      expect(find.text('Todo tranquilo'), findsOneWidget);
      await recargarConUnSpinner(tester);
    });

    testWidgets('error del listado con el perfil listo', (tester) async {
      await montar(tester, listado(RepoControlado(fallaDisponibles: true)));
      expect(find.text('No pudimos cargar la información'), findsOneWidget);
      await recargarConUnSpinner(tester);
    });

    testWidgets('con alertas', (tester) async {
      final repo = RepoControlado(disponibles: [priorizada('a', MetodoDisparo.toque, 300), priorizada('b', MetodoDisparo.mantener, 900)]);
      await montar(tester, listado(repo));
      expect(find.text('2 alertas'), findsOneWidget);
      await recargarConUnSpinner(tester);
      expect(find.text('2 alertas'), findsOneWidget);
    });

    testWidgets('sin resultados por los filtros', (tester) async {
      final repo = RepoControlado(disponibles: [priorizada('a', MetodoDisparo.toque, 300)]);
      await montar(tester, listado(repo, antes: (vm) => vm.cambiarMetodo(MetodoDisparo.agitacion)));
      expect(find.text('Sin alertas con estos filtros'), findsOneWidget);
      await recargarConUnSpinner(tester);
      expect(find.text('Sin alertas con estos filtros'), findsOneWidget, reason: 'recargar no borra los filtros');
    });
  });

  testWidgets('Inicio: un solo indicador de recarga', (tester) async {
    final repo = RepoControlado(historial: [atendida('h1')]);
    await montar(tester, InicioGuardiaPage(viewModel: InicioGuardiaViewModel(repo, sesion, reloj: () => ahoraPrueba)));
    expect(find.text('MI TURNO'), findsOneWidget);
    await recargarConUnSpinner(tester);
  });

  testWidgets('Historial con datos: un solo indicador de recarga', (tester) async {
    final repo = RepoControlado(historial: [atendida('h1'), atendida('h2')]);
    await montar(tester, HistorialGuardiaPage(viewModel: HistorialGuardiaViewModel(repo, reloj: () => ahoraPrueba)));
    expect(find.text('ALERTAS ATENDIDAS'), findsOneWidget);
    await recargarConUnSpinner(tester);
  });

  testWidgets('Historial vacío: un solo indicador de recarga', (tester) async {
    await montar(tester, HistorialGuardiaPage(viewModel: HistorialGuardiaViewModel(RepoControlado(), reloj: () => ahoraPrueba)));
    expect(find.text('Aún no atiendes alertas'), findsOneWidget);
    await recargarConUnSpinner(tester);
  });
}
