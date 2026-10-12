#!/usr/bin/env bash
#
# build-videocut-native.sh — 构建"原生窗口"版 ClipFlow.app
# 与 build-videocut-app.sh 的区别：用 Swift + WKWebView 作为外壳，
# 双击打开的是真正的 macOS 原生窗口（不是浏览器），内部自动起本地服务并加载编辑器。
#
# 前置：需在装有 Xcode / Swift 的 Mac 上运行（沙箱内通常无 swiftc）。
#       若 swiftc 不在 PATH，可设置 SWIFTC="xcrun swiftc" 或指向 Xcode-beta 工具链。
#
set -euo pipefail
trap 'echo "[build] 失败于第 $LINENO 行：$BASH_COMMAND" >&2' ERR

APP_NAME="ClipFlow"
APP_VERSION="${APP_VERSION:-0.2.14}"
NODE_VERSION="${NODE_VERSION:-22.22.2}"

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${OUT_DIR:-$PWD}"
PKG_SRC="${PKG_SRC:-$(npm root -g 2>/dev/null)/@ffclip-com/videocut}"

NODE_ARM64_BIN="${NODE_ARM64_BIN:-}"
NODE_X64_BIN="${NODE_X64_BIN:-}"
INCLUDE_X64_NODE="${INCLUDE_X64_NODE:-1}"
SWIFTC="${SWIFTC:-swiftc}"
# 最低系统部署目标。必须显式指定：新工具链默认 minos 可能高于用户系统，
# 导致"应用程序的这个版本不能与此版本的 macOS 配合使用"。
MIN_MACOS="${MIN_MACOS:-13.0}"

APP="$OUT_DIR/$APP_NAME.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

[ -d "$PKG_SRC" ] || { echo "找不到工具包: $PKG_SRC" >&2; exit 1; }
if ! command -v "$SWIFTC" >/dev/null 2>&1; then
  echo "未找到 '$SWIFTC'。请在装有 Xcode 的 Mac 上运行，或设置 SWIFTC='xcrun swiftc'。" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$MACOS" "$RES/app"

echo "==> 用 $SWIFTC 编译原生窗口（通用二进制，部署目标 macOS ${MIN_MACOS}）..."
"$SWIFTC" "$SRC_DIR/main.swift" -O \
  -target "arm64-apple-macos${MIN_MACOS}" \
  -framework AppKit -framework WebKit -o "$MACOS/$APP_NAME.arm64"
"$SWIFTC" "$SRC_DIR/main.swift" -O \
  -target "x86_64-apple-macos${MIN_MACOS}" \
  -framework AppKit -framework WebKit -o "$MACOS/$APP_NAME.x86_64"
lipo -create "$MACOS/$APP_NAME.arm64" "$MACOS/$APP_NAME.x86_64" -output "$MACOS/$APP_NAME"
rm -f "$MACOS/$APP_NAME.arm64" "$MACOS/$APP_NAME.x86_64"

get_node() {
  local arch="$1" out="$2"
  if [ "$arch" = "arm64" ] && [ -n "${NODE_ARM64_BIN:-}" ]; then cp "$NODE_ARM64_BIN" "$out"; return; fi
  if [ "$arch" = "x64" ]   && [ -n "${NODE_X64_BIN:-}" ];   then cp "$NODE_X64_BIN"   "$out"; return; fi
  local url="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-darwin-${arch}.tar.gz"
  echo "==> 下载 node v$NODE_VERSION ($arch) ..."
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmp/n.tgz"
  tar -xzf "$tmp/n.tgz" -C "$tmp"
  cp "$tmp/node-v${NODE_VERSION}-darwin-${arch}/bin/node" "$out"
  rm -rf "$tmp"
}
get_node arm64 "$MACOS/node-arm64"
[ "${INCLUDE_X64_NODE:-1}" = "1" ] && get_node x64 "$MACOS/node-x64"

echo "==> 拷贝工具包 ..."
cp -R "$PKG_SRC/." "$RES/app/"
for f in LICENSE THIRD_PARTY_NOTICES.md README.md; do
  [ -f "$PKG_SRC/$f" ] && cp "$PKG_SRC/$f" "$RES/app/" 2>/dev/null || true
done
[ -d "$PKG_SRC/licenses" ] && cp -R "$PKG_SRC/licenses" "$RES/app/" 2>/dev/null || true
[ -f "$SRC_DIR/AppIcon.icns" ] && cp -f "$SRC_DIR/AppIcon.icns" "$RES/" || echo "警告：未找到 AppIcon.icns"

echo "==> 应用 ClipFlow 重品牌补丁 ..."
"$SRC_DIR/rebrand.sh" "$RES/app"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>com.clipflow.app</string>
  <key>CFBundleVersion</key><string>${APP_VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${APP_VERSION}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <!-- 允许 WKWebView 加载本地 http://127.0.0.1 服务（ATS 默认拦截明文 HTTP，会导致白屏） -->
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key><true/>
  </dict>
</dict>
</plist>
PLIST

echo "==> 完成: $APP"
du -sh "$APP"
echo "==> 双击 $APP 即可打开原生窗口（内部自动起本地服务并加载编辑器）"
echo "==> 分发：zip -r ClipFlow-native-unsigned.zip ClipFlow.app"
