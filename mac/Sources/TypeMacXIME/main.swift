// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Yukishiro

import Cocoa
import InputMethodKit
import Carbon

// インストーラー (pkg の postinstall) から --register 付きで呼ばれたら、入力ソースとして登録だけして終わる。
// 登録しておくと、ログインし直さなくても「入力ソース」の「+」の一覧に出る。
if CommandLine.arguments.contains("--register") {
    let status = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
    if let sources = TISCreateInputSourceList([kTISPropertyBundleID as String: Bundle.main.bundleIdentifier ?? ""] as CFDictionary, true)?.takeRetainedValue() as? [TISInputSource] {
        sources.forEach { TISEnableInputSource($0) }
    }
    exit(status == noErr ? 0 : 1)
}

// Input Method Kit のサーバーを起動する。入力欄 (クライアント) ごとに TypeMacXInputController が作られる。
let connectionName = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String ?? "TypeMacX_Connection"
guard let bundleIdentifier = Bundle.main.bundleIdentifier,
      let server = IMKServer(name: connectionName, bundleIdentifier: bundleIdentifier) else {
    NSLog("TypeMacX: IMKServer を起動できませんでした (TypeMacX.app から起動してください)")
    exit(1)
}

/// 変換の候補の一覧 (すべての入力欄で共有する)。
var candidatesWindow: IMKCandidates? = IMKCandidates(server: server, panelType: kIMKSingleColumnScrollingCandidatePanel)

// 本体 (libMeltypeNative.dylib) を読み込み、漢字変換・英単語の判定の関数を登録しておく。
NativeCore.shared.initialize()

// 自動アップデート (Sparkle) の確認を、起動から少し待って始める (Update/Updater.swift)。
if Edition.updatesEnabled {
    Updater.shared.scheduleStart()
}

// はじめての起動なら、ようこそウィンドウを出す (Onboarding/OnboardingWindow.swift)。
OnboardingWindowController.showIfFirstLaunch()

NSApplication.shared.run()
