// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Yukishiro

import Carbon.HIToolbox
import Cocoa
import InputMethodKit

/// 入力欄 (クライアント) ごとの IME。キーを本体 (libMeltypeNative.dylib) に渡し、
/// 返ってきた結果 (確定する文字・変換中の表示・候補) を入力欄に反映する。
/// Info.plist の InputMethodServerControllerClass に書いた名前で、Input Method Kit が作る。
@objc(TypeMacXInputController)
final class TypeMacXInputController: IMKInputController {
    private var session: UnsafeMutableRawPointer?
    private var candidateList: [String] = []
    private var hasMarkedText = false
    /// 入力しているアプリの種類 (AppProfiles.swift。bundle ID から決める)。
    private var appKind: AppKind = .general

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        session = NativeCore.shared.createSession()
    }

    deinit {
        NativeCore.shared.destroySession(session)
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown, let client = sender as? IMKTextInput else { return false }
        // アプリ別設定で「無効」のアプリでは何もしない (キーをすべてアプリに渡す)。
        updateAppKind(client)
        if appKind == .disabled { return false }
        // ライセンスが無く試用期間も終わっていたら、「無効」のアプリと同じくキーをそのまま渡す (License/LicenseManager.swift)。
        if !LicenseManager.shared.isConversionAllowed {
            if hasMarkedText { apply(NativeCore.shared.commit(session), to: client) }
            LicenseManager.shared.noteBlockedKey()
            return false
        }

        // JIS キーボードの「英数」「かな」キー: 英数 (直接入力) ⇔ 日本語。
        // コードのアプリでは「かな」でコードの行でも日本語にする (改行まで)、「英数」で戻す。
        switch Int(event.keyCode) {
        case kVK_JIS_Eisu:
            apply(NativeCore.shared.commit(session), to: client)
            NativeCore.shared.setDirect(session, true)
            NativeCore.shared.setCodeJapanese(session, false)
            return true
        case kVK_JIS_Kana:
            NativeCore.shared.setDirect(session, false)
            if appKind == .code { NativeCore.shared.setCodeJapanese(session, true) }
            return true
        default:
            break
        }

        guard let vk = KeyMapping.virtualKey(for: event) else { return false }
        let utf16 = Array((event.characters ?? "").utf16)
        let character: Int32 = utf16.count == 1 ? Int32(utf16[0]) : 0
        let flags = event.modifierFlags
        var modifiers: Int32 = 0
        if flags.contains(.shift) { modifiers |= 1 }
        if flags.contains(.control) { modifiers |= 2 }
        if flags.contains(.option) { modifiers |= 4 }
        if flags.contains(.command) { modifiers |= 8 }

        let (before, after) = hasMarkedText ? (nil, nil) : surroundingText(of: client)
        guard let result = NativeCore.shared.handleKey(session, vk: vk, character: character, modifiers: modifiers, before: before, after: after) else {
            return false
        }
        apply(result, to: client)
        return result.consumed
    }

    /// フォーカスが外れた・クリックで別の場所に移ったときなど。未確定の内容をそのまま確定する。
    override func commitComposition(_ sender: Any!) {
        guard let client = (sender as? IMKTextInput) ?? (self.client() as? IMKTextInput) else { return }
        apply(NativeCore.shared.commit(session), to: client)
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        if let client = (sender as? IMKTextInput) ?? (self.client() as? IMKTextInput) { updateAppKind(client) }
    }

    /// 入力欄のアプリ (bundle ID) の種類を調べ直して本体に伝える。設定 (config.json) を変えたときもすぐ効く。
    private func updateAppKind(_ client: IMKTextInput) {
        let kind = AppProfiles.shared.kind(for: client.bundleIdentifier())
        guard kind != appKind else { return }
        // 無効にする前に、変換中の内容を確定しておく。
        if kind == .disabled { apply(NativeCore.shared.commit(session), to: client) }
        appKind = kind
        NativeCore.shared.setAppKind(session, kind)
    }

    override func deactivateServer(_ sender: Any!) {
        commitComposition(sender)
        candidatesWindow?.hide()
        super.deactivateServer(sender)
    }

    // ---- 変換の候補の一覧 ----

    override func candidates(_ sender: Any!) -> [Any]! {
        candidateList
    }

    override func candidateSelected(_ candidateString: NSAttributedString!) {
        guard let client = self.client() as? IMKTextInput,
              let string = candidateString?.string,
              let index = candidateList.firstIndex(of: string) else { return }
        apply(NativeCore.shared.selectCandidate(session, index: index), to: client)
    }

    // ---- メニュー (メニューバーの入力メニュー) ----

    override func menu() -> NSMenu! {
        let menu = NSMenu()
        menu.addItem(withTitle: "TypeMacX 設定…", action: #selector(openSettings(_:)), keyEquivalent: "")
        menu.addItem(withTitle: LicenseManager.shared.menuTitle, action: #selector(openLicense(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "ようこそ / 使い方…", action: #selector(openOnboarding(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "アップデートを確認…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "TypeMacX のデータフォルダを開く (設定・ユーザー辞書)", action: #selector(openDataFolder(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "不具合の報告・提案… (Mac 版はプレビュー版です)", action: #selector(openReport(_:)), keyEquivalent: "")
        return menu
    }

    @objc private func openOnboarding(_ sender: Any?) {
        OnboardingWindowController.shared.show()
    }

    @objc private func openLicense(_ sender: Any?) {
        SettingsWindowController.shared.showLicense()
    }

    @objc private func openSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        Updater.shared.checkForUpdates()
    }

    @objc private func openReport(_ sender: Any?) {
        guard let url = NativeCore.shared.reportUrl else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openDataFolder(_ sender: Any?) {
        guard let directory = NativeCore.shared.dataDirectory else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: directory, isDirectory: true))
    }

    // ---- 結果を入力欄に反映する ----

    private func apply(_ result: SessionResult?, to client: IMKTextInput) {
        guard let result else { return }
        for edit in result.commits {
            var range = NSRange(location: NSNotFound, length: NSNotFound)
            if edit.deleteBefore > 0 {
                // 確定し直し: キャレット (変換中の文字があればその先頭) の前の文字を置き換える。
                let marked = client.markedRange()
                let caret = marked.location != NSNotFound && marked.length > 0 ? marked.location : client.selectedRange().location
                if caret != NSNotFound {
                    let length = min(edit.deleteBefore, caret)
                    range = NSRange(location: caret - length, length: length)
                }
            }
            client.insertText(edit.text, replacementRange: range)
            hasMarkedText = false
        }
        if let view = result.view {
            showComposition(view, client: client)
        } else {
            hideComposition(client: client)
        }
    }

    /// 変換中の文字を入力欄に下線付きで出す (変換中は文節ごと、選んでいる文節は太い下線)。
    private func showComposition(_ view: CompositionView, client: IMKTextInput) {
        let text = NSMutableAttributedString(string: view.text)
        let length = (view.text as NSString).length
        if view.converting && !view.clauses.isEmpty {
            var location = 0
            for (index, clause) in view.clauses.enumerated() {
                let clauseLength = (clause as NSString).length
                let style = index == view.selectedClause ? kTSMHiliteSelectedConvertedText : kTSMHiliteConvertedText
                addMark(style, to: text, range: NSRange(location: location, length: clauseLength))
                location += clauseLength
            }
        } else {
            addMark(kTSMHiliteRawText, to: text, range: NSRange(location: 0, length: length))
        }
        client.setMarkedText(text, selectionRange: NSRange(location: length, length: 0), replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        hasMarkedText = length > 0
        updateCandidates(view)
    }

    private func hideComposition(client: IMKTextInput) {
        if hasMarkedText {
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            hasMarkedText = false
        }
        candidateList = []
        candidatesWindow?.hide()
    }

    private func addMark(_ style: Int, to text: NSMutableAttributedString, range: NSRange) {
        guard range.length > 0, range.location + range.length <= text.length,
              let marks = mark(forStyle: style, at: range) else { return }
        var attributes: [NSAttributedString.Key: Any] = [:]
        for (key, value) in marks {
            if let name = key as? String {
                attributes[NSAttributedString.Key(name)] = value
            } else if let name = key as? NSAttributedString.Key {
                attributes[name] = value
            }
        }
        text.addAttributes(attributes, range: range)
    }

    /// 候補で少し (1.5 秒) 止まったら、その候補の意味を候補ウィンドウの注釈に出す (Windows 版と同じ)。
    private var meaningKey: String?

    private func scheduleMeaning(_ view: CompositionView) {
        let key = view.meaning.map { "\(view.selectedIndex):\($0)" }
        guard key != meaningKey else { return }
        meaningKey = key
        guard let key, let meaning = view.meaning else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.meaningKey == key, let window = candidatesWindow, window.isVisible() else { return }
            window.showAnnotation(NSAttributedString(string: meaning))
        }
    }

    private func updateCandidates(_ view: CompositionView) {
        guard let window = candidatesWindow else { return }
        if view.converting && view.candidates.count > 1 {
            candidateList = view.candidates
            window.update()
            window.show(kIMKLocateCandidatesBelowHint)
            if view.selectedIndex >= 0 && view.selectedIndex < view.candidates.count {
                window.selectCandidate(withIdentifier: window.candidateIdentifier(atLineNumber: view.selectedIndex))
            }
            scheduleMeaning(view)
        } else {
            meaningKey = nil
            candidateList = []
            window.hide()
        }
    }

    /// 入力欄のキャレットの前後の文字列 (それぞれ 20 文字まで)。取れなければ nil。
    private func surroundingText(of client: IMKTextInput) -> (String?, String?) {
        let selection = client.selectedRange()
        guard selection.location != NSNotFound else { return (nil, nil) }
        // コードのアプリでは、コメントの記号 (// # など) が分かるように行頭まで届く長さを読む (本体が変換に使うのは後ろの 20 文字だけ)。
        let start = max(0, selection.location - (appKind == .code ? 300 : 20))
        let before = client.attributedSubstring(from: NSRange(location: start, length: selection.location - start))?.string
        let after = client.attributedSubstring(from: NSRange(location: selection.location + selection.length, length: 20))?.string
        return (before, after)
    }
}
