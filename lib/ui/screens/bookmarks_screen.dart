import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../core/url_utils.dart';
import '../../models/site_entry.dart';

/// Liste des favoris.
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  late Future<List<SiteEntry>> _items;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _items = AppScope.of(context).db.bookmarks(); // premier chargement : pas de setState ici
    }
  }

  // Corps entre accolades : setState ne doit pas recevoir une fonction qui renvoie un Future
  void _reload() => setState(() {
        _items = AppScope.of(context).db.bookmarks();
      });

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Favoris')),
      body: FutureBuilder<List<SiteEntry>>(
        future: _items,
        builder: (BuildContext context, AsyncSnapshot<List<SiteEntry>> snapshot) {
          final List<SiteEntry> items = snapshot.data ?? const [];
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (items.isEmpty) {
            return const _EmptyState(
              icon: Icons.star_border,
              text: 'Aucun favori.\nMenu ⋮ → « Ajouter aux favoris » sur une page.',
            );
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (BuildContext context, int i) {
              final SiteEntry entry = items[i];
              return Dismissible(
                key: ValueKey<String>(entry.url),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete_outline),
                ),
                onDismissed: (_) async {
                  await scope.db.removeBookmark(entry.url);
                  _reload();
                },
                child: ListTile(
                  leading: const Icon(Icons.star_rounded),
                  title: Text(entry.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(UrlUtils.displayUrl(entry.url), maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    scope.browser.loadUrl(entry.url);
                    Navigator.pop(context);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Message affiché quand une liste est vide.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
