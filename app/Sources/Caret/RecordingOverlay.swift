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
/// Quatre contraintes non négociables :
///
/// * **ne jamais prendre le focus.** Le texte doit atterrir dans l'application
///   que l'utilisateur avait devant lui ; une fenêtre qui devient active
///   déplacerait le curseur. D'où un `NSPanel` `.nonactivatingPanel`, dont les
///   contrôles restent cliquables sans activer Caret.
/// * **montrer qu'on entend.** Un point fixe dit que l'enregistrement est
///   lancé, pas que le micro capte. Le niveau en direct, si.
/// * **montrer l'état, pas seulement l'action.** Des boutons qui font défiler
///   les valeurs obligent à lire le libellé pour savoir où on en est. Des
///   segments montrent la valeur active d'un coup d'œil.
/// * **rester étroite.** Elle vit en bas de l'écran pendant qu'on travaille
///   ailleurs. D'où deux lignes courtes plutôt qu'une longue : ce qui
///   concerne la *captation* en haut — chrono, niveau, micro, aperçu — et ce
///   qui concerne le *texte* en dessous — mode et destination.
@MainActor
final class RecordingOverlay {
    /// Tout ce que la barre affiche, en un seul objet.
    ///
    /// Regroupé parce que ces valeurs bougent ensemble : changer de mode
    /// pendant une dictée doit repeindre la barre entière, et une signature à
    /// six paramètres se serait désynchronisée au premier oubli.
    struct Status {
        var mode: TranscriptionMode
        var target: DictationTarget
        /// Nom du fichier de notes mémorisé, `nil` si aucun.
        var noteName: String?
        /// Faux quand basculer sur les notes exigerait un sélecteur qu'on ne
        /// peut pas ouvrir maintenant.
        var canPickNote: Bool = true
        var previewEnabled: Bool
        var corpusEnabled: Bool
        var corpusKeepsAudio: Bool
    }

    private var panel: NSPanel?
    private var timer: Timer?

    private let dot = NSView()
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let statusLabel = NSTextField(labelWithString: "")
    private let previewLabel = NSTextField(labelWithString: "")
    private let meter = LevelMeter()
    private let modeControl = PillSelector(
        labels: TranscriptionMode.allCases.map(\.label), accent: accent)
    private let targetControl = PillSelector(
        labels: ["Curseur", "Notes…"], accent: accent)
    private let micButton = FirstMouseButton()
    private let previewButton = FirstMouseButton()
    private let corpusBadge = BadgeButton()
    private var container: NSStackView?
    private var recordingRow: NSStackView?
    private var textRow: NSStackView?
    private var previewHeight: NSLayoutConstraint?
    private var previewLineCount = 1

    var levelProvider: (() -> Float)?
    var onSelectMode: ((TranscriptionMode) -> Void)?
    var onSelectTarget: ((Bool) -> Void)?
    var onTogglePreview: (() -> Void)?
    var onToggleCorpus: (() -> Void)?
    var onCancel: (() -> Void)?

    private var startedAt: Date?
    private var pulsePhase: CGFloat = 0
    private var status = Status(mode: .intended, target: .caret, noteName: nil,
                                previewEnabled: false, corpusEnabled: false,
                                corpusKeepsAudio: false)

    // MARK: - Mesures et couleurs

    /// Teinte des états actifs. Une seule dans toute la barre : deux accents
    /// concurrents et plus rien ne ressort.
    static let accent = NSColor.systemTeal
    /// La collecte a sa propre couleur, et c'est délibéré : c'est le seul
    /// réglage qui écrit sur le disque à l'insu de l'utilisateur. Il doit se
    /// distinguer d'un simple choix de mode.
    private static let collecting = NSColor.systemOrange

    private static let rowHeight: CGFloat = 26
    private static let controlRowHeight: CGFloat = 29
    private static let padding: CGFloat = 10
    private static let rowSpacing: CGFloat = 7
    private static let previewLines = 3
    private static let previewFontSize: CGFloat = 13
    private static let previewLineHeight: CGFloat = 18
    private static let minimumWidth: CGFloat = 380
    private static let widthWithPreview: CGFloat = 440
    /// Au-delà, on ne garde que la fin du texte : ce sont les derniers mots
    /// prononcés qui intéressent, pas le début de la dictée.
    private static let previewCharacters = 200

    init() {
        // Une fenêtre créée sur un écran qui disparaît reste rattachée à
        // l'espace de cet écran : macOS ne la rapatrie pas. Elle continue
        // d'être ordonnée au premier plan, avec des coordonnées correctes,
        // sans jamais s'afficher — panne observée en débranchant un second
        // écran, et parfaitement muette côté application. On jette donc le
        // panneau à chaque changement d'écrans ; le suivant sera reconstruit
        // dans l'espace courant.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildForNewScreens() }
        }
    }

    // MARK: - Cycle de vie

    func showRecording(_ status: Status) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        startedAt = Date()
        statusLabel.isHidden = true
        container?.isHidden = false
        // Une ligne vide laisserait croire que l'aperçu est en panne le temps
        // que les premiers mots arrivent.
        setPreviewNotice(status.previewEnabled ? "en écoute…" : "")
        update(status)

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
        container?.isHidden = true
        statusLabel.isHidden = false
        statusLabel.stringValue = "Transcription…"
        panel.setContentSize(NSSize(width: 190, height: 46))
        position(panel)
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        startedAt = nil
        panel?.orderOut(nil)
    }

    var isRecording: Bool { timer != nil }

    func update(_ status: Status) {
        self.status = status

        modeControl.select(TranscriptionMode.allCases.firstIndex(of: status.mode) ?? 0)

        targetControl.setLabel(Self.noteLabel(for: status), at: 1)
        targetControl.select(status.target.isLocked ? 1 : 0)
        targetControl.setEnabled(status.noteName != nil || status.canPickNote, at: 1)
        // Court, et sur deux lignes : macOS ne replie pas les infobulles, une
        // phrase entière produit une bulle plus large que la moitié de l'écran.
        targetControl.toolTip = status.noteName.map {
            "Ajouté à \($0)\nVaut aussi pour la dictée en cours"
        } ?? "Aucun fichier de notes\nEn choisir un dans le menu de Caret"

        micButton.attributedTitle = Self.buttonTitle(Self.microphoneModeLabel)
        micButton.toolTip = "Mode micro du système\nCliquer pour le changer"

        previewButton.image = NSImage(
            systemSymbolName: status.previewEnabled ? "eye" : "eye.slash",
            accessibilityDescription: "Aperçu en direct")
        previewButton.contentTintColor = status.previewEnabled
            ? Self.accent : .tertiaryLabelColor
        previewButton.toolTip = Self.previewExplanation
        previewLabel.toolTip = Self.previewExplanation
        previewLabel.isHidden = !status.previewEnabled

        corpusBadge.setActive(status.corpusEnabled, color: Self.collecting)
        corpusBadge.toolTip = status.corpusEnabled
            ? (status.corpusKeepsAudio
                ? "Chaque dictée est archivée, audio compris\nCliquer pour arrêter"
                : "Chaque dictée est archivée (texte seul)\nCliquer pour arrêter")
            : "Collecte arrêtée\nCliquer pour archiver les dictées"

        resize()
    }

    /// Texte reconnu en direct. Ne redimensionne rien : la géométrie est figée,
    /// précisément pour que ceci puisse arriver vingt fois par seconde sans
    /// faire bouger la barre.
    ///
    /// La coupe est faite ici, sur la chaîne, plutôt que laissée à
    /// `.byTruncatingHead` : sur du texte replié, AppKit tronque la fin selon
    /// les cas, et on se retrouverait à lire le début de la dictée pendant que
    /// la suite se perd hors du cadre.
    func setPreviewText(_ text: String) {
        guard status.previewEnabled else { return }
        previewLabel.stringValue = text.count > Self.previewCharacters
            ? "… " + text.suffix(Self.previewCharacters)
            : text
        previewLabel.textColor = .secondaryLabelColor
    }

    /// Message sur l'aperçu lui-même — attente, téléchargement, indisponibilité
    /// — à la place du texte reconnu.
    func setPreviewNotice(_ message: String) {
        previewLabel.stringValue = message
        previewLabel.textColor = .tertiaryLabelColor
        adjustPreviewHeight()
    }

    /// Ne redimensionne qu'au changement de nombre de lignes — deux fois par
    /// dictée au plus, jamais à chaque mot reconnu.
    private func adjustPreviewHeight() {
        let lines = previewLines(for: previewLabel.stringValue)
        guard lines != previewLineCount else { return }
        previewLineCount = lines
        resize()
    }

    private static let previewExplanation =
        "Aperçu indicatif, par le moteur de macOS\n"
        + "Sans le lexique : le texte inséré différera\n"
        + "Cliquer pour l'activer ou le couper"

    /// Nom court : la largeur de la barre suit celle des contrôles, donc un
    /// nom de fichier long la ferait grossir d'autant. Le nom entier reste
    /// dans l'infobulle.
    private static func noteLabel(for status: Status) -> String {
        guard let name = status.noteName else { return "Notes…" }
        let short = name.count > 14 ? name.prefix(13) + "…" : name[...]
        return "Notes › \(short)"
    }

    /// Mode micro courant, tel que macOS le rapporte.
    ///
    /// Lecture seule : Apple ne laisse aucune application imposer ce réglage,
    /// c'est un choix de l'utilisateur. On peut en revanche ouvrir le panneau
    /// système, ce qui évite d'aller le chercher dans le Centre de contrôle.
    private static var microphoneModeLabel: String {
        switch AVCaptureDevice.activeMicrophoneMode {
        case .voiceIsolation: "Isolement"
        case .wideSpectrum: "Large"
        default: "Standard"
        }
    }

    // MARK: - Construction

    private static func buttonTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    /// Largeur dictée par les contrôles seuls — jamais par le texte reconnu —
    /// et jamais plus large que l'écran. Hauteur ajustée au nombre de lignes
    /// que l'aperçu occupe vraiment : réserver trois lignes en permanence
    /// laissait un vide sous le texte les trois quarts du temps.
    private func resize() {
        guard let panel else { return }
        let rows = [recordingRow?.fittingSize.width ?? 0,
                    textRow?.fittingSize.width ?? 0]
        let needed = (rows.max() ?? Self.minimumWidth) + 2 * Self.padding + 14
        let floor = status.previewEnabled ? Self.widthWithPreview : Self.minimumWidth
        let ceiling = (NSScreen.main?.visibleFrame.width ?? 1440) - 80
        let width = min(max(floor, needed), max(floor, ceiling))

        var height = Self.padding + Self.rowHeight + Self.rowSpacing
            + Self.controlRowHeight + Self.padding
        if status.previewEnabled {
            height += Self.rowSpacing + CGFloat(previewLineCount) * Self.previewLineHeight
        }
        previewHeight?.constant = CGFloat(previewLineCount) * Self.previewLineHeight
        panel.setContentSize(NSSize(width: width, height: height))
        position(panel)
    }

    /// Nombre de lignes qu'occupe le texte courant, plafonné.
    ///
    /// Mesuré plutôt que deviné : la police est italique et proportionnelle,
    /// donc le nombre de caractères ne dit rien de fiable sur le nombre de
    /// lignes.
    private func previewLines(for text: String) -> Int {
        guard !text.isEmpty, let font = previewLabel.font,
              let width = panel?.contentView?.bounds.width, width > 0 else { return 1 }
        let usable = width - 2 * (Self.padding + 5)
        let box = NSSize(width: usable, height: .greatestFiniteMagnitude)
        let measured = (text as NSString).boundingRect(
            with: box, options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]).height
        let lines = Int((measured / Self.previewLineHeight).rounded(.up))
        return max(1, min(Self.previewLines, lines))
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.minimumWidth, height: 78),
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
        blur.layer?.cornerRadius = 18
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        panel.contentView = blur

        buildIndicators()
        buildControls()

        let recording = makeRow([dot, timeLabel, meter, NSView(),
                                 micButton, corpusBadge, previewButton])
        let text = makeSpacedRow([modeControl, targetControl])
        recordingRow = recording
        textRow = text

        let stack = NSStackView(views: [recording, text, previewLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Self.rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        container = stack

        blur.addSubview(stack)
        blur.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor,
                                           constant: Self.padding + 5),
            stack.trailingAnchor.constraint(equalTo: blur.trailingAnchor,
                                            constant: -(Self.padding + 5)),
            stack.topAnchor.constraint(equalTo: blur.topAnchor, constant: Self.padding),

            recording.heightAnchor.constraint(equalToConstant: Self.rowHeight),
            recording.widthAnchor.constraint(equalTo: stack.widthAnchor),
            text.heightAnchor.constraint(equalToConstant: Self.controlRowHeight),
            text.widthAnchor.constraint(equalTo: stack.widthAnchor),
            previewLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),

            statusLabel.centerXAnchor.constraint(equalTo: blur.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
        ])
        let height = previewLabel.heightAnchor.constraint(
            equalToConstant: Self.previewLineHeight)
        height.isActive = true
        previewHeight = height
        return panel
    }

    /// Rangée centrée, espaces égaux autour de chaque élément.
    ///
    /// L'équivalent du `space-around` de flexbox, que `NSStackView` ne sait
    /// pas faire seul : ses distributions répartissent l'espace *entre* les
    /// vues, jamais aux extrémités. On intercale donc des entretoises dont on
    /// contraint les largeurs — les bords valent la moitié de l'intervalle
    /// central, ce qui est exactement la définition.
    private func makeSpacedRow(_ views: [NSView]) -> NSStackView {
        let spacers = (0...views.count).map { _ in NSView() }
        var arranged: [NSView] = []
        for (index, view) in views.enumerated() {
            arranged.append(spacers[index])
            arranged.append(view)
        }
        arranged.append(spacers[views.count])

        let row = makeRow(arranged)
        row.spacing = 0
        for spacer in spacers.dropFirst().dropLast() {
            spacer.widthAnchor.constraint(
                equalTo: spacers[0].widthAnchor, multiplier: 2).isActive = true
        }
        spacers[views.count].widthAnchor.constraint(
            equalTo: spacers[0].widthAnchor).isActive = true
        return row
    }

    private func makeRow(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        // La vue vide sert d'entretoise : elle seule doit s'étirer.
        for view in views where type(of: view) == NSView.self {
            view.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        }
        return row
    }

    private func buildIndicators() {
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        timeLabel.textColor = .labelColor
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor

        // Italique et discret : l'aperçu ne doit jamais être pris pour le
        // texte qui sera inséré.
        previewLabel.font = NSFontManager.shared.convert(
            .systemFont(ofSize: Self.previewFontSize), toHaveTrait: .italicFontMask)
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.lineBreakMode = .byTruncatingHead
        previewLabel.maximumNumberOfLines = Self.previewLines
        previewLabel.usesSingleLineMode = false
        previewLabel.cell?.wraps = true
        previewLabel.cell?.truncatesLastVisibleLine = true
        // Sans ça, le champ impose sa largeur naturelle au panneau : mesuré,
        // une fenêtre de 1164 px pour un écran de 1728, le texte sortant par
        // la droite. Un libellé doit céder, c'est le panneau qui commande.
        previewLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        previewLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        previewLabel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        previewLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            meter.widthAnchor.constraint(equalToConstant: 46),
            meter.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    private func buildControls() {
        for (button, action) in [(micButton, #selector(openMicrophoneModes)),
                                 (previewButton, #selector(togglePreview))] {
            button.isBordered = false
            button.bezelStyle = .inline
            button.target = self
            button.action = action
            // Réagit sans que Caret passe au premier plan.
            button.setButtonType(.momentaryChange)
        }
        previewButton.imagePosition = .imageOnly
        previewButton.symbolConfiguration = .init(pointSize: 12, weight: .medium)

        corpusBadge.title = "COLLECTE"
        corpusBadge.target = self
        corpusBadge.action = #selector(toggleCorpus)

        modeControl.onSelect = { [weak self] index in
            let modes = TranscriptionMode.allCases
            guard modes.indices.contains(index) else { return }
            self?.onSelectMode?(modes[index])
        }
        targetControl.onSelect = { [weak self] index in
            self?.onSelectTarget?(index == 1)
        }
    }

    /// Jette le panneau après un changement d'écrans, et le remonte aussitôt
    /// si une dictée est en cours — sinon la barre disparaîtrait en plein
    /// milieu d'une phrase.
    private func rebuildForNewScreens() {
        guard panel != nil else { return }
        let wasRecording = isRecording
        let elapsed = startedAt

        panel?.orderOut(nil)
        panel = nil
        container = nil
        recordingRow = nil
        textRow = nil
        NSLog("caret: écrans modifiés — panneau reconstruit")

        guard wasRecording else { return }
        showRecording(status)
        startedAt = elapsed          // le chrono ne repart pas de zéro
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

    @objc private func togglePreview() { onTogglePreview?() }
    @objc private func toggleCorpus() { onToggleCorpus?() }

    @objc private func openMicrophoneModes() {
        AVCaptureDevice.showSystemUserInterface(.microphoneModes)
    }
}

/// Pastille d'état, allumée ou éteinte.
///
/// Elle sert de rappel autant que d'interrupteur : la collecte écrit sur le
/// disque, et un réglage qu'on oublie d'avoir activé finit par accumuler des
/// gigaoctets d'audio sans qu'on s'en aperçoive.
private final class BadgeButton: NSButton {
    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 17).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("non utilisé") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setActive(_ active: Bool, color: NSColor) {
        layer?.backgroundColor = active
            ? color.withAlphaComponent(0.9).cgColor
            : NSColor.clear.cgColor
        layer?.borderWidth = active ? 0 : 1
        layer?.borderColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.5).cgColor

        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .bold),
            // L'espacement des lettres fait lire la pastille comme une
            // étiquette d'état plutôt que comme un mot de plus dans la barre.
            .kern: 0.8,
            .foregroundColor: active ? NSColor.white : NSColor.tertiaryLabelColor,
        ])
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 12
        return size
    }
}

/// Bouton qui répond au premier clic dans une fenêtre inactive.
///
/// Le panneau ne devient jamais clé — c'est ce qui garantit que le curseur ne
/// bouge pas. En contrepartie tout clic y est un « premier clic », que
/// `NSControl` ignore par défaut.
private final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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

        for index in 0..<barCount {
            let value = index < history.count ? history[history.count - 1 - index] : 0
            let height = max(3, CGFloat(value) * bounds.height)
            // Les barres récentes sont franches, les anciennes s'effacent :
            // le sens de défilement se lit sans y penser.
            let fade = 1 - CGFloat(index) / CGFloat(barCount) * 0.75
            context.setFillColor(NSColor.systemTeal.withAlphaComponent(fade).cgColor)
            let x = bounds.width - CGFloat(index + 1) * barWidth - CGFloat(index) * gap
            let rect = NSRect(x: x, y: (bounds.height - height) / 2,
                              width: barWidth, height: height)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 1.5,
                                   cornerHeight: 1.5, transform: nil))
            context.fillPath()
        }
    }
}
