@testable import Aidoku
import AsyncDisplayKit
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct PaperMaterialDisplayTests {
    private let keys = ["Reader.backgroundColor", "Reader.textureScope", "Reader.textureStyle",
                        "Reader.texturePageStrength", "Reader.texturePreserveColor"]

    private func withSettings(_ body: () async throws -> Void) async rethrows {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier.flatMap { defaults.persistentDomain(forName: $0) } ?? [:]
        defer {
            for key in keys {
                if let value = domain[key] { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
                NotificationCenter.default.post(name: Notification.Name(key), object: nil)
            }
        }
        defaults.set("texture", forKey: keys[0])
        defaults.set("pages", forKey: keys[1])
        defaults.set("kraft", forKey: keys[2])
        defaults.set(1.0, forKey: keys[3])
        defaults.set(true, forKey: keys[4])
        try await body()
    }

    private func whiteImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
    }

    private func waitForResult(in view: UIImageView) async throws -> UIImageView {
        for _ in 0..<100 {
            if let overlay = view.subviews.compactMap({ $0 as? UIImageView }).first,
               overlay.image != nil {
                return overlay
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("No material image reached the actual UIImageView within five seconds")
        return try #require(view.subviews.compactMap { $0 as? UIImageView }.first)
    }

    @Test("Presentation reaches a laid-out image view while original stays intact")
    func presentation() async throws {
        try await withSettings {
            let view = UIImageView()
            let display = PaperMaterialDisplay(imageView: view)
            let original = whiteImage()
            view.image = original
            display.setImage(animated: false)
            view.frame = CGRect(x: 0, y: 0, width: 160, height: 240)
            view.layoutIfNeeded()
            let overlay = try await waitForResult(in: view)
            #expect(overlay.bounds == view.bounds)
            #expect(view.image === original)
            #expect(overlay.image != nil)
            UserDefaults.standard.set("background", forKey: "Reader.textureScope")
            NotificationCenter.default.post(name: Notification.Name("Reader.textureScope"), object: nil)
            #expect(overlay.image == nil)
            #expect(view.image === original)
        }
    }

    @Test("Webtoon custom view block installs material and reset clears it")
    func webtoon() async throws {
        try await withSettings {
            let node = GIFImageNode()
            let original = whiteImage()
            node.image = original
            let view = try #require(node.view as? UIImageView)
            view.frame = CGRect(x: 0, y: 0, width: 160, height: 240)
            let overlay = try await waitForResult(in: view)
            #expect(view.image === original)
            node.reset()
            await Task.yield()
            // reset schedules its UIKit changes onto the main actor.
            for _ in 0..<20 where overlay.image != nil {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            #expect(overlay.image == nil)
            #expect(view.image == nil)
        }
    }
}
