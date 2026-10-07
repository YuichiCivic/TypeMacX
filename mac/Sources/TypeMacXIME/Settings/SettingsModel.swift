// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 AIBOS Inc.

import AppKit
import Foundation

/// 英語か日本語かの自動判定の強さ (src/Meltype.Core/Config/Settings.cs の DetectionLevel と同じ名前)。
enum DetectionLevelSetting: String, CaseIterable, Identifiable {
    case aggressive = "Aggressive"
    case balanced = "Balanced"
    case conservative = "Conservative"
    case manual = "Manual"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aggressive: return "積極的"
        case .balanced: return "標準"
        case .conservative: return "慎重"
        case .manual: return "手動 (提案のみ)"
        }
    }

    var detail: String {
        switch self {
        case .aggressive: return "英語らしければすぐ英字にします。"
        case .balanced: return "短い語 (no, to など) は前後が英語のときだけ英字にします。"
        case .conservative: return "確信度が高いときだけ英字にします。"
        case .manual: return "自動では切り替えず、提案だけ出します (変換中に Tab で英字に)。"
        }
    }
}

/// ユーザー辞書の 1 語 (userdict.txt の 1 行「読み<Tab>単語」)。
struct UserWordEntry: Identifiable, Equatable {
    let id = UUID()
    var reading: String
    var word: String
}

/// config.json (と辞書のファイル) を読み書きする。
/// 本体 (C#) が知っている項目のうち Mac 版で効くものだけを画面に出し、知らない項目・ほかの項目はそのまま残す。
final class SettingsModel: ObservableObject {
    static let shared = SettingsModel()

    // ---- config.json の項目 (名前と既定値は Settings.cs と合わせる) ----
    @Published var enabled = true { didSet { changed("Enabled", enabled) } }
    @Published var liveConversion = true { didSet { changed("LiveConversion", liveConversion) } }
    @Published var autoCorrectAfterCommit = true { didSet { changed("AutoCorrectAfterCommit", autoCorrectAfterCommit) } }
    @Published var spaceAroundEnglish = false { didSet { changed("SpaceAroundEnglish", spaceAroundEnglish) } }
    @Published var translationCandidates = true { didSet { changed("TranslationCandidates", translationCandidates) } }
    @Published var showCandidateMeanings = true { didSet { changed("ShowCandidateMeanings", showCandidateMeanings) } }
    @Published var correctTypos = true { didSet { changed("CorrectTypos", correctTypos) } }
    @Published var detectionLevel = DetectionLevelSetting.balanced { didSet { changed("DetectionLevel", detectionLevel.rawValue) } }
    @Published var fileLog = false { didSet { changed("FileLog", fileLog) } }
    @Published var logTypedText = false { didSet { changed("LogTypedText", logTypedText) } }

    // ---- 辞書 ----
    /// いつも英語として扱う語 (dictionaries/english.txt)。
    @Published var englishWords = ""
    /// いつも日本語 (ローマ字) として扱う語 (dictionaries/japanese.txt)。
    @Published var japaneseWords = ""
    @Published var userWords: [UserWordEntry] = []

    // ---- アプリ別の種類 (config.json の "AppProfiles"。AppProfiles.swift が読む) ----
    /// ユーザーの設定 (bundle ID → 種類)。キーは書いてあるとおりの大文字小文字。
    @Published private(set) var appProfiles: [String: AppKind] = [:]

    /// 最後に読み書きできなかったときの理由 (画面の下に出す)。
    @Published var errorMessage: String?

    /// config.json の中身そのもの (知らない項目も入っている)。
    private var raw: [String: Any] = [:]
    /// 読み込み中は didSet で保存しない。
    private var loading = false

    /// 設定・学習データ・ユーザー辞書の保存場所 (~/Library/Application Support/TypeMacX)。
    let dataDirectory: URL = {
        if let path = NativeCore.shared.dataDirectory { return URL(fileURLWithPath: path, isDirectory: true) }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("TypeMacX", isDirectory: true)
    }()

    var configFile: URL { dataDirectory.appendingPathComponent("config.json") }
    var userDictionaryFile: URL { dataDirectory.appendingPathComponent("userdict.txt") }
    var dictionaryDirectory: URL { dataDirectory.appendingPathComponent("dictionaries", isDirectory: true) }
    var englishFile: URL { dictionaryDirectory.appendingPathComponent("english.txt") }
    var japaneseFile: URL { dictionaryDirectory.appendingPathComponent("japanese.txt") }

    private init() {
        load()
    }

    // ---- config.json ----

    /// ファイルから読み直す (設定画面を開くたびに呼ぶ。手で書き換えた内容も拾う)。
    func load() {
        loading = true
        defer { loading = false }
        errorMessage = nil
        raw = [:]
        if let data = try? Data(contentsOf: configFile), !data.isEmpty {
            do {
                // 本体はコメント・末尾のカンマを許すので、JSON5 として読む。
                if let object = try JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) as? [String: Any] {
                    raw = object
                }
            } catch {
                errorMessage = "config.json を読めませんでした (保存すると上書きされます): \(error.localizedDescription)"
            }
        }
        enabled = bool("Enabled", true)
        liveConversion = bool("LiveConversion", true)
        autoCorrectAfterCommit = bool("AutoCorrectAfterCommit", true)
        spaceAroundEnglish = bool("SpaceAroundEnglish", false)
        translationCandidates = bool("TranslationCandidates", true)
        showCandidateMeanings = bool("ShowCandidateMeanings", true)
        correctTypos = bool("CorrectTypos", true)
        fileLog = bool("FileLog", false)
        logTypedText = bool("LogTypedText", false)
        // 本体は名前でも数値でも読めるので、どちらでも受ける。
        if let name = raw["DetectionLevel"] as? String,
           let level = DetectionLevelSetting.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(name) == .orderedSame }) {
            detectionLevel = level
        } else if let index = raw["DetectionLevel"] as? Int, DetectionLevelSetting.allCases.indices.contains(index) {
            detectionLevel = DetectionLevelSetting.allCases[index]
        } else {
            detectionLevel = .balanced
        }
        englishWords = readText(englishFile)
        japaneseWords = readText(japaneseFile)
        userWords = readUserWords()
        appProfiles = readAppProfiles()
    }

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        (raw[key] as? NSNumber)?.boolValue ?? fallback
    }

    /// 項目が変わったら、すぐ config.json に書いて本体に読み直させる (macOS の設定画面と同じく「適用」ボタンは無し)。
    private func changed(_ key: String, _ value: Any) {
        guard !loading else { return }
        raw[key] = value
        saveConfig()
    }

    private func saveConfig() {
        // 新しく作るときは形式のバージョンも入れる (無いと本体が古い設定とみなして移行する)。
        if raw["SettingsVersion"] == nil { raw["SettingsVersion"] = 5 }
        do {
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: configFile, options: .atomic)
            errorMessage = nil
        } catch {
            errorMessage = "config.json に保存できませんでした: \(error.localizedDescription)"
            return
        }
        NativeCore.shared.reloadSettings()
    }

    /// 既定の設定に戻す (Mac 版の画面に出している項目だけ。プロファイル・アプリ別設定などは残す)。
    func resetToDefaults() {
        loading = true
        enabled = true
        liveConversion = true
        autoCorrectAfterCommit = true
        spaceAroundEnglish = false
        translationCandidates = true
        showCandidateMeanings = true
        correctTypos = true
        detectionLevel = .balanced
        fileLog = false
        logTypedText = false
        loading = false
        for key in ["Enabled", "LiveConversion", "AutoCorrectAfterCommit", "SpaceAroundEnglish", "TranslationCandidates",
                    "ShowCandidateMeanings", "CorrectTypos", "DetectionLevel", "FileLog", "LogTypedText"] {
            raw.removeValue(forKey: key)
        }
        saveConfig()
    }

    // ---- アプリ別の種類 ----

    private func readAppProfiles() -> [String: AppKind] {
        // 手で書いたときのために "appProfiles" も読む (AppProfiles.swift と同じ)。
        guard let table = (raw["AppProfiles"] ?? raw["appProfiles"]) as? [String: Any] else { return [:] }
        var result: [String: AppKind] = [:]
        for (id, value) in table {
            let id = id.trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, let name = value as? String, let kind = AppKind(rawValue: name.lowercased()) else { continue }
            result[id] = kind
        }
        return result
    }

    /// アプリの種類を決める (nil なら設定を消して既定に戻す)。bundle ID の大文字小文字は区別しない。
    func setAppProfile(_ bundleIdentifier: String, kind: AppKind?) {
        let id = bundleIdentifier.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return }
        var table = (raw["AppProfiles"] ?? raw["appProfiles"]) as? [String: Any] ?? [:]
        // 大文字小文字だけ違う同じアプリの行は消してから書く。
        for key in table.keys where key.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(id) == .orderedSame {
            table.removeValue(forKey: key)
        }
        if let kind { table[id] = kind.rawValue }
        raw.removeValue(forKey: "appProfiles")
        raw["AppProfiles"] = table
        saveConfig()
        appProfiles = readAppProfiles()
    }

    // ---- 英単語・日本語の語の一覧 (空白・改行区切り、# 以降はコメント) ----

    func saveEnglishWords() { writeText(englishWords, to: englishFile) }
    func saveJapaneseWords() { writeText(japaneseWords, to: japaneseFile) }

    private func readText(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\u{FEFF}", with: "")
    }

    private func writeText(_ text: String, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
            errorMessage = nil
        } catch {
            errorMessage = "\(url.lastPathComponent) に保存できませんでした: \(error.localizedDescription)"
        }
    }

    // ---- ユーザー辞書 (userdict.txt、1 行に「読み<Tab>単語」、# の行はコメント) ----

    private func readUserWords() -> [UserWordEntry] {
        readText(userDictionaryFile)
            .components(separatedBy: "\n")
            .compactMap { line in
                let line = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
                guard !line.hasPrefix("#") else { return nil }
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 2 else { return nil }
                let reading = parts[0].trimmingCharacters(in: .whitespaces)
                let word = parts[1].trimmingCharacters(in: .whitespaces)
                guard !reading.isEmpty, !word.isEmpty else { return nil }
                return UserWordEntry(reading: reading, word: word)
            }
    }

    /// 本体 (UserDictionary.Save) と同じ形で書く。読みが 2 文字未満・単語が空の行は本体が読まないので入れない。
    func saveUserWords() {
        var lines = ["# Meltype ユーザー辞書: 1 行に「読み<Tab>単語」"]
        for entry in userWords {
            let reading = entry.reading.trimmingCharacters(in: .whitespaces)
            let word = entry.word.trimmingCharacters(in: .whitespaces)
            guard reading.count >= 2, !word.isEmpty, !reading.contains("\t"), !word.contains("\t") else { continue }
            lines.append("\(reading)\t\(word)")
        }
        // 本体と同じく BOM 付きの UTF-8。
        writeText("\u{FEFF}" + lines.joined(separator: "\n") + "\n", to: userDictionaryFile)
    }

    // ---- Finder・エディターで開く ----

    func openDataFolder() {
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dataDirectory)
    }

    /// ファイルを既定のテキストエディターで開く (無ければ空で作ってから)。
    func openInEditor(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        if let editor = NSWorkspace.shared.urlForApplication(toOpen: url) ?? (FileManager.default.fileExists(atPath: textEdit.path) ? textEdit : nil) {
            NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
