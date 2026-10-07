// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 AIBOS Inc.

import Foundation

/// Mac の台数 (seats) を数えるための、サーバーでの有効化。
/// TODO: Paddle (またはライセンスサーバー) ができたら実装する。今はキーの署名だけを確かめ、台数は数えない。
///   - activate: 登録のとき、licenseId とこの Mac の ID を送り、seats を超えていたら断る。
///   - deactivate: 登録を解除したとき、この Mac の分を空ける。
///   - オフラインのときは登録を止めない (署名が正しければ使える) ようにする。
protocol LicenseActivation {
    func activate(_ license: LicensePayload, machineId: String, completion: @escaping (Result<Void, Error>) -> Void)
    func deactivate(_ license: LicensePayload, machineId: String, completion: @escaping (Result<Void, Error>) -> Void)
}

/// 今使う「何もしない」有効化 (いつも成功する)。
struct OfflineLicenseActivation: LicenseActivation {
    func activate(_ license: LicensePayload, machineId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }

    func deactivate(_ license: LicensePayload, machineId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }
}
