package com.nexa.nexa_browser.download

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/** Permissions utiles aux téléchargements (aucune n'est bloquante). */
object DownloadPermissions {
    const val KEY_NOTIFICATIONS = "notifications"
    const val KEY_STORAGE = "storage"

    /**
     *  - Android 13+ : afficher la progression dans les notifications ;
     *  - Android 9 et moins : écrire dans le dossier public Téléchargements.
     */
    fun required(): List<String> = buildList {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) add(Manifest.permission.POST_NOTIFICATIONS)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
    }

    fun missing(context: Context): List<String> = required().filter {
        ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED
    }

    /** État envoyé à Dart. */
    fun status(context: Context): Map<String, Boolean> = mapOf(
        KEY_NOTIFICATIONS to NotificationManagerCompat.from(context).areNotificationsEnabled(),
        KEY_STORAGE to (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
                ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
            ),
    )
}

/** Implémenté par l'activité : seule une activité peut afficher la demande de permission. */
fun interface PermissionRequester {
    fun requestDownloadPermissions(onResult: (Map<String, Boolean>) -> Unit)
}
