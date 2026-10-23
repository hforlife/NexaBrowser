package com.nexa.nexa_browser.download

import android.content.Context
import android.util.Log
import android.webkit.CookieManager
import android.webkit.WebSettings

/** En-têtes HTTP identiques à ceux du navigateur : beaucoup de CDN les exigent. */
internal class RequestHeaders(context: Context) {
    private companion object {
        const val TAG = "NexaDownloads"
        const val FALLBACK_USER_AGENT =
            "Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) " +
                "Chrome/130.0 Mobile Safari/537.36"
    }

    /**
     * User-Agent de la WebView du téléphone (même identité que la page).
     * Calculé à la première requête, sur un thread de travail : le chargement
     * de la WebView ne doit pas ralentir le démarrage.
     */
    private val userAgent: String by lazy {
        try {
            WebSettings.getDefaultUserAgent(context)
        } catch (e: RuntimeException) {
            // WebView absente ou en cours de mise à jour
            FALLBACK_USER_AGENT
        }
    }

    /**
     * En-têtes pour [url] dans le cadre de [task].
     * « Accept-Encoding: identity » : sans compression, la taille annoncée et
     * les reprises par plage d'octets restent exactes.
     */
    fun forTask(task: DownloadTask, url: String, extra: Map<String, String> = emptyMap()): Map<String, String> {
        val headers: MutableMap<String, String> = mutableMapOf(
            "User-Agent" to userAgent,
            "Accept-Encoding" to "identity",
            "Accept" to "*/*",
        )
        task.referer?.let { headers["Referer"] = it }
        if (task.withCookies) cookiesFor(url)?.let { headers["Cookie"] = it }
        headers.putAll(extra)
        return headers
    }

    /** Cookies de la WebView (connexion au site), y compris ceux marqués HttpOnly. */
    private fun cookiesFor(url: String): String? = try {
        CookieManager.getInstance().getCookie(url)?.takeIf { it.isNotBlank() }
    } catch (e: RuntimeException) {
        Log.w(TAG, "Cookies indisponibles", e)
        null
    }
}
