package com.nexa.nexa_browser.download

import java.io.IOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.net.ssl.SSLException

/**
 * Erreur de téléchargement, avec un message en français destiné à l'utilisateur.
 *
 * @property retryable vrai si une nouvelle tentative peut réussir (coupure réseau, serveur saturé).
 */
class DownloadException(
    message: String,
    val retryable: Boolean,
    cause: Throwable? = null,
) : Exception(message, cause)

/** Traduction des erreurs techniques en messages compréhensibles. */
internal object DownloadErrors {
    private const val NO_SPACE_ERRNO = "ENOSPC"
    private const val NO_SPACE_MESSAGE = "No space left"

    fun from(error: Throwable): DownloadException = when (error) {
        is DownloadException -> error
        is SocketTimeoutException -> DownloadException("Le réseau ne répond plus", true, error)
        is UnknownHostException ->
            DownloadException("Serveur introuvable (réseau indisponible ?)", true, error)
        is ConnectException, is NoRouteToHostException ->
            DownloadException("Connexion au serveur impossible", true, error)
        is SSLException -> DownloadException("Connexion sécurisée interrompue", true, error)
        is IOException -> if (isNoSpace(error)) {
            DownloadException("Espace de stockage insuffisant", false, error)
        } else {
            DownloadException("Connexion interrompue", true, error)
        }
        is SecurityException -> DownloadException("Accès au stockage refusé", false, error)
        else -> DownloadException("Erreur inattendue (${error.javaClass.simpleName})", false, error)
    }

    /** Erreur HTTP : seules les erreurs temporaires (408, 429, 5xx) justifient un nouvel essai. */
    fun httpStatus(code: Int): DownloadException = when {
        code == 404 || code == 410 ->
            DownloadException("Fichier introuvable sur le serveur (erreur $code)", false)
        code == 401 || code == 403 ->
            DownloadException("Accès refusé par le serveur (lien expiré ?) — erreur $code", false)
        code == 408 || code == 429 || code >= 500 ->
            DownloadException("Serveur indisponible (erreur $code)", true)
        else -> DownloadException("Erreur du serveur ($code)", false)
    }

    private fun isNoSpace(error: IOException): Boolean {
        val message: String = error.message ?: return false
        return message.contains(NO_SPACE_ERRNO) || message.contains(NO_SPACE_MESSAGE)
    }
}
