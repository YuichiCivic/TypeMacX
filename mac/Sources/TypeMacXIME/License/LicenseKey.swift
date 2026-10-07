// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 AIBOS Inc.
//
// ライセンスキーの形式と検証。ネットにつながなくても確かめられるように、Ed25519 の署名付きにしている。
// このファイルは AppKit を使わない (tools/license の発行ツールも同じファイルをコンパイルして使う)。
//
// キーの形式: "TMX1-" + base64url(ペイロードの JSON) + "." + base64url(署名 64 バイト)
// 署名はペイロードの JSON のバイト列そのものに対して付ける (JSON を並べ直さないので、正規化の問題が起きない)。

import CryptoKit
import Foundation

/// ライセンスの中身 (署名する JSON)。
struct LicensePayload: Codable, Equatable {
    var email: String
    var name: String
    var licenseId: String
    var purchasedAt: Date
    /// この日より後にビルドした版は、このライセンスでは使えない (買い切り + 1 年間のアップデート)。
    var updatesUntil: Date
    /// 使える Mac の台数 (数えるにはサーバーが要るので、今は表示だけ。LicenseActivation を参照)。
    var seats: Int
    /// "direct" (直販)。Setapp 版は別の仕組みにするので、このキーは受け付けない。
    var edition: String
}

/// ライセンスキーが使えない理由。
enum LicenseKeyError: Error, Equatable, CustomStringConvertible {
    /// TMX1- で始まっていない・読めない。
    case malformed
    /// 署名が合わない (書き換えられた・別の鍵で作られた)。
    case badSignature
    /// 直販版のキーではない。
    case wrongEdition(String)
    /// 正しいキーだが、このバージョンはアップデートの期間より後にビルドされている。
    case updatesExpired(LicensePayload)

    var description: String {
        switch self {
        case .malformed:
            return "ライセンスキーの形式が正しくありません。TMX1- から最後まで、そのまま貼り付けてください。"
        case .badSignature:
            return "ライセンスキーが正しくありません (途中が欠けているか、書き換えられています)。"
        case .wrongEdition(let edition):
            return "この版では使えないライセンスキーです (\(edition))。"
        case .updatesExpired(let payload):
            return "このライセンスのアップデート期間 (\(LicenseKey.dayString(payload.updatesUntil)) まで) より後に出たバージョンです。期間内のバージョンを使うか、アップデートを購入してください。"
        }
    }
}

enum LicenseKey {
    static let prefix = "TMX1-"
    static let editionDirect = "direct"

    /// 製品に埋め込む公開鍵 (Ed25519 の raw 32 バイトを base64 にしたもの)。tools/license/public.key と同じ。
    /// 秘密鍵は tools/license/private/ (git に入れない)。鍵を作り直したら、ここも書き換える。
    static let embeddedPublicKeyBase64 = "2zDQSpsL5G/mHGg7qsU7Jir7IjHoZsO3AKzpEIH2y+A="

    static var embeddedPublicKey: Curve25519.Signing.PublicKey? {
        Data(base64Encoded: embeddedPublicKeyBase64).flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
    }

    // ---- JSON ----

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // ---- 作る (発行ツール用) ----

    /// ペイロードに署名してキーの文字列にする。
    static func issue(_ payload: LicensePayload, privateKey: Curve25519.Signing.PrivateKey) throws -> String {
        let data = try makeEncoder().encode(payload)
        let signature = try privateKey.signature(for: data)
        return encode(payload: data, signature: signature)
    }

    static func encode(payload: Data, signature: Data) -> String {
        prefix + base64url(payload) + "." + base64url(signature)
    }

    // ---- 読む・確かめる ----

    /// キーの文字列からペイロードと署名を取り出す。貼り付けたときに入った空白・改行は無視する。
    static func decode(_ key: String) -> (payload: Data, signature: Data)? {
        let compact = String(key.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
        guard compact.hasPrefix(prefix) else { return nil }
        let parts = compact.dropFirst(prefix.count).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payload = fromBase64url(String(parts[0])),
              let signature = fromBase64url(String(parts[1])),
              signature.count == 64 else { return nil }
        return (payload, signature)
    }

    /// キーを確かめてペイロードを返す。使えなければ LicenseKeyError を投げる。
    /// - Parameter buildDate: この版をビルドした日。nil ならアップデート期間は確かめない (発行ツールの確認用)。
    static func verify(_ key: String, publicKey: Curve25519.Signing.PublicKey? = embeddedPublicKey, buildDate: Date?) throws -> LicensePayload {
        guard let (data, signature) = decode(key) else { throw LicenseKeyError.malformed }
        guard let publicKey, publicKey.isValidSignature(signature, for: data) else { throw LicenseKeyError.badSignature }
        guard let payload = try? makeDecoder().decode(LicensePayload.self, from: data) else { throw LicenseKeyError.malformed }
        guard payload.edition == editionDirect else { throw LicenseKeyError.wrongEdition(payload.edition) }
        if let buildDate, buildDate > payload.updatesUntil { throw LicenseKeyError.updatesExpired(payload) }
        return payload
    }

    // ---- ビルドした日 ----

    /// Info.plist の TMXBuildDate (build.sh が書く。"yyyy-MM-dd"、UTC)。無ければ fallbackBuildDate。
    static func buildDate(info: [String: Any]?) -> Date? {
        if let text = info?["TMXBuildDate"] as? String, let date = parseDay(text) { return date }
        return parseDay(fallbackBuildDate)
    }

    /// build.sh を通さずにビルドしたとき (swift build だけ) に使う日付。リリースのたびに直さなくてよい (build.sh が書くので)。
    static let fallbackBuildDate = "2026-10-07"

    static func parseDay(_ text: String) -> Date? {
        dayFormatter.date(from: text.trimmingCharacters(in: .whitespaces))
    }

    static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // ---- base64url (パディングなし) ----

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func fromBase64url(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard !base64.contains("=") else { return nil }
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
