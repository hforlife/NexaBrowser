package com.nexa.nexa_browser.download

import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL

/** Ouverture des connexions HTTP, avec délais adaptés aux réseaux 3G instables. */
internal object HttpConnections {
    /** Délai pour établir la connexion. */
    private const val CONNECT_TIMEOUT_MS = 20_000

    /** Délai sans recevoir aucun octet : au-delà, la connexion est jugée bloquée. */
    private const val READ_TIMEOUT_MS = 30_000

    private const val MAX_REDIRECTS = 5
    private const val BUFFER_SIZE = 64 * 1024

    /**
     * Ouvre une requête GET et suit les redirections (y compris http → https,
     * que [HttpURLConnection] ne suit pas seul). Les en-têtes sont recalculés
     * pour chaque adresse (les cookies dépendent du domaine).
     */
    fun open(url: String, headersFor: (String) -> Map<String, String>): HttpURLConnection {
        var current: String = url
        repeat(MAX_REDIRECTS + 1) {
            val connection = URL(current).openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = CONNECT_TIMEOUT_MS
            connection.readTimeout = READ_TIMEOUT_MS
            headersFor(current).forEach { (name, value) -> connection.setRequestProperty(name, value) }

            val code: Int = connection.responseCode
            val location: String? = connection.getHeaderField("Location")
            if (code !in 300..399 || code == 304 || location == null) return connection
            connection.disconnect()
            current = URI(current).resolve(location.replace(" ", "%20")).toString()
        }
        throw DownloadException("Trop de redirections", false)
    }

    /**
     * Télécharge une petite ressource (liste HLS, segment) en mémoire.
     * [isCancelled] est consulté entre chaque bloc lu.
     */
    fun readBytes(
        url: String,
        maxBytes: Long,
        headersFor: (String) -> Map<String, String>,
        onConnection: (HttpURLConnection?) -> Unit,
        isCancelled: () -> Boolean,
    ): ByteArray? {
        val connection: HttpURLConnection = open(url, headersFor)
        onConnection(connection)
        try {
            val code: Int = connection.responseCode
            if (code >= 400) throw DownloadErrors.httpStatus(code)
            val output = ByteArrayOutputStream()
            connection.inputStream.use { input ->
                val buffer = ByteArray(BUFFER_SIZE)
                while (true) {
                    if (isCancelled()) return null
                    val read: Int = input.read(buffer)
                    if (read < 0) break
                    output.write(buffer, 0, read)
                    if (output.size() > maxBytes) {
                        throw DownloadException("Segment de flux anormalement volumineux", false)
                    }
                }
            }
            return output.toByteArray()
        } finally {
            onConnection(null)
            connection.disconnect()
        }
    }
}
