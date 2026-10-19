//
//  ReaderTexturePickerView.swift
//  Aidoku (iOS)
//
//  阅读器纹理背景的选择页面：样式 + 不透明度。
//

import SwiftUI

struct ReaderTexturePickerView: View {
    @State private var selectedStyle: ReaderTextureStyle
    @State private var opacity: Double
    @State private var scope = UserDefaults.standard.string(forKey: PaperMaterialProcessor.scopeKey) ?? "background"
    @State private var pageStrength = (UserDefaults.standard.object(forKey: PaperMaterialProcessor.strengthKey) as? NSNumber)?.doubleValue ?? 0.35
    @State private var preserveColor = UserDefaults.standard.object(forKey: PaperMaterialProcessor.preserveColorKey) as? Bool ?? true
    @State private var sample: UIImage?
    @State private var sampleStatus = ""
    @Environment(\.colorScheme) private var colorScheme

    private func image(for style: ReaderTextureStyle) -> UIImage? {
        UIImage(
            named: style.imageName,
            in: .main,
            compatibleWith: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        )
    }

    private static let spacing: CGFloat = 12
    private static let minCardWidth: CGFloat = 130

    init() {
        let available = ReaderTextureStyle.available
        let stored = ReaderTextureBackground.style
        self._selectedStyle = State(
            initialValue: available.contains(stored) ? stored : (available.first ?? .paper)
        )
        self._opacity = State(initialValue: Double(ReaderTextureBackground.opacity))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                preview
                materialControls
                Text(sampleStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("paperMaterial.previewStatus")
                Text(NSLocalizedString("READER_TEXTURE_LIMITS"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                opacitySlider
                styleGrid
                Text(NSLocalizedString("READER_TEXTURE_HELP"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
        }
        .navigationTitle(NSLocalizedString("READER_TEXTURE_PICKER"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { updateSample() }
        .onChange(of: scope) { _ in saveMaterial(scope, key: PaperMaterialProcessor.scopeKey) }
        .onChange(of: pageStrength) { _ in saveMaterial(pageStrength, key: PaperMaterialProcessor.strengthKey) }
        .onChange(of: preserveColor) { _ in saveMaterial(preserveColor, key: PaperMaterialProcessor.preserveColorKey) }
        .onChange(of: selectedStyle) { _ in
            UserDefaults.standard.setValue(selectedStyle.rawValue, forKey: ReaderTextureBackground.styleKey)
            ReaderTextureBackground.broadcastChange(style: true)
            updateSample()
        }
        .onChange(of: opacity) { _ in
            UserDefaults.standard.setValue(opacity, forKey: ReaderTextureBackground.opacityKey)
            ReaderTextureBackground.broadcastChange(style: false)
        }
    }

    // MARK: - 预览

    private var preview: some View {
        ZStack {
            // 纹理背景
            Color(uiColor: ReaderTextureBackground.fallbackColor)
            if let image = image(for: selectedStyle) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(opacity)
            } else {
                Color(uiColor: .secondarySystemBackground)
            }

            if let sample {
                Image(uiImage: sample)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.vertical, 28)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
            }

            VStack {
                Spacer()
                Text(NSLocalizedString("READER_TEXTURE_PREVIEW"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            }
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(uiColor: .secondarySystemFill))
        }
    }

    private var materialControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("READER_TEXTURE_SCOPE")).font(.headline)
            Picker(NSLocalizedString("READER_TEXTURE_SCOPE"), selection: $scope) {
                Text(NSLocalizedString("READER_TEXTURE_BACKGROUND_ONLY")).tag("background")
                Text(NSLocalizedString("READER_TEXTURE_BACKGROUND_PAGES")).tag("pages")
            }
            .pickerStyle(.segmented)
            HStack {
                Text(NSLocalizedString("READER_TEXTURE_PAGE_STRENGTH"))
                Spacer()
                Text("\(Int((pageStrength * 100).rounded()))%").monospacedDigit()
            }
            Slider(value: $pageStrength, in: 0...1)
                .accessibilityLabel(NSLocalizedString("READER_TEXTURE_PAGE_STRENGTH"))
                .disabled(scope != "pages")
            Toggle(NSLocalizedString("READER_TEXTURE_PRESERVE_COLOR"), isOn: $preserveColor)
                .disabled(scope != "pages")
        }
    }

    private func saveMaterial(_ value: Any, key: String) {
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: Notification.Name(key), object: nil)
        updateSample()
    }

    private func updateSample() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 220, height: 320), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 220, height: 320))
            UIColor.black.setStroke()
            context.cgContext.setLineWidth(3)
            context.cgContext.stroke(CGRect(x: 12, y: 12, width: 196, height: 185))
            context.cgContext.strokeEllipse(in: CGRect(x: 32, y: 34, width: 154, height: 76))
            ("Paper / 紙\nHello!" as NSString).draw(in: CGRect(x: 57, y: 48, width: 120, height: 60), withAttributes: [
                .font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.black
            ])
            UIColor.black.setFill()
            context.fill(CGRect(x: 26, y: 136, width: 64, height: 44))
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 113, y: 136, width: 64, height: 44))
            context.cgContext.stroke(CGRect(x: 12, y: 212, width: 196, height: 95))
            ("MANGA\nSample 012345" as NSString).draw(at: CGPoint(x: 30, y: 233), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.black
            ])
        }
        guard scope == "pages" else {
            sample = original
            sampleStatus = NSLocalizedString("READER_TEXTURE_STATUS_BACKGROUND")
            return
        }
        guard pageStrength > 0 else {
            sample = original
            sampleStatus = NSLocalizedString("READER_TEXTURE_STATUS_ZERO")
            return
        }
        guard let texture = PaperMaterialProcessor.lightTexture(for: selectedStyle) else {
            sample = original
            sampleStatus = String(format: NSLocalizedString("READER_TEXTURE_STATUS_ASSET"), selectedStyle.imageName)
            return
        }
        let result = PaperMaterialProcessor(style: selectedStyle, strength: pageStrength, preserveColor: preserveColor)
            .process(original, texture: texture)
        sample = result ?? original
        sampleStatus = result == nil
            ? NSLocalizedString("READER_TEXTURE_STATUS_FAILED")
            : String(format: NSLocalizedString("READER_TEXTURE_STATUS_RENDERED"), selectedStyle.title, Int(pageStrength * 100))
        if !ReaderTextureBackground.isEnabled {
            sampleStatus += " " + NSLocalizedString("READER_TEXTURE_STATUS_INACTIVE")
        }
    }

    // MARK: - 不透明度

    private var opacitySlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(NSLocalizedString("READER_TEXTURE_OPACITY"))
                Spacer()
                Text("\(Int((opacity * 100).rounded()))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $opacity, in: 0...1)
                .accessibilityLabel(NSLocalizedString("READER_TEXTURE_OPACITY"))
                .accessibilityValue("\(Int((opacity * 100).rounded()))%")
        }
    }

    // MARK: - 样式

    private var styleGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("READER_TEXTURE_STYLE"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Self.minCardWidth), spacing: Self.spacing)],
                spacing: Self.spacing
            ) {
                ForEach(ReaderTextureStyle.available) { style in
                    Button {
                        selectedStyle = style
                    } label: {
                        textureCard(style)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(style.title)
                    .accessibilityAddTraits(selectedStyle == style ? [.isSelected] : [])
                }
            }
        }
    }

    private func textureCard(_ style: ReaderTextureStyle) -> some View {
        let selected = selectedStyle == style
        return VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                if let image = image(for: style) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 96)
                        .frame(maxWidth: .infinity)
                        .clipped()
                } else {
                    Color(uiColor: .secondarySystemFill)
                        .frame(height: 96)
                }

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .imageScale(.medium)
                    .foregroundStyle(selected ? Color.accentColor : Color(uiColor: .systemBackground).opacity(0.8))
                    .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? Color.accentColor : Color(uiColor: .secondarySystemFill), lineWidth: selected ? 2 : 1)
            }

            Text(style.title)
                .font(.caption)
                .fontWeight(selected ? .medium : .regular)
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .lineLimit(1)
        }
    }
}

#Preview {
    PlatformNavigationStack {
        ReaderTexturePickerView()
    }
}
