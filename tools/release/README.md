# TypeMacX (Mac 版) のリリースと自動アップデート

TypeMacX は App Store を通さずに直接配布するので、自動アップデートには [Sparkle 2](https://sparkle-project.org/) を使います。
アプリ側のしくみは `mac/Sources/TypeMacXIME/Update/Updater.swift`、設定は `mac/Resources/Info.plist` の `SU…` のキーです。

| キー | 値 |
| --- | --- |
| `SUFeedURL` | `https://typemacx.com/appcast.xml` (仮。サーバーが決まったら直す) |
| `SUPublicEDKey` | `vwNYuy+tC0nhC8UWKFEhbza39smD2PnaTm5u5fN29P8=` |
| `SUEnableAutomaticChecks` | `true` |
| `SUScheduledCheckInterval` | `86400` (1 日 1 回) |

Sparkle の版は `mac/Package.swift` で固定しています (今は 2.10.0)。上げるときは、下のツールも同じ版のものを使ってください (`release.sh` は Package.swift の版を読みます)。

## 署名の鍵 (EdDSA)

- 公開鍵は Info.plist の `SUPublicEDKey` に入っています。
- **秘密鍵はリポジトリには入っていません。** 作った人の Mac のログイン キーチェーンに、アカウント名 `typemacx` で入っています
  (Sparkle の `generate_keys --account typemacx` で作成。キーチェーン アクセスでは「https://sparkle-project.org」の項目)。
- 秘密鍵を無くすと、今まで配った TypeMacX には二度とアップデートを届けられません。必ずバックアップしてください:

```sh
# 書き出す (このファイルは安全な場所に保管し、リポジトリには入れない)
generate_keys --account typemacx -x typemacx-sparkle-private.key
# 別の Mac に入れる
generate_keys --account typemacx -f typemacx-sparkle-private.key
# 公開鍵を確かめる
generate_keys --account typemacx -p
```

`generate_keys` などのツールは、`mac` で一度ビルドすると `mac/.build/artifacts/sparkle/Sparkle/bin/` にあります
(無ければ [Sparkle のリリース](https://github.com/sparkle-project/Sparkle/releases) の `Sparkle-2.10.0.tar.xz` の `bin/`)。

## 公証の準備 (最初の 1 回だけ)

Xcode (notarytool / stapler) と、Apple Developer Program のアカウントが必要です。
App 用パスワード (appleid.apple.com で作る) をキーチェーンに保存しておきます:

```sh
xcrun notarytool store-credentials typemacx-notary \
    --apple-id "<Apple ID>" --team-id "<チーム ID>" --password "<App 用パスワード>"
```

## リリースの手順

1. `mac/Resources/Info.plist` の `CFBundleShortVersionString` (表示する版) と `CFBundleVersion` (ビルド番号) を上げる。
   **Sparkle は `CFBundleVersion` で新旧を比べる**ので、毎回必ず増やすこと。
2. Developer ID で署名してビルドする (iCloud で同期していない場所に組み立てる):

   ```sh
   cd mac
   export TYPEMACX_BUILD_DIR="$HOME/Library/Caches/TypeMacX/build-release"
   TYPEMACX_MAC_IDENTITY="Developer ID Application: AIBOS Inc. (XXXXXXXXXX)" ./build.sh --no-install
   ```

   build.sh は Sparkle.framework の中の `Installer.xpc` → `Downloader.xpc` → `Autoupdate` → `Updater.app` → `Sparkle.framework` → `TypeMacX.app` の順 (内側から) に署名します。
3. 公証・zip・署名・appcast をまとめて行う:

   ```sh
   tools/release/release.sh --notarize "$TYPEMACX_BUILD_DIR/TypeMacX.app"
   ```

   中でしていること (手で行うときも同じ):

   ```sh
   ditto -c -k --keepParent TypeMacX.app TypeMacX-notary.zip
   xcrun notarytool submit TypeMacX-notary.zip --keychain-profile typemacx-notary --wait
   xcrun stapler staple TypeMacX.app
   ditto -c -k --keepParent TypeMacX.app TypeMacX-<版>.zip   # staple した後の .app を zip にする
   sign_update --account typemacx TypeMacX-<版>.zip           # EdDSA 署名 (sparkle:edSignature と length が出る)
   generate_appcast --account typemacx --download-url-prefix https://typemacx.com/downloads/ -o appcast.xml <zip を置いたフォルダ>
   ```

4. できた `TypeMacX-<版>.zip` (と差分の `.delta`) を `https://typemacx.com/downloads/` に、`appcast.xml` を `https://typemacx.com/appcast.xml` に置く。

### release.sh の設定 (環境変数)

| 変数 | 既定 | 内容 |
| --- | --- | --- |
| `TYPEMACX_RELEASE_DIR` | `~/Library/Caches/TypeMacX/release` | zip と appcast.xml を置く場所。前の版の zip も残しておくと、appcast に前の版も載り、差分アップデートも作られる |
| `TYPEMACX_DOWNLOAD_PREFIX` | `https://typemacx.com/downloads/` | zip を置く URL |
| `TYPEMACX_NOTARY_PROFILE` | `typemacx-notary` | notarytool のキーチェーン プロファイル |
| `TYPEMACX_SPARKLE_ACCOUNT` | `typemacx` | EdDSA の秘密鍵のアカウント名 |
| `SPARKLE_BIN` | (自動) | Sparkle のツールの場所 |

リリースノートは、`TYPEMACX_RELEASE_DIR` に zip と同じ名前の `TypeMacX-<版>.html` (または `.md`) を置くと、generate_appcast が appcast に入れます。

## IME の更新と再起動

TypeMacX は `~/Library/Input Methods` に入る LSBackgroundOnly の入力メソッドなので、ふつうのアプリと違う点があります。

- **画面**: IME はふだん Dock にもメニューにも出ない (activation policy が prohibited) ので、Sparkle の画面を出す間だけ
  `.accessory` にして前に出し、終わったら戻します (設定ウィンドウと同じ。Updater.swift)。
  入力メニューの「アップデートを確認…」でも、1 日 1 回の自動確認 (起動から 60 秒後に開始) で見つかったときも、同じように出ます。
- **置き換え**: `~/Library/Input Methods` はユーザーが書き込める場所なので、管理者のパスワードは要りません。
- **再起動**: 「インストールして再起動」を押すと、Sparkle が TypeMacX のプロセスを終わらせ (`NSApp.terminate`)、
  別プロセスの Autoupdate が .app を置き換えて、LaunchServices で新しい TypeMacX.app を開き直します。
  IME は LaunchServices からも起動でき、起動すると IMKServer が同じ接続名で待ち受けるので、ほとんどのアプリはそのまま新しい版で入力できます。
  また、入力メソッドのプロセスが無いときは、入力ソースが使われた時点で macOS が起動し直すので、開き直しに失敗しても入力できなくなることはありません。
- **「終了時にインストール」を選んだとき**: IME はふつう終了しないので、ログアウト・再起動・(下の) pkill のときまで更新されません。
- **うまく切り替わらないとき (回避策)**: 開いていたアプリが古い接続を持ったままで入力できないときは、入力ソースを一度ほかに切り替えて戻すか、
  `pkill -x TypeMacX` で IME を終わらせてください (次に使うときに macOS が新しい版を起動します。`mac/build.sh` のインストールと同じ方法)。

> 注意: 実機での「インストールして再起動」は、本物の appcast と Developer ID 署名済みの版が揃ってから確かめること
> (開発用のアドホック署名でも EdDSA 署名が合えば更新できるが、Developer ID 版から更新するときは、新しい版も同じチームの Developer ID で署名されている必要がある)。
