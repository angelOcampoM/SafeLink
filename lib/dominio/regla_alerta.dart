// CAPA: DOMINIO — reglas del ciclo de vida de la alerta
// 4.5 Transiciones · G-05 Aceptación · U-09 Confirmación · A-04 Escalamiento
// A-08 Falsas alarmas y bloqueo
// Quién puede hacer qué y cuándo. Cada validación devuelve el motivo o `null`.
// No hace: no guarda nada ni lee el reloj; quien pregunta le pasa `ahora`.

import 'alerta.dart';
import 'enums.dart';
import 'usuario.dart';

abstract final class ReglaAlerta {
  static const _transiciones = <EstadoAlerta, Set<EstadoAlerta>>{
    EstadoAlerta.pendienteUbicacion: {EstadoAlerta.buscando},
    EstadoAlerta.buscando: {EstadoAlerta.enAtencion, EstadoAlerta.sinRespuesta},
    EstadoAlerta.sinRespuesta: {EstadoAlerta.escalada},
    EstadoAlerta.enAtencion: {EstadoAlerta.guardiaEnLugar},
    EstadoAlerta.guardiaEnLugar: {EstadoAlerta.cerrada, EstadoAlerta.escalada},
    EstadoAlerta.escalada: {EstadoAlerta.resueltaPorAdmin},
    EstadoAlerta.cerrada: {},
    EstadoAlerta.resueltaPorAdmin: {},
  };

  static bool puedeTransicionar(EstadoAlerta desde, EstadoAlerta hacia) => _transiciones[desde]!.contains(hacia);

  /// U-03/U-04: un usuario bloqueado no puede enviar alertas.
  static String? validarCreacion(Usuario usuario, DateTime ahora) =>
      usuario.bloqueadoEn(ahora) ? 'Tu cuenta está bloqueada temporalmente' : null;

  /// G-05: solo se acepta una alerta que sigue buscando guardia.
  static String? validarAceptacion(Alerta a) =>
      a.estado == EstadoAlerta.buscando ? null : 'Otro guardia ya aceptó esta alerta';

  /// U-09: solo el usuario cierra, solo con guardia asignado y ya llegado.
  static bool puedeConfirmarUsuario(Alerta a) => a.estado == EstadoAlerta.guardiaEnLugar && a.guardiaId != null;

  static String? validarConfirmacion(Alerta a) =>
      puedeConfirmarUsuario(a) ? null : 'Solo puedes confirmar cuando el guardia ya llegó';

  /// A-04: ¿la alerta debe escalarse? [desde] es cuándo entró a su estado actual.
  /// - `buscando` sin que nadie acepte → "sin respuesta".
  /// - `guardiaEnLugar` sin que el usuario confirme → "sin confirmación".
  static RazonEscalamiento? razonParaEscalar(
    Alerta a, {
    required DateTime desde,
    required DateTime ahora,
    required Duration limite,
  }) {
    if (ahora.difference(desde) < limite) return null;
    return switch (a.estado) {
      EstadoAlerta.buscando || EstadoAlerta.sinRespuesta => RazonEscalamiento.sinRespuesta,
      EstadoAlerta.guardiaEnLugar => RazonEscalamiento.sinConfirmacion,
      _ => null,
    };
  }

  /// A-04: solo se resuelven las escaladas.
  static String? validarResolucion(Alerta a) =>
      a.estado == EstadoAlerta.escalada ? null : 'Esta alerta ya no está escalada';

  /// A-04: el admin debe dejar una nota administrativa al resolver.
  static const maxNota = 300;

  static String? nota(String? nota) {
    final texto = nota?.trim() ?? '';
    if (texto.isEmpty) return 'Escribe una nota administrativa para resolver la alerta';
    if (texto.length > maxNota) return 'La nota no puede pasar de $maxNota caracteres';
    return null;
  }

  /// A-08: aplica una resolución de falsa alarma al usuario.
  static Usuario aplicarFalsaAlarma(
    Usuario usuario, {
    required DateTime ahora,
    required int limite,
    required int diasBloqueo,
  }) {
    final cuenta = usuario.falsasAlarmas + 1;
    return usuario.copyWith(
      falsasAlarmas: cuenta,
      bloqueadoHasta: cuenta >= limite ? ahora.add(Duration(days: diasBloqueo)) : null,
    );
  }
}
