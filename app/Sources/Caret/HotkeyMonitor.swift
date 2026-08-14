import AppKit
import Carbon.HIToolbox

/// Raccourci global, actif même quand Caret n'est pas au premier plan.
///
/// On passe par `RegisterEventHotKey` (Carbon) et non par un `CGEventTap` :
/// l'API Carbon ne demande **aucune permission**, là où un tap exige
/// l'Autorisation de saisie. Contrepartie : impossible d'écouter une touche
/// modificatrice seule — d'où un combo classique par défaut.
///
/// Contrainte macOS 15+ : un raccourci dont les seuls modificateurs sont
/// Option et/ou Majuscule est refusé (mesure anti-enregistreur de frappe).
/// `⌃⌥D` contient Contrôle, il passe.
final class HotkeyMonitor {
    struct Shortcut: Equatable {
        var keyCode: UInt32
        var modifiers: UInt32
        var label: String

        /// Défaut : ⌃⌥D — libre sur macOS, mnémonique « Dictate », et sans
        /// conflit avec AZERTY où Option sert à saisir @ # { } [ ] | \ ~.
        static let dictate = Shortcut(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: UInt32(controlKey | optionKey),
            label: "⌃⌥D"
        )
    }

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onTrigger: () -> Void
    private static let signature = OSType(0x43524554)  // 'CRET'

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    deinit {
        unregister()
    }

    func register(_ shortcut: Shortcut = .dictate) -> Bool {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData else { return noErr }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == HotkeyMonitor.signature else {
                return noErr
            }
            DispatchQueue.main.async { monitor.onTrigger() }
            return noErr
        }

        let installed = InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
        guard installed == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let registered = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        return registered == noErr
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}
