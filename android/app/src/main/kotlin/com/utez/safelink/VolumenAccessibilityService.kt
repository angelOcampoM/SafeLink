package com.utez.safelink

import android.accessibilityservice.AccessibilityService
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.database.ContentObserver
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
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
 *  4. Con la PANTALLA APAGADA, `onKeyEvent` no recibe nada: sin ventana con foco, el sistema
 *     se queda las teclas de volumen antes de que lleguen a ningún servicio. Eso no se puede
 *     arreglar desde aquí, así que se añade un segundo camino: observar el VALOR del volumen
 *     (`ContentObserver` sobre Settings.System), que sí cambia y sí se puede escuchar con la
 *     pantalla apagada. Los dos caminos alimentan el mismo contador; el del volumen solo
 *     cuenta cuando la pantalla está apagada, para no duplicar cada pulsación.
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
        registrarObservadores()
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

        // Solo la que completa el doble clic no mueve el volumen (cambio 2 del encabezado).
        return registrarPulsacion(System.currentTimeMillis())
    }

    /**
     * Cuenta una pulsación y avisa a Flutter. Devuelve `true` si esta cerró un doble clic.
     * Lo comparten las teclas (pantalla encendida) y el observador del volumen (apagada).
     */
    private fun registrarPulsacion(ahora: Long): Boolean {
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
        return completaDoble
    }

    // ── Segundo camino: el volumen, para cuando la pantalla está apagada ──────────

    private var observadorVolumen: ContentObserver? = null
    private var volumenes = mapOf<Int, Int>()

    /**
     * Streams que hay que vigilar. Con la pantalla apagada y sin música sonando, las teclas
     * de volumen mueven el de TIMBRE, no el de música: observar solo música (como se intentó
     * primero) no detecta nada. Se miran los tres y vale con que cambie cualquiera.
     */
    private val streamsVigilados = listOf(
        AudioManager.STREAM_RING,
        AudioManager.STREAM_NOTIFICATION,
        AudioManager.STREAM_MUSIC,
    )

    private val audio: AudioManager
        get() = getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private val pantallaEncendida: Boolean
        get() = (getSystemService(Context.POWER_SERVICE) as PowerManager).isInteractive

    private fun leerVolumenes(): Map<Int, Int> =
        streamsVigilados.associateWith { audio.getStreamVolume(it) }

    private fun registrarObservadores() {
        if (observadorVolumen != null) return
        volumenes = leerVolumenes()
        val observador = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) = alCambiarElVolumen()
        }
        contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, observador)
        observadorVolumen = observador
    }

    private fun quitarObservadores() {
        observadorVolumen?.let { contentResolver.unregisterContentObserver(it) }
        observadorVolumen = null
    }

    /**
     * Cambió algún volumen. Con la pantalla encendida no se hace nada: las teclas ya llegan a
     * `onKeyEvent` y contarlas también aquí duplicaría cada pulsación.
     */
    private fun alCambiarElVolumen() {
        val actuales = leerVolumenes()
        val cambio = actuales != volumenes
        volumenes = actuales
        if (!cambio || !escuchando || pantallaEncendida) return
        registrarPulsacion(System.currentTimeMillis())
    }

    private fun marcarPendiente(pendiente: Boolean, timestamp: Long) {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(CLAVE_PENDIENTE, pendiente)
            .putLong(CLAVE_TIMESTAMP, timestamp)
            .apply()
    }

    /**
     * Trae la app al frente, también con la pantalla apagada y bloqueada.
     *
     * Un `startActivity` suelto NO basta: desde Android 10 el sistema bloquea que una app en
     * segundo plano abra pantallas, y con la pantalla apagada ni siquiera hay a dónde
     * dibujar. El camino que sí funciona es el mismo de las llamadas y las alarmas: una
     * notificación con `setFullScreenIntent`, que el sistema convierte en pantalla completa
     * cuando el teléfono está bloqueado. El `WakeLock` enciende la pantalla para que se vea.
     */
    private fun traerAppAlFrente() {
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return
        launch.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                Intent.FLAG_ACTIVITY_CLEAR_TOP,
        )
        launch.putExtra(EXTRA_ALERTA_VOLUMEN, true)

        encenderPantalla()

        val gestor = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        gestor.createNotificationChannel(
            NotificationChannel(CANAL_ALERTA, "Alerta por volumen", NotificationManager.IMPORTANCE_HIGH)
                .apply { description = "Avisa cuando se dispara una alerta con el botón de volumen." },
        )
        val pendiente = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val aviso = Notification.Builder(this, CANAL_ALERTA)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("Alerta enviada")
            .setContentText("SafeLink está registrando tu alerta.")
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setFullScreenIntent(pendiente, true)
            .build()
        gestor.notify(ID_NOTIFICACION, aviso)

        // Por si el sistema decide no honrar la pantalla completa, se intenta igual.
        runCatching { startActivity(launch) }
    }

    /** Enciende la pantalla unos segundos para que la alerta se vea. */
    private fun encenderPantalla() {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        @Suppress("DEPRECATION")
        val wakeLock = power.newWakeLock(
            PowerManager.FULL_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
            "SafeLink:alertaVolumen",
        )
        runCatching { wakeLock.acquire(SEGUNDOS_PANTALLA * 1000L) }
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
        private const val CANAL_ALERTA = "safelink_alerta_volumen"
        private const val ID_NOTIFICACION = 4701
        private const val SEGUNDOS_PANTALLA = 10

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
