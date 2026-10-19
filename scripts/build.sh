#!/bin/bash
# AirLingo 构建脚本：Xcode 工具链直编，绕开 SwiftPM 的原子写缓存。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFTC="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
SDK="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
PLUG="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
PLUG2="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins"

mkdir -p "$ROOT/build/out"

"$SWIFTC" \
  -parse-as-library -O \
  -target arm64-apple-macosx14.0 \
  -sdk "$SDK" \
  -plugin-path "$PLUG" \
  -plugin-path "$PLUG2" \
  -module-name AirLingo \
  -Xlinker -weak_framework -Xlinker Translation \
  -Xlinker -weak_framework -Xlinker _Translation_SwiftUI \
  $(find "$ROOT/Sources/AirLingo" -name '*.swift') \
  -o "$ROOT/build/out/AirLingo" || exit 1

python3 "$ROOT/scripts/assemble.py" || exit 1
echo "构建完成: $ROOT/build/AirLingo.app"
