/// Média (vidéo / audio) repéré sur une page.
library;

enum MediaKind {
  video('Vidéo'),
  audio('Audio'),
  stream('Flux HLS');

  const MediaKind(this.label);

  final String label;
}

/// Origine de la détection (utile pour le débogage et la fiabilité).
enum MediaSource { network, page, download }

class DetectedMedia {
  const DetectedMedia({
    required this.url,
    required this.kind,
    required this.source,
    required this.pageUrl,
    this.pageTitle,
    this.mimeType,
    this.contentLength,
  });

  /// Extensions reprises telles quelles depuis l'URL ; les autres (« .php »,
  /// « .aspx »…) sont remplacées par l'extension par défaut du type de média.
  static const Set<String> _knownExtensions = {
    '.mp4', '.webm', '.mov', '.mkv', '.m4v', '.3gp',
    '.mp3', '.m4a', '.aac', '.ogg', '.wav', '.opus',
  };

  final String url;
  final MediaKind kind;
  final MediaSource source;
  final String pageUrl;     // page d'origine (sert de « Referer »)
  final String? pageTitle;  // sert à nommer le fichier
  final String? mimeType;
  final int? contentLength;

  bool get isHls => kind == MediaKind.stream;

  /// Extension du fichier final. Les flux HLS sont convertis en MP4 par le moteur.
  String get extension {
    if (isHls) return '.mp4';
    final String path = (Uri.tryParse(url)?.path ?? '').toLowerCase();
    final int dot = path.lastIndexOf('.');
    if (dot != -1) {
      final String fromUrl = path.substring(dot);
      if (_knownExtensions.contains(fromUrl)) return fromUrl;
    }
    return kind == MediaKind.audio ? '.mp3' : '.mp4';
  }
}
