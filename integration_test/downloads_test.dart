// Test de bout en bout du moteur de téléchargement natif, sur appareil ou émulateur Android.
//
// Nécessite un serveur de test (médias, plages d'octets, débit bridé, coupures)
// joignable depuis l'appareil, puis :
//   flutter test integration_test/downloads_test.dart \
//     --dart-define=NEXA_TEST_SERVER=http://10.0.2.2:8765
//
// Médias attendus sur le serveur : clip.mp4, big.mp4, hls_ts/master.m3u8,
// hls_fmp4/index.m3u8, hls_split/master.m3u8, encrypted.m3u8, live.m3u8.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nexa_browser/models/download_task.dart';
import 'package:nexa_browser/services/download_service.dart';
import 'package:nexa_browser/services/settings_service.dart';

const String server = String.fromEnvironment('NEXA_TEST_SERVER');

/// Tailles exactes des fichiers servis (générés par ffmpeg pour le test).
const int clipSize = int.fromEnvironment('NEXA_CLIP_SIZE');
const int bigSize = int.fromEnvironment('NEXA_BIG_SIZE');

const Duration pollInterval = Duration(milliseconds: 200);
const Duration defaultTimeout = Duration(seconds: 90);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late DownloadService downloads;

  setUpAll(() async {
    final SettingsService settings = SettingsService();
    await settings.load();
    settings.downloadPermissionsAsked = true; // pas de boîte de dialogue pendant le test
    downloads = DownloadService(settings);
    await downloads.load();
  });

  /// Attend que la tâche [id] vérifie [condition] ; retourne aussi les statuts traversés.
  Future<(DownloadTask, Set<DownloadStatus>)> waitFor(
    String id,
    bool Function(DownloadTask task) condition, {
    Duration timeout = defaultTimeout,
  }) async {
    final Set<DownloadStatus> seen = <DownloadStatus>{};
    final DateTime deadline = DateTime.now().add(timeout);
    DownloadTask? last;
    while (DateTime.now().isBefore(deadline)) {
      last = downloads.tasks.where((DownloadTask t) => t.id == id).firstOrNull;
      if (last != null) {
        seen.add(last.status);
        if (condition(last)) return (last, seen);
      }
      await Future<void>.delayed(pollInterval);
    }
    fail('Délai dépassé — dernier état : ${last?.status} ${last?.error ?? ''} '
        '(${last?.receivedBytes} octets) ; statuts vus : $seen');
  }

  bool finished(DownloadTask t) =>
      t.status == DownloadStatus.completed || t.status == DownloadStatus.failed;

  Future<DownloadTask> downloadUntilFinished(String path, String name, {bool isHls = false}) async {
    final DownloadTask task = await downloads.enqueue(url: '$server/$path', fileName: name, isHls: isHls);
    return (await waitFor(task.id, finished)).$1;
  }

  group('Moteur de téléchargement', skip: server.isEmpty ? 'NEXA_TEST_SERVER non défini' : null, () {
    testWidgets('fichier MP4 → Téléchargements/NexaBrowser', (_) async {
      final DownloadTask done = await downloadUntilFinished('clip.mp4', 'clip.mp4');
      expect(done.status, DownloadStatus.completed, reason: done.error);
      expect(done.receivedBytes, clipSize);
      expect(done.displayPath, contains('NexaBrowser'));
    });

    testWidgets('HLS (segments TS) → MP4', (_) async {
      final DownloadTask done = await downloadUntilFinished('hls_ts/master.m3u8', 'flux ts.mp4', isHls: true);
      expect(done.status, DownloadStatus.completed, reason: done.error);
      expect(done.fileName, endsWith('.mp4'));
      expect(done.segmentsDone, done.segmentsTotal);
    });

    testWidgets('HLS fMP4 → MP4', (_) async {
      final DownloadTask done = await downloadUntilFinished('hls_fmp4/index.m3u8', 'flux fmp4.mp4', isHls: true);
      expect(done.status, DownloadStatus.completed, reason: done.error);
      expect(done.fileName, endsWith('.mp4'));
    });

    testWidgets('HLS avec audio séparé → MP4 (deux pistes assemblées)', (_) async {
      final DownloadTask done = await downloadUntilFinished('hls_split/master.m3u8', 'flux audio separe.mp4', isHls: true);
      expect(done.status, DownloadStatus.completed, reason: done.error);
      expect(done.fileName, endsWith('.mp4'));
    });

    testWidgets('pause puis reprise sans corruption', (_) async {
      final DownloadTask task =
          await downloads.enqueue(url: '$server/big.mp4?rate=300000', fileName: 'pause reprise.mp4');
      await waitFor(task.id, (DownloadTask t) => t.status == DownloadStatus.running && t.receivedBytes > 400000);
      await downloads.pause(task);
      final DownloadTask paused = (await waitFor(task.id, (DownloadTask t) => t.status == DownloadStatus.paused)).$1;

      // Plus rien ne doit arriver pendant la pause
      await Future<void>.delayed(const Duration(seconds: 2));
      final DownloadTask stillPaused = downloads.tasks.firstWhere((DownloadTask t) => t.id == task.id);
      expect(stillPaused.status, DownloadStatus.paused);
      expect(stillPaused.receivedBytes, lessThan(bigSize));

      // Reprise immédiate après la pause (cas qui corrompait le fichier en v0.1)
      await downloads.resume(paused);
      final DownloadTask done = (await waitFor(task.id, finished)).$1;
      expect(done.status, DownloadStatus.completed, reason: done.error);
      expect(done.receivedBytes, bigSize);
    });

    testWidgets('coupure réseau : nouvel essai automatique puis reprise', (_) async {
      final DownloadTask task =
          await downloads.enqueue(url: '$server/clip.mp4?dropafter=100000', fileName: 'coupure.mp4');
      final (DownloadTask done, Set<DownloadStatus> seen) = await waitFor(task.id, finished);
      expect(done.status, DownloadStatus.completed, reason: done.error);
      expect(seen, contains(DownloadStatus.retrying));
      expect(done.receivedBytes, clipSize);
    });

    testWidgets('erreur 404 : échec immédiat, sans nouvel essai', (_) async {
      final DownloadTask done = await downloadUntilFinished('absent.mp4', 'absent.mp4');
      expect(done.status, DownloadStatus.failed);
      expect(done.error, contains('404'));
      expect(done.retryCount, 0);
    });

    testWidgets('flux chiffré refusé', (_) async {
      final DownloadTask done = await downloadUntilFinished('encrypted.m3u8', 'chiffre.mp4', isHls: true);
      expect(done.status, DownloadStatus.failed);
      expect(done.error, contains('chiffré'));
    });

    testWidgets('direct refusé', (_) async {
      final DownloadTask done = await downloadUntilFinished('live.m3u8', 'direct.mp4', isHls: true);
      expect(done.status, DownloadStatus.failed);
      expect(done.error, contains('direct'));
    });

    testWidgets('lien blob: refusé par le moteur', (_) async {
      expect(
        () => downloads.enqueue(url: 'blob:https://site.ml/1234', fileName: 'x.mp4'),
        throwsA(isA<DownloadException>()),
      );
    });

    testWidgets('suppression : la tâche disparaît de la liste', (_) async {
      final DownloadTask done = await downloadUntilFinished('clip.mp4', 'a supprimer.mp4');
      expect(done.status, DownloadStatus.completed, reason: done.error);
      expect(await downloads.remove(done, deleteFile: true), isTrue);
      await waitForRemoval(downloads, done.id);
    });
  });
}

Future<void> waitForRemoval(DownloadService downloads, String id) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (!downloads.tasks.any((DownloadTask t) => t.id == id)) return;
    await Future<void>.delayed(pollInterval);
  }
  fail('La tâche $id est toujours dans la liste');
}
