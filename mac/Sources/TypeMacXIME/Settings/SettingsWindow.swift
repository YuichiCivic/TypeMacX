// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 AIBOS Inc.

import AppKit
import SwiftUI

/// 設定ウィンドウ (入力メニューの「TypeMacX 設定…」で開く)。ウィンドウは 1 つだけ作って使い回す。
/// 上のツールバーのアイコンで「一般 / 変換 / 英単語 / ユーザー辞書 / このアプリについて」を切り替える (macOS の設定画面と同じ形)。
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        let model = SettingsModel.shared
        tabs.addTabViewItem(Self.tab("一般", symbol: "gearshape", GeneralSettingsView(model: model)))
        tabs.addTabViewItem(Self.tab("変換", symbol: "character.book.closed", ConversionSettingsView(model: model)))
        tabs.addTabViewItem(Self.tab("英単語", symbol: "textformat.abc", EnglishWordsSettingsView(model: model)))
        tabs.addTabViewItem(Self.tab("ユーザー辞書", symbol: "book", UserDictionarySettingsView(model: model)))
        tabs.addTabViewItem(Self.tab("アプリ", symbol: "square.grid.2x2", AppProfilesView(model: model)))
        tabs.addTabViewItem(Self.tab(LicenseView.tabTitle, symbol: "key", LicenseView(manager: LicenseManager.shared)))
        tabs.addTabViewItem(Self.tab("このアプリについて", symbol: "info.circle", AboutSettingsView()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("TypeMacXSettings")
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) は使わない") }

    private static func tab<Content: View>(_ title: String, symbol: String, _ view: Content) -> NSTabViewItem {
        let host = NSHostingController(rootView: view.frame(width: 560).fixedSize(horizontal: false, vertical: true))
        // タブごとに中身の高さに合わせてウィンドウの大きさを変える。
        host.sizingOptions = [.preferredContentSize]
        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    /// 設定ウィンドウを前に出す。IME は LSBackgroundOnly なので、出している間だけ普通のウィンドウを持てるアプリにする。
    func show() {
        SettingsModel.shared.load()
        if NSApp.activationPolicy() == .prohibited {
            NSApp.setActivationPolicy(.accessory)
        }
        guard let window else { return }
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        // 閉じたら元の (Dock にもメニューにも出ない) IME に戻す。
        NSApp.setActivationPolicy(.prohibited)
    }
}

// MARK: - 共通の部品

/// 項目の下に出す説明。
private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// スイッチ + 説明。
private struct SettingToggle: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail { Note(detail) }
            }
        }
        .toggleStyle(.switch)
    }
}

/// 保存できなかったときのメッセージ。
private struct ErrorBanner: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        if let message = model.errorMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
    }
}

// MARK: - 一般

private struct GeneralSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    SettingToggle("TypeMacX を有効にする",
                                  detail: "OFF にすると、キーをすべてそのままアプリに渡します (入力メニューから TypeMacX を外さずに一時停止できます)。",
                                  isOn: $model.enabled)
                    SettingToggle("ライブ変換",
                                  detail: "Space を押さなくても、打ったそばから漢字に変換して表示します。",
                                  isOn: $model.liveConversion)
                    SettingToggle("英単語の前後に半角スペース",
                                  detail: "確定するとき、日本語と英単語の間に半角スペースを入れます (今日はGitHubにpushした → 今日は GitHub に push した)。",
                                  isOn: $model.spaceAroundEnglish)
                } header: {
                    Text("入力")
                }
                Section {
                    SettingToggle("ファイルにログを書く",
                                  detail: "データフォルダの meltype.log に動作の記録を書きます (うまく動かないときの調査用)。",
                                  isOn: $model.fileLog)
                    SettingToggle("ログに入力した文字を残す",
                                  detail: "確定した文字列や読みもログに残します。調べ終わったら OFF にしてください。",
                                  isOn: $model.logTypedText)
                        .disabled(!model.fileLog)
                } header: {
                    Text("診断")
                }
                Section {
                    HStack {
                        Button("データフォルダを開く") { model.openDataFolder() }
                        Button("config.json を編集…") { model.openInEditor(model.configFile) }
                        Spacer()
                        Button("既定に戻す") { model.resetToDefaults() }
                    }
                } footer: {
                    Note("設定は変えるとすぐ保存され、開いている入力欄にもそのまま効きます。")
                }
            }
            .formStyle(.grouped)
            ErrorBanner(model: model)
        }
    }
}

// MARK: - 変換

private struct ConversionSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    SettingToggle("打ち間違いを直す",
                                  detail: "Space・Enter で変換・確定するとき、ローマ字の押し間違い (onegaishimsu → お願いします) や英語のよくある綴り間違い (teh → the) を直します。",
                                  isOn: $model.correctTypos)
                    SettingToggle("確定後も文脈に合わせて直す",
                                  detail: "英語とも日本語とも読める語 (i, sushi など) を確定した後、次の語で英語か日本語かがはっきりしたら確定し直します (i → 胃 の後に want と打つと I want)。",
                                  isOn: $model.autoCorrectAfterCommit)
                        .disabled(model.detectionLevel == .manual)
                } header: {
                    Text("変換")
                }
                Section {
                    SettingToggle("英訳の候補",
                                  detail: "変換候補の後ろに英訳も出します (複雑な → complex, complicated)。",
                                  isOn: $model.translationCandidates)
                    SettingToggle("候補の意味を表示",
                                  detail: "同じ候補で少し止まると、その語の意味を候補の横に出します。同音異義語を選ぶときの手がかりに。",
                                  isOn: $model.showCandidateMeanings)
                } header: {
                    Text("候補")
                }
            }
            .formStyle(.grouped)
            ErrorBanner(model: model)
        }
    }
}

// MARK: - 英単語

private struct EnglishWordsSettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var editing = Kind.english

    enum Kind: String, CaseIterable, Identifiable {
        case english, japanese
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("判定の強さ", selection: $model.detectionLevel) {
                        ForEach(DetectionLevelSetting.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    Note(model.detectionLevel.detail)
                } header: {
                    Text("英語と日本語の自動判定")
                }
                Section {
                    Picker("一覧", selection: $editing) {
                        Text("いつも英語にする語").tag(Kind.english)
                        Text("いつも日本語にする語").tag(Kind.japanese)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    TextEditor(text: editing == .english ? $model.englishWords : $model.japaneseWords)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 160)
                    HStack {
                        Button("保存") {
                            if editing == .english { model.saveEnglishWords() } else { model.saveJapaneseWords() }
                        }
                        .keyboardShortcut("s", modifiers: .command)
                        Button("エディターで開く…") {
                            model.openInEditor(editing == .english ? model.englishFile : model.japaneseFile)
                        }
                        Spacer()
                    }
                } header: {
                    Text("単語の一覧")
                } footer: {
                    Note(editing == .english
                         ? "ローマ字としても読めてしまう英単語 (game, sake など) をここに足すと英字のままにします。空白か改行で区切り、# 以降はコメントです。英小文字だけの語が使えます。"
                         : "英単語と間違えやすいローマ字の語をここに足すと日本語にします。空白か改行で区切り、# 以降はコメントです。英小文字だけの語が使えます。")
                    Note("一覧の変更は、次に入力欄を切り替えたときから効きます。")
                }
            }
            .formStyle(.grouped)
            ErrorBanner(model: model)
        }
    }
}

// MARK: - ユーザー辞書

private struct UserDictionarySettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var selection: UserWordEntry.ID?
    @State private var newReading = ""
    @State private var newWord = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Table(model.userWords, selection: $selection) {
                        TableColumn("読み", value: \.reading)
                        TableColumn("単語", value: \.word)
                    }
                    .frame(height: 200)
                    HStack {
                        TextField("読み (ひらがな・ローマ字)", text: $newReading)
                        TextField("単語", text: $newWord)
                        Button("追加") { add() }
                            .disabled(newReading.trimmingCharacters(in: .whitespaces).isEmpty || newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("削除") { remove() }
                            .disabled(selection == nil)
                    }
                } header: {
                    Text("登録した語 (\(model.userWords.count))")
                } footer: {
                    Note("変換で最優先に使います。読みは 2 文字以上のひらがなで登録します (ローマ字で打つと、ひらがなに直して登録します)。変更は次に入力欄を切り替えたときから効きます。")
                }
                Section {
                    HStack {
                        Button("userdict.txt をエディターで開く…") { model.openInEditor(model.userDictionaryFile) }
                        Button("読み直す") { model.load() }
                        Spacer()
                    }
                } footer: {
                    Note("1 行に「読み<Tab>単語」の形式です。ほかの日本語入力から書き出した一覧を貼り付けることもできます。")
                }
            }
            .formStyle(.grouped)
            ErrorBanner(model: model)
        }
    }

    private func add() {
        var reading = newReading.trimmingCharacters(in: .whitespaces)
        // ローマ字・カタカナで打った読みはひらがなにする。
        if reading.unicodeScalars.contains(where: { $0.isASCII }) {
            reading = reading.lowercased().applyingTransform(.latinToHiragana, reverse: false) ?? reading
        }
        reading = reading.applyingTransform(.hiraganaToKatakana, reverse: true) ?? reading
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard reading.count >= 2, !word.isEmpty else { return }
        model.userWords.append(UserWordEntry(reading: reading, word: word))
        model.saveUserWords()
        newReading = ""
        newWord = ""
    }

    private func remove() {
        guard let selection else { return }
        model.userWords.removeAll { $0.id == selection }
        self.selection = nil
        model.saveUserWords()
    }
}

// MARK: - このアプリについて

private struct AboutSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "バージョン \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("TypeMacX")
                    .font(.title.weight(.semibold))
                Text(version)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("日本語と英語を切り替えずに打てる日本語入力")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)
            Form {
                Section {
                    Credit(name: "Meltype", detail: "雪代 / Yukishiro — GPL-3.0", note: "TypeMacX は Meltype をもとに作られています。")
                    Credit(name: "AzooKeyKanaKanjiConverter", detail: "azooKey — MIT License", note: "かな漢字変換エンジン")
                    Credit(name: "JMdict", detail: "EDRDG — CC BY-SA 4.0", note: "英訳の候補・候補の意味")
                    Credit(name: "SCOWL", detail: "Kevin Atkinson ほか", note: "英単語の一覧")
                    Credit(name: "Unicode CLDR", detail: "Unicode, Inc. — Unicode License", note: "絵文字の読み")
                } header: {
                    Text("謝辞")
                } footer: {
                    Note("TypeMacX は GNU General Public License v3.0 のもとで配布されます。")
                }
            }
            .formStyle(.grouped)
            Text("© 2026 AIBOS Inc.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 14)
        }
    }

    private struct Credit: View {
        let name: String
        let detail: String
        let note: String

        var body: some View {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                    Note(note)
                }
                Spacer()
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
