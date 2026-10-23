import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../app_scope.dart';
import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../services/adblock/adblock_service.dart';
import '../../services/adblock/adblock_stats.dart';
import '../../services/settings_service.dart';
import 'adblock_exceptions_screen.dart';

/// Paramètres du navigateur.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _updateBlocklist(AdblockService adblock) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final int count = await adblock.updateFromRemote();
      messenger.showSnackBar(
        SnackBar(content: Text('Liste mise à jour : ${Formatters.count(count)} domaines bloqués')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Mise à jour impossible : $e')));
    }
  }

  Future<void> _resetStats(AdblockStats stats) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Remettre les statistiques à zéro ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remettre à zéro')),
        ],
      ),
    );
    if (ok == true) await stats.reset();
  }

  Future<void> _clearBrowsingData() async {
    final AppScope scope = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Effacer les données de navigation ?'),
        content: const Text('Cookies, cache, données des sites et historique seront supprimés. '
            'Vous serez déconnecté des sites.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Effacer')),
        ],
      ),
    );
    if (ok != true) return;
    await CookieManager.instance().deleteAllCookies();
    await InAppWebViewController.clearAllCache();
    // localStorage, IndexedDB, bases Web SQL des sites
    await WebStorageManager.instance().deleteAllData();
    await scope.db.clearHistory();
    messenger.showSnackBar(const SnackBar(content: Text('Données de navigation effacées')));
  }

  String _blocklistSubtitle(AdblockService adblock) {
    if (adblock.isLoadingFullList) return 'Chargement de la liste complète…';
    if (adblock.isUpdating) return 'Téléchargement de la liste…';
    final DateTime? lastUpdate = adblock.lastUpdate;
    if (lastUpdate == null) {
      return 'Liste de base intégrée (≈ 1 Mo à télécharger pour la liste complète)';
    }
    return 'Dernière mise à jour : ${Formatters.relativeDate(lastUpdate)}';
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final SettingsService settings = scope.settings;
    final AdblockService adblock = scope.adblock;

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListenableBuilder(
        listenable: Listenable.merge([settings, adblock, adblock.stats, adblock.exceptions]),
        builder: (BuildContext context, _) => ListView(
          children: [
            const _Section('Recherche'),
            RadioGroup<SearchEngine>(
              groupValue: settings.searchEngine,
              onChanged: (SearchEngine? v) {
                if (v != null) settings.searchEngine = v;
              },
              child: Column(
                children: [
                  for (final SearchEngine engine in SearchEngine.values)
                    RadioListTile<SearchEngine>(title: Text(engine.label), value: engine),
                ],
              ),
            ),
            const _Section('Confidentialité et publicités'),
            SwitchListTile(
              secondary: const Icon(Icons.shield_outlined),
              title: const Text('Bloquer les publicités et traqueurs'),
              subtitle: Text('${Formatters.count(adblock.ruleCount)} domaines dans la liste'),
              value: settings.adblockEnabled,
              onChanged: (bool v) => settings.adblockEnabled = v,
            ),
            ListTile(
              leading: const Icon(Icons.update),
              title: const Text('Mettre à jour la liste de blocage'),
              subtitle: Text(_blocklistSubtitle(adblock)),
              trailing: adblock.isBusy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              onTap: adblock.isBusy ? null : () => _updateBlocklist(adblock),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.wifi),
              title: const Text('Mise à jour automatique'),
              subtitle: const Text('Une fois par semaine, en Wi-Fi uniquement'),
              value: settings.blocklistAutoUpdate,
              onChanged: settings.adblockEnabled ? (bool v) => settings.blocklistAutoUpdate = v : null,
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_check),
              title: const Text('Sites autorisés'),
              subtitle: Text(adblock.exceptions.sites.isEmpty
                  ? 'Aucun : publicités bloquées partout'
                  : '${adblock.exceptions.sites.length} site(s) où les publicités sont autorisées'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AdblockExceptionsScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.insights_outlined),
              title: Text('${Formatters.count(adblock.stats.blockedTotal)} publicités et traqueurs bloqués'),
              subtitle: Text('Depuis le ${Formatters.date(adblock.stats.since)} · '
                  '≈ ${Formatters.bytes(adblock.stats.estimatedBytesSaved)} économisés (estimation)'),
              trailing: IconButton(
                tooltip: 'Remettre à zéro',
                icon: const Icon(Icons.restart_alt),
                onPressed: () => _resetStats(adblock.stats),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('Effacer les données de navigation'),
              onTap: _clearBrowsingData,
            ),
            const _Section('Données mobiles'),
            SwitchListTile(
              secondary: const Icon(Icons.data_saver_on_outlined),
              title: const Text('Économie de données'),
              subtitle: const Text('Les images ne sont pas chargées, les vidéos ne démarrent pas seules'),
              value: settings.dataSaver,
              onChanged: (bool v) => settings.dataSaver = v,
            ),
            const _Section('Vidéos'),
            SwitchListTile(
              secondary: const Icon(Icons.video_library_outlined),
              title: const Text('Détecter les vidéos'),
              subtitle: const Text('Affiche un bouton pour télécharger les vidéos des pages'),
              value: settings.mediaDetection,
              onChanged: (bool v) => settings.mediaDetection = v,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.play_circle_outline),
              title: const Text('Lecture automatique des vidéos'),
              subtitle: Text(settings.dataSaver
                  ? "Désactivée par l'économie de données"
                  : 'Consomme des données sans que vous touchiez la vidéo'),
              value: settings.autoplayVideos,
              onChanged: settings.dataSaver ? null : (bool v) => settings.autoplayVideos = v,
            ),
            const _Section('Affichage'),
            SwitchListTile(
              secondary: const Icon(Icons.desktop_windows_outlined),
              title: const Text('Version ordinateur par défaut'),
              value: settings.desktopMode,
              onChanged: (bool v) => settings.desktopMode = v,
            ),
            const _Section('À propos'),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text(AppConstants.appName),
              subtitle: Text('Version 0.1.0'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );
}
