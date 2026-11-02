// CAPA: DATOS — datos ficticios de Morelos (sección 9)
// Usuarios, guardias, alertas activas e historial, como si fueran respuestas de la API:
// cada alerta es UN registro que la base en memoria hace avanzar por sus estados.
// Los turnos "en turno" y todas las fechas se calculan relativos a [ahora] (nunca hay
// fechas fijas ni en el futuro). Siempre genera lo mismo para el mismo [ahora].
// No hace: no guarda nada; MemoriaBaseDatos copia estas listas.
//
// Cuentas de prueba (contraseña de todas: `SafeLink1`):
// | Correo                       | Rol               | Notas                            |
// |------------------------------|-------------------|----------------------------------|
// | usuario@safelink.mx          | Usuario protegido | Sin alerta activa, con historial |
// | rosa.diaz@mail.com           | Usuario protegido | 2 falsas alarmas (1 más bloquea) |
// | bloqueado@safelink.mx        | Usuario protegido | Bloqueado 5 días más             |
// | guardia@safelink.mx          | Guardia (grd-1)   | En turno, con alertas cerca      |
// | daniela.salgado@safelink.mx  | Guardia (grd-2)   | En turno                         |
// | jorge.ocampo@safelink.mx     | Guardia (grd-3)   | En turno, ya en el lugar de una  |
// | guardia.noche@safelink.mx    | Guardia (grd-4)   | Turno 22:00 → 06:00              |
// | paola.estrada@safelink.mx    | Guardia (grd-6)   | En turno                         |
// | andres.figueroa@safelink.mx  | Guardia (grd-7)   | Fuera de turno                   |
// | sofia.rendon@safelink.mx     | Guardia (grd-8)   | Sin zona, sin historial          |
// | admin@safelink.mx            | Administrador     |                                  |
//
// Zonas de cobertura: círculos sin traslape (el borde más cercano entre dos zonas
// queda a 1.4 km: grd-1 ↔ grd-2), así dos guardias nunca ven ni se quitan una alerta.
// Qué trae cada guardia (historial por cubeta: hoy · ayer · 2–7 d · 8–30 d · 31–120 d):
// | Guardia | Zona (centro · radio)        | Disponibles     | Historial                          |
// |---------|------------------------------|-----------------|------------------------------------|
// | grd-1   | Emiliano Zapata · 4 km       | alt-101…104     | 2 · 2 · 4 · 5 · 3 (+ alt-302, -304) |
// | grd-2   | Cuernavaca · 5 km            | alt-105, 111…113| 2 · 2 · 4 · 5 · 3                  |
// | grd-3   | Yautepec · 4 km              | alt-114…117     | 2 · 2 · 4 · 5 · 3                  |
// | grd-4   | Cuautla · 4 km (nocturno)    | alt-118…121     | 2 · 2 · 4 · 5 · 3                  |
// | grd-5   | Jojutla · 2 km (dado de baja)| —               | 0 · 0 · 0 · 0 · 3                  |
// | grd-6   | Tepoztlán · 3.5 km           | alt-122…125     | 2 · 2 · 4 · 5 · 3 (+ alt-303)      |
// | grd-7   | Xochitepec · 2.5 km (fuera)  | alt-126, 127    | 2 · 2 · 4 · 5 · 3                  |
// | grd-8   | sin zona                     | —               | vacío (para probar el estado vacío)|
// - Disponibles de cada guardia en turno: un método de cada tipo, una sin foto y distancias
//   ≤ 500 m, ≤ 1 km, ≤ 3 km y más de 3 km desde su última ubicación.
// - Historial: mayoría `cerrada`, una `escalada` sin confirmación (sigue en la bandeja del
//   admin) y varias `resueltaPorAdmin`; los tres métodos, con y sin foto. Ids `alt-h…`
//   (≤ 30 días, ≥ 80) y `alt-v…` (más antiguas). Si faltan menos de 30 min desde la
//   medianoche, las 2 de "hoy" pasan a "ayer" (no cabe una atención completa).
// - Las "sin respuesta" no tienen guardia: solo las ve el admin.
// - Cada alerta activa es de un usuario distinto; `usr-28…35` quedan libres para que la
//   simulación de alertas nuevas tenga a quién elegir.

import 'dart:math';

import '../dominio/dominio.dart';

class DatosSemilla {
  DatosSemilla(this.ahora);

  final DateTime ahora;
  final _azar = Random(7);

  static const contrasena = 'SafeLink1';
  static const centroEmilianoZapata = PuntoGeo(18.8400, -99.1800);
  static const centroCuernavaca = PuntoGeo(18.9186, -99.2342);
  static const centroYautepec = PuntoGeo(18.8833, -99.0667);
  static const centroCuautla = PuntoGeo(18.8122, -98.9548);
  static const centroTepoztlan = PuntoGeo(18.9850, -99.0990);
  static const centroXochitepec = PuntoGeo(18.7800, -99.2300);
  static const centroJojutla = PuntoGeo(18.6150, -99.1800);

  /// Punto a [metros] de [desde] con rumbo [grados] (0 = norte, 90 = este).
  /// Aproximación plana: a escala de ciudad el error es menor al 1 %.
  static PuntoGeo aDistancia(PuntoGeo desde, double metros, int grados) {
    final r = grados * pi / 180;
    return PuntoGeo(
      desde.lat + metros * cos(r) / 111320,
      desde.lng + metros * sin(r) / (111320 * cos(desde.lat * pi / 180)),
    );
  }

  /// Última ubicación conocida de los guardias en turno (de ahí se miden las distancias).
  static const ubicacionGrd1 = PuntoGeo(18.8385, -99.1835);
  static const ubicacionGrd2 = PuntoGeo(18.9150, -99.2300);
  static final ubicacionGrd3 = aDistancia(centroYautepec, 600, 225);
  static final ubicacionGrd4 = aDistancia(centroCuautla, 500, 45);
  static final ubicacionGrd6 = aDistancia(centroTepoztlan, 300, 180);

  /// Ubicación simulada del teléfono del usuario protegido.
  static const ubicacionDispositivoUsuario = PuntoGeo(18.8452, -99.1771);

  /// Correos que la pantalla de login ofrece para rellenar (solo demo).
  static const cuentasDemo = [
    ('Usuario', 'usuario@safelink.mx'),
    ('Bloqueado', 'bloqueado@safelink.mx'),
    ('Guardia', 'guardia@safelink.mx'),
    ('Guardia noche', 'guardia.noche@safelink.mx'),
    ('Admin', 'admin@safelink.mx'),
  ];

  final usuarios = <Usuario>[];
  final perfiles = <PerfilGuardia>[];
  final alertas = <Alerta>[];

  DatosSemilla construir() {
    _usuarios();
    _guardias();
    _alertasActivas();
    _historial();
    return this;
  }

  Usuario _u(String id) => usuarios.firstWhere((u) => u.id == id);

  // ── Usuarios ──────────────────────────────────────────────────────
  void _usuarios() {
    final creado = ahora.subtract(const Duration(days: 90));
    Usuario guardia(String id, String nombre, String correo, String tel, {bool activo = true}) =>
        Usuario(id: id, nombre: nombre, correo: correo, telefono: tel, rol: RolUsuario.guardia, activo: activo, creadoEn: creado);
    Usuario protegido(String id, String nombre, String correo, String tel, {bool agitacion = false, int falsas = 0, DateTime? bloqueo}) =>
        Usuario(id: id, nombre: nombre, correo: correo, telefono: tel, rol: RolUsuario.usuarioProtegido, agitacionActiva: agitacion, falsasAlarmas: falsas, bloqueadoHasta: bloqueo, creadoEn: creado);

    usuarios.addAll([
      Usuario(id: 'adm-1', nombre: 'Mariana Ortega Ruiz', correo: 'admin@safelink.mx', telefono: '7771002030', rol: RolUsuario.admin, creadoEn: creado),
      // Guardias
      guardia('grd-1', 'Carlos Hernández López', 'guardia@safelink.mx', '7772345610'),
      guardia('grd-2', 'Daniela Salgado Pérez', 'daniela.salgado@safelink.mx', '7773456721'),
      guardia('grd-3', 'Jorge Ocampo Bahena', 'jorge.ocampo@safelink.mx', '7774567832'),
      guardia('grd-4', 'Ramiro Villalobos Cruz', 'guardia.noche@safelink.mx', '7775678943'),
      guardia('grd-5', 'Luis Arturo Nava Díaz', 'luis.nava@safelink.mx', '7776789054', activo: false),
      guardia('grd-6', 'Paola Estrada Mena', 'paola.estrada@safelink.mx', '7777890165'),
      guardia('grd-7', 'Andrés Figueroa Ávila', 'andres.figueroa@safelink.mx', '7778901276'),
      guardia('grd-8', 'Sofía Rendón Campos', 'sofia.rendon@safelink.mx', '7779012387'),
      // Usuarios protegidos
      protegido('usr-1', 'Fernanda Morales Gil', 'usuario@safelink.mx', '7771234567', agitacion: true),
      protegido('usr-2', 'Rosa María Díaz Toledo', 'rosa.diaz@mail.com', '7772233445', falsas: 2),
      protegido('usr-3', 'Héctor Jaimes Rosales', 'hector.jaimes@mail.com', '7773344556'),
      protegido('usr-4', 'Iván Castañeda Soto', 'bloqueado@safelink.mx', '7774455667', falsas: 3, bloqueo: ahora.add(const Duration(days: 5))),
      protegido('usr-5', 'Guadalupe Benítez Arce', 'lupita.benitez@mail.com', '7775566778'),
      protegido('usr-6', 'Miguel Ángel Tapia Ruiz', 'miguel.tapia@mail.com', '7776677889', falsas: 1),
      protegido('usr-7', 'Valeria Campos Ocampo', 'valeria.campos@mail.com', '7777788990', agitacion: true),
      protegido('usr-8', 'Ernesto Salazar Pliego', 'ernesto.salazar@mail.com', '7778899001'),
    ]);
    // Más usuarios protegidos para que cada alerta activa sea de una persona distinta
    // (nadie tiene dos a la vez) y la simulación de alertas nuevas tenga a quién elegir.
    for (final (i, (nombre, correo)) in _masProtegidos.indexed) {
      usuarios.add(protegido('usr-${i + 9}', nombre, correo, '77730${(i + 9).toString().padLeft(5, '0')}'));
    }
  }

  static const _masProtegidos = [
    ('Alejandra Rojas Medina', 'alejandra.rojas@mail.com'),
    ('Bruno Galindo Ortiz', 'bruno.galindo@mail.com'),
    ('Claudia Pineda Luna', 'claudia.pineda@mail.com'),
    ('Diego Sámano Reyes', 'diego.samano@mail.com'),
    ('Elena Bustamante Cruz', 'elena.bustamante@mail.com'),
    ('Fabián Olivares Mora', 'fabian.olivares@mail.com'),
    ('Gabriela Quintero Salas', 'gabriela.quintero@mail.com'),
    ('Hugo Montiel Vega', 'hugo.montiel@mail.com'),
    ('Irene Zúñiga Barrera', 'irene.zuniga@mail.com'),
    ('Javier Peralta Núñez', 'javier.peralta@mail.com'),
    ('Karla Bahena Flores', 'karla.bahena@mail.com'),
    ('Leonardo Avilés Ríos', 'leonardo.aviles@mail.com'),
    ('Mónica Trujillo Sosa', 'monica.trujillo@mail.com'),
    ('Norberto Cázares León', 'norberto.cazares@mail.com'),
    ('Olivia Mendoza Garduño', 'olivia.mendoza@mail.com'),
    ('Pablo Ayala Jiménez', 'pablo.ayala@mail.com'),
    ('Regina Carrillo Paz', 'regina.carrillo@mail.com'),
    ('Samuel Lira Arriaga', 'samuel.lira@mail.com'),
    ('Teresa Uribe Domínguez', 'teresa.uribe@mail.com'),
    ('Ulises Navarrete Gil', 'ulises.navarrete@mail.com'),
    ('Verónica Saldaña Ruiz', 'veronica.saldana@mail.com'),
    ('Wenceslao Ortega Díaz', 'wenceslao.ortega@mail.com'),
    ('Ximena Arellano Toledo', 'ximena.arellano@mail.com'),
    ('Yolanda Ferrer Campos', 'yolanda.ferrer@mail.com'),
    ('Zacarías Lozano Brito', 'zacarias.lozano@mail.com'),
    ('Adriana Villegas Soto', 'adriana.villegas@mail.com'),
    ('Bernardo Cuevas Nava', 'bernardo.cuevas@mail.com'),
  ];

  // ── Guardias ──────────────────────────────────────────────────────
  void _guardias() {
    String hhmm(DateTime t) => ReglaTurno.deHoraMinuto(t.hour, t.minute);
    // Turnos relativos a "ahora" para que la demo siempre tenga guardias en turno.
    final enInicio = hhmm(ahora.subtract(const Duration(hours: 2)));
    final enFin = hhmm(ahora.add(const Duration(hours: 6)));
    final fueraInicio = hhmm(ahora.add(const Duration(hours: 3)));
    final fueraFin = hhmm(ahora.add(const Duration(hours: 11)));

    // Cada guardia con zona tiene la suya, sin traslapes (≥ 500 m entre bordes; ver cabecera).
    perfiles.addAll([
      PerfilGuardia(usuarioId: 'grd-1', inicioTurno: enInicio, finTurno: enFin, centroCobertura: centroEmilianoZapata, radioCoberturaMetros: 4000, zona: 'Emiliano Zapata', ultimaUbicacion: ubicacionGrd1, ultimaUbicacionEn: ahora),
      PerfilGuardia(usuarioId: 'grd-2', inicioTurno: enInicio, finTurno: enFin, centroCobertura: centroCuernavaca, radioCoberturaMetros: 5000, zona: 'Cuernavaca', ultimaUbicacion: ubicacionGrd2, ultimaUbicacionEn: ahora),
      PerfilGuardia(usuarioId: 'grd-3', inicioTurno: enInicio, finTurno: enFin, centroCobertura: centroYautepec, radioCoberturaMetros: 4000, zona: 'Yautepec', ultimaUbicacion: ubicacionGrd3, ultimaUbicacionEn: ahora),
      // Turno nocturno que cruza medianoche.
      PerfilGuardia(usuarioId: 'grd-4', inicioTurno: '22:00', finTurno: '06:00', centroCobertura: centroCuautla, radioCoberturaMetros: 4000, zona: 'Cuautla', ultimaUbicacion: ubicacionGrd4),
      PerfilGuardia(usuarioId: 'grd-5', inicioTurno: fueraInicio, finTurno: fueraFin, centroCobertura: centroJojutla, radioCoberturaMetros: 2000, zona: 'Jojutla'),
      PerfilGuardia(usuarioId: 'grd-6', inicioTurno: enInicio, finTurno: enFin, centroCobertura: centroTepoztlan, radioCoberturaMetros: 3500, zona: 'Tepoztlán', ultimaUbicacion: ubicacionGrd6, ultimaUbicacionEn: ahora),
      PerfilGuardia(usuarioId: 'grd-7', inicioTurno: fueraInicio, finTurno: fueraFin, centroCobertura: centroXochitepec, radioCoberturaMetros: 2500, zona: 'Xochitepec'),
      // Recién dado de alta: aún sin radio de cobertura (no recibe alertas).
      const PerfilGuardia(usuarioId: 'grd-8', inicioTurno: '08:00', finTurno: '16:00', centroCobertura: null, radioCoberturaMetros: null),
    ]);
  }

  // ── Alertas activas (todos los estados) ──────────────────────────
  void _alertasActivas() {
    DateTime hace(int minutos) => ahora.subtract(Duration(minutes: minutos));
    String foto(String semilla) => 'https://picsum.photos/seed/$semilla/640/420';

    Alerta alerta(
      String id,
      String usuarioId,
      EstadoAlerta estado,
      MetodoDisparo metodo,
      int minutos, {
      PuntoGeo? ubicacion,
      int? rumbo,
      String? guardiaId,
      DateTime? aceptada,
      DateTime? llegada,
      DateTime? cerrada,
      RazonEscalamiento? razon,
      Resolucion? resolucion,
      String? nota,
      bool sinFoto = false,
      int? eta,
    }) {
      final u = _u(usuarioId);
      return Alerta(
        id: id,
        usuarioId: u.id,
        nombreUsuario: u.nombre,
        telefonoUsuario: u.telefono,
        guardiaId: guardiaId,
        nombreGuardia: guardiaId == null ? null : _u(guardiaId).nombre,
        estado: estado,
        metodo: metodo,
        disparadaEn: hace(minutos),
        aceptadaEn: aceptada,
        llegadaEn: llegada,
        cerradaEn: cerrada,
        razonEscalamiento: razon,
        resolucion: resolucion,
        notaAdmin: nota,
        ubicacion: ubicacion,
        rumbo: rumbo,
        fotoUrl: sinFoto ? null : foto('sl$id'),
        evidenciaIncompleta: sinFoto,
        etaSegundos: eta,
      );
    }

    // Disponible para un solo guardia: [metros] y [grados] se miden desde su última ubicación.
    Alerta buscando(String id, String usuarioId, MetodoDisparo metodo, int minutos, PuntoGeo base, double metros, int grados, {bool sinFoto = false}) =>
        alerta(id, usuarioId, EstadoAlerta.buscando, metodo, minutos, ubicacion: aDistancia(base, metros, grados), rumbo: (grados * 7) % 360, sinFoto: sinFoto);

    alertas.addAll([
      // Buscando guardia. Cada guardia en turno tiene 4: un método de cada tipo, una sin foto
      // y distancias ≤ 500 m, ≤ 1 km, ≤ 3 km y más de 3 km.
      // grd-1 (guardia@safelink.mx) · Emiliano Zapata
      buscando('alt-101', 'usr-3', MetodoDisparo.agitacion, 1, ubicacionGrd1, 850, 20),
      buscando('alt-102', 'usr-2', MetodoDisparo.toque, 2, ubicacionGrd1, 3300, 60),
      buscando('alt-103', 'usr-5', MetodoDisparo.mantener, 4, ubicacionGrd1, 2200, 300, sinFoto: true),
      buscando('alt-104', 'usr-6', MetodoDisparo.toque, 0, ubicacionGrd1, 350, 110),
      // grd-2 (daniela.salgado) · Cuernavaca
      buscando('alt-105', 'usr-7', MetodoDisparo.agitacion, 3, ubicacionGrd2, 450, 200),
      buscando('alt-111', 'usr-11', MetodoDisparo.toque, 1, ubicacionGrd2, 900, 80),
      buscando('alt-112', 'usr-12', MetodoDisparo.mantener, 5, ubicacionGrd2, 2500, 250, sinFoto: true),
      buscando('alt-113', 'usr-13', MetodoDisparo.toque, 2, ubicacionGrd2, 3600, 315),
      // grd-3 (jorge.ocampo) · Yautepec
      buscando('alt-114', 'usr-14', MetodoDisparo.agitacion, 2, ubicacionGrd3, 300, 150),
      buscando('alt-115', 'usr-15', MetodoDisparo.toque, 0, ubicacionGrd3, 950, 300),
      buscando('alt-116', 'usr-16', MetodoDisparo.mantener, 6, ubicacionGrd3, 1800, 10, sinFoto: true),
      buscando('alt-117', 'usr-17', MetodoDisparo.toque, 3, ubicacionGrd3, 3300, 45),
      // grd-4 (guardia.noche, 22:00–06:00) · Cuautla
      buscando('alt-118', 'usr-18', MetodoDisparo.agitacion, 1, ubicacionGrd4, 400, 270),
      buscando('alt-119', 'usr-19', MetodoDisparo.mantener, 4, ubicacionGrd4, 900, 120, sinFoto: true),
      buscando('alt-120', 'usr-20', MetodoDisparo.toque, 2, ubicacionGrd4, 2600, 200),
      buscando('alt-121', 'usr-21', MetodoDisparo.toque, 7, ubicacionGrd4, 3400, 225),
      // grd-6 (paola.estrada) · Tepoztlán
      buscando('alt-122', 'usr-22', MetodoDisparo.agitacion, 2, ubicacionGrd6, 250, 60),
      buscando('alt-123', 'usr-23', MetodoDisparo.toque, 1, ubicacionGrd6, 700, 330),
      buscando('alt-124', 'usr-24', MetodoDisparo.mantener, 3, ubicacionGrd6, 2100, 100, sinFoto: true),
      buscando('alt-125', 'usr-25', MetodoDisparo.toque, 5, ubicacionGrd6, 3150, 0),
      // grd-7 (andres.figueroa, fuera de turno) · Xochitepec: las verá al entrar a su turno
      buscando('alt-126', 'usr-26', MetodoDisparo.agitacion, 2, centroXochitepec, 700, 45),
      buscando('alt-127', 'usr-27', MetodoDisparo.mantener, 6, centroXochitepec, 1500, 250, sinFoto: true),
      // Resto de estados activos (cada una en la zona del guardia que la atiende)
      alerta('alt-201', 'usr-8', EstadoAlerta.pendienteUbicacion, MetodoDisparo.toque, 1),
      alerta('alt-202', 'usr-9', EstadoAlerta.enAtencion, MetodoDisparo.mantener, 9, guardiaId: 'grd-2', aceptada: hace(8), ubicacion: aDistancia(ubicacionGrd2, 1600, 320), rumbo: 120, eta: 240),
      // grd-3 ya está en el lugar: su última ubicación queda dentro de la geocerca.
      alerta('alt-203', 'usr-10', EstadoAlerta.guardiaEnLugar, MetodoDisparo.toque, 14, guardiaId: 'grd-3', aceptada: hace(13), llegada: hace(3), ubicacion: aDistancia(ubicacionGrd3, 25, 90), rumbo: 15),
      alerta('alt-204', 'usr-5', EstadoAlerta.sinRespuesta, MetodoDisparo.toque, 6, ubicacion: aDistancia(centroYautepec, 2500, 300), rumbo: 220),
      // Escaladas (las dos razones) y una resuelta por admin
      alerta('alt-301', 'usr-3', EstadoAlerta.escalada, MetodoDisparo.agitacion, 22, razon: RazonEscalamiento.sinRespuesta, ubicacion: aDistancia(centroEmilianoZapata, 2500, 40), rumbo: 75),
      alerta('alt-302', 'usr-2', EstadoAlerta.escalada, MetodoDisparo.toque, 48, guardiaId: 'grd-1', aceptada: hace(47), llegada: hace(38), razon: RazonEscalamiento.sinConfirmacion, ubicacion: aDistancia(centroEmilianoZapata, 1100, 130), rumbo: 260),
      alerta('alt-303', 'usr-6', EstadoAlerta.escalada, MetodoDisparo.mantener, 75, guardiaId: 'grd-6', aceptada: hace(73), llegada: hace(60), razon: RazonEscalamiento.sinConfirmacion, ubicacion: aDistancia(centroTepoztlan, 1200, 250), rumbo: 330),
      alerta('alt-304', 'usr-4', EstadoAlerta.resueltaPorAdmin, MetodoDisparo.toque, 60 * 26, guardiaId: 'grd-1', aceptada: hace(60 * 26 - 1), llegada: hace(60 * 26 - 9), cerrada: hace(60 * 25), razon: RazonEscalamiento.sinConfirmacion, resolucion: Resolucion.falsaAlarma, ubicacion: aDistancia(centroEmilianoZapata, 400, 300), rumbo: 0),
    ]);
  }

  // ── Historial por guardia ─────────────────────────────────────────
  /// Lo que atendió cada guardia: (días atrás, resultado, método, con foto).
  /// 0 = hoy · 1 = ayer · 2–7 · 8–30 · más de 30 días (estas con id `alt-v…`).
  static const _plantilla = <(int, _Resultado, MetodoDisparo, bool)>[
    (0, _Resultado.cerrada, MetodoDisparo.toque, true),
    (0, _Resultado.cerrada, MetodoDisparo.agitacion, true),
    (1, _Resultado.cerrada, MetodoDisparo.mantener, false),
    (1, _Resultado.escalada, MetodoDisparo.toque, true),
    (3, _Resultado.cerrada, MetodoDisparo.agitacion, true),
    (4, _Resultado.cerrada, MetodoDisparo.toque, false),
    (5, _Resultado.resueltaPorAdmin, MetodoDisparo.mantener, true),
    (6, _Resultado.cerrada, MetodoDisparo.mantener, true),
    (9, _Resultado.cerrada, MetodoDisparo.toque, true),
    (13, _Resultado.cerrada, MetodoDisparo.agitacion, false),
    (18, _Resultado.resueltaPorAdmin, MetodoDisparo.toque, true),
    (22, _Resultado.cerrada, MetodoDisparo.mantener, true),
    (27, _Resultado.cerrada, MetodoDisparo.toque, true),
    (45, _Resultado.cerrada, MetodoDisparo.agitacion, true),
    (70, _Resultado.resueltaPorAdmin, MetodoDisparo.mantener, false),
    (100, _Resultado.cerrada, MetodoDisparo.toque, true),
  ];

  /// Días de las alertas que nadie aceptó (sin guardia: solo las ve el admin).
  static const _diasSinRespuesta = [2, 5, 9, 12, 16, 20, 24, 28];

  /// Más alertas en la noche para que la gráfica por hora tenga forma.
  static const _horas = [0, 1, 2, 7, 8, 12, 14, 17, 18, 19, 20, 20, 21, 21, 22, 22, 23, 23];

  void _historial() {
    const historicos = ['usr-1', 'usr-2', 'usr-3', 'usr-5', 'usr-6', 'usr-7', 'usr-8', 'usr-1'];
    final todos = [for (final u in usuarios) if (u.rol == RolUsuario.usuarioProtegido) u.id];
    var h = 0;
    var v = 0;
    var k = 0;

    void agregar(String? guardiaId, PerfilGuardia zona, int dias, _Resultado? resultado, MetodoDisparo metodo, bool conFoto) {
      final i = k++;
      final id = dias > 30 ? 'alt-v${(v++).toString().padLeft(2, '0')}' : 'alt-h${(h++).toString().padLeft(2, '0')}';
      // La mitad con los usuarios de siempre (usr-1 aparece seguido en su historial).
      final u = _u(i.isEven ? historicos[_azar.nextInt(historicos.length)] : todos[_azar.nextInt(todos.length)]);
      final g = guardiaId == null ? null : _u(guardiaId);
      final aceptar = Duration(seconds: 20 + _azar.nextInt(160));
      final llegar = Duration(seconds: 240 + _azar.nextInt(600));
      final cierre = switch (resultado) {
        _Resultado.cerrada => Duration(seconds: 60 + _azar.nextInt(240)),
        _Resultado.resueltaPorAdmin => Duration(seconds: 1800 + _azar.nextInt(1200)),
        _Resultado.escalada => null, // sigue en la bandeja del admin
        null => Duration(seconds: 1800 + _azar.nextInt(1800)), // sin respuesta: la cierra el admin
      };
      final duracion = (g == null ? Duration.zero : aceptar + llegar) + (cierre ?? Duration.zero);
      final t = _momento(dias, i, duracion);
      final llegada = g == null ? null : t.add(aceptar + llegar);
      final centro = zona.centroCobertura!;

      alertas.add(Alerta(
        id: id,
        usuarioId: u.id,
        nombreUsuario: u.nombre,
        telefonoUsuario: u.telefono,
        guardiaId: g?.id,
        nombreGuardia: g?.nombre,
        estado: switch (resultado) {
          _Resultado.cerrada => EstadoAlerta.cerrada,
          _Resultado.escalada => EstadoAlerta.escalada,
          _ => EstadoAlerta.resueltaPorAdmin,
        },
        metodo: metodo,
        disparadaEn: t,
        aceptadaEn: g == null ? null : t.add(aceptar),
        llegadaEn: llegada,
        cerradaEn: cierre == null ? null : t.add(duracion),
        razonEscalamiento: switch (resultado) {
          _Resultado.cerrada => null,
          null => RazonEscalamiento.sinRespuesta,
          _ => RazonEscalamiento.sinConfirmacion,
        },
        resolucion: resultado == _Resultado.resueltaPorAdmin || resultado == null ? Resolucion.values[i % Resolucion.values.length] : null,
        ubicacion: aDistancia(centro, zona.radioCoberturaMetros! * 0.85 * sqrt(_azar.nextDouble()), _azar.nextInt(360)),
        rumbo: _azar.nextInt(360),
        fotoUrl: conFoto ? 'https://picsum.photos/seed/sl$id/640/420' : null,
        evidenciaIncompleta: !conFoto,
      ),);
    }

    PerfilGuardia perfil(String id) => perfiles.firstWhere((p) => p.usuarioId == id);
    const conHistorial = ['grd-1', 'grd-2', 'grd-3', 'grd-4', 'grd-6', 'grd-7'];
    for (final (n, gid) in conHistorial.indexed) {
      for (final (dias, resultado, metodo, conFoto) in _plantilla) {
        // Cada guardia corre sus fechas un día (sin salir de la cubeta) para que no coincidan.
        agregar(gid, perfil(gid), dias < 2 ? dias : dias + n % 2, resultado, metodo, conFoto);
      }
    }
    // grd-5 (dado de baja) solo trae alertas antiguas; grd-8 no trae ninguna.
    for (final (dias, resultado, metodo, conFoto) in _plantilla.where((p) => p.$1 > 30)) {
      agregar('grd-5', perfil('grd-5'), dias, resultado, metodo, conFoto);
    }
    for (final (n, dias) in _diasSinRespuesta.indexed) {
      agregar(null, perfil(conHistorial[n % conHistorial.length]), dias, null, MetodoDisparo.values[n % 3], n % 3 != 0);
    }
  }

  /// Cuándo se disparó una alerta de hace [dias] días que tardó [duracion] en cerrarse.
  /// Nunca queda en el futuro. Las de hoy caen entre medianoche y `ahora − duración`;
  /// si faltan menos de 30 min desde medianoche no caben y pasan a ayer.
  DateTime _momento(int dias, int i, Duration duracion) {
    final medianoche = DateTime(ahora.year, ahora.month, ahora.day);
    final margen = duracion + const Duration(minutes: 1);
    if (dias == 0 && ahora.difference(medianoche) >= const Duration(minutes: 30)) {
      final hueco = ahora.difference(medianoche) - margen;
      return medianoche.add(hueco * _azar.nextDouble());
    }
    final dia = dias == 0 ? 1 : dias;
    final t = DateTime(ahora.year, ahora.month, ahora.day - dia, _horas[i % _horas.length], _azar.nextInt(60));
    return t.add(margen).isAfter(ahora) ? ahora.subtract(margen) : t;
  }
}

/// Resultado de una alerta del historial (`null` en [DatosSemilla._historial] = sin respuesta).
enum _Resultado { cerrada, escalada, resueltaPorAdmin }
