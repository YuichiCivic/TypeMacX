#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Yukishiro
#
# TypeMacX の Mac 版をビルドして ~/Library/Input Methods にインストールする。
#   ./build.sh            ビルドしてインストール
#   ./build.sh --no-install  ビルドだけ (build/TypeMacX.app)
# 必要なもの: macOS 13 以降、Xcode (またはコマンドライン ツール: xcode-select --install)、.NET 10 SDK
set -euo pipefail
cd "$(dirname "$0")"

INSTALL=1
# 入力ソースの「+」の一覧に TypeMacX が出ない Mac がある (自分で署名した版、macOS 26、#21)。
# ことえりと同じ形で、有効な入力ソースの一覧 (AppleEnabledInputSources) に入れておく。もう入っていれば何もしない。
enable_input_source() {
    local id=jp.co.aibos.inputmethod.TypeMacX
    defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | grep -q "$id" && return 0
    defaults write com.apple.HIToolbox AppleEnabledInputSources -array-add \
        "<dict><key>Bundle ID</key><string>$id</string><key>InputSourceKind</key><string>Keyboard Input Method</string></dict>" \
        "<dict><key>Bundle ID</key><string>$id</string><key>Input Mode</key><string>$id.Japanese</string><key>InputSourceKind</key><string>Input Mode</string></dict>"
    killall TextInputMenuAgent 2>/dev/null || true
    echo "入力ソースに TypeMacX を追加しました"
}
[[ "${1:-}" == "--no-install" ]] && INSTALL=0

case "$(uname -m)" in
    arm64) RID=osx-arm64 ;;
    x86_64) RID=osx-x64 ;;
    *) echo "対応していない CPU です: $(uname -m)" >&2; exit 1 ;;
esac

# 使う swift (コマンドライン ツールの swift が壊れている Mac では、swift.org のツールチェーンを SWIFT=... で指定する)
SWIFT="${SWIFT:-swift}"
# 組み立てる場所。iCloud で同期しているフォルダ (デスクトップなど) では、拡張属性が付け直されて codesign が失敗するので、
# そのときは TYPEMACX_BUILD_DIR に同期していない場所を指定する。
BUILD="${TYPEMACX_BUILD_DIR:-build}"
APP="$BUILD/TypeMacX.app"
rm -rf "$BUILD/native" "$APP"
mkdir -p "$BUILD"

echo "== 1/3 本体 (C#, NativeAOT) をビルド"
# リポジトリの nuget.config は NuGet を使わない設定 (Windows の開発環境用) なので、NativeAOT のコンパイラを取るために nuget.org を指定する。
dotnet publish ../src/Meltype.Mac.Native/Meltype.Mac.Native.csproj -c Release -r "$RID" \
    -p:PublishAot=true -p:NativeLib=Shared -p:StripSymbols=true \
    --source https://api.nuget.org/v3/index.json -o "$BUILD/native"

echo "== 2/3 IME (Swift) をビルド (初回は azooKey の変換エンジンと辞書のダウンロードに時間がかかります)"
"$SWIFT" build -c release

echo "== 3/3 TypeMacX.app を組み立て"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
BIN="$("$SWIFT" build -c release --show-bin-path)"
cp "$BIN/TypeMacXIME" "$APP/Contents/MacOS/TypeMacX"
# azooKey が使う llama.framework などの動的なフレームワークも同梱する。
# 入れていなかったため、1.0.0 は起動できなかった (dyld: Library not loaded: @rpath/llama.framework、#13)。
for framework in "$BIN"/*.framework; do
    [[ -e "$framework" ]] && cp -R "$framework" "$APP/Contents/Frameworks/"
done
# Swift 6.2 以降は、古い macOS 向けの互換ライブラリ (libswiftCompatibilitySpan.dylib など) を @rpath で読む。
# macOS 26 は OS に入っているが、13〜15 では無いので、ツールチェーンから同梱する (#20)。
SWIFT_PATH="$(command -v "$SWIFT" 2>/dev/null || xcrun --find swift)"
TOOLCHAIN_SWIFT_LIBS="$(dirname "$SWIFT_PATH")/../lib"
while read -r lib; do
    name="${lib#@rpath/}"
    [[ "$name" == libswift*.dylib && ! -e "$APP/Contents/Frameworks/$name" ]] || continue
    for dylib in "$TOOLCHAIN_SWIFT_LIBS"/swift-*/macosx/"$name" "$TOOLCHAIN_SWIFT_LIBS"/swift/macosx/"$name"; do
        [[ -e "$dylib" ]] && { cp "$dylib" "$APP/Contents/Frameworks/"; break; }
    done
done < <(otool -L "$BIN/TypeMacXIME" | awk '/@rpath\//{print $1}')
# 実行ファイルの隣 (@loader_path) だけでなく、Contents/Frameworks も探すようにする
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/TypeMacX" 2>/dev/null || true
# @rpath で読み込むライブラリが全部 Contents/Frameworks にあるか確かめる (無ければ配布しない)
missing=0
while read -r lib; do
    name="${lib#@rpath/}"
    if [[ ! -e "$APP/Contents/Frameworks/$name" ]]; then echo "同梱されていないライブラリ: $lib" >&2; missing=1; fi
done < <(otool -L "$APP/Contents/MacOS/TypeMacX" | awk '/@rpath\//{print $1}')
[[ $missing -eq 0 ]] || { echo "TypeMacX.app に必要なライブラリが足りません" >&2; exit 1; }
cp "$BUILD/native/MeltypeNative.dylib" "$APP/Contents/Frameworks/libMeltypeNative.dylib"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/icon.tiff "$APP/Contents/Resources/icon.tiff"
# システム設定の入力ソースの一覧に出す名前
cp -R Resources/ja.lproj Resources/en.lproj "$APP/Contents/Resources/"
# azooKey の辞書などのリソース (Swift Package のリソースバンドル)
for bundle in "$BIN"/*.bundle; do
    [[ -e "$bundle" ]] && cp -R "$bundle" "$APP/Contents/Resources/"
done
# 署名の前に拡張属性 (Finder 情報・iCloud の印など) を消す (残っていると codesign が「detritus not allowed」で失敗する)
chmod -R u+w "$APP"
xattr -cr "$APP"
# 署名: 環境変数 TYPEMACX_MAC_IDENTITY (Developer ID Application の証明書の名前) があれば配布用に署名する
# (Hardened Runtime・タイムスタンプ付き。公証 (notarization) は mac.yml で行う)。無ければ自分の Mac で使うための署名。
if [[ -n "${TYPEMACX_MAC_IDENTITY:-}" ]]; then
    for item in "$APP/Contents/Frameworks/"*; do
        codesign --force --sign "$TYPEMACX_MAC_IDENTITY" --options runtime --timestamp "$item"
    done
    codesign --force --deep --sign "$TYPEMACX_MAC_IDENTITY" --options runtime --timestamp "$APP"
    echo "配布用に署名しました: $TYPEMACX_MAC_IDENTITY"
else
    codesign --force --deep --sign - "$APP"
fi
echo "作成しました: $APP"

if [[ $INSTALL -eq 1 ]]; then
    TARGET="$HOME/Library/Input Methods"
    mkdir -p "$TARGET"
    pkill -x TypeMacX 2>/dev/null || true
    rm -rf "$TARGET/TypeMacX.app"
    cp -R "$APP" "$TARGET/"
    echo "インストールしました: $TARGET/TypeMacX.app"
    enable_input_source
    echo "初めてのときは、いったんログアウトしてログインし直してから、"
    echo "システム設定 → キーボード → 入力ソース →「編集…」→「+」→ 日本語 → TypeMacX を追加してください。"
fi
