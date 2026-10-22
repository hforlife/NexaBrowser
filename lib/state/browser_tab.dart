import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/detected_media.dart';

/// État d'un onglet. La WebView elle-même vit dans le widget [TabWebView].
class BrowserTab extends ChangeNotifier {
  BrowserTab({required this.id, this.isPrivate = false, String? initialUrl})
      : _url = initialUrl ?? '';

  final int id;

  /// Navigation privée : pas d'historique, cookies et cache non conservés.
  final bool isPrivate;

  InAppWebViewController? webController;

  String _url;
  String _title = '';
  double _progress = 0;
  bool _isLoading = false;
  bool _canGoBack = false;
  bool _canGoForward = false;
  int _blockedCount = 0;

  /// Médias trouvés sur la page courante (clé = URL, sans doublon).
  final LinkedHashMap<String, DetectedMedia> _media = LinkedHashMap();

  /// URL à charger dès que la WebView sera créée.
  String? pendingUrl;

  String get url => _url;
  String get title => _title;
  double get progress => _progress;
  bool get isLoading => _isLoading;
  bool get canGoBack => _canGoBack;
  bool get canGoForward => _canGoForward;
  int get blockedCount => _blockedCount;
  List<DetectedMedia> get media => _media.values.toList(growable: false);

  /// Vrai tant qu'aucune page n'est ouverte : on affiche la page d'accueil.
  bool get isStartPage => _url.isEmpty;

  String get displayTitle {
    if (isStartPage) return isPrivate ? 'Onglet privé' : 'Nouvel onglet';
    return _title.isNotEmpty ? _title : _url;
  }

  // ---------------------------------------------------------------- mutations

  void onPageStarted(String url) {
    final bool newPage = url != _url;
    _url = url;
    _isLoading = true;
    if (newPage) {
      // Nouvelle page : on repart de zéro pour les compteurs
      _blockedCount = 0;
      _media.clear();
    }
    notifyListeners();
  }

  void onPageFinished(String url) {
    _url = url;
    _isLoading = false;
    _progress = 1;
    notifyListeners();
  }

  void updateProgress(double value) {
    _progress = value;
    notifyListeners();
  }

  void updateTitle(String? title) {
    _title = title ?? '';
    notifyListeners();
  }

  void updateUrl(String url) {
    _url = url;
    notifyListeners();
  }

  void updateNavigation({required bool canGoBack, required bool canGoForward}) {
    _canGoBack = canGoBack;
    _canGoForward = canGoForward;
    notifyListeners();
  }

  void incrementBlocked() {
    _blockedCount++;
    // Pas de notifyListeners à chaque requête : trop fréquent.
    // L'interface se met à jour avec la progression de la page.
  }

  /// Ajoute un média ; retourne vrai s'il est nouveau.
  bool addMedia(DetectedMedia media) {
    if (_media.containsKey(media.url)) return false;
    _media[media.url] = media;
    notifyListeners();
    return true;
  }

  /// Retour à la page d'accueil de l'onglet.
  void resetToStartPage() {
    _url = '';
    _title = '';
    _progress = 0;
    _isLoading = false;
    _blockedCount = 0;
    _media.clear();
    notifyListeners();
  }
}
