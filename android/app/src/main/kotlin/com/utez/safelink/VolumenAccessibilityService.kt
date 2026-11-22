package com.utez.safelink

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.util.Log
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

/**
 * U-05 · Escucha las pulsaciones físicas de volumen a nivel de sistema, también con la
 * pantalla bloqueada. Basado en el servicio que nos compartió el profesor
 * (BOTON-ALERTA-PERMISOS/alerta_utez), con tres cambios:
 *
 *  1. Emite CADA pulsación hacia Flutter, no solo el doble. Quién decide qué es un doble clic
 *     es `ReglaDobleClic` en el dominio (lib/dominio/regla_doble_clic.dart), que ya está
 *     probada; si la cuenta se hiciera aquí habría dos reglas distintas que mantener.
 *  2. No se queda con las teclas de volumen. El original devolvía `true` para todas, así que
 *     mientras el servicio estaba encendido el teléfono no podía subir ni bajar el volumen.
 *     Aquí solo se consume la pulsación que COMPLETA el doble clic, para que esa no mueva el
 *     volumen; las demás siguen su camino normal.
 *  3. Nunca lee el contenido de otras apps: `onAccessibilityEvent` no hace nada.
 *
 * Requiere que la persona lo active en Ajustes → Accesibilidad → SafeLink. Android no deja
 * encenderlo desde la app (es una decisión del usuario, no un permiso que se pida).
 */
class VolumenAccessibilityService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
        instancia = this
        // El proceso pudo morir y volver (con la pantalla bloqueada pasa todo el rato): se
        // recupera lo que la persona dejó configurado en vez de arrancar apagado.
        cargarPreferencias(this)
        Log.i(TAG, "Servicio de volumen conectado (escuchando=$escuchando, ventana=${ventanaMs}ms)")
    }

    /** No leemos nada de otras apps: el servicio solo existe para las teclas. */
    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onInterrupt() {
        Log.w(TAG, "Servicio de volumen interrumpido")
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (!escuchando) return super.onKeyEvent(event)

        val esVolumen = event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
            event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN
        if (!esVolumen || event.action != KeyEvent.ACTION_DOWN) return super.onKeyEvent(event)

        val ahora = System.currentTimeMillis()
        contador = if (ahora - ultimaPulsacionMs <= ventanaMs) contador + 1 else 1
        ultimaPulsacionMs = ahora

        // Cada pulsación viaja a Flutter; la regla del dominio decide si hubo doble clic.
        val entregada = MainActivity.emitirEventoVolumen(
            mapOf("tipo" to "pulsacion", "timestamp" to ahora),
        )

        val completaDoble = contador >= 2
        if (completaDoble) {
            contador = 0
            Log.i(TAG, "Doble pulsación de volumen detectada")
            // Si Flutter no estaba escuchando (app cerrada), queda la bandera para el arranque.
            marcarPendiente(pendiente = !entregada, timestamp = ahora)
            traerAppAlFrente()
        }
        // Solo la que completa el doble clic no mueve el volumen (cambio 2 del encabezado).
        return completaDoble
    }

    override fun onDestroy() {
        if (instancia === this) instancia = null
        super.onDestroy()
    }

    private fun marcarPendiente(pendiente: Boolean, timestamp: Long) {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(CLAVE_PENDIENTE, pendiente)
            .putLong(CLAVE_TIMESTAMP, timestamp)
            .apply()
    }

    private fun traerAppAlFrente() {
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return
        launch.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                Intent.FLAG_ACTIVITY_CLEAR_TOP,
        )
        launch.putExtra(EXTRA_ALERTA_VOLUMEN, true)
        startActivity(launch)
    }

    companion object {
        private const val TAG = "SafeLinkVolumen"
        const val PREFS = "safelink_volumen"
        const val CLAVE_PENDIENTE = "alerta_pendiente"
        const val CLAVE_TIMESTAMP = "alerta_timestamp"
        const val CLAVE_ESCUCHANDO = "escuchando"
        const val CLAVE_VENTANA = "ventana_ms"
        const val EXTRA_ALERTA_VOLUMEN = "extra_alerta_volumen"
        const val VENTANA_POR_DEFECTO = 600L

        @Volatile
        var instancia: VolumenAccessibilityService? = null
            private set

        /**
         * Lo apaga `detener()` desde Flutter: el servicio sigue vivo pero deja de contar.
         *
         * NO basta con tenerlo en memoria. Android mata y reinicia el proceso de la app a
         * menudo —justo con la pantalla bloqueada, que es para lo que existe U-05—, y cuando
         * eso pasa el servicio vuelve a arrancar sin que Flutter haya llamado a `iniciar`.
         * Si el valor viviera solo aquí, el atajo se apagaría solo y en silencio: la app
         * seguiría enseñando el interruptor encendido y el botón de pánico no haría nada.
         * Por eso se guarda también en SharedPreferences y se recupera al conectar.
         */
        @Volatile
        var escuchando: Boolean = false

        /** Ventana del doble clic en milisegundos; la fija Flutter al iniciar (600 ms). */
        @Volatile
        var ventanaMs: Long = VENTANA_POR_DEFECTO

        /** Guarda lo que pidió Flutter, para que sobreviva al reinicio del proceso. */
        fun guardarPreferencias(context: Context, escuchar: Boolean, ventana: Long?) {
            escuchando = escuchar
            if (ventana != null) ventanaMs = ventana
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(CLAVE_ESCUCHANDO, escuchar)
                .putLong(CLAVE_VENTANA, ventanaMs)
                .apply()
        }

        /** Recupera lo guardado. Lo llama el servicio cada vez que se conecta. */
        fun cargarPreferencias(context: Context) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            escuchando = prefs.getBoolean(CLAVE_ESCUCHANDO, false)
            ventanaMs = prefs.getLong(CLAVE_VENTANA, VENTANA_POR_DEFECTO)
        }

        private var ultimaPulsacionMs: Long = 0L
        private var contador: Int = 0

        fun estaActivo(): Boolean = instancia != null
    }
}
