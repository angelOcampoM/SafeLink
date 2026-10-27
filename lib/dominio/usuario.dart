// CAPA: DOMINIO — persona que usa SafeLink (sección 4.1)
// U-01 Registro · U-05 Agitación · A-08 Bloqueo
// Datos del usuario en cualquiera de los tres roles y consultas simples sobre él.
// No hace: no valida formularios (ReglaRegistro) ni decide bloqueos (ReglaAlerta).

import 'enums.dart';

class Usuario {
  const Usuario({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.telefono,
    required this.rol,
    required this.creadoEn,
    this.activo = true,
    this.agitacionActiva = false,
    this.falsasAlarmas = 0,
    this.bloqueadoHasta,
  });

  final String id;
  final String nombre;
  final String correo;
  final String telefono;
  final RolUsuario rol;
  final bool activo;
  final bool agitacionActiva;
  final int falsasAlarmas;
  final DateTime? bloqueadoHasta;
  final DateTime creadoEn;

  bool bloqueadoEn(DateTime ahora) => bloqueadoHasta != null && bloqueadoHasta!.isAfter(ahora);

  /// "Laura Méndez" → "LM"
  String get iniciales => inicialesDe(nombre);

  String get primerNombre => nombre.trim().split(RegExp(r'\s+')).first;

  static String inicialesDe(String? nombre) {
    if (nombre == null || nombre.trim().isEmpty) return '?';
    final partes = nombre.trim().split(RegExp(r'\s+'));
    return partes.take(2).map((p) => p[0].toUpperCase()).join();
  }

  Usuario copyWith({
    String? nombre,
    String? correo,
    String? telefono,
    bool? activo,
    bool? agitacionActiva,
    int? falsasAlarmas,
    DateTime? bloqueadoHasta,
    bool quitarBloqueo = false,
  }) =>
      Usuario(
        id: id,
        nombre: nombre ?? this.nombre,
        correo: correo ?? this.correo,
        telefono: telefono ?? this.telefono,
        rol: rol,
        creadoEn: creadoEn,
        activo: activo ?? this.activo,
        agitacionActiva: agitacionActiva ?? this.agitacionActiva,
        falsasAlarmas: falsasAlarmas ?? this.falsasAlarmas,
        bloqueadoHasta: quitarBloqueo ? null : (bloqueadoHasta ?? this.bloqueadoHasta),
      );
}
