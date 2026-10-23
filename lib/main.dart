import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'app_scope.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'services/adblock/adblock_service.dart';
import 'services/adblock/adblock_stats.dart';
import 'services/adblock/blocklist_auto_updater.dart';
import 'services/adblock/site_exceptions.dart';
import 'services/database_service.dart';
import 'services/download_service.dart';
import 'services/network_info.dart';
import 'services/settings_service.dart';
import 'state/browser_controller.dart';
import 'ui/browser_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Débogage des pages web depuis chrome://inspect (mode debug uniquement)
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(kDebugMode);
  }

  final DatabaseService db = DatabaseService();
  final SettingsService settings = SettingsService();
  final SiteExceptions exceptions = SiteExceptions();
  final AdblockStats stats = AdblockStats();
  await Future.wait([db.open(), settings.load(), exceptions.load(), stats.load()]);

  final AdblockService adblock = AdblockService(exceptions: exceptions, stats: stats);
  final BlocklistAutoUpdater autoUpdater =
      BlocklistAutoUpdater(adblock: adblock, settings: settings, network: NetworkInfo());
  // Pas d'attente : la liste complète (≈ 150 000 domaines) se charge dans un
  // isolate pendant que l'interface s'affiche, puis la mise à jour hebdomadaire
  // est tentée (Wi-Fi uniquement) une fois la première page passée.
  unawaited(adblock.load().then((_) => autoUpdater.runAfterStartup()));

  final DownloadService downloads = DownloadService(settings);
  await downloads.load();

  final BrowserController browser = BrowserController(db: db, settings: settings);

  runApp(AppScope(
    db: db,
    settings: settings,
    adblock: adblock,
    downloads: downloads,
    browser: browser,
    child: const NexaBrowserApp(),
  ));
}

class NexaBrowserApp extends StatelessWidget {
  const NexaBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const BrowserScreen(),
    );
  }
}
