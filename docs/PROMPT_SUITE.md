# Contexte

Tu reprends le développement de **NexaBrowser**, un navigateur mobile Flutter léger pensé pour le marché africain (Mali en priorité), sur le modèle de Phoenix Browser : bloqueur de publicités, économie de données, détection et téléchargement de vidéos.

- **Emplacement** : `~/development/nexa_browser` sur mon Mac (Intel, macOS). Flutter est installé.
- **Mes versions** : [coller ici la sortie de `flutter --version` et `flutter doctor`]
- **Cible** : Android en priorité (Google Play + APK), iOS plus tard. Bureau éventuellement.
- **Stack** : Flutter 3 / Dart 3, Material 3, `flutter_inappwebview` 6.x, `sqflite`, `shared_preferences`, `http`, `path_provider`, `open_filex`, `url_launcher`. Pas de gestionnaire d'état externe : `ChangeNotifier` + un `InheritedWidget` (`AppScope`).
- **Plus tard** : un cœur Rust (`adblock-rust` de Brave via `flutter_rust_bridge`) sera branché derrière `AdblockService`. L'architecture doit rester compatible avec ça.

# Ce qui existe déjà (v0.1, jamais compilée)

⚠️ Le code a été écrit **sans pouvoir lancer `flutter analyze` ni `flutter test`**. Il faut s'attendre à des erreurs de compilation, en particulier sur l'API de `flutter_inappwebview` 6.x.

```
lib/
├── main.dart                  # init services (DB, réglages, adblock, téléchargements), MaterialApp
├── app_scope.dart             # InheritedWidget donnant accès aux services
├── core/                      # constants.dart (moteurs de recherche, liens rapides, domaines interdits),
│                              # theme.dart (M3, couleur #6366F1), url_utils.dart, formatters.dart
├── models/                    # detected_media.dart, download_task.dart, site_entry.dart
├── services/
│   ├── adblock_service.dart   # Set de domaines (format hosts), test domaine + parents, règles iOS ContentBlocker,
│   │                          # liste de base assets/adblock/hosts.txt + mise à jour (StevenBlack), CSS cosmétique
│   ├── media_detector.dart    # classification URL/MIME (mp4, mp3, m3u8…), exclusion YouTube, script JS injecté
│   │                          # (balises <video>/<audio> + MutationObserver → handler « nexaMedia »)
│   ├── hls_parser.dart        # liste maître → meilleure qualité, segments, détection du chiffrement
│   ├── download_service.dart  # file d'attente (2 simultanés), pause/reprise HTTP Range, cookies + Referer,
│   │                          # HLS assemblé en .ts, persistance SQLite
│   ├── database_service.dart  # tables history / bookmarks / downloads
│   └── settings_service.dart  # moteur de recherche, adblock, économie de données, version ordinateur, détection vidéo
├── state/
│   ├── browser_controller.dart # onglets (12 max, privés), navigation, retour Android, historique
│   └── browser_tab.dart        # URL, titre, progression, compteur de pubs bloquées, médias détectés
└── ui/
    ├── browser_screen.dart     # barre d'adresse, IndexedStack d'onglets, barre du bas, menu, bouton vidéos
    ├── widgets/                # tab_web_view.dart (InAppWebView + interception), address_bar.dart,
    │                           # start_page.dart, media_sheet.dart
    └── screens/                # tabs, bookmarks, history, downloads, settings
test/core_test.dart             # tests unitaires : URL, adblock, MediaDetector, HlsParser, formatage
setup.sh + tool/patch_platforms.py  # flutter create . + permission INTERNET, cleartext, nom « NexaBrowser »
```

# Ce qui manque (connu)

1. **Compilation non vérifiée.** Aucun `flutter analyze`, test ou lancement sur appareil n'a encore été fait.
2. **Téléchargements :**
   - pas de service en arrière-plan ni de notification de progression : le téléchargement s'arrête quand l'app est fermée ;
   - les fichiers restent dans le dossier privé de l'app au lieu du dossier public Téléchargements ;
   - les flux HLS sont enregistrés en `.ts`, sans conversion en `.mp4`.
3. **Bloqueur :**
   - le filtrage se fait seulement par domaine : pas de règles EasyList complètes ni de règles cosmétiques par site ;
   - pas de liste blanche par site ;
   - pas de mise à jour automatique de la liste.
4. **Ergonomie :**
   - pas de suggestions dans la barre d'adresse (historique, favoris) ni de favicons ;
   - les onglets ne sont pas restaurés au redémarrage et n'ont pas d'aperçu ;
   - pas de menu à l'appui long sur un lien ou une image (ouvrir dans un nouvel onglet, télécharger, copier) ;
   - pas de recherche dans la page, de partage, de taille du texte ni de mode sombre forcé ;
   - la vidéo en plein écran n'a pas été vérifiée.
5. **Économie de données :** aucun compteur des données ou des publicités économisées.
6. **Identité et publication :**
   - pas d'icône, d'écran de démarrage ni d'identifiant d'app définitif ;
   - pas de signature release ni de R8/ProGuard ;
   - pas de politique de confidentialité ni de fiche Play Store.
7. **Qualité :** pas de tests de widgets ni d'intégration, pas de CI.
8. **Écosystème :** pas d'intégration avec NexaFiles (mon gestionnaire de fichiers Flutter), et le cœur Rust n'est pas encore branché.

# Règles de travail

- **Code** : complet et prêt pour la production, commenté en français, avec des types explicites, des constantes plutôt que des chaînes magiques, `switch` en expression et `match` quand c'est pertinent, et une responsabilité par fichier. Pas de pseudo-code ni de « … reste inchangé ».
- **Interface** : textes en français. Pense aux contraintes du terrain : téléphones Android d'entrée de gamme (2 à 3 Go de RAM), réseau 3G/4G instable, données mobiles chères.
- **Fichiers** : donne-moi chaque fichier modifié en entier, ou un diff clair avec son chemin.
- **Fin de chaque lot** : liste des fichiers créés ou modifiés, commandes pour vérifier (`flutter analyze`, `flutter test`, `flutter run`), points à tester à la main sur le téléphone, risques restants.
- **Ne passe jamais au lot suivant sans ma validation.**

# Ce que je te demande

## Étape 1 — Analyse (pas de code)

1. Lis tout le projet.
2. Relève les **problèmes probables**, classés par gravité :
   - erreurs de compilation (surtout l'API de `flutter_inappwebview` 6.x) ;
   - bugs de logique ;
   - fuites mémoire (WebView, listeners) ;
   - performances (interception de chaque requête, Set de 150 000 domaines) ;
   - sécurité ;
   - règles de Google Play.
3. Dis-moi ce qui est bien conçu et doit être gardé, et ce qui doit être refait.
4. Propose un **découpage en lots** cohérent, en reprenant ou corrigeant celui ci-dessous. Pour chaque lot, donne :
   - l'objectif ;
   - les fichiers concernés ;
   - les critères d'acceptation vérifiables ;
   - la difficulté (S, M ou L) ;
   - les dépendances avec les autres lots.

## Découpage proposé (à challenger)

- **Lot 1 — Compilation et stabilisation**
  - `flutter analyze` sans erreur, tests verts, lancement réussi sur un appareil Android ;
  - navigation, onglets, bloqueur et détection vidéo vérifiés sur des sites réels (un site d'actualités local, Facebook mobile, un site vidéo hors YouTube).
- **Lot 2 — Téléchargements solides**
  - service au premier plan conforme Android 14+, avec notifications (progression, pause, terminé) ;
  - enregistrement dans le dossier public Téléchargements (MediaStore) ;
  - nouvelle tentative automatique quand le réseau coupe ;
  - conversion HLS `.ts` → `.mp4` (évalue les options maintenues et leur poids dans l'APK) ;
  - bouton « Ouvrir dans NexaFiles ».
- **Lot 3 — Bloqueur avancé**
  - liste blanche par site (bouclier → « Désactiver sur ce site ») ;
  - règles cosmétiques EasyList par domaine ;
  - mise à jour automatique hebdomadaire, en Wi-Fi seulement ;
  - statistiques (publicités bloquées, données économisées) ;
  - préparation de l'interface pour un futur moteur Rust.
- **Lot 4 — Ergonomie du navigateur**
  - suggestions dans la barre d'adresse, favicons ;
  - restauration des onglets au redémarrage, aperçus des onglets ;
  - menu à l'appui long, recherche dans la page, partage ;
  - taille du texte, mode sombre forcé, vidéo en plein écran.
- **Lot 5 — Économie de données et performance**
  - compteur de données économisées, mode « données faibles » ;
  - mise en veille des onglets en arrière-plan ;
  - mesure de la mémoire et du temps de démarrage.
- **Lot 6 — Identité et publication**
  - icône (même famille que le logo NexaFiles), écran de démarrage, identifiant d'app définitif ;
  - signature release, R8 ;
  - politique de confidentialité (loi malienne 2013-015 + RGPD) ;
  - textes de la fiche Play Store, préparation du test fermé (12 testeurs pendant 14 jours).
- **Lot 7 — Qualité**
  - tests de widgets et d'intégration ;
  - CI GitHub Actions (analyze, test, build APK).
- **Lot 8 — Plus tard**
  - cœur Rust (`adblock-rust` via `flutter_rust_bridge`) ;
  - version iOS ;
  - monétisation (partenariat moteur de recherche, version Premium).

## Étape 2

Après ma validation du plan, attaque **uniquement le Lot 1**.
