import '../core/constants.dart';
import '../core/url_utils.dart';
import '../models/detected_media.dart';

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

  /// Classe une URL : type de média, ou null si ce n'en est pas un.
  static MediaKind? classify(String url, {String? mimeType}) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) return null;

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
}

/// Script injecté dans chaque page : signale les sources des balises
/// <video>/<audio> au code Dart, y compris celles ajoutées après coup.
/// Les sources « blob: » (lecteurs MSE) ne sont pas téléchargeables directement :
/// elles sont ignorées, le flux réel est capté côté réseau (.m3u8).
const String mediaDetectionScript = '''
(function () {
  if (window.__nexaMediaInstalled) return;
  window.__nexaMediaInstalled = true;
  var reported = {};

  function collect() {
    var found = [];
    var nodes = document.querySelectorAll('video, audio, video source, audio source');
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      var src = el.currentSrc || el.src || el.getAttribute('src');
      if (!src || src.indexOf('blob:') === 0 || src.indexOf('data:') === 0) continue;
      try { src = new URL(src, document.baseURI).href; } catch (e) { continue; }
      if (reported[src]) continue;
      reported[src] = true;
      var tag = (el.tagName === 'SOURCE' && el.parentElement) ? el.parentElement.tagName : el.tagName;
      found.push({ url: src, tag: tag.toLowerCase(), type: el.getAttribute('type') || '' });
    }
    if (found.length && window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('${AppConstants.mediaJsHandler}', found);
    }
  }

  collect();
  new MutationObserver(function () { collect(); })
    .observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['src'] });
  document.addEventListener('play', function () { collect(); }, true);
})();
''';
