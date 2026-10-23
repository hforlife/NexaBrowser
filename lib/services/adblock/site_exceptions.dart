import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sites sur lesquels l'utilisateur a désactivé le bloqueur
/// (bouclier → « Bloquer les publicités sur ce site »).
///
/// Clé = site (« site.ml ») : l'exception couvre www.site.ml, m.site.ml, etc.
class SiteExceptions extends ChangeNotifier {
  static const String _key = 'adblock_site_exceptions';

  final Set<String> _sites = <String>{};
  SharedPreferences? _prefs;

  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _sites
      ..clear()
      ..addAll(prefs.getStringList(_key) ?? const <String>[]);
    notifyListeners();
  }

  /// Sites autorisés, par ordre alphabétique.
  List<String> get sites => _sites.toList()..sort();

  /// Appelé pour chaque requête : simple recherche dans un ensemble.
  bool contains(String site) => site.isNotEmpty && _sites.contains(site);

  Future<void> add(String site) => _update(() => _sites.add(site));

  Future<void> remove(String site) => _update(() => _sites.remove(site));

  /// Retourne vrai si le site est désormais autorisé (bloqueur désactivé).
  Future<bool> toggle(String site) async {
    final bool nowExcepted = !_sites.contains(site);
    await (nowExcepted ? add(site) : remove(site));
    return nowExcepted;
  }

  Future<void> _update(bool Function() change) async {
    if (!change()) return;
    notifyListeners();
    await _prefs?.setStringList(_key, _sites.toList());
  }
}
