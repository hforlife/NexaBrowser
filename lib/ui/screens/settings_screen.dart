import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../app_scope.dart';
import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../services/adblock_service.dart';
import '../../services/settings_service.dart';

/// Paramètres du navigateur.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _updatingList = false;

  Future<void> _updateBlocklist(AdblockService adblock) async {
    setState(() => _updatingList = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final int count = await adblock.updateFromRemote();
      messenger.showSnackBar(SnackBar(content: Text('Liste mise à jour : $count domaines bloqués')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Mise à jour impossible : $e')));
    } finally {
      if (mounted) setState(() => _updatingList = false);
    }
  }

  Future<void> _clearBrowsingData() async {
    final AppScope scope = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Effacer les données de navigation ?'),
        content: const Text('Cookies, cache et historique seront supprimés. '
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
    await scope.db.clearHistory();
    messenger.showSnackBar(const SnackBar(content: Text('Données de navigation effacées')));
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final SettingsService settings = scope.settings;
    final AdblockService adblock = scope.adblock;

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListenableBuilder(
        listenable: Listenable.merge([settings, adblock]),
        builder: (BuildContext context, _) => ListView(
          children: [
            const _Section('Recherche'),
            for (final SearchEngine engine in SearchEngine.values)
              RadioListTile<SearchEngine>(
                title: Text(engine.label),
                value: engine,
                groupValue: settings.searchEngine,
                onChanged: (SearchEngine? v) {
                  if (v != null) settings.searchEngine = v;
                },
              ),
            const _Section('Confidentialité et publicités'),
            SwitchListTile(
              secondary: const Icon(Icons.shield_outlined),
              title: const Text('Bloquer les publicités et traqueurs'),
              subtitle: Text('${adblock.domainCount} domaines dans la liste'),
              value: settings.adblockEnabled,
              onChanged: (bool v) => settings.adblockEnabled = v,
            ),
            ListTile(
              leading: const Icon(Icons.update),
              title: const Text('Mettre à jour la liste de blocage'),
              subtitle: Text(adblock.lastUpdate == null
                  ? 'Liste de base intégrée (≈ 1 Mo à télécharger pour la liste complète)'
                  : 'Dernière mise à jour : ${Formatters.relativeDate(adblock.lastUpdate!)}'),
              trailing: _updatingList
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              onTap: _updatingList ? null : () => _updateBlocklist(adblock),
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
