import AppKit
import AVFoundation

/// Panneau flottant affiché pendant la dictée.
///
/// Il ne se contente pas d'indiquer que l'enregistrement tourne : il permet de
/// corriger le tir **en parlant**. On se rend compte au milieu d'une phrase
/// qu'on est en mot-à-mot au lieu de texte nettoyé, ou que la destination
/// n'est pas la bonne — il faut pouvoir changer sans arrêter, sinon la dictée
/// est à refaire.
///
/// Deux contraintes non négociables :
///
/// * **ne jamais prendre le focus.** Le texte doit atterrir dans l'application
///   que l'utilisateur avait devant lui ; une fenêtre qui devient active
///   déplacerait le curseur. D'où un `NSPanel` `.nonactivatingPanel`, dont les
///   boutons restent cliquables sans activer Caret.
/// * **montrer qu'on entend.** Un point fixe dit que l'enregistrement est
///   lancé, pas que le micro capte. Le niveau en direct, si.
@MainActor
final class RecordingOverlay {
    private var panel: NSPanel?
    private var timer: Timer?

    private let dot = NSView()
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let statusLabel = NSTextField(labelWithString: "")
    private let meter = LevelMeter()
    private let modeButton = NSButton()
    private let targetButton = NSButton()
    private let micButton = NSButton()
    private var controls: NSStackView?

    var levelProvider: (() -> Float)?
    var onToggleMode: (() -> Void)?
    var onToggleTarget: (() -> Void)?
    var onCancel: (() -> Void)?

    private var startedAt: Date?
    private var pulsePhase: CGFloat = 0

    // MARK: - Cycle de vie

    func showRecording(mode: TranscriptionMode, target: DictationTarget) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        startedAt = Date()
        statusLabel.isHidden = true
        controls?.isHidden = false
        update(mode: mode, target: target)

        position(panel)
        panel.orderFrontRegardless()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Bascule sur « transcription en cours ».
    ///
    /// Sur une longue dictée le traitement prend plusieurs secondes ; sans ce
    /// retour, on croit à un échec et on relance.
    func showProcessing() {
        guard let panel else { return }
        timer?.invalidate()
        controls?.isHidden = true
        statusLabel.isHidden = false
        statusLabel.stringValue = "Transcription…"
        panel.setContentSize(NSSize(width: 190, height: 46))
        position(panel)
    }

    /// La relecture prend quelques secondes de plus : le dire évite qu'on
    /// croie l'application bloquée.
    func showReviewing() {
        statusLabel.stringValue = "Relecture…"
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        startedAt = nil
        panel?.orderOut(nil)
    }

    func update(mode: TranscriptionMode, target: DictationTarget) {
        modeButton.attributedTitle = Self.buttonTitle(mode.label)
        targetButton.attributedTitle = Self.buttonTitle(
            target.isLocked ? "→ \(target.displayName)" : "Au curseur")
        targetButton.toolTip = target.isLocked
            ? "Cliquer pour revenir au curseur"
            : "Cliquer pour écrire dans un fichier"
        micButton.attributedTitle = Self.buttonTitle(Self.microphoneModeLabel)
        micButton.toolTip = "Mode micro du système — cliquer pour le changer"
        panel?.setContentSize(fittingSize())
        if let panel { position(panel) }
    }

    /// Mode micro courant, tel que macOS le rapporte.
    ///
    /// Lecture seule : Apple ne laisse aucune application imposer ce réglage,
    /// c'est un choix de l'utilisateur. On peut en revanche ouvrir le panneau
    /// système, ce qui évite d'aller le chercher dans le Centre de contrôle.
    private static var microphoneModeLabel: String {
        switch AVCaptureDevice.activeMicrophoneMode {
        case .voiceIsolation: "🎙 Isolement"
        case .wideSpectrum: "🎙 Large"
        default: "🎙 Standard"
        }
    }

    // MARK: - Construction

    private static func buttonTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    private static func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return line
    }

    private func fittingSize() -> NSSize {
        let width = (controls?.fittingSize.width ?? 260) + 28
        return NSSize(width: max(260, width), height: 46)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 46),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        // Visible au-dessus du plein écran et sur tous les bureaux : dicter en
        // travaillant ailleurs est précisément l'usage.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 23
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 0.5
        blur.layer?.borderColor = NSColor.separatorColor.cgColor
        panel.contentView = blur

        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 4.5
        dot.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timeLabel.textColor = .labelColor
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor

        for (button, action) in [(modeButton, #selector(toggleMode)),
                                 (targetButton, #selector(toggleTarget)),
                                 (micButton, #selector(openMicrophoneModes))] {
            button.isBordered = false
            button.bezelStyle = .inline
            button.target = self
            button.action = action
            // Réagit sans que Caret passe au premier plan.
            button.setButtonType(.momentaryChange)
        }

        let stack = NSStackView(views: [
            dot, timeLabel, meter,
            Self.separator(), modeButton,
            Self.separator(), targetButton,
            Self.separator(), micButton,
        ])
        stack.orientation = .horizontal
        stack.spacing = 9
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        controls = stack

        blur.addSubview(stack)
        blur.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            stack.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: blur.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 9),
            dot.heightAnchor.constraint(equalToConstant: 9),
            meter.widthAnchor.constraint(equalToConstant: 54),
            meter.heightAnchor.constraint(equalToConstant: 16),
        ])
        return panel
    }

    /// Bas de l'écran, centré — hors du regard et du texte en cours de saisie,
    /// mais visible du coin de l'œil.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                     y: frame.minY + 90))
    }

    private func tick() {
        if let startedAt {
            let elapsed = Int(Date().timeIntervalSince(startedAt))
            timeLabel.stringValue = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
        }
        meter.level = levelProvider?() ?? 0

        pulsePhase += 0.09
        dot.layer?.opacity = Float(0.55 + 0.45 * (sin(pulsePhase) + 1) / 2)
    }

    @objc private func toggleMode() { onToggleMode?() }
    @objc private func toggleTarget() { onToggleTarget?() }

    @objc private func openMicrophoneModes() {
        AVCaptureDevice.showSystemUserInterface(.microphoneModes)
    }
}

/// Barres de niveau sonore, défilant de droite à gauche.
private final class LevelMeter: NSView {
    var level: Float = 0 {
        didSet { needsDisplay = true }
    }

    private let barCount = 9
    private var history: [Float] = []

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        history.append(level)
        if history.count > barCount { history.removeFirst(history.count - barCount) }

        let barWidth: CGFloat = 3
        let gap = (bounds.width - CGFloat(barCount) * barWidth) / CGFloat(barCount - 1)
        context.setFillColor(NSColor.labelColor.withAlphaComponent(0.7).cgColor)

        for index in 0..<barCount {
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
