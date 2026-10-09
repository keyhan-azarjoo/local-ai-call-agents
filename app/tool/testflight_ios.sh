#!/usr/bin/env bash
# Builds the iPhone app and uploads it to TestFlight.
#
# Signing is automatic, with the App Store Connect API key, so no Xcode account sign-in is
# needed. The key comes from the owner's private vault (~/.myotgo-secrets), never from git.
# Build numbers are the date and time (YYYYMMDDHHMM), so each is higher than every earlier one.
#   app/tool/testflight_ios.sh
# The iPhone app uses the App Store Connect app (and bundle ID) that was MyOTGO's, so its version
# continues from there: 2.1 and up (BUILD_NAME=… to set another).
set -euo pipefail
cd "$(dirname "$0")/.."
VAULT="${LOCALAILINE_SECRETS:-$HOME/.myotgo-secrets}"
KEY_ID=$(python3 -c "import json;print(json.load(open('$VAULT/secrets.json'))['ASC_KEY_ID'])")
ISSUER=$(python3 -c "import json;print(json.load(open('$VAULT/secrets.json'))['ASC_ISSUER_ID'])")
P8="$VAULT/files/AuthKey_${KEY_ID}.p8"
BUILD="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$P8" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER")

OWN_ID=com.myotgo.myotgo
BUNDLE_ID="${BUNDLE_ID:-$OWN_ID}"
BUILD_NAME="${BUILD_NAME:-2.1}"
PBX=ios/Runner.xcodeproj/project.pbxproj
if [ "$BUNDLE_ID" != "$OWN_ID" ]; then
  # Only for this build: the app's own ID comes back afterwards, whatever happens.
  cp "$PBX" "$PBX.keep"
  trap 'mv -f "$PBX.keep" "$PBX"' EXIT
  sed -i '' "s/PRODUCT_BUNDLE_IDENTIFIER = $OWN_ID;/PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID;/" "$PBX"
fi

echo "Building LocalAILine for iPhone ($BUNDLE_ID), build $BUILD"
flutter pub get >/dev/null
flutter build ios --release --config-only --build-number="$BUILD" ${BUILD_NAME:+--build-name="$BUILD_NAME"}
rm -rf build/ios/archive/Runner.xcarchive
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/ios/archive/Runner.xcarchive archive "${AUTH[@]}" DEVELOPMENT_TEAM=4AUJB659UV CODE_SIGN_STYLE=Automatic | grep -E "error|warning: .*sign|ARCHIVE (SUCCEEDED|FAILED)" || true
test -d build/ios/archive/Runner.xcarchive || { echo "Archive failed"; exit 1; }

cat > build/ios/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>4AUJB659UV</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive -exportOptionsPlist build/ios/ExportOptions.plist \
  -exportPath build/ios/upload "${AUTH[@]}" | grep -E "error|Upload|EXPORT (SUCCEEDED|FAILED)|Progress" || true
echo "Done: build $BUILD sent to App Store Connect (processing takes a few minutes)."
