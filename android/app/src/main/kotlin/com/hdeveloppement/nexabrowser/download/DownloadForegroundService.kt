package com.nexa.nexa_browser.download

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Service au premier plan (type « dataSync ») : garde le processus en vie
 * tant qu'un téléchargement est actif, même après la fermeture de l'app.
 * Le travail lui-même est fait par [DownloadEngine].
 */
class DownloadForegroundService : Service() {
    companion object {
        private const val TAG = "NexaDownloads"

        @Volatile
        private var instance: DownloadForegroundService? = null

        @Volatile
        private var starting = false

        private val mainHandler = Handler(Looper.getMainLooper())

        /** Démarre le service s'il ne tourne pas déjà. */
        fun ensureStarted(context: Context) {
            if (instance != null || starting) return
            starting = true
            try {
                ContextCompat.startForegroundService(context, Intent(context, DownloadForegroundService::class.java))
            } catch (error: RuntimeException) {
                // Android 12+ : démarrage refusé si l'app est en arrière-plan.
                // Les téléchargements continuent tant que le processus vit.
                starting = false
                Log.w(TAG, "Service de téléchargement non démarré", error)
            }
        }

        /** Arrête le service s'il n'y a plus rien à faire. */
        fun stop() {
            val service: DownloadForegroundService = instance ?: return
            mainHandler.post { service.stopIfIdle() }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        DownloadEngine.init(applicationContext)
        val type: Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        } else {
            0
        }
        try {
            // Toujours appelé en premier : Android l'exige dans les secondes qui suivent le démarrage
            ServiceCompat.startForeground(this, DownloadNotifier.FOREGROUND_ID, DownloadEngine.foregroundNotification(), type)
        } catch (error: RuntimeException) {
            Log.w(TAG, "Passage au premier plan refusé", error)
            starting = false
            stopSelf()
            return START_NOT_STICKY
        }
        instance = this
        starting = false
        stopIfIdle()
        // Pas de redémarrage automatique : les transferts reprennent à la prochaine ouverture
        return START_NOT_STICKY
    }

    /** Android 15+ : un service « dataSync » est limité à 6 h par jour. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        DownloadEngine.pauseAll()
        shutdown()
    }

    override fun onDestroy() {
        instance = null
        starting = false
        super.onDestroy()
    }

    private fun stopIfIdle() {
        if (!DownloadEngine.hasActiveTasks()) shutdown()
    }

    private fun shutdown() {
        instance = null
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }
}
