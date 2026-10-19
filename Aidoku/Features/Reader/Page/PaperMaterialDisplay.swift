import UIKit

/// Keeps ReaderPageView.imageView.image original for OCR, splitting and every existing consumer.
/// Only one bounded display result is retained per live page; no texture images enter Nuke caches.
final class PaperMaterialDisplay {
    private weak var imageView: UIImageView?
    private let overlay = UIImageView()
    private var observers: [NSObjectProtocol] = []
    private var operation: Operation?
    private var generation = UUID()
    private var renderedIdentifier: String?
    private var animated = false

    init(imageView: UIImageView) {
        self.imageView = imageView
        overlay.contentMode = .scaleAspectFit
        overlay.isUserInteractionEnabled = false
        overlay.isAccessibilityElement = false
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.frame = imageView.bounds
        imageView.insertSubview(overlay, at: 0)
        for key in [
            "Reader.backgroundColor", ReaderTextureBackground.styleKey,
            PaperMaterialProcessor.scopeKey, PaperMaterialProcessor.strengthKey,
            PaperMaterialProcessor.preserveColorKey
        ] {
            observers.append(NotificationCenter.default.addObserver(
                forName: Notification.Name(key), object: nil, queue: .main
            ) { [weak self] _ in self?.refresh() })
        }
    }

    deinit {
        operation?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func setImage(animated: Bool) {
        self.animated = animated
        renderedIdentifier = nil
        refresh()
    }

    private func refresh() {
        if let processor = PaperMaterialProcessor.current,
           renderedIdentifier == processor.identifier, overlay.image != nil {
            return
        }
        operation?.cancel()
        operation = nil
        generation = UUID()
        overlay.image = nil
        guard !animated, let image = imageView?.image,
              let processor = PaperMaterialProcessor.current,
              PaperMaterialProcessor.supports(image),
              let texture = UIImage(named: processor.style.imageName, in: .main,
                                    compatibleWith: UITraitCollection(userInterfaceStyle: .light)) else {
            renderedIdentifier = nil
            return
        }
        // The generation binds this settings identifier to this exact source image.
        let token = generation
        let identifier = processor.identifier
        let work = BlockOperation()
        work.addExecutionBlock { [weak self, weak work] in
            guard work?.isCancelled == false else { return }
            let result = autoreleasepool { processor.process(image, texture: texture) }
            guard work?.isCancelled == false else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.overlay.image = result
                self.renderedIdentifier = identifier
                self.operation = nil
            }
        }
        operation = work
        PaperMaterialProcessor.queue.addOperation(work)
    }
}
