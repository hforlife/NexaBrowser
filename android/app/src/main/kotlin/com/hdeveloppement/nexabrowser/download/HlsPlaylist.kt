package com.nexa.nexa_browser.download

import java.net.URI

/** Variante d'une liste « maître » (une qualité). */
data class HlsVariant(
    val uri: URI,
    val bandwidth: Long,
    /** Hauteur en pixels (720 pour « 1280x720 »), null si non indiquée. */
    val height: Int?,
    /** Groupe audio séparé (attribut AUDIO), null si l'audio est dans la vidéo. */
    val audioGroup: String?,
)

/** Piste audio alternative (#EXT-X-MEDIA:TYPE=AUDIO). */
data class HlsAudioRendition(
    val groupId: String,
    /** Null : l'audio est déjà mélangé à la vidéo. */
    val uri: URI?,
    val isDefault: Boolean,
)

/** Contenu d'un fichier .m3u8 (liste maître ou liste de segments). */
data class HlsPlaylist(
    val variants: List<HlsVariant>,
    val audioRenditions: List<HlsAudioRendition>,
    val segments: List<URI>,
    /** Segment d'initialisation (#EXT-X-MAP) : présent pour les flux fMP4. */
    val initSegment: URI?,
    /** Durée totale en secondes (somme des #EXTINF). */
    val durationSeconds: Double,
    /** #EXT-X-KEY avec chiffrement : non pris en charge. */
    val isEncrypted: Boolean,
    /** #EXT-X-ENDLIST présent : vidéo complète (sinon : direct). */
    val isComplete: Boolean,
    /** #EXT-X-BYTERANGE : segments découpés dans un même fichier, non pris en charge. */
    val usesByteRanges: Boolean,
) {
    val isMaster: Boolean get() = variants.isNotEmpty()
}

/** Lecture des listes HLS et choix de la qualité. */
object HlsParser {
    /** Qualité maximale choisie automatiquement : au-delà, la consommation de données explose. */
    const val MAX_AUTO_HEIGHT = 720

    private const val HEADER = "#EXTM3U"
    private const val TAG_STREAM_INF = "#EXT-X-STREAM-INF:"
    private const val TAG_MEDIA = "#EXT-X-MEDIA:"
    private const val TAG_KEY = "#EXT-X-KEY:"
    private const val TAG_MAP = "#EXT-X-MAP:"
    private const val TAG_INF = "#EXTINF:"
    private const val TAG_BYTERANGE = "#EXT-X-BYTERANGE"
    private const val TAG_ENDLIST = "#EXT-X-ENDLIST"
    private const val METHOD_NONE = "NONE"

    /** NOM=valeur ou NOM="valeur, avec virgules". */
    private val ATTRIBUTE = Regex("""([A-Z0-9-]+)=("[^"]*"|[^,]*)""")
    private val RESOLUTION = Regex("""^(\d+)x(\d+)$""")

    /** Analyse le contenu d'un .m3u8 ; les chemins relatifs sont résolus sur [base]. */
    fun parse(content: String, base: URI): HlsPlaylist {
        val lines: List<String> = content.lines().map(String::trim).filter(String::isNotEmpty)
        if (lines.isEmpty() || !lines.first().startsWith(HEADER)) {
            throw DownloadException("Liste de lecture HLS invalide", false)
        }

        val variants = mutableListOf<HlsVariant>()
        val renditions = mutableListOf<HlsAudioRendition>()
        val segments = mutableListOf<URI>()
        var initSegment: URI? = null
        var duration = 0.0
        var encrypted = false
        var complete = false
        var byteRanges = false
        var pendingStreamInf: Map<String, String>? = null

        for (line in lines) {
            when {
                line.startsWith(TAG_STREAM_INF) ->
                    pendingStreamInf = attributes(line.removePrefix(TAG_STREAM_INF))
                line.startsWith(TAG_MEDIA) -> {
                    val attrs: Map<String, String> = attributes(line.removePrefix(TAG_MEDIA))
                    val groupId: String? = attrs["GROUP-ID"]
                    if (attrs["TYPE"] == "AUDIO" && groupId != null) {
                        renditions += HlsAudioRendition(
                            groupId = groupId,
                            uri = attrs["URI"]?.let { resolve(base, it) },
                            isDefault = attrs["DEFAULT"] == "YES",
                        )
                    }
                }
                line.startsWith(TAG_KEY) -> {
                    val method: String = attributes(line.removePrefix(TAG_KEY))["METHOD"] ?: METHOD_NONE
                    if (method != METHOD_NONE) encrypted = true
                }
                line.startsWith(TAG_MAP) -> {
                    val attrs: Map<String, String> = attributes(line.removePrefix(TAG_MAP))
                    attrs["URI"]?.let { initSegment = resolve(base, it) }
                    if (attrs.containsKey("BYTERANGE")) byteRanges = true
                }
                line.startsWith(TAG_INF) ->
                    duration += line.removePrefix(TAG_INF).substringBefore(',').toDoubleOrNull() ?: 0.0
                line.startsWith(TAG_BYTERANGE) -> byteRanges = true
                line.startsWith(TAG_ENDLIST) -> complete = true
                line.startsWith("#") -> Unit // autres balises : sans effet ici
                pendingStreamInf != null -> {
                    val attrs: Map<String, String> = pendingStreamInf
                    variants += HlsVariant(
                        uri = resolve(base, line),
                        bandwidth = attrs["BANDWIDTH"]?.toLongOrNull() ?: 0L,
                        height = attrs["RESOLUTION"]?.let { RESOLUTION.matchEntire(it) }
                            ?.groupValues?.get(2)?.toIntOrNull(),
                        audioGroup = attrs["AUDIO"],
                    )
                    pendingStreamInf = null
                }
                else -> segments += resolve(base, line)
            }
        }

        return HlsPlaylist(
            variants = variants,
            audioRenditions = renditions,
            segments = segments,
            initSegment = initSegment,
            durationSeconds = duration,
            isEncrypted = encrypted,
            isComplete = complete,
            usesByteRanges = byteRanges,
        )
    }

    /**
     * Choisit la qualité à télécharger :
     *  1. la meilleure qualité jusqu'à [maxHeight] pixels ;
     *  2. sinon (toutes plus grandes) la plus légère ;
     *  3. si aucune résolution n'est indiquée, le meilleur débit.
     */
    fun chooseVariant(variants: List<HlsVariant>, maxHeight: Int = MAX_AUTO_HEIGHT): HlsVariant? {
        if (variants.isEmpty()) return null
        val withHeight: List<HlsVariant> = variants.filter { it.height != null }
        if (withHeight.isEmpty()) return variants.maxByOrNull { it.bandwidth }
        return withHeight.filter { it.height!! <= maxHeight }.maxByOrNull { it.bandwidth }
            ?: withHeight.minByOrNull { it.bandwidth }
    }

    /** Piste audio séparée à télécharger avec [variant], ou null si l'audio est inclus. */
    fun audioFor(master: HlsPlaylist, variant: HlsVariant): HlsAudioRendition? {
        val group: String = variant.audioGroup ?: return null
        val candidates: List<HlsAudioRendition> =
            master.audioRenditions.filter { it.groupId == group && it.uri != null }
        return candidates.firstOrNull { it.isDefault } ?: candidates.firstOrNull()
    }

    private fun attributes(list: String): Map<String, String> =
        ATTRIBUTE.findAll(list).associate { match ->
            match.groupValues[1] to match.groupValues[2].removeSurrounding("\"")
        }

    /** Résout un chemin relatif ; tolère les espaces et caractères non encodés. */
    private fun resolve(base: URI, reference: String): URI = try {
        base.resolve(reference)
    } catch (e: IllegalArgumentException) {
        base.resolve(reference.replace(" ", "%20").replace("|", "%7C"))
    }
}
