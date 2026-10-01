//
//  InGameView.swift
//  BreakGlass
//
//  Created by qaq on 4/10/2025.
//

import Combine
import DisplayLink
import GlyphixTextFx
import SnapKit
import Then
import UIKit

final class InGameView: UIView {
    private enum Constant {
        static let maxSimultaneousButtons = 4
        static let defaultLives = 3
    }

    private let playfieldView = UIView().then {
        $0.backgroundColor = .clear
        $0.clipsToBounds = false
    }

    private let scoreLabel = GlyphixTextLabel().then {
        $0.isBlurEffectEnabled = true
        $0.countsDown = true
        $0.font = .rounded(ofTextStyle: .largeTitle, weight: .black)
        $0.textColor = .label
        $0.numberOfLines = 0
    }

    private let heartsLabel = GlyphixTextLabel().then {
        $0.isBlurEffectEnabled = true
        $0.countsDown = false
        $0.font = .rounded(ofTextStyle: .title2, weight: .heavy)
        $0.textColor = .systemRed
        $0.textAlignment = .center
        $0.numberOfLines = 1
    }

    private lazy var displayLink = DisplayLink(context: .view(self))
    private var lastFrameTimestamp: TimeInterval?
    private var viewAlphaCurrent: CGFloat = 0
    private var viewAlphaTarget: CGFloat = 0
    private var cancellables = Set<AnyCancellable>()
    private var activeButtons: [FlyingBreakGlassButtonView] = []
    private var spawnTask: Task<Void, Never>?
    private var isGameActive = false
    private var latestDetails: GameStatus.Details?

    deinit {
        spawnTask?.cancel()
    }

    init() {
        super.init(frame: .zero)
        configureView()
        configureAnimationState()
        displayLink.delegate = self
        bindGameState()
        GameStatus.shared.requestGameReadyItems()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        startSpawnerIfNeeded()
    }

    private func configureView() {
        addSubview(playfieldView)
        addSubview(scoreLabel)
        addSubview(heartsLabel)

        scoreLabel.snp.makeConstraints { make in
            make.top.equalTo(safeAreaLayoutGuide).offset(24)
            make.centerX.equalToSuperview()
        }

        heartsLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(safeAreaLayoutGuide).inset(16)
        }

        playfieldView.snp.makeConstraints { make in
            make.top.equalTo(scoreLabel.snp.bottom).offset(24)
            make.left.right.equalToSuperview()
            make.bottom.equalTo(heartsLabel.snp.top).offset(-32)
        }

        scoreLabel.attachWiggleEffect(duration: 3)
        updateHearts(current: Constant.defaultLives, max: Constant.defaultLives, animated: false)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)
    }

    private func configureAnimationState() {
        alpha = 0
        lastFrameTimestamp = nil

        viewAlphaCurrent = 0
        viewAlphaTarget = 0

        scoreLabel.transform = .identity
        heartsLabel.transform = .identity

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.viewAlphaTarget = 1
        }
    }

    private func bindGameState() {
        GameStatus.shared.eventsPublisher
            .sink { [weak self] event in
                self?.handle(event)
            }
            .store(in: &cancellables)
    }

    private func handle(_ event: GameStatus.Event) {
        switch event {
        case let .scoreUpdate(details):
            updateHUD(with: details)
        case .newGame:
            resetForNewGame()
        case .gameOver:
            processGameOver()
        }
    }

    private func updateHUD(with details: GameStatus.Details) {
        let previousLives = latestDetails?.lives ?? details.maxLives
        scoreLabel.text = "\(details.score)"

        let lifeLost = details.lives < previousLives
        updateHearts(current: details.lives, max: details.maxLives, animated: lifeLost)

        latestDetails = details

        if details.gameOver {
            processGameOver()
        } else {
            isGameActive = true
            startSpawnerIfNeeded()
        }
    }

    private func resetForNewGame() {
        isGameActive = true
        latestDetails = nil
        stopSpawner()
        clearActiveButtons()
        updateHearts(current: Constant.defaultLives, max: Constant.defaultLives, animated: false)
        startSpawnerIfNeeded()
    }

    private func processGameOver() {
        guard isGameActive else { return }
        isGameActive = false
        stopSpawner()
        clearActiveButtons()
    }

    private func startSpawnerIfNeeded() {
        guard spawnTask == nil else { return }
        guard isGameActive else { return }
        guard playfieldView.bounds.width > 1, playfieldView.bounds.height > 1 else { return }

        spawnTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let delay = nextThrowDelay()
                let nanos = UInt64(max(delay, 0.3) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)

                if Task.isCancelled { break }

                await MainActor.run {
                    self.spawnBreakGlassButton()
                }
            }
        }
    }

    private func stopSpawner() {
        spawnTask?.cancel()
        spawnTask = nil
    }

    private func clearActiveButtons() {
        let buttons = activeButtons
        activeButtons.removeAll()
        buttons.forEach { $0.cancelFlight() }
    }

    private func spawnBreakGlassButton() {
        guard isGameActive else { return }
        guard latestDetails?.gameOver != true else { return }
        guard activeButtons.count < Constant.maxSimultaneousButtons else { return }

        let bounds = playfieldView.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }

        let configuration = makeConfiguration(in: bounds)
        let button = FlyingBreakGlassButtonView(configuration: configuration)

        button.onHit = { GameStatus.shared.hit() }
        button.onMiss = { GameStatus.shared.miss() }
        button.onRemoval = { [weak self, weak button] in
            guard let self, let button else { return }
            activeButtons.removeAll { $0 === button }
        }

        activeButtons.append(button)
        button.deploy(in: playfieldView)
    }

    private func makeConfiguration(in bounds: CGRect) -> FlyingBreakGlassButtonView.Configuration {
        let random = CGFloat.random(in: 80 ... 120)
        let size = CGSize(width: random, height: random)
        let padding = size.width / 2 + 24

        let startX = randomX(in: bounds, padding: padding)
        let endX = randomX(in: bounds, padding: padding)
        let startY = bounds.maxY + size.height
        let endY = bounds.maxY + size.height * 0.6

        let minPeak = max(bounds.height * 0.08, 32)
        let maxPeak = max(bounds.height * 0.28, minPeak + 24)
        let controlY = CGFloat.random(in: minPeak ... min(maxPeak, bounds.height * 0.6))
        let lateralDrift = CGFloat.random(in: -bounds.width * 0.25 ... bounds.width * 0.25)
        let controlX = ((startX + endX) / 2) + lateralDrift

        let combo = Double(latestDetails?.combo ?? 0)
        let durationBase = max(0.9, 1.7 - combo * 0.05)
        let duration = max(0.8, durationBase + Double.random(in: -0.12 ... 0.12))
        let spin = CGFloat.random(in: -CGFloat.pi ... CGFloat.pi) * 1.5

        return .init(
            size: size,
            startPoint: CGPoint(x: startX, y: startY),
            controlPoint: CGPoint(x: controlX, y: controlY),
            endPoint: CGPoint(x: endX, y: endY),
            duration: duration,
            spin: spin,
            gravity: 0,
            symbol: SFSymbols.all.randomElement()!
        )
    }

    private func randomX(in bounds: CGRect, padding: CGFloat) -> CGFloat {
        guard bounds.width > padding * 2 else {
            return bounds.midX
        }
        return CGFloat.random(in: padding ... (bounds.width - padding))
    }

    private func nextThrowDelay() -> TimeInterval {
        let combo = Double(latestDetails?.combo ?? 0)
        let base = max(0.95, 1.6 - combo * 0.04)
        let jitter = Double.random(in: -0.15 ... 0.15)
        return max(0.6, base + jitter)
    }

    private func stepAnimations(deltaTime: TimeInterval) {
        let clampedDelta = max(0, min(deltaTime, 1.0 / 30.0))

        viewAlphaCurrent = approach(current: viewAlphaCurrent, target: viewAlphaTarget, rate: 6, deltaTime: clampedDelta)
        alpha = viewAlphaCurrent
    }

    private func updateHearts(current: Int, max maxValue: Int, animated _: Bool) {
        let filled = max(0, min(current, maxValue))
        let empty = max(0, maxValue - filled)

        let newValue = String(repeating: "❤️", count: filled)
            + String(repeating: "🤍", count: empty)

        guard heartsLabel.text != newValue else { return }

        heartsLabel.text = newValue
    }

    private func approach(current value: CGFloat, target: CGFloat, rate: CGFloat, deltaTime: TimeInterval) -> CGFloat {
        guard value != target else { return target }
        let maxStep = CGFloat(deltaTime) * rate
        if maxStep <= 0 { return value }

        let diff = target - value
        if abs(diff) <= 0.0001 { return target }

        let step = diff * min(1, maxStep)
        let result = value + step
        return abs(result - target) < 0.0001 ? target : result
    }

    @objc private func handleTap() {
        SoundEffect.shared.playTap()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // The link stops ticking outside a window; restart timing on return.
        lastFrameTimestamp = nil
    }
}

extension InGameView: DisplayLinkDelegate {
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
        stepAnimations(deltaTime: delta)
    }
}
