// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 AIBOS Inc.

import Foundation

/// 配る版ごとの違い。build.sh が Info.plist に書く (TYPEMACX_EDITION=free / direct)。
enum Edition {
    /// 無料版: 試用期間・ライセンスの仕組みを使わず、ずっとすべての機能が使える。
    static let isFree = info("TMXFreeEdition") as? Bool ?? false

    /// 自動アップデート (Sparkle) を使うか。配信先 (SUFeedURL) を用意していない配り方では切っておく。
    static let updatesEnabled = info("TMXUpdatesEnabled") as? Bool ?? true

    /// 不具合の報告・提案の受付先。無ければメニューに出さない。
    static let supportURL: URL? = (info("TMXSupportURL") as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }

    /// GPL のソースコードの入手先。無ければ「配布物に同梱」と案内する。
    static let sourceURL: URL? = (info("TMXSourceURL") as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }

    private static func info(_ key: String) -> Any? {
        Bundle.main.object(forInfoDictionaryKey: key)
    }
}
