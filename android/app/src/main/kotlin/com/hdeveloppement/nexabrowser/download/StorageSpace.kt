package com.nexa.nexa_browser.download

import android.os.StatFs
import java.io.File
import java.util.Locale

/** Vérification de l'espace libre avant d'écrire (téléphones à 16-32 Go souvent pleins). */
internal object StorageSpace {
    /** Marge gardée libre pour ne pas bloquer le téléphone. */
    private const val SAFETY_MARGIN_BYTES: Long = 50L * 1024 * 1024

    /** Lève une erreur si [neededBytes] (null = inconnu) ne tient pas dans [directory]. */
    fun ensure(directory: File, neededBytes: Long?) {
        if (neededBytes == null || neededBytes <= 0) return
        val available: Long = StatFs(directory.path).availableBytes
        if (available < neededBytes + SAFETY_MARGIN_BYTES) {
            throw DownloadException(
                "Espace de stockage insuffisant : ${format(neededBytes)} nécessaires, " +
                    "${format(available)} disponibles",
                false,
            )
        }
    }

    /** 845 o · 12 Ko · 3,4 Mo · 1,2 Go */
    fun format(bytes: Long): String {
        val units: Array<String> = arrayOf("o", "Ko", "Mo", "Go")
        var value: Double = bytes.toDouble()
        var unit = 0
        while (value >= 1024 && unit < units.size - 1) {
            value /= 1024
            unit++
        }
        val number: String = if (unit == 0 || value >= 100) {
            value.toLong().toString()
        } else {
            String.format(Locale.FRANCE, "%.1f", value)
        }
        return "$number ${units[unit]}"
    }
}
