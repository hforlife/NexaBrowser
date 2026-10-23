import 'package:flutter/foundation.dart';

import 'adblock_engine.dart';

/// Moteur par nom de domaine : un ensemble de domaines au format « hosts ».
///
/// La vérification teste le domaine puis ses domaines parents
/// (« a.b.ads.com » → « b.ads.com » → « ads.com ») : quelques recherches dans
/// une table de hachage, très rapide même avec 150 000 entrées.
class DomainSetEngine implements AdblockEngine {
  /// [domains] n'est jamais modifié ensuite : un moteur neuf remplace l'ancien.
  DomainSetEngine(Set<String> domains) : _domains = domains;

  /// Moteur vide (avant le chargement de la première liste).
  DomainSetEngine.empty() : _domains = const <String>{};

  final Set<String> _domains;

  @override
  int get ruleCount => _domains.length;

  @override
  bool shouldBlock(AdblockRequest request) {
    final String host = request.url.host;
    return host.isNotEmpty && isHostInSet(host.toLowerCase(), _domains);
  }

  /// Une liste de domaines n'a pas de règles par site : CSS générique.
  @override
  String cosmeticCss(String pageSite) => genericCosmeticCss;

  @override
  Iterable<String> domainsForNativeRules(int limit) => _domains.take(limit);

  // ------------------------------------------------------- fonctions pures

  /// Lit un fichier « hosts » ou une liste simple de domaines.
  ///
  /// Accepte : « 0.0.0.0 ads.example.com », « 127.0.0.1 x.com », « ads.example.com ».
  /// Ignore les commentaires (#) et les entrées locales.
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
    final RegExp whitespace = RegExp(r'\s+');
    final Set<String> result = <String>{};
    for (final String rawLine in content.split('\n')) {
      final int hash = rawLine.indexOf('#');
      final String line = (hash >= 0 ? rawLine.substring(0, hash) : rawLine).trim();
      if (line.isEmpty) continue;
      final List<String> parts = line.split(whitespace);
      final String domain = (parts.length >= 2 ? parts[1] : parts[0]).toLowerCase();
      if (domain.contains('.') && !ignored.contains(domain)) result.add(domain);
    }
    return result;
  }

  /// Liste embarquée en tête (prioritaire pour la limite iOS), puis la liste complète.
  static Set<String> mergeDomains(Set<String> bundled, Set<String> remote) =>
      <String>{...bundled, ...remote};

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
const String genericCosmeticCss = '''
[id^="google_ads"], [id^="div-gpt-ad"], ins.adsbygoogle, iframe[src*="doubleclick"],
.adsbygoogle, .ad-banner, .ad-container, .ad-slot, .advertisement, .adsbox,
[class*="sponsored-ad"], [aria-label="Advertisement"], [data-ad-slot] {
  display: none !important;
}
''';
