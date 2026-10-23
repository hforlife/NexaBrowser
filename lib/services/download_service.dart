import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/download_task.dart';
import 'settings_service.dart';

/// Interface Dart du moteur de téléchargement natif (Android).
///
/// Le moteur tourne dans un service au premier plan : il continue quand l'app
/// est fermée, gère les notifications, les nouvelles tentatives, la conversion
/// HLS → MP4 et l'enregistrement dans Téléchargements/NexaBrowser.
/// Ce service se contente de refléter son état et de lui transmettre les commandes.
class DownloadService extends ChangeNotifier {
  DownloadService(this._settings);

  static const MethodChannel _methods = MethodChannel('nexa_browser/downloads');
  static const EventChannel _events = EventChannel('nexa_browser/downloads/events');

  /// Clé ajoutée par le moteur aux événements de suppression.
  static const String _removedKey = 'removed';

  final SettingsService _settings;
  final Map<String, DownloadTask> _tasks = <String, DownloadTask>{};
  StreamSubscription<dynamic>? _subscription;

  /// Téléchargements, du plus récent au plus ancien.
  List<DownloadTask> get tasks => _tasks.values.toList()
    ..sort((DownloadTask a, DownloadTask b) => b.createdAt.compareTo(a.createdAt));

  int get activeCount => _tasks.values.where((DownloadTask t) => t.isActive).length;

  /// Le moteur n'existe que sur Android pour l'instant.
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<void> load() async {
    if (!isSupported) return;
    // Abonnement avant la lecture : aucun changement ne peut être manqué
    _subscription = _events.receiveBroadcastStream().listen(_onEvent);
    final List<Map<Object?, Object?>> rows =
        await _methods.invokeListMethod<Map<Object?, Object?>>('list') ?? const [];
    for (final Map<Object?, Object?> row in rows) {
      final DownloadTask task = DownloadTask.fromMap(row);
      _tasks.putIfAbsent(task.id, () => task);
    }
    notifyListeners();
  }

  /// Ajoute un téléchargement.
  ///
  /// [withCookies] : joindre les cookies du site (faux pour un média hébergé
  /// sur un autre domaine que la page, signalé par un script de la page).
  /// Lève une [DownloadException] si le moteur refuse (lien blob:, data:…).
  Future<DownloadTask> enqueue({
    required String url,
    required String fileName,
    String? referer,
    String? mimeType,
    bool isHls = false,
    bool withCookies = true,
  }) async {
    if (!isSupported) {
      throw const DownloadException('Téléchargements disponibles sur Android uniquement');
    }
    await _askPermissionsOnce();
    try {
      final Map<Object?, Object?>? row = await _methods.invokeMapMethod<Object?, Object?>('enqueue', {
        'url': url,
        'fileName': fileName,
        'referer': referer,
        'mimeType': mimeType,
        'isHls': isHls,
        'withCookies': withCookies,
      });
      if (row == null) throw const DownloadException('Téléchargement impossible');
      final DownloadTask task = DownloadTask.fromMap(row);
      _upsert(task);
      return task;
    } on PlatformException catch (e) {
      throw DownloadException(e.message ?? 'Téléchargement impossible');
    }
  }

  Future<void> pause(DownloadTask task) => _methods.invokeMethod<void>('pause', {'id': task.id});

  Future<void> resume(DownloadTask task) => _methods.invokeMethod<void>('resume', {'id': task.id});

  /// Retire de la liste ; [deleteFile] supprime aussi le fichier terminé.
  /// Retourne faux si le fichier n'a pas pu être supprimé.
  Future<bool> remove(DownloadTask task, {required bool deleteFile}) async =>
      await _methods.invokeMethod<bool>('remove', {'id': task.id, 'deleteFile': deleteFile}) ?? false;

  /// Ouvre le fichier dans l'app adaptée. Faux si aucune app ne sait l'ouvrir.
  Future<bool> open(DownloadTask task) async =>
      await _methods.invokeMethod<bool>('open', {'id': task.id}) ?? false;

  /// Notifications (Android 13+) et stockage (Android 9-) : demandés une seule
  /// fois, au premier téléchargement. Un refus n'empêche pas de télécharger.
  Future<void> _askPermissionsOnce() async {
    if (_settings.downloadPermissionsAsked) return;
    _settings.downloadPermissionsAsked = true;
    try {
      await _methods.invokeMethod<Object?>('ensurePermissions');
    } on PlatformException catch (e) {
      debugPrint('Permissions de téléchargement : ${e.message}');
    }
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final Map<Object?, Object?> map = event.cast<Object?, Object?>();
    final Object? id = map['id'];
    if (id is! String) return;
    if (map[_removedKey] == true) {
      if (_tasks.remove(id) != null) notifyListeners();
      return;
    }
    _upsert(DownloadTask.fromMap(map));
  }

  void _upsert(DownloadTask task) {
    _tasks[task.id] = task;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// Erreur affichable à l'utilisateur.
class DownloadException implements Exception {
  const DownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}
