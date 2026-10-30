// CAPA: DATOS — datos ficticios de Morelos (sección 9)
// Usuarios, guardias y ~80 alertas de historial en Emiliano Zapata y Cuernavaca.
// Los turnos "en turno" se calculan relativos a [ahora] para que la demo siempre
// tenga guardias disponibles. Siempre genera lo mismo para el mismo [ahora].
// No hace: no guarda nada; MemoriaBaseDatos copia estas listas.
//
// Cuentas de prueba (contraseña de todas: `SafeLink1`):
// | Correo                     | Rol                 | Notas                           |
// |----------------------------|---------------------|---------------------------------|
// | usuario@safelink.mx        | Usuario protegido   | Sin alerta activa, con historial|
// | rosa.diaz@mail.com         | Usuario protegido   | 2 falsas alarmas (1 más bloquea)|
// | bloqueado@safelink.mx      | Usuario protegido   | Bloqueado 5 días más            |
// | guardia@safelink.mx        | Guardia             | En turno, con alertas cerca     |
// | guardia.noche@safelink.mx  | Guardia             | Turno 22:00 → 06:00             |
// | admin@safelink.mx          | Administrador       |                                 |

import 'dart:math';

import '../dominio/dominio.dart';

class DatosSemilla {
  DatosSemilla(this.ahora);

  final DateTime ahora;
  final _azar = Random(7);

  static const contrasena = 'SafeLink1';
  static const centroEmilianoZapata = PuntoGeo(18.8400, -99.1800);
  static const centroCuernavaca = PuntoGeo(18.9186, -99.2342);

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
  }

  // ── Guardias ──────────────────────────────────────────────────────
  void _guardias() {
    String hhmm(DateTime t) => ReglaTurno.deHoraMinuto(t.hour, t.minute);
    // Turnos relativos a "ahora" para que la demo siempre tenga guardias en turno.
    final enInicio = hhmm(ahora.subtract(const Duration(hours: 2)));
    final enFin = hhmm(ahora.add(const Duration(hours: 6)));
    final fueraInicio = hhmm(ahora.add(const Duration(hours: 3)));
    final fueraFin = hhmm(ahora.add(const Duration(hours: 11)));

    perfiles.addAll([
      PerfilGuardia(usuarioId: 'grd-1', inicioTurno: enInicio, finTurno: enFin, centroCobertura: centroEmilianoZapata, radioCoberturaMetros: 4000, ultimaUbicacion: const PuntoGeo(18.8385, -99.1835), ultimaUbicacionEn: ahora),
      PerfilGuardia(usuarioId: 'grd-2', inicioTurno: enInicio, finTurno: enFin, centroCobertura: centroCuernavaca, radioCoberturaMetros: 5000, ultimaUbicacion: const PuntoGeo(18.9150, -99.2300), ultimaUbicacionEn: ahora),
      PerfilGuardia(usuarioId: 'grd-3', inicioTurno: enInicio, finTurno: enFin, centroCobertura: const PuntoGeo(18.8600, -99.1950), radioCoberturaMetros: 3000, ultimaUbicacion: const PuntoGeo(18.8590, -99.1940), ultimaUbicacionEn: ahora),
      // Turno nocturno que cruza medianoche.
      const PerfilGuardia(usuarioId: 'grd-4', inicioTurno: '22:00', finTurno: '06:00', centroCobertura: centroEmilianoZapata, radioCoberturaMetros: 4000, ultimaUbicacion: PuntoGeo(18.8420, -99.1790)),
      PerfilGuardia(usuarioId: 'grd-5', inicioTurno: fueraInicio, finTurno: fueraFin, centroCobertura: centroEmilianoZapata, radioCoberturaMetros: 2000),
      PerfilGuardia(usuarioId: 'grd-6', inicioTurno: enInicio, finTurno: enFin, centroCobertura: const PuntoGeo(18.9220, -99.2380), radioCoberturaMetros: 3500, ultimaUbicacion: const PuntoGeo(18.9230, -99.2370), ultimaUbicacionEn: ahora),
      PerfilGuardia(usuarioId: 'grd-7', inicioTurno: fueraInicio, finTurno: fueraFin, centroCobertura: const PuntoGeo(18.8300, -99.1700), radioCoberturaMetros: 2500),
      // Recién dado de alta: aún sin radio de cobertura (no recibe alertas).
      const PerfilGuardia(usuarioId: 'grd-8', inicioTurno: '08:00', finTurno: '16:00', centroCobertura: null, radioCoberturaMetros: null),
    ]);
  }

  // ── Alertas activas (todos los estados) ──────────────────────────
  void _alertasActivas() {
    PuntoGeo cerca(PuntoGeo c, double dLat, double dLng) => PuntoGeo(c.lat + dLat, c.lng + dLng);
    DateTime hace(int minutos) => ahora.subtract(Duration(minutes: minutos));
    String foto(String semilla) => 'https://picsum.photos/seed/$semilla/640/420';
    const ez = centroEmilianoZapata;
    const cva = centroCuernavaca;

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

    alertas.addAll([
      // Buscando guardia: visibles para guardia@safelink.mx (grd-1)
      alerta('alt-101', 'usr-3', EstadoAlerta.buscando, MetodoDisparo.agitacion, 1, ubicacion: cerca(ez, 0.0110, 0.0060), rumbo: 40),
      alerta('alt-102', 'usr-2', EstadoAlerta.buscando, MetodoDisparo.toque, 2, ubicacion: cerca(ez, -0.0020, 0.0015), rumbo: 185),
      alerta('alt-103', 'usr-5', EstadoAlerta.buscando, MetodoDisparo.mantener, 4, ubicacion: cerca(ez, 0.0140, -0.0120), rumbo: 300, sinFoto: true),
      alerta('alt-104', 'usr-6', EstadoAlerta.buscando, MetodoDisparo.toque, 0, ubicacion: cerca(ez, 0.0050, 0.0040), rumbo: 90),
      // Buscando en Cuernavaca (grd-2, grd-6)
      alerta('alt-105', 'usr-7', EstadoAlerta.buscando, MetodoDisparo.agitacion, 3, ubicacion: cerca(cva, 0.0040, -0.0030), rumbo: 210),
      // Resto de estados activos
      alerta('alt-201', 'usr-8', EstadoAlerta.pendienteUbicacion, MetodoDisparo.toque, 1),
      alerta('alt-202', 'usr-7', EstadoAlerta.enAtencion, MetodoDisparo.mantener, 9, guardiaId: 'grd-2', aceptada: hace(8), ubicacion: cerca(cva, 0.0100, -0.0080), rumbo: 120, eta: 240),
      alerta('alt-203', 'usr-3', EstadoAlerta.guardiaEnLugar, MetodoDisparo.toque, 14, guardiaId: 'grd-3', aceptada: hace(13), llegada: hace(3), ubicacion: cerca(ez, 0.0190, -0.0140), rumbo: 15),
      alerta('alt-204', 'usr-5', EstadoAlerta.sinRespuesta, MetodoDisparo.toque, 6, ubicacion: cerca(ez, 0.0900, 0.0400), rumbo: 220),
      // Escaladas (las dos razones) y una resuelta por admin
      alerta('alt-301', 'usr-3', EstadoAlerta.escalada, MetodoDisparo.agitacion, 22, razon: RazonEscalamiento.sinRespuesta, ubicacion: cerca(ez, 0.0300, 0.0250), rumbo: 75),
      alerta('alt-302', 'usr-2', EstadoAlerta.escalada, MetodoDisparo.toque, 48, guardiaId: 'grd-1', aceptada: hace(47), llegada: hace(38), razon: RazonEscalamiento.sinConfirmacion, ubicacion: cerca(ez, -0.0060, 0.0080), rumbo: 260),
      alerta('alt-303', 'usr-6', EstadoAlerta.escalada, MetodoDisparo.mantener, 75, guardiaId: 'grd-6', aceptada: hace(73), llegada: hace(60), razon: RazonEscalamiento.sinConfirmacion, ubicacion: cerca(cva, 0.0020, 0.0050), rumbo: 330),
      alerta('alt-304', 'usr-4', EstadoAlerta.resueltaPorAdmin, MetodoDisparo.toque, 60 * 26, guardiaId: 'grd-1', aceptada: hace(60 * 26 - 1), llegada: hace(60 * 26 - 9), cerrada: hace(60 * 25), razon: RazonEscalamiento.sinConfirmacion, resolucion: Resolucion.falsaAlarma, nota: 'Se verificó con la usuaria; no hubo riesgo.', ubicacion: cerca(ez, 0.0020, -0.0030), rumbo: 0),
    ]);
  }

  // ── Historial: 80 alertas en los últimos 30 días ─────────────────
  void _historial() {
    const guardias = ['grd-1', 'grd-2', 'grd-3', 'grd-1', 'grd-6', 'grd-7', 'grd-4', 'grd-5'];
    const protegidos = ['usr-1', 'usr-2', 'usr-3', 'usr-5', 'usr-6', 'usr-7', 'usr-8', 'usr-1'];
    // Más alertas en la noche para que la gráfica por hora tenga forma.
    const horas = [0, 1, 2, 7, 8, 12, 14, 17, 18, 19, 20, 20, 21, 21, 22, 22, 23, 23];
    const resoluciones = Resolucion.values;

    for (var i = 0; i < 80; i++) {
      final gid = guardias[i % guardias.length];
      final perfil = perfiles.firstWhere((p) => p.usuarioId == gid);
      final centro = perfil.centroCobertura ?? centroEmilianoZapata;
      final u = _u(protegidos[_azar.nextInt(protegidos.length)]);
      final dia = ahora.subtract(Duration(days: 1 + _azar.nextInt(29)));
      final t = DateTime(dia.year, dia.month, dia.day, horas[i % horas.length], _azar.nextInt(60));
      final aceptar = 20 + _azar.nextInt(160); // segundos
      final llegar = 240 + _azar.nextInt(600); // segundos
      final sinFoto = i % 7 == 0;
      final tipo = i % 10; // 0–7 cerrada · 8 sin confirmación · 9 sin respuesta
      final sinRespuesta = tipo == 9;
      final g = sinRespuesta ? null : _u(gid);

      alertas.add(Alerta(
        id: 'alt-h${i.toString().padLeft(2, '0')}',
        usuarioId: u.id,
        nombreUsuario: u.nombre,
        telefonoUsuario: u.telefono,
        guardiaId: g?.id,
        nombreGuardia: g?.nombre,
        estado: tipo < 8 ? EstadoAlerta.cerrada : EstadoAlerta.resueltaPorAdmin,
        metodo: MetodoDisparo.values[i % 3],
        disparadaEn: t,
        aceptadaEn: sinRespuesta ? null : t.add(Duration(seconds: aceptar)),
        llegadaEn: sinRespuesta ? null : t.add(Duration(seconds: aceptar + llegar)),
        cerradaEn: t.add(Duration(seconds: aceptar + llegar + 180 + (tipo < 8 ? 0 : 1800))),
        razonEscalamiento: switch (tipo) {
          8 => RazonEscalamiento.sinConfirmacion,
          9 => RazonEscalamiento.sinRespuesta,
          _ => null,
        },
        resolucion: tipo < 8 ? null : resoluciones[(i ~/ 10) % resoluciones.length],
        ubicacion: PuntoGeo(centro.lat + (_azar.nextDouble() - 0.5) * 0.05, centro.lng + (_azar.nextDouble() - 0.5) * 0.05),
        rumbo: _azar.nextInt(360),
        fotoUrl: sinFoto ? null : 'https://picsum.photos/seed/slh$i/640/420',
        evidenciaIncompleta: sinFoto,
      ),);
    }
  }
}
