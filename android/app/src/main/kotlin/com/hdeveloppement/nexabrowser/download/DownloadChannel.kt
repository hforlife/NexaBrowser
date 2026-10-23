package com.nexa.nexa_browser.download

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Pont entre Dart et le moteur natif.
 *  - méthodes : list, enqueue, pause, resume, remove, open, ensurePermissions ;
 *  - événements : chaque changement de téléchargement (Map), ou {id, removed: true}.
 */
class DownloadChannel(
    messenger: BinaryMessenger,
    private val permissions: PermissionRequester,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "nexa_browser/downloads"
        const val EVENT_CHANNEL = "nexa_browser/downloads/events"
        private val ALLOWED_SCHEMES: Set<String> = setOf("http", "https")
    }

    private val methods = MethodChannel(messenger, METHOD_CHANNEL)
    private val events = EventChannel(messenger, EVENT_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    /** Les événements du moteur arrivent de threads de travail : Flutter exige le thread principal. */
    private val listener: (Map<String, Any?>) -> Unit = { event -> mainHandler.post { sink?.success(event) } }

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        DownloadEngine.removeListener(listener)
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "list" -> result.success(DownloadEngine.list())
            "enqueue" -> enqueue(call, result)
            "pause" -> withId(call, result) { DownloadEngine.pause(it); null }
            "resume" -> withId(call, result) { DownloadEngine.resume(it); null }
            "remove" -> withId(call, result) {
                DownloadEngine.remove(it, deleteFile = call.argument<Boolean>("deleteFile") ?: false)
            }
            "open" -> withId(call, result) { DownloadEngine.open(it) }
            "ensurePermissions" -> permissions.requestDownloadPermissions { status -> result.success(status) }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        DownloadEngine.addListener(listener)
    }

    override fun onCancel(arguments: Any?) {
        DownloadEngine.removeListener(listener)
        sink = null
    }

    private fun enqueue(call: MethodCall, result: MethodChannel.Result) {
        val url: String? = call.argument("url")
        val fileName: String? = call.argument("fileName")
        if (url.isNullOrBlank() || fileName.isNullOrBlank()) {
            result.error("ARGUMENTS", "url et fileName sont obligatoires", null)
            return
        }
        // blob:, data:, file:… ne peuvent pas être téléchargés par le réseau
        if (url.substringBefore(':').lowercase() !in ALLOWED_SCHEMES) {
            result.error("UNSUPPORTED_URL", "Seuls les liens http et https peuvent être téléchargés", null)
            return
        }
        result.success(
            DownloadEngine.enqueue(
                url = url,
                fileName = fileName,
                mimeType = call.argument("mimeType"),
                referer = call.argument("referer"),
                isHls = call.argument<Boolean>("isHls") ?: false,
                withCookies = call.argument<Boolean>("withCookies") ?: true,
            ),
        )
    }

    private fun withId(call: MethodCall, result: MethodChannel.Result, action: (String) -> Any?) {
        val id: String? = call.argument("id")
        if (id == null) {
            result.error("ARGUMENTS", "id obligatoire", null)
            return
        }
        result.success(action(id))
    }
}
