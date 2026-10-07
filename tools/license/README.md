# TypeMacX ライセンスキーの発行ツール

直販版 (買い切り + 1 年間のアップデート、Mac 2 台まで) のライセンスキーを作る道具です。
キーは Ed25519 で署名してあり、アプリはネットにつながずに確かめます。
キーの形式と検証のコードは `mac/Sources/TypeMacXIME/License/LicenseKey.swift` にあり、このツールも同じファイルを一緒にコンパイルして使います。

## キーの形式

```
TMX1-<base64url(ペイロードの JSON)>.<base64url(Ed25519 の署名 64 バイト)>
```

ペイロード (署名するのは JSON のバイト列そのもの):

```json
{"edition":"direct","email":"…","licenseId":"…","name":"…","purchasedAt":"2026-10-01T00:00:00Z","seats":2,"updatesUntil":"2027-10-01T00:00:00Z"}
```

- `updatesUntil` は、アプリの Info.plist の `TMXBuildDate` (`mac/build.sh` がビルドした日を書く) と比べます。ビルドした日がこれより後なら、そのバージョンでは使えません (試用期間に戻ります)。
- `edition` が `direct` 以外のキーは受け付けません (Setapp 版は別の仕組みにする予定)。
- `seats` は今は表示だけです。台数を数えるにはサーバーが要るので、`License/LicenseActivation.swift` の `LicenseActivation` に Paddle での有効化を後で実装します。

## 使い方

```sh
# コンパイル (コマンドライン ツールの swift が壊れている Mac では swift.org のツールチェーンを指定する)
SWIFTC=~/Library/Developer/Toolchains/swift-6.3.3-RELEASE.xctoolchain/usr/bin/swiftc ./build.sh

# 鍵の組を作る (最初の 1 回だけ)。秘密鍵は private/typemacx-license.key、公開鍵は public.key
.build/typemacx-license keygen
# → 表示された公開鍵を LicenseKey.swift の embeddedPublicKeyBase64 に書く

# キーを発行する (既定: 購入日は今日、アップデートは 1 年、2 台)
.build/typemacx-license issue --email user@example.com --name "山田 太郎"
.build/typemacx-license issue --email user@example.com --name "山田 太郎" \
    --license-id paddle-txn_123 --purchased 2026-10-01 --update-years 1 --seats 2 --json

# キーを確かめる (アプリと同じ検証)。--build-date でアップデート期間も確かめる
.build/typemacx-license verify TMX1-… --build-date 2026-10-07

# テスト (使い捨ての鍵で発行・検証・改ざん・期限切れなどを確かめる)
SWIFTC=… ./test.sh
```

## 秘密鍵

- `tools/license/private/` は `.gitignore` に入れてあります。**絶対にコミットしないでください。** なくすと、同じ公開鍵で確かめられるキーを二度と作れません (1Password などに控えておく)。
- `keygen` は、秘密鍵がもうあるときは `--force` を付けないと作り直しません。作り直すと今までに発行したキーがすべて使えなくなります。
- 今の鍵は開発用に作ったものです。販売を始める前に本番用の鍵を作り直し、アプリの公開鍵も差し替えてください。
- サーバーではファイルの代わりに環境変数 `TMX_LICENSE_PRIVATE_KEY` (秘密鍵の base64) で渡せます。

## Paddle の webhook (後で)

購入の webhook (`transaction.completed`) を受けるサーバーから、同じ処理でキーを作ってメールで送る予定です。

1. webhook の署名 (`Paddle-Signature`) を確かめる。
2. `issue --email <customer.email> --name <customer.name> --license-id <transaction_id> --json` と同じ内容でキーを作る
   (サーバーで Swift を動かさない場合は、`LicenseKey.issue` と同じ形式 — ソートしたキーの JSON・ISO 8601 の日付・base64url — を Node などで作る。Ed25519 なので `crypto.sign(null, data, key)` で同じ署名になる)。
3. キーと licenseId を保存し、購入者にメールで送る。
4. 台数 (seats) を数えるときは、アプリの `LicenseActivation` からこのサーバーに有効化・解除を送る。
