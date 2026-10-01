//
//  MovingDotsView.swift
//  BreakGlass
//
//  Created by qaq on 5/10/2025.
//

import DisplayLink
import UIKit

class MovingDotsView: UIView {
    private lazy var displayLink = DisplayLink(context: .view(self))
    private var dots: [Dot] = []
    private let dotDiameter: CGFloat = 4.0
    private let dotSpacing: CGFloat = 10.0
    private let dotAlpha: CGFloat = 0.1
    private let dotColor = UIColor.label
    private let speed: CGFloat = 60.0 // pixels per second
    private var lastFrameTimestamp: TimeInterval?

    struct Dot {
        var position: CGPoint
        var isActive: Bool
    }

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        setupDisplayLink()
        setupDots()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    private func setupDisplayLink() {
        displayLink.delegate = self
    }

    private func setupDots() {
        // Create dots across the width with some spacing
        guard bounds.width > 0 else { return }

        let numberOfDots = max(1, Int(ceil(bounds.width / dotSpacing))) + 1

        dots = (0 ..< numberOfDots).map { index in
            let x = CGFloat(index) * dotSpacing + CGFloat.random(in: -dotSpacing / 2 ... dotSpacing / 2)
            let y = bounds.height + CGFloat.random(in: 0 ... bounds.height)
            return Dot(position: CGPoint(x: x, y: y), isActive: true)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setupDots()
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.setFillColor(dotColor.withAlphaComponent(dotAlpha).cgColor)

        for dot in dots where dot.isActive {
            let dotRect = CGRect(
                x: dot.position.x - dotDiameter / 2,
                y: dot.position.y - dotDiameter / 2,
                width: dotDiameter,
                height: dotDiameter
            )
            context.fillEllipse(in: dotRect)
        }
    }

    private func updateDots(deltaTime: TimeInterval) {
        let deltaY = CGFloat(deltaTime) * speed

        for i in 0 ..< dots.count {
            dots[i].position.y -= deltaY

            // Reset dot to bottom when it goes off screen
            if dots[i].position.y < -dotDiameter {
                dots[i].position.y = bounds.height + dotDiameter
                dots[i].position.x = CGFloat(i) * dotSpacing + CGFloat.random(in: -dotSpacing / 2 ... dotSpacing / 2)
            }
        }

        setNeedsDisplay()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // The link stops ticking outside a window; restart timing on return.
        lastFrameTimestamp = nil
    }
}

extension MovingDotsView: DisplayLinkDelegate {
    func displayLink(_: DisplayLink, didUpdate frame: DisplayLinkFrame) {
        let timestamp = frame.timestamp
        guard let previousTimestamp = lastFrameTimestamp else {
            lastFrameTimestamp = timestamp
            return
        }

        var delta = timestamp - previousTimestamp
        if !delta.isFinite || delta <= 0 {
            delta = max(frame.duration, 1.0 / 120.0)
        }
        lastFrameTimestamp = timestamp
        updateDots(deltaTime: delta)
    }
}
