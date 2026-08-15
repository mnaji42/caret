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
    /// Instant de l'appui, pour distinguer une pression d'un maintien.
    private var pressedAt = Date.distantPast

    /// Au-delà, le relâchement n'est plus lu comme « dicter » mais comme
    /// « ouvre les réglages ».
    ///
    /// Deux secondes, parce que le déclenchement a lieu au **relâchement** :
    /// quelqu'un qui presse Option puis hésite avant de parler tiendrait la
    /// touche sans le vouloir, et un seuil court lui ouvrirait les réglages à
    /// la place de sa dictée. Maintenir un modificateur deux secondes sans
    /// appuyer sur rien d'autre, en revanche, n'arrive pas par accident.
    private let holdDuration: TimeInterval = 2.0
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
                if isDown { usedAsModifier = true }
                return
            }

            let pressed = event.flags.contains(.maskAlternate)
            if pressed {
                isDown = true
                usedAsModifier = false
                pressedAt = Date()
            } else if isDown {
                isDown = false
                guard !usedAsModifier else { return }
                let now = Date()
                guard now.timeIntervalSince(lastTrigger) > debounce else {
                    NSLog("sofler: rebond ignoré")
                    return
                }
                lastTrigger = now
                // Maintenue seule : c'est une demande d'ouvrir les réglages,
                // pas de dicter. Rien n'a démarré entre-temps, puisque le
                // déclenchement n'a lieu qu'ici, au relâchement.
                let held = now.timeIntervalSince(pressedAt) >= holdDuration
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    held ? onHold() : onTrigger()
                }
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
