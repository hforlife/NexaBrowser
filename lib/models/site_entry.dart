/// Entrée de favori ou d'historique.
library;

class SiteEntry {
  const SiteEntry({
    this.id,
    required this.url,
    required this.title,
    required this.date,
  });

  final int? id;
  final String url;
  final String title;
  final DateTime date; // date d'ajout (favori) ou de visite (historique)

  String get displayTitle => title.trim().isEmpty ? url : title;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'url': url,
        'title': title,
        'date': date.millisecondsSinceEpoch,
      };

  factory SiteEntry.fromMap(Map<String, Object?> map) => SiteEntry(
        id: map['id'] as int?,
        url: map['url']! as String,
        title: map['title'] as String? ?? '',
        date: DateTime.fromMillisecondsSinceEpoch(map['date']! as int),
      );
}
