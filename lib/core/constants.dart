/// Constantes globales de NexaBrowser.
library;

class AppConstants {
  AppConstants._();

  static const String appName = 'NexaBrowser';

  /// Nombre maximum d'onglets ouverts (chaque WebView consomme de la mémoire).
  static const int maxTabs = 12;

  /// Nombre maximum d'entrées d'historique conservées.
  static const int maxHistoryEntries = 2000;

  /// Liste de blocage distante (format « hosts », licence MIT).
  static const String remoteBlocklistUrl =
      'https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts';

  /// Liste de blocage embarquée dans l'app.
  static const String bundledBlocklistAsset = 'assets/adblock/hosts.txt';

  /// Nom du gestionnaire JS appelé par le script de détection vidéo.
  static const String mediaJsHandler = 'nexaMedia';

  /// Sous-dossier des téléchargements.
  static const String downloadsFolder = 'NexaBrowser';
}

/// Moteurs de recherche disponibles.
enum SearchEngine {
  google('Google', 'https://www.google.com/search?q='),
  duckDuckGo('DuckDuckGo', 'https://duckduckgo.com/?q='),
  bing('Bing', 'https://www.bing.com/search?q=');

  const SearchEngine(this.label, this.queryUrl);

  final String label;
  final String queryUrl;

  static SearchEngine fromName(String? name) => SearchEngine.values.firstWhere(
        (e) => e.name == name,
        orElse: () => SearchEngine.google,
      );
}

/// Raccourcis proposés sur la page d'accueil quand aucun favori n'existe.
class QuickLink {
  const QuickLink(this.title, this.url);

  final String title;
  final String url;
}

const List<QuickLink> defaultQuickLinks = [
  QuickLink('Google', 'https://www.google.com'),
  QuickLink('Wikipédia', 'https://fr.wikipedia.org'),
  QuickLink('Facebook', 'https://m.facebook.com'),
  QuickLink('YouTube', 'https://m.youtube.com'),
  QuickLink('TikTok', 'https://www.tiktok.com'),
  QuickLink('X', 'https://x.com'),
  QuickLink('Jumia', 'https://www.jumia.com'),
  QuickLink('Actualités', 'https://news.google.com/?hl=fr'),
];

/// Domaines dont les vidéos ne doivent PAS être proposées au téléchargement
/// (interdit par le règlement Google Play).
const Set<String> mediaDownloadBlockedDomains = {
  'youtube.com',
  'youtu.be',
  'youtube-nocookie.com',
  'googlevideo.com',
  'ytimg.com',
};
