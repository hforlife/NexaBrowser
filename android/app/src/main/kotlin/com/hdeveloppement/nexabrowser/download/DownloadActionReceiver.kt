package com.nexa.nexa_browser.download

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Boutons des notifications : Pause, Reprendre / Réessayer, Annuler. */
class DownloadActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_PAUSE = "com.nexa.nexa_browser.download.PAUSE"
        const val ACTION_RESUME = "com.nexa.nexa_browser.download.RESUME"
        const val ACTION_CANCEL = "com.nexa.nexa_browser.download.CANCEL"
        const val EXTRA_ID = "id"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val id: String = intent.getStringExtra(EXTRA_ID) ?: return
        // L'app peut avoir été fermée : le moteur se recharge depuis la base
        DownloadEngine.init(context.applicationContext)
        when (intent.action) {
            ACTION_PAUSE -> DownloadEngine.pause(id)
            ACTION_RESUME -> DownloadEngine.resume(id)
            ACTION_CANCEL -> DownloadEngine.remove(id, deleteFile = false)
        }
    }
}
