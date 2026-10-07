// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 AIBOS Inc.
//
// TypeMacX のライセンスキーを作る道具 (build.sh でコンパイルする)。
// キーの形式と検証は mac/Sources/TypeMacXIME/License/LicenseKey.swift を一緒にコンパイルして、アプリと同じコードを使う。
//
//   typemacx-license keygen [--force]                 鍵の組を作る (秘密鍵は private/、公開鍵は public.key)
//   typemacx-license issue --email E --name N [...]   キーを発行する
//   typemacx-license verify KEY [--build-date D]      キーを確かめる (アプリと同じ検証)
//   typemacx-license pubkey                           秘密鍵から公開鍵を表示する

import CryptoKit
import Foundation

let toolDirectory: URL = {
    // 実行ファイルは tools/license/.build/ に置く。環境変数 TMX_LICENSE_DIR で変えられる。
    if let dir = ProcessInfo.processInfo.environment["TMX_LICENSE_DIR"] { return URL(fileURLWithPath: dir, isDirectory: true) }
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    return executable.deletingLastPathComponent().deletingLastPathComponent()
}()
let defaultPrivateKeyFile = toolDirectory.appendingPathComponent("private/typemacx-license.key")
let defaultPublicKeyFile = toolDirectory.appendingPathComponent("public.key")

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(code)
}

/// --name value の形の引数を読む。値の無いフラグ (--force など) は "" にする。
func parseOptions(_ arguments: ArraySlice<String>) -> (options: [String: String], positional: [String]) {
    var options: [String: String] = [:]
    var positional: [String] = []
    var index = arguments.startIndex
    while index < arguments.endIndex {
        let argument = arguments[index]
        if argument.hasPrefix("--") {
            let name = String(argument.dropFirst(2))
            let next = arguments.index(after: index)
            if next < arguments.endIndex, !arguments[next].hasPrefix("--") {
                options[name] = arguments[next]
                index = arguments.index(after: next)
            } else {
                options[name] = ""
                index = next
            }
        } else {
            positional.append(argument)
            index = arguments.index(after: index)
        }
    }
    return (options, positional)
}

func loadPrivateKey(_ path: String?) -> Curve25519.Signing.PrivateKey {
    // Paddle の webhook などサーバーで使うときは、ファイルの代わりに環境変数 TMX_LICENSE_PRIVATE_KEY (base64) で渡せる。
    let text: String
    if let path {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { fail("秘密鍵を読めません: \(path)") }
        text = contents
    } else if let env = ProcessInfo.processInfo.environment["TMX_LICENSE_PRIVATE_KEY"] {
        text = env
    } else {
        guard let contents = try? String(contentsOf: defaultPrivateKeyFile, encoding: .utf8) else {
            fail("秘密鍵がありません: \(defaultPrivateKeyFile.path) (先に keygen を実行してください)")
        }
        text = contents
    }
    guard let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else { fail("秘密鍵の形式が正しくありません") }
    return key
}

func loadPublicKey(_ value: String?) -> Curve25519.Signing.PublicKey? {
    guard let value else { return LicenseKey.embeddedPublicKey }
    let text = (try? String(contentsOfFile: value, encoding: .utf8)) ?? value
    guard let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PublicKey(rawRepresentation: data) else { fail("公開鍵の形式が正しくありません") }
    return key
}

func keygen(_ options: [String: String]) {
    let privateFile = options["private-key"].map { URL(fileURLWithPath: $0) } ?? defaultPrivateKeyFile
    let publicFile = options["public-key"].map { URL(fileURLWithPath: $0) } ?? defaultPublicKeyFile
    if FileManager.default.fileExists(atPath: privateFile.path) && options["force"] == nil {
        fail("秘密鍵がもうあります: \(privateFile.path)\n作り直すと、今までに発行したキーがすべて使えなくなります。本当に作り直すときは --force を付けてください。")
    }
    let key = Curve25519.Signing.PrivateKey()
    let privateBase64 = key.rawRepresentation.base64EncodedString()
    let publicBase64 = key.publicKey.rawRepresentation.base64EncodedString()
    do {
        try FileManager.default.createDirectory(at: privateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (privateBase64 + "\n").write(to: privateFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateFile.path)
        try (publicBase64 + "\n").write(to: publicFile, atomically: true, encoding: .utf8)
    } catch {
        fail("書き込めません: \(error)")
    }
    print("秘密鍵: \(privateFile.path) (git に入れない・なくさない)")
    print("公開鍵: \(publicFile.path)")
    print("LicenseKey.swift の embeddedPublicKeyBase64 をこの値にしてください:")
    print(publicBase64)
}

func issue(_ options: [String: String]) {
    guard let email = options["email"], !email.isEmpty else { fail("--email が要ります") }
    guard let name = options["name"], !name.isEmpty else { fail("--name が要ります") }
    let purchasedAt: Date
    if let text = options["purchased"] {
        guard let date = LicenseKey.parseDay(text) ?? ISO8601DateFormatter().date(from: text) else { fail("--purchased の日付が読めません: \(text)") }
        purchasedAt = date
    } else {
        // 秒より細かい部分は JSON に出ないので落としておく。
        purchasedAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    }
    let updatesUntil: Date
    if let text = options["updates-until"] {
        guard let date = LicenseKey.parseDay(text) else { fail("--updates-until の日付が読めません (yyyy-MM-dd): \(text)") }
        updatesUntil = date
    } else {
        let years = Int(options["update-years"] ?? "1") ?? 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        updatesUntil = calendar.date(byAdding: .year, value: years, to: purchasedAt)!
    }
    let payload = LicensePayload(
        email: email,
        name: name,
        licenseId: options["license-id"] ?? UUID().uuidString.lowercased(),
        purchasedAt: purchasedAt,
        updatesUntil: updatesUntil,
        seats: Int(options["seats"] ?? "2") ?? 2,
        edition: options["edition"] ?? LicenseKey.editionDirect)
    let privateKey = loadPrivateKey(options["private-key"])
    guard let key = try? LicenseKey.issue(payload, privateKey: privateKey) else { fail("署名できませんでした") }
    if options["json"] != nil {
        let output: [String: String] = ["key": key, "licenseId": payload.licenseId, "email": email, "updatesUntil": LicenseKey.dayString(updatesUntil)]
        let data = try! JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    } else {
        print(key)
    }
}

func verify(_ options: [String: String], _ positional: [String]) {
    // キーは引数か標準入力で渡す。
    let key = positional.first ?? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { fail("確かめるキーを渡してください") }
    var buildDate: Date?
    if let text = options["build-date"] {
        guard let date = LicenseKey.parseDay(text) else { fail("--build-date の日付が読めません (yyyy-MM-dd): \(text)") }
        buildDate = date
    }
    do {
        let payload = try LicenseKey.verify(key, publicKey: loadPublicKey(options["public-key"]), buildDate: buildDate)
        let data = try LicenseKey.makeEncoder().encode(payload)
        print("OK " + String(data: data, encoding: .utf8)!)
    } catch let error as LicenseKeyError {
        let code: Int32
        switch error {
        case .malformed: code = 2
        case .badSignature: code = 3
        case .wrongEdition: code = 4
        case .updatesExpired: code = 5
        }
        fail("NG \(error)", code: code)
    } catch {
        fail("NG \(error)")
    }
}

let arguments = CommandLine.arguments.dropFirst()
let command = arguments.first ?? "help"
let (options, positional) = parseOptions(arguments.dropFirst())
switch command {
case "keygen": keygen(options)
case "issue": issue(options)
case "verify": verify(options, positional)
case "pubkey": print(loadPrivateKey(options["private-key"]).publicKey.rawRepresentation.base64EncodedString())
default:
    print("""
    使い方:
      typemacx-license keygen [--force]
      typemacx-license issue --email E --name N [--license-id ID] [--purchased yyyy-MM-dd] [--updates-until yyyy-MM-dd | --update-years 1] [--seats 2] [--private-key FILE] [--json]
      typemacx-license verify KEY [--build-date yyyy-MM-dd] [--public-key FILE|BASE64]
      typemacx-license pubkey [--private-key FILE]
    """)
}
