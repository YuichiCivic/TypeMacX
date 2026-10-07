// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 AIBOS Inc.

import AppKit
import SwiftUI

/// 設定ウィンドウの「ライセンス」のタブ。
struct LicenseView: View {
    static let tabTitle = "ライセンス"

    @ObservedObject var manager: LicenseManager
    @State private var key = ""
    @State private var message: String?
    @State private var confirmingDeactivate = false

    var body: some View {
        Form {
            Section {
                status
                if let old = manager.updatesExpiredLicense {
                    Label("登録してあるライセンス (\(old.email)) のアップデート期間は \(LicenseKey.dayString(old.updatesUntil)) までです。このバージョンはその後に出たため使えません。", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("状態")
            }

            if case .licensed = manager.status {
                Section {
                    HStack {
                        Button("この Mac の登録を解除…") { confirmingDeactivate = true }
                        Spacer()
                    }
                } footer: {
                    note("別の Mac に移すときは、先にこの Mac の登録を解除してください。")
                }
            } else {
                Section {
                    TextField("TMX1-…", text: $key, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("登録") { register() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("購入する…") { NSWorkspace.shared.open(LicenseManager.buyURL) }
                        Spacer()
                    }
                    if let message {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("ライセンスキー")
                } footer: {
                    note("購入すると、ライセンスキーがメールで届きます。1 つのライセンスで Mac 2 台まで使えます。買い切りで、購入から 1 年間に出たバージョンへのアップデートが含まれます。")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { manager.refresh() }
        .confirmationDialog("この Mac の登録を解除しますか?", isPresented: $confirmingDeactivate) {
            Button("登録を解除", role: .destructive) {
                manager.deactivate()
                key = ""
                message = nil
            }
        } message: {
            Text("解除すると、もう一度ライセンスキーを入力するまで英語と日本語の混ぜ書きの変換が使えなくなります (試用期間が残っていれば試用中に戻ります)。")
        }
    }

    @ViewBuilder
    private var status: some View {
        switch manager.status {
        case .licensed(let license):
            row(symbol: "checkmark.seal.fill", color: .green, title: "登録済み",
                detail: "\(license.name) (\(license.email))")
            LabeledContent("アップデート", value: "\(LicenseKey.dayString(license.updatesUntil)) までに出たバージョン")
            LabeledContent("使える台数", value: "Mac \(license.seats) 台まで")
            LabeledContent("ライセンス ID") { Text(license.licenseId).textSelection(.enabled) }
        case .trial(let daysLeft):
            row(symbol: "clock", color: .accentColor, title: "試用中 — あと \(daysLeft) 日",
                detail: "\(LicenseManager.trialDays) 日間、すべての機能を試せます。")
        case .expired:
            row(symbol: "clock.badge.exclamationmark", color: .orange, title: "試用期間が終了しました",
                detail: "英語と日本語の混ぜ書きの変換を止めています (ふつうの入力はそのままできます)。")
        }
    }

    private func row(symbol: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                note(detail)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func register() {
        message = manager.register(key)
        if message == nil { key = "" }
    }
}
