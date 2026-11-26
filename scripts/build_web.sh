#!/usr/bin/env bash
# Builds the production web app with the business branding.
#   ./scripts/build_web.sh [config/local.json]
set -euo pipefail
CONFIG="${1:-config/local.json}"
flutter pub get
flutter build web --release --dart-define-from-file="$CONFIG"
dart run tool/apply_brand.dart "$CONFIG" build/web
