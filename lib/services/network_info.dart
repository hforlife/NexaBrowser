import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// État de la connexion, fourni par Android.
class NetworkInfo {
  static const MethodChannel _channel = MethodChannel('nexa_browser/network');

  /// Vrai si la connexion n'est pas facturée au volume (Wi-Fi classique, Ethernet).
  ///
  /// Plus juste que « Wi-Fi » : un partage de connexion depuis un téléphone
  /// est un Wi-Fi… qui consomme des données mobiles. Faux en cas de doute.
  Future<bool> isUnmetered() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isUnmetered') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
