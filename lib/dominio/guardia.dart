// CAPA: DOMINIO — guardia y su perfil operativo (sección 4.2)
// A-03 Turnos y radios · G-02 Disponibilidad
// Turno "HH:mm" (puede cruzar medianoche), zona de cobertura y última ubicación.
// No hace: no calcula turnos ni distancias por su cuenta; pregunta a ReglaTurno.

import 'punto_geo.dart';
import 'regla_turno.dart';
import 'usuario.dart';

class PerfilGuardia {
  const PerfilGuardia({
    required this.usuarioId,
    required this.inicioTurno,
    required this.finTurno,
    required this.centroCobertura,
    required this.radioCoberturaMetros,
    this.zona,
    this.ultimaUbicacion,
    this.ultimaUbicacionEn,
  });

  final String usuarioId;
  final String inicioTurno;
  final String finTurno;
  final PuntoGeo? centroCobertura;
  final int? radioCoberturaMetros;

  /// Nombre de la zona de cobertura (A-06 distribución por zona).
  final String? zona;
  final PuntoGeo? ultimaUbicacion;
  final DateTime? ultimaUbicacionEn;

  bool enTurnoA(DateTime horaLocal) => ReglaTurno.dentroDeTurno(inicioTurno, finTurno, horaLocal);

  bool get tieneCobertura => centroCobertura != null && (radioCoberturaMetros ?? 0) > 0;

  PerfilGuardia copyWith({
    String? inicioTurno,
    String? finTurno,
    PuntoGeo? centroCobertura,
    int? radioCoberturaMetros,
    String? zona,
    PuntoGeo? ultimaUbicacion,
    DateTime? ultimaUbicacionEn,
  }) =>
      PerfilGuardia(
        usuarioId: usuarioId,
        inicioTurno: inicioTurno ?? this.inicioTurno,
        finTurno: finTurno ?? this.finTurno,
        centroCobertura: centroCobertura ?? this.centroCobertura,
        radioCoberturaMetros: radioCoberturaMetros ?? this.radioCoberturaMetros,
        zona: zona ?? this.zona,
        ultimaUbicacion: ultimaUbicacion ?? this.ultimaUbicacion,
        ultimaUbicacionEn: ultimaUbicacionEn ?? this.ultimaUbicacionEn,
      );
}

/// Usuario guardia + su perfil.
class Guardia {
  const Guardia({required this.usuario, required this.perfil});

  final Usuario usuario;
  final PerfilGuardia perfil;

  /// Disponible = activo + en turno + con radio (sección 4.2).
  bool disponibleA(DateTime horaLocal) => usuario.activo && perfil.tieneCobertura && perfil.enTurnoA(horaLocal);
}
