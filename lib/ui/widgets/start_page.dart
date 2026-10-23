import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../core/constants.dart';
import '../../core/url_utils.dart';
import '../../models/site_entry.dart';

/// Page d'accueil d'un onglet : recherche + accès rapides (favoris).
class StartPage extends StatefulWidget {
  const StartPage({super.key, required this.isPrivate, required this.onSubmit});

  final bool isPrivate;
  final ValueChanged<String> onSubmit;

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  static const int _maxTiles = 8;

  final TextEditingController _search = TextEditingController();
  Future<List<SiteEntry>>? _bookmarks;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bookmarks ??= AppScope.of(context).db.bookmarks();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return ColoredBox(
      color: widget.isPrivate ? scheme.inverseSurface : scheme.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 48, 20, 24),
        children: [
          Icon(
            widget.isPrivate ? Icons.privacy_tip_outlined : Icons.travel_explore_rounded,
            size: 56,
            color: widget.isPrivate ? scheme.onInverseSurface : scheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            widget.isPrivate ? 'Navigation privée' : AppConstants.appName,
            textAlign: TextAlign.center,
            style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: widget.isPrivate ? scheme.onInverseSurface : scheme.onSurface,
            ),
          ),
          if (widget.isPrivate) ...[
            const SizedBox(height: 8),
            Text(
              "Les pages visitées ne sont pas ajoutées à l'historique et ne sont pas mises en cache.\n"
              "Les cookies et connexions aux sites restent partagés avec vos autres onglets.",
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
            ),
          ],
          const SizedBox(height: 24),
          TextField(
            controller: _search,
            textInputAction: TextInputAction.go,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'Rechercher ou saisir une adresse',
              prefixIcon: Icon(Icons.search),
            ),
            onSubmitted: widget.onSubmit,
          ),
          const SizedBox(height: 28),
          FutureBuilder<List<SiteEntry>>(
            future: _bookmarks,
            builder: (BuildContext context, AsyncSnapshot<List<SiteEntry>> snapshot) {
              final List<SiteEntry> saved = snapshot.data ?? const [];
              final List<QuickLink> links = saved.isNotEmpty
                  ? saved.take(_maxTiles).map((e) => QuickLink(e.displayTitle, e.url)).toList()
                  : defaultQuickLinks;
              return _QuickLinksGrid(
                links: links,
                onTap: widget.onSubmit,
                foreground: widget.isPrivate ? scheme.onInverseSurface : scheme.onSurface,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QuickLinksGrid extends StatelessWidget {
  const _QuickLinksGrid({required this.links, required this.onTap, required this.foreground});

  final List<QuickLink> links;
  final ValueChanged<String> onTap;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 8,
      childAspectRatio: 0.85,
      children: [
        for (final QuickLink link in links)
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onTap(link.url),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    _initial(link),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  link.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _initial(QuickLink link) {
    final String source = link.title.isNotEmpty ? link.title : UrlUtils.hostOf(link.url);
    return source.isEmpty ? '?' : source.characters.first.toUpperCase();
  }
}
