// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 AIBOS Inc.

import AppKit
import Carbon
import SwiftUI

/// ようこそウィンドウ (はじめて IME が起動したときと、入力メニューの「ようこそ / 使い方…」で開く)。
/// ウィンドウは 1 つだけ作って使い回す。
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    /// 一度見せたら UserDefaults (IME の bundle ID のドメイン) に印を付け、次からは自動では出さない。
    private static let shownKey = "OnboardingShown"

    private init() {
        let host = NSHostingController(rootView: OnboardingView())
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "TypeMacX へようこそ"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 640, height: 500))
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) は使わない") }

    /// はじめての起動なら少し待ってから出す (IME の起動直後は入力欄の処理を先にさせる)。
    static func showIfFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: shownKey) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            UserDefaults.standard.set(true, forKey: shownKey)
            shared.show()
        }
    }

    /// ウィンドウを前に出す。IME は LSBackgroundOnly なので、出している間だけ普通のウィンドウを持てるアプリにする (設定ウィンドウと同じ)。
    func show() {
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
        // ほかのウィンドウ (設定など) が出ていなければ、元の (Dock にもメニューにも出ない) IME に戻す。
        let others = NSApp.windows.contains { $0 !== window && $0.isVisible && !($0 is NSPanel) && $0.styleMask.contains(.titled) }
        if !others { NSApp.setActivationPolicy(.prohibited) }
    }
}

// MARK: - 画面

private enum OnboardingStep: Int, CaseIterable {
    case welcome, inputSource, codeApps, tryIt

    var title: String {
        switch self {
        case .welcome: "ようこそ"
        case .inputSource: "入力ソースを追加"
        case .codeApps: "コードを書くとき"
        case .tryIt: "試してみる"
        }
    }
}

private struct OnboardingView: View {
    @State private var step = OnboardingStep.welcome
    @State private var forward = true

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case .welcome: WelcomePage()
                case .inputSource: InputSourcePage()
                case .codeApps: CodeAppsPage()
                case .tryIt: TryItPage()
                }
            }
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Divider()
            HStack(spacing: 12) {
                if step != .welcome {
                    Button("戻る") { go(-1) }
                        .keyboardShortcut(.leftArrow, modifiers: .command)
                }
                Spacer()
                HStack(spacing: 7) {
                    ForEach(OnboardingStep.allCases, id: \.self) { item in
                        Capsule()
                            .fill(item == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: item == step ? 18 : 7, height: 7)
                            .help(item.title)
                            .onTapGesture { move(to: item) }
                    }
                }
                Spacer()
                if step == .tryIt {
                    Button("はじめる") { OnboardingWindowController.shared.close() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("次へ") { go(1) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)
        }
        .frame(width: 640, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func go(_ delta: Int) {
        guard let next = OnboardingStep(rawValue: step.rawValue + delta) else { return }
        move(to: next)
    }

    private func move(to next: OnboardingStep) {
        guard next != step else { return }
        forward = next.rawValue > step.rawValue
        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) { step = next }
    }
}

// MARK: - 共通の部品

/// 各ページの見出し。
private struct PageHeader: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.accentColor.opacity(0.12)))
            Text(title)
                .font(.system(size: 22, weight: .bold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 34)
        .padding(.horizontal, 48)
    }
}

/// アイコン + 見出し + 説明 の 1 行。
private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// 角の丸いカード。
private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

// MARK: - 1. ようこそ

private struct WelcomePage: View {
    private static let typed = "kyouhagoogledekensaku"
    private static let result = "今日はgoogleで検索"

    @State private var shown = 0
    @State private var converted = false

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 76, height: 76)
                Text("TypeMacX へようこそ")
                    .font(.system(size: 26, weight: .bold))
                Text("日本語と英語を、切り替えずにそのまま打てる日本語入力です。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 30)

            // 打った文字が変換されるまでの見本。
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "keyboard").foregroundStyle(.secondary)
                        (Text(String(Self.typed.prefix(shown)))
                            .foregroundColor(.secondary)
                        + Text(shown < Self.typed.count ? "▏" : "")
                            .foregroundColor(.accentColor))
                            .font(.system(.title3, design: .monospaced))
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.turn.down.right").foregroundStyle(Color.accentColor)
                        Text(Self.result)
                            .font(.system(size: 24, weight: .semibold))
                            .opacity(converted ? 1 : 0)
                            .offset(y: converted ? 0 : 6)
                    }
                    .frame(height: 32)
                }
            }
            .padding(.horizontal, 64)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(symbol: "character.textbox", title: "英語と日本語を自動で見分ける",
                           detail: "ローマ字は日本語に、英単語は英字のまま。英数・かなキーを押し直す必要はありません。")
                FeatureRow(symbol: "wand.and.stars", title: "打ち間違いも直す",
                           detail: "onegaishimsu → お願いします、teh → the のような押し間違いを変換のときに直します。")
            }
            .padding(.horizontal, 72)
            Spacer(minLength: 0)
        }
        .task { await play() }
    }

    /// 1 文字ずつ打って、変換された結果を出す (繰り返す)。
    private func play() async {
        while !Task.isCancelled {
            shown = 0
            converted = false
            try? await Task.sleep(nanoseconds: 500_000_000)
            for count in 1...Self.typed.count {
                try? await Task.sleep(nanoseconds: 70_000_000)
                if Task.isCancelled { return }
                shown = count
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            withAnimation(.easeOut(duration: 0.35)) { converted = true }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }
}

// MARK: - 2. 入力ソースを追加

private struct InputSourcePage: View {
    @State private var added = InputSourceStatus.isEnabled()
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            PageHeader(symbol: "keyboard.badge.ellipsis", title: "入力ソースに TypeMacX を追加",
                       subtitle: "macOS の「システム設定」で TypeMacX を入力ソースに追加します。")

            Card {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, text in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(Color.accentColor))
                            Text(text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 64)

            HStack(spacing: 14) {
                Button {
                    InputSourceStatus.openKeyboardSettings()
                } label: {
                    Label("キーボード設定を開く", systemImage: "arrow.up.forward.app")
                }
                .controlSize(.large)
                if added {
                    Label("TypeMacX は追加済みです", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("まだ追加されていません", systemImage: "circle.dashed")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)

            Text("macOS のしくみ上、入力ソースはアプリから自動では追加できません。お手数ですが上の手順で追加してください。追加すると、メニューバーの入力メニューから TypeMacX を選べます。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 72)
            Spacer(minLength: 0)
        }
        .onReceive(timer) { _ in added = InputSourceStatus.isEnabled() }
    }

    private static let steps = [
        "「システム設定」→「キーボード」を開く",
        "「テキスト入力」の「入力ソース」の「編集…」をクリック",
        "左下の「+」をクリックして「日本語」を選ぶ",
        "一覧から「TypeMacX」を選んで「追加」",
    ]
}

/// 入力ソースに TypeMacX が入っているか (TIS で調べる)。
enum InputSourceStatus {
    static func isEnabled() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
        let filter = [kTISPropertyBundleID as String: bundleIdentifier] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return false }
        return !list.isEmpty
    }

    static func openKeyboardSettings() {
        // macOS 13 以降の「キーボード」設定。開けなければ古い形の URL を試す。
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"), NSWorkspace.shared.open(url) { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?InputSources") { NSWorkspace.shared.open(url) }
    }
}

// MARK: - 3. コードを書くとき

private struct CodeAppsPage: View {
    var body: some View {
        VStack(spacing: 16) {
            PageHeader(symbol: "chevron.left.forwardslash.chevron.right", title: "コードを書くアプリでは",
                       subtitle: "Xcode・VS Code・Cursor・ターミナルなどでは、コードの邪魔をしないように動きます。")

            // コードの見本 (コードの行は英語、コメントは日本語)。
            VStack(alignment: .leading, spacing: 3) {
                codeLine([("let ", .pink), ("total", .primary), (" = price * ", .primary), ("2", .orange)])
                codeLine([("// 合計を計算する", .green)])
                codeLine([("print", .cyan), ("(", .primary), ("\"送料は無料です\"", .red), (")", .primary)])
            }
            .font(.system(size: 13, design: .monospaced))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            .padding(.horizontal, 64)

            VStack(alignment: .leading, spacing: 11) {
                FeatureRow(symbol: "curlybraces", title: "コードの行は英語のまま",
                           detail: "変数名やキーワードを打っても日本語になりません。")
                FeatureRow(symbol: "text.bubble", title: "コメント・文字列は日本語",
                           detail: "// や # の後ろ、\"…\" の中、AI への入力行では、ふだんどおり日本語を判定します。")
                FeatureRow(symbol: "globe", title: "「かな」キーでその行は日本語",
                           detail: "コードの行でも「かな」を押すと Enter まで日本語で入力できます。「英数」で元に戻ります。")
            }
            .padding(.horizontal, 72)

            Button("アプリごとの設定を開く…") { SettingsWindowController.shared.show() }
                .buttonStyle(.link)
                .font(.callout)
            Spacer(minLength: 0)
        }
    }

    private func codeLine(_ parts: [(String, Color)]) -> Text {
        parts.reduce(Text("")) { $0 + Text($1.0).foregroundColor($1.1) }
    }
}

// MARK: - 4. 試してみる

private struct TryItPage: View {
    @State private var text = ""
    @FocusState private var focused: Bool

    private static let examples = ["kyouhagoogledekensaku", "ashitanomeetingha3jikara", "kinouGitHubnipushshita"]

    var body: some View {
        VStack(spacing: 16) {
            PageHeader(symbol: "text.cursor", title: "試してみましょう",
                       subtitle: "メニューバーの入力メニューで TypeMacX を選んでから、下の欄に打ってみてください。")

            TextEditor(text: $text)
                .font(.system(size: 17))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 120)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(focused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.12), lineWidth: focused ? 2 : 1))
                .focused($focused)
                .padding(.horizontal, 64)

            VStack(spacing: 8) {
                Text("たとえば、こう打ってみてください")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(Self.examples, id: \.self) { example in
                        Text(example)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.1)))
                    }
                }
            }

            Text("Space で変換・候補の選択、Enter で確定。うまく変換されないときは「TypeMacX 設定…」の「英単語」「ユーザー辞書」で調整できます。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 72)
            Spacer(minLength: 0)
        }
        .onAppear { focused = true }
    }
}
