#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 AIBOS Inc.
#
# ライセンスキーの発行と検証を確かめる (アプリと同じ LicenseKey.swift の検証を使う)。
#   SWIFTC=... ./test.sh
# 使い捨ての鍵で試すので、private/ の本物の秘密鍵は使わない (最後の 1 件だけ、あれば本物の鍵と埋め込みの公開鍵で試す)。
set -uo pipefail
cd "$(dirname "$0")"
./build.sh >/dev/null || exit 1
TOOL="$(pwd)/.build/typemacx-license"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PRIV="$WORK/test.key"
PUB="$WORK/test.pub"
failed=0

check() { # 名前 期待する終了コード コマンド...
    local name="$1" expected="$2"; shift 2
    local output code
    output="$("$@" 2>&1)"; code=$?
    if [[ $code -eq $expected ]]; then echo "ok   $name"; else echo "FAIL $name (終了コード $code、期待 $expected): $output"; failed=1; fi
}

"$TOOL" keygen --private-key "$PRIV" --public-key "$PUB" >/dev/null
KEY="$("$TOOL" issue --email test@example.com --name "山田 太郎" --purchased 2026-10-01 --private-key "$PRIV")"
echo "発行したキー (${#KEY} 文字): ${KEY:0:40}…"

check "正しいキーを受け付ける" 0 "$TOOL" verify "$KEY" --public-key "$PUB"
check "アップデート期間内のビルド" 0 "$TOOL" verify "$KEY" --public-key "$PUB" --build-date 2027-10-01
check "アップデート期間より後のビルドは断る" 5 "$TOOL" verify "$KEY" --public-key "$PUB" --build-date 2027-10-02
# 改行・空白を挟んで貼り付けても通る
check "途中の改行・空白は無視する" 0 "$TOOL" verify "$(echo "$KEY" | fold -w 60)  " --public-key "$PUB"

# ペイロードの 1 文字を書き換える
body="${KEY#TMX1-}"
c="${body:10:1}"; [[ "$c" == "A" ]] && r="B" || r="A"
TAMPERED="TMX1-${body:0:10}${r}${body:11}"
check "書き換えたキーは断る" 3 "$TOOL" verify "$TAMPERED" --public-key "$PUB"
check "別の鍵の公開鍵では断る" 3 "$TOOL" verify "$KEY"   # 埋め込みの公開鍵 (テスト用の鍵とは別)
check "形式が違うキーは断る" 2 "$TOOL" verify "TMX1-abc" --public-key "$PUB"
check "接頭辞が無いキーは断る" 2 "$TOOL" verify "${KEY#TMX1-}" --public-key "$PUB"
SETAPP="$("$TOOL" issue --email a@b.c --name x --edition setapp --private-key "$PRIV")"
check "直販版以外のキーは断る" 4 "$TOOL" verify "$SETAPP" --public-key "$PUB"

if [[ -f private/typemacx-license.key ]]; then
    REAL="$("$TOOL" issue --email dev@aibos.co.jp --name "開発用")"
    check "本物の秘密鍵 + アプリに埋め込んだ公開鍵" 0 "$TOOL" verify "$REAL" --build-date "$(date -u +%Y-%m-%d)"
fi

[[ $failed -eq 0 ]] && echo "すべて通りました" || { echo "失敗したテストがあります"; exit 1; }
