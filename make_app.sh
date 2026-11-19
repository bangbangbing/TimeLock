#!/bin/bash
# 构建 TimeLock.app（Universal: x86_64 + arm64），失败时回退单架构
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="TimeLock"
APP_DIR="build/$APP_NAME.app"

echo "==> Building x86_64 slice..."
swift build -c release --arch x86_64 --scratch-path .build-x64

BINARY="$PWD/.build-x64/release/$APP_NAME"
if swift build -c release --arch arm64 --scratch-path .build-arm; then
    echo "==> Creating universal binary (x86_64 + arm64)..."
    lipo -create ".build-x64/release/$APP_NAME" ".build-arm/release/$APP_NAME" -output ".build-x64/release/$APP_NAME-universal"
    BINARY="$PWD/.build-x64/release/$APP_NAME-universal"
else
    echo "==> arm64 build failed, producing Intel-only binary (x86_64)."
fi

echo "==> Bundling $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BINARY" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "==> Ad-hoc code signing (stable identifier, TCC 授权在重打包后仍有效)..."
REQ_FILE="$(mktemp)"
printf 'designated => identifier "com.zhougj.timelock"\n' > "$REQ_FILE"
codesign --force --sign - --identifier com.zhougj.timelock \
    --requirements "$REQ_FILE" "$APP_DIR"
rm -f "$REQ_FILE"

lipo -info "$APP_DIR/Contents/MacOS/$APP_NAME" || true
echo "==> Done: $APP_DIR"
