// Copyright (C) 2026 AIBOS Inc.

import AppKit
import Sparkle

/// 自動アップデート (Sparkle 2)。フィードの URL・公開鍵・確認の間隔は Info.plist (SUFeedURL など) に書いてある。
///
/// IME は LSBackgroundOnly なので、Sparkle の画面 (「新しいバージョンがあります」など) を出す間だけ
/// 設定ウィンドウと同じように .accessory にして前に出し、終わったら元の (Dock にもメニューにも出ない) IME に戻す。
///
/// インストールと再起動について: Sparkle は「インストールして再起動」で TypeMacX のプロセスを終わらせ、
/// ~/Library/Input Methods/TypeMacX.app を置き換えてから、Autoupdate が新しい TypeMacX.app を開き直す。
/// IME はふつうのアプリと同じく LaunchServices で起動でき、起動すると IMKServer が接続を作り直すので、
/// 入力中のアプリは次のキー入力から新しい版を使う。開き直しに失敗しても、入力ソースが使われたときに
/// macOS が IME を起動し直すので、入力できなくなることはない (tools/release/README.md の「IME の更新と再起動」)。
final class Updater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    /// 起動してすぐは辞書の読み込みなどで忙しいので、自動確認はしばらく待ってから始める。
    private static let startDelay: TimeInterval = 60

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    private var started = false

    private override init() {
        super.init()
    }

    /// 起動から少し待って Sparkle を始める (自動確認のスケジュールはここから動く)。
    func scheduleStart() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.startDelay) { [weak self] in
            self?.startIfNeeded()
        }
    }

    /// 入力メニューの「アップデートを確認…」。
    func checkForUpdates() {
        startIfNeeded()
        bringToFront()
        controller.checkForUpdates(nil)
    }

    private func startIfNeeded() {
        guard !started else { return }
        started = true
        do {
            try controller.updater.start()
        } catch {
            NSLog("TypeMacX: アップデートの確認を始められませんでした: \(error.localizedDescription)")
        }
    }

    /// Sparkle の画面を出せるように、ウィンドウを持てるアプリにして前に出す (SettingsWindowController.show と同じ)。
    private func bringToFront() {
        if NSApp.activationPolicy() == .prohibited {
            NSApp.setActivationPolicy(.accessory)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // ---- SPUStandardUserDriverDelegate ----

    /// 自動確認で見つかったときも画面を出すので、そのときも前に出す。
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if handleShowingUpdate { bringToFront() }
    }

    /// アップデートの画面を閉じたら元の IME に戻す (設定ウィンドウが開いていればそのまま)。
    func standardUserDriverWillFinishUpdateSession() {
        let settingsVisible = SettingsWindowController.shared.window?.isVisible ?? false
        if !settingsVisible { NSApp.setActivationPolicy(.prohibited) }
    }
}
