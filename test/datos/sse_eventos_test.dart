// D3 · Lectura del formato SSE. Pura: sin HTTP y sin servidor.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/sse_eventos.dart';

/// Parte un bloque de texto SSE en líneas con el MISMO LineSplitter que usa el cliente
/// sobre la red: un texto que acaba en salto de línea no deja una línea en blanco de más.
Stream<String> lineasDe(String texto) =>
    Stream.fromIterable(const LineSplitter().convert(texto));

Future<List<Map<String, Object?>>> leer(String texto) =>
    eventosSse(lineasDe(texto)).toList();

void main() {
  test('un evento con data y línea en blanco', () async {
    final eventos = await leer('data: {"data":null}\n\n');
    expect(eventos, [
      {'data': null},
    ]);
  });

  test('varios eventos seguidos llegan en orden', () async {
    final eventos = await leer(
      'data: {"data":1}\n'
      '\n'
      'data: {"data":2}\n'
      '\n',
    );
    expect(eventos.map((e) => e['data']), [1, 2]);
  });

  test('los comentarios del servidor se ignoran (el ": ping" de D26)', () async {
    final eventos = await leer(
      ': ping\n'
      '\n'
      'data: {"data":"hola"}\n'
      '\n'
      ': ping\n'
      '\n',
    );
    expect(eventos, [
      {'data': 'hola'},
    ]);
  });

  test('un envoltorio de error llega tal cual, no se traga', () async {
    final eventos = await leer('data: {"error":{"code":"UNAUTHORIZED","message":"x"}}\n\n');
    expect(eventos.single['error'], {'code': 'UNAUTHORIZED', 'message': 'x'});
  });

  test('sin el espacio de cortesía después de los dos puntos también vale', () async {
    final eventos = await leer('data:{"data":7}\n\n');
    expect(eventos.single['data'], 7);
  });

  test('un data partido en varias líneas se une con saltos de línea', () async {
    final eventos = await leer(
      'data: {"data":\n'
      'data: 42}\n'
      '\n',
    );
    expect(eventos.single['data'], 42);
  });

  test('los campos event, id y retry no estorban', () async {
    final eventos = await leer(
      'event: snapshot\n'
      'id: 7\n'
      'retry: 3000\n'
      'data: {"data":"ok"}\n'
      '\n',
    );
    expect(eventos.single['data'], 'ok');
  });

  test('un evento con JSON roto se descarta sin tumbar el canal', () async {
    final eventos = await leer(
      'data: {esto no es json\n'
      '\n'
      'data: {"data":"la siguiente sí"}\n'
      '\n',
    );
    expect(eventos, [
      {'data': 'la siguiente sí'},
    ]);
  });

  test('un data que no es objeto JSON se descarta', () async {
    final eventos = await leer(
      'data: 123\n'
      '\n'
      'data: "texto"\n'
      '\n',
    );
    expect(eventos, isEmpty);
  });

  test('un evento sin cerrar (el servidor cortó) NO se emite a medias', () async {
    final eventos = await leer('data: {"data":"incompleto"}\n');
    expect(eventos, isEmpty, reason: 'un snapshot a medias es peor que esperar la reconexión');
  });

  test('líneas en blanco de sobra no generan eventos vacíos', () async {
    final eventos = await leer('\n\n\ndata: {"data":1}\n\n\n\n');
    expect(eventos, hasLength(1));
  });

  test('un flujo vacío no emite nada y termina', () async {
    expect(await leer(''), isEmpty);
  });
}
