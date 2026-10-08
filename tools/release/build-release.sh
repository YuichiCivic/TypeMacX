#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 AIBOS Inc.
#
# 配る TypeMacX (無料版・GPL) の一式を作る。ふつうは publish.sh から呼ぶ。
#   1. ビルドして Developer ID で署名する (mac/build.sh)
#   2. .app を公証 (notarization) に出して staple する
#   3. 自動アップデート用の zip を作り、Sparkle の EdDSA 鍵で署名して appcast.xml を作る
#   4. /Library/Input Methods に入れる pkg を作り、Developer ID Installer で署名して公証する
#   5. GPL のためのソースコード一式 (TypeMacX-source-<版>.zip) と、渡す人向けの説明を添える
#
#   tools/release/build-release.sh            署名・公証まで (配る用)
#   tools/release/build-release.sh --unsigned 証明書が無くても作る (手元の確認用。配らない)
#
# 環境変数 (tools/release/README.md):
#   TYPEMACX_MAC_IDENTITY        "Developer ID Application: <名前> (<TEAMID>)"
#   TYPEMACX_INSTALLER_IDENTITY  "Developer ID Installer: <名前> (<TEAMID>)"
#   TYPEMACX_NOTARY_PROFILE      notarytool のキーチェーン プロファイル (既定 typemacx-notary)
#   TYPEMACX_SPARKLE_ACCOUNT     Sparkle の EdDSA 秘密鍵のキーチェーンのアカウント (既定 typemacx)
#   TYPEMACX_DOWNLOAD_PREFIX     アップデートの zip を置く URL (publish.sh が GitHub Releases の URL を渡す)
#   TYPEMACX_RELEASE_DIR         作業場所 (既定 ~/Library/Caches/TypeMacX/release)
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"

UNSIGNED=0
[[ "${1:-}" == "--unsigned" ]] && UNSIGNED=1

NOTARY_PROFILE="${TYPEMACX_NOTARY_PROFILE:-typemacx-notary}"
ACCOUNT="${TYPEMACX_SPARKLE_ACCOUNT:-typemacx}"
# iCloud で同期しているフォルダでは codesign が失敗するので、作業場所は同期していない所にする
WORK="${TYPEMACX_RELEASE_DIR:-$HOME/Library/Caches/TypeMacX/release}"
export SWIFT="${SWIFT:-$HOME/Library/Developer/Toolchains/swift-6.3.3-RELEASE.xctoolchain/usr/bin/swift}"
export PATH="$HOME/.dotnet:$PATH" DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"

if [[ $UNSIGNED -eq 0 ]]; then
    : "${TYPEMACX_MAC_IDENTITY:?Developer ID Application の証明書の名前を TYPEMACX_MAC_IDENTITY に入れてください}"
    : "${TYPEMACX_INSTALLER_IDENTITY:?Developer ID Installer の証明書の名前を TYPEMACX_INSTALLER_IDENTITY に入れてください}"
else
    unset TYPEMACX_MAC_IDENTITY
fi

# ---- Sparkle のツール (generate_appcast・sign_update)。Package.swift と同じ版を使う ----
SPARKLE_VERSION="$(sed -n 's/.*sparkle-project\/Sparkle", exact: "\([0-9.]*\)".*/\1/p' "$ROOT/mac/Package.swift")"
find_sparkle_bin() {
    if [[ -n "${SPARKLE_BIN:-}" ]]; then echo "$SPARKLE_BIN"; return; fi
    local spm="$ROOT/mac/.build/artifacts/sparkle/Sparkle/bin"
    if [[ -x "$spm/generate_appcast" ]]; then echo "$spm"; return; fi
    local cache="$HOME/Library/Caches/TypeMacX/sparkle-$SPARKLE_VERSION"
    if [[ ! -x "$cache/bin/generate_appcast" ]]; then
        echo "Sparkle $SPARKLE_VERSION のツールをダウンロードします" >&2
        mkdir -p "$cache"
        curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" | tar -xJf - -C "$cache"
    fi
    echo "$cache/bin"
}

notarize() {
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

rm -rf "$WORK"
mkdir -p "$WORK/build"

echo "== 1/5 ビルド"
TYPEMACX_EDITION=free TYPEMACX_BUILD_DIR="$WORK/build" "$ROOT/mac/build.sh" --no-install
APP="$WORK/build/TypeMacX.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
NAME="TypeMacX-$VERSION"
OUT="$WORK/dist"
mkdir -p "$OUT"

echo "== 2/5 .app の公証"
if [[ $UNSIGNED -eq 0 ]]; then
    ditto -c -k --keepParent "$APP" "$WORK/notary-app.zip"
    notarize "$WORK/notary-app.zip"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
else
    echo "--unsigned なので飛ばします"
fi

echo "== 3/5 自動アップデート用の zip と appcast.xml"
# appcast.xml には、この版だけを載せる (GitHub Releases は版ごとに URL が違うので、前の版を載せるとリンクが合わなくなる)
mkdir -p "$WORK/updates"
ditto -c -k --keepParent "$APP" "$WORK/updates/$NAME.zip"
[[ -f "$ROOT/tools/release/notes/$VERSION.md" ]] && cp "$ROOT/tools/release/notes/$VERSION.md" "$WORK/updates/$NAME.md"
if [[ $UNSIGNED -eq 0 ]]; then
    SPARKLE="$(find_sparkle_bin)"
    "$SPARKLE/generate_appcast" --account "$ACCOUNT" --embed-release-notes \
        --download-url-prefix "${TYPEMACX_DOWNLOAD_PREFIX:-https://example.invalid/}" \
        -o "$OUT/appcast.xml" "$WORK/updates"
else
    echo "--unsigned なので appcast.xml は作りません"
fi
cp "$WORK/updates/$NAME.zip" "$OUT/"

echo "== 4/5 pkg"
PKGROOT="$WORK/pkgroot"
mkdir -p "$PKGROOT/Library/Input Methods"
ditto "$APP" "$PKGROOT/Library/Input Methods/TypeMacX.app"
# pkgbuild は、同じ Bundle ID のアプリが別の場所にあるとそちらへ上書きしてしまう (relocation)。
# 中の Sparkle の部品も含めて、必ず /Library/Input Methods に入れる。
pkgbuild --analyze --root "$PKGROOT" "$WORK/component.plist" >/dev/null
count="$(/usr/libexec/PlistBuddy -c Print "$WORK/component.plist" | grep -c BundleIsRelocatable)"
for ((i = 0; i < count; i++)); do
    plutil -replace "$i.BundleIsRelocatable" -bool NO "$WORK/component.plist"
done
pkgbuild --root "$PKGROOT" --component-plist "$WORK/component.plist" \
    --scripts "$ROOT/tools/release/pkg-scripts" \
    --identifier jp.co.aibos.pkg.TypeMacX --version "$VERSION" --install-location / \
    "$WORK/TypeMacX-component.pkg"
mkdir -p "$WORK/resources"
cp "$ROOT/LICENSE" "$WORK/resources/LICENSE.txt"
cp "$ROOT/tools/release/pkg-resources/"*.html "$WORK/resources/"
sed "s/@VERSION@/$VERSION/g" "$ROOT/tools/release/pkg-resources/distribution.xml" > "$WORK/distribution.xml"
SIGN_ARGS=()
[[ $UNSIGNED -eq 0 ]] && SIGN_ARGS=(--sign "$TYPEMACX_INSTALLER_IDENTITY" --timestamp)
productbuild --distribution "$WORK/distribution.xml" --resources "$WORK/resources" \
    --package-path "$WORK" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} "$OUT/$NAME.pkg"
if [[ $UNSIGNED -eq 0 ]]; then
    notarize "$OUT/$NAME.pkg"
    xcrun stapler staple "$OUT/$NAME.pkg"
    spctl -a -vv -t install "$OUT/$NAME.pkg"
fi

echo "== 5/5 ソースコードと説明"
# GPL v3 第6条: バイナリを渡すときは、対応するソースコードも渡す。コミット済みの内容をそのまま固める。
if [[ -n "$(git status --porcelain)" ]]; then
    echo "注意: コミットしていない変更があります。ソース zip はコミット済みの HEAD から作ります" >&2
fi
git archive --format=zip --prefix="TypeMacX-source-$VERSION/" -o "$OUT/TypeMacX-source-$VERSION.zip" HEAD
mkdir -p "$WORK/$NAME"
cp "$OUT/$NAME.pkg" "$OUT/TypeMacX-source-$VERSION.zip" "$ROOT/LICENSE" "$WORK/$NAME/"
mv "$WORK/$NAME/LICENSE" "$WORK/$NAME/LICENSE.txt"
cp "$ROOT/tools/release/pkg-resources/はじめにお読みください.txt" "$WORK/$NAME/"
(cd "$WORK" && ditto -c -k --keepParent "$NAME" "$OUT/$NAME-手渡し用.zip")

echo
echo "できました: $OUT"
ls -1 "$OUT" | sed 's/^/  /'
