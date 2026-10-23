import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../core/formatters.dart';
import '../../models/download_task.dart';
import '../../services/download_service.dart';

/// Suivi des téléchargements : progression, pause, reprise, ouverture.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final DownloadService downloads = AppScope.of(context).downloads;

    return Scaffold(
      appBar: AppBar(title: const Text('Téléchargements')),
      body: ListenableBuilder(
        listenable: downloads,
        builder: (BuildContext context, _) {
          final List<DownloadTask> tasks = downloads.tasks;
          if (tasks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Aucun téléchargement.\nLes vidéos détectées et les fichiers apparaîtront ici.\n\n'
                  'Ils sont enregistrés dans Téléchargements/NexaBrowser.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: tasks.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int i) =>
                _DownloadTile(task: tasks[i], service: downloads),
          );
        },
      ),
    );
  }
}

/// Choix proposés à l'appui long.
enum _RemoveChoice { keepFile, deleteFile }

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({required this.task, required this.service});

  final DownloadTask task;
  final DownloadService service;

  /// Taille et avancement : « 12 Mo / 45 Mo », « 34 % · 12 Mo ».
  String get _amount {
    final String received = Formatters.bytes(task.receivedBytes);
    final double? progress = task.progress;
    if (task.isHls) {
      return progress == null ? received : '${(progress * 100).round()} % · $received';
    }
    return task.totalBytes != null ? '$received / ${Formatters.bytes(task.totalBytes)}' : received;
  }

  String get _details => switch (task.status) {
        DownloadStatus.completed => [
            'Terminé · ${Formatters.bytes(task.receivedBytes)}',
            if (task.displayPath != null) task.displayPath!,
          ].join('\n'),
        DownloadStatus.failed => 'Échec : ${task.error ?? 'erreur inconnue'}',
        DownloadStatus.retrying || DownloadStatus.waitingNetwork =>
          '${task.status.label} · $_amount${task.error != null ? '\n${task.error}' : ''}',
        DownloadStatus.converting => task.status.label,
        DownloadStatus.queued || DownloadStatus.running || DownloadStatus.paused =>
          '${task.status.label} · $_amount',
      };

  IconData get _icon {
    final String mime = task.mimeType ?? '';
    if (task.isHls || mime.startsWith('video/')) return Icons.movie_outlined;
    if (mime.startsWith('audio/')) return Icons.music_note_outlined;
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _open(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!await service.open(task)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Aucune application ne peut ouvrir ce fichier')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool done = task.status == DownloadStatus.completed;

    final Widget? action = switch (task.status) {
      _ when task.canPause => IconButton(
          tooltip: 'Pause',
          icon: const Icon(Icons.pause_circle_outline),
          onPressed: () => service.pause(task),
        ),
      _ when task.canResume => IconButton(
          tooltip: task.status == DownloadStatus.failed ? 'Réessayer' : 'Reprendre',
          icon: Icon(task.status == DownloadStatus.failed ? Icons.refresh : Icons.play_circle_outline),
          onPressed: () => service.resume(task),
        ),
      DownloadStatus.completed => IconButton(
          tooltip: 'Ouvrir',
          icon: const Icon(Icons.open_in_new),
          onPressed: () => _open(context),
        ),
      _ => null, // conversion en cours
    };

    final bool showBar = task.status == DownloadStatus.running || task.status == DownloadStatus.converting;
    return ListTile(
      leading: Icon(_icon),
      title: Text(task.fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showBar)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: LinearProgressIndicator(
                value: task.status == DownloadStatus.converting ? null : task.progress,
              ),
            ),
          Text(_details, maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
      ),
      isThreeLine: done || task.status == DownloadStatus.retrying,
      trailing: action,
      onTap: done ? () => _open(context) : null,
      onLongPress: () => _confirmRemove(context),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool done = task.status == DownloadStatus.completed;
    final _RemoveChoice? choice = await showDialog<_RemoveChoice>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(done ? 'Supprimer ce téléchargement ?' : 'Annuler ce téléchargement ?'),
        content: Text(task.fileName),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Retour')),
          if (done)
            TextButton(
              onPressed: () => Navigator.pop(context, _RemoveChoice.keepFile),
              child: const Text('Retirer de la liste'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _RemoveChoice.deleteFile),
            child: Text(done ? 'Supprimer le fichier' : 'Annuler le téléchargement'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    final bool deleted = await service.remove(task, deleteFile: choice == _RemoveChoice.deleteFile);
    if (!deleted) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Retiré de la liste. Le fichier n\'a pas pu être supprimé : '
            'supprimez-le depuis votre gestionnaire de fichiers.'),
      ));
    }
  }
}
