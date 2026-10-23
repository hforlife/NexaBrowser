/// Mesures de chargement d'une page, pour évaluer le coût de l'interception
/// des requêtes sur les téléphones d'entrée de gamme.
///
/// Affichées dans la console (`flutter run --profile` de préférence : le mode
/// debug fausse les temps). Comparer une même page avec et sans interception
/// (Paramètres → bloqueur et détection vidéo désactivés).
library;

class PageLoadStats {
  final Stopwatch _page = Stopwatch();
  int _requests = 0;
  int _blocked = 0;
  int _dartMicros = 0;
  int _maxDartMicros = 0;

  bool get isRunning => _page.isRunning;

  /// Début du chargement d'une page principale.
  void start() {
    _requests = 0;
    _blocked = 0;
    _dartMicros = 0;
    _maxDartMicros = 0;
    _page
      ..reset()
      ..start();
  }

  /// Une requête a été traitée côté Dart en [micros] microsecondes.
  void recordRequest(int micros, {required bool blocked}) {
    if (!_page.isRunning) return;
    _requests++;
    if (blocked) _blocked++;
    _dartMicros += micros;
    if (micros > _maxDartMicros) _maxDartMicros = micros;
  }

  /// Fin du chargement : retourne le résumé, ou null si aucune mesure n'était en cours.
  String? finish({required String url, required bool interception}) {
    if (!_page.isRunning) return null;
    _page.stop();
    final String dart = interception
        ? 'requêtes interceptées : $_requests (bloquées : $_blocked), '
            'temps Dart total : ${(_dartMicros / 1000).toStringAsFixed(1)} ms, '
            'max : ${(_maxDartMicros / 1000).toStringAsFixed(2)} ms'
        : 'interception désactivée';
    return '[perf] ${_page.elapsedMilliseconds} ms · $dart · $url';
  }
}
