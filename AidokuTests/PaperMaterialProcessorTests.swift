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
        let output = try #require(PaperMaterialProcessor(style: .paper, strength: 1, preserveColor: false)
            .process(image(.white, size: CGSize(width: 8, height: 1024)), texture: texture))
        #expect(try pixel(output, y: 64) == pixel(output, y: 576))
        #expect(try pixel(output, y: 64) != pixel(output, y: 320))
    }
}
