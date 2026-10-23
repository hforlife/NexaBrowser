import 'package:flutter/foundation.dart';

import '../network_info.dart';
import '../settings_service.dart';
import 'adblock_service.dart';

/// Mise à jour automatique de la liste de blocage : au plus une fois par
/// semaine, uniquement sur une connexion non facturée (Wi-Fi), jamais pendant
/// le démarrage.
class BlocklistAutoUpdater {
  BlocklistAutoUpdater({required this.adblock, required this.settings, required this.network});

  final AdblockService adblock;
  final SettingsService settings;
  final NetworkInfo network;

  /// Fréquence de mise à jour.
  static const Duration updateInterval = Duration(days: 7);

  /// Attente après l'ouverture : la première page passe avant la liste.
  static const Duration startupDelay = Duration(seconds: 20);

  /// Vrai si la liste n'a jamais été téléchargée ou date de plus de [updateInterval].
  static bool isDue({required DateTime? lastUpdate, required DateTime now}) =>
      lastUpdate == null || now.difference(lastUpdate) >= updateInterval;

  /// À lancer sans `await` une fois la liste locale chargée.
  Future<void> runAfterStartup() async {
    await Future<void>.delayed(startupDelay);
    await runOnce();
  }

  /// Retourne vrai si une mise à jour a été faite.
  Future<bool> runOnce() async {
    if (!settings.adblockEnabled || !settings.blocklistAutoUpdate) return false;
    if (adblock.isBusy) return false;
    if (!isDue(lastUpdate: adblock.lastUpdate, now: DateTime.now())) return false;
    if (!await network.isUnmetered()) return false;
    try {
      final int count = await adblock.updateFromRemote();
      debugPrint('Adblock : liste mise à jour automatiquement ($count domaines)');
      return true;
    } catch (e) {
      // Nouvel essai au prochain lancement
      debugPrint('Adblock : mise à jour automatique impossible ($e)');
      return false;
    }
  }
}
