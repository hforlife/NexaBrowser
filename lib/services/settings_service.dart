import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

/// Réglages de l'utilisateur, persistés et observables.
class SettingsService extends ChangeNotifier {
  static const String _kSearchEngine = 'search_engine';
  static const String _kAdblock = 'adblock_enabled';
  static const String _kDataSaver = 'data_saver';
  static const String _kDesktopMode = 'desktop_mode';
  static const String _kMediaDetection = 'media_detection';

  late final SharedPreferences _prefs;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
  }

  SearchEngine get searchEngine => SearchEngine.fromName(_prefs.getString(_kSearchEngine));
  set searchEngine(SearchEngine value) => _set(() => _prefs.setString(_kSearchEngine, value.name));

  /// Bloqueur de publicités et de traqueurs.
  bool get adblockEnabled => _prefs.getBool(_kAdblock) ?? true;
  set adblockEnabled(bool value) => _set(() => _prefs.setBool(_kAdblock, value));

  /// Économie de données : les images ne sont pas chargées.
  bool get dataSaver => _prefs.getBool(_kDataSaver) ?? false;
  set dataSaver(bool value) => _set(() => _prefs.setBool(_kDataSaver, value));

  /// Afficher la version ordinateur des sites.
  bool get desktopMode => _prefs.getBool(_kDesktopMode) ?? false;
  set desktopMode(bool value) => _set(() => _prefs.setBool(_kDesktopMode, value));

  /// Détecter les vidéos présentes dans les pages.
  bool get mediaDetection => _prefs.getBool(_kMediaDetection) ?? true;
  set mediaDetection(bool value) => _set(() => _prefs.setBool(_kMediaDetection, value));

  void _set(Future<bool> Function() write) {
    write();
    notifyListeners();
  }
}
