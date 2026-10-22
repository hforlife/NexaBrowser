/// Lecture des listes de lecture HLS (.m3u8).
library;

/// Variante d'une liste « maître » (une qualité).
class HlsVariant {
  const HlsVariant({required this.uri, required this.bandwidth, this.resolution});

  final Uri uri;
  final int bandwidth;
  final String? resolution; // ex. « 1280x720 »
}

class HlsPlaylist {
  const HlsPlaylist({
    required this.variants,
    required this.segments,
    required this.isEncrypted,
  });

  /// Non vide si c'est une liste maître (plusieurs qualités).
  final List<HlsVariant> variants;

  /// Segments à télécharger dans l'ordre (liste « média »).
  final List<Uri> segments;

  /// Flux chiffré (#EXT-X-KEY) : non pris en charge.
  final bool isEncrypted;

  bool get isMaster => variants.isNotEmpty;

  /// Meilleure qualité disponible.
  HlsVariant? get bestVariant {
    if (variants.isEmpty) return null;
    return variants.reduce((a, b) => a.bandwidth >= b.bandwidth ? a : b);
  }
}

class HlsParser {
  HlsParser._();

  static final RegExp _bandwidth = RegExp(r'BANDWIDTH=(\d+)');
  static final RegExp _resolution = RegExp(r'RESOLUTION=(\d+x\d+)');
  static final RegExp _keyMethod = RegExp(r'METHOD=([A-Z0-9-]+)');

  /// Analyse le contenu d'un .m3u8 ; les chemins relatifs sont résolus sur [base].
  static HlsPlaylist parse(String content, Uri base) {
    final List<String> lines = content
        .split('\n')
        .map((String l) => l.trim())
        .where((String l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty || !lines.first.startsWith('#EXTM3U')) {
      throw const FormatException('Liste HLS invalide');
    }

    final List<HlsVariant> variants = [];
    final List<Uri> segments = [];
    bool encrypted = false;
    String? pendingStreamInf;

    for (final String line in lines) {
      if (line.startsWith('#EXT-X-STREAM-INF')) {
        pendingStreamInf = line;
      } else if (line.startsWith('#EXT-X-KEY')) {
        final String method = _keyMethod.firstMatch(line)?.group(1) ?? 'NONE';
        if (method != 'NONE') encrypted = true;
      } else if (line.startsWith('#')) {
        continue;
      } else if (pendingStreamInf != null) {
        variants.add(HlsVariant(
          uri: base.resolve(line),
          bandwidth: int.tryParse(_bandwidth.firstMatch(pendingStreamInf)?.group(1) ?? '') ?? 0,
          resolution: _resolution.firstMatch(pendingStreamInf)?.group(1),
        ));
        pendingStreamInf = null;
      } else {
        segments.add(base.resolve(line));
      }
    }

    return HlsPlaylist(variants: variants, segments: segments, isEncrypted: encrypted);
  }
}
