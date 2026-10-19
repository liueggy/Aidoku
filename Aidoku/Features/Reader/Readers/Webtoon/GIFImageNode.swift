//
//  GIFImageNode.swift
//  Aidoku
//
//  Created by Skitty on 6/23/25.
//

import AsyncDisplayKit
import Gifu
import VisionKit

class GIFImageNode: ASControlNode {
    var imageView: GIFImageView?
    var animatedData: Data?
    private var hasAnimatedSource = false
    private var paperDisplay: PaperMaterialDisplay?
    var storedInteractions: [UIInteraction] = []

    override var contentMode: UIView.ContentMode {
        didSet {
            imageView?.contentMode = contentMode
        }
    }

    var image: UIImage? {
        didSet {
            Task { @MainActor [weak self] in
                self?.updateDisplayedImage()
            }
        }
    }

    override var isUserInteractionEnabled: Bool {
        didSet {
            imageView?.isUserInteractionEnabled = isUserInteractionEnabled
        }
    }

    @available(iOS 16.0, *)
    var imageAnalaysisInteraction: ImageAnalysisInteraction? {
        imageView?.interactions.first(where: { $0 is ImageAnalysisInteraction }) as? ImageAnalysisInteraction
    }

    override init() {
        super.init()

        setViewBlock { [weak self] in
            let gifView = GIFImageView()
            gifView.image = self?.image
            gifView.isUserInteractionEnabled = true
            if let contentMode = self?.contentMode {
                gifView.contentMode = contentMode
            }
            if let data = self?.animatedData {
                gifView.animate(withGIFData: data)
                self?.animatedData = nil
            }
            if let storedInteractions = self?.storedInteractions {
                storedInteractions.forEach {
                    gifView.addInteraction($0)
                }
                self?.storedInteractions = []
            }
            self?.imageView = gifView
            self?.paperDisplay = PaperMaterialDisplay(imageView: gifView)
            self?.paperDisplay?.setImage(animated: self?.hasAnimatedSource == true || self?.image?.images != nil)
            return gifView
        }
    }

    @MainActor
    private func updateDisplayedImage() {
        imageView?.image = image
        paperDisplay?.setImage(animated: hasAnimatedSource || image?.images != nil)
    }

    func animate(withGIFData data: Data) {
        hasAnimatedSource = true
        if let imageView {
            Task { @MainActor [weak self] in
                self?.paperDisplay?.setImage(animated: true)
                imageView.animate(withGIFData: data)
            }
        } else {
            animatedData = data
        }
    }

    func reset() {
        image = nil
        animatedData = nil
        hasAnimatedSource = false

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.imageView?.stopAnimatingGIF()
            self.updateDisplayedImage()
        }
    }

    @MainActor
    func addInteraction(_ interaction: UIInteraction) {
        if let imageView {
            imageView.addInteraction(interaction)
        } else {
            storedInteractions.append(interaction)
        }
    }

    @MainActor
    @available(iOS 16.0, *)
    func removeImageAnalysisInteraction() {
        guard
            let imageView,
            let interaction = imageView.interactions.first(where: { $0 is ImageAnalysisInteraction })
        else {
            return
        }
        imageView.removeInteraction(interaction)
    }
}
