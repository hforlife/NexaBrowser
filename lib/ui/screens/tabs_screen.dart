import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../core/url_utils.dart';
import '../../state/browser_controller.dart';
import '../../state/browser_tab.dart';

/// Vue de tous les onglets ouverts.
class TabsScreen extends StatelessWidget {
  const TabsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final BrowserController browser = AppScope.of(context).browser;

    return ListenableBuilder(
      listenable: browser,
      builder: (BuildContext context, _) {
        final List<BrowserTab> tabs = browser.tabs;
        final bool hasPrivate = tabs.any((t) => t.isPrivate);
        return Scaffold(
          appBar: AppBar(
            title: Text('${tabs.length} onglet${tabs.length > 1 ? 's' : ''}'),
            actions: [
              if (hasPrivate)
                IconButton(
                  tooltip: 'Fermer les onglets privés',
                  icon: const Icon(Icons.privacy_tip_outlined),
                  onPressed: browser.closePrivateTabs,
                ),
            ],
          ),
          body: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: tabs.length,
            itemBuilder: (BuildContext context, int i) {
              final BrowserTab tab = tabs[i];
              final bool selected = i == browser.currentIndex;
              return Card(
                clipBehavior: Clip.antiAlias,
                color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
                child: ListTile(
                  leading: Icon(tab.isPrivate ? Icons.privacy_tip_outlined : Icons.public),
                  title: Text(tab.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: tab.isStartPage
                      ? null
                      : Text(UrlUtils.displayUrl(tab.url), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    tooltip: "Fermer l'onglet",
                    icon: const Icon(Icons.close),
                    onPressed: () => browser.closeTab(tab),
                  ),
                  onTap: () {
                    browser.switchTo(i);
                    Navigator.pop(context);
                  },
                ),
              );
            },
          ),
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.small(
                heroTag: 'private',
                tooltip: 'Nouvel onglet privé',
                onPressed: () => _open(context, browser, isPrivate: true),
                child: const Icon(Icons.privacy_tip_outlined),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.extended(
                heroTag: 'new',
                onPressed: () => _open(context, browser),
                icon: const Icon(Icons.add),
                label: const Text('Nouvel onglet'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _open(BuildContext context, BrowserController browser, {bool isPrivate = false}) {
    if (browser.newTab(isPrivate: isPrivate) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Nombre maximum d'onglets atteint")),
      );
      return;
    }
    Navigator.pop(context);
  }
}
