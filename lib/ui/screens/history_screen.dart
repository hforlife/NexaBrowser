import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../core/formatters.dart';
import '../../core/url_utils.dart';
import '../../models/site_entry.dart';

/// Historique de navigation (hors onglets privés), avec recherche.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<SiteEntry>> _items;
  String _query = '';
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _items = AppScope.of(context).db.history(search: _query); // premier chargement : pas de setState ici
    }
  }

  // Corps entre accolades : setState ne doit pas recevoir une fonction qui renvoie un Future
  void _reload() => setState(() {
        _items = AppScope.of(context).db.history(search: _query);
      });

  Future<void> _confirmClear() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text("Effacer tout l'historique ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Effacer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AppScope.of(context).db.clearHistory();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique'),
        actions: [
          IconButton(
            tooltip: "Effacer l'historique",
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _confirmClear,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              decoration: const InputDecoration(
                hintText: "Rechercher dans l'historique",
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (String value) {
                _query = value;
                _reload();
              },
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<SiteEntry>>(
        future: _items,
        builder: (BuildContext context, AsyncSnapshot<List<SiteEntry>> snapshot) {
          final List<SiteEntry> items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return Center(
              child: Text(
                snapshot.connectionState == ConnectionState.done ? 'Historique vide' : '',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            );
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (BuildContext context, int i) {
              final SiteEntry entry = items[i];
              return ListTile(
                leading: const Icon(Icons.history),
                title: Text(entry.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${UrlUtils.displayUrl(entry.url)} · ${Formatters.relativeDate(entry.date)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () async {
                    if (entry.id != null) await scope.db.deleteHistory(entry.id!);
                    _reload();
                  },
                ),
                onTap: () {
                  scope.browser.loadUrl(entry.url);
                  Navigator.pop(context);
                },
              );
            },
          );
        },
      ),
    );
  }
}
