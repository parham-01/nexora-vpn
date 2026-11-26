#!/usr/bin/env bash
set -euo pipefail
app="$1"
platforms="$2"
tmp="$(mktemp -d)"
flutter create --platforms="$platforms" --org com.parham --project-name "parham_$app" "$tmp/p"
for p in $(echo "$platforms" | tr ',' ' '); do
  rm -rf "$app/$p"
  cp -r "$tmp/p/$p" "$app/$p"
done
