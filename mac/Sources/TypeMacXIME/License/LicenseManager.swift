// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 AIBOS Inc.

import AppKit
import Foundation
import IOKit

/// ライセンスの状態。
enum LicenseStatus: Equatable {
    /// 登録済み。
    case licensed(LicensePayload)
    /// 試用中 (あと何日)。
    case trial(daysLeft: Int)
    /// 試用期間が終わり、ライセンスも無い。
    case expired
}

/// ライセンスと試用期間をまとめて扱う。メインスレッドだけで使う。
/// InputController.handle() はキーのたびに isConversionAllowed を見るので、そこではキーチェーンもファイルも読まない
/// (状態は起動時と登録・解除のときに計算して覚えておく)。
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    /// 購入ページ (仮)。
    static let buyURL = URL(string: "https://typemacx.com/buy")!
    static let trialDays = 14

    private static let licenseKeyDefaultsKey = "TMXLicenseKey"
    private static let lastNoticeDefaultsKey = "TMXTrialExpiredNoticeShownAt"

    @Published private(set) var status: LicenseStatus = .expired
    /// 登録したキーが、この版のアップデート期間より前に切れていたとき (試用期間に戻っている)。
    @Published private(set) var updatesExpiredLicense: LicensePayload?

    /// Paddle での台数の管理 (今は何もしない。LicenseActivation.swift)。
    var activation: LicenseActivation = OfflineLicenseActivation()

    /// この版をビルドした日 (Info.plist の TMXBuildDate)。
    let buildDate = LicenseKey.buildDate(info: Bundle.main.infoDictionary)

    // ---- handle() で毎回見る値 (軽くしておく) ----
    private var licensed = false
    private var trialEnd: CFAbsoluteTime = 0
    /// 次に「試用期間が終了しました」を出してよい時刻 (1 日 1 回まで)。
    private var nextNotice: CFAbsoluteTime = 0

    private let trialStart: Date

    private init() {
        trialStart = TrialStore.firstRunDate()
        refresh()
    }

    /// 英語・日本語の混ぜ書きの変換を使ってよいか (ライセンスがあるか、試用期間中)。
    var isConversionAllowed: Bool {
        if Edition.isFree { return true }
        return licensed || CFAbsoluteTimeGetCurrent() < trialEnd
    }

    /// 保存してあるキーを確かめ直して、状態を計算し直す。
    func refresh() {
        let end = trialStart.addingTimeInterval(TimeInterval(Self.trialDays * 24 * 60 * 60))
        trialEnd = end.timeIntervalSinceReferenceDate
        updatesExpiredLicense = nil
        licensed = false
        if let key = UserDefaults.standard.string(forKey: Self.licenseKeyDefaultsKey) {
            do {
                let payload = try LicenseKey.verify(key, buildDate: buildDate)
                licensed = true
                status = .licensed(payload)
                return
            } catch LicenseKeyError.updatesExpired(let payload) {
                updatesExpiredLicense = payload
            } catch {
                NSLog("TypeMacX: 保存してあるライセンスキーが使えません: \(error)")
            }
        }
        let left = end.timeIntervalSinceNow
        status = left > 0 ? .trial(daysLeft: Int((left / 86_400).rounded(.up))) : .expired
    }

    /// キーを登録する。使えなければ理由を返す。
    func register(_ key: String) -> String? {
        let payload: LicensePayload
        do {
            payload = try LicenseKey.verify(key, buildDate: buildDate)
        } catch let error as LicenseKeyError {
            return error.description
        } catch {
            return "\(error)"
        }
        let compact = String(key.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
        UserDefaults.standard.set(compact, forKey: Self.licenseKeyDefaultsKey)
        activation.activate(payload, machineId: Self.machineId) { result in
            if case .failure(let error) = result { NSLog("TypeMacX: ライセンスの有効化に失敗しました: \(error)") }
        }
        refresh()
        return nil
    }

    /// この Mac の登録を解除する (試用期間が残っていれば試用中に戻る)。
    func deactivate() {
        if case .licensed(let payload) = status {
            activation.deactivate(payload, machineId: Self.machineId) { result in
                if case .failure(let error) = result { NSLog("TypeMacX: ライセンスの解除に失敗しました: \(error)") }
            }
        }
        UserDefaults.standard.removeObject(forKey: Self.licenseKeyDefaultsKey)
        refresh()
    }

    /// 変換を止めているときにキーが押された。1 日 1 回まで「試用期間が終了しました」の小さなパネルを出す。
    func noteBlockedKey() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now >= nextNotice else { return }
        let calendar = Calendar.current
        let today = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today)) ?? today.addingTimeInterval(86_400)
        nextNotice = tomorrow.timeIntervalSinceReferenceDate
        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: Self.lastNoticeDefaultsKey) as? Date, calendar.isDate(last, inSameDayAs: today) { return }
        defaults.set(today, forKey: Self.lastNoticeDefaultsKey)
        if case .trial = status { refresh() }
        // キーの処理を終えてから出す。
        DispatchQueue.main.async { TrialExpiredPanel.shared.show() }
    }

    /// 入力メニューに出す項目の名前。
    var menuTitle: String {
        if licensed { return "ライセンス…" }
        let left = trialEnd - CFAbsoluteTimeGetCurrent()
        if left > 0 { return "試用期間：あと \(Int((left / 86_400).rounded(.up))) 日 (ライセンス…)" }
        return "試用期間が終了しました (ライセンス…)"
    }

    /// この Mac の ID (台数を数えるとき用)。
    static var machineId: String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        let uuid = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
        return uuid ?? "unknown"
    }
}

extension SettingsWindowController {
    /// 設定ウィンドウを「ライセンス」のタブで開く。
    func showLicense() {
        show()
        guard let tabs = window?.contentViewController as? NSTabViewController,
              let index = tabs.tabViewItems.firstIndex(where: { $0.label == LicenseView.tabTitle }) else { return }
        tabs.selectedTabViewItemIndex = index
    }
}
