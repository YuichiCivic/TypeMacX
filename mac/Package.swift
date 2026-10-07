// swift-tools-version:5.10
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Yukishiro
//
// TypeMacX の Mac 版 (Input Method Kit の IME)。ビルドとインストールは build.sh で行う。
// 漢字変換には azooKey の変換エンジン (AzooKeyKanaKanjiConverter, MIT License) を使う。
// 英語 / 日本語の判定などの本体は、C# の Meltype.Core を NativeAOT で libMeltypeNative.dylib にしたものを dlopen で読み込む。

import PackageDescription

let package = Package(
    name: "TypeMacXIME",
    platforms: [.macOS(.v13)],
    dependencies: [
        // main は API がよく変わるので、確かめたコミットに固定する (更新するときは Converter.swift も合わせて直す)。
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", revision: "d59a28e4c7ca049aef04f29a91eae9677a7753f2"),
        // 自動アップデート (Sparkle 2)。バイナリの XCFramework なので、build.sh が Sparkle.framework を Contents/Frameworks に同梱する。
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "TypeMacXIME",
            dependencies: [
                .product(name: "KanaKanjiConverterModuleWithDefaultDictionary", package: "AzooKeyKanaKanjiConverter"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/TypeMacXIME",
            linkerSettings: [
                .linkedFramework("InputMethodKit"),
                .linkedFramework("Carbon"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
