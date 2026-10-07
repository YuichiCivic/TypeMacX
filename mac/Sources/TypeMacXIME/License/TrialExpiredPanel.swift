// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 AIBOS Inc.

import AppKit
import SwiftUI

/// 「試用期間が終了しました」の小さなパネル (画面の右上)。入力の邪魔をしないように、前に出してもキーを奪わない。
final class TrialExpiredPanel {
    static let shared = TrialExpiredPanel()

    private var panel: NSPanel?

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - panel.frame.width - 16, y: frame.maxY - 16))
        }
        panel.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
                            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "TypeMacX"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: TrialExpiredView(
            buy: { [weak self] in
                NSWorkspace.shared.open(LicenseManager.buyURL)
                self?.close()
            },
            enterKey: { [weak self] in
                self?.close()
                SettingsWindowController.shared.showLicense()
            }))
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        return panel
    }
}

private struct TrialExpiredView: View {
    let buy: () -> Void
    let enterKey: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("試用期間が終了しました", systemImage: "clock.badge.exclamationmark")
                .font(.headline)
            Text("英語と日本語の混ぜ書きの変換を止めています (ふつうの入力はそのままできます)。続けて使うにはライセンスを購入してください。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("ライセンスキーを入力", action: enterKey)
                Button("購入する", action: buy)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
