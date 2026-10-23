package com.nexa.nexa_browser.download

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/**
 * Liste des téléchargements, conservée côté Android : elle reste à jour
 * même quand l'interface Flutter est fermée.
 */
internal class DownloadStore(context: Context) :
    SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    private companion object {
        const val DATABASE_NAME = "nexa_downloads.db"
        const val DATABASE_VERSION = 1
        const val TABLE = "downloads"

        const val ID = "id"
        const val URL = "url"
        const val FILE_NAME = "file_name"
        const val MIME_TYPE = "mime_type"
        const val REFERER = "referer"
        const val WITH_COOKIES = "with_cookies"
        const val IS_HLS = "is_hls"
        const val CREATED_AT = "created_at"
        const val STATUS = "status"
        const val RECEIVED_BYTES = "received_bytes"
        const val TOTAL_BYTES = "total_bytes"
        const val SEGMENTS_DONE = "segments_done"
        const val SEGMENTS_TOTAL = "segments_total"
        const val RESUME_OFFSET = "resume_offset"
        const val ETAG = "etag"
        const val LAST_MODIFIED = "last_modified"
        const val RETRY_COUNT = "retry_count"
        const val ERROR = "error"
        const val CONTENT_URI = "content_uri"
        const val FILE_PATH = "file_path"
        const val DISPLAY_PATH = "display_path"
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE $TABLE (
                $ID             TEXT PRIMARY KEY,
                $URL            TEXT NOT NULL,
                $FILE_NAME      TEXT NOT NULL,
                $MIME_TYPE      TEXT,
                $REFERER        TEXT,
                $WITH_COOKIES   INTEGER NOT NULL DEFAULT 1,
                $IS_HLS         INTEGER NOT NULL DEFAULT 0,
                $CREATED_AT     INTEGER NOT NULL,
                $STATUS         TEXT NOT NULL,
                $RECEIVED_BYTES INTEGER NOT NULL DEFAULT 0,
                $TOTAL_BYTES    INTEGER,
                $SEGMENTS_DONE  INTEGER NOT NULL DEFAULT 0,
                $SEGMENTS_TOTAL INTEGER,
                $RESUME_OFFSET  INTEGER NOT NULL DEFAULT 0,
                $ETAG           TEXT,
                $LAST_MODIFIED  TEXT,
                $RETRY_COUNT    INTEGER NOT NULL DEFAULT 0,
                $ERROR          TEXT,
                $CONTENT_URI    TEXT,
                $FILE_PATH      TEXT,
                $DISPLAY_PATH   TEXT
            )
            """.trimIndent(),
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Version 1 : rien à migrer pour l'instant
    }

    fun all(): List<DownloadTask> =
        readableDatabase.query(TABLE, null, null, null, null, null, "$CREATED_AT ASC").use { cursor ->
            buildList { while (cursor.moveToNext()) add(read(cursor)) }
        }

    fun save(task: DownloadTask) {
        writableDatabase.insertWithOnConflict(TABLE, null, write(task), SQLiteDatabase.CONFLICT_REPLACE)
    }

    fun delete(id: String) {
        writableDatabase.delete(TABLE, "$ID = ?", arrayOf(id))
    }

    private fun write(task: DownloadTask) = ContentValues().apply {
        put(ID, task.id)
        put(URL, task.url)
        put(FILE_NAME, task.fileName)
        put(MIME_TYPE, task.mimeType)
        put(REFERER, task.referer)
        put(WITH_COOKIES, if (task.withCookies) 1 else 0)
        put(IS_HLS, if (task.isHls) 1 else 0)
        put(CREATED_AT, task.createdAt)
        put(STATUS, task.status.wireName)
        put(RECEIVED_BYTES, task.receivedBytes)
        put(TOTAL_BYTES, task.totalBytes)
        put(SEGMENTS_DONE, task.segmentsDone)
        put(SEGMENTS_TOTAL, task.segmentsTotal)
        put(RESUME_OFFSET, task.resumeOffset)
        put(ETAG, task.etag)
        put(LAST_MODIFIED, task.lastModified)
        put(RETRY_COUNT, task.retryCount)
        put(ERROR, task.error)
        put(CONTENT_URI, task.contentUri)
        put(FILE_PATH, task.filePath)
        put(DISPLAY_PATH, task.displayPath)
    }

    private fun read(cursor: Cursor): DownloadTask = DownloadTask(
        id = cursor.string(ID)!!,
        url = cursor.string(URL)!!,
        fileName = cursor.string(FILE_NAME)!!,
        mimeType = cursor.string(MIME_TYPE),
        referer = cursor.string(REFERER),
        withCookies = cursor.long(WITH_COOKIES) == 1L,
        isHls = cursor.long(IS_HLS) == 1L,
        createdAt = cursor.long(CREATED_AT) ?: 0L,
        status = DownloadStatus.fromWireName(cursor.string(STATUS)),
        receivedBytes = cursor.long(RECEIVED_BYTES) ?: 0L,
        totalBytes = cursor.long(TOTAL_BYTES),
        segmentsDone = cursor.long(SEGMENTS_DONE)?.toInt() ?: 0,
        segmentsTotal = cursor.long(SEGMENTS_TOTAL)?.toInt(),
        resumeOffset = cursor.long(RESUME_OFFSET) ?: 0L,
        etag = cursor.string(ETAG),
        lastModified = cursor.string(LAST_MODIFIED),
        retryCount = cursor.long(RETRY_COUNT)?.toInt() ?: 0,
        error = cursor.string(ERROR),
        contentUri = cursor.string(CONTENT_URI),
        filePath = cursor.string(FILE_PATH),
        displayPath = cursor.string(DISPLAY_PATH),
    )

    private fun Cursor.string(column: String): String? {
        val index: Int = getColumnIndexOrThrow(column)
        return if (isNull(index)) null else getString(index)
    }

    private fun Cursor.long(column: String): Long? {
        val index: Int = getColumnIndexOrThrow(column)
        return if (isNull(index)) null else getLong(index)
    }
}
