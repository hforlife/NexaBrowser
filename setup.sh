#!/usr/bin/env bash
# Prépare le projet sur votre machine : génère android/ et ios/, applique les réglages.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "❌ Flutter introuvable. Installez-le : https://docs.flutter.dev/get-started/install"
  exit 1
fi

echo "▶ Génération des dossiers Android et iOS (vos fichiers lib/ ne sont pas modifiés)…"
flutter create --org com.nexa --project-name nexa_browser --platforms android,ios .

# flutter create ajoute un test d'exemple qui ne correspond pas à l'app
rm -f test/widget_test.dart

echo "▶ Réglages Android / iOS…"
python3 tool/patch_platforms.py

echo "▶ Téléchargement des dépendances…"
flutter pub get

echo ""
echo "✅ Prêt ! Branchez un téléphone Android (ou lancez un émulateur) puis :"
echo "   flutter run"
