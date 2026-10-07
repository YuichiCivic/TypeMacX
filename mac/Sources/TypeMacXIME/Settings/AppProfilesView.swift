// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 AIBOS Inc.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - アプリ (アプリ別の種類: コード / 一般 / 無効)

extension AppKind: Identifiable {
    var id: String { rawValue }

    /// 設定画面に出す名前。
    var settingsTitle: String {
        switch self {
        case .code: "コード"
        case .general: "一般"
        case .disabled: "無効"
        }
    }

    var settingsSymbol: String {
        switch self {
        case .code: "chevron.left.forwardslash.chevron.right"
        case .general: "text.alignleft"
        case .disabled: "nosign"
        }
    }

    var settingsDetail: String {
        switch self {
        case .code: "英数が基本。コメント・文字列・AI への入力行の中だけ日本語にします。「かな」キーでその行は Enter まで日本語。"
        case .general: "日本語が基本。英単語は自動で見分けて英字にします。"
        case .disabled: "TypeMacX は何もしません (キーをすべてそのままアプリに渡します)。"
        }
    }

    /// 選ぶ順 (よく使うものから)。
    static let settingsOrder: [AppKind] = [.code, .general, .disabled]
}

/// bundle ID からアプリの名前・アイコンを引く (見つからないアプリは bundle ID から作った名前と汎用のアイコン)。
private struct AppInfo {
    let name: String
    let icon: NSImage
    let installed: Bool

    private static var cache: [String: AppInfo] = [:]

    /// 入っていないことがある既定のアプリの名前。
    private static let knownNames: [String: String] = [
        "com.apple.dt.xcode": "Xcode",
        "com.microsoft.vscode": "Visual Studio Code",
        "com.microsoft.vscodeinsiders": "Visual Studio Code - Insiders",
        "com.vscodium": "VSCodium",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.exafunction.windsurf": "Windsurf",
        "dev.zed.zed": "Zed",
        "dev.zed.zed-preview": "Zed Preview",
        "com.jetbrains.*": "JetBrains の IDE (すべて)",
        "com.google.android.studio": "Android Studio",
        "com.sublimetext.4": "Sublime Text 4",
        "com.sublimetext.3": "Sublime Text 3",
        "com.panic.nova": "Nova",
        "com.apple.terminal": "ターミナル",
        "com.googlecode.iterm2": "iTerm2",
        "com.mitchellh.ghostty": "Ghostty",
        "com.github.wez.wezterm": "WezTerm",
        "dev.warp.warp-stable": "Warp",
        "dev.warp.warp": "Warp",
        "org.alacritty": "Alacritty",
        "io.alacritty": "Alacritty",
        "net.kovidgoyal.kitty": "kitty",
    ]

    static func lookup(_ bundleIdentifier: String) -> AppInfo {
        if let cached = cache[bundleIdentifier] { return cached }
        let info: AppInfo
        if !bundleIdentifier.hasSuffix("*"), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let name = FileManager.default.displayName(atPath: url.path)
            info = AppInfo(name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name,
                           icon: NSWorkspace.shared.icon(forFile: url.path), installed: true)
        } else {
            let name = knownNames[bundleIdentifier.lowercased()]
                ?? (bundleIdentifier.hasSuffix("*") ? "\(bundleIdentifier) で始まるアプリ" : bundleIdentifier.components(separatedBy: ".").last ?? bundleIdentifier)
            info = AppInfo(name: name, icon: NSWorkspace.shared.icon(for: .application), installed: false)
        }
        cache[bundleIdentifier] = info
        return info
    }

    /// メニューに出す小さいアイコン。
    var smallIcon: NSImage {
        let image = icon.copy() as? NSImage ?? icon
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

struct AppProfilesView: View {
    @ObservedObject var model: SettingsModel

    /// ユーザーの設定 (アプリの名前順)。
    private var overrides: [(id: String, kind: AppKind)] {
        model.appProfiles
            .map { (id: $0.key, kind: $0.value) }
            .sorted { AppInfo.lookup($0.id).name.localizedStandardCompare(AppInfo.lookup($1.id).name) == .orderedAscending }
    }

    /// 既定の一覧 (アプリの名前順)。
    private var defaults: [(id: String, kind: AppKind)] {
        AppProfiles.defaults
            .map { (id: $0.key, kind: $0.value) }
            .sorted { AppInfo.lookup($0.id).name.localizedStandardCompare(AppInfo.lookup($1.id).name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if overrides.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 6) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 26, weight: .light))
                                    .foregroundStyle(.tertiary)
                                Text("まだ設定したアプリはありません")
                                    .foregroundStyle(.secondary)
                                Text("下のボタンでアプリを追加すると、アプリごとに入力のしかたを変えられます。")
                                    .font(.callout)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 14)
                            Spacer()
                        }
                    } else {
                        ForEach(overrides, id: \.id) { entry in
                            OverrideRow(bundleIdentifier: entry.id, kind: entry.kind, defaultKind: Self.defaultKind(for: entry.id)) { kind in
                                model.setAppProfile(entry.id, kind: kind)
                            } onRemove: {
                                model.setAppProfile(entry.id, kind: nil)
                            }
                        }
                    }
                    HStack {
                        Button {
                            chooseApplications()
                        } label: {
                            Label("アプリを追加…", systemImage: "plus")
                        }
                        Menu {
                            let apps = runningApplications()
                            if apps.isEmpty {
                                Text("追加できるアプリはありません")
                            }
                            ForEach(apps, id: \.id) { app in
                                Button {
                                    add(app.id)
                                } label: {
                                    Label {
                                        Text(app.name)
                                    } icon: {
                                        Image(nsImage: app.icon)
                                    }
                                }
                            }
                        } label: {
                            Label("起動中のアプリから追加", systemImage: "app.badge")
                        }
                        .fixedSize()
                        Spacer()
                    }
                } header: {
                    Text("アプリごとの設定")
                } footer: {
                    AppNote("ここで決めた種類が既定の一覧より優先されます。変更はすぐ保存され、次のキー入力から効きます。")
                }

                Section {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(defaults.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { Divider().padding(.leading, 34) }
                                DefaultRow(bundleIdentifier: entry.id, kind: entry.kind,
                                           overridden: Self.overriddenKind(for: entry.id, in: model.appProfiles)) { kind in
                                    model.setAppProfile(entry.id, kind: kind)
                                }
                                .padding(.vertical, 5)
                            }
                        }
                    }
                    .frame(height: 210)
                } header: {
                    Text("既定の一覧")
                } footer: {
                    AppNote("コードエディター・IDE・ターミナルは、はじめから「コード」になっています。ここに無いアプリは「一般」です。変えたいときは「変更」から種類を選びます。")
                }
            }
            .formStyle(.grouped)
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
    }

    // ---- 追加 ----

    /// /Applications からアプリを選んで追加する (いくつでも)。
    private func chooseApplications() {
        let panel = NSOpenPanel()
        panel.title = "アプリを追加"
        panel.prompt = "追加"
        panel.message = "TypeMacX の種類を設定するアプリを選んでください。"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier else {
                model.errorMessage = "\(url.lastPathComponent) の bundle ID を読めませんでした。"
                continue
            }
            add(id)
        }
    }

    /// 追加したときの種類: 一般のアプリはコードに、コードのアプリは一般にする (追加するのはたいてい既定を変えたいとき)。
    private func add(_ bundleIdentifier: String) {
        guard Self.overriddenKind(for: bundleIdentifier, in: model.appProfiles) == nil else { return }
        let current = Self.defaultKind(for: bundleIdentifier) ?? .general
        model.setAppProfile(bundleIdentifier, kind: current == .general ? .code : .general)
    }

    /// 起動中の普通のアプリ (まだ設定していないもの、名前順)。
    private func runningApplications() -> [(id: String, name: String, icon: NSImage)] {
        let own = Bundle.main.bundleIdentifier?.lowercased()
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (id: String, name: String, icon: NSImage)? in
                guard let id = app.bundleIdentifier, id.lowercased() != own,
                      Self.overriddenKind(for: id, in: model.appProfiles) == nil,
                      seen.insert(id.lowercased()).inserted else { return nil }
                let icon = (app.icon?.copy() as? NSImage) ?? AppInfo.lookup(id).icon
                icon.size = NSSize(width: 16, height: 16)
                return (id: id, name: app.localizedName ?? AppInfo.lookup(id).name, icon: icon)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // ---- 既定の一覧を引く (AppProfiles と同じ: 完全一致、無ければ「*」の前方一致で長いもの) ----

    static func defaultKind(for bundleIdentifier: String) -> AppKind? {
        let id = bundleIdentifier.lowercased()
        if let exact = AppProfiles.defaults.first(where: { $0.key.lowercased() == id }) { return exact.value }
        return AppProfiles.defaults
            .filter { $0.key.hasSuffix("*") && id.hasPrefix(String($0.key.dropLast()).lowercased()) }
            .max { $0.key.count < $1.key.count }?
            .value
    }

    static func overriddenKind(for bundleIdentifier: String, in table: [String: AppKind]) -> AppKind? {
        table.first { $0.key.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }?.value
    }
}

// MARK: - 行

private struct AppNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// アイコン + 名前 + bundle ID。
private struct AppLabel: View {
    let bundleIdentifier: String
    var dimmed = false

    var body: some View {
        let info = AppInfo.lookup(bundleIdentifier)
        HStack(spacing: 10) {
            Image(nsImage: info.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
                .opacity(info.installed && !dimmed ? 1 : 0.55)
            VStack(alignment: .leading, spacing: 1) {
                Text(info.name)
                    .lineLimit(1)
                    .foregroundStyle(dimmed ? .secondary : .primary)
                Text(bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .help(info.installed ? bundleIdentifier : "\(bundleIdentifier) (このMacには見つかりません)")
    }
}

/// ユーザーの設定の 1 行 (種類を選ぶ・消す)。
private struct OverrideRow: View {
    let bundleIdentifier: String
    let kind: AppKind
    let defaultKind: AppKind?
    let onChange: (AppKind) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AppLabel(bundleIdentifier: bundleIdentifier)
            Spacer(minLength: 8)
            Picker("種類", selection: Binding(get: { kind }, set: { onChange($0) })) {
                ForEach(AppKind.settingsOrder) { kind in
                    Label(kind.settingsTitle, systemImage: kind.settingsSymbol).tag(kind)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .help(kind.settingsDetail)
            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 15))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(defaultKind.map { "設定を消して既定 (\($0.settingsTitle)) に戻す" } ?? "設定を消して既定 (一般) に戻す")
        }
    }
}

/// 既定の一覧の 1 行 (変えるとユーザーの設定に入る)。
private struct DefaultRow: View {
    let bundleIdentifier: String
    let kind: AppKind
    let overridden: AppKind?
    let onOverride: (AppKind) -> Void

    var body: some View {
        HStack(spacing: 10) {
            AppLabel(bundleIdentifier: bundleIdentifier, dimmed: overridden != nil)
            Spacer(minLength: 8)
            if let overridden {
                Text("上の設定で「\(overridden.settingsTitle)」")
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            } else {
                Label(kind.settingsTitle, systemImage: kind.settingsSymbol)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Menu("変更") {
                    ForEach(AppKind.settingsOrder.filter { $0 != kind }) { choice in
                        Button {
                            onOverride(choice)
                        } label: {
                            Label("「\(choice.settingsTitle)」にする", systemImage: choice.settingsSymbol)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.trailing, 4)
    }
}
