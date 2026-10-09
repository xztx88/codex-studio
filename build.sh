#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Codex Studio"
VERSION="1.0.0"
BUILD_DIR="$SCRIPT_DIR/build"
DIST_DIR="$SCRIPT_DIR/dist"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
DEST_APP="/Applications/$APP_NAME.app"

echo "🔨 正在多架构交叉编译 $APP_NAME (Universal 2: Apple Silicon arm64 + Intel x86_64) ..."
mkdir -p "$BUILD_DIR"
mkdir -p "$DIST_DIR"

# 1. 编译 Apple Silicon (arm64)
echo "  -> 编译 arm64 架构..."
swiftc -parse-as-library \
    -target arm64-apple-macos14.0 \
    -framework SwiftUI \
    -framework AppKit \
    -O \
    "$SCRIPT_DIR/src/"*.swift \
    -o "$BUILD_DIR/$APP_NAME-arm64"

# 2. 编译 Intel (x86_64)
echo "  -> 编译 x86_64 架构..."
swiftc -parse-as-library \
    -target x86_64-apple-macos14.0 \
    -framework SwiftUI \
    -framework AppKit \
    -O \
    "$SCRIPT_DIR/src/"*.swift \
    -o "$BUILD_DIR/$APP_NAME-x86_64"

# 3. lipo 合并为 Universal 2 通用二进制
echo "  -> 合并为 Universal 2 通用二进制..."
lipo -create "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64" -output "$BUILD_DIR/$APP_NAME"

echo "📦 正在生成应用包 $APP_NAME.app ..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [ -f "$SCRIPT_DIR/assets/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat << 'EOF' > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>Codex Studio</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.zcj.codex.studio</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Codex Studio</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Ad-hoc code sign for local running
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "🚀 安装到本机 /Applications ..."
rm -rf "$DEST_APP"
cp -R "$APP_BUNDLE" "$DEST_APP"

# 4. 生成可分发的 DMG 安装镜像与 ZIP 包
echo "💿 正在打包对外分发安装包 (DMG & ZIP) ..."
DMG_STAGING="$BUILD_DIR/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# 复制 App 与 Applications 替身
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# 生成解除 Gatekeeper 隔离的便捷脚本
cat << 'EOF' > "$DMG_STAGING/一键解除已损坏提示(打开前运行一次).command"
#!/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "=========================================="
echo "  Codex Studio - 解除 macOS 安全隔离限制"
echo "=========================================="
echo ""
echo "正在移除系统的 com.apple.quarantine 隔离标记..."
xattr -cr "/Applications/Codex Studio.app" 2>/dev/null || true
xattr -cr "$DIR/Codex Studio.app" 2>/dev/null || true
echo "✅ 解除成功！现在您可以直接双击打开 Codex Studio。"
echo ""
echo "按 Enter 键退出本窗口..."
read -r
EOF
chmod +x "$DMG_STAGING/一键解除已损坏提示(打开前运行一次).command"

# 使用说明
cat << 'EOF' > "$DMG_STAGING/使用说明与常见问题.txt"
Codex Studio v1.0.0 (macOS 原生 Universal 版)
============================================================
【架构支持】
同时原生支持 Apple Silicon（M1/M2/M3/M4）以及 Intel 芯片 Mac。
零外部依赖（不需要安装 Python、Node 或 Xcode 命令行工具），即装即用。

【安装步骤】
1. 将「Codex Studio.app」拖拽至右侧「Applications」文件夹中；
2. 在「应用程序」中双击打开「Codex Studio」。

【若打开时提示“已损坏，无法打开”或“无法验证开发者”】
这是 macOS 对非 App Store 下载软件的默认 Gatekeeper 隔离保护机制。
解决方法任选其一：
- 推荐方式：双击本镜像内的「一键解除已损坏提示(打开前运行一次).command」；
- 终端方式：打开「终端」App，粘贴执行以下命令：
  xattr -cr "/Applications/Codex Studio.app"
- 系统设置：进入 Mac「系统设置」->「隐私与安全性」，滑到最底部点击「仍要打开」。
============================================================
EOF

DMG_FILE="$DIST_DIR/Codex-Studio-v${VERSION}-macOS-Universal.dmg"
rm -f "$DMG_FILE"
hdiutil create -volname "Codex Studio" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_FILE" -quiet

ZIP_FILE="$DIST_DIR/Codex-Studio-v${VERSION}-macOS-Universal.zip"
rm -f "$ZIP_FILE"
cd "$BUILD_DIR"
ditto -c -k --keepParent "dmg_staging" "$ZIP_FILE"
cd "$SCRIPT_DIR"

echo "✅ 打包完成！"
echo "  -> 本地已安装: $DEST_APP"
echo "  -> 分发 DMG 镜像: $DMG_FILE"
echo "  -> 分发 ZIP 压缩包: $ZIP_FILE"
