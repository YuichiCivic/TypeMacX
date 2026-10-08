#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 AIBOS Inc.
#
# 無料版 (GPL) の TypeMacX を、知人に直接渡せる形にまとめる。
#   1. 無料版・自動アップデート無しでビルドし、Developer ID で署名する (mac/build.sh)
#   2. /Library/Input Methods に入れる pkg を作り、Developer ID Installer で署名する
#   3. 公証 (notarization) を通して staple する
#   4. GPL のためのソースコード一式 (TypeMacX-source-<版>.zip) と、渡す人向けの説明を添える
#
# 必要なもの (はじめに一度だけ、tools/release/README.md の「無料版を配る」を参照):
#   TYPEMACX_MAC_IDENTITY        "Developer ID Application: <名前> (<TEAMID>)"
#   TYPEMACX_INSTALLER_IDENTITY  "Developer ID Installer: <名前> (<TEAMID>)"
#   notarytool のキーチェーン プロファイル (既定 typemacx-notary、TYPEMACX_NOTARY_PROFILE で変える)
#
#   tools/release/make-free-release.sh            署名・公証まで
#   tools/release/make-free-release.sh --unsigned 証明書が無くても、自分で署名した pkg を作る (手元の確認用。配らない)
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"

UNSIGNED=0
[[ "${1:-}" == "--unsigned" ]] && UNSIGNED=1

NOTARY_PROFILE="${TYPEMACX_NOTARY_PROFILE:-typemacx-notary}"
# iCloud で同期しているフォルダでは codesign が失敗するので、作業場所は同期していない所にする
WORK="${TYPEMACX_RELEASE_DIR:-$HOME/Library/Caches/TypeMacX/free-release}"
export SWIFT="${SWIFT:-$HOME/Library/Developer/Toolchains/swift-6.3.3-RELEASE.xctoolchain/usr/bin/swift}"
export PATH="$HOME/.dotnet:$PATH" DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"

if [[ $UNSIGNED -eq 0 ]]; then
    : "${TYPEMACX_MAC_IDENTITY:?Developer ID Application の証明書の名前を TYPEMACX_MAC_IDENTITY に入れてください}"
    : "${TYPEMACX_INSTALLER_IDENTITY:?Developer ID Installer の証明書の名前を TYPEMACX_INSTALLER_IDENTITY に入れてください}"
else
    unset TYPEMACX_MAC_IDENTITY
fi

rm -rf "$WORK"
mkdir -p "$WORK/build"

echo "== 1/4 無料版をビルド"
TYPEMACX_EDITION=free TYPEMACX_UPDATES=0 TYPEMACX_BUILD_DIR="$WORK/build" \
    "$ROOT/mac/build.sh" --no-install
APP="$WORK/build/TypeMacX.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
NAME="TypeMacX-$VERSION"
OUT="$WORK/$NAME"
mkdir -p "$OUT"

echo "== 2/4 pkg を作る"
PKGROOT="$WORK/pkgroot"
mkdir -p "$PKGROOT/Library/Input Methods"
ditto "$APP" "$PKGROOT/Library/Input Methods/TypeMacX.app"
# pkgbuild は、同じ Bundle ID のアプリが別の場所にあるとそちらへ上書きしてしまう (relocation)。必ず /Library/Input Methods に入れる。
pkgbuild --analyze --root "$PKGROOT" "$WORK/component.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/component.plist"
pkgbuild --root "$PKGROOT" --component-plist "$WORK/component.plist" \
    --scripts "$ROOT/tools/release/pkg-scripts" \
    --identifier jp.co.aibos.pkg.TypeMacX --version "$VERSION" --install-location / \
    "$WORK/TypeMacX-component.pkg"

mkdir -p "$WORK/resources"
cp "$ROOT/LICENSE" "$WORK/resources/LICENSE.txt"
cp "$ROOT/tools/release/pkg-resources/"* "$WORK/resources/"
sed "s/@VERSION@/$VERSION/g" "$ROOT/tools/release/pkg-resources/distribution.xml" > "$WORK/distribution.xml"
SIGN_ARGS=()
[[ $UNSIGNED -eq 0 ]] && SIGN_ARGS=(--sign "$TYPEMACX_INSTALLER_IDENTITY" --timestamp)
productbuild --distribution "$WORK/distribution.xml" --resources "$WORK/resources" \
    --package-path "$WORK" "${SIGN_ARGS[@]}" "$OUT/$NAME.pkg"

if [[ $UNSIGNED -eq 0 ]]; then
    echo "== 3/4 公証 (数分かかります)"
    xcrun notarytool submit "$OUT/$NAME.pkg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$OUT/$NAME.pkg"
    xcrun stapler validate "$OUT/$NAME.pkg"
    spctl -a -vv -t install "$OUT/$NAME.pkg"
else
    echo "== 3/4 公証: --unsigned なので飛ばします (この pkg は配らないでください)"
fi

echo "== 4/4 ソースコードと説明を添える"
# GPL v3 第6条: バイナリを渡すときは、対応するソースコードも渡す。コミット済みの内容をそのまま固める。
if [[ -n "$(git status --porcelain)" ]]; then
    echo "注意: コミットしていない変更があります。ソース zip はコミット済みの HEAD から作るので、先にコミットしてください" >&2
fi
git archive --format=zip --prefix="TypeMacX-source-$VERSION/" -o "$OUT/TypeMacX-source-$VERSION.zip" HEAD
cp "$ROOT/tools/release/pkg-resources/はじめにお読みください.txt" "$OUT/"
cp "$ROOT/LICENSE" "$OUT/LICENSE.txt"
(cd "$WORK" && ditto -c -k --keepParent "$NAME" "$NAME.zip")

echo
echo "できました: $WORK/$NAME.zip"
echo "  中身: $NAME.pkg / TypeMacX-source-$VERSION.zip / はじめにお読みください.txt / LICENSE.txt"
