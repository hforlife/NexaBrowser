package com.nexa.nexa_browser.download

/** Lecture de l'en-tête « Content-Range » (reprise des téléchargements). */
internal object HttpRanges {
    private val CONTENT_RANGE = Regex("""^bytes\s+(\d+)-(\d+)/(\d+|\*)$""", RegexOption.IGNORE_CASE)

    /** « bytes 100-199/1000 » → 100. */
    fun startOf(header: String?): Long? =
        header?.trim()?.let { CONTENT_RANGE.matchEntire(it) }?.groupValues?.get(1)?.toLongOrNull()

    /** « bytes 100-199/1000 » → 1000 ; null si la taille est inconnue (astérisque). */
    fun totalOf(header: String?): Long? =
        header?.trim()?.let { CONTENT_RANGE.matchEntire(it) }?.groupValues?.get(3)?.toLongOrNull()
}
