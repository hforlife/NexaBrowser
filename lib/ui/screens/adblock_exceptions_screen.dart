import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/adblock/site_exceptions.dart';

/// Sites sur lesquels le bloqueur est désactivé.
class AdblockExceptionsScreen extends StatelessWidget {
  const AdblockExceptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final SiteExceptions exceptions = AppScope.of(context).adblock.exceptions;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Sites autorisés')),
      body: ListenableBuilder(
        listenable: exceptions,
        builder: (BuildContext context, _) {
          final List<String> sites = exceptions.sites;
          if (sites.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Aucun site autorisé.\nLes publicités sont bloquées partout.\n\n'
                  'Pour autoriser un site : touchez le bouclier dans la barre d\'adresse.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: sites.length,
            itemBuilder: (BuildContext context, int i) => ListTile(
              leading: Icon(Icons.remove_moderator_outlined, color: scheme.outline),
              title: Text(sites[i]),
              subtitle: const Text('Publicités autorisées'),
              trailing: IconButton(
                tooltip: 'Bloquer de nouveau',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => exceptions.remove(sites[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}
