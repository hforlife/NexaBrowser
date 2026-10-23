package com.nexa.nexa_browser.download

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

/**
 * Conversion sans réencodage (« remux ») de fichiers TS / fMP4 en MP4 standard,
 * avec les outils intégrés à Android : aucun poids ajouté à l'APK, rapide
 * (simple copie des échantillons) même sur un téléphone d'entrée de gamme.
 */
internal object MediaRemuxer {
    private const val MIN_BUFFER_SIZE = 2 * 1024 * 1024
    private const val MIME_VIDEO_PREFIX = "video/"
    private const val MIME_AUDIO_PREFIX = "audio/"

    /** Piste copiée : source, index dans la source, index dans le MP4. */
    private class Track(val extractor: MediaExtractor, val sourceIndex: Int, val muxerIndex: Int)

    /**
     * Copie une piste vidéo et une piste audio trouvées dans [sources] vers [output].
     * Retourne faux si annulé ; lève une exception si le format n'est pas pris en charge.
     */
    fun remuxToMp4(sources: List<File>, output: File, isCancelled: () -> Boolean): Boolean {
        output.delete()
        val extractors: MutableList<MediaExtractor> = mutableListOf()
        val muxer = MediaMuxer(output.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var started = false
        var completed = false
        try {
            val tracks: MutableList<Track> = mutableListOf()
            var hasVideo = false
            var hasAudio = false
            var bufferSize: Int = MIN_BUFFER_SIZE

            for (source in sources) {
                val extractor = MediaExtractor()
                extractors += extractor
                extractor.setDataSource(source.path)
                for (index in 0 until extractor.trackCount) {
                    val format: MediaFormat = extractor.getTrackFormat(index)
                    val mime: String = format.getString(MediaFormat.KEY_MIME) ?: continue
                    val isVideo: Boolean = mime.startsWith(MIME_VIDEO_PREFIX)
                    val isAudio: Boolean = mime.startsWith(MIME_AUDIO_PREFIX)
                    // Une seule piste de chaque type (sous-titres, métadonnées ignorés)
                    if ((isVideo && hasVideo) || (isAudio && hasAudio) || (!isVideo && !isAudio)) continue
                    if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                        bufferSize = maxOf(bufferSize, format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
                    }
                    extractor.selectTrack(index)
                    tracks += Track(extractor, index, muxer.addTrack(format))
                    hasVideo = hasVideo || isVideo
                    hasAudio = hasAudio || isAudio
                }
            }
            if (tracks.isEmpty()) throw DownloadException("Aucune piste audio ou vidéo lisible", false)

            muxer.start()
            started = true

            // Les flux TS commencent rarement à zéro : on ramène le début à 0
            val activeExtractors: List<MediaExtractor> = tracks.map { it.extractor }.distinct()
            val startTimeUs: Long = activeExtractors.map { it.sampleTime }.filter { it >= 0 }.minOrNull() ?: 0L

            val buffer: ByteBuffer = ByteBuffer.allocateDirect(bufferSize)
            val info = MediaCodec.BufferInfo()
            while (true) {
                if (isCancelled()) return false
                // Entrelacement par horodatage : évite que le MP4 garde tout en mémoire
                val extractor: MediaExtractor = activeExtractors
                    .filter { it.sampleTrackIndex >= 0 }
                    .minByOrNull { it.sampleTime } ?: break
                val track: Track = tracks.first {
                    it.extractor === extractor && it.sourceIndex == extractor.sampleTrackIndex
                }
                info.offset = 0
                info.size = extractor.readSampleData(buffer, 0)
                if (info.size >= 0) {
                    info.presentationTimeUs = maxOf(0L, extractor.sampleTime - startTimeUs)
                    info.flags = if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
                        MediaCodec.BUFFER_FLAG_KEY_FRAME
                    } else {
                        0
                    }
                    muxer.writeSampleData(track.muxerIndex, buffer, info)
                }
                extractor.advance()
            }
            // stop() finalise le MP4 ; il lève une exception si aucun échantillon n'a été écrit
            started = false
            muxer.stop()
            completed = true
            return true
        } finally {
            if (started) {
                // Arrêt anticipé (annulation ou erreur) : le fichier sera supprimé
                try {
                    muxer.stop()
                } catch (e: IllegalStateException) {
                    // Rien à finaliser
                }
            }
            muxer.release()
            extractors.forEach(MediaExtractor::release)
            if (!completed) output.delete()
        }
    }
}
