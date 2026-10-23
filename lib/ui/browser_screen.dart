import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../core/formatters.dart';
import '../core/url_utils.dart';
import '../services/download_service.dart';
import '../services/settings_service.dart';
import '../state/browser_controller.dart';
import '../state/browser_tab.dart';
import 'screens/bookmarks_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tabs_screen.dart';
import 'widgets/address_bar.dart';
import 'widgets/media_sheet.dart';
import 'widgets/tab_web_view.dart';

/// Écran principal du navigateur.
class BrowserScreen extends StatelessWidget {
  const BrowserScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final BrowserController browser = AppScope.of(context).browser;

    return ListenableBuilder(
      listenable: browser,
      builder: (BuildContext context, _) {
        final BrowserTab tab = browser.current;
        return PopScope(
          canPop: false,
          // Bouton retour Android : page précédente, puis accueil, puis sortie
          onPopInvokedWithResult: (bool didPop, Object? result) async {
            if (didPop) return;
            final bool handled = await browser.handleSystemBack();
            if (!handled) await SystemNavigator.pop();
          },
          child: Scaffold(
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  AddressBar(
                    tab: tab,
                    onSubmit: browser.openInput,
                    onReloadOrStop: browser.reloadOrStop,
                  ),
                  _ProgressLine(tab: tab),
                  Expanded(
                    child: IndexedStack(
                      index: browser.currentIndex,
                      children: [
                        for (final BrowserTab t in browser.tabs)
                          TabWebView(
                            key: ValueKey<int>(t.id),
                            tab: t,
                            onDownloadRequested: ({
                              required String url,
                              required String referer,
                              String? suggestedName,
                              String? mimeType,
                              int? contentLength,
                            }) =>
                                _confirmDownload(
                              context,
                              url: url,
                              referer: referer,
                              suggestedName: suggestedName,
                              mimeType: mimeType,
                              contentLength: contentLength,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            floatingActionButton: _MediaButton(tab: tab),
            bottomNavigationBar: _BottomBar(browser: browser, tab: tab),
          ),
        );
      },
    );
  }

  /// Un lien de fichier a été touché : on demande confirmation.
  Future<void> _confirmDownload(
    BuildContext context, {
    required String url,
    required String referer,
    String? suggestedName,
    String? mimeType,
    int? contentLength,
  }) async {
    final DownloadService downloads = AppScope.of(context).downloads;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final String name = UrlUtils.sanitizeFileName(
      (suggestedName != null && suggestedName.isNotEmpty)
          ? suggestedName
          : UrlUtils.fileNameFromUrl(url),
    );
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        icon: const Icon(Icons.download_rounded),
        title: const Text('Télécharger ce fichier ?'),
        content: Text(
          contentLength != null && contentLength > 0
              ? '$name\n${Formatters.bytes(contentLength)}'
              : name,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Télécharger')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // Lien touché dans la page : la WebView aurait envoyé les cookies du site
      await downloads.enqueue(url: url, fileName: name, referer: referer, mimeType: mimeType);
    } on DownloadException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    messenger.showSnackBar(SnackBar(
      content: Text('Téléchargement de « $name »'),
      action: SnackBarAction(
        label: 'Voir',
        onPressed: () => navigator.push(
          MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()),
        ),
      ),
    ));
  }
}

/// Fine barre de progression sous la barre d'adresse.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.tab});

  final BrowserTab tab;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tab,
      builder: (BuildContext context, _) => SizedBox(
        height: 2,
        child: tab.isLoading && tab.progress < 1
            ? LinearProgressIndicator(value: tab.progress > 0 ? tab.progress : null)
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// Bouton flottant affiché quand des vidéos sont détectées.
class _MediaButton extends StatelessWidget {
  const _MediaButton({required this.tab});

  final BrowserTab tab;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tab,
      builder: (BuildContext context, _) {
        final int count = tab.media.length;
        if (count == 0 || tab.isStartPage) return const SizedBox.shrink();
        return FloatingActionButton.small(
          tooltip: 'Vidéos détectées',
          onPressed: () => MediaSheet.show(context, tab),
          child: Badge(
            label: Text('$count'),
            child: const Icon(Icons.download_for_offline_outlined),
          ),
        );
      },
    );
  }
}

/// Barre du bas : précédent, suivant, accueil, onglets, menu.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.browser, required this.tab});

  final BrowserController browser;
  final BrowserTab tab;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tab,
      builder: (BuildContext context, _) => BottomAppBar(
        height: 56,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              tooltip: 'Précédent',
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: tab.isStartPage ? null : browser.goBack,
            ),
            IconButton(
              tooltip: 'Suivant',
              icon: const Icon(Icons.arrow_forward_ios_rounded),
              onPressed: tab.canGoForward ? browser.goForward : null,
            ),
            IconButton(
              tooltip: 'Accueil',
              icon: const Icon(Icons.home_outlined),
              onPressed: browser.goHome,
            ),
            _TabsButton(browser: browser),
            IconButton(
              tooltip: 'Menu',
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showMenu(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final AppScope scope = AppScope.of(context);
    final bool bookmarked = !tab.isStartPage && await scope.db.isBookmarked(tab.url);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _MainMenu(
        browser: browser,
        tab: tab,
        bookmarked: bookmarked,
        rootContext: context,
      ),
    );
  }
}

class _TabsButton extends StatelessWidget {
  const _TabsButton({required this.browser});

  final BrowserController browser;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int count = browser.tabs.length;
    return IconButton(
      tooltip: 'Onglets',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const TabsScreen()),
      ),
      icon: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: scheme.onSurface, width: 1.8),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          count > 99 ? ':)' : '$count',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// Menu principal (feuille du bas).
class _MainMenu extends StatelessWidget {
  const _MainMenu({
    required this.browser,
    required this.tab,
    required this.bookmarked,
    required this.rootContext,
  });

  final BrowserController browser;
  final BrowserTab tab;
  final bool bookmarked;
  final BuildContext rootContext; // contexte de l'écran (survit à la fermeture du menu)

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final SettingsService settings = scope.settings;
    final DownloadService downloads = scope.downloads;

    void close() => Navigator.of(context).pop();
    void push(Widget screen) {
      close();
      Navigator.of(rootContext).push(MaterialPageRoute<void>(builder: (_) => screen));
    }

    void newTab({bool private = false}) {
      close();
      if (browser.newTab(isPrivate: private) == null) {
        ScaffoldMessenger.of(rootContext).showSnackBar(
          const SnackBar(content: Text("Nombre maximum d'onglets atteint")),
        );
      }
    }

    return ListenableBuilder(
      listenable: settings,
      builder: (BuildContext context, _) => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_box_outlined),
              title: const Text('Nouvel onglet'),
              onTap: newTab,
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Nouvel onglet privé'),
              onTap: () => newTab(private: true),
            ),
            if (!tab.isStartPage)
              ListTile(
                leading: Icon(bookmarked ? Icons.star : Icons.star_border),
                title: Text(bookmarked ? 'Retirer des favoris' : 'Ajouter aux favoris'),
                onTap: () async {
                  close();
                  if (bookmarked) {
                    await scope.db.removeBookmark(tab.url);
                  } else {
                    await scope.db.addBookmark(tab.url, tab.title);
                  }
                  if (!rootContext.mounted) return;
                  ScaffoldMessenger.of(rootContext).showSnackBar(SnackBar(
                    content: Text(bookmarked ? 'Retiré des favoris' : 'Ajouté aux favoris'),
                  ));
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.bookmarks_outlined),
              title: const Text('Favoris'),
              onTap: () => push(const BookmarksScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Historique'),
              onTap: () => push(const HistoryScreen()),
            ),
            ListenableBuilder(
              listenable: downloads,
              builder: (BuildContext context, _) => ListTile(
                leading: Badge(
                  isLabelVisible: downloads.activeCount > 0,
                  label: Text('${downloads.activeCount}'),
                  child: const Icon(Icons.download_outlined),
                ),
                title: const Text('Téléchargements'),
                onTap: () => push(const DownloadsScreen()),
              ),
            ),
            const Divider(),
            SwitchListTile(
              secondary: const Icon(Icons.desktop_windows_outlined),
              title: const Text('Version ordinateur'),
              value: settings.desktopMode,
              onChanged: (bool v) => settings.desktopMode = v,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.data_saver_on_outlined),
              title: const Text('Économie de données'),
              subtitle: const Text('Ne charge pas les images'),
              value: settings.dataSaver,
              onChanged: (bool v) => settings.dataSaver = v,
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Paramètres'),
              onTap: () => push(const SettingsScreen()),
            ),
          ],
        ),
      ),
    );
  }
}
