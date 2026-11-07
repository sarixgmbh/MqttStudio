#!/bin/sh
# Creates the notarized disk image build/macos/dist/MQTT-Studio.dmg for distribution outside the Mac App
# Store. The Release build is signed with the Developer ID of Sarix Srl and the hardened runtime (Runner.xcodeproj).
# The app is notarized and stapled before it goes into the image, so it also opens offline after it was copied out of
# the image; then the image itself is signed, notarized and stapled. Last, the image is signed for the Sparkle updater
# and build/macos/dist/appcast.xml is written; upload both to the folder of SUFeedURL in Info.plist (downloads below).
# The names stay the same with every release, so invalidate the CDN cache of both after the upload.
# Sparkle offers an update when the build number (the +n of the version in pubspec.yaml) is higher than the installed
# one, so increase it with every release. macos/packaging/release_notes.html, if present, becomes the release notes.
# Needs the "Developer ID Application: Sarix Srl" certificate in the keychain and the notarytool profile
# mqttstudio-notary (xcrun notarytool store-credentials mqttstudio-notary ...), and the Sparkle signing key in the
# keychain (generate_keys -f <exported key file> imports it on another Mac).
# Run from src/mqttstudio_client: sh macos/packaging/create_dmg.sh

set -eu
cd "$(dirname "$0")/../.."

identity="Developer ID Application: Sarix Srl (3K9CD3C6B4)"
profile=mqttstudio-notary
version=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)
build=$(sed -n 's/^version: *[^+]*+\([0-9]*\).*/\1/p' pubspec.yaml)
downloads=https://www.mqttstudio.com/downloads
app="build/macos/Build/Products/Release/MQTT Studio.app"
dist=build/macos/dist
dmg="$dist/MQTT-Studio.dmg"
# Sparkle's tools come with the Swift package, the build resolves it
sparkle=build/macos/SourcePackages/artifacts/sparkle/Sparkle/bin

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

# Xcode signs Sparkle.framework but not the helpers inside, which the Swift package has signed ad hoc; notarization
# needs them signed with the Developer ID. Then the framework and the app are sealed again.
sign() {
  codesign --force --sign "$identity" --options runtime --timestamp "$@"
}
framework="$app/Contents/Frameworks/Sparkle.framework"
sign "$framework/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$framework/Versions/B/XPCServices/Downloader.xpc"
sign "$framework/Versions/B/Autoupdate"
sign "$framework/Versions/B/Updater.app"
sign "$framework"
sign --preserve-metadata=entitlements "$app"

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

# prints sparkle:edSignature="..." length="..."
enclosure=$("$sparkle/sign_update" "$dmg")
notes=macos/packaging/release_notes.html
cat > "$dist/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MQTT Studio</title>
    <item>
      <title>MQTT Studio $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
$(if [ -f "$notes" ]; then printf '      <description><![CDATA[%s]]></description>' "$(cat "$notes")"; fi)
      <enclosure url="$downloads/MQTT-Studio.dmg" type="application/octet-stream" $enclosure/>
    </item>
  </channel>
</rss>
EOF
echo "created $dmg and $dist/appcast.xml, upload both to $downloads"
