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

  final String url;
  final MediaKind kind;
  final MediaSource source;
  final String pageUrl;     // page d'origine (sert de « Referer »)
  final String? pageTitle;  // sert à nommer le fichier
  final String? mimeType;
  final int? contentLength;

  bool get isHls => kind == MediaKind.stream;

  /// Extension de fichier probable.
  String get extension {
    if (isHls) return '.ts';
    final String path = (Uri.tryParse(url)?.path ?? '').toLowerCase();
    final int dot = path.lastIndexOf('.');
    if (dot != -1 && path.length - dot <= 5) return path.substring(dot);
    return kind == MediaKind.audio ? '.mp3' : '.mp4';
  }
}
