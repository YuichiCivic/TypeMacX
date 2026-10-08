# TypeMacX を配る・アップデートする

TypeMacX は無料 (GNU GPL v3) で配ります。インストーラーとアップデートは GitHub Releases に置き、
入れている人の TypeMacX は Sparkle で 1 日 1 回新しい版を確かめて知らせます。

## いつもの手順 (新しい版を出す)

```sh
# 1. (任意) リリースノートを書いてコミットする。無ければ前の版からのコミットの一覧になる
$EDITOR tools/release/notes/0.2.0.md && git add -A && git commit -m "Notes for 0.2.0"

# 2. 出す (版上げ → ビルド → 署名 → 公証 → GitHub Releases まで全部)
tools/release/publish.sh 0.2.0
```

- 入れている人: TypeMacX が「新しい版があります」と知らせ、「インストールして再起動」で更新される
  (/Library/Input Methods に入っているので、更新のときに Mac のパスワードを聞かれる)。
  メニューの「アップデートを確認…」で、すぐ確かめることもできる。
- はじめての人: Releases の `TypeMacX-<版>.pkg` を渡す (または作業場所の `TypeMacX-<版>-手渡し用.zip`。
  pkg・ソース・説明書・ライセンスが入っている)。
- 途中で失敗したら、版上げのコミットとタグは自動で取り消される。直してから同じコマンドをもう一度。

## 最初に一度だけ: 準備

### 1. 証明書 (Apple Developer Program)

developer.apple.com → Certificates で次の 2 つを作り、ダブルクリックしてキーチェーンに入れる
(CSR はキーチェーンアクセス → 証明書アシスタント → 認証局に証明書を要求 で作る)。

- **Developer ID Application** (アプリの署名)
- **Developer ID Installer** (pkg の署名)

名前を確かめて、シェルの設定 (~/.zshrc) に書いておく:

```sh
security find-identity -v                        # 名前を確かめる
export TYPEMACX_MAC_IDENTITY="Developer ID Application: AIBOS Inc. (XXXXXXXXXX)"
export TYPEMACX_INSTALLER_IDENTITY="Developer ID Installer: AIBOS Inc. (XXXXXXXXXX)"
```

### 2. 公証 (notarization) の準備

appleid.apple.com → サインインとセキュリティ → App 用パスワード を作ってから:

```sh
xcrun notarytool store-credentials typemacx-notary \
    --apple-id "<Apple ID>" --team-id "XXXXXXXXXX" --password "<App 用パスワード>"
```

### 3. GitHub のリポジトリ

このリポジトリを GitHub の公開リポジトリに push しておく (`gh repo create ... --public --source . --push`)。
GPL なのでソースは公開する。アップデートの配信先 (appcast.xml) も、このリポジトリの Releases になる:
`https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml`

### 4. 鍵のバックアップ (大事)

Sparkle の EdDSA 秘密鍵 (キーチェーン、アカウント `typemacx`) は、アップデートの署名に使う。
**無くすと、もう配った TypeMacX にアップデートを届けられなくなる。** 書き出して安全な所 (1Password など) に置く:

```sh
mac/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account typemacx -x ~/typemacx-sparkle-key.txt
```

公開鍵は `mac/Resources/Info.plist` の `SUPublicEDKey`。別の Mac で出すときは `generate_keys --account typemacx -f <ファイル>` で取り込む。

## 中で何をしているか

| スクリプト | すること |
|---|---|
| `publish.sh <版>` | Info.plist の版を上げてコミット・タグ → `build-release.sh` → push → `gh release create` |
| `build-release.sh` | ビルド (無料版) → .app を公証・staple → アップデート用 zip と appcast.xml (Sparkle で署名) → pkg を作って署名・公証 → ソース zip・手渡し用 zip |
| `build-release.sh --unsigned` | 証明書が無くても一式を作る (手元の確認用。**配らない**) |
| `pkg-scripts/` | pkg のインストール前後の処理 (古い TypeMacX を止める / 入力ソースに登録する) |
| `pkg-resources/` | インストーラーの画面、渡す人向けの説明書 |

- 作業場所: `~/Library/Caches/TypeMacX/release/dist` (デスクトップは iCloud で同期していて codesign が失敗するため)
- 対応: macOS 13 以降、Apple シリコン (arm64) のみ
- Sparkle は CFBundleVersion で新しさを比べる。`publish.sh` が毎回 1 つ上げる
