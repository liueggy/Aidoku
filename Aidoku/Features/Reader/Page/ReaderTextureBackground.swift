//
//  ReaderTextureBackground.swift
//  Aidoku (iOS)
//
//  阅读器「材质纹理」背景。
//

import UIKit

/// 阅读器可选的材质纹理样式。
///
/// 对应的图片资源存放在 `Assets.xcassets`（`ReaderTexture<Style>`），
/// 每种样式都带有浅色 / 深色两套变体，由 asset catalog 跟随系统外观自动切换。
enum ReaderTextureStyle: String, CaseIterable, Identifiable {
    case paper
    case beige
    case kraft
    case grunge
    case plaster
    case wood
    case fabric

    var id: String { rawValue }

    /// Asset catalog 中的图片名。
    var imageName: String { "ReaderTexture\(rawValue.capitalized)" }

    /// 是否已打包对应素材（缺素材时不显示该项）。
    var isAvailable: Bool { UIImage(named: imageName) != nil }

    var title: String {
        NSLocalizedString("READER_TEXTURE_\(rawValue.uppercased())")
    }

    /// 只列出实际带有素材的样式。
    static var available: [ReaderTextureStyle] {
        allCases.filter(\.isAvailable)
    }
}

/// 纹理背景的取值与应用逻辑。
enum ReaderTextureBackground {
    /// 背景选项：纯色之外新增的纹理模式。
    static let backgroundColorOption = "texture"

    static let styleKey = "Reader.textureStyle"
    static let opacityKey = "Reader.textureOpacity"

    static let defaultStyle: ReaderTextureStyle = .paper
    static let defaultOpacity: Double = 0.4

    /// 用户当前是否选择了纹理背景。
    static var isEnabled: Bool {
        UserDefaults.standard.string(forKey: "Reader.backgroundColor") == backgroundColorOption
    }

    static var style: ReaderTextureStyle {
        UserDefaults.standard.string(forKey: styleKey)
            .flatMap(ReaderTextureStyle.init) ?? defaultStyle
    }

    /// 纹理不透明度，取值 0...1。
    static var opacity: CGFloat {
        let stored = (UserDefaults.standard.object(forKey: opacityKey) as? NSNumber)?.doubleValue
        return CGFloat(min(max(stored ?? defaultOpacity, 0), 1))
    }

    /// 纹理模式下垫在纹理底下的纯色（跟随外观设置）。
    static var fallbackColor: UIColor {
        if AppSettings.appearance.useSystemAppearance.get() {
            return .systemBackground
        }
        return AppSettings.appearance.appearance.get() == 0 ? .white : .black
    }

    // MARK: - 图层管理

    private static let textureViewTag = 0x7E_7E_7E  // "TEXTURE" 标记

    /// 在给定视图的最底层铺上纹理。
    ///
    /// 不处于纹理模式（或素材缺失）时会移除已有纹理层。
    /// - Returns: 是否铺上了纹理。
    @discardableResult
    static func apply(to view: UIView) -> Bool {
        guard isEnabled, let image = UIImage(named: style.imageName, in: .main, compatibleWith: view.traitCollection) else {
            remove(from: view)
            return false
        }

        let imageView: UIImageView
        if let existing = view.subviews.first(where: { $0.tag == textureViewTag }) as? UIImageView {
            imageView = existing
        } else {
            imageView = UIImageView()
            imageView.tag = textureViewTag
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.isUserInteractionEnabled = false
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            imageView.frame = view.bounds
            view.insertSubview(imageView, at: 0)
        }

        imageView.image = image
        imageView.alpha = opacity
        if imageView.frame != view.bounds {
            imageView.frame = view.bounds
        }
        return true
    }

    /// 移除已安装的纹理层。
    static func remove(from view: UIView) {
        view.subviews.first(where: { $0.tag == textureViewTag })?.removeFromSuperview()
    }

    /// 样式 / 不透明度变化后通知阅读器刷新。
    static func broadcastChange(style: Bool) {
        NotificationCenter.default.post(
            name: Notification.Name(style ? styleKey : opacityKey),
            object: nil
        )
    }
}
