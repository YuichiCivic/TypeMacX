// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 AIBOS Inc.

import Foundation

/// 入力しているアプリの種類。Windows 版のアプリ別設定の「種類」(src/Meltype.Core/Config/Settings.cs の AppProfile) と同じ考え方。
enum AppKind: String, CaseIterable {
    /// 一般 (文章を書くアプリ)。日本語が基本で、英単語を自動で見分ける。
    case general
    /// コードエディター・ターミナル。英数が基本で、コメント・文字列・AI の入力行 (「> 」の後) の中だけ日本語を判定する。
    /// コードの行でも「かな」キーを押せば、その行 (改行まで) は日本語で入力できる。
    case code
    /// 無効。TypeMacX は何もしない (キーをすべてそのままアプリに渡す)。
    case disabled

    /// 本体 (meltype_set_app_kind) に渡す値。0 = 一般、1 = コード、2 = 無効。
    var nativeValue: Int32 {
        switch self {
        case .general: 0
        case .code: 1
        case .disabled: 2
        }
    }
}

/// アプリ (bundle ID) ごとの種類。
///
/// 既定の一覧 (`defaults`) に、ユーザーの設定 (データフォルダの config.json の `"AppProfiles"`) を重ねる。
/// config.json の形:
///
///     "AppProfiles": {
///       "com.apple.TextEdit": "code",
///       "com.microsoft.VSCode": "general",
///       "com.example.Game": "disabled"
///     }
///
/// 値は "code" | "general" | "disabled" (大文字小文字は問わない。それ以外の値は無視する)。キーは bundle ID (大文字小文字は問わない)。
/// キーの末尾を「*」にすると前方一致 (例: "com.jetbrains.*")。完全一致が前方一致より優先、ユーザーの設定が既定より優先。
/// config.json は書き換えられたら (更新日時が変わったら) 読み直すので、設定画面で保存すればすぐ効く。
final class AppProfiles {
    static let shared = AppProfiles()

    /// 既定で「コード」にするアプリ (コードエディター・IDE・ターミナル)。それ以外は一般。
    static let defaults: [String: AppKind] = [
        // コードエディター・IDE
        "com.apple.dt.Xcode": .code,
        "com.microsoft.VSCode": .code,
        "com.microsoft.VSCodeInsiders": .code,
        "com.vscodium": .code,
        "com.todesktop.230313mzl4w4u92": .code, // Cursor
        "com.exafunction.windsurf": .code,
        "dev.zed.Zed": .code,
        "dev.zed.Zed-Preview": .code,
        "com.jetbrains.*": .code, // IntelliJ IDEA・PyCharm・WebStorm・GoLand・Rider・CLion など
        "com.google.android.studio": .code,
        "com.sublimetext.4": .code,
        "com.sublimetext.3": .code,
        "com.panic.Nova": .code,
        // ターミナル
        "com.apple.Terminal": .code,
        "com.googlecode.iterm2": .code,
        "com.mitchellh.ghostty": .code,
        "com.github.wez.wezterm": .code,
        "dev.warp.Warp-Stable": .code,
        "dev.warp.Warp": .code,
        "org.alacritty": .code,
        "io.alacritty": .code,
        "net.kovidgoyal.kitty": .code,
    ]

    /// config.json のユーザーの設定 (bundle ID は小文字にしたもの)。
    private var overrides: [String: AppKind] = [:]
    private var configDate: Date?
    private var configPath: String?

    /// アプリの種類。bundle ID が分からなければ一般。
    func kind(for bundleIdentifier: String?) -> AppKind {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return .general }
        reloadIfNeeded()
        let id = bundleIdentifier.lowercased()
        return Self.lookup(id, in: overrides) ?? Self.lookup(id, in: Self.lowercasedDefaults) ?? .general
    }

    private static let lowercasedDefaults: [String: AppKind] =
        Dictionary(defaults.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })

    /// 完全一致、無ければ「*」で終わるキーの前方一致 (長いものを優先)。
    private static func lookup(_ id: String, in table: [String: AppKind]) -> AppKind? {
        if let kind = table[id] { return kind }
        return table
            .filter { $0.key.hasSuffix("*") && id.hasPrefix(String($0.key.dropLast())) }
            .max { $0.key.count < $1.key.count }?
            .value
    }

    /// config.json が変わっていたら、ユーザーの設定を読み直す。
    private func reloadIfNeeded() {
        if configPath == nil {
            guard let directory = NativeCore.shared.dataDirectory else { return }
            configPath = (directory as NSString).appendingPathComponent("config.json")
        }
        guard let configPath else { return }
        let date = (try? FileManager.default.attributesOfItem(atPath: configPath))?[.modificationDate] as? Date
        guard date != configDate else { return }
        configDate = date
        overrides = Self.readOverrides(atPath: configPath)
    }

    private static func readOverrides(atPath path: String) -> [String: AppKind] {
        guard let data = FileManager.default.contents(atPath: path),
              let root = (try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed])) as? [String: Any] else { return [:] }
        // C# の Settings と同じ "AppProfiles"。手で書いたときのために "appProfiles" も読む。
        guard let table = (root["AppProfiles"] ?? root["appProfiles"]) as? [String: Any] else { return [:] }
        var result: [String: AppKind] = [:]
        for (id, value) in table {
            guard let name = value as? String, let kind = AppKind(rawValue: name.lowercased()) else { continue }
            result[id.trimmingCharacters(in: .whitespaces).lowercased()] = kind
        }
        return result
    }
}
