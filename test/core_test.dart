// Tests des briques sans interface (URL, bloqueur, détection vidéo, téléchargements) : « flutter test ».
// Le moteur de téléchargement natif (HLS, reprise…) est testé côté Kotlin :
// cd android && ./gradlew :app:testDebugUnitTest
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_browser/core/constants.dart';
import 'package:nexa_browser/core/formatters.dart';
import 'package:nexa_browser/core/url_utils.dart';
import 'package:nexa_browser/models/detected_media.dart';
import 'package:nexa_browser/models/download_task.dart';
import 'package:nexa_browser/services/adblock/adblock_engine.dart';
import 'package:nexa_browser/services/adblock/domain_set_engine.dart';
import 'package:nexa_browser/services/media_detector.dart';
import 'package:nexa_browser/state/page_load_stats.dart';

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

  group('DomainSetEngine', () {
    final Set<String> domains = DomainSetEngine.parseHosts('''
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
      expect(DomainSetEngine.isHostInSet('stats.g.doubleclick.net', domains), isTrue);
      expect(DomainSetEngine.isHostInSet('ads.example.com', domains), isTrue);
    });

    test('ne bloque pas les sites légitimes', () {
      expect(DomainSetEngine.isHostInSet('example.com', domains), isFalse);
      expect(DomainSetEngine.isHostInSet('notdoubleclick.net', domains), isFalse);
      expect(DomainSetEngine.isHostInSet('net', domains), isFalse);
    });

    test('fusion : liste embarquée en tête, sans doublon', () {
      final Set<String> merged = DomainSetEngine.mergeDomains(
        {'doubleclick.net', 'adnxs.com'},
        {'tracker.io', 'doubleclick.net', 'pub.ml'},
      );
      expect(merged.toList(), ['doubleclick.net', 'adnxs.com', 'tracker.io', 'pub.ml']);
    });

    test('décision par requête, insensible à la casse', () {
      final DomainSetEngine engine = DomainSetEngine(domains);
      expect(engine.ruleCount, 2);
      bool blocks(String url) =>
          engine.shouldBlock(AdblockRequest(url: Uri.parse(url), pageSite: 'site.ml'));
      expect(blocks('https://Stats.G.DoubleClick.net/pixel.gif'), isTrue);
      expect(blocks('https://site.ml/app.js'), isFalse);
      expect(blocks('data:image/png;base64,AAAA'), isFalse);
      expect(DomainSetEngine.empty().ruleCount, 0);
    });

    test('analyse dans un isolate (comme au démarrage)', () async {
      const String content = '0.0.0.0 a.com\n0.0.0.0 b.com\n';
      final Set<String> parsed = await Isolate.run(() => DomainSetEngine.parseHosts(content));
      expect(parsed, {'a.com', 'b.com'});
    });
  });

  group('MediaDetector.parsePageReport', () {
    test('garde les médias http(s) valides', () {
      final List<PageMediaReport> reports = MediaDetector.parsePageReport([
        [
          {'url': 'https://cdn.ml/clip.mp4', 'tag': 'video', 'type': ''},
          {'url': 'https://cdn.ml/son', 'tag': 'audio', 'type': ''},
        ],
      ]);
      expect(reports.map((r) => r.url), ['https://cdn.ml/clip.mp4', 'https://cdn.ml/son']);
      expect(reports.map((r) => r.kind), [MediaKind.video, MediaKind.audio]);
    });

    test('rejette les entrées invalides ou dangereuses', () {
      final List<PageMediaReport> reports = MediaDetector.parsePageReport([
        [
          {'url': 'javascript:alert(1)', 'tag': 'video'},
          {'url': 'file:///sdcard/secret.mp4', 'tag': 'video'},
          {'url': 42, 'tag': 'video'},
          {'url': 'https://${'a' * MediaDetector.maxUrlLength}.com/v.mp4', 'tag': 'video'},
          'pas une map',
        ],
      ]);
      expect(reports, isEmpty);
    });

    test('limite le nombre d\'entrées par message', () {
      final List<Map<String, String>> many = [
        for (int i = 0; i < 500; i++) {'url': 'https://cdn.ml/$i.mp4', 'tag': 'video'},
      ];
      expect(MediaDetector.parsePageReport([many]).length, MediaDetector.maxItemsPerReport);
    });

    test('arguments mal formés', () {
      expect(MediaDetector.parsePageReport([]), isEmpty);
      expect(MediaDetector.parsePageReport(['texte']), isEmpty);
    });
  });

  group('PageLoadStats', () {
    test('résumé après un chargement', () {
      final PageLoadStats stats = PageLoadStats()..start();
      stats
        ..recordRequest(1500, blocked: true)
        ..recordRequest(500, blocked: false);
      final String? summary = stats.finish(url: 'https://site.ml', interception: true);
      expect(summary, contains('requêtes interceptées : 2 (bloquées : 1)'));
      expect(summary, contains('max : 1.50 ms'));
      expect(stats.isRunning, isFalse);
    });

    test('rien à résumer sans démarrage', () {
      expect(PageLoadStats().finish(url: 'x', interception: false), isNull);
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

  group('UrlUtils.isSameSite', () {
    test('même site malgré les sous-domaines', () {
      expect(UrlUtils.isSameSite('https://video.site.ml/a.mp4', 'https://www.site.ml/page'), isTrue);
      expect(UrlUtils.isSameSite('https://site.ml/a.mp4', 'https://site.ml/'), isTrue);
    });

    test('sites différents', () {
      expect(UrlUtils.isSameSite('https://cdn.autre.com/a.mp4', 'https://site.ml/page'), isFalse);
      expect(UrlUtils.isSameSite('pas une url', 'https://site.ml'), isFalse);
    });
  });

  group('DetectedMedia.extension', () {
    DetectedMedia media(String url, MediaKind kind) =>
        DetectedMedia(url: url, kind: kind, source: MediaSource.network, pageUrl: 'https://site.ml');

    test('HLS converti en MP4', () {
      expect(media('https://cdn.ml/master.m3u8', MediaKind.stream).extension, '.mp4');
    });

    test('extension connue reprise de l\'URL', () {
      expect(media('https://cdn.ml/clip.webm?x=1', MediaKind.video).extension, '.webm');
      expect(media('https://cdn.ml/son.m4a', MediaKind.audio).extension, '.m4a');
    });

    test('extension de script remplacée', () {
      expect(media('https://site.ml/get.php?id=4', MediaKind.video).extension, '.mp4');
      expect(media('https://site.ml/stream.aspx', MediaKind.audio).extension, '.mp3');
    });
  });

  group('DownloadTask', () {
    Map<Object?, Object?> row({
      String status = 'running',
      bool isHls = false,
      int received = 50,
      int? total = 200,
      int done = 0,
      int? segments,
    }) =>
        {
          'id': 'a1',
          'url': 'https://cdn.ml/v.mp4',
          'fileName': 'v.mp4',
          'isHls': isHls,
          'createdAt': 1700000000000,
          'status': status,
          'receivedBytes': received,
          'totalBytes': total,
          'segmentsDone': done,
          'segmentsTotal': segments,
        };

    test('lit les données du moteur natif', () {
      final DownloadTask task = DownloadTask.fromMap(row());
      expect(task.status, DownloadStatus.running);
      expect(task.progress, 0.25);
      expect(task.canPause, isTrue);
      expect(task.canResume, isFalse);
    });

    test('progression HLS par segments', () {
      final DownloadTask task =
          DownloadTask.fromMap(row(isHls: true, done: 3, segments: 12, total: null));
      expect(task.progress, 0.25);
    });

    test('statuts et actions possibles', () {
      expect(DownloadTask.fromMap(row(status: 'converting')).canPause, isFalse);
      expect(DownloadTask.fromMap(row(status: 'waitingNetwork')).isActive, isTrue);
      expect(DownloadTask.fromMap(row(status: 'failed')).canResume, isTrue);
      expect(DownloadTask.fromMap(row(status: 'inconnu')).status, DownloadStatus.failed);
    });

    test('taille inconnue', () {
      expect(DownloadTask.fromMap(row(total: null)).progress, isNull);
    });
  });

  test('Formatters.bytes', () {
    expect(Formatters.bytes(500), '500 o');
    expect(Formatters.bytes(1536), '1,5 Ko');
    expect(Formatters.bytes(5 * 1024 * 1024), '5,0 Mo');
  });
}
