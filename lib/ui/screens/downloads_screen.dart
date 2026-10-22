import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

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
              child: Text(
                'Aucun téléchargement.\nLes vidéos détectées et les fichiers apparaîtront ici.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({required this.task, required this.service});

  final DownloadTask task;
  final DownloadService service;

  String get _details {
    final String size = task.isHls
        ? '${task.received}/${task.total ?? '?'} segments'
        : task.total != null
            ? '${Formatters.bytes(task.received)} / ${Formatters.bytes(task.total)}'
            : Formatters.bytes(task.received);
    return switch (task.status) {
      DownloadStatus.completed => task.isHls ? 'Terminé' : 'Terminé · ${Formatters.bytes(task.received)}',
      DownloadStatus.failed => 'Échec : ${task.error ?? 'erreur inconnue'}',
      _ => '${task.status.label} · $size',
    };
  }

  Future<void> _open(BuildContext context) async {
    final OpenResult result = await OpenFilex.open(task.savePath);
    if (result.type != ResultType.done && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Impossible d'ouvrir le fichier : ${result.message}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool done = task.status == DownloadStatus.completed;

    final Widget action = switch (task.status) {
      DownloadStatus.running || DownloadStatus.queued => IconButton(
          tooltip: 'Pause',
          icon: const Icon(Icons.pause_circle_outline),
          onPressed: () => service.pause(task),
        ),
      DownloadStatus.paused || DownloadStatus.failed => IconButton(
          tooltip: 'Reprendre',
          icon: const Icon(Icons.play_circle_outline),
          onPressed: () => service.resume(task),
        ),
      DownloadStatus.completed => IconButton(
          tooltip: 'Ouvrir',
          icon: const Icon(Icons.open_in_new),
          onPressed: () => _open(context),
        ),
    };

    return ListTile(
      leading: Icon(task.isHls ? Icons.live_tv_outlined : Icons.insert_drive_file_outlined),
      title: Text(task.fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (task.status == DownloadStatus.running)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: LinearProgressIndicator(value: task.progress),
            ),
          Text(_details, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
      trailing: action,
      onTap: done ? () => _open(context) : null,
      onLongPress: () => _confirmDelete(context),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Supprimer ce téléchargement ?'),
        content: Text(task.fileName),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok == true) await service.remove(task);
  }
}
