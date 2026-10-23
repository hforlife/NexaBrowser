/// Outils pour interpréter ce que l'utilisateur tape dans la barre d'adresse.
library;

import 'constants.dart';

class UrlUtils {
  UrlUtils._();

  static final RegExp _schemePattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');
  static final RegExp _domainPattern =
      RegExp(r'^(localhost|[\w-]+(\.[\w-]+)+|\d{1,3}(\.\d{1,3}){3})(:\d+)?(/.*)?$');

  /// Transforme la saisie en URL : adresse directe ou recherche.
  ///
  /// « google.com » → https://google.com
  /// « recette tô » → recherche avec le moteur choisi
  static String resolveInput(String input, SearchEngine engine) {
    final String text = input.trim();
    if (text.isEmpty) return '';

    if (_schemePattern.hasMatch(text)) return text;
    if (text.startsWith('about:') || text.startsWith('data:')) return text;

    final bool looksLikeDomain = !text.contains(' ') && _domainPattern.hasMatch(text);
    if (looksLikeDomain) return 'https://$text';

    return '${engine.queryUrl}${Uri.encodeQueryComponent(text)}';
  }

  /// Hôte d'une URL en minuscules, sans « www. » (chaîne vide si invalide).
  static String hostOf(String? url) {
    if (url == null || url.isEmpty) return '';
    final Uri? uri = Uri.tryParse(url);
    final String host = (uri?.host ?? '').toLowerCase();
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  /// Vrai si [host] est [domain] ou l'un de ses sous-domaines.
  static bool hostMatches(String host, String domain) =>
      host == domain || host.endsWith('.$domain');

  /// Vrai si les deux URL appartiennent au même site (deux derniers niveaux
  /// du nom : « video.site.ml » et « www.site.ml » → « site.ml »).
  ///
  /// Approximation volontaire (pas de liste des suffixes publics) : sert
  /// seulement à décider si les cookies du site accompagnent un téléchargement.
  static bool isSameSite(String urlA, String urlB) {
    final String a = siteOf(urlA);
    return a.isNotEmpty && a == siteOf(urlB);
  }

  /// Site d'une URL : « https://m.site.ml/page » → « site.ml » (chaîne vide si invalide).
  static String siteOf(String url) => _siteOfHost(hostOf(url));

  static String _siteOfHost(String host) {
    final List<String> labels = host.split('.');
    return labels.length <= 2 ? host : labels.sublist(labels.length - 2).join('.');
  }

  /// Texte affiché dans la barre d'adresse quand elle n'a pas le focus.
  static String displayUrl(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    final String host = uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host;
    return uri.path.length > 1 ? '$host${uri.path}' : host;
  }

  /// Nom de fichier sûr (pas de caractères interdits, longueur limitée).
  static String sanitizeFileName(String name) {
    String cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
    if (cleaned.isEmpty) cleaned = 'fichier';
    if (cleaned.length > 120) {
      final int dot = cleaned.lastIndexOf('.');
      final String ext = dot > 0 && cleaned.length - dot <= 6 ? cleaned.substring(dot) : '';
      cleaned = cleaned.substring(0, 120 - ext.length) + ext;
    }
    return cleaned;
  }

  /// Devine un nom de fichier à partir de l'URL.
  static String fileNameFromUrl(String url, {String fallbackExtension = ''}) {
    final Uri? uri = Uri.tryParse(url);
    // pathSegments est déjà décodé (%20 → espace)
    String name = uri != null && uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    if (name.isEmpty || !name.contains('.')) {
      final String stamp = DateTime.now().millisecondsSinceEpoch.toString();
      name = 'nexa_$stamp$fallbackExtension';
    }
    return sanitizeFileName(name);
  }
}
