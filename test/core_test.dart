// Tests des briques sans interface (URL, bloqueur, détection vidéo, HLS) : « flutter test ».
import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_browser/core/constants.dart';
import 'package:nexa_browser/core/formatters.dart';
import 'package:nexa_browser/core/url_utils.dart';
import 'package:nexa_browser/models/detected_media.dart';
import 'package:nexa_browser/services/adblock_service.dart';
import 'package:nexa_browser/services/hls_parser.dart';
import 'package:nexa_browser/services/media_detector.dart';

void main() {
  group('UrlUtils.resolveInput', () {
    test('ajoute https aux domaines', () {
      expect(UrlUtils.resolveInput('google.com', SearchEngine.google), 'https://google.com');
      expect(UrlUtils.resolveInput('fr.wikipedia.org/wiki/Mali', SearchEngine.google),
          'https://fr.wikipedia.org/wiki/Mali');
    });

    test('garde les URL complètes', () {
      expect(UrlUtils.resolveInput('http://exemple.ml', SearchEngine.google), 'http://exemple.ml');
    });

    test('transforme le texte en recherche', () {
      expect(UrlUtils.resolveInput('recette tô', SearchEngine.duckDuckGo),
          'https://duckduckgo.com/?q=recette+t%C3%B4');
    });

    test('adresse IP et port', () {
      expect(UrlUtils.resolveInput('192.168.1.1:8080', SearchEngine.google),
          'https://192.168.1.1:8080');
    });
  });

  group('UrlUtils fichiers', () {
    test('nettoie les noms de fichier', () {
      expect(UrlUtils.sanitizeFileName('a/b:c?.mp4'), 'a_b_c_.mp4');
      expect(UrlUtils.sanitizeFileName('   '), 'fichier');
    });

    test('nom depuis une URL', () {
      expect(UrlUtils.fileNameFromUrl('https://cdn.x.com/v/clip%20final.mp4?t=1'), 'clip final.mp4');
    });
  });

  group('AdblockService', () {
    final Set<String> domains = AdblockService.parseHosts('''
# commentaire
0.0.0.0 ads.example.com
127.0.0.1 localhost
doubleclick.net   # inline
0.0.0.0 0.0.0.0
''');

    test('lit le format hosts', () {
      expect(domains, {'ads.example.com', 'doubleclick.net'});
    });

    test('bloque les sous-domaines', () {
      expect(AdblockService.isHostInSet('stats.g.doubleclick.net', domains), isTrue);
      expect(AdblockService.isHostInSet('ads.example.com', domains), isTrue);
    });

    test('ne bloque pas les sites légitimes', () {
      expect(AdblockService.isHostInSet('example.com', domains), isFalse);
      expect(AdblockService.isHostInSet('notdoubleclick.net', domains), isFalse);
      expect(AdblockService.isHostInSet('net', domains), isFalse);
    });
  });

  group('MediaDetector', () {
    test('reconnaît vidéos, audio et HLS', () {
      expect(MediaDetector.classify('https://cdn.com/a/video.mp4?x=1'), MediaKind.video);
      expect(MediaDetector.classify('https://cdn.com/song.mp3'), MediaKind.audio);
      expect(MediaDetector.classify('https://cdn.com/live/master.m3u8'), MediaKind.stream);
      expect(MediaDetector.classify('https://cdn.com/x', mimeType: 'video/webm'), MediaKind.video);
    });

    test('ignore les segments et les pages', () {
      expect(MediaDetector.classify('https://cdn.com/seg_001.ts'), isNull);
      expect(MediaDetector.classify('https://cdn.com/index.html'), isNull);
      expect(MediaDetector.classify('blob:https://site.com/123'), isNull);
    });

    test('refuse YouTube', () {
      expect(
        MediaDetector.isDownloadAllowed(
          mediaUrl: 'https://rr1.googlevideo.com/videoplayback',
          pageUrl: 'https://m.youtube.com/watch?v=1',
        ),
        isFalse,
      );
      expect(
        MediaDetector.isDownloadAllowed(
          mediaUrl: 'https://cdn.site.com/v.mp4',
          pageUrl: 'https://site.com/page',
        ),
        isTrue,
      );
    });
  });

  group('HlsParser', () {
    final Uri base = Uri.parse('https://cdn.com/live/master.m3u8');

    test('liste maître : choisit la meilleure qualité', () {
      final HlsPlaylist playlist = HlsParser.parse('''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
low/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720
hd/index.m3u8
''', base);
      expect(playlist.isMaster, isTrue);
      expect(playlist.bestVariant!.uri.toString(), 'https://cdn.com/live/hd/index.m3u8');
      expect(playlist.bestVariant!.resolution, '1280x720');
    });

    test('liste média : segments résolus', () {
      final HlsPlaylist playlist = HlsParser.parse('''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXTINF:6.0,
seg0.ts
#EXTINF:6.0,
https://other.com/seg1.ts
#EXT-X-ENDLIST
''', base);
      expect(playlist.isMaster, isFalse);
      expect(playlist.segments.map((u) => u.toString()),
          ['https://cdn.com/live/seg0.ts', 'https://other.com/seg1.ts']);
      expect(playlist.isEncrypted, isFalse);
    });

    test('détecte le chiffrement', () {
      final HlsPlaylist playlist = HlsParser.parse(
          '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="k"\n#EXTINF:6,\na.ts\n', base);
      expect(playlist.isEncrypted, isTrue);
    });

    test('refuse un fichier invalide', () {
      expect(() => HlsParser.parse('<html>', base), throwsFormatException);
    });
  });

  test('Formatters.bytes', () {
    expect(Formatters.bytes(500), '500 o');
    expect(Formatters.bytes(1536), '1,5 Ko');
    expect(Formatters.bytes(5 * 1024 * 1024), '5,0 Mo');
  });
}
