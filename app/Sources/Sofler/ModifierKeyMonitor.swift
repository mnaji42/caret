import AppKit
import Carbon.HIToolbox

/// Déclenche sur une touche modificatrice pressée seule — Option droite par
/// défaut.
///
/// `RegisterEventHotKey` ne sait pas écouter un modificateur isolé : il exige
/// une touche principale. Il faut donc un `CGEventTap`, qui demande
/// l'autorisation d'accessibilité — déjà nécessaire pour insérer le texte, donc
/// sans coût supplémentaire pour l'utilisateur.
///
/// Le point délicat est de ne pas confisquer la touche. Sur un clavier AZERTY,
/// Option sert à saisir `@ # { } [ ] | \ ~`, indispensables pour écrire du
/// code. On ne déclenche donc que si Option est pressée **et relâchée sans
/// qu'aucune autre touche ne soit intervenue** : `⌥` seul dicte, `⌥ + touche`
/// tape un caractère comme d'habitude.
///
/// Le tap est en écoute seule : les événements continuent leur chemin intact.
final class ModifierKeyMonitor {
    enum Side: String, CaseIterable, Hashable, Sendable {
        case right, left

        var keyCode: Int64 {
            switch self {
            case .right: Int64(kVK_RightOption)
            case .left: Int64(kVK_Option)
            }
        }

        var label: String {
            switch self {
            case .right: "⌥ droite"
            case .left: "⌥ gauche"
            }
        }
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let side: Side
    private let onTrigger: () -> Void
    /// Appelé quand Option a été maintenue seule assez longtemps.
    private let onHold: () -> Void

    /// Vrai entre l'appui et le relâchement d'Option.
    private var isDown = false
    /// Durée d'appui au-delà de laquelle on ouvre les réglages.
    ///
    /// L'ouverture a lieu **pendant** l'appui, pas au relâchement. C'est une
    /// différence d'usage, pas de mise en œuvre : sur un seuil détecté au
    /// relâchement, l'utilisateur doit deviner quand lâcher, et un geste dont
    /// on ne sait pas s'il a été compris n'en est pas un. Là, l'action se
    /// produit sous les doigts et le relâchement ne fait plus rien.
    ///
    /// Deux secondes parce que la dictée se déclenche, elle, au relâchement :
    /// quelqu'un qui presse Option puis hésite avant de parler tient la touche
    /// sans le vouloir, et un seuil court lui ouvrirait les réglages à la
    /// place de sa dictée.
    private let holdDuration: TimeInterval = 2.0

    /// Décompte armé à l'appui, désarmé au relâchement ou dès qu'une autre
    /// touche intervient.
    private var holdTimer: DispatchWorkItem?
    /// Vrai quand le décompte est allé au bout : le relâchement qui suit ne
    /// doit plus rien déclencher.
    private var didHold = false
    /// Passe à vrai si une autre touche est pressée pendant qu'Option est
    /// maintenue : le relâchement ne doit alors rien déclencher.
    private var usedAsModifier = false

    /// Instant du dernier déclenchement, pour absorber les rebonds.
    ///
    /// Précaution, pas correctif : aucun double déclenchement n'a été observé
    /// à l'usage. Mais un `CGEventTap` peut recevoir deux `flagsChanged` pour
    /// un seul relâchement — clavier externe, changement de disposition, tap
    /// réarmé au mauvais moment — et le coût est nul : deux appuis volontaires
    /// séparés de moins de 400 ms ne correspondent à aucune dictée réelle.
    private var lastTrigger = Date.distantPast
    private let debounce: TimeInterval = 0.4

    /// Arme le décompte : au bout du délai, les réglages s'ouvrent d'eux-mêmes.
    private func armHoldTimer() {
        cancelHoldTimer()
        let work = DispatchWorkItem { [weak self] in
            guard let self, isDown, !usedAsModifier else { return }
            didHold = true
            onHold()
        }
        holdTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration, execute: work)
    }

    private func cancelHoldTimer() {
        holdTimer?.cancel()
        holdTimer = nil
    }

    init(side: Side = .right,
         onTrigger: @escaping () -> Void,
         onHold: @escaping () -> Void = {}) {
        self.side = side
        self.onHold = onHold
        self.onTrigger = onTrigger
    }

    deinit {
        stop()
    }

    var hasPermission: Bool { AXIsProcessTrusted() }

    @discardableResult
    func start() -> Bool {
        stop()
        guard hasPermission else { return false }

        let mask = (1 << CGEventType.flagsChanged.rawValue)
                 | (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.leftMouseDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<ModifierKeyMonitor>
                .fromOpaque(userInfo).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        cancelHoldTimer()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            self.tap = nil
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            self.source = nil
        }
        isDown = false
        usedAsModifier = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .flagsChanged:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            guard code == side.keyCode else {
                // Un autre modificateur entre en jeu pendant qu'Option est
                // tenue (⌥⇧, ⌥⌘…) : c'est une combinaison, pas une dictée.
                if isDown {
                    usedAsModifier = true
                    cancelHoldTimer()
                }
                return
            }

            let pressed = event.flags.contains(.maskAlternate)
            if pressed {
                isDown = true
                usedAsModifier = false
                didHold = false
                armHoldTimer()
            } else if isDown {
                isDown = false
                cancelHoldTimer()
                // Le décompte est allé au bout : les réglages sont déjà
                // ouverts, ce relâchement ne doit pas lancer une dictée.
                guard !didHold else { return }
                guard !usedAsModifier else { return }
                let now = Date()
                guard now.timeIntervalSince(lastTrigger) > debounce else {
                    NSLog("sofler: rebond ignoré")
                    return
                }
                lastTrigger = now
                DispatchQueue.main.async { [weak self] in self?.onTrigger() }
            }

        case .keyDown, .leftMouseDown:
            // Option a servi à composer un caractère ou à cliquer : on annule.
            if isDown { usedAsModifier = true }

        default:
            break
        }
    }

    /// Un tap peut être désactivé par le système si le processus tarde trop à
    /// répondre. Le réarmer évite que la dictée cesse silencieusement.
    func reArmIfNeeded() {
        guard let tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("sofler: tap clavier réarmé")
    }
}
