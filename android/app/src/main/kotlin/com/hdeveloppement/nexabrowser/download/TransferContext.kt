package com.nexa.nexa_browser.download

import java.net.HttpURLConnection

/**
 * Lien entre un transfert en cours (thread de travail) et le moteur :
 * annulation et remontée de la progression.
 */
internal interface TransferContext {
    /** Vrai après une pause ou une suppression : le transfert doit s'arrêter au plus vite. */
    val isCancelled: Boolean

    /** Connexion active, coupée immédiatement en cas d'annulation (null = plus de connexion). */
    fun attach(connection: HttpURLConnection?)

    /** Fichier classique : octets reçus et taille totale (null = inconnue). */
    fun onFileProgress(receivedBytes: Long, totalBytes: Long?)

    /** Validateurs HTTP du fichier (pour vérifier les reprises). */
    fun onValidators(etag: String?, lastModified: String?)

    /** Type MIME annoncé par le serveur. */
    fun onMimeType(mimeType: String?)

    /** HLS : segments terminés, octets reçus et point de reprise dans la piste en cours. */
    fun onSegmentProgress(segmentsDone: Int, segmentsTotal: Int, receivedBytes: Long, resumeOffset: Long)

    /** HLS : estimation de la taille totale (débit × durée). */
    fun onEstimatedSize(totalBytes: Long?)
}
