#!/usr/bin/env bash
# 在 macOS 上本地一键打出未签名 IPA（与 GitHub Actions 完全同一条流水线）
# 用法：bash tools/build_ipa.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "缺少 xcodegen，请先执行：brew install xcodegen"
  exit 1
fi

echo "==> 生成 Xcode 工程"
xcodegen generate --spec project.yml --project .
xcodebuild -list -project KanAV.xcodeproj

echo "==> 编译（未签名）"
xcodebuild \
  -project KanAV.xcodeproj \
  -scheme KanAV \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="build/Build/Products/Release-iphoneos/KanAV.app"
[ -d "$APP_PATH" ] || { echo "编译产物缺失：$APP_PATH"; exit 1; }

echo "==> 打包 IPA"
rm -rf Payload KanAV-unsigned.ipa
mkdir -p Payload
cp -R "$APP_PATH" Payload/KanAV.app
rm -rf Payload/KanAV.app/_CodeSignature
xattr -cr Payload/KanAV.app || true
zip -qry KanAV-unsigned.ipa Payload
rm -rf Payload

ls -lh KanAV-unsigned.ipa
shasum -a 256 KanAV-unsigned.ipa
echo "==> 完成：$(pwd)/KanAV-unsigned.ipa"
