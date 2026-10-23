import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/constants.dart';
import '../core/url_utils.dart';
import '../models/detected_media.dart';

/// État d'un onglet. La WebView elle-même vit dans le widget [TabWebView].
class BrowserTab extends ChangeNotifier {
  BrowserTab({required this.id, this.isPrivate = false, String? initialUrl}) {
    _setUrl(initialUrl ?? '');
  }

  /// Délai de regroupement des mises à jour du compteur de pubs bloquées
  /// (des dizaines de blocages par seconde au chargement d'une page).
  static const Duration blockedNotifyDelay = Duration(milliseconds: 500);

  final int id;

  /// Navigation privée : pas d'historique ni de cache.
  /// Les cookies restent partagés avec les autres onglets (limite d'Android WebView).
  final bool isPrivate;

  InAppWebViewController? webController;

  String _url = '';
  String _site = '';
  String _title = '';
  double _progress = 0;
  bool _isLoading = false;
  bool _canGoBack = false;
  bool _canGoForward = false;
  int _blockedCount = 0;
  Timer? _blockedNotifyTimer;

  /// Médias trouvés sur la page courante (clé = URL, sans doublon).
  final LinkedHashMap<String, DetectedMedia> _media = LinkedHashMap();

  /// URL à charger dès que la WebView sera créée.
  String? pendingUrl;

  String get url => _url;

  /// Site de la page (« site.ml »), calculé une fois par changement d'URL :
  /// il est lu pour chaque requête interceptée.
  String get site => _site;

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
    _setUrl(url);
    _isLoading = true;
    if (newPage) {
      // Nouvelle page : on repart de zéro pour les compteurs
      _blockedCount = 0;
      _media.clear();
    }
    notifyListeners();
  }

  void onPageFinished(String url) {
    _setUrl(url);
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
    _setUrl(url);
    notifyListeners();
  }

  void updateNavigation({required bool canGoBack, required bool canGoForward}) {
    _canGoBack = canGoBack;
    _canGoForward = canGoForward;
    notifyListeners();
  }

  /// Une ressource a été bloquée. L'interface est prévenue au plus toutes
  /// les [blockedNotifyDelay] (y compris pour les pubs chargées après la page).
  void incrementBlocked() {
    _blockedCount++;
    _blockedNotifyTimer ??= Timer(blockedNotifyDelay, () {
      _blockedNotifyTimer = null;
      notifyListeners();
    });
  }

  /// Ajoute un média ; retourne vrai s'il est nouveau.
  /// Au-delà de [AppConstants.maxMediaPerPage], les médias sont ignorés.
  bool addMedia(DetectedMedia media) {
    if (_media.containsKey(media.url) || _media.length >= AppConstants.maxMediaPerPage) {
      return false;
    }
    _media[media.url] = media;
    notifyListeners();
    return true;
  }

  /// Retour à la page d'accueil de l'onglet.
  void resetToStartPage() {
    _setUrl('');
    _title = '';
    _progress = 0;
    _isLoading = false;
    _blockedCount = 0;
    _media.clear();
    notifyListeners();
  }

  void _setUrl(String url) {
    if (url == _url && (_site.isNotEmpty || url.isEmpty)) return;
    _url = url;
    _site = UrlUtils.siteOf(url);
  }

  @override
  void dispose() {
    _blockedNotifyTimer?.cancel();
    super.dispose();
  }
}
