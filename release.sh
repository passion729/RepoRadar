#!/bin/bash
# Publish a release from this Mac: ./release.sh 1.1
# Signs with the Yuanju Bo team certificate, so every version keeps the same signature and the
# Keychain keeps trusting the app across updates. Then packs a drag-to-install DMG, tags the
# current commit and creates the GitHub release. Not notarized: the notes say how to open it.
# Last, signs the DMG with the Sparkle EdDSA key (Infisical project RepoRadar, prod,
# SPARKLE_ED_PRIVATE_KEY; needs `infisical login`) into appcast.xml and pushes it to main,
# where installed copies look for updates.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: release.sh <version>}"
TAG="v$VERSION"
IDENTITY="${SIGN_IDENTITY:-Apple Development: Oscar Passion (8HXY99Y2JK)}"
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin

# Checked first, so a failure doesn't leave a half-made release.
security find-identity -v -p codesigning | grep -qF "\"$IDENTITY\"" \
  || { echo "signing certificate not in the Keychain: $IDENTITY"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "commit or stash your changes first"; exit 1; }
git fetch -q origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
  || { echo "release from main, pushed and in sync with origin/main"; exit 1; }
! git ls-remote --exit-code --tags origin "$TAG" >/dev/null || { echo "$TAG already exists"; exit 1; }
KEY=$(infisical secrets get SPARKLE_ED_PRIVATE_KEY --plain --silent --env prod)
[ -n "$KEY" ] || { echo "no SPARKLE_ED_PRIVATE_KEY from Infisical (infisical login?)"; exit 1; }

./test.sh
VERSION="$VERSION" SIGN_IDENTITY="$IDENTITY" ./build.sh release

# The app next to an Applications shortcut.
STAGE=$(mktemp -d)
mkdir "$STAGE/dmg" "$STAGE/out"
ditto RepoRadar.app "$STAGE/dmg/RepoRadar.app"
ln -s /Applications "$STAGE/dmg/Applications"
DMG="$STAGE/out/RepoRadar-$TAG.dmg"
hdiutil create -quiet -volname RepoRadar -srcfolder "$STAGE/dmg" -format UDZO "$DMG"

gh release create "$TAG" "$DMG" --target "$(git rev-parse HEAD)" --title "RepoRadar $VERSION" --generate-notes \
  --notes "RepoRadar isn't notarized. On first launch, dismiss the warning, then click **Open Anyway** in System Settings → Privacy & Security, or run \`xattr -dr com.apple.quarantine /Applications/RepoRadar.app\`."
# Only the new DMG in the folder: generate_appcast keeps the older entries already in appcast.xml.
echo "$KEY" | "$SPARKLE_BIN/generate_appcast" --ed-key-file - \
  --download-url-prefix "https://github.com/passion729/RepoRadar/releases/download/$TAG/" \
  -o appcast.xml "$STAGE/out"
git add appcast.xml
git commit -q -m "Appcast for $VERSION"
git push -q origin HEAD:main
echo "Released $TAG"
