import AppKit

/// Pastille flottante affichée pendant la dictée.
///
/// Deux exigences non négociables :
///
/// * **ne jamais prendre le focus.** Le texte doit atterrir dans l'application
///   que l'utilisateur avait devant lui ; une fenêtre qui devient active
///   déplacerait le curseur et casserait l'insertion. D'où un `NSPanel`
///   `.nonactivatingPanel` qui refuse de devenir fenêtre clé.
/// * **montrer qu'on entend.** Une pastille statique ne dit pas si le micro
///   capte vraiment. Le niveau sonore en direct, si.
@MainActor
final class RecordingOverlay {
    private var panel: NSPanel?
    private var timer: Timer?

    private let dot = NSView()
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let statusLabel = NSTextField(labelWithString: "")
    private let meter = LevelMeter()
    private let modeButton = NSButton()

    /// Source du niveau sonore, interrogée à l'affichage.
    var levelProvider: (() -> Float)?
    var durationProvider: (() -> TimeInterval)?
    var onToggleMode: (() -> Void)?
    var onCancel: (() -> Void)?

    private var startedAt: Date?
    private var pulsePhase: CGFloat = 0

    // MARK: - Cycle de vie

    func showRecording(mode: TranscriptionMode) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        startedAt = Date()
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        meter.isHidden = false
        dot.isHidden = false
        timeLabel.isHidden = false
        modeButton.isHidden = false
        modeButton.title = mode == .intended ? "Texte nettoyé" : "Mot à mot"

        position(panel)
        panel.orderFrontRegardless()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Bascule sur l'état « transcription en cours ».
    ///
    /// Sur une longue dictée le traitement dure plusieurs secondes : sans ce
    /// retour, l'utilisateur croit que rien ne se passe et relance la dictée.
    func showProcessing() {
        guard let panel else { return }
        dot.isHidden = true
        meter.isHidden = true
        timeLabel.isHidden = true
        modeButton.isHidden = true
        statusLabel.isHidden = false
        statusLabel.stringValue = "Transcription…"
        position(panel)
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        startedAt = nil
        panel?.orderOut(nil)
    }

    // MARK: - Construction

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        // Visible au-dessus du plein écran et sur tous les bureaux : la dictée
        // sert justement pendant qu'on travaille ailleurs.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 22
        blur.layer?.masksToBounds = true
        panel.contentView = blur

        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 5
        dot.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timeLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor

        modeButton.bezelStyle = .inline
        modeButton.isBordered = false
        modeButton.font = .systemFont(ofSize: 11)
        modeButton.contentTintColor = .tertiaryLabelColor
        modeButton.target = self
        modeButton.action = #selector(toggleMode)

        let stack = NSStackView(views: [dot, timeLabel, meter, modeButton, statusLabel])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),
            meter.widthAnchor.constraint(equalToConstant: 76),
            meter.heightAnchor.constraint(equalToConstant: 16),
        ])
        return panel
    }

    /// Bas de l'écran, centré — hors du chemin du regard et du texte en cours
    /// de saisie, tout en restant visible du coin de l'œil.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 90
        ))
    }

    private func tick() {
        if let startedAt {
            let elapsed = Int(Date().timeIntervalSince(startedAt))
            timeLabel.stringValue = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
        }
        meter.level = levelProvider?() ?? 0

        // Pulsation du point : signale que l'enregistrement est actif même
        // quand l'utilisateur se tait un instant.
        pulsePhase += 0.09
        let alpha = 0.55 + 0.45 * (sin(pulsePhase) + 1) / 2
        dot.layer?.opacity = Float(alpha)
    }

    @objc private func toggleMode() {
        onToggleMode?()
    }

    func updateMode(_ mode: TranscriptionMode) {
        modeButton.title = mode == .intended ? "Texte nettoyé" : "Mot à mot"
    }
}

/// Barres de niveau sonore.
private final class LevelMeter: NSView {
    var level: Float = 0 {
        didSet { needsDisplay = true }
    }

    private let barCount = 13
    private var history: [Float] = []

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        history.append(level)
        if history.count > barCount { history.removeFirst(history.count - barCount) }

        let barWidth: CGFloat = 3
        let gap = (bounds.width - CGFloat(barCount) * barWidth) / CGFloat(barCount - 1)
        context.setFillColor(NSColor.labelColor.withAlphaComponent(0.65).cgColor)

        for index in 0..<barCount {
            // Les barres défilent de droite à gauche : le plus récent à droite,
            // comme un tracé qui avance.
            let value = index < history.count ? history[history.count - 1 - index] : 0
            let height = max(3, CGFloat(value) * bounds.height)
            let x = bounds.width - CGFloat(index + 1) * barWidth - CGFloat(index) * gap
            let rect = NSRect(x: x, y: (bounds.height - height) / 2,
                              width: barWidth, height: height)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 1.5,
                                   cornerHeight: 1.5, transform: nil))
            context.fillPath()
        }
    }
}
