import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';
import 'adblock_engine.dart';
import 'adblock_stats.dart';
import 'domain_set_engine.dart';
import 'site_exceptions.dart';

/// Bloqueur de publicités : point d'entrée unique pour le reste de l'app.
///
/// Rôle : charger et mettre à jour les listes, construire le moteur
/// ([AdblockEngine]), appliquer les exceptions par site et compter les blocages.
/// Le moteur peut être remplacé (Rust) sans modifier ce qui l'utilise.
///
/// Chargement en deux temps pour ne pas retarder l'ouverture de l'app :
///  1. la liste embarquée (≈ 100 domaines majeurs), quasi instantanée ;
///  2. la liste complète téléchargée, lue et analysée dans un isolate séparé.
class AdblockService extends ChangeNotifier {
  AdblockService({required this.exceptions, required this.stats});

  /// Sites où le bloqueur est désactivé par l'utilisateur.
  final SiteExceptions exceptions;

  /// Compteurs cumulés.
  final AdblockStats stats;

  static const String _remoteFileName = 'blocklist_hosts.txt';

  /// Nombre max de règles WebKit (iOS) : au-delà, la compilation est lente.
  static const int _maxIosRules = 3000;

  /// En dessous de ce nombre de domaines, une liste téléchargée est jugée invalide.
  static const int _minRemoteDomains = 1000;

  static const Duration _downloadTimeout = Duration(seconds: 60);

  /// Moteur actif. Remplacé d'un bloc (jamais modifié en place) pour que
  /// les requêtes en cours voient toujours une liste cohérente.
  AdblockEngine _engine = DomainSetEngine.empty();
  DateTime? _lastUpdate;
  bool _loadingFullList = false;
  bool _updating = false;

  int get ruleCount => _engine.ruleCount;
  DateTime? get lastUpdate => _lastUpdate;

  /// Vrai pendant la lecture de la liste complète au démarrage.
  bool get isLoadingFullList => _loadingFullList;

  /// Vrai pendant un téléchargement de la liste.
  bool get isUpdating => _updating;

  bool get isBusy => _loadingFullList || _updating;

  // ------------------------------------------------------------- blocage

  /// Vrai si le bloqueur s'applique à ce site (pas d'exception utilisateur).
  bool isActiveOn(String pageSite) => !exceptions.contains(pageSite);

  /// Décision pour une ressource de la page [pageSite]. Compte les blocages.
  /// Appelé pour CHAQUE requête : uniquement des recherches en mémoire.
  bool shouldBlock(Uri url, {required String pageSite}) {
    if (exceptions.contains(pageSite)) return false;
    final bool blocked = _engine.shouldBlock(AdblockRequest(url: url, pageSite: pageSite));
    if (blocked) stats.recordBlocked();
    return blocked;
  }

  /// CSS cosmétique à injecter, ou null si le site est autorisé.
  String? cosmeticCssFor(String pageSite) =>
      isActiveOn(pageSite) ? _engine.cosmeticCss(pageSite) : null;

  /// Règles de blocage natives pour iOS (WebKit ne permet pas d'intercepter
  /// les requêtes). Limitées aux [_maxIosRules] domaines les plus importants.
  List<ContentBlocker> iosContentBlockers() {
    return _engine.domainsForNativeRules(_maxIosRules).map((String domain) {
      final String escaped = RegExp.escape(domain);
      return ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: '^https?://([^/]+\\.)?$escaped[:/]'),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      );
    }).toList();
  }

  // ------------------------------------------------------------- listes

  /// Charge la liste embarquée, puis la liste téléchargée si elle existe.
  ///
  /// Peut être lancé sans `await` : le blocage fonctionne dès la fin de
  /// l'étape 1, la liste complète prend le relais quand elle est prête.
  Future<void> load() async {
    final Set<String> bundled = await _bundledDomains();
    _engine = DomainSetEngine(bundled);
    notifyListeners();

    final File remote = await _remoteFile();
    if (!await remote.exists()) return;

    _loadingFullList = true;
    notifyListeners();
    try {
      final String path = remote.path;
      _engine = DomainSetEngine(await Isolate.run(() => _readAndMerge(path, bundled)));
      _lastUpdate = await remote.lastModified();
    } catch (e) {
      // Fichier illisible : on garde la liste embarquée
      debugPrint('Adblock : lecture de la liste complète impossible ($e)');
    } finally {
      _loadingFullList = false;
      notifyListeners();
    }
  }

  /// Télécharge la liste complète (~150 000 domaines). Retourne le nombre de règles.
  Future<int> updateFromRemote() async {
    if (_updating) throw StateError('Mise à jour déjà en cours');
    _updating = true;
    notifyListeners();
    try {
      final http.Response response =
          await http.get(Uri.parse(AppConstants.remoteBlocklistUrl)).timeout(_downloadTimeout);
      if (response.statusCode != 200) {
        throw HttpException('Erreur ${response.statusCode}');
      }
      final String body = response.body;
      final Set<String> parsed = await Isolate.run(() => DomainSetEngine.parseHosts(body));
      if (parsed.length < _minRemoteDomains) {
        throw const FormatException('Liste reçue invalide');
      }
      await (await _remoteFile()).writeAsString(body);

      final Set<String> bundled = await _bundledDomains();
      _engine = DomainSetEngine(await Isolate.run(() => DomainSetEngine.mergeDomains(bundled, parsed)));
      _lastUpdate = DateTime.now();
      return _engine.ruleCount;
    } finally {
      _updating = false;
      notifyListeners();
    }
  }

  Future<Set<String>> _bundledDomains() async =>
      DomainSetEngine.parseHosts(await rootBundle.loadString(AppConstants.bundledBlocklistAsset));

  Future<File> _remoteFile() async {
    final Directory dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _remoteFileName));
  }

  /// Exécuté dans un isolate : lit le fichier et fusionne avec la liste embarquée.
  static Set<String> _readAndMerge(String path, Set<String> bundled) => DomainSetEngine.mergeDomains(
        bundled,
        DomainSetEngine.parseHosts(File(path).readAsStringSync()),
      );
}
