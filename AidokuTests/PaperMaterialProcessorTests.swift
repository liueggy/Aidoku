@testable import Aidoku
import Testing
import UIKit

@Suite(.serialized)
struct PaperMaterialProcessorTests {
    private func image(_ color: UIColor, size: CGSize = CGSize(width: 8, height: 8)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func pixel(_ image: UIImage, x: Int = 0, y: Int = 0) throws -> [UInt8] {
        let cg = try #require(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cg, in: CGRect(x: -x, y: -y, width: cg.width, height: cg.height))
        return bytes
    }

    @Test("Paper changes white, not black ink; input pixels remain original")
    func multiply() throws {
        let texture = image(UIColor(white: 0.7, alpha: 1))
        let processor = PaperMaterialProcessor(style: .paper, strength: 1, preserveColor: false)
        let white = image(.white)
        let output = try #require(processor.process(white, texture: texture))
        #expect(try pixel(output)[0] < 245)
        #expect(try pixel(white)[0] == 255)
        let black = try #require(processor.process(image(.black), texture: texture))
        #expect(try pixel(black)[0] < 3)
        #expect(output.size == white.size)
    }

    @Test("Color protection must still change neutral white, including the bundled kraft texture")
    func neutralWhiteWithProtection() throws {
        let source = image(.white)
        let processor = PaperMaterialProcessor(style: .kraft, strength: 1, preserveColor: true)
        let synthetic = try #require(processor.process(source, texture: image(UIColor(white: 0.6, alpha: 1))))
        #expect(try pixel(synthetic)[0] < 230)
        let texture = try #require(PaperMaterialProcessor.lightTexture(for: .kraft))
        let bundled = try #require(processor.process(source, texture: texture))
        #expect(try pixel(bundled)[0] < 250)
        #expect(try pixel(bundled)[2] < 245)
    }

    @Test("White is identical with protection on/off; log rendered RGB for bundled kraft")
    func whiteProtectionParity() throws {
        let source = image(.white)
        let texture = try #require(PaperMaterialProcessor.lightTexture(for: .kraft))
        let protected = try #require(PaperMaterialProcessor(style: .kraft, strength: 1, preserveColor: true)
            .process(source, texture: texture))
        let unprotected = try #require(PaperMaterialProcessor(style: .kraft, strength: 1, preserveColor: false)
            .process(source, texture: texture))
        let lhs = try pixel(protected)
        let rhs = try pixel(unprotected)
        print("PAPER_RGB kraft white protected=\(lhs) unprotected=\(rhs)")
        for channel in 0..<3 { #expect(abs(Int(lhs[channel]) - Int(rhs[channel])) <= 2) }
        #expect(rhs[2] < 230)
    }

    @Test("Mask branches: black, dark gray, bright gray, white, saturated and pale color")
    func maskBranches() throws {
        let texture = image(UIColor(white: 0.5, alpha: 1))
        let colors: [UIColor] = [.black, UIColor(white: 0.5, alpha: 1),
                                 UIColor(white: 0.9, alpha: 1), .white, .yellow,
                                 UIColor(red: 1, green: 0.9, blue: 0.9, alpha: 1)]
        for (index, color) in colors.enumerated() {
            let source = image(color)
            let original = try pixel(source)
            let protected = try #require(PaperMaterialProcessor(style: .paper, strength: 1, preserveColor: true)
                .process(source, texture: texture))
            let unprotected = try #require(PaperMaterialProcessor(style: .paper, strength: 1, preserveColor: false)
                .process(source, texture: texture))
            let result = try pixel(protected)
            let unrestricted = try pixel(unprotected)
            print("PAPER_RGB branch=\(index) source=\(original) protected=\(result) unprotected=\(unrestricted)")
            if [0, 1, 4].contains(index) {
                for channel in 0..<3 { #expect(abs(Int(original[channel]) - Int(result[channel])) <= 3) }
            } else {
                #expect(Int(original[0]) - Int(result[0]) > 8)
            }
            if index == 5 { #expect(result[0] > unrestricted[0] + 8) }
            #expect(result[3] == 255)
        }
    }

    @Test("Legacy catalog loading must produce material in light and dark ambient traits")
    func legacyCatalogPath() throws {
        for ambient in [UIUserInterfaceStyle.light, .dark] {
            try UITraitCollection(userInterfaceStyle: ambient).performAsCurrent {
                let texture = try #require(UIImage(named: ReaderTextureStyle.kraft.imageName, in: .main,
                    compatibleWith: UITraitCollection(userInterfaceStyle: .light)))
                print("PAPER_LEGACY ambient=\(ambient.rawValue) cg=\(texture.cgImage != nil) asset=\(texture.imageAsset != nil)")
                let output = try #require(PaperMaterialProcessor(style: .kraft, strength: 1, preserveColor: true)
                    .process(image(.white), texture: texture))
                let rgb = try pixel(output)
                print("PAPER_LEGACY ambient=\(ambient.rawValue) rgb=\(rgb)")
                #expect(rgb[2] < 230)
            }
        }
    }

    @Test("Frozen asset and legacy catalog both render off the main thread")
    func backgroundCatalogPath() async throws {
        let source = image(.white)
        let texture = try #require(UIImage(named: ReaderTextureStyle.kraft.imageName, in: .main,
            compatibleWith: UITraitCollection(userInterfaceStyle: .light)))
        let frozen = try #require(PaperMaterialProcessor.lightTexture(for: .kraft))
        let outputs = await Task.detached {
            let processor = PaperMaterialProcessor(style: .kraft, strength: 1, preserveColor: true)
            return [processor.process(source, texture: texture), processor.process(source, texture: frozen)]
        }.value
        for (index, output) in outputs.enumerated() {
            let result = try #require(output)
            let rgb = try pixel(result)
            print("PAPER_BACKGROUND path=\(index) rgb=\(rgb)")
            #expect(rgb[2] < 230)
        }
    }

    @Test("Color protection preserves saturated artwork")
    func colorProtection() throws {
        let processor = PaperMaterialProcessor(style: .paper, strength: 1, preserveColor: true)
        let red = image(.red)
        let output = try #require(processor.process(red, texture: image(UIColor(white: 0.6, alpha: 1))))
        let original = try pixel(red)
        let result = try pixel(output)
        #expect(abs(Int(original[0]) - Int(result[0])) <= 2)
        #expect(result[1] <= 2)
    }

    @Test("Zero intensity skips allocation; orientation and scale survive")
    func identityAndMetadata() throws {
        let source = image(.white)
        let texture = image(.gray)
        #expect(PaperMaterialProcessor(style: .paper, strength: 0, preserveColor: true)
            .process(source, texture: texture) == nil)
        let rotated = UIImage(cgImage: try #require(source.cgImage), scale: 2, orientation: .right)
        let output = try #require(PaperMaterialProcessor(style: .paper, strength: 0.5, preserveColor: true)
            .process(rotated, texture: texture))
        #expect(output.scale == rotated.scale)
        #expect(output.imageOrientation == rotated.imageOrientation)
    }

    @Test("Light variants exist in every style and settings identifiers cannot collide")
    func assetsAndIdentifiers() throws {
        for style in ReaderTextureStyle.allCases {
            #expect(UIImage(named: style.imageName, in: .main,
                            compatibleWith: UITraitCollection(userInterfaceStyle: .light)) != nil)
        }
        let processors = [
            PaperMaterialProcessor(style: .paper, strength: 0.3, preserveColor: true),
            PaperMaterialProcessor(style: .beige, strength: 0.3, preserveColor: true),
            PaperMaterialProcessor(style: .paper, strength: 0.4, preserveColor: true),
            PaperMaterialProcessor(style: .paper, strength: 0.3, preserveColor: false)
        ]
        #expect(Set(processors.map(\.identifier)).count == processors.count)
        #expect(processors[0].identifier.contains("/light/"))
    }

    @Test("Animated and oversized pages are skipped")
    func bounds() throws {
        let source = image(.white)
        let animated = try #require(UIImage.animatedImage(with: [source, source], duration: 1))
        #expect(!PaperMaterialProcessor.supports(animated))
        #expect(!PaperMaterialProcessor.supports(image(.white, size: CGSize(width: 33_000, height: 1))))
    }

    @Test("Grayscale-backed scanned pages receive paper with protection on and off")
    func grayscaleScan() throws {
        let bytes = Data(repeating: 255, count: 64)
        let provider = try #require(CGDataProvider(data: bytes as CFData))
        let cg = try #require(CGImage(width: 8, height: 8, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: 8, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        for protection in [true, false] {
            let output = try #require(PaperMaterialProcessor(style: .kraft, strength: 1, preserveColor: protection)
                .process(UIImage(cgImage: cg), texture: try #require(PaperMaterialProcessor.lightTexture(for: .kraft))))
            let rgb = try pixel(output)
            print("PAPER_GRAY protected=\(protection) rgb=\(rgb)")
            #expect(rgb[2] < 230)
        }
    }

    @Test("Webtoon texture repeats every 512 source pixels rather than stretching")
    func repeatPitch() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let texture = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
        }
        for protection in [true, false] {
            let output = try #require(PaperMaterialProcessor(style: .paper, strength: 1, preserveColor: protection)
                .process(image(.white, size: CGSize(width: 8, height: 1024)), texture: texture))
            #expect(try pixel(output, y: 64) == pixel(output, y: 576))
            #expect(try pixel(output, y: 64) != pixel(output, y: 320))
        }
    }
}
