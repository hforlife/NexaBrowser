package com.nexa.nexa_browser.download

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/** Notifications : progression (avec Pause / Reprendre / Annuler), terminé, échec. */
internal class DownloadNotifier(private val context: Context) {
    companion object {
        /** Notification du service au premier plan (résumé des transferts). */
        const val FOREGROUND_ID = 1

        private const val CHANNEL_PROGRESS = "downloads_progress"
        private const val CHANNEL_RESULT = "downloads_result"
        private const val GROUP_ACTIVE = "com.nexa.nexa_browser.DOWNLOADS_ACTIVE"
        private const val TASK_ID_BASE = 1_000
        private const val TASK_ID_RANGE = 1_000_000
        private const val PERCENT = 100
    }

    private val manager: NotificationManagerCompat = NotificationManagerCompat.from(context)

    init {
        createChannels()
    }

    /** Résumé affiché tant que le service tourne. */
    fun foreground(active: List<DownloadTask>): Notification {
        val running: Int = active.count { it.status == DownloadStatus.RUNNING }
        val title: String = when (active.size) {
            0 -> "Téléchargements"
            1 -> active.first().fileName
            else -> "${active.size} téléchargements"
        }
        val text: String = when {
            active.isEmpty() -> "Préparation…"
            running == 0 -> statusLabel(active.first().status)
            else -> "$running en cours"
        }
        return NotificationCompat.Builder(context, CHANNEL_PROGRESS)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(openAppIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setGroup(GROUP_ACTIVE)
            .setGroupSummary(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    fun updateForeground(active: List<DownloadTask>) = notify(FOREGROUND_ID, foreground(active))

    /** Progression d'un téléchargement actif ou en pause. */
    fun progress(task: DownloadTask) {
        val builder: NotificationCompat.Builder = NotificationCompat.Builder(context, CHANNEL_PROGRESS)
            .setSmallIcon(
                if (task.status == DownloadStatus.PAUSED) android.R.drawable.stat_sys_download_done
                else android.R.drawable.stat_sys_download,
            )
            .setContentTitle(task.fileName)
            .setContentText(progressText(task))
            .setContentIntent(openAppIntent())
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setOngoing(task.status.isActive)
            .setGroup(GROUP_ACTIVE)

        val percent: Int? = percentOf(task)
        when {
            task.status == DownloadStatus.CONVERTING -> builder.setProgress(0, 0, true)
            task.status == DownloadStatus.PAUSED -> Unit // pas de barre en pause
            percent != null -> builder.setProgress(PERCENT, percent, false)
            else -> builder.setProgress(0, 0, true)
        }
        if (task.status.isPausable) {
            builder.addAction(0, "Pause", actionIntent(task, DownloadActionReceiver.ACTION_PAUSE))
        } else if (task.status == DownloadStatus.PAUSED) {
            builder.addAction(0, "Reprendre", actionIntent(task, DownloadActionReceiver.ACTION_RESUME))
        }
        if (task.status != DownloadStatus.CONVERTING) {
            builder.addAction(0, "Annuler", actionIntent(task, DownloadActionReceiver.ACTION_CANCEL))
        }
        notify(notificationId(task), builder.build())
    }

    /** Téléchargement terminé : toucher la notification ouvre le fichier. */
    fun completed(task: DownloadTask, openIntent: Intent?) {
        val content: PendingIntent? = openIntent?.let {
            PendingIntent.getActivity(
                context, requestCode(task, 0), it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        } ?: openAppIntent()
        val notification: Notification = NotificationCompat.Builder(context, CHANNEL_RESULT)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(task.fileName)
            .setContentText(task.displayPath?.let { "Enregistré dans $it" } ?: "Téléchargement terminé")
            .setContentIntent(content)
            .setAutoCancel(true)
            .build()
        notify(notificationId(task), notification)
    }

    fun failed(task: DownloadTask) {
        val notification: Notification = NotificationCompat.Builder(context, CHANNEL_RESULT)
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle(task.fileName)
            .setContentText("Échec : ${task.error ?: "erreur inconnue"}")
            .setContentIntent(openAppIntent())
            .addAction(0, "Réessayer", actionIntent(task, DownloadActionReceiver.ACTION_RESUME))
            .setAutoCancel(true)
            .build()
        notify(notificationId(task), notification)
    }

    fun cancel(task: DownloadTask) = manager.cancel(notificationId(task))

    fun cancelForeground() = manager.cancel(FOREGROUND_ID)

    // ----------------------------------------------------------------- outils

    private fun progressText(task: DownloadTask): String {
        val received: String = StorageSpace.format(task.receivedBytes)
        val amount: String = when {
            task.isHls && task.segmentsTotal != null -> "${percentOf(task)} % · $received"
            task.totalBytes != null -> "$received / ${StorageSpace.format(task.totalBytes!!)}"
            else -> received
        }
        return when (task.status) {
            DownloadStatus.RUNNING -> amount
            DownloadStatus.RETRYING, DownloadStatus.WAITING_NETWORK ->
                "${statusLabel(task.status)} · $amount"
            else -> statusLabel(task.status)
        }
    }

    private fun percentOf(task: DownloadTask): Int? {
        if (task.isHls) {
            val total: Int = task.segmentsTotal?.takeIf { it > 0 } ?: return null
            return (task.segmentsDone * PERCENT / total).coerceIn(0, PERCENT)
        }
        val total: Long = task.totalBytes?.takeIf { it > 0 } ?: return null
        return (task.receivedBytes * PERCENT / total).toInt().coerceIn(0, PERCENT)
    }

    private fun statusLabel(status: DownloadStatus): String = when (status) {
        DownloadStatus.QUEUED -> "En attente"
        DownloadStatus.RUNNING -> "En cours"
        DownloadStatus.WAITING_NETWORK -> "En attente du réseau"
        DownloadStatus.RETRYING -> "Nouvelle tentative bientôt"
        DownloadStatus.PAUSED -> "En pause"
        DownloadStatus.CONVERTING -> "Conversion en MP4…"
        DownloadStatus.COMPLETED -> "Terminé"
        DownloadStatus.FAILED -> "Échec"
    }

    private fun openAppIntent(): PendingIntent? {
        val launch: Intent = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
        launch.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
        return PendingIntent.getActivity(
            context, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun actionIntent(task: DownloadTask, action: String): PendingIntent {
        val intent: Intent = Intent(context, DownloadActionReceiver::class.java)
            .setAction(action)
            .putExtra(DownloadActionReceiver.EXTRA_ID, task.id)
        return PendingIntent.getBroadcast(
            context, requestCode(task, action.hashCode()), intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun notificationId(task: DownloadTask): Int =
        TASK_ID_BASE + Math.floorMod(task.id.hashCode(), TASK_ID_RANGE)

    private fun requestCode(task: DownloadTask, salt: Int): Int = 31 * task.id.hashCode() + salt

    /** Sans permission de notification (Android 13+), le téléchargement continue sans afficher. */
    private fun notify(id: Int, notification: Notification) {
        if (!manager.areNotificationsEnabled()) return
        try {
            manager.notify(id, notification)
        } catch (e: SecurityException) {
            // Permission retirée pendant le transfert
        }
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val system: NotificationManager = context.getSystemService(NotificationManager::class.java)
        system.createNotificationChannel(
            NotificationChannel(CHANNEL_PROGRESS, "Téléchargements en cours", NotificationManager.IMPORTANCE_LOW)
                .apply { description = "Progression, pause et reprise des téléchargements" },
        )
        system.createNotificationChannel(
            NotificationChannel(CHANNEL_RESULT, "Téléchargements terminés", NotificationManager.IMPORTANCE_DEFAULT)
                .apply { description = "Fichier prêt ou échec du téléchargement" },
        )
    }
}
