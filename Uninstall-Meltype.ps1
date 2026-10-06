# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Yukishiro

param(
    # 設定と学習データ (%LOCALAPPDATA%\Meltype) も削除する
    [switch]$RemoveData
)
$ErrorActionPreference = 'Stop'

$shortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\Meltype.lnk'
if (Test-Path -LiteralPath $shortcut) { Remove-Item -LiteralPath $shortcut -Force }
Get-Process Meltype, meltype_mozc_helper -ErrorAction SilentlyContinue | Stop-Process -Force

if ($RemoveData) {
    $data = Join-Path $env:LOCALAPPDATA 'Meltype'
    if (Test-Path -LiteralPath $data) { Remove-Item -LiteralPath $data -Recurse -Force }
    Write-Host 'Meltype を停止し、自動起動と設定・学習データを削除しました。'
} else {
    Write-Host 'Meltype を停止し、自動起動から外しました。設定と学習データは %LOCALAPPDATA%\Meltype に残っています (-RemoveData で削除)。'
}
