import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
// Préfixe : évite le conflit entre Cookie (dart:io) et Cookie (inappwebview)
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iaw;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../core/url_utils.dart';
import '../models/download_task.dart';
import 'database_service.dart';
import 'hls_parser.dart';

/// Gestionnaire de téléchargements : fichiers classiques (avec reprise)
/// et flux HLS (.m3u8) assemblés en un seul fichier .ts.
class DownloadService extends ChangeNotifier {
  DownloadService(this._db);

  final DatabaseService _db;
  final http.Client _client = http.Client();

  /// Téléchargements simultanés maximum.
  static const int maxConcurrent = 2;

  /// Fréquence max de rafraîchissement de l'écran et de la base pendant un transfert.
  static const Duration _progressThrottle = Duration(milliseconds: 400);

  final List<DownloadTask> _tasks = [];
  final Set<String> _cancelled = <String>{};
  Directory? _directory;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  int get activeCount => _tasks.where((t) => t.status == DownloadStatus.running).length;

  Future<void> load() async {
    _tasks
      ..clear()
      ..addAll(await _db.downloads());
    // Les transferts interrompus par la fermeture de l'app passent en pause
    for (final DownloadTask task in _tasks.where((t) => t.isActive)) {
      task.status = DownloadStatus.paused;
      await _db.saveDownload(task);
    }
    notifyListeners();
  }

  /// Dossier de destination (visible dans Android/data/<app>/files/Download/NexaBrowser).
  Future<Directory> downloadDirectory() async {
    if (_directory != null) return _directory!;
    Directory? base;
    if (Platform.isAndroid) {
      final List<Directory>? dirs =
          await getExternalStorageDirectories(type: StorageDirectory.downloads);
      base = (dirs != null && dirs.isNotEmpty) ? dirs.first : null;
    }
    base ??= await getApplicationDocumentsDirectory();
    final Directory dir = Directory(p.join(base.path, AppConstants.downloadsFolder));
    await dir.create(recursive: true);
    return _directory = dir;
  }

  /// Ajoute un téléchargement et le démarre dès qu'une place est libre.
  Future<DownloadTask> enqueue({
    required String url,
    String? fileName,
    String? referer,
    bool isHls = false,
  }) async {
    final Directory dir = await downloadDirectory();
    final String baseName = UrlUtils.sanitizeFileName(
      fileName ?? UrlUtils.fileNameFromUrl(url, fallbackExtension: isHls ? '.ts' : ''),
    );
    final String name = isHls && !baseName.endsWith('.ts') ? '${p.withoutExtension(baseName)}.ts' : baseName;
    final String path = await _uniquePath(dir, name);

    final DownloadTask task = DownloadTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      url: url,
      fileName: p.basename(path),
      savePath: path,
      createdAt: DateTime.now(),
      referer: referer,
      isHls: isHls,
    );
    _tasks.insert(0, task);
    await _db.saveDownload(task);
    notifyListeners();
    _pump();
    return task;
  }

  void pause(DownloadTask task) {
    if (!task.isActive) return;
    _cancelled.add(task.id);
    task.status = DownloadStatus.paused;
    _persist(task);
  }

  void resume(DownloadTask task) {
    if (task.status != DownloadStatus.paused && task.status != DownloadStatus.failed) return;
    task
      ..status = DownloadStatus.queued
      ..error = null;
    _persist(task);
    _pump();
  }

  /// Supprime la tâche (et le fichier si [deleteFile]).
  Future<void> remove(DownloadTask task, {bool deleteFile = true}) async {
    _cancelled.add(task.id);
    _tasks.remove(task);
    await _db.deleteDownload(task.id);
    if (deleteFile) {
      final File file = File(task.savePath);
      if (await file.exists()) await file.delete();
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ moteur

  /// Démarre les tâches en attente dans la limite de [maxConcurrent].
  void _pump() {
    final Iterable<DownloadTask> waiting =
        _tasks.reversed.where((t) => t.status == DownloadStatus.queued);
    for (final DownloadTask task in waiting.toList()) {
      if (activeCount >= maxConcurrent) break;
      task.status = DownloadStatus.running;
      _cancelled.remove(task.id);
      notifyListeners();
      unawaited(_run(task));
    }
  }

  Future<void> _run(DownloadTask task) async {
    try {
      if (task.isHls) {
        await _downloadHls(task);
      } else {
        await _downloadFile(task);
      }
      if (_cancelled.contains(task.id)) return; // mis en pause ou supprimé
      task.status = DownloadStatus.completed;
    } catch (e) {
      if (_cancelled.contains(task.id)) return;
      task
        ..status = DownloadStatus.failed
        ..error = e.toString();
    } finally {
      _cancelled.remove(task.id);
      if (_tasks.contains(task)) await _persist(task);
      _pump();
    }
  }

  /// En-têtes : User-Agent, Referer et cookies du site (souvent exigés par les CDN).
  Future<Map<String, String>> _headersFor(String url, String? referer) async {
    final Map<String, String> headers = {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/130.0 Mobile Safari/537.36',
      if (referer != null) 'Referer': referer,
    };
    try {
      final List<iaw.Cookie> cookies =
          await iaw.CookieManager.instance().getCookies(url: iaw.WebUri(url));
      if (cookies.isNotEmpty) {
        headers['Cookie'] = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      }
    } catch (_) {
      // Pas de cookies disponibles : on continue sans
    }
    return headers;
  }

  Future<void> _downloadFile(DownloadTask task) async {
    final File file = File(task.savePath);
    final int existing = await file.exists() ? await file.length() : 0;

    final http.Request request = http.Request('GET', Uri.parse(task.url))
      ..headers.addAll(await _headersFor(task.url, task.referer));
    if (existing > 0) request.headers['Range'] = 'bytes=$existing-';

    final http.StreamedResponse response = await _client.send(request);
    if (response.statusCode >= 400) {
      throw HttpException('Erreur serveur ${response.statusCode}');
    }

    // 206 = le serveur accepte la reprise ; sinon on repart de zéro
    final bool resumed = response.statusCode == 206 && existing > 0;
    task.received = resumed ? existing : 0;
    final int? length = response.contentLength;
    task.total = length == null ? null : length + task.received;

    final IOSink sink = file.openWrite(mode: resumed ? FileMode.append : FileMode.write);
    DateTime lastUpdate = DateTime.now();
    try {
      await for (final List<int> chunk in response.stream) {
        if (_cancelled.contains(task.id)) break;
        sink.add(chunk);
        task.received += chunk.length;
        if (DateTime.now().difference(lastUpdate) > _progressThrottle) {
          lastUpdate = DateTime.now();
          notifyListeners();
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  Future<void> _downloadHls(DownloadTask task) async {
    final Map<String, String> headers = await _headersFor(task.url, task.referer);

    Uri playlistUri = Uri.parse(task.url);
    HlsPlaylist playlist = HlsParser.parse(await _getText(playlistUri, headers), playlistUri);

    // Liste maître : on prend la meilleure qualité
    final HlsVariant? best = playlist.bestVariant;
    if (playlist.isMaster && best != null) {
      playlistUri = best.uri;
      playlist = HlsParser.parse(await _getText(playlistUri, headers), playlistUri);
    }
    if (playlist.isEncrypted) {
      throw const HttpException('Flux protégé (chiffré) : téléchargement impossible');
    }
    if (playlist.segments.isEmpty) {
      throw const FormatException('Aucun segment dans ce flux');
    }

    task.total = playlist.segments.length;
    final File file = File(task.savePath);
    // Reprise : on repart du segment suivant le dernier terminé
    final int start =
        (await file.exists()) ? math.min(math.max(task.received, 0), playlist.segments.length) : 0;
    task.received = start;
    final IOSink sink = file.openWrite(mode: start > 0 ? FileMode.append : FileMode.write);

    try {
      for (int i = start; i < playlist.segments.length; i++) {
        if (_cancelled.contains(task.id)) break;
        final http.Response segment =
            await _client.get(playlist.segments[i], headers: headers).timeout(const Duration(seconds: 60));
        if (segment.statusCode >= 400) {
          throw HttpException('Segment ${i + 1} : erreur ${segment.statusCode}');
        }
        sink.add(segment.bodyBytes);
        task.received = i + 1;
        notifyListeners();
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  Future<String> _getText(Uri uri, Map<String, String> headers) async {
    final http.Response response =
        await _client.get(uri, headers: headers).timeout(const Duration(seconds: 30));
    if (response.statusCode >= 400) {
      throw HttpException('Liste de lecture : erreur ${response.statusCode}');
    }
    return response.body;
  }

  Future<void> _persist(DownloadTask task) async {
    notifyListeners();
    await _db.saveDownload(task);
  }

  /// « video.mp4 » existe déjà → « video (1).mp4 »
  Future<String> _uniquePath(Directory dir, String name) async {
    final String stem = p.basenameWithoutExtension(name);
    final String ext = p.extension(name);
    String candidate = p.join(dir.path, name);
    int index = 1;
    final Set<String> reserved = _tasks.map((t) => t.savePath).toSet();
    while (await File(candidate).exists() || reserved.contains(candidate)) {
      candidate = p.join(dir.path, '$stem ($index)$ext');
      index++;
    }
    return candidate;
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
