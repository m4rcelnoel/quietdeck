#!/bin/zsh
# Writes build/release/appcast.xml for the DMG that scripts/release.sh built.
#
# Needs the update signing key in SPARKLE_ED_PRIVATE_KEY, see docs/release.md. It has to
# run after notarization, because stapling changes the DMG and the signature covers it.
set -euo pipefail
cd "${0:a:h}/.."

: "${SPARKLE_ED_PRIVATE_KEY:?Set SPARKLE_ED_PRIVATE_KEY to the update signing key}"

out="build/release"
info="$out/QuietDeck.app/Contents/Info.plist"
read_info() { /usr/libexec/PlistBuddy -c "Print :$1" "$info"; }

version=$(read_info CFBundleShortVersionString)
build=$(read_info CFBundleVersion)
minimum=$(read_info LSMinimumSystemVersion)
dmg="$out/QuietDeck-$version.dmg"
tag="v$version"

# The feed points at this tag's download, so a mismatch would publish a dead link.
if [[ "${GITHUB_REF_TYPE:-}" == "tag" && "${GITHUB_REF_NAME:-}" != "$tag" ]]; then
  echo "The tag ${GITHUB_REF_NAME:-} doesn't match the app version $version" >&2
  exit 1
fi

# The key travels over stdin, so it doesn't appear in the process list.
signature=$(print -r -- "$SPARKLE_ED_PRIVATE_KEY" |
  build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update --ed-key-file - "$dmg")

repository="https://github.com/m4rcelnoel/quietdeck"
cat > "$out/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>QuietDeck</title>
    <item>
      <title>QuietDeck $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$repository/releases/tag/$tag</sparkle:fullReleaseNotesLink>
      <enclosure url="$repository/releases/download/$tag/QuietDeck-$version.dmg" type="application/octet-stream" $signature/>
    </item>
  </channel>
</rss>
XML

echo "==> Wrote $out/appcast.xml"
