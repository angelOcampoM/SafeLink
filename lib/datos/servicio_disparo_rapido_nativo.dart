// CAPA: DATOS — servicio de disparo rápido real (Android)
// U-05. Implementa el mismo contrato que `ServicioDisparoRapidoSimulado`, pero las
// pulsaciones llegan del servicio de accesibilidad nativo
// (android/.../VolumenAccessibilityService.kt), así que funcionan con la pantalla
// bloqueada. Portado del repositorio que compartió el profesor.
// No hace: no decide qué es un doble clic (eso es ReglaDobleClic) ni crea alertas.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../dominio/regla_doble_clic.dart';
import 'servicio_disparo_rapido.dart';

/// Nombres de los canales; tienen que coincidir con MainActivity.kt.
const _canalMetodos = MethodChannel('com.utez.safelink/volumen');
const _canalEventos = EventChannel('com.utez.safelink/volumen_eventos');

class ServicioDisparoRapidoNativo implements ServicioDisparoRapido {
  ServicioDisparoRapidoNativo({
    MethodChannel metodos = _canalMetodos,
    EventChannel eventos = _canalEventos,
    Duration ventana = ReglaDobleClic.ventanaPorDefecto,
  })  : _metodos = metodos,
        _eventos = eventos,
        _ventana = ventana;

  final MethodChannel _metodos;
  final EventChannel _eventos;
  final Duration _ventana;

  final _control = StreamController<DateTime>.broadcast();
  StreamSubscription<dynamic>? _sub;
  bool _enEjecucion = false;

  /// ¿Esta plataforma tiene servicio nativo? Solo Android.
  static bool get disponible => !kIsWeb && Platform.isAndroid;

  @override
  Stream<DateTime> get pulsaciones => _control.stream;

  @override
  bool get enEjecucion => _enEjecucion;

  /// En Android el aviso permanente no es una notificación propia: mientras el servicio de
  /// accesibilidad está encendido, el sistema mantiene su propia señal visible y la entrada
  /// en Ajustes. Vive exactamente mientras vive el servicio, que es lo que promete el contrato.
  @override
  bool get notificacionVisible => _enEjecucion;

  @override
  Future<void> iniciar() async {
    if (_enEjecucion) return;
    try {
      await _metodos.invokeMethod<void>('iniciar', {'ventanaMs': _ventana.inMilliseconds});
    } on MissingPluginException {
      return; // plataforma sin implementación nativa: queda apagado, no revienta
    } on PlatformException {
      return;
    }
    _sub ??= _eventos.receiveBroadcastStream().listen(_alEvento, onError: (_) {});
    _enEjecucion = true;
  }

  @override
  Future<void> detener() async {
    _enEjecucion = false;
    await _sub?.cancel();
    _sub = null;
    try {
      await _metodos.invokeMethod<void>('detener');
    } on MissingPluginException {
      // Nada que apagar.
    } on PlatformException {
      // Nada que apagar.
    }
  }

  /// ¿La persona activó el servicio en Ajustes → Accesibilidad? Sin eso, el sistema no
  /// entrega las teclas y el doble clic no funciona aunque la app lo tenga encendido.
  @override
  Future<bool> listoEnElSistema() async {
    try {
      return await _metodos.invokeMethod<bool>('accesibilidadActiva') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Abre la pantalla del sistema donde se activa. Android no deja encenderlo desde la app.
  @override
  Future<void> abrirAjustesDelSistema() async {
    try {
      await _metodos.invokeMethod<void>('abrirAjustesAccesibilidad');
    } on MissingPluginException {
      // Nada que abrir.
    } on PlatformException {
      // Nada que abrir.
    }
  }

  void _alEvento(dynamic evento) {
    if (evento is! Map) return;
    if (evento['tipo'] != 'pulsacion') return;
    final ms = evento['timestamp'];
    final cuando = ms is int
        ? DateTime.fromMillisecondsSinceEpoch(ms)
        : DateTime.now();
    // Con el servicio apagado no se emite nada, igual que en el simulado.
    if (_enEjecucion && !_control.isClosed) _control.add(cuando);
  }

  Future<void> dispose() async {
    await detener();
    await _control.close();
  }
}

/// U-05 · Vibración de confirmación con el motor de Flutter: no hace falta ningún paquete.
class VibradorNativo implements Vibrador {
  const VibradorNativo();

  @override
  Future<void> vibrar() => HapticFeedback.heavyImpact();
}
