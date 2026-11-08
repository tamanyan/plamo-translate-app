#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-$(uname -m)}" in
  arm64) arch=arm64; checksum=4f5b8de12e0b9516658ca6a5764c6ffb3d7c659c3dd538556b1413c7b4050662 ;;
  x86_64|x64) arch=x64; checksum=c8094268b6bf62f4998f0e45656fd9f5e2d4afb6b1cd0044d761db64be1dd47d ;;
  *) echo 'Unsupported architecture' >&2; exit 1 ;;
esac
root=".build/engine/$arch"
mkdir -p "$root"
archive="$root/llama.tar.gz"
# Reuse the archive from the initial development session after verifying it.
if [[ "$arch" == arm64 && ! -f "$archive" && -f .build/engine/llama.tar.gz ]]; then
  cp .build/engine/llama.tar.gz "$archive"
fi
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 "https://github.com/ggml-org/llama.cpp/releases/download/b12110/llama-b12110-bin-macos-$arch.tar.gz" -o "$archive.download"
  mv "$archive.download" "$archive"
fi
printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 --check
# Always extract again from the verified archive.
tar -xzf "$archive" -C "$root"
# Stable development location; distribution copies from the architecture-specific path.
ln -sfn "$arch/llama-b12110" .build/engine/current
echo "Engine ready: $root/llama-b12110/llama-server"
