#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 AIBOS Inc.
#
# ライセンスキーの発行ツール (.build/typemacx-license) をコンパイルする。
# アプリと同じ検証コード (mac/Sources/TypeMacXIME/License/LicenseKey.swift) を一緒にコンパイルする。
# 使う swiftc は SWIFTC=... で変えられる (コマンドライン ツールの swift が壊れている Mac 用)。
set -euo pipefail
cd "$(dirname "$0")"

SWIFTC="${SWIFTC:-swiftc}"
mkdir -p .build
"$SWIFTC" -O -sdk "$(xcrun --show-sdk-path)" \
    main.swift ../../mac/Sources/TypeMacXIME/License/LicenseKey.swift \
    -o .build/typemacx-license
echo "作成しました: $(pwd)/.build/typemacx-license"
