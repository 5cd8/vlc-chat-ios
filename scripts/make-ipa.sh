#!/bin/bash
# 署名なしipa（SideStoreが取り込む用）と、偽署名(ldid -S)のipaを作る。
# 署名が要る -exportArchive は使わず、archive の成果物の .app を Payload/ に詰めて zip する。
set -euo pipefail

cd "$(dirname "$0")/.."
# tee の出力先が無いと、キャッシュなしの初回で pipefail により失敗する。
mkdir -p build

BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}"
APP_NAME=VLCWithChat

xcodebuild archive \
  -project "$APP_NAME.xcodeproj" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "build/$APP_NAME.xcarchive" \
  -clonedSourcePackagesDirPath build/SourcePackages \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO AD_HOC_CODE_SIGNING_ALLOWED=YES \
  2>&1 | tee build/xcodebuild.log

rm -rf build/ipa build/ipa-fake build/*.ipa
mkdir -p build/ipa/Payload
cp -R "build/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app" build/ipa/Payload/
# ipaのルートが Payload/ になるよう、build/ipa の中で zip する。
(cd build/ipa && zip -qry ../vlc-with-chat-unsigned.ipa Payload)

# チェック1が外れたときの往復を減らすため、偽署名版も作る（SideStore自身のMakefileと同じ手順）。
# 実行ファイルにかける（.app ではなく）。unsigned側を汚さないよう、コピーに対して行う。
cp -R build/ipa build/ipa-fake
ldid -S "build/ipa-fake/Payload/$APP_NAME.app/$APP_NAME"
(cd build/ipa-fake && zip -qry ../vlc-with-chat-fakesigned.ipa Payload)

# できたipaを機械的に確かめる。
for ipa in build/vlc-with-chat-unsigned.ipa build/vlc-with-chat-fakesigned.ipa; do
  rm -rf build/verify
  mkdir -p build/verify
  unzip -q "$ipa" -d build/verify
  if [ "$(ls build/verify)" != "Payload" ] || [ "$(ls build/verify/Payload)" != "$APP_NAME.app" ]; then
    echo "ipaのルートが Payload/$APP_NAME.app になっていない: $ipa" >&2
    exit 1
  fi
  plist="build/verify/Payload/$APP_NAME.app/Info.plist"
  if ! plutil -extract UIBackgroundModes json -o - "$plist" | grep -q '"audio"'; then
    echo "UIBackgroundModes に audio が無い: $ipa" >&2
    exit 1
  fi
  actual="$(plutil -extract CFBundleVersion raw -o - "$plist")"
  if [ "$actual" != "$BUILD_NUMBER" ]; then
    echo "CFBundleVersion が実行番号($BUILD_NUMBER)でない: $actual ($ipa)" >&2
    exit 1
  fi
done
rm -rf build/verify
echo "ipa OK: build=$BUILD_NUMBER"
ls -l build/*.ipa
