//
//  ParticleView.swift
//  TrollNFC
//
//  Created by 砍砍 on 6/8/25.
//

import MetalKit
import simd
import UIEffectKitBase

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

class ParticleView: EffectKitView {
    private var device: MTLDevice!
    private var metalView: MTKView!
    private var renderer = Renderer()

    #if canImport(UIKit)
        override init(frame: CGRect) {
            super.init(frame: frame)
            setupMetalDevice()
            setupMetalView()
            setupViewProperties()
        }

    #elseif canImport(AppKit)
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setupMetalDevice()
            setupMetalView()
            setupViewProperties()
        }
    #endif

    private func setupMetalDevice() {
        guard let device = Self.createSystemDefaultDevice() else {
            fatalError("failed to create Metal device")
        }
        self.device = device
    }

    private func setupMetalView() {
        metalView = MTKView(frame: .zero, device: device)
        configureMetalView()
        addSubview(metalView)
        updateMetalViewLayout(for: bounds)
    }

    private func configureMetalView() {
        #if canImport(UIKit)
            metalView.layer.isOpaque = false
            metalView.backgroundColor = UIColor.clear
        #elseif canImport(AppKit)
            metalView.wantsLayer = true
            metalView.layer?.isOpaque = false
            metalView.layer?.backgroundColor = NSColor.clear.cgColor
        #endif
        metalView.delegate = renderer
    }

    private func setupViewProperties() {
        #if canImport(UIKit)
            clipsToBounds = false
            metalView.clipsToBounds = false
        #elseif canImport(AppKit)
            // macOS doesn't have clipsToBounds, use layer property instead
            wantsLayer = true
            layer?.masksToBounds = false
            metalView.wantsLayer = true
            metalView.layer?.masksToBounds = false
        #endif
    }

    private static func createSystemDefaultDevice() -> MTLDevice? {
        MTLCreateSystemDefaultDevice()
    }

    private func updateMetalViewLayout(for bounds: CGRect) {
        let expandedBounds = bounds.insetBy(dx: -bounds.width, dy: -bounds.height)
        metalView.frame = expandedBounds

        #if canImport(UIKit)
            let scale = metalView.window?.screen.nativeScale
                ?? UIScreen.main.nativeScale
        #elseif canImport(AppKit)
            let scale = metalView.window?.backingScaleFactor
                ?? metalView.layer?.contentsScale
                ?? NSScreen.main?.backingScaleFactor
                ?? 1
        #endif

        let drawableSize = CGSize(width: expandedBounds.width * scale, height: expandedBounds.height * scale)
        metalView.drawableSize = drawableSize
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        metalView.delegate = nil
        renderer.cancel()
        metalView.removeFromSuperview()
        metalView = nil
    }

    func beginWith(
        _ image: CGImage,
        targetFrame: CGRect,
        onComplete: @escaping () -> Void,
        onFirstFrameRendered: @escaping () -> Void
    ) {
        renderer.prepareResources(
            with: device,
            image: image,
            targetFrame: targetFrame,
            onComplete: onComplete,
            onFirstFrameRendered: onFirstFrameRendered
        )
        metalView.draw()
    }

    #if canImport(UIKit)
        override func layoutSubviews() {
            super.layoutSubviews()
            updateMetalViewLayout(for: bounds)
        }
    #endif

    #if canImport(AppKit)
        override func layout() {
            super.layout()
            updateMetalViewLayout(for: bounds)
        }
    #endif
}
