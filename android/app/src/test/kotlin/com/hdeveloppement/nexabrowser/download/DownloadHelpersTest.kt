package com.nexa.nexa_browser.download

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

class DownloadHelpersTest {
    // ------------------------------------------------------------ noms de fichiers

    @Test
    fun `nettoie les noms de fichier`() {
        assertEquals("a_b_c_.mp4", FileNames.sanitize("a/b:c?.mp4"))
        assertEquals("fichier", FileNames.sanitize("   "))
        assertEquals("cache.mp4", FileNames.sanitize("..cache.mp4"))
        val long: String = FileNames.sanitize("x".repeat(300) + ".mp4")
        assertEquals(120, long.length)
        assertTrue(long.endsWith(".mp4"))
    }

    @Test
    fun `change l'extension`() {
        assertEquals("clip.mp4", FileNames.withExtension("clip.ts", "mp4"))
        assertEquals("clip.mp4", FileNames.withExtension("clip", "mp4"))
        assertEquals("Journal 20h.mp4", FileNames.withExtension("Journal 20h", "mp4"))
        assertEquals("v1.2 finale.mp4", FileNames.withExtension("v1.2 finale", "mp4"))
    }

    @Test
    fun `nom unique`() {
        val taken: Set<String> = setOf("video.mp4", "video (1).mp4", "notes")
        assertEquals("video (2).mp4", FileNames.unique("video.mp4") { it in taken })
        assertEquals("notes (1)", FileNames.unique("notes") { it in taken })
        assertEquals("libre.pdf", FileNames.unique("libre.pdf") { it in taken })
    }

    // ------------------------------------------------------------ Content-Range

    @Test
    fun `lit Content-Range`() {
        assertEquals(100L, HttpRanges.startOf("bytes 100-199/1000"))
        assertEquals(1000L, HttpRanges.totalOf("bytes 100-199/1000"))
        assertNull(HttpRanges.totalOf("bytes 100-199/*"))
        assertNull(HttpRanges.startOf("n'importe quoi"))
        assertNull(HttpRanges.startOf(null))
    }

    // ------------------------------------------------------------ erreurs

    @Test
    fun `erreurs réseau - nouvel essai`() {
        assertTrue(DownloadErrors.from(SocketTimeoutException()).retryable)
        assertTrue(DownloadErrors.from(UnknownHostException()).retryable)
        assertTrue(DownloadErrors.from(IOException("unexpected end of stream")).retryable)
    }

    @Test
    fun `stockage plein - pas de nouvel essai`() {
        val error: DownloadException = DownloadErrors.from(IOException("write failed: ENOSPC (No space left on device)"))
        assertFalse(error.retryable)
        assertEquals("Espace de stockage insuffisant", error.message)
    }

    @Test
    fun `codes HTTP`() {
        assertFalse(DownloadErrors.httpStatus(404).retryable)
        assertFalse(DownloadErrors.httpStatus(403).retryable)
        assertTrue(DownloadErrors.httpStatus(503).retryable)
        assertTrue(DownloadErrors.httpStatus(429).retryable)
    }

    @Test
    fun `une DownloadException est conservée telle quelle`() {
        val original = DownloadException("message", retryable = false)
        assertSame(original, DownloadErrors.from(original))
    }

    @Test
    fun `statuts échangés avec Dart`() {
        assertEquals(DownloadStatus.WAITING_NETWORK, DownloadStatus.fromWireName("waitingNetwork"))
        assertEquals(DownloadStatus.FAILED, DownloadStatus.fromWireName("inconnu"))
        assertTrue(DownloadStatus.CONVERTING.isActive)
        assertFalse(DownloadStatus.CONVERTING.isPausable)
        assertFalse(DownloadStatus.PAUSED.isActive)
    }
}
