// U-09 Confirmación · G-05 Aceptación · A-04 Escalamiento · A-08 Bloqueo · 4.5 Transiciones
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/dominio.dart';

void main() {
  final ahora = DateTime(2026, 10, 7, 18);

  Alerta alerta(EstadoAlerta s, {String? guardiaId}) =>
      Alerta(id: 'a', usuarioId: 'u', guardiaId: guardiaId, estado: s, metodo: MetodoDisparo.toque, disparadaEn: ahora);

  group('U-09 confirmación', () {
    test('solo tras la llegada del guardia', () {
      expect(ReglaAlerta.puedeConfirmarUsuario(alerta(EstadoAlerta.guardiaEnLugar, guardiaId: 'g')), isTrue);
      expect(ReglaAlerta.puedeConfirmarUsuario(alerta(EstadoAlerta.enAtencion, guardiaId: 'g')), isFalse);
      expect(ReglaAlerta.validarConfirmacion(alerta(EstadoAlerta.enAtencion, guardiaId: 'g')), isNotNull);
    });

    test('nunca sin guardia asignado', () {
      expect(ReglaAlerta.puedeConfirmarUsuario(alerta(EstadoAlerta.guardiaEnLugar)), isFalse);
    });
  });

  test('G-05 solo se acepta una alerta que sigue buscando', () {
    expect(ReglaAlerta.validarAceptacion(alerta(EstadoAlerta.buscando)), isNull);
    expect(ReglaAlerta.validarAceptacion(alerta(EstadoAlerta.enAtencion)), 'Otro guardia ya aceptó esta alerta');
  });

  group('Transiciones (4.5)', () {
    test('válidas', () {
      expect(ReglaAlerta.puedeTransicionar(EstadoAlerta.buscando, EstadoAlerta.enAtencion), isTrue);
      expect(ReglaAlerta.puedeTransicionar(EstadoAlerta.guardiaEnLugar, EstadoAlerta.escalada), isTrue);
    });

    test('inválidas', () {
      expect(ReglaAlerta.puedeTransicionar(EstadoAlerta.buscando, EstadoAlerta.cerrada), isFalse);
      expect(ReglaAlerta.puedeTransicionar(EstadoAlerta.cerrada, EstadoAlerta.buscando), isFalse);
    });
  });

  group('A-04 escalamiento', () {
    const limite = Duration(seconds: 90);

    test('antes del límite no escala', () {
      final r = ReglaAlerta.razonParaEscalar(alerta(EstadoAlerta.buscando), desde: ahora, ahora: ahora.add(const Duration(seconds: 89)), limite: limite);
      expect(r, isNull);
    });

    test('buscando sin respuesta → sin respuesta; en el lugar sin confirmar → sin confirmación', () {
      final despues = ahora.add(limite);
      expect(ReglaAlerta.razonParaEscalar(alerta(EstadoAlerta.buscando), desde: ahora, ahora: despues, limite: limite), RazonEscalamiento.sinRespuesta);
      expect(ReglaAlerta.razonParaEscalar(alerta(EstadoAlerta.guardiaEnLugar), desde: ahora, ahora: despues, limite: limite), RazonEscalamiento.sinConfirmacion);
      expect(ReglaAlerta.razonParaEscalar(alerta(EstadoAlerta.enAtencion), desde: ahora, ahora: despues, limite: limite), isNull);
    });
  });

  group('A-04 nota administrativa', () {
    test('vacía o solo espacios pide escribirla', () {
      expect(ReglaAlerta.nota(null), 'Escribe una nota administrativa para resolver la alerta');
      expect(ReglaAlerta.nota('   '), 'Escribe una nota administrativa para resolver la alerta');
    });

    test('no acepta más de ${ReglaAlerta.maxNota} caracteres', () {
      expect(ReglaAlerta.nota('a' * (ReglaAlerta.maxNota + 1)), 'La nota no puede pasar de ${ReglaAlerta.maxNota} caracteres');
    });

    test('una nota válida no tiene error', () {
      expect(ReglaAlerta.nota('Se revisó con la usuaria; sin riesgo.'), isNull);
    });
  });

  group('A-08 aplicarFalsaAlarma', () {    final usuario = Usuario(id: 'u', nombre: 'Rosa', correo: 'r@m.com', telefono: '7772233445', rol: RolUsuario.usuarioProtegido, creadoEn: ahora, falsasAlarmas: 1);

    test('debajo del límite solo incrementa', () {
      final r = ReglaAlerta.aplicarFalsaAlarma(usuario, ahora: ahora, limite: 3, diasBloqueo: 7);
      expect(r.falsasAlarmas, 2);
      expect(r.bloqueadoHasta, isNull);
    });

    test('al llegar al límite bloquea N días', () {
      final r = ReglaAlerta.aplicarFalsaAlarma(usuario.copyWith(falsasAlarmas: 2), ahora: ahora, limite: 3, diasBloqueo: 7);
      expect(r.falsasAlarmas, 3);
      expect(r.bloqueadoHasta, ahora.add(const Duration(days: 7)));
      expect(r.bloqueadoEn(ahora), isTrue);
      expect(ReglaAlerta.validarCreacion(r, ahora), isNotNull);
    });
  });
}
