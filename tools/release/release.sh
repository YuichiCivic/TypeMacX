#!/bin/bash
# Copyright (C) 2026 AIBOS Inc.
#
# TypeMacX の Mac 版を Sparkle の自動アップデートで配る準備をする (使い方は README.md)。
#   tools/release/release.sh [--notarize] <TypeMacX.app>
#
#   1. (--notarize のとき) Apple の公証 (notarytool) に出して、通ったら staple する
#   2. ditto で zip にする (TypeMacX-<版>.zip)
#   3. Sparkle の sign_update で EdDSA 署名する (表示と確かめのため)
#   4. Sparkle の generate_appcast で appcast.xml を作る / 更新する (署名・長さも入る)
#
# 環境変数:
#   TYPEMACX_RELEASE_DIR      zip と appcast.xml を置く場所 (既定: ~/Library/Caches/TypeMacX/release)。
#                             前の版の zip も残しておくと、appcast.xml に前の版も載り、差分 (delta) も作られる。
#   TYPEMACX_DOWNLOAD_PREFIX  zip を置く URL (既定: https://typemacx.com/downloads/)
#   TYPEMACX_NOTARY_PROFILE   notarytool のキーチェーン プロファイル名 (既定: typemacx-notary。README.md の「公証の準備」)
#   TYPEMACX_SPARKLE_ACCOUNT  EdDSA の秘密鍵のキーチェーンのアカウント名 (既定: typemacx)
#   SPARKLE_BIN               Sparkle の bin (generate_appcast など) の場所。無ければ mac/.build から探し、
#                             それも無ければ Package.swift と同じ版をダウンロードする。
set -euo pipefail

NOTARIZE=0
if [[ "${1:-}" == "--notarize" ]]; then NOTARIZE=1; shift; fi
APP="${1:-}"
[[ -d "$APP" && "$APP" == *.app ]] || { echo "使い方: $0 [--notarize] <TypeMacX.app>" >&2; exit 1; }
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RELEASE_DIR="${TYPEMACX_RELEASE_DIR:-$HOME/Library/Caches/TypeMacX/release}"
DOWNLOAD_PREFIX="${TYPEMACX_DOWNLOAD_PREFIX:-https://typemacx.com/downloads/}"
NOTARY_PROFILE="${TYPEMACX_NOTARY_PROFILE:-typemacx-notary}"
ACCOUNT="${TYPEMACX_SPARKLE_ACCOUNT:-typemacx}"
# Package.swift に固定した Sparkle の版 (ツールも同じ版を使う)
SPARKLE_VERSION="$(sed -n 's/.*sparkle-project\/Sparkle", exact: "\([0-9.]*\)".*/\1/p' "$ROOT/mac/Package.swift")"

# ---- Sparkle のツールを探す ----
find_sparkle_bin() {
    if [[ -n "${SPARKLE_BIN:-}" ]]; then echo "$SPARKLE_BIN"; return; fi
    local spm="$ROOT/mac/.build/artifacts/sparkle/Sparkle/bin"
    if [[ -x "$spm/generate_appcast" ]]; then echo "$spm"; return; fi
    local cache="$HOME/Library/Caches/TypeMacX/sparkle-$SPARKLE_VERSION"
    if [[ ! -x "$cache/bin/generate_appcast" ]]; then
        echo "Sparkle $SPARKLE_VERSION のツールをダウンロードします" >&2
        mkdir -p "$cache"
        curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
            | tar -xJf - -C "$cache"
    fi
    echo "$cache/bin"
}
SPARKLE="$(find_sparkle_bin)"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
echo "== TypeMacX $VERSION ($BUILD_NUMBER)"

# ---- 署名を確かめる (Developer ID でなければ、配布用ではないので警告する) ----
codesign --verify --deep --strict --verbose=2 "$APP"
if ! codesign -dvv "$APP" 2>&1 | grep -q "^Authority=Developer ID Application"; then
    echo "注意: Developer ID で署名されていません (TYPEMACX_MAC_IDENTITY を付けて mac/build.sh でビルドしてください)。" >&2
    [[ $NOTARIZE -eq 1 ]] && { echo "公証には Developer ID の署名が必要です" >&2; exit 1; }
fi

# ---- 1. 公証 ----
if [[ $NOTARIZE -eq 1 ]]; then
    echo "== 公証に出します (数分かかります)"
    NOTARY_ZIP="$(mktemp -d)/TypeMacX-notary.zip"
    ditto -c -k --keepParent "$APP" "$NOTARY_ZIP"
    xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=2 "$APP" || echo "注意: spctl の確認に通りませんでした (入力メソッドでは出ることがある)" >&2
    rm -f "$NOTARY_ZIP"
fi

# ---- 2. zip にする (staple した後の .app を入れる) ----
mkdir -p "$RELEASE_DIR"
ZIP="$RELEASE_DIR/TypeMacX-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "== zip: $ZIP"

# ---- 3. EdDSA 署名 ----
echo "== sign_update"
"$SPARKLE/sign_update" --account "$ACCOUNT" "$ZIP"

# ---- 4. appcast.xml ----
# リリースノート: 同じ場所に TypeMacX-<版>.html (または .md) を置くと、generate_appcast が自動で使う。
echo "== generate_appcast"
"$SPARKLE/generate_appcast" --account "$ACCOUNT" --download-url-prefix "$DOWNLOAD_PREFIX" \
    -o "$RELEASE_DIR/appcast.xml" "$RELEASE_DIR"

echo
echo "できました。次のファイルをサーバーに置いてください:"
echo "  $ZIP  →  ${DOWNLOAD_PREFIX}TypeMacX-$VERSION.zip"
echo "  $RELEASE_DIR/appcast.xml  →  https://typemacx.com/appcast.xml (Info.plist の SUFeedURL)"
ls "$RELEASE_DIR"/*.delta 2>/dev/null | sed 's/^/  (差分) /' || true
