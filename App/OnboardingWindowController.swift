import AppKit
import QuartzCore

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let rows: (OnboardingStep) -> [NSView]
    private let didChangeStep: (OnboardingStep) -> Void
    private let didDismiss: () -> Void
    private let didComplete: () -> Void
    private let appIcon: NSImage
    private let lifecycle: ApplicationLifecycle
    private(set) var step = OnboardingStep.welcome
    private var intro: OnboardingIntroView?
    private var wasVisibleBeforeTermination = false
    private let content = NSView()

    init(
        lifecycle: ApplicationLifecycle, rows: @escaping (OnboardingStep) -> [NSView],
        didChangeStep: @escaping (OnboardingStep) -> Void, didDismiss: @escaping () -> Void,
        didComplete: @escaping () -> Void
    ) {
        self.lifecycle = lifecycle
        self.rows = rows
        self.didChangeStep = didChangeStep
        self.didDismiss = didDismiss
        self.didComplete = didComplete
        if let url = Bundle.main.url(forResource: "Buckle", withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            appIcon = image
        } else {
            appIcon = NSApp.applicationIconImage
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = localized("onboarding.title")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentView = content
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func present() {
        guard !lifecycle.terminationRequested, let window else { return }
        let shouldAnimate = !window.isVisible
        if shouldAnimate {
            step = .welcome
            render()
            window.center()
        }
        NSApp.activate()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        if shouldAnimate { playIntro() }
    }

    // External Finder actions take precedence without marking an unseen guide as dismissed.
    func suspend() {
        intro?.cancel()
        intro = nil
        window?.orderOut(nil)
    }

    func suspendForTermination() {
        guard !lifecycle.terminationRequested else { return }
        wasVisibleBeforeTermination = window?.isVisible == true
        suspend()
    }

    func resumeAfterCancelledTermination() {
        guard wasVisibleBeforeTermination, !lifecycle.terminationRequested, let window else { return }
        wasVisibleBeforeTermination = false
        render()
        NSApp.activate()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        didChangeStep(step)
    }

    func refresh() {
        guard window?.isVisible == true, step == .permissions || step == .finder || step == .preferences else { return }
        render()
    }

    func windowWillClose(_ notification: Notification) {
        intro?.cancel()
        intro = nil
        didDismiss()
    }

    private func playIntro() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            content.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                content.animator().alphaValue = 1
            }
            return
        }
        let animation = OnboardingIntroView(frame: content.bounds, image: appIcon)
        animation.autoresizingMask = [.width, .height]
        intro = animation
        for view in content.subviews { view.isHidden = true }
        content.addSubview(animation)
        animation.play { [weak self] in
            guard let self, !self.lifecycle.terminationRequested, self.window?.isVisible == true else { return }
            self.intro = nil
            self.render()
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            self.content.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.45
                self.content.animator().alphaValue = 1
            }
        }
    }

    private func render() {
        for view in content.subviews { view.removeFromSuperview() }
        content.alphaValue = 1
        let headingText: String
        let helpText: String
        switch step {
        case .welcome:
            headingText = localized("onboarding.title")
            helpText = localized("onboarding.welcome.help")
        case .permissions:
            headingText = localized("onboarding.permissions.title")
            helpText = localized("onboarding.permissions.help")
        case .finder:
            headingText = localized("onboarding.finder.title")
            helpText = localized("onboarding.finder.help")
        case .complete:
            headingText = localized("onboarding.complete.title")
            helpText = localized("onboarding.complete.help")
        case .preferences:
            headingText = localized("onboarding.preferences.title")
            helpText = localized("onboarding.preferences.help")
        }
        let heading = NSTextField(wrappingLabelWithString: headingText)
        heading.font = .systemFont(ofSize: step == .welcome ? 29 : 25, weight: .semibold)
        heading.alignment = .center
        let help = NSTextField(wrappingLabelWithString: helpText)
        help.font = .systemFont(ofSize: 14)
        help.textColor = .secondaryLabelColor
        help.alignment = .center
        let body = NSStackView()
        body.orientation = .vertical
        body.alignment = .centerX
        body.spacing = 16
        var successIcon: NSImageView?
        if step == .welcome || step == .complete {
            let icon = NSImageView(image: appIcon)
            if step == .complete {
                icon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
                icon.contentTintColor = .systemGreen
                icon.wantsLayer = true
                icon.clipsToBounds = false
                successIcon = icon
            }
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.widthAnchor.constraint(equalToConstant: 80).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 80).isActive = true
            body.addArrangedSubview(icon)
        }
        body.addArrangedSubview(heading)
        body.addArrangedSubview(help)
        for row in rows(step) {
            body.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
        heading.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        help.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        let document = OnboardingDocumentView()
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        content.addSubview(scroll)
        document.addSubview(body)
        for view in [scroll, document, body] { view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(
                equalTo: content.topAnchor, constant: step == .welcome || step == .complete ? 64 : 24),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -100),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            body.topAnchor.constraint(equalTo: document.topAnchor),
            body.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
        let nextTitle: String
        switch step {
        case .welcome: nextTitle = localized("onboarding.start")
        case .complete: nextTitle = localized("onboarding.finish")
        case .permissions, .finder, .preferences: nextTitle = localized("onboarding.next")
        }
        let next = navigationButton(symbol: "arrow.right", title: nextTitle, primary: true, action: #selector(advance))
        next.identifier = NSUserInterfaceItemIdentifier("onboarding.next")
        next.keyEquivalent = "\r"
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 16
        if step != .welcome && step != .complete {
            let back = navigationButton(
                symbol: "arrow.left", title: localized("onboarding.back"),
                primary: false, action: #selector(goBack))
            back.identifier = NSUserInterfaceItemIdentifier("onboarding.back")
            footer.addArrangedSubview(back)
        }
        footer.addArrangedSubview(next)
        footer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(footer)
        NSLayoutConstraint.activate([
            footer.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -32),
        ])
        if step == .complete {
            let title = NSTextField(labelWithString: nextTitle)
            title.font = .systemFont(ofSize: 12, weight: .medium)
            title.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(title)
            title.centerXAnchor.constraint(equalTo: next.centerXAnchor).isActive = true
            title.topAnchor.constraint(equalTo: next.bottomAnchor, constant: 6).isActive = true
        }
        if let successIcon {
            content.layoutSubtreeIfNeeded()
            celebrate(successIcon)
        }
    }

    private func navigationButton(symbol: String, title: String, primary: Bool, action: Selector) -> NSButton {
        let button = OnboardingNextButton(title: "", target: self, action: action)
        button.isPrimary = primary
        button.bezelStyle = .circular
        button.isBordered = false
        button.wantsLayer = true
        let size: CGFloat = primary ? 52 : 40
        button.layer?.cornerRadius = size / 2
        button.updateBackground()
        button.contentTintColor = primary ? .windowBackgroundColor : .secondaryLabelColor
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: primary ? 21 : 17, weight: .medium))
        button.setAccessibilityLabel(title)
        button.toolTip = title
        button.isEnabled = !lifecycle.terminationRequested
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: size).isActive = true
        button.heightAnchor.constraint(equalToConstant: size).isActive = true
        return button
    }

    private func celebrate(_ icon: NSImageView) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = icon.layer else { return }
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.6
        pop.toValue = 1
        pop.damping = 12
        pop.stiffness = 180
        pop.duration = 0.6
        layer.add(pop, forKey: "success")
        let colors: [NSColor] = [.systemPink, .systemYellow, .systemBlue, .systemGreen, .systemOrange]
        for index in 0..<24 {
            let particle = CALayer()
            particle.bounds = CGRect(x: 0, y: 0, width: 5, height: 8)
            particle.position = CGPoint(x: 40, y: 40)
            particle.cornerRadius = 1
            icon.effectiveAppearance.performAsCurrentDrawingAppearance {
                particle.backgroundColor = colors[index % colors.count].cgColor
            }
            particle.opacity = 0
            layer.addSublayer(particle)
            let angle = CGFloat(index) * .pi * 2 / 24
            let distance = CGFloat(75 + (index % 4) * 16)
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = particle.position
            move.toValue = CGPoint(x: 40 + cos(angle) * distance, y: 40 + sin(angle) * distance)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.toValue = angle * 2
            let group = CAAnimationGroup()
            group.animations = [move, fade, spin]
            group.duration = 0.8
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            particle.add(group, forKey: "confetti")
        }
    }

    @objc func advance() {
        guard !lifecycle.terminationRequested else { return }
        switch step {
        case .welcome: step = .permissions
        case .permissions: step = .finder
        case .finder: step = .preferences
        case .preferences: step = .complete
        case .complete:
            window?.performClose(nil)
            didComplete()
            return
        }
        render()
        didChangeStep(step)
    }

    @objc private func goBack() {
        guard !lifecycle.terminationRequested else { return }
        switch step {
        case .preferences: step = .finder
        case .finder: step = .permissions
        case .permissions: step = .welcome
        case .welcome, .complete: return
        }
        render()
        didChangeStep(step)
    }

}

private final class OnboardingDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class OnboardingNextButton: NSButton {
    var isPrimary = true
    // The native circular bezel adds alignment insets even when its border is hidden.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    func updateBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (isPrimary ? NSColor.labelColor : NSColor.controlBackgroundColor).cgColor
        }
    }
}

@MainActor
private final class OnboardingIntroView: NSView {
    private var task: Task<Void, Never>?
    private let icon = CALayer()
    private let particles = CALayer()

    init(frame: NSRect, image: NSImage) {
        super.init(frame: frame)
        wantsLayer = true
        let size: CGFloat = 136
        let origin = CGPoint(x: (bounds.width - size) / 2, y: bounds.height * 0.61 - size / 2)
        icon.frame = CGRect(origin: origin, size: CGSize(width: size, height: size))
        // Request enough pixels for Retina rendering and the brief scale overshoot.
        var rect = CGRect(x: 0, y: 0, width: 512, height: 512)
        icon.contentsScale = 2
        icon.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        icon.contentsGravity = .resizeAspect
        particles.frame = bounds
        layer?.addSublayer(icon)
        layer?.addSublayer(particles)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    isolated deinit { task?.cancel() }

    func play(completion: @escaping @MainActor () -> Void) {
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.12, 1.09, 1, 1.06, 0.96, 1.12]
        scale.keyTimes = [0, 0.44, 0.58, 0.87, 0.94, 1]
        let shake = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        shake.values = [0, 0, -0.087, 0.087, -0.122, 0.122, -0.052, 0]
        shake.keyTimes = [0, 0.58, 0.66, 0.73, 0.80, 0.87, 0.94, 1]
        let group = CAAnimationGroup()
        group.animations = [scale, shake]
        group.duration = 1.18
        icon.add(group, forKey: "entrance")
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(1180))
                guard let self else { return }
                self.burst()
                try await Task.sleep(for: .milliseconds(500))
                completion()
            } catch is CancellationError {
                // Closing or suspending the window cancels the opening timeline.
            } catch { preconditionFailure("Unexpected onboarding animation error: \(error)") }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        icon.removeAllAnimations()
        for shard in particles.sublayers ?? [] { shard.removeAllAnimations() }
        removeFromSuperview()
    }

    private func burst() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        icon.isHidden = true
        for y in 0..<4 {
            for x in 0..<4 {
                let shard = CALayer()
                shard.contents = icon.contents
                shard.contentsRect = CGRect(x: CGFloat(x) / 4, y: CGFloat(y) / 4, width: 0.25, height: 0.25)
                shard.frame = CGRect(
                    x: icon.frame.minX + CGFloat(x) * 34,
                    y: icon.frame.maxY - CGFloat(y + 1) * 34, width: 34, height: 34)
                particles.addSublayer(shard)
                let move = CABasicAnimation(keyPath: "position")
                move.fromValue = shard.position
                move.toValue = CGPoint(
                    x: shard.position.x + (CGFloat(x) - 1.5) * 98,
                    y: shard.position.y - (CGFloat(y) - 1.5) * 92)
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1
                fade.toValue = 0
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0
                spin.toValue = Double(x - y) * 0.28
                let group = CAAnimationGroup()
                group.animations = [move, fade, spin]
                group.duration = 0.5
                group.timingFunction = CAMediaTimingFunction(name: .easeOut)
                shard.opacity = 0
                shard.add(group, forKey: "scatter")
            }
        }
        CATransaction.commit()
    }
}
