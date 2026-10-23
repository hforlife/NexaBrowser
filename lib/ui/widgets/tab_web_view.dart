import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/detected_media.dart';
import '../../services/adblock/adblock_service.dart';
import '../../services/media_detector.dart';
import '../../services/settings_service.dart';
import '../../state/browser_controller.dart';
import '../../state/browser_tab.dart';
import '../../state/page_load_stats.dart';
import 'start_page.dart';

/// Demande de téléchargement venant d'une page (lien de fichier).
typedef DownloadRequestCallback = void Function({
  required String url,
  required String referer,
  String? suggestedName,
  String? mimeType,
  int? contentLength,
});

/// Contenu d'un onglet : page d'accueil ou WebView.
class TabWebView extends StatefulWidget {
  const TabWebView({super.key, required this.tab, required this.onDownloadRequested});

  final BrowserTab tab;
  final DownloadRequestCallback onDownloadRequested;

  @override
  State<TabWebView> createState() => _TabWebViewState();
}

class _TabWebViewState extends State<TabWebView> {
  static const String _desktopUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/130.0 Safari/537.36';

  /// Schémas affichés dans la WebView ; les autres sont confiés au système.
  static const Set<String> _webSchemes = {'http', 'https', 'about', 'data', 'javascript', 'blob'};

  /// Schéma interdit en navigation principale lancée par une page (hameçonnage).
  static const String _dataScheme = 'data';

  /// Mesures de chargement (debug et profile uniquement, jamais en release).
  static const bool _measure = !kReleaseMode;

  late final SettingsService _settings;
  late final AdblockService _adblock;
  late final BrowserController _browser;
  PullToRefreshController? _pullToRefresh;
  final PageLoadStats _stats = PageLoadStats();

  bool _showStartPage = true;
  bool _lastAdblock = true;
  bool _lastDesktop = false;
  bool _initialized = false;

  BrowserTab get _tab => widget.tab;

  /// Android : chaque requête passe par Dart (blocage + détection vidéo).
  /// Coûteux : l'appel est synchrone côté natif, d'où les mesures [_stats].
  bool get _interceptionEnabled =>
      Platform.isAndroid && (_settings.adblockEnabled || _settings.mediaDetection);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final AppScope scope = AppScope.of(context);
    _settings = scope.settings;
    _adblock = scope.adblock;
    _browser = scope.browser;
    _lastAdblock = _settings.adblockEnabled;
    _lastDesktop = _settings.desktopMode;
    _showStartPage = _tab.isStartPage;

    if (!_showStartPage) _pullToRefresh = _createPullToRefresh();

    _tab.addListener(_onTabChanged);
    _settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  /// On ne reconstruit que si on bascule entre accueil et WebView
  /// (reconstruire la WebView à chaque progression serait inutile).
  void _onTabChanged() {
    if (_tab.isStartPage != _showStartPage && mounted) {
      setState(() {
        _showStartPage = _tab.isStartPage;
        // Un contrôleur « tirer pour actualiser » neuf pour chaque nouvelle WebView
        _pullToRefresh = _showStartPage ? null : _createPullToRefresh();
      });
    }
  }

  PullToRefreshController _createPullToRefresh() => PullToRefreshController(
        settings: PullToRefreshSettings(color: AppTheme.brand),
        onRefresh: () async => _tab.webController?.reload(),
      );

  /// Applique les nouveaux réglages à la WebView ouverte.
  Future<void> _onSettingsChanged() async {
    final InAppWebViewController? controller = _tab.webController;
    if (controller == null) return;
    await controller.setSettings(settings: _buildSettings());

    final bool needsReload =
        _settings.desktopMode != _lastDesktop || _settings.adblockEnabled != _lastAdblock;
    _lastDesktop = _settings.desktopMode;
    _lastAdblock = _settings.adblockEnabled;
    if (needsReload) await controller.reload();
  }

  InAppWebViewSettings _buildSettings() {
    final bool adblock = _settings.adblockEnabled;
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      useShouldInterceptRequest: _interceptionEnabled,
      useOnLoadResource: _settings.mediaDetection,
      useOnDownloadStart: true,
      useShouldOverrideUrlLoading: true,
      // Navigation privée : pas de cache. On n'utilise PAS « incognito » :
      // sur Android il efface les cookies de TOUS les onglets (stockage unique).
      cacheEnabled: !_tab.isPrivate,
      // Économie de données : pas d'images
      blockNetworkImage: _settings.dataSaver,
      // Pas de lecture automatique par défaut (données mobiles chères)
      mediaPlaybackRequiresUserGesture: !_settings.allowsAutoplay,
      allowsInlineMediaPlayback: true,
      // Version ordinateur
      preferredContentMode: _settings.desktopMode
          ? UserPreferredContentMode.DESKTOP
          : UserPreferredContentMode.RECOMMENDED,
      userAgent: _settings.desktopMode ? _desktopUserAgent : '',
      // iOS : blocage natif WebKit (pas d'interception possible)
      contentBlockers: Platform.isIOS && adblock ? _adblock.iosContentBlockers() : [],
      // Fenêtres pop-up publicitaires
      supportMultipleWindows: false,
      javaScriptCanOpenWindowsAutomatically: false,
      supportZoom: true,
      builtInZoomControls: true,
      displayZoomControls: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showStartPage) {
      return StartPage(isPrivate: _tab.isPrivate, onSubmit: _browser.openInput);
    }

    return InAppWebView(
      key: ValueKey<String>('webview-${_tab.id}'),
      initialSettings: _buildSettings(),
      pullToRefreshController: _pullToRefresh,
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: mediaDetectionScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
          forMainFrameOnly: false, // lecteurs vidéo souvent dans des iframes
        ),
      ]),
      onWebViewCreated: (InAppWebViewController controller) {
        _tab.webController = controller;
        controller.addJavaScriptHandler(
          handlerName: AppConstants.mediaJsHandler,
          callback: (List<dynamic> args) {
            _onPageMedia(args);
            return null;
          },
        );
        // Charge l'URL demandée depuis la page d'accueil / la barre d'adresse
        final String? url = _tab.pendingUrl;
        _tab.pendingUrl = null;
        if (url != null) controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      },
      onLoadStart: (InAppWebViewController controller, WebUri? url) {
        if (url != null) _tab.onPageStarted(url.toString());
        if (_measure) _stats.start();
      },
      onLoadStop: (InAppWebViewController controller, WebUri? url) async {
        _pullToRefresh?.endRefreshing();
        _tab.onPageFinished(url?.toString() ?? _tab.url);
        if (_measure) {
          final String? summary =
              _stats.finish(url: _tab.url, interception: _interceptionEnabled);
          if (summary != null) debugPrint(summary);
        }
        await _refreshNavigation(controller);
        final String? cosmeticCss = _settings.adblockEnabled ? _adblock.cosmeticCssFor(_tab.site) : null;
        if (cosmeticCss != null) await controller.injectCSSCode(source: cosmeticCss);
        await _browser.recordVisit(_tab);
      },
      onReceivedError: (InAppWebViewController controller, WebResourceRequest request,
          WebResourceError error) {
        if (request.isForMainFrame ?? false) _pullToRefresh?.endRefreshing();
      },
      onProgressChanged: (InAppWebViewController controller, int progress) {
        _tab.updateProgress(progress / 100);
        if (progress == 100) _pullToRefresh?.endRefreshing();
      },
      onTitleChanged: (InAppWebViewController controller, String? title) =>
          _tab.updateTitle(title),
      onUpdateVisitedHistory: (InAppWebViewController controller, WebUri? url, bool? isReload) {
        if (url != null) _tab.updateUrl(url.toString());
        _refreshNavigation(controller);
      },
      shouldInterceptRequest: (InAppWebViewController controller, WebResourceRequest request) async {
        if (!_measure) return _interceptRequest(request);
        final Stopwatch watch = Stopwatch()..start();
        final WebResourceResponse? response = _interceptRequest(request);
        _stats.recordRequest(watch.elapsedMicroseconds, blocked: response != null);
        return response;
      },
      onLoadResource: (InAppWebViewController controller, LoadedResource resource) {
        final WebUri? url = resource.url;
        if (url != null && _settings.mediaDetection) _onNetworkMedia(url.toString());
      },
      onDownloadStartRequest: (InAppWebViewController controller, DownloadStartRequest request) {
        widget.onDownloadRequested(
          url: request.url.toString(),
          referer: _tab.url,
          suggestedName: request.suggestedFilename,
          mimeType: request.mimeType,
          contentLength: request.contentLength,
        );
      },
      shouldOverrideUrlLoading:
          (InAppWebViewController controller, NavigationAction action) async {
        final WebUri? uri = action.request.url;
        if (uri == null) return NavigationActionPolicy.ALLOW;
        // Une page ne peut pas ouvrir une URL « data: » en pleine page (hameçonnage)
        if (uri.scheme == _dataScheme && action.isForMainFrame) {
          return NavigationActionPolicy.CANCEL;
        }
        if (_webSchemes.contains(uri.scheme)) return NavigationActionPolicy.ALLOW;
        await _openExternal(uri, controller);
        return NavigationActionPolicy.CANCEL;
      },
    );
  }

  /// Décision pour une requête : réponse vide si bloquée, null sinon.
  /// Exécutée pour CHAQUE ressource : doit rester très rapide.
  WebResourceResponse? _interceptRequest(WebResourceRequest request) {
    final String url = request.url.toString();
    if (_settings.mediaDetection) _onNetworkMedia(url);

    final bool isMainFrame = request.isForMainFrame ?? false;
    // La page elle-même n'est jamais bloquée ; les exceptions par site sont
    // appliquées par le service
    if (_settings.adblockEnabled && !isMainFrame && _adblock.shouldBlock(request.url, pageSite: _tab.site)) {
      _tab.incrementBlocked();
      // Réponse vide : la publicité n'est jamais téléchargée
      return WebResourceResponse(contentType: 'text/plain', data: Uint8List(0));
    }
    return null; // requête normale
  }

  Future<void> _refreshNavigation(InAppWebViewController controller) async {
    _tab.updateNavigation(
      canGoBack: await controller.canGoBack(),
      canGoForward: await controller.canGoForward(),
    );
  }

  // ------------------------------------------------------------ détection vidéo

  void _onNetworkMedia(String url) {
    final MediaKind? kind = MediaDetector.classify(url);
    if (kind == null) return;
    _addMedia(url, kind, MediaSource.network);
  }

  /// Résultats du script JS, validés par [MediaDetector.parsePageReport].
  void _onPageMedia(List<dynamic> args) {
    if (!_settings.mediaDetection) return;
    for (final PageMediaReport report in MediaDetector.parsePageReport(args)) {
      _addMedia(report.url, report.kind, MediaSource.page);
    }
  }

  void _addMedia(String url, MediaKind kind, MediaSource source) {
    if (!MediaDetector.isDownloadAllowed(mediaUrl: url, pageUrl: _tab.url)) return;
    _tab.addMedia(DetectedMedia(
      url: url,
      kind: kind,
      source: source,
      pageUrl: _tab.url,
      pageTitle: _tab.title,
    ));
  }

  // ------------------------------------------------------------- liens externes

  /// WhatsApp, téléphone, e-mail, intent:// Android…
  Future<void> _openExternal(WebUri uri, InAppWebViewController controller) async {
    if (uri.scheme == 'intent') {
      // intent://…#Intent;…;S.browser_fallback_url=https%3A%2F%2F…;end
      final RegExpMatch? fallback =
          RegExp(r'S\.browser_fallback_url=([^;]+)').firstMatch(uri.toString());
      if (fallback != null) {
        final String url = Uri.decodeComponent(fallback.group(1)!);
        await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      }
      return;
    }
    bool opened;
    try {
      // launchUrl renvoie faux (sans exception) quand aucune app ne gère le lien
      opened = await launchUrl(Uri.parse(uri.toString()), mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Aucune application ne peut ouvrir ce lien.')),
    );
  }
}
