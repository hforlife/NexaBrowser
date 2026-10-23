import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

/// Réglages de l'utilisateur, persistés et observables.
class SettingsService extends ChangeNotifier {
  static const String _kSearchEngine = 'search_engine';
  static const String _kAdblock = 'adblock_enabled';
  static const String _kBlocklistAutoUpdate = 'blocklist_auto_update';
  static const String _kDataSaver = 'data_saver';
  static const String _kDesktopMode = 'desktop_mode';
  static const String _kMediaDetection = 'media_detection';
  static const String _kAutoplayVideos = 'autoplay_videos';
  static const String _kDownloadPermissionsAsked = 'download_permissions_asked';

  late final SharedPreferences _prefs;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
  }

  SearchEngine get searchEngine => SearchEngine.fromName(_prefs.getString(_kSearchEngine));
  set searchEngine(SearchEngine value) => _set(() => _prefs.setString(_kSearchEngine, value.name));

  /// Bloqueur de publicités et de traqueurs.
  bool get adblockEnabled => _prefs.getBool(_kAdblock) ?? true;
  set adblockEnabled(bool value) => _set(() => _prefs.setBool(_kAdblock, value));

  /// Mise à jour hebdomadaire de la liste de blocage, en Wi-Fi uniquement.
  bool get blocklistAutoUpdate => _prefs.getBool(_kBlocklistAutoUpdate) ?? true;
  set blocklistAutoUpdate(bool value) => _set(() => _prefs.setBool(_kBlocklistAutoUpdate, value));

  /// Économie de données : les images ne sont pas chargées, pas de lecture automatique.
  bool get dataSaver => _prefs.getBool(_kDataSaver) ?? false;
  set dataSaver(bool value) => _set(() => _prefs.setBool(_kDataSaver, value));

  /// Afficher la version ordinateur des sites.
  bool get desktopMode => _prefs.getBool(_kDesktopMode) ?? false;
  set desktopMode(bool value) => _set(() => _prefs.setBool(_kDesktopMode, value));

  /// Détecter les vidéos présentes dans les pages.
  bool get mediaDetection => _prefs.getBool(_kMediaDetection) ?? true;
  set mediaDetection(bool value) => _set(() => _prefs.setBool(_kMediaDetection, value));

  /// Lecture automatique des vidéos. Désactivée par défaut : les données
  /// mobiles sont chères, la vidéo ne démarre qu'au toucher.
  bool get autoplayVideos => _prefs.getBool(_kAutoplayVideos) ?? false;
  set autoplayVideos(bool value) => _set(() => _prefs.setBool(_kAutoplayVideos, value));

  /// Les permissions des téléchargements (notifications, stockage) ont déjà été
  /// demandées : on ne les redemande pas à chaque fichier.
  bool get downloadPermissionsAsked => _prefs.getBool(_kDownloadPermissionsAsked) ?? false;
  set downloadPermissionsAsked(bool value) =>
      _set(() => _prefs.setBool(_kDownloadPermissionsAsked, value));

  /// Vrai si les vidéos peuvent démarrer seules (jamais en économie de données).
  bool get allowsAutoplay => autoplayVideos && !dataSaver;

  void _set(Future<bool> Function() write) {
    write();
    notifyListeners();
  }
}
