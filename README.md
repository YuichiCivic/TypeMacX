# TypeMacX

**日本語と英語を、切り替えずに。** Mac の入力ソースです。

ローマ字のまま英語を混ぜて打つだけで、日本語はかな・漢字に、英単語は英字のままになります。

```
kyouhagoogledekensaku  →  今日はgoogleで検索
```

- 英語/日本語の入力切り替え (英数・かな) をほとんど押さなくてよい
- Xcode・VS Code・ターミナルでは、コードは英語のまま、コメントや文字列の中は日本語
- アプリごとに「コード」「一般」「無効」を設定できる
- 入力した文字はすべて Mac の中だけで処理し、外部に送らない
- 無料 (GNU GPL v3)。新しい版は自動で知らせる

## インストール

1. [Releases](https://github.com/YuichiCivic/TypeMacX/releases/latest) から `TypeMacX-<版>.pkg` をダウンロードして開く
2. システム設定 → キーボード → 入力ソースの「編集…」→ 左下の「+」→ 日本語 → **TypeMacX** →「追加」
3. メニューバーの入力メニュー (または Control + Space) で TypeMacX を選ぶ

動く環境: macOS 13 以降、Apple シリコン (M1 以降) の Mac

## ビルド

[mac/README.md](mac/README.md) を見てください。配布とアップデートの出し方は [tools/release/README.md](tools/release/README.md)。

## ライセンスと謝辞

TypeMacX は [Meltype](https://github.com/yksr-melt/Meltype) (© 2026 雪代 / Yukishiro) をもとにした
フリーソフトウェアで、[GNU General Public License v3.0](LICENSE) のもとで配布します。
Meltype の元の README は [docs/MELTYPE-README.md](docs/MELTYPE-README.md) にあります。

かな漢字変換に azooKey の変換エンジン (MIT)、自動アップデートに Sparkle (MIT)、辞書に JMdict・Wiktionary
(CC BY-SA 4.0)、SCOWL、Unicode CLDR を使っています。詳しくは [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。

不具合・要望は [Issues](https://github.com/YuichiCivic/TypeMacX/issues) へ。

© 2026 AIBOS Inc.
