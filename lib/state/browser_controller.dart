import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/constants.dart';
import '../core/url_utils.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import 'browser_tab.dart';

/// Gère la liste des onglets et la navigation de l'onglet actif.
class BrowserController extends ChangeNotifier {
  BrowserController({required DatabaseService db, required SettingsService settings})
      : _db = db,
        _settings = settings {
    newTab();
  }

  final DatabaseService _db;
  final SettingsService _settings;

  final List<BrowserTab> _tabs = [];
  int _currentIndex = 0;
  int _nextId = 1;

  List<BrowserTab> get tabs => List.unmodifiable(_tabs);
  int get currentIndex => _currentIndex;
  BrowserTab get current => _tabs[_currentIndex];
  bool get canOpenTab => _tabs.length < AppConstants.maxTabs;

  // ------------------------------------------------------------------ onglets

  /// Ouvre un onglet (vide = page d'accueil). Retourne null si la limite est atteinte.
  BrowserTab? newTab({String? url, bool isPrivate = false}) {
    if (!canOpenTab) return null;
    final BrowserTab tab = BrowserTab(id: _nextId++, isPrivate: isPrivate);
    if (url != null && url.isNotEmpty) tab.pendingUrl = url;
    _tabs.add(tab);
    _currentIndex = _tabs.length - 1;
    notifyListeners();
    return tab;
  }

  void switchTo(int index) {
    if (index < 0 || index >= _tabs.length) return;
    _currentIndex = index;
    notifyListeners();
  }

  void closeTab(BrowserTab tab) {
    final int index = _tabs.indexOf(tab);
    if (index == -1) return;
    _tabs.removeAt(index);
    // Pas de tab.dispose() ici : les widgets qui l'écoutent se détachent
    // eux-mêmes en se démontant ; l'objet est ensuite libéré par le ramasse-miettes.
    if (_tabs.isEmpty) {
      // Toujours au moins un onglet ouvert
      newTab();
      return;
    }
    if (_currentIndex >= _tabs.length) _currentIndex = _tabs.length - 1;
    if (index < _currentIndex) _currentIndex--;
    notifyListeners();
  }

  /// Ferme tous les onglets privés (ex. bouton « Fermer la navigation privée »).
  void closePrivateTabs() {
    for (final BrowserTab tab in _tabs.where((t) => t.isPrivate).toList()) {
      closeTab(tab);
    }
  }

  // --------------------------------------------------------------- navigation

  /// Ouvre ce que l'utilisateur a tapé (adresse ou recherche) dans l'onglet actif.
  void openInput(String input) {
    final String url = UrlUtils.resolveInput(input, _settings.searchEngine);
    if (url.isNotEmpty) loadUrl(url);
  }

  void loadUrl(String url, {BrowserTab? tab}) {
    final BrowserTab target = tab ?? current;
    final InAppWebViewController? controller = target.webController;
    if (target.isStartPage || controller == null) {
      // La WebView n'existe pas encore : elle chargera l'URL à sa création
      target.pendingUrl = url;
      target.updateUrl(url);
      notifyListeners();
      return;
    }
    controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> goBack() async {
    final InAppWebViewController? c = current.webController;
    if (c != null && await c.canGoBack()) {
      await c.goBack();
    } else if (!current.isStartPage) {
      goHome();
    }
  }

  Future<void> goForward() async {
    final InAppWebViewController? c = current.webController;
    if (c != null && await c.canGoForward()) await c.goForward();
  }

  void reloadOrStop() {
    final InAppWebViewController? c = current.webController;
    if (c == null) return;
    current.isLoading ? c.stopLoading() : c.reload();
  }

  /// Affiche la page d'accueil dans l'onglet actif (la WebView est détruite).
  void goHome() {
    current.webController = null;
    current.resetToStartPage();
    notifyListeners();
  }

  /// Gestion du bouton retour Android. Retourne vrai si l'événement est consommé.
  Future<bool> handleSystemBack() async {
    final InAppWebViewController? c = current.webController;
    if (c != null && await c.canGoBack()) {
      await c.goBack();
      return true;
    }
    if (!current.isStartPage) {
      goHome();
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------------- historique

  Future<void> recordVisit(BrowserTab tab) async {
    if (tab.isPrivate || tab.url.isEmpty) return;
    final Uri? uri = Uri.tryParse(tab.url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) return;
    await _db.addHistory(tab.url, tab.title);
  }
}
