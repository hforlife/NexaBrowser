import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';

/// Bloqueur de publicités par nom de domaine.
///
/// La liste est un ensemble de domaines (format « hosts ») : la vérification
/// d'une requête teste le domaine et ses domaines parents → très rapide,
/// même avec 150 000 entrées.
class AdblockService extends ChangeNotifier {
  static const String _remoteFileName = 'blocklist_hosts.txt';

  /// Nombre max de règles WebKit (iOS) : au-delà, la compilation est lente.
  static const int _maxIosRules = 3000;

  final Set<String> _domains = <String>{};
  DateTime? _lastUpdate;

  int get domainCount => _domains.length;
  DateTime? get lastUpdate => _lastUpdate;

  /// Charge la liste téléchargée si elle existe, sinon la liste embarquée.
  Future<void> load() async {
    final File remote = await _remoteFile();
    if (await remote.exists()) {
      _domains
        ..clear()
        ..addAll(parseHosts(await remote.readAsString()));
      _lastUpdate = await remote.lastModified();
    }
    // La liste embarquée est toujours ajoutée (domaines publicitaires majeurs)
    _domains.addAll(parseHosts(await rootBundle.loadString(AppConstants.bundledBlocklistAsset)));
    notifyListeners();
  }

  /// Télécharge la liste complète (~150 000 domaines). Retourne le nombre de domaines.
  Future<int> updateFromRemote() async {
    final http.Response response = await http
        .get(Uri.parse(AppConstants.remoteBlocklistUrl))
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw HttpException('Erreur ${response.statusCode}');
    }
    final Set<String> parsed = parseHosts(response.body);
    if (parsed.length < 1000) {
      throw const FormatException('Liste reçue invalide');
    }
    await (await _remoteFile()).writeAsString(response.body);
    _domains
      ..clear()
      ..addAll(parsed)
      ..addAll(parseHosts(await rootBundle.loadString(AppConstants.bundledBlocklistAsset)));
    _lastUpdate = DateTime.now();
    notifyListeners();
    return _domains.length;
  }

  /// Vrai si l'hôte (ou l'un de ses domaines parents) est bloqué.
  bool isBlockedHost(String host) => isHostInSet(host.toLowerCase(), _domains);

  bool isBlockedUrl(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    return isBlockedHost(uri.host);
  }

  /// Règles de blocage natives pour iOS (WebKit ne permet pas d'intercepter
  /// les requêtes). Limitées aux [_maxIosRules] premiers domaines.
  List<ContentBlocker> iosContentBlockers() {
    return _domains.take(_maxIosRules).map((String domain) {
      final String escaped = RegExp.escape(domain);
      return ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: '^https?://([^/]+\\.)?$escaped[:/]'),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      );
    }).toList();
  }

  Future<File> _remoteFile() async {
    final Directory dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _remoteFileName));
  }

  // ------------------------------------------------------- fonctions pures

  /// Lit un fichier « hosts » ou une liste simple de domaines.
  ///
  /// Accepte : « 0.0.0.0 ads.example.com », « 127.0.0.1 x.com », « ads.example.com ».
  /// Ignore les commentaires (#) et les entrées locales.
  @visibleForTesting
  static Set<String> parseHosts(String content) {
    const Set<String> ignored = {
      'localhost',
      'localhost.localdomain',
      'local',
      'broadcasthost',
      'ip6-localhost',
      'ip6-loopback',
      '0.0.0.0',
    };
    final Set<String> result = <String>{};
    for (final String rawLine in content.split('\n')) {
      final int hash = rawLine.indexOf('#');
      final String line = (hash >= 0 ? rawLine.substring(0, hash) : rawLine).trim();
      if (line.isEmpty) continue;
      final List<String> parts = line.split(RegExp(r'\s+'));
      final String domain = (parts.length >= 2 ? parts[1] : parts[0]).toLowerCase();
      if (domain.contains('.') && !ignored.contains(domain)) result.add(domain);
    }
    return result;
  }

  /// Teste « a.b.ads.com » puis « b.ads.com » puis « ads.com »…
  @visibleForTesting
  static bool isHostInSet(String host, Set<String> domains) {
    String current = host;
    while (true) {
      if (domains.contains(current)) return true;
      final int dot = current.indexOf('.');
      if (dot == -1 || dot == current.length - 1) return false;
      current = current.substring(dot + 1);
      if (!current.contains('.')) return false; // on ne teste pas les TLD seuls (« com »)
    }
  }
}

/// CSS injecté pour masquer les emplacements publicitaires restés vides.
const String cosmeticAdblockCss = '''
[id^="google_ads"], [id^="div-gpt-ad"], ins.adsbygoogle, iframe[src*="doubleclick"],
.adsbygoogle, .ad-banner, .ad-container, .ad-slot, .advertisement, .adsbox,
[class*="sponsored-ad"], [aria-label="Advertisement"], [data-ad-slot] {
  display: none !important;
}
''';
