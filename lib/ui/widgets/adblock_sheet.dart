import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../core/formatters.dart';
import '../../services/adblock/adblock_service.dart';
import '../../services/adblock/adblock_stats.dart';
import '../../state/browser_tab.dart';
import '../screens/adblock_exceptions_screen.dart';

/// Feuille ouverte depuis le bouclier : blocage sur ce site, statistiques.
class AdblockSheet extends StatelessWidget {
  const AdblockSheet({super.key, required this.tab});

  final BrowserTab tab;

  static Future<void> show(BuildContext context, BrowserTab tab) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => AdblockSheet(tab: tab),
      );

  /// Change l'exception du site puis recharge la page pour l'appliquer.
  Future<void> _toggleSite(BuildContext context, AdblockService adblock) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool nowAllowed = await adblock.exceptions.toggle(tab.site);
    await tab.webController?.reload();
    messenger.showSnackBar(SnackBar(
      content: Text(nowAllowed
          ? 'Publicités autorisées sur ${tab.site}'
          : 'Publicités de nouveau bloquées sur ${tab.site}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final AdblockService adblock = AppScope.of(context).adblock;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: Listenable.merge([tab, adblock.exceptions, adblock.stats]),
      builder: (BuildContext context, _) {
        final bool active = adblock.isActiveOn(tab.site);
        final AdblockStats stats = adblock.stats;
        final int count = tab.blockedCount;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: Icon(
                    active ? Icons.shield : Icons.remove_moderator_outlined,
                    size: 36,
                    color: active ? scheme.primary : scheme.outline,
                  ),
                  title: Text(tab.site, style: text.titleMedium),
                  subtitle: Text(active
                      ? '$count publicité${count > 1 ? 's' : ''} et traqueur${count > 1 ? 's' : ''} '
                          'bloqué${count > 1 ? 's' : ''} sur cette page'
                      : 'Bloqueur désactivé sur ce site'),
                ),
                SwitchListTile(
                  title: const Text('Bloquer les publicités sur ce site'),
                  subtitle: const Text("Désactivez-le si la page s'affiche mal ou refuse les bloqueurs"),
                  value: active,
                  onChanged: tab.site.isEmpty ? null : (_) => _toggleSite(context, adblock),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.insights_outlined),
                  title: Text('${Formatters.count(stats.blockedTotal)} bloqués '
                      'depuis le ${Formatters.date(stats.since)}'),
                  subtitle: Text('≈ ${Formatters.bytes(stats.estimatedBytesSaved)} de données économisées (estimation)'),
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_add_check),
                  title: const Text('Sites autorisés'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    final NavigatorState navigator = Navigator.of(context);
                    navigator.pop();
                    navigator.push(MaterialPageRoute<void>(builder: (_) => const AdblockExceptionsScreen()));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
