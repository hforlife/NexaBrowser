package com.nexa.nexa_browser.download

/** Noms de fichiers : nettoyage, extension, unicité. */
internal object FileNames {
    private const val MAX_LENGTH = 120
    private const val FALLBACK_NAME = "fichier"
    private val FORBIDDEN = Regex("""[\\/:*?"<>|\x00-\x1F]""")

    /** Remplace les caractères interdits et limite la longueur (extension conservée). */
    fun sanitize(name: String): String {
        var cleaned: String = FORBIDDEN.replace(name, "_").trim().trimStart('.')
        if (cleaned.isEmpty()) cleaned = FALLBACK_NAME
        if (cleaned.length > MAX_LENGTH) {
            val extension: String = extensionOf(cleaned)?.let { ".$it" } ?: ""
            cleaned = cleaned.substring(0, MAX_LENGTH - extension.length) + extension
        }
        return cleaned
    }

    /** « clip.ts » + « mp4 » → « clip.mp4 » ; « clip » + « mp4 » → « clip.mp4 ». */
    fun withExtension(name: String, extension: String): String {
        val dot: Int = name.lastIndexOf('.')
        val stem: String = if (dot > 0 && name.length - dot <= 6) name.substring(0, dot) else name
        return "$stem.$extension"
    }

    /** Extension en minuscules sans le point, ou null. */
    fun extensionOf(name: String): String? {
        val dot: Int = name.lastIndexOf('.')
        if (dot <= 0 || dot == name.length - 1 || name.length - dot > 6) return null
        return name.substring(dot + 1).lowercase()
    }

    /** « video.mp4 » déjà pris → « video (1).mp4 », « video (2).mp4 »… */
    fun unique(name: String, exists: (String) -> Boolean): String {
        if (!exists(name)) return name
        val extension: String? = extensionOf(name)
        val stem: String = if (extension != null) name.dropLast(extension.length + 1) else name
        var index = 1
        while (true) {
            val candidate: String = if (extension != null) "$stem ($index).$extension" else "$stem ($index)"
            if (!exists(candidate)) return candidate
            index++
        }
    }
}
