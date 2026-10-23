#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

command -v flutter >/dev/null || { echo 'Add Flutter 3.44.6 to PATH.' >&2; exit 1; }
command -v dart >/dev/null || { echo 'Add the bundled Flutter Dart SDK to PATH.' >&2; exit 1; }
flutter --no-version-check pub get
dart format --output=none --set-exit-if-changed lib test tool packages
# Dart's analyzer handles non-ASCII workspace paths in this pinned SDK.
dart analyze --fatal-infos
flutter --no-version-check test --no-pub --reporter expanded
python3 scripts/verify_repository.py
