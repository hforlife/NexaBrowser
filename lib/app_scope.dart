import 'package:flutter/widgets.dart';

import 'services/adblock_service.dart';
import 'services/database_service.dart';
import 'services/download_service.dart';
import 'services/settings_service.dart';
import 'state/browser_controller.dart';

/// Rend les services accessibles partout : `AppScope.of(context).settings`.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.db,
    required this.settings,
    required this.adblock,
    required this.downloads,
    required this.browser,
    required super.child,
  });

  final DatabaseService db;
  final SettingsService settings;
  final AdblockService adblock;
  final DownloadService downloads;
  final BrowserController browser;

  static AppScope of(BuildContext context) {
    final AppScope? scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope introuvable dans l\'arbre des widgets');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false; // services immuables
}
