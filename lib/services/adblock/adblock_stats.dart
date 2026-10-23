import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Compteur cumulé des publicités et traqueurs bloqués, et estimation des
/// données économisées.
///
/// Le compteur augmente pour chaque requête bloquée (souvent des dizaines par
/// page) : l'enregistrement et l'affichage sont regroupés toutes les [flushInterval].
class AdblockStats extends ChangeNotifier {
  static const String _kBlocked = 'adblock_blocked_total';
  static const String _kSince = 'adblock_stats_since';

  /// Taille moyenne retenue pour une ressource bloquée (script, image,
  /// iframe publicitaire). Hypothèse prudente : la taille réelle n'est pas
  /// connue puisque la ressource n'est jamais téléchargée.
  static const int estimatedBytesPerBlockedRequest = 20 * 1024;

  static const Duration flushInterval = Duration(seconds: 5);

  SharedPreferences? _prefs;
  int _blocked = 0;
  DateTime _since = DateTime.now();
  Timer? _flushTimer;

  int get blockedTotal => _blocked;

  /// Début du comptage (installation ou dernière remise à zéro).
  DateTime get since => _since;

  /// Estimation : [blockedTotal] × [estimatedBytesPerBlockedRequest].
  int get estimatedBytesSaved => _blocked * estimatedBytesPerBlockedRequest;

  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _blocked = prefs.getInt(_kBlocked) ?? 0;
    final int? since = prefs.getInt(_kSince);
    if (since == null) {
      await prefs.setInt(_kSince, _since.millisecondsSinceEpoch);
    } else {
      _since = DateTime.fromMillisecondsSinceEpoch(since);
    }
    notifyListeners();
  }

  /// Appelé pour chaque requête bloquée : aucune écriture immédiate.
  void recordBlocked() {
    _blocked++;
    _flushTimer ??= Timer(flushInterval, flush);
  }

  /// Enregistre le compteur et prévient l'interface.
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    notifyListeners();
    await _prefs?.setInt(_kBlocked, _blocked);
  }

  Future<void> reset() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _blocked = 0;
    _since = DateTime.now();
    notifyListeners();
    await _prefs?.setInt(_kBlocked, 0);
    await _prefs?.setInt(_kSince, _since.millisecondsSinceEpoch);
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    super.dispose();
  }
}
