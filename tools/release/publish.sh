#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 AIBOS Inc.
#
# TypeMacX の新しい版を出す (これ 1 つで、配布もアップデートも済む)。
#   tools/release/publish.sh 0.2.0
#
#   1. 版を上げてコミットし、タグ v0.2.0 を付ける (Info.plist の CFBundleShortVersionString / CFBundleVersion)
#   2. build-release.sh で、署名・公証した pkg / アップデート用 zip / appcast.xml / ソース zip を作る
#   3. GitHub に push して、GitHub Releases に上げる
#      → 入れている人の TypeMacX が「新しい版があります」と知らせる (Sparkle、1 日 1 回確認)
#
# リリースノート: tools/release/notes/<版>.md を先に書いておく (無ければ前の版からのコミットの一覧で作る)。
# 証明書などの準備は tools/release/README.md。
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"
PLIST="$ROOT/mac/Resources/Info.plist"

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "使い方: $0 <版 (例 0.2.0)>" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "コミットしていない変更があります。先にコミットしてください" >&2; exit 1; }
git rev-parse "v$VERSION" >/dev/null 2>&1 && { echo "v$VERSION はもうあります" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh にログインしてください (gh auth login)" >&2; exit 1; }
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

CURRENT="$(plutil -extract CFBundleShortVersionString raw "$PLIST")"
newer() { [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]; }
# 初めて出すときだけは今の版と同じでよい。2 回目からは今の版より大きくする (Sparkle が新しい版と分かるように)
if git tag -l 'v*' | grep -q . || [[ "$CURRENT" != "$VERSION" ]]; then
    newer "$VERSION" "$CURRENT" || { echo "版は今の $CURRENT より大きくしてください" >&2; exit 1; }
fi

echo "== 1/3 版を $VERSION に上げる ($REPO)"
BUILD_NUMBER=$(( $(plutil -extract CFBundleVersion raw "$PLIST") + 1 ))
plutil -replace CFBundleShortVersionString -string "$VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$PLIST"
NOTES="$ROOT/tools/release/notes/$VERSION.md"
if [[ ! -f "$NOTES" ]]; then
    mkdir -p "$(dirname "$NOTES")"
    LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
    { echo "## TypeMacX $VERSION"; echo; git log --format='- %s' ${LAST_TAG:+"$LAST_TAG"..HEAD}; } > "$NOTES"
fi
git add "$PLIST" "$NOTES"
git commit -qm "Release v$VERSION"
git tag "v$VERSION"
# push する前に失敗したら、版上げのコミットとタグを取り消して、同じ版でやり直せるようにする
PUSHED=0
undo() { [[ $PUSHED -eq 0 ]] && { git tag -d "v$VERSION" >/dev/null; git reset -q --hard HEAD~1; echo "失敗したので、版上げを取り消しました" >&2; }; }
trap undo ERR

echo "== 2/3 ビルド・署名・公証"
TYPEMACX_FEED_URL="https://github.com/$REPO/releases/latest/download/appcast.xml" \
TYPEMACX_DOWNLOAD_PREFIX="https://github.com/$REPO/releases/download/v$VERSION/" \
TYPEMACX_SUPPORT_URL="https://github.com/$REPO/issues" \
TYPEMACX_SOURCE_URL="https://github.com/$REPO" \
    "$ROOT/tools/release/build-release.sh"
OUT="${TYPEMACX_RELEASE_DIR:-$HOME/Library/Caches/TypeMacX/release}/dist"

echo "== 3/3 GitHub Releases に上げる"
git push origin HEAD "v$VERSION"
PUSHED=1
gh release create "v$VERSION" --title "TypeMacX $VERSION" --notes-file "$NOTES" \
    "$OUT/TypeMacX-$VERSION.pkg" \
    "$OUT/TypeMacX-$VERSION.zip" \
    "$OUT/TypeMacX-source-$VERSION.zip" \
    "$OUT/appcast.xml"

echo
echo "出しました: https://github.com/$REPO/releases/tag/v$VERSION"
echo "  はじめて渡す人には: TypeMacX-$VERSION.pkg (または $OUT/TypeMacX-$VERSION-手渡し用.zip)"
echo "  入れている人には: TypeMacX が自動で知らせます (メニューの「アップデートを確認…」ですぐ確かめられる)"
