import CoreImage
import UIKit

/// Display-only: deliberately NOT part of Nuke's shared requests or disk cache.
struct PaperMaterialProcessor {
    static let scopeKey = "Reader.textureScope"
    static let strengthKey = "Reader.texturePageStrength"
    static let preserveColorKey = "Reader.texturePreserveColor"
    static let maximumPixels = 8_000_000
    static let maximumDimension = 32_768

    let style: ReaderTextureStyle
    let strength: Double
    let preserveColor: Bool

    var identifier: String {
        "paper-material-v1/light/tile512/scope=pages/\(style.rawValue)/\(strength)/color=\(preserveColor)"
    }

    static var current: Self? {
        guard ReaderTextureBackground.isEnabled,
              UserDefaults.standard.string(forKey: scopeKey) == "pages" else { return nil }
        let value = (UserDefaults.standard.object(forKey: strengthKey) as? NSNumber)?.doubleValue ?? 0.35
        let strength = value.isFinite ? min(max(value, 0), 1) : 0.35
        guard strength > 0 else { return nil }
        return Self(
            style: ReaderTextureBackground.style,
            strength: strength,
            preserveColor: UserDefaults.standard.object(forKey: preserveColorKey) as? Bool ?? true
        )
    }

    static func supports(_ image: UIImage) -> Bool {
        guard image.images == nil, let cg = image.cgImage else { return false }
        return cg.width <= maximumDimension && cg.height <= maximumDimension &&
            cg.width <= maximumPixels / max(cg.height, 1)
    }

    // A serial display queue bounds concurrent CPU/GPU work across preloaded pages.
    static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "app.aidoku.paper-material"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private static let context = CIContext(options: [.cacheIntermediates: false])

    func process(_ image: UIImage, texture: UIImage) -> UIImage? {
        guard strength.isFinite, strength > 0, Self.supports(image),
              let sourceCG = image.cgImage, let textureCG = texture.cgImage else { return nil }
        let source = CIImage(cgImage: sourceCG)
        let extent = source.extent
        // Fixed source-pixel pitch, never stretch a square texture over a tall webtoon.
        let tile = CIImage(cgImage: textureCG).transformed(by: CGAffineTransform(
            scaleX: 512 / CGFloat(textureCG.width), y: 512 / CGFloat(textureCG.height)
        )).applyingFilter("CIAffineTile").cropped(to: extent)
        let amount = CGFloat(min(max(strength, 0), 1))
        let white = CIImage(color: .white).cropped(to: extent)
        let paper = tile.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: white, kCIInputTimeKey: 1 - amount
        ]).cropped(to: extent)
        let multiplied = paper.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: source])
        let result: CIImage
        if preserveColor {
            // Only near-white neutral pixels receive paper. Saturated colors and ink stay intact.
            let minimum = source.applyingFilter("CIMinimumComponent")
            let maximum = source.applyingFilter("CIMaximumComponent")
            let chroma = maximum.applyingFilter("CISubtractBlendMode", parameters: [kCIInputBackgroundImageKey: minimum])
            let neutral = chroma.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: -5, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: -5, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: -5, w: 0),
                "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)
            ]).applyingFilter("CIColorClamp")
            let bright = minimum.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 4, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 4, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 4, w: 0),
                "inputBiasVector": CIVector(x: -3, y: -3, z: -3, w: 0)
            ]).applyingFilter("CIColorClamp")
            let mask = bright.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: neutral])
            result = multiplied.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: source, kCIInputMaskImageKey: mask
            ])
        } else {
            result = multiplied
        }
        guard let cg = Self.context.createCGImage(result, from: extent) else { return nil }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }
}
