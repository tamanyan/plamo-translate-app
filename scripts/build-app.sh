#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
./scripts/fetch-engine.sh
swift build -c "$configuration"
bin="$(swift build -c "$configuration" --show-bin-path)"
app="dist/PLaMo Translate.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers/llama"
cp "$bin/PlamoTranslate" "$app/Contents/MacOS/PlamoTranslate"
# Keep resources in the standard, sealable application layout.
cp -R "$bin/PlamoTranslate_PlamoTranslate.bundle" "$app/Contents/Resources/"
engine=".build/engine/current"
cp "$engine/llama-server" "$app/Contents/Helpers/llama/"
# Keep the loader's @rpath symlink layout intact.
cp -RP "$engine/"*.dylib "$app/Contents/Helpers/llama/"
cp "$engine/LICENSE" "$app/Contents/Resources/llama-LICENSE.txt"
cp THIRD-PARTY-NOTICES.md "$app/Contents/Resources/"
./scripts/make-icon.sh
cp .build/AppIcon.icns "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PlamoTranslate</string>
<key>CFBundleIdentifier</key><string>com.tamanyan.plamo-translate</string>
<key>CFBundleName</key><string>PLaMo Translate</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleDisplayName</key><string>PLaMo Translate</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleDevelopmentRegion</key><string>ja</string>
<key>CFBundleLocalizations</key><array><string>ja</string><string>en</string></array>
</dict></plist>
PLIST
# Local ad-hoc signature by default. Use a Developer ID identity for a signed build.
identity="${CODE_SIGN_IDENTITY:--}"
while IFS= read -r -d '' file; do
  codesign --force --sign "$identity" "$file"
done < <(find "$app/Contents/Helpers/llama" -type f \( -name '*.dylib' -o -name 'llama-server' \) -print0)
codesign --force --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
echo "Built: $app"
