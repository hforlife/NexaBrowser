package com.nexa.nexa_browser.download

import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.net.URI

/**
 * Téléchargement d'un flux HLS : chaque piste (vidéo, puis audio séparé
 * éventuel) est assemblée segment par segment dans un fichier brut.
 * La reprise se fait au segment près.
 */
internal class HlsDownloader(private val headers: RequestHeaders) {
    private companion object {
        /** Taille max acceptée pour une liste .m3u8. */
        const val MAX_PLAYLIST_BYTES: Long = 5L * 1024 * 1024

        /** Taille max acceptée pour un segment (protège la mémoire). */
        const val MAX_SEGMENT_BYTES: Long = 64L * 1024 * 1024

        /** Débit par défaut pour estimer la taille quand la liste n'en indique pas (≈ 480p). */
        const val DEFAULT_BANDWIDTH: Long = 1_200_000L
        const val BITS_PER_BYTE = 8
    }

    /** Une piste : nom (pour le fichier temporaire) et adresses à télécharger dans l'ordre. */
    private class Track(val name: String, val items: List<URI>)

    /** Plan de téléchargement résolu à partir de l'URL du flux. */
    private class Plan(val tracks: List<Track>, val isFragmentedMp4: Boolean, val estimatedBytes: Long?)

    /** Fichiers bruts obtenus, à convertir ensuite en MP4. */
    class Result(val trackFiles: List<File>, val isFragmentedMp4: Boolean)

    /** Retourne les fichiers bruts, ou null si le transfert a été annulé. */
    fun download(task: DownloadTask, workDir: File, context: TransferContext): Result? {
        val plan: Plan = resolvePlan(task, context) ?: return null
        val total: Int = plan.tracks.sumOf { it.items.size }
        val files: List<File> = plan.tracks.map { File(workDir, "${task.id}.${it.name}.part") }

        var done: Int = task.segmentsDone
        var receivedBytes: Long = task.receivedBytes
        // La liste a changé depuis le dernier essai : on recommence proprement
        if (done > 0 && task.segmentsTotal != total) {
            files.forEach(File::delete)
            done = 0
            receivedBytes = 0
        }
        done = done.coerceIn(0, total)

        // Taille estimée ×2 : fichiers bruts + fichier MP4 converti
        context.onEstimatedSize(plan.estimatedBytes)
        if (done == 0) StorageSpace.ensure(workDir, plan.estimatedBytes?.times(2))
        context.onSegmentProgress(done, total, receivedBytes, task.resumeOffset)

        var trackStart = 0
        for ((index, track) in plan.tracks.withIndex()) {
            val file: File = files[index]
            val trackEnd: Int = trackStart + track.items.size
            if (done < trackEnd) {
                var local: Int = done - trackStart
                if (local > 0 && !truncateTo(file, task.resumeOffset)) {
                    // Fichier partiel abîmé : on reprend la piste depuis le début
                    done = trackStart
                    local = 0
                }
                if (local == 0) file.delete()

                FileOutputStream(file, true).use { output ->
                    for (i in local until track.items.size) {
                        if (context.isCancelled) return null
                        val bytes: ByteArray = fetch(task, track.items[i].toString(), MAX_SEGMENT_BYTES, context)
                            ?: return null
                        output.write(bytes)
                        output.flush()
                        done++
                        receivedBytes += bytes.size
                        context.onSegmentProgress(done, total, receivedBytes, file.length())
                    }
                }
            }
            trackStart = trackEnd
        }
        return Result(files, plan.isFragmentedMp4)
    }

    /** Lit la liste (maître puis média) et choisit la qualité. Null si annulé. */
    private fun resolvePlan(task: DownloadTask, context: TransferContext): Plan? {
        val root: HlsPlaylist = fetchPlaylist(task, URI(task.url), context) ?: return null

        val video: HlsPlaylist
        var audio: HlsPlaylist? = null
        var bandwidth: Long = DEFAULT_BANDWIDTH
        if (root.isMaster) {
            val variant: HlsVariant = HlsParser.chooseVariant(root.variants)
                ?: throw DownloadException("Aucune qualité disponible dans ce flux", false)
            video = fetchPlaylist(task, variant.uri, context) ?: return null
            HlsParser.audioFor(root, variant)?.uri?.let { audioUri ->
                audio = fetchPlaylist(task, audioUri, context) ?: return null
            }
            if (variant.bandwidth > 0) bandwidth = variant.bandwidth
        } else {
            video = root
        }

        listOfNotNull(video, audio).forEach(::validate)
        val tracks: List<Track> = buildList {
            add(Track("video", listOfNotNull(video.initSegment) + video.segments))
            audio?.let { add(Track("audio", listOfNotNull(it.initSegment) + it.segments)) }
        }
        val estimated: Long? = video.durationSeconds.takeIf { it > 0 }
            ?.let { (it * bandwidth / BITS_PER_BYTE).toLong() }
        return Plan(tracks, video.initSegment != null, estimated)
    }

    private fun validate(playlist: HlsPlaylist) {
        when {
            playlist.isEncrypted ->
                throw DownloadException("Flux protégé (chiffré) : téléchargement impossible", false)
            !playlist.isComplete ->
                throw DownloadException("Vidéo en direct : téléchargement impossible", false)
            playlist.usesByteRanges ->
                throw DownloadException("Format de flux non pris en charge (plages d'octets)", false)
            playlist.segments.isEmpty() ->
                throw DownloadException("Aucun segment dans ce flux", false)
        }
    }

    private fun fetchPlaylist(task: DownloadTask, uri: URI, context: TransferContext): HlsPlaylist? {
        val bytes: ByteArray = fetch(task, uri.toString(), MAX_PLAYLIST_BYTES, context) ?: return null
        return HlsParser.parse(String(bytes, Charsets.UTF_8), uri)
    }

    private fun fetch(task: DownloadTask, url: String, maxBytes: Long, context: TransferContext): ByteArray? =
        HttpConnections.readBytes(
            url = url,
            maxBytes = maxBytes,
            headersFor = { target -> headers.forTask(task, target) },
            onConnection = context::attach,
            isCancelled = { context.isCancelled },
        )

    /** Ramène [file] à [length] octets (fin du dernier segment complet). Faux si impossible. */
    private fun truncateTo(file: File, length: Long): Boolean {
        if (!file.exists() || file.length() < length) return false
        RandomAccessFile(file, "rw").use { it.setLength(length) }
        return true
    }
}
