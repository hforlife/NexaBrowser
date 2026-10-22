import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'app_scope.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'services/adblock_service.dart';
import 'services/database_service.dart';
import 'services/download_service.dart';
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
  final AdblockService adblock = AdblockService();
  await Future.wait([db.open(), settings.load()]);
  await adblock.load();

  final DownloadService downloads = DownloadService(db);
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
