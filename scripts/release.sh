#!/bin/zsh
# Builds a signed, notarized DMG in build/release.
#
# Needs a Developer ID Application certificate and stored notary credentials, see
# docs/release.md. With SKIP_SIGNING=1 it builds an unsigned DMG to test the steps.
set -euo pipefail
cd "${0:a:h}/.."

identity="Developer ID Application"
profile="${NOTARY_PROFILE:-quietdeck-notary}"
out="build/release"
archive="$out/QuietDeck.xcarchive"
app="$out/QuietDeck.app"

rm -rf "$out"
mkdir -p "$out"

if [[ "${SKIP_SIGNING:-0}" == "1" ]]; then
  signing=(CODE_SIGN_IDENTITY=-)
else
  : "${TEAM_ID:?Set TEAM_ID to your Apple Developer team ID}"
  signing=(
    CODE_SIGN_IDENTITY="$identity"
    CODE_SIGN_STYLE=Manual
    DEVELOPMENT_TEAM="$TEAM_ID"
    OTHER_CODE_SIGN_FLAGS=--timestamp
  )
fi

echo "==> Archiving"
xcodebuild -project QuietDeck.xcodeproj -scheme QuietDeck -configuration Release \
  -archivePath "$archive" -destination 'generic/platform=macOS' archive "${signing[@]}" -quiet

cp -R "$archive/Products/Applications/QuietDeck.app" "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
dmg="$out/QuietDeck-$version.dmg"

echo "==> Checking the signature"
codesign --verify --deep --strict "$app"

echo "==> Building the disk image"
stage="$out/stage"
mkdir -p "$stage"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -volname QuietDeck -srcfolder "$stage" -format UDZO -ov "$dmg" -quiet
rm -rf "$stage"

if [[ "${SKIP_SIGNING:-0}" == "1" ]]; then
  echo "==> Skipped signing and notarization: $dmg"
  exit 0
fi

codesign --force --timestamp --sign "$identity" "$dmg"

echo "==> Notarizing, this can take a few minutes"
keychain_option=()
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
  keychain_option=(--keychain "$NOTARY_KEYCHAIN")
fi
xcrun notarytool submit "$dmg" --keychain-profile "$profile" "${keychain_option[@]}" --wait
xcrun stapler staple "$dmg"

echo "==> Checking with Gatekeeper"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"

echo "==> Done: $dmg"
