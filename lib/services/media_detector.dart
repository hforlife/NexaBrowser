import '../core/constants.dart';
import '../core/url_utils.dart';
import '../models/detected_media.dart';

/// Média signalé par le script injecté, après validation.
class PageMediaReport {
  const PageMediaReport({required this.url, required this.kind});

  final String url;
  final MediaKind kind;
}

/// Reconnaît les URL de médias téléchargeables.
///
/// Deux sources alimentent la détection :
///  1. le réseau (requêtes interceptées / ressources chargées) ;
///  2. le script injecté [mediaDetectionScript] qui lit les balises <video>/<audio>.
class MediaDetector {
  MediaDetector._();

  static const Set<String> _videoExtensions = {'.mp4', '.webm', '.mov', '.mkv', '.m4v', '.3gp'};
  static const Set<String> _audioExtensions = {'.mp3', '.m4a', '.aac', '.ogg', '.wav', '.opus'};
  static const Set<String> _hlsExtensions = {'.m3u8'};

  /// Morceaux de flux (segments) : jamais proposés seuls.
  static const Set<String> _segmentExtensions = {'.ts', '.m4s', '.aac.ts', '.vtt'};

  /// Nombre max d'éléments acceptés par message du script (une page hostile
  /// pourrait envoyer des milliers d'entrées).
  static const int maxItemsPerReport = 20;

  /// Longueur max d'une URL signalée par une page.
  static const int maxUrlLength = 2048;

  /// Classe une URL : type de média, ou null si ce n'en est pas un.
  static MediaKind? classify(String url, {String? mimeType}) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !_isHttp(uri)) return null;

    final String mime = (mimeType ?? '').toLowerCase();
    if (mime.contains('mpegurl')) return MediaKind.stream;
    if (mime.startsWith('video/')) return MediaKind.video;
    if (mime.startsWith('audio/')) return MediaKind.audio;

    final String path = uri.path.toLowerCase();
    if (_segmentExtensions.any(path.endsWith)) return null;
    if (_hlsExtensions.any(path.endsWith)) return MediaKind.stream;
    if (_videoExtensions.any(path.endsWith)) return MediaKind.video;
    if (_audioExtensions.any(path.endsWith)) return MediaKind.audio;

    // Certains CDN mettent le type dans la requête : ?mime=video/mp4
    final String query = uri.query.toLowerCase();
    if (query.contains('mime=video') || query.contains('mime%3dvideo')) return MediaKind.video;
    return null;
  }

  /// Faux si la page ou le média appartient à un domaine interdit (YouTube).
  static bool isDownloadAllowed({required String mediaUrl, required String pageUrl}) {
    final String mediaHost = UrlUtils.hostOf(mediaUrl);
    final String pageHost = UrlUtils.hostOf(pageUrl);
    return !mediaDownloadBlockedDomains.any(
      (String d) => UrlUtils.hostMatches(mediaHost, d) || UrlUtils.hostMatches(pageHost, d),
    );
  }

  /// Valide les arguments reçus du script injecté : `[[{url, tag, type}, …]]`.
  ///
  /// N'importe quelle page (ou iframe publicitaire) peut appeler le gestionnaire :
  /// seules les URL http(s) bien formées sont gardées, en nombre limité.
  static List<PageMediaReport> parsePageReport(List<dynamic> args) {
    if (args.isEmpty || args.first is! List) return const [];
    final List<PageMediaReport> reports = [];
    for (final dynamic item in (args.first as List).take(maxItemsPerReport)) {
      if (item is! Map) continue;
      final Object? rawUrl = item['url'];
      if (rawUrl is! String || rawUrl.length > maxUrlLength) continue;
      final Uri? uri = Uri.tryParse(rawUrl);
      if (uri == null || !_isHttp(uri) || uri.host.isEmpty) continue;

      final Object? rawType = item['type'];
      final String type = rawType is String ? rawType : '';
      final MediaKind kind = classify(rawUrl, mimeType: type) ??
          (item['tag'] == 'audio' ? MediaKind.audio : MediaKind.video);
      reports.add(PageMediaReport(url: rawUrl, kind: kind));
    }
    return reports;
  }

  static bool _isHttp(Uri uri) => uri.isScheme('http') || uri.isScheme('https');
}

/// Script injecté dans chaque page : signale les sources des balises
/// <video>/<audio> au code Dart, y compris celles ajoutées après coup.
/// Les sources « blob: » (lecteurs MSE) ne sont pas téléchargeables directement :
/// elles sont ignorées, le flux réel est capté côté réseau (.m3u8).
///
/// Sur les sites très dynamiques (Facebook…), le DOM change sans arrêt :
/// l'analyse est donc regroupée au plus une fois toutes les 800 ms.
const String mediaDetectionScript = '''
(function () {
  if (window.__nexaMediaInstalled) return;
  window.__nexaMediaInstalled = true;
  var reported = {};
  var reportedCount = 0;
  var MAX_REPORTED = 100;
  var DELAY_MS = 800;
  var timer = null;

  function collect() {
    if (reportedCount >= MAX_REPORTED) return;
    var found = [];
    var nodes = document.querySelectorAll('video, audio, video source, audio source');
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      var src = el.currentSrc || el.src || el.getAttribute('src');
      if (!src || src.indexOf('blob:') === 0 || src.indexOf('data:') === 0) continue;
      try { src = new URL(src, document.baseURI).href; } catch (e) { continue; }
      if (reported[src]) continue;
      reported[src] = true;
      reportedCount++;
      var tag = (el.tagName === 'SOURCE' && el.parentElement) ? el.parentElement.tagName : el.tagName;
      found.push({ url: src, tag: tag.toLowerCase(), type: el.getAttribute('type') || '' });
    }
    if (found.length && window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('${AppConstants.mediaJsHandler}', found);
    }
  }

  // Regroupe les appels : une seule analyse par période, quel que soit le nombre de mutations
  function schedule() {
    if (timer !== null) return;
    timer = setTimeout(function () { timer = null; collect(); }, DELAY_MS);
  }

  collect();
  new MutationObserver(schedule)
    .observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['src'] });
  document.addEventListener('play', schedule, true);
})();
''';
