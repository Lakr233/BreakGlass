//
//  FlyingBreakGlassButtonView.swift
//  BreakGlass
//
//  Created by qaq on 4/10/2025.
//

import DisplayLink
import UIKit

final class FlyingBreakGlassButtonView: BreakGlassButtonView {
    struct Configuration {
        var size: CGSize
        var startPoint: CGPoint
        var controlPoint: CGPoint
        var endPoint: CGPoint
        var duration: TimeInterval
        var spin: CGFloat
        var gravity: CGFloat
        var symbol: String
    }

    private enum FlightState {
        case idle
        case flying
        case resolved(Resolution)
    }

    private enum Resolution {
        case hit
        case miss
        case cancel
    }

    private let configuration: Configuration
    private lazy var displayLink: DisplayLink = {
        let link = DisplayLink(context: .view(self))
        link.isPaused = true
        link.delegate = self
        return link
    }()
    private var state: FlightState = .idle
    private let sizeScale: CGFloat = 0.85
    private let slowDownIncrement: Double = 0.18
    private let maxSlowDownFactor: Double = 1.9

    private var activeControlPoint: CGPoint
    private var activeEndPoint: CGPoint

    private var lastFrameTimestamp: TimeInterval?
    private var slowDownFactor: Double = 1

    private var launchElapsedTime: TimeInterval = 0
    private var velocity: CGVector = .zero
    private var horizontalAcceleration: CGFloat = 0
    private var verticalGravity: CGFloat = 0

    private let fadeInDuration: TimeInterval = 0.18
    private let fadeOutDuration: TimeInterval = 0.22
    private var fadeOutElapsed: TimeInterval = 0
    private var isFadingOut = false

    private var angularVelocity: CGFloat = 0
    private var rotationAngle: CGFloat = 0

    private var flightDuration: TimeInterval { max(configuration.duration, 0.35) }

    var onHit: (() -> Void)?
    var onMiss: (() -> Void)?

    init(configuration: Configuration) {
        self.configuration = configuration
        activeControlPoint = configuration.controlPoint
        activeEndPoint = configuration.endPoint
        super.init {
            let image = UIImage(systemName: configuration.symbol)
            let view = UIImageView(image: image)
            view.tintColor = .random
            view.contentMode = .scaleAspectFit
            let wrapper = UIView()
            wrapper.addSubview(view)
            view.snp.makeConstraints { make in
                make.width.height.equalTo(32).priority(.high)
                make.center.equalToSuperview()
            }
            return wrapper
        }

        onTap = { [weak self] in
            self?.applyTapSlowdown()
        }
        onBreak = { [weak self] in
            self?.resolve(with: .hit)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func deploy(in container: UIView) {
        guard case .idle = state else { return }
        state = .flying
        slowDownFactor = 1
        launchElapsedTime = 0
        fadeOutElapsed = 0
        isFadingOut = false
        lastFrameTimestamp = nil
        rotationAngle = 0
        angularVelocity = 0

        container.addSubview(self)

        bounds = CGRect(origin: .zero, size: configuration.size)
        transform = .identity
        center = configuration.startPoint
        alpha = 0

        updateFlightPath(for: container)
        configureFlightParameters()
        startDisplayLink()
    }

    private func configureFlightParameters() {
        let duration = flightDuration
        let start = configuration.startPoint
        let control = activeControlPoint
        let end = activeEndPoint

        let peakY = min(control.y, start.y - 20)
        let upwardDistance = max(Double(start.y - peakY), 12)
        let downwardDistance = max(Double(end.y - peakY), 12)

        var gravityValue: Double
        if configuration.gravity > 0 {
            gravityValue = Double(configuration.gravity)
        } else {
            let ascend = sqrt(2 * upwardDistance)
            let descend = sqrt(2 * downwardDistance)
            gravityValue = pow((ascend + descend) / Double(duration), 2)
        }
        gravityValue = min(max(gravityValue, 280), 3600)
        verticalGravity = CGFloat(gravityValue)

        let initialVy = -sqrt(2 * gravityValue * upwardDistance)
        velocity = CGVector(dx: 0, dy: CGFloat(initialVy))

        let timeToPeak = max(-velocity.dy / verticalGravity, 0.05)
        let tPeak = Double(timeToPeak)
        let totalTime = Double(duration)

        let deltaControlX = Double(control.x - start.x)
        let deltaEndX = Double(end.x - start.x)
        let determinant = 0.5 * tPeak * totalTime * (totalTime - tPeak)

        if abs(determinant) > 0.0001 {
            let vx0 = (deltaControlX * 0.5 * totalTime * totalTime - deltaEndX * 0.5 * tPeak * tPeak) / determinant
            let ax = (tPeak * deltaEndX - totalTime * deltaControlX) / determinant
            velocity.dx = CGFloat(vx0)
            horizontalAcceleration = CGFloat(ax)
        } else {
            horizontalAcceleration = 0
            velocity.dx = totalTime > 0 ? CGFloat(deltaEndX / totalTime) : 0
        }

        angularVelocity = configuration.spin / CGFloat(max(duration, 0.01))
    }

    func cancelFlight() {
        if case .flying = state {
            resolve(with: .cancel)
        } else {
            stopDisplayLink()
        }
        alpha = 0
        layer.removeAllAnimations()
        removeFromSuperview()
    }

    override func removeFromSuperview() {
        stopDisplayLink()
        isFadingOut = false
        super.removeFromSuperview()
    }

    private func startDisplayLink() {
        displayLink.isPaused = false
        lastFrameTimestamp = nil
    }

    private func stopDisplayLink() {
        displayLink.isPaused = true
        lastFrameTimestamp = nil
    }

    private func updateFlightPath(for container: UIView) {
        let height = container.bounds.height
        guard height > 0 else {
            activeControlPoint = configuration.controlPoint
            activeEndPoint = configuration.endPoint
            return
        }

        // Randomize the peak height (where button reaches before falling off screen)
        let minimumPeakY = height * 0.25
        let maximumPeakY = height * (2.0 / 3.0)

        guard maximumPeakY >= minimumPeakY else {
            activeControlPoint = configuration.controlPoint
            activeEndPoint = configuration.endPoint
            return
        }

        let peakY = CGFloat.random(in: minimumPeakY ... maximumPeakY)

        // Keep the original endPoint (off-screen), only adjust control point for peak
        activeEndPoint = configuration.endPoint
        activeControlPoint = CGPoint(
            x: configuration.controlPoint.x,
            y: peakY
        )
    }

    private func applyTapSlowdown() {
        guard case .flying = state else { return }
        guard slowDownFactor < maxSlowDownFactor else { return }
        slowDownFactor = min(slowDownFactor + slowDownIncrement, maxSlowDownFactor)
    }

    private func handleFrame(deltaTime: TimeInterval) {
        let clampedDelta = max(0, min(deltaTime, 1.0 / 30.0))
        let effectiveDelta = clampedDelta / slowDownFactor

        switch state {
        case .flying:
            launchElapsedTime += effectiveDelta
            advancePhysics(by: effectiveDelta)

            if center.y < -bounds.height {
                resolve(with: .miss)
            } else if launchElapsedTime >= flightDuration {
                resolve(with: .miss)
            }
        case let .resolved(resolution):
            if resolution == .miss {
                advancePhysics(by: effectiveDelta)
            }
        case .idle:
            break
        }

        updateAppearance(deltaTime: clampedDelta, motionDelta: effectiveDelta)
    }

    private func advancePhysics(by delta: TimeInterval) {
        guard delta > 0 else { return }

        let dt = CGFloat(delta)
        velocity.dx += horizontalAcceleration * dt
        velocity.dy += verticalGravity * dt

        center.x += velocity.dx * dt
        center.y += velocity.dy * dt
    }

    private func updateAppearance(deltaTime: TimeInterval, motionDelta: TimeInterval) {
        if isFadingOut {
            fadeOutElapsed += deltaTime
            let fadeProgress = min(fadeOutElapsed / fadeOutDuration, 1)
            alpha = max(0, 1 - CGFloat(fadeProgress))
            if fadeProgress >= 1 {
                isFadingOut = false
                removeFromSuperview()
                return
            }
        } else {
            let fadeProgress = min(launchElapsedTime / fadeInDuration, 1)
            alpha = max(alpha, CGFloat(fadeProgress))
        }

        rotationAngle += angularVelocity * CGFloat(motionDelta)
        applyTransform()
    }

    private func applyTransform() {
        transform = CGAffineTransform.identity
            .rotated(by: rotationAngle)
    }

    private func approach(_ value: CGFloat, to target: CGFloat, rate: CGFloat, delta: TimeInterval) -> CGFloat {
        guard value != target else { return target }
        let maximumStep = CGFloat(delta) * rate
        if maximumStep <= 0 { return value }

        let diff = target - value
        if abs(diff) <= 0.0001 { return target }

        let step = diff * min(1, maximumStep)
        let result = value + step
        return abs(result - target) < 0.0001 ? target : result
    }

    private func resolve(with resolution: Resolution) {
        switch state {
        case .flying:
            state = .resolved(resolution)
        case .resolved:
            state = .resolved(resolution)
        case .idle:
            state = .resolved(resolution)
        }

        switch resolution {
        case .hit:
            stopDisplayLink()
            onHit?()
        case .miss:
            slowDownFactor = 1
            if !isFadingOut {
                isFadingOut = true
                fadeOutElapsed = 0
            }
            onMiss?()
        case .cancel:
            stopDisplayLink()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // The link stops ticking outside a window; restart timing on return.
        lastFrameTimestamp = nil
    }
}

extension FlyingBreakGlassButtonView: DisplayLinkDelegate {
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
        handleFrame(deltaTime: delta)
    }
}
