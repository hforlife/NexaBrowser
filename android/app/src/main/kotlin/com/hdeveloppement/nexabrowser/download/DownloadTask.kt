package com.nexa.nexa_browser.download

/** États d'un téléchargement. [wireName] est la valeur échangée avec Dart. */
enum class DownloadStatus(val wireName: String) {
    QUEUED("queued"),
    RUNNING("running"),
    WAITING_NETWORK("waitingNetwork"),
    RETRYING("retrying"),
    PAUSED("paused"),
    CONVERTING("converting"),
    COMPLETED("completed"),
    FAILED("failed");

    /** Le téléchargement est en cours ou va reprendre seul : le service doit rester actif. */
    val isActive: Boolean
        get() = this == QUEUED || this == RUNNING || this == WAITING_NETWORK ||
            this == RETRYING || this == CONVERTING

    /** L'utilisateur peut mettre en pause (la conversion, courte, ne s'interrompt pas). */
    val isPausable: Boolean
        get() = this == QUEUED || this == RUNNING || this == WAITING_NETWORK || this == RETRYING

    companion object {
        fun fromWireName(name: String?): DownloadStatus =
            entries.firstOrNull { it.wireName == name } ?: FAILED
    }
}

/**
 * Téléchargement : fichier classique ou flux HLS.
 *
 * Les champs `var` ne sont modifiés que sous le verrou de [DownloadEngine].
 */
class DownloadTask(
    val id: String,
    val url: String,
    /** Nom du fichier final (peut changer : « .mp4 » → « .ts » si la conversion échoue). */
    var fileName: String,
    var mimeType: String?,
    /** Page d'origine, envoyée comme « Referer » (souvent exigé par les CDN). */
    val referer: String?,
    /** Joindre les cookies du site (faux pour un média signalé par un autre domaine). */
    val withCookies: Boolean,
    val isHls: Boolean,
    val createdAt: Long,
    var status: DownloadStatus = DownloadStatus.QUEUED,
    var receivedBytes: Long = 0,
    var totalBytes: Long? = null,
    /** HLS : segments terminés (segment d'initialisation compris), toutes pistes confondues. */
    var segmentsDone: Int = 0,
    var segmentsTotal: Int? = null,
    /** HLS : taille du fichier de la piste en cours à la fin du dernier segment terminé. */
    var resumeOffset: Long = 0,
    /** Validateurs HTTP : garantissent qu'une reprise concerne bien le même fichier. */
    var etag: String? = null,
    var lastModified: String? = null,
    var retryCount: Int = 0,
    var error: String? = null,
    /** Fichier publié : URI « content:// » utilisable pour l'ouvrir. */
    var contentUri: String? = null,
    /** Chemin du fichier (Android 9 et moins uniquement). */
    var filePath: String? = null,
    /** Emplacement lisible par l'utilisateur, ex. « Téléchargements/NexaBrowser/clip.mp4 ». */
    var displayPath: String? = null,
) {
    /** Copie figée, à prendre sous le verrou du moteur avant de la lire depuis un autre thread. */
    fun copy(): DownloadTask = DownloadTask(
        id = id, url = url, fileName = fileName, mimeType = mimeType, referer = referer,
        withCookies = withCookies, isHls = isHls, createdAt = createdAt, status = status,
        receivedBytes = receivedBytes, totalBytes = totalBytes, segmentsDone = segmentsDone,
        segmentsTotal = segmentsTotal, resumeOffset = resumeOffset, etag = etag,
        lastModified = lastModified, retryCount = retryCount, error = error,
        contentUri = contentUri, filePath = filePath, displayPath = displayPath,
    )

    /** Représentation envoyée à Dart (types simples uniquement). */
    fun toWireMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "url" to url,
        "fileName" to fileName,
        "mimeType" to mimeType,
        "isHls" to isHls,
        "createdAt" to createdAt,
        "status" to status.wireName,
        "receivedBytes" to receivedBytes,
        "totalBytes" to totalBytes,
        "segmentsDone" to segmentsDone,
        "segmentsTotal" to segmentsTotal,
        "retryCount" to retryCount,
        "error" to error,
        "displayPath" to displayPath,
    )
}
