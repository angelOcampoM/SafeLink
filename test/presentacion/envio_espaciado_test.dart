// CR-F02 · CR-F05 — las posiciones salen espaciadas para no exceder el límite
// de la API (429): un envío en vuelo a la vez y, en una ráfaga, solo el último.
// Con reloj falso (fakeAsync): no dependen de la velocidad de la máquina.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/presentacion/comun/envio_espaciado.dart';

void main() {
  const intervalo = Duration(seconds: 5);

  test('el primer valor sale de inmediato', () {
    fakeAsync((async) {
      final enviados = <int>[];
      final envio = EnvioEspaciado<int>(intervalo: intervalo, enviar: (v) async => enviados.add(v));

      envio.agregar(1);
      async.flushMicrotasks();

      expect(enviados, [1]);
      envio.cerrar();
    });
  });

  test('en una ráfaga dentro del intervalo solo sale la posición más reciente', () {
    fakeAsync((async) {
      final enviados = <int>[];
      final envio = EnvioEspaciado<int>(intervalo: intervalo, enviar: (v) async => enviados.add(v));

      envio
        ..agregar(1)
        ..agregar(2)
        ..agregar(3)
        ..agregar(4);
      async.elapse(const Duration(seconds: 4));
      expect(enviados, [1], reason: 'dentro del intervalo no sale nada más');

      async.elapse(const Duration(seconds: 2));
      expect(enviados, [1, 4], reason: 'las intermedias se descartan');

      async.elapse(const Duration(seconds: 30));
      expect(enviados, [1, 4], reason: 'sin posiciones nuevas no se repite nada');
      envio.cerrar();
    });
  });

  test('nunca hay dos envíos en vuelo, aunque la red tarde más que el intervalo', () {
    fakeAsync((async) {
      var enVuelo = 0;
      var maximo = 0;
      final pendientes = <Completer<void>>[];
      final envio = EnvioEspaciado<int>(
        intervalo: intervalo,
        enviar: (v) {
          enVuelo++;
          maximo = enVuelo > maximo ? enVuelo : maximo;
          final c = Completer<void>();
          pendientes.add(c);
          return c.future.whenComplete(() => enVuelo--);
        },
      );

      envio.agregar(1);
      async.elapse(const Duration(seconds: 1));
      envio.agregar(2);
      async.elapse(const Duration(seconds: 20));
      expect(pendientes, hasLength(1), reason: 'el segundo espera a que termine el primero');

      pendientes.first.complete();
      async.elapse(const Duration(seconds: 4));
      expect(pendientes, hasLength(1), reason: 'y luego todavía respeta el intervalo');
      async.elapse(const Duration(seconds: 1));
      expect(pendientes, hasLength(2));

      pendientes.last.complete();
      async.flushMicrotasks();
      expect(maximo, 1);
      envio.cerrar();
    });
  });

  test('un error de red no detiene los envíos siguientes', () {
    fakeAsync((async) {
      final enviados = <int>[];
      final envio = EnvioEspaciado<int>(
        intervalo: intervalo,
        enviar: (v) async {
          if (v == 1) throw Exception('sin red');
          enviados.add(v);
        },
      );

      envio.agregar(1);
      async.flushMicrotasks();
      envio.agregar(2);
      async.elapse(const Duration(seconds: 6));

      expect(enviados, [2]);
      envio.cerrar();
    });
  });

  test('al cerrar se descarta lo pendiente y no se envía nada más', () {
    fakeAsync((async) {
      final enviados = <int>[];
      final envio = EnvioEspaciado<int>(intervalo: intervalo, enviar: (v) async => enviados.add(v));

      envio
        ..agregar(1)
        ..agregar(2);
      envio.cerrar();
      envio.agregar(3);
      async.elapse(const Duration(seconds: 30));

      expect(enviados, [1]);
      expect(async.pendingTimers, isEmpty, reason: 'no queda ningún temporizador vivo');
    });
  });

  test('sin intervalo cada valor sale en cuanto llega', () {
    fakeAsync((async) {
      final enviados = <int>[];
      final envio = EnvioEspaciado<int>(intervalo: Duration.zero, enviar: (v) async => enviados.add(v));

      envio
        ..agregar(1)
        ..agregar(2)
        ..agregar(3);
      async.flushMicrotasks();

      expect(enviados, [1, 2, 3]);
      envio.cerrar();
    });
  });
}
