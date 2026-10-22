/// Téléchargement (fichier classique ou flux HLS assemblé).
library;

enum DownloadStatus {
  queued('En attente'),
  running('En cours'),
  paused('En pause'),
  completed('Terminé'),
  failed('Échec');

  const DownloadStatus(this.label);

  final String label;

  static DownloadStatus fromName(String name) =>
      DownloadStatus.values.firstWhere((s) => s.name == name, orElse: () => DownloadStatus.failed);
}

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.savePath,
    required this.createdAt,
    this.referer,
    this.isHls = false,
    this.received = 0,
    this.total,
    this.status = DownloadStatus.queued,
    this.error,
  });

  final String id;
  final String url;
  final String fileName;
  final String savePath;
  final DateTime createdAt;
  final String? referer;
  final bool isHls;

  /// Fichier classique : octets reçus. HLS : segments téléchargés.
  int received;

  /// Fichier classique : taille totale en octets. HLS : nombre de segments.
  int? total;

  DownloadStatus status;
  String? error;

  /// Progression entre 0 et 1, ou null si inconnue.
  double? get progress {
    final int? t = total;
    if (t == null || t <= 0) return null;
    return (received / t).clamp(0.0, 1.0);
  }

  bool get isActive => status == DownloadStatus.running || status == DownloadStatus.queued;

  Map<String, Object?> toMap() => {
        'id': id,
        'url': url,
        'file_name': fileName,
        'save_path': savePath,
        'created_at': createdAt.millisecondsSinceEpoch,
        'referer': referer,
        'is_hls': isHls ? 1 : 0,
        'received': received,
        'total': total,
        'status': status.name,
        'error': error,
      };

  factory DownloadTask.fromMap(Map<String, Object?> map) => DownloadTask(
        id: map['id']! as String,
        url: map['url']! as String,
        fileName: map['file_name']! as String,
        savePath: map['save_path']! as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
        referer: map['referer'] as String?,
        isHls: (map['is_hls'] as int? ?? 0) == 1,
        received: map['received'] as int? ?? 0,
        total: map['total'] as int?,
        status: DownloadStatus.fromName(map['status']! as String),
        error: map['error'] as String?,
      );
}
