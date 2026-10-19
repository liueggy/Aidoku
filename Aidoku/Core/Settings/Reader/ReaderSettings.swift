//
//  ReaderSettings.swift
//  Aidoku
//
//  Created by skitty on 8/29/26.
//

struct ReaderSettings: Sendable {
    var keys: [any SettingsDefault] {
        [
            autoScrollPosition,
            upscaleQuality,
            textureStyle,
            textureOpacity,
            textureScope,
            texturePageStrength,
            texturePreserveColor
        ]
    }

    let textureStyle = SettingsKey<String>("Reader.textureStyle", default: "paper")
    let textureOpacity = SettingsKey<Double>("Reader.textureOpacity", default: 0.4)

    let textureScope = SettingsKey<String>("Reader.textureScope", default: "background")
    let texturePageStrength = SettingsKey<Double>("Reader.texturePageStrength", default: 0.35)
    let texturePreserveColor = SettingsKey<Bool>("Reader.texturePreserveColor", default: true)

    // todo: move reader settings here

    let autoScrollPosition = SettingsKey<AutoScrollPosition>("Reader.autoScrollPosition", default: .right)
    let upscaleQuality = SettingsKey<UpscaleQuality>("Reader.upscaleQuality", default: .fast)
}
