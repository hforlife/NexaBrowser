import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../core/formatters.dart';
import '../../core/url_utils.dart';
import '../../models/detected_media.dart';
import '../../services/download_service.dart';
import '../../state/browser_tab.dart';
import '../screens/downloads_screen.dart';

/// Liste des vidéos détectées sur la page, avec bouton « Télécharger ».
class MediaSheet extends StatelessWidget {
  const MediaSheet({super.key, required this.tab});

  final BrowserTab tab;

  static Future<void> show(BuildContext context, BrowserTab tab) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => MediaSheet(tab: tab),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tab,
      builder: (BuildContext context, _) {
        final List<DetectedMedia> items = tab.media;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '${items.length} média${items.length > 1 ? 's' : ''} détecté${items.length > 1 ? 's' : ''}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int i) => _MediaTile(media: items[i]),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.media});

  final DetectedMedia media;

  IconData get _icon => switch (media.kind) {
        MediaKind.video => Icons.movie_outlined,
        MediaKind.audio => Icons.music_note_outlined,
        MediaKind.stream => Icons.live_tv_outlined,
      };

  /// Nom de fichier lisible : titre de la page + extension.
  String get _fileName {
    final String title = (media.pageTitle ?? '').trim();
    final String base = title.isNotEmpty ? title : UrlUtils.fileNameFromUrl(media.url);
    final String withoutExt =
        base.toLowerCase().endsWith(media.extension) ? base : '$base${media.extension}';
    return UrlUtils.sanitizeFileName(withoutExt);
  }

  Future<void> _download(BuildContext context) async {
    final AppScope scope = AppScope.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    try {
      await scope.downloads.enqueue(
        url: media.url,
        fileName: _fileName,
        referer: media.pageUrl,
        mimeType: media.mimeType,
        isHls: media.isHls,
        // Cookies du site seulement si le média est sur le même site que la page
        withCookies: UrlUtils.isSameSite(media.url, media.pageUrl),
      );
    } on DownloadException catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: const Text('Téléchargement lancé'),
      action: SnackBarAction(
        label: 'Voir',
        onPressed: () => navigator.push(
          MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final String subtitle = [
      media.kind.label,
      UrlUtils.hostOf(media.url),
      if (media.contentLength != null) Formatters.bytes(media.contentLength),
    ].where((s) => s.isNotEmpty).join(' · ');

    return ListTile(
      leading: Icon(_icon),
      title: Text(_fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton.filledTonal(
        tooltip: 'Télécharger',
        icon: const Icon(Icons.download_rounded),
        onPressed: () => _download(context),
      ),
    );
  }
}
