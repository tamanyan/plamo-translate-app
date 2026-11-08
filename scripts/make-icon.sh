#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/AppIcon.iconset
swift scripts/generate-icon.swift .build/AppIcon-1024.png
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" .build/AppIcon-1024.png --out ".build/AppIcon.iconset/icon_${size}x${size}.png" > /dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" .build/AppIcon-1024.png --out ".build/AppIcon.iconset/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns .build/AppIcon.iconset -o .build/AppIcon.icns
