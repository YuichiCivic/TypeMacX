// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 AIBOS Inc.

import Foundation
import LocalAuthentication
import Security

/// 試用期間 (初めて起動してから 14 日) の始まりの日を覚えておく。
/// データフォルダ (~/Library/Application Support/TypeMacX) を消しても戻らないように、キーチェーン (汎用パスワード) に書く。
/// キーチェーンが使えないときのために UserDefaults にも書き、両方あれば早いほうを使う。
enum TrialStore {
    static let keychainService = "jp.co.aibos.TypeMacX.trial"
    static let keychainAccount = "firstRun"
    static let defaultsKey = "TMXTrialFirstRun"

    /// 試用期間の始まり。まだ無ければ今を書き込んで返す。キーチェーンを読むので、起動後 1 回だけ呼ぶ (LicenseManager が覚えておく)。
    static func firstRunDate(now: Date = Date()) -> Date {
        let keychain = readKeychain()
        let defaults = UserDefaults.standard.object(forKey: defaultsKey) as? Date
        let date = [keychain, defaults].compactMap { $0 }.min() ?? now
        if keychain == nil { writeKeychain(date) }
        if defaults == nil || defaults != date { UserDefaults.standard.set(date, forKey: defaultsKey) }
        return date
    }

    // ---- キーチェーン ----

    private static var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        // IME はキー入力の途中で動くので、キーチェーンの確認ダイアログは出さない (出せなければ UserDefaults だけを使う)。
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        return query
    }

    private static func readKeychain() -> Date? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    private static func writeKeychain(_ date: Date) {
        let data = Data(ISO8601DateFormatter().string(from: date).utf8)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrLabel as String] = "TypeMacX"
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // 読めなかったが既にある (アクセス権が合わないなど)。上書きはしない (試用期間を延ばさないため)。
            return
        }
        if status != errSecSuccess { NSLog("TypeMacX: 試用期間の開始日をキーチェーンに書けませんでした (\(status))") }
    }
}
