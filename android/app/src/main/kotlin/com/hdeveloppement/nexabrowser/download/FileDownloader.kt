package com.nexa.nexa_browser.download

import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection

/** Téléchargement d'un fichier classique, avec reprise par plage d'octets (HTTP Range). */
internal class FileDownloader(private val headers: RequestHeaders) {
    private companion object {
        const val BUFFER_SIZE = 64 * 1024
        const val HTTP_PARTIAL = 206
        const val HTTP_RANGE_NOT_SATISFIABLE = 416
    }

    /**
     * Télécharge [task] dans [partial]. Retourne normalement quand le fichier
     * est complet ou que le transfert est annulé ([TransferContext.isCancelled]).
     */
    fun download(task: DownloadTask, partial: File, context: TransferContext) {
        var existing: Long = if (partial.exists()) partial.length() else 0L
        val knownTotal: Long? = task.totalBytes

        // Déjà complet (ex. : la publication avait échoué faute de place)
        if (knownTotal != null && existing > 0 && existing == knownTotal) return
        if (knownTotal != null && existing > knownTotal) {
            partial.delete()
            existing = 0L
        }

        val extra: MutableMap<String, String> = mutableMapOf()
        if (existing > 0) {
            extra["Range"] = "bytes=$existing-"
            // Si le fichier a changé sur le serveur, il renverra le fichier entier (200)
            (task.etag ?: task.lastModified)?.let { extra["If-Range"] = it }
        }

        val connection: HttpURLConnection = HttpConnections.open(task.url) { url -> headers.forTask(task, url, extra) }
        context.attach(connection)
        try {
            val code: Int = connection.responseCode
            if (code == HTTP_RANGE_NOT_SATISFIABLE) {
                // Plage refusée : on repart de zéro au prochain essai
                partial.delete()
                throw DownloadException("Reprise refusée par le serveur, nouvel essai depuis le début", true)
            }
            if (code >= 400) throw DownloadErrors.httpStatus(code)

            val contentRange: String? = connection.getHeaderField("Content-Range")
            val resumed: Boolean = code == HTTP_PARTIAL && existing > 0 && HttpRanges.startOf(contentRange) == existing
            if (code == HTTP_PARTIAL && !resumed) {
                partial.delete()
                throw DownloadException("Réponse de reprise incohérente, nouvel essai depuis le début", true)
            }

            val start: Long = if (resumed) existing else 0L
            val length: Long = connection.contentLengthLong
            val total: Long? = when {
                resumed -> HttpRanges.totalOf(contentRange) ?: if (length >= 0) start + length else null
                length >= 0 -> length
                else -> null
            }
            context.onValidators(connection.getHeaderField("ETag"), connection.getHeaderField("Last-Modified"))
            context.onMimeType(connection.contentType)
            partial.parentFile?.let { StorageSpace.ensure(it, total?.minus(start)) }

            var received: Long = start
            context.onFileProgress(received, total)
            connection.inputStream.use { input ->
                FileOutputStream(partial, resumed).use { output ->
                    val buffer = ByteArray(BUFFER_SIZE)
                    while (true) {
                        if (context.isCancelled) return
                        val read: Int = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        received += read
                        context.onFileProgress(received, total)
                    }
                }
            }
            if (total != null && received < total) {
                throw DownloadException("Connexion interrompue", true)
            }
        } finally {
            context.attach(null)
            connection.disconnect()
        }
    }
}
