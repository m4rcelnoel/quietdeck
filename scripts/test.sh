#!/bin/zsh
# Runs every package test suite, then builds the app.
set -euo pipefail
cd "${0:a:h}/.."

for package in Packages/*/; do
  echo "==> swift test: $(basename "$package")"
  swift test --package-path "$package" --quiet
done

echo "==> xcodebuild: QuietDeck"
xcodebuild -project QuietDeck.xcodeproj -scheme QuietDeck -configuration Debug \
  -derivedDataPath build/DerivedData build -quiet
