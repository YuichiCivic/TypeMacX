# セキュリティについて

TypeMacX はキーボードの入力を扱うソフトです。安心して使ってもらえるように、次の方針で作っています。

## TypeMacX がすること・しないこと

- **打った文字を外部に送りません。** 判定・変換・学習はすべて Mac の中で行います。通信するのは次の 2 つだけです。
  - 自動アップデート: 1 日 1 回、GitHub Releases に新しい版があるかを確かめる (Sparkle。送るのは今の版と macOS の版だけ)。
  - 不具合の報告: 入力メニューの「不具合の報告・提案…」から、利用者が自分で GitHub を開いたときだけ。
- **パスワードの欄では何もしません。** macOS はパスワードの欄で入力ソースを使わせないので、TypeMacX にキーは届きません。
- **ログに打った文字を残しません (既定)。** 設定「ログに入力した文字を残す」を ON にしたときだけ残します。OFF のときは文字数だけです
  (ただし判定の理由には、判定した語の先頭の数文字が残ります)。
- **管理者権限は要りません。** インストール先はユーザーのフォルダー (`%LOCALAPPDATA%\Programs\TypeMacX`) で、ふつうの権限で動きます。
- 保存するのは、設定・学習データ・ユーザー辞書 (`%LOCALAPPDATA%\TypeMacX`) と、ON にしたときのログだけです。

## 脆弱性の報告

悪用できそうな問題 (打った文字が漏れる・ほかのアプリに勝手に入力される・権限が上がる など) を見つけたら、
**公開の Issue ではなく、非公開で報告してください。**

- GitHub: [Security → Report a vulnerability](https://github.com/yksr-melt/TypeMacX/security/advisories/new) (非公開で作者にだけ届きます)
- GitHub の非公開の脆弱性報告 (https://github.com/YuichiCivic/TypeMacX/security/advisories/new)

次のことを書いてもらえると助かります: 起きること、再現の手順、TypeMacX の版と OS、考えられる影響。
受け取ったら 1 週間以内に返事をし、直すまでの見通しをお知らせします。直した版を出すまでは、内容を公開しないでください。
直した版の公開後、希望があれば報告してくれた方のお名前をリリースノートに載せます。

## 対象の版

直すのは最新の版だけです (テスト版の期間は、最新のテスト版)。古い版を使っている場合は、最新の版で起きるかを確かめてください。

## 配布物の確かめ方

- 配布しているのは https://github.com/YuichiCivic/TypeMacX/releases と、AIBOS が直接渡すものだけです。ほかの場所の TypeMacX は使わないでください。
- 自動アップデートは、Sparkle の EdDSA 署名 (Info.plist の SUPublicEDKey) と Apple のコード署名を確かめてからインストールします。
- 配布する TypeMacX は Developer ID で署名し、Apple の公証 (notarization) を通しています。
