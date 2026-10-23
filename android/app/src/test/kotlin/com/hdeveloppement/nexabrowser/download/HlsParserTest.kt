package com.nexa.nexa_browser.download

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.URI

class HlsParserTest {
    private val base: URI = URI("https://cdn.example.ml/live/master.m3u8")

    @Test
    fun `liste maître - variantes, résolutions et groupe audio`() {
        val playlist: HlsPlaylist = HlsParser.parse(
            """
            #EXTM3U
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="Français",DEFAULT=YES,URI="audio/fr.m3u8"
            #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS="avc1.4d401e,mp4a.40.2"
            low/index.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720,AUDIO="aud"
            hd/index.m3u8
            """.trimIndent(),
            base,
        )
        assertTrue(playlist.isMaster)
        assertEquals(2, playlist.variants.size)
        assertEquals(URI("https://cdn.example.ml/live/low/index.m3u8"), playlist.variants[0].uri)
        assertEquals(360, playlist.variants[0].height)
        // La virgule entre guillemets (CODECS) ne casse pas la lecture des attributs
        assertNull(playlist.variants[0].audioGroup)
        assertEquals("aud", playlist.variants[1].audioGroup)

        val audio: HlsAudioRendition? = HlsParser.audioFor(playlist, playlist.variants[1])
        assertEquals(URI("https://cdn.example.ml/live/audio/fr.m3u8"), audio?.uri)
        assertNull(HlsParser.audioFor(playlist, playlist.variants[0]))
    }

    @Test
    fun `liste média - segments, durée, fin`() {
        val playlist: HlsPlaylist = HlsParser.parse(
            """
            #EXTM3U
            #EXT-X-TARGETDURATION:6
            #EXTINF:6.0,
            seg0.ts
            #EXTINF:4.5,titre
            https://other.example.ml/seg1.ts
            #EXT-X-ENDLIST
            """.trimIndent(),
            base,
        )
        assertFalse(playlist.isMaster)
        assertEquals(
            listOf(URI("https://cdn.example.ml/live/seg0.ts"), URI("https://other.example.ml/seg1.ts")),
            playlist.segments,
        )
        assertEquals(10.5, playlist.durationSeconds, 0.001)
        assertTrue(playlist.isComplete)
        assertFalse(playlist.isEncrypted)
        assertNull(playlist.initSegment)
    }

    @Test
    fun `flux fMP4 - segment d'initialisation`() {
        val playlist: HlsPlaylist = HlsParser.parse(
            "#EXTM3U\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:6,\nseg1.m4s\n#EXT-X-ENDLIST\n",
            base,
        )
        assertEquals(URI("https://cdn.example.ml/live/init.mp4"), playlist.initSegment)
        assertEquals(1, playlist.segments.size)
    }

    @Test
    fun `détecte chiffrement, direct et plages d'octets`() {
        val encrypted: HlsPlaylist = HlsParser.parse(
            "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"k\"\n#EXTINF:6,\na.ts\n#EXT-X-ENDLIST\n", base,
        )
        assertTrue(encrypted.isEncrypted)

        val clear: HlsPlaylist = HlsParser.parse(
            "#EXTM3U\n#EXT-X-KEY:METHOD=NONE\n#EXTINF:6,\na.ts\n", base,
        )
        assertFalse(clear.isEncrypted)
        assertFalse(clear.isComplete) // pas de #EXT-X-ENDLIST : direct

        val ranges: HlsPlaylist = HlsParser.parse(
            "#EXTM3U\n#EXTINF:6,\n#EXT-X-BYTERANGE:1000@0\nall.ts\n#EXT-X-ENDLIST\n", base,
        )
        assertTrue(ranges.usesByteRanges)
    }

    @Test
    fun `refuse un fichier qui n'est pas une liste HLS`() {
        assertThrows(DownloadException::class.java) { HlsParser.parse("<html></html>", base) }
        assertThrows(DownloadException::class.java) { HlsParser.parse("", base) }
    }

    @Test
    fun `tolère les espaces dans les chemins`() {
        val playlist: HlsPlaylist = HlsParser.parse("#EXTM3U\n#EXTINF:6,\nmon segment.ts\n#EXT-X-ENDLIST\n", base)
        assertEquals("https://cdn.example.ml/live/mon%20segment.ts", playlist.segments.single().toString())
    }

    @Test
    fun `choix de qualité - la meilleure jusqu'à 720p`() {
        val variants: List<HlsVariant> = listOf(
            variant(400_000, 240), variant(1_200_000, 480), variant(2_500_000, 720), variant(6_000_000, 1080),
        )
        assertEquals(720, HlsParser.chooseVariant(variants)?.height)
        assertEquals(480, HlsParser.chooseVariant(variants, maxHeight = 480)?.height)
    }

    @Test
    fun `choix de qualité - la plus légère si toutes dépassent 720p`() {
        val variants: List<HlsVariant> = listOf(variant(9_000_000, 2160), variant(6_000_000, 1080))
        assertEquals(1080, HlsParser.chooseVariant(variants)?.height)
    }

    @Test
    fun `choix de qualité - meilleur débit si aucune résolution`() {
        val variants: List<HlsVariant> = listOf(variant(500_000, null), variant(900_000, null))
        assertEquals(900_000L, HlsParser.chooseVariant(variants)?.bandwidth)
        assertNull(HlsParser.chooseVariant(emptyList()))
    }

    private fun variant(bandwidth: Long, height: Int?) =
        HlsVariant(URI("https://cdn.example.ml/$bandwidth.m3u8"), bandwidth, height, null)
}
