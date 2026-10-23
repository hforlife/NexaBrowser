/// Contrat commun des moteurs de blocage.
///
/// Implémentation actuelle : [DomainSetEngine] (liste de domaines, en Dart).
/// Prévu : moteur Rust `adblock-rust` (Brave) via flutter_rust_bridge, qui
/// gérera les règles EasyList complètes (chemins, exceptions, règles cosmétiques
/// par site). Le reste de l'app ne dépend que de cette interface.
library;

/// Requête soumise au moteur.
class AdblockRequest {
  const AdblockRequest({required this.url, required this.pageSite});

  /// Ressource demandée (script, image, iframe…).
  final Uri url;

  /// Site de la page qui la demande (« site.ml ») : les règles EasyList
  /// distinguent les ressources du site lui-même et celles de tiers.
  final String pageSite;
}

abstract interface class AdblockEngine {
  /// Nombre de règles chargées (affiché dans les paramètres).
  int get ruleCount;

  /// Vrai si la requête doit être bloquée.
  ///
  /// Appelé pour CHAQUE ressource de chaque page, de façon synchrone :
  /// doit répondre en quelques microsecondes.
  bool shouldBlock(AdblockRequest request);

  /// CSS masquant les emplacements publicitaires de la page (règles cosmétiques).
  String cosmeticCss(String pageSite);

  /// Domaines à bloquer nativement là où l'interception est impossible (iOS),
  /// les plus importants en premier, au plus [limit].
  Iterable<String> domainsForNativeRules(int limit);
}
