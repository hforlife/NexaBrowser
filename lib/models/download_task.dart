/// Téléchargement, tel que transmis par le moteur natif Android.
///
/// Objet immuable : chaque événement du moteur remplace l'instance précédente.
library;

enum DownloadStatus {
  queued('En attente'),
  running('En cours'),
  waitingNetwork('En attente du réseau'),
  retrying('Nouvelle tentative bientôt'),
  paused('En pause'),
  converting('Conversion en MP4…'),
  completed('Terminé'),
  failed('Échec');

  const DownloadStatus(this.label);

  final String label;

  static DownloadStatus fromName(String? name) =>
      DownloadStatus.values.firstWhere((s) => s.name == name, orElse: () => DownloadStatus.failed);
}

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.isHls,
    required this.createdAt,
    required this.status,
    this.mimeType,
    this.receivedBytes = 0,
    this.totalBytes,
    this.segmentsDone = 0,
    this.segmentsTotal,
    this.retryCount = 0,
    this.error,
    this.displayPath,
  });

  final String id;
  final String url;
  final String fileName;
  final String? mimeType;
  final bool isHls;
  final DateTime createdAt;
  final DownloadStatus status;
  final int receivedBytes;

  /// Fichier : taille exacte. HLS : estimation (débit × durée), peut être null.
  final int? totalBytes;

  /// HLS : segments terminés / total.
  final int segmentsDone;
  final int? segmentsTotal;

  final int retryCount;
  final String? error;

  /// Emplacement lisible, ex. « Téléchargements/NexaBrowser/clip.mp4 ».
  final String? displayPath;

  /// Progression entre 0 et 1, ou null si inconnue.
  double? get progress {
    if (isHls) {
      final int? total = segmentsTotal;
      if (total == null || total <= 0) return null;
      return (segmentsDone / total).clamp(0.0, 1.0);
    }
    final int? total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0);
  }

  /// En cours ou reprendra seul.
  bool get isActive => switch (status) {
        DownloadStatus.queued ||
        DownloadStatus.running ||
        DownloadStatus.waitingNetwork ||
        DownloadStatus.retrying ||
        DownloadStatus.converting =>
          true,
        DownloadStatus.paused || DownloadStatus.completed || DownloadStatus.failed => false,
      };

  /// La conversion, courte, ne peut pas être interrompue.
  bool get canPause => isActive && status != DownloadStatus.converting;

  bool get canResume => status == DownloadStatus.paused || status == DownloadStatus.failed;

  factory DownloadTask.fromMap(Map<Object?, Object?> map) => DownloadTask(
        id: map['id']! as String,
        url: map['url']! as String,
        fileName: map['fileName']! as String,
        mimeType: map['mimeType'] as String?,
        isHls: map['isHls'] as bool? ?? false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int? ?? 0),
        status: DownloadStatus.fromName(map['status'] as String?),
        receivedBytes: map['receivedBytes'] as int? ?? 0,
        totalBytes: map['totalBytes'] as int?,
        segmentsDone: map['segmentsDone'] as int? ?? 0,
        segmentsTotal: map['segmentsTotal'] as int?,
        retryCount: map['retryCount'] as int? ?? 0,
        error: map['error'] as String?,
        displayPath: map['displayPath'] as String?,
      );
}
