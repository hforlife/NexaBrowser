package com.nexa.nexa_browser.download

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.File

/**
 * Publication des fichiers terminés dans le dossier public « Téléchargements/NexaBrowser »,
 * visible par la galerie, les lecteurs vidéo et les gestionnaires de fichiers.
 *
 *  - Android 10 et plus : MediaStore, sans aucune permission.
 *  - Android 9 et moins : écriture directe si la permission de stockage est accordée,
 *    sinon repli sur le dossier propre à l'app.
 */
internal class DownloadPublisher(private val context: Context) {
    companion object {
        const val FOLDER = "NexaBrowser"
        private const val TAG = "NexaDownloads"
        private const val DEFAULT_MIME = "application/octet-stream"
        private const val DISPLAY_DOWNLOADS = "Téléchargements"
        private const val BUFFER_SIZE = 256 * 1024
    }

    /** Fichier publié. */
    class Published(val contentUri: String, val filePath: String?, val displayPath: String, val fileName: String)

    private val fileProviderAuthority: String = "${context.packageName}.files"

    /** Déplace [source] vers les Téléchargements publics. [source] est supprimé en cas de succès. */
    fun publish(source: File, fileName: String, mimeType: String?): Published {
        val mime: String = resolveMime(fileName, mimeType)
        StorageSpace.ensure(Environment.getExternalStorageDirectory(), source.length())
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            publishWithMediaStore(source, fileName, mime)
        } else {
            publishLegacy(source, fileName, mime)
        }
    }

    /** Supprime le fichier publié. Faux s'il n'a pas pu l'être (ex. : app réinstallée entre-temps). */
    fun delete(task: DownloadTask): Boolean {
        val path: String? = task.filePath
        if (path != null) return File(path).delete()
        val uri: String = task.contentUri ?: return true
        return try {
            context.contentResolver.delete(Uri.parse(uri), null, null) > 0
        } catch (e: SecurityException) {
            Log.w(TAG, "Suppression refusée : $uri", e)
            false
        }
    }

    /** Ouvre le fichier avec l'application choisie par l'utilisateur. Faux si aucune ne convient. */
    fun open(task: DownloadTask): Boolean {
        val uri: Uri = task.contentUri?.let(Uri::parse) ?: return false
        val mime: String = context.contentResolver.getType(uri) ?: resolveMime(task.fileName, task.mimeType)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    /** Intention d'ouverture pour la notification « Terminé ». */
    fun openIntent(task: DownloadTask): Intent? {
        val uri: Uri = task.contentUri?.let(Uri::parse) ?: return null
        return Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, resolveMime(task.fileName, task.mimeType))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun publishWithMediaStore(source: File, fileName: String, mime: String): Published {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$FOLDER")
            // Invisible pour les autres apps tant que la copie n'est pas terminée
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri: Uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw DownloadException("Impossible de créer le fichier dans Téléchargements", false)
        try {
            val output = resolver.openOutputStream(uri)
                ?: throw DownloadException("Impossible d'écrire dans Téléchargements", false)
            output.use { out -> source.inputStream().use { it.copyTo(out, BUFFER_SIZE) } }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        // MediaStore renomme en cas de doublon (« clip (1).mp4 »)
        val actualName: String = queryDisplayName(uri) ?: fileName
        source.delete()
        return Published(uri.toString(), null, "$DISPLAY_DOWNLOADS/$FOLDER/$actualName", actualName)
    }

    private fun publishLegacy(source: File, fileName: String, mime: String): Published {
        val canWritePublic: Boolean = ContextCompat.checkSelfPermission(
            context, Manifest.permission.WRITE_EXTERNAL_STORAGE,
        ) == PackageManager.PERMISSION_GRANTED
        @Suppress("DEPRECATION")
        val directory: File = if (canWritePublic) {
            File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), FOLDER)
        } else {
            File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: context.filesDir, FOLDER)
        }
        directory.mkdirs()
        val target = File(directory, FileNames.unique(fileName) { File(directory, it).exists() })
        if (!source.renameTo(target)) {
            source.copyTo(target, overwrite = false, bufferSize = BUFFER_SIZE)
            source.delete()
        }
        // Rend le fichier visible dans la galerie et les lecteurs
        MediaScannerConnection.scanFile(context, arrayOf(target.path), arrayOf(mime), null)
        val uri: Uri = FileProvider.getUriForFile(context, fileProviderAuthority, target)
        val display: String = if (canWritePublic) {
            "$DISPLAY_DOWNLOADS/$FOLDER/${target.name}"
        } else {
            "Android/data/${context.packageName}/files/Download/$FOLDER/${target.name}"
        }
        return Published(uri.toString(), target.path, display, target.name)
    }

    private fun queryDisplayName(uri: Uri): String? =
        context.contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }

    private fun resolveMime(fileName: String, mimeType: String?): String {
        val declared: String? = mimeType?.substringBefore(';')?.trim()?.lowercase()
        if (!declared.isNullOrEmpty() && declared != DEFAULT_MIME) return declared
        val fromExtension: String? = FileNames.extensionOf(fileName)
            ?.let { MimeTypeMap.getSingleton().getMimeTypeFromExtension(it) }
        return fromExtension ?: DEFAULT_MIME
    }
}
