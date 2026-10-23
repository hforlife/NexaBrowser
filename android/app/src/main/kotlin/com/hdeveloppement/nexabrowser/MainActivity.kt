package com.nexa.nexa_browser

import com.nexa.nexa_browser.download.DownloadChannel
import com.nexa.nexa_browser.download.DownloadEngine
import com.nexa.nexa_browser.download.DownloadPermissions
import com.nexa.nexa_browser.download.PermissionRequester
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity(), PermissionRequester {
    private companion object {
        const val PERMISSIONS_REQUEST_CODE = 4201
    }

    private var downloadChannel: DownloadChannel? = null
    private var networkChannel: NetworkChannel? = null
    private var pendingPermissionResult: ((Map<String, Boolean>) -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DownloadEngine.init(applicationContext)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        downloadChannel = DownloadChannel(messenger, this)
        networkChannel = NetworkChannel(applicationContext, messenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        downloadChannel?.dispose()
        downloadChannel = null
        networkChannel?.dispose()
        networkChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** Demande les permissions manquantes ; répond tout de suite si rien n'est à demander. */
    override fun requestDownloadPermissions(onResult: (Map<String, Boolean>) -> Unit) {
        val missing: List<String> = DownloadPermissions.missing(this)
        if (missing.isEmpty() || pendingPermissionResult != null) {
            onResult(DownloadPermissions.status(this))
            return
        }
        pendingPermissionResult = onResult
        requestPermissions(missing.toTypedArray(), PERMISSIONS_REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSIONS_REQUEST_CODE) return
        pendingPermissionResult?.invoke(DownloadPermissions.status(this))
        pendingPermissionResult = null
    }
}
