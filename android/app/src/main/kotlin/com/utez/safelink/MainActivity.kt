package com.utez.safelink

import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * U-05 · Puente entre Flutter y el servicio de accesibilidad que escucha el volumen.
 *
 * - `CANAL_METODOS`: iniciar/detener la escucha, abrir Ajustes y preguntar si el servicio
 *   está encendido.
 * - `CANAL_EVENTOS`: una emisión por cada pulsación. Al suscribirse se entrega la pulsación
 *   pendiente, si el servicio disparó con la app cerrada.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val mensajero = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(mensajero, CANAL_METODOS).setMethodCallHandler { llamada, respuesta ->
            when (llamada.method) {
                "iniciar" -> {
                    val ventana = (llamada.argument<Number>("ventanaMs"))?.toLong()
                    if (ventana != null) VolumenAccessibilityService.ventanaMs = ventana
                    VolumenAccessibilityService.escuchando = true
                    respuesta.success(null)
                }
                "detener" -> {
                    VolumenAccessibilityService.escuchando = false
                    respuesta.success(null)
                }
                "accesibilidadActiva" -> respuesta.success(servicioEnAjustes())
                "abrirAjustesAccesibilidad" -> {
                    startActivity(
                        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    respuesta.success(null)
                }
                else -> respuesta.notImplemented()
            }
        }

        EventChannel(mensajero, CANAL_EVENTOS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(argumentos: Any?, emisor: EventChannel.EventSink?) {
                    sink = emisor
                    entregarPendiente()
                }

                override fun onCancel(argumentos: Any?) {
                    sink = null
                }
            },
        )
    }

    /**
     * ¿El servicio está encendido en Ajustes? Se lee de la lista del sistema y no de
     * `estaActivo()`, porque la instancia puede no haberse creado todavía.
     */
    private fun servicioEnAjustes(): Boolean {
        val habilitados = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val nombre = "$packageName/${VolumenAccessibilityService::class.java.name}"
        return habilitados.split(':').any { it.equals(nombre, ignoreCase = true) }
    }

    /** Pulsación que ocurrió con la app cerrada: se entrega una sola vez. */
    private fun entregarPendiente() {
        val prefs = getSharedPreferences(
            VolumenAccessibilityService.PREFS,
            Context.MODE_PRIVATE,
        )
        if (!prefs.getBoolean(VolumenAccessibilityService.CLAVE_PENDIENTE, false)) return
        val timestamp = prefs.getLong(VolumenAccessibilityService.CLAVE_TIMESTAMP, 0L)
        prefs.edit().putBoolean(VolumenAccessibilityService.CLAVE_PENDIENTE, false).apply()
        // La app estaba cerrada: la regla del dominio no vio la primera pulsación, así que se
        // entregan las dos del doble clic para que la cuente completa.
        emitirEventoVolumen(mapOf("tipo" to "pulsacion", "timestamp" to timestamp))
        emitirEventoVolumen(mapOf("tipo" to "pulsacion", "timestamp" to timestamp))
    }

    companion object {
        private const val CANAL_METODOS = "com.utez.safelink/volumen"
        private const val CANAL_EVENTOS = "com.utez.safelink/volumen_eventos"

        @Volatile
        private var sink: EventChannel.EventSink? = null

        /** Manda el evento a Flutter. Devuelve false si nadie estaba escuchando. */
        fun emitirEventoVolumen(evento: Map<String, Any?>): Boolean {
            val destino = sink ?: return false
            return try {
                destino.success(evento)
                true
            } catch (e: IllegalStateException) {
                // El motor de Flutter ya se fue: se trata como "no entregado".
                false
            }
        }
    }
}
