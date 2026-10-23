# NexaBrowser

Navigateur mobile léger (Flutter) pensé pour l'Afrique : **bloqueur de publicités**, **économie de données**, **détection et téléchargement de vidéos**.

## Fonctionnalités (v0.1)

| | |
|---|---|
| 🌐 Navigation | barre d'adresse intelligente (adresse ou recherche), onglets (12 max), tirer pour actualiser, bouton retour Android |
| 🕶 Onglets privés | ni historique, ni cookies, ni cache conservés |
| 🛡 Bloqueur de pubs | blocage réseau par domaine (Android) + masquage des emplacements vides ; liste de base intégrée, liste complète (~150 000 domaines) téléchargeable dans Paramètres ; compteur de pubs bloquées par page |
| 📉 Économie de données | images non chargées, vidéos sans lecture automatique |
| 🎬 Détection vidéo | MP4/WEBM/MP3… et flux HLS (.m3u8), via le réseau et les balises `<video>` (y compris dans les iframes) ; bouton flottant avec compteur |
| ⬇️ Téléchargements | moteur natif Android : continue app fermée (service au premier plan), notifications avec Pause / Reprendre / Annuler, 2 simultanés, reprise HTTP Range, nouvel essai automatique et reprise au retour du réseau, HLS (TS, fMP4, audio séparé) converti en `.mp4` sans réencodage |
| ⭐ Favoris, 🕘 Historique | SQLite, recherche dans l'historique |
| 🖥 Version ordinateur | bascule à la volée |
| 🔗 Liens externes | WhatsApp, téléphone, e-mail, `intent://` (repli sur la version web) |

YouTube est volontairement exclu du téléchargement (règlement Google Play).

## Installation

Prérequis : Flutter installé (`flutter doctor` sans erreur pour Android).

```bash
cd nexa_browser
bash setup.sh     # génère android/ et ios/, applique les réglages, installe les dépendances
flutter test      # tests unitaires (URL, bloqueur, détection vidéo, HLS)
flutter run       # sur un téléphone Android branché ou un émulateur
```

`setup.sh` lance `flutter create .` (qui ne touche pas à `lib/`), supprime le test d'exemple, puis `tool/patch_platforms.py` ajoute la permission Internet, le trafic `http://`, et le nom « NexaBrowser ».

APK de test : `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`.

## Où vont les fichiers téléchargés ?

Android 10 et plus : dossier public **Téléchargements/NexaBrowser** (MediaStore, aucune permission).
Android 9 et moins : même dossier si la permission de stockage est accordée, sinon
`Android/data/com.nexa.nexa_browser/files/Download/NexaBrowser/`.

Le moteur est en Kotlin (`android/app/src/main/kotlin/com/nexa/nexa_browser/download/`) ;
Dart (`lib/services/download_service.dart`) ne fait que l'afficher et le piloter.

Tests du moteur :

```bash
cd android && ./gradlew :app:testDebugUnitTest      # tests JVM (HLS, reprise, erreurs)
flutter test integration_test/downloads_test.dart \
  --dart-define=NEXA_TEST_SERVER=http://10.0.2.2:8765 \
  --dart-define=NEXA_CLIP_SIZE=… --dart-define=NEXA_BIG_SIZE=…   # sur émulateur, serveur de test requis
```

## Structure

```
lib/
├── main.dart                     # démarrage, création des services
├── app_scope.dart                # accès aux services depuis les widgets
├── core/                         # constantes, thème, URL, formatage
├── models/                       # DetectedMedia, DownloadTask, SiteEntry
├── services/
│   ├── adblock_service.dart      # liste de domaines, blocage, règles iOS
│   ├── media_detector.dart       # reconnaissance des médias + script JS injecté
│   ├── hls_parser.dart           # lecture des .m3u8
│   ├── download_service.dart     # file d'attente, reprise, HLS
│   ├── database_service.dart     # SQLite
│   └── settings_service.dart     # réglages
├── state/                        # BrowserController (onglets), BrowserTab
└── ui/
    ├── browser_screen.dart       # écran principal, barre du bas, menu
    ├── widgets/                  # WebView d'onglet, barre d'adresse, accueil, vidéos détectées
    └── screens/                  # onglets, favoris, historique, téléchargements, paramètres
```

## Limites connues / prochaines étapes

- iOS : WebKit ne permet pas d'intercepter les requêtes → blocage par règles natives (3 000 domaines max) et détection vidéo par script uniquement.
- Les flux HLS chiffrés (DRM, AES) ne sont pas téléchargeables.
- Les téléchargements s'arrêtent si l'app est fermée (reprise possible ensuite) → prochaine étape : service en arrière-plan + notifications.
- Cœur Rust (adblock-rust de Brave, règles EasyList complètes) à brancher via `flutter_rust_bridge` derrière `AdblockService`.
- Intégration NexaFiles : envoyer les fichiers téléchargés dans le gestionnaire.
