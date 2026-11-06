#!/bin/sh
# Creates the notarized disk image build/macos/dist/MQTT-Studio-<version>.dmg for distribution outside the Mac App
# Store. The Release build is signed with the Developer ID of Sarix Srl and the hardened runtime (Runner.xcodeproj).
# The app is notarized and stapled before it goes into the image, so it also opens offline after it was copied out of
# the image; then the image itself is signed, notarized and stapled.
# Needs the "Developer ID Application: Sarix Srl" certificate in the keychain and the notarytool profile
# mqttstudio-notary (xcrun notarytool store-credentials mqttstudio-notary ...).
# Run from src/mqttstudio_client: sh macos/packaging/create_dmg.sh

set -eu
cd "$(dirname "$0")/../.."

identity="Developer ID Application: Sarix Srl (3K9CD3C6B4)"
profile=mqttstudio-notary
version=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)
app="build/macos/Build/Products/Release/MQTT Studio.app"
dist=build/macos/dist
dmg="$dist/MQTT-Studio-$version.dmg"

notarize() {
  out=$(xcrun notarytool submit "$1" --keychain-profile "$profile" --wait --output-format plist)
  id=$(printf '%s' "$out" | plutil -extract id raw -)
  status=$(printf '%s' "$out" | plutil -extract status raw -)
  if [ "$status" != "Accepted" ]; then
    echo "notarization of $1 failed: $status" >&2
    xcrun notarytool log "$id" --keychain-profile "$profile" >&2
    exit 1
  fi
  echo "notarized $1"
}

# macOS does not let the build overwrite a notarized app that was started once, but it can be deleted
rm -rf "$app"
flutter build macos --release

codesign --verify --deep --strict "$app"
if ! codesign -dvv "$app" 2>&1 | grep -q "Authority=$identity"; then
  echo "$app is not signed with $identity" >&2
  exit 1
fi

rm -rf "$dist"
mkdir -p "$dist"
ditto -c -k --keepParent "$app" "$dist/app.zip"
notarize "$dist/app.zip"
rm "$dist/app.zip"
xcrun stapler staple "$app"

staging="$dist/staging"
mkdir "$staging"
ditto "$app" "$staging/MQTT Studio.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "MQTT Studio" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg"
rm -rf "$staging"
codesign --sign "$identity" --timestamp "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"

spctl --assess --type execute --verbose "$app"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"
echo "created $dmg"
