package com.nexa.nexa_browser

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** État de la connexion pour Dart (mise à jour de la liste de blocage en Wi-Fi seulement). */
class NetworkChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "nexa_browser/network"
    }

    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() = channel.setMethodCallHandler(null)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isUnmetered" -> result.success(isUnmetered())
            else -> result.notImplemented()
        }
    }

    /**
     * Vrai si la connexion active n'est pas facturée au volume.
     * Un partage de connexion depuis un téléphone est un Wi-Fi « facturé » : faux.
     */
    private fun isUnmetered(): Boolean {
        val manager: ConnectivityManager = context.getSystemService(ConnectivityManager::class.java) ?: return false
        val capabilities: NetworkCapabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
    }
}
