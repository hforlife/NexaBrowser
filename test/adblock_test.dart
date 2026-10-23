// Tests du bloqueur : exceptions par site, statistiques, mise à jour
// automatique, service complet et compteur de l'onglet : « flutter test ».
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_browser/core/formatters.dart';
import 'package:nexa_browser/core/url_utils.dart';
import 'package:nexa_browser/services/adblock/adblock_service.dart';
import 'package:nexa_browser/services/adblock/adblock_stats.dart';
import 'package:nexa_browser/services/adblock/blocklist_auto_updater.dart';
import 'package:nexa_browser/services/adblock/site_exceptions.dart';
import 'package:nexa_browser/state/browser_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('UrlUtils.siteOf', () {
    test('ramène au site', () {
      expect(UrlUtils.siteOf('https://m.facebook.com/home'), 'facebook.com');
      expect(UrlUtils.siteOf('https://www.maliweb.net/a'), 'maliweb.net');
      expect(UrlUtils.siteOf('http://site.ml'), 'site.ml');
      expect(UrlUtils.siteOf(''), '');
    });
  });

  group('SiteExceptions', () {
    test('ajout, retrait, bascule et persistance', () async {
      final SiteExceptions exceptions = SiteExceptions();
      await exceptions.load();
      expect(exceptions.contains('site.ml'), isFalse);

      expect(await exceptions.toggle('site.ml'), isTrue);
      await exceptions.add('autre.com');
      expect(exceptions.sites, ['autre.com', 'site.ml']);

      // Relu depuis le stockage
      final SiteExceptions reloaded = SiteExceptions();
      await reloaded.load();
      expect(reloaded.contains('site.ml'), isTrue);

      expect(await reloaded.toggle('site.ml'), isFalse);
      expect(reloaded.contains('site.ml'), isFalse);
      expect(reloaded.contains(''), isFalse);
    });
  });

  group('AdblockStats', () {
    test('compte, estime, enregistre et remet à zéro', () async {
      final AdblockStats stats = AdblockStats();
      await stats.load();
      for (int i = 0; i < 3; i++) {
        stats.recordBlocked();
      }
      expect(stats.blockedTotal, 3);
      expect(stats.estimatedBytesSaved, 3 * AdblockStats.estimatedBytesPerBlockedRequest);
      await stats.flush();

      final AdblockStats reloaded = AdblockStats();
      await reloaded.load();
      expect(reloaded.blockedTotal, 3);

      await reloaded.reset();
      expect(reloaded.blockedTotal, 0);
    });

    test('regroupe les écritures', () {
      fakeAsync((FakeAsync async) {
        final AdblockStats stats = AdblockStats();
        int notifications = 0;
        stats.addListener(() => notifications++);
        for (int i = 0; i < 100; i++) {
          stats.recordBlocked();
        }
        expect(notifications, 0);
        async.elapse(AdblockStats.flushInterval);
        expect(notifications, 1);
        stats.dispose();
      });
    });
  });

  group('BlocklistAutoUpdater.isDue', () {
    final DateTime now = DateTime(2026, 10, 23);
    test('jamais téléchargée : à faire', () {
      expect(BlocklistAutoUpdater.isDue(lastUpdate: null, now: now), isTrue);
    });
    test('moins d\'une semaine : rien à faire', () {
      expect(BlocklistAutoUpdater.isDue(lastUpdate: now.subtract(const Duration(days: 6)), now: now), isFalse);
    });
    test('une semaine ou plus : à faire', () {
      expect(BlocklistAutoUpdater.isDue(lastUpdate: now.subtract(const Duration(days: 7)), now: now), isTrue);
    });
  });

  group('AdblockService', () {
    setUp(() {
      // Liste embarquée remplacée par une liste de test
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (ByteData? message) async {
        return ByteData.sublistView(Uint8List.fromList('0.0.0.0 doubleclick.net\nadnxs.com\n'.codeUnits));
      });
      // Pas de liste téléchargée
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall call) async => '/chemin/inexistant',
      );
    });

    Future<AdblockService> loadedService() async {
      final SiteExceptions exceptions = SiteExceptions();
      final AdblockStats stats = AdblockStats();
      await Future.wait([exceptions.load(), stats.load()]);
      final AdblockService service = AdblockService(exceptions: exceptions, stats: stats);
      await service.load();
      return service;
    }

    test('bloque, compte et respecte les exceptions', () async {
      final AdblockService service = await loadedService();
      expect(service.ruleCount, 2);

      final Uri ad = Uri.parse('https://securepubads.g.doubleclick.net/tag.js');
      expect(service.shouldBlock(ad, pageSite: 'maliweb.net'), isTrue);
      expect(service.shouldBlock(Uri.parse('https://maliweb.net/app.js'), pageSite: 'maliweb.net'), isFalse);
      expect(service.stats.blockedTotal, 1);

      await service.exceptions.add('maliweb.net');
      expect(service.shouldBlock(ad, pageSite: 'maliweb.net'), isFalse);
      expect(service.cosmeticCssFor('maliweb.net'), isNull);
      // Les autres sites restent protégés
      expect(service.shouldBlock(ad, pageSite: 'autre.ml'), isTrue);
      expect(service.cosmeticCssFor('autre.ml'), isNotNull);
    });
  });

  group('BrowserTab', () {
    test('site calculé à chaque changement d\'adresse', () {
      final BrowserTab tab = BrowserTab(id: 1);
      expect(tab.site, '');
      tab.onPageStarted('https://m.facebook.com/');
      expect(tab.site, 'facebook.com');
      tab.updateUrl('https://www.maliweb.net/article');
      expect(tab.site, 'maliweb.net');
      tab.resetToStartPage();
      expect(tab.site, '');
    });

    test('compteur de blocages : notifications regroupées', () {
      fakeAsync((FakeAsync async) {
        final BrowserTab tab = BrowserTab(id: 1)..onPageStarted('https://site.ml/');
        int notifications = 0;
        tab.addListener(() => notifications++);
        for (int i = 0; i < 40; i++) {
          tab.incrementBlocked();
        }
        expect(tab.blockedCount, 40);
        expect(notifications, 0);
        async.elapse(BrowserTab.blockedNotifyDelay);
        expect(notifications, 1);
        tab.dispose();
      });
    });
  });

  test('Formatters.count : séparateur des milliers', () {
    expect(Formatters.count(950), '950');
    expect(Formatters.count(1234567), '1 234 567');
  });
}
