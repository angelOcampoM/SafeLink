// CAPA: DOMINIO — la alerta de seguridad (sección 4.3)
// U-03 a U-09 · G-02 a G-07 · A-04 · A-05
// Incluye campos "de lectura" que la API agrega para la UI (nombreUsuario,
// nombreGuardia, etaSegundos) y que no existen en la tabla.
// No hace: no decide transiciones (ReglaAlerta) ni sabe de JSON.

import 'enums.dart';
import 'punto_geo.dart';

class Alerta {
  const Alerta({
    required this.id,
    required this.usuarioId,
    required this.estado,
    required this.metodo,
    required this.disparadaEn,
    this.nombreUsuario,
    this.telefonoUsuario,
    this.guardiaId,
    this.nombreGuardia,
    this.fotoUrl,
    this.evidenciaIncompleta = false,
    this.ubicacion,
    this.rumbo,
    this.aceptadaEn,
    this.llegadaEn,
    this.cerradaEn,
    this.razonEscalamiento,
    this.resolucion,
    this.etaSegundos,
  });

  final String id;
  final String usuarioId;
  final String? nombreUsuario;
  final String? telefonoUsuario;
  final String? guardiaId;
  final String? nombreGuardia;
  final EstadoAlerta estado;
  final MetodoDisparo metodo;
  final String? fotoUrl;
  final bool evidenciaIncompleta;
  final PuntoGeo? ubicacion;
  final int? rumbo;
  final DateTime disparadaEn;
  final DateTime? aceptadaEn;
  final DateTime? llegadaEn;
  final DateTime? cerradaEn;
  final RazonEscalamiento? razonEscalamiento;
  final Resolucion? resolucion;
  final int? etaSegundos;

  /// Agitación = urgente (sección 6.3).
  bool get esUrgente => metodo == MetodoDisparo.agitacion;

  Duration esperaA(DateTime ahora) => ahora.difference(disparadaEn);

  Alerta copyWith({
    EstadoAlerta? estado,
    String? guardiaId,
    String? nombreGuardia,
    DateTime? aceptadaEn,
    DateTime? llegadaEn,
    DateTime? cerradaEn,
    RazonEscalamiento? razonEscalamiento,
    Resolucion? resolucion,
    PuntoGeo? ubicacion,
    int? etaSegundos,
  }) =>
      Alerta(
        id: id,
        usuarioId: usuarioId,
        nombreUsuario: nombreUsuario,
        telefonoUsuario: telefonoUsuario,
        guardiaId: guardiaId ?? this.guardiaId,
        nombreGuardia: nombreGuardia ?? this.nombreGuardia,
        estado: estado ?? this.estado,
        metodo: metodo,
        fotoUrl: fotoUrl,
        evidenciaIncompleta: evidenciaIncompleta,
        ubicacion: ubicacion ?? this.ubicacion,
        rumbo: rumbo,
        disparadaEn: disparadaEn,
        aceptadaEn: aceptadaEn ?? this.aceptadaEn,
        llegadaEn: llegadaEn ?? this.llegadaEn,
        cerradaEn: cerradaEn ?? this.cerradaEn,
        razonEscalamiento: razonEscalamiento ?? this.razonEscalamiento,
        resolucion: resolucion ?? this.resolucion,
        etaSegundos: etaSegundos ?? this.etaSegundos,
      );
}
