#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
developer="$(xcode-select -p)"
if [[ "$developer" == */CommandLineTools ]]; then
  # CLT ships Swift Testing but does not add its framework/plugin paths to SwiftPM.
  swift test --disable-xctest --enable-swift-testing \
    -Xswiftc -F -Xswiftc "$developer/Library/Developer/Frameworks" \
    -Xswiftc -load-plugin-library -Xswiftc "$developer/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib" \
    -Xlinker -F -Xlinker "$developer/Library/Developer/Frameworks" \
    -Xlinker -framework -Xlinker Testing \
    -Xlinker -rpath -Xlinker "$developer/Library/Developer/Frameworks" \
    -Xlinker -rpath -Xlinker "$developer/Library/Developer/usr/lib" "$@"
else
  swift test "$@"
fi
