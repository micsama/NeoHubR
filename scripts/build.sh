#!/usr/bin/env bash

set -euo pipefail

# 切换到脚本所在目录的父目录（项目根目录）
cd "$(dirname "$0")/.."

APP_NAME="NeoHubR"
BUILD_DIR="./build"
DIST_DIR="$BUILD_DIR/dist"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
BG_IMG="./scripts/dmg_background.png"
BG_IMG_RESIZED="$BUILD_DIR/bg_resized.png"
DERIVED_DATA="$BUILD_DIR/derived"

# 1. 先构建 Release app 到 build 目录
echo "▶ 正在构建 $APP_NAME Release..."
xcodebuild -quiet -project NeoHubR.xcodeproj -scheme "$APP_NAME" -configuration Release build \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  1>/dev/null

mkdir -p "$BUILD_DIR"
rm -rf "$APP_PATH" # 关键修复：确保先删除旧的 .app，防止嵌套
cp -R "$DERIVED_DATA/Build/Products/Release/$APP_NAME.app" "$APP_PATH"

# 2. 提取版本号
APP_VERSION=$(defaults read "$(realpath "$APP_PATH")/Contents/Info" CFBundleShortVersionString)
OUTPUT_DMG="$DIST_DIR/${APP_NAME}_v${APP_VERSION}.dmg"

# 3. 准备输出目录
mkdir -p "$DIST_DIR"
rm -f "$OUTPUT_DMG"

# 4. 调整背景图片尺寸（匹配窗口大小 600x400）
echo "▶ 正在调整背景图片尺寸..."
sips -z 400 600 "$BG_IMG" --out "$BG_IMG_RESIZED" 1>/dev/null

# 5. 制作 DMG
echo "▶ 正在从 $APP_PATH 制作 DMG 到 $DIST_DIR ..."

create-dmg \
  --volname "${APP_NAME} Installer" \
  --background "$BG_IMG_RESIZED" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 150 200 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 450 200 \
  "$OUTPUT_DMG" \
  "$APP_PATH"

# 6. 清理临时文件
rm -f "$BG_IMG_RESIZED"

echo "✅ 大功告成！成品在: $OUTPUT_DMG"
