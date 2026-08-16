import Testing
@testable import SoflerCore

/// Ce que le journal du service permet de conclure — et ce qu'il ne permet pas.
///
/// L'enjeu de chaque cas ci-dessous est le même : l'application doit dire
/// « patientez » ou « c'est cassé », et les deux erreurs coûtent cher. Annoncer
/// une panne pendant un chargement normal envoie chercher un problème qui
/// n'existe pas ; annoncer un chargement sur un service mort laisse attendre
/// indéfiniment.
@Suite("Journal du moteur")
struct EngineLogTests {

    /// La vraie trace, celle qui a motivé tout ceci : Metal absent en machine
    /// virtuelle, `.to("mps")` qui lève, le service qui meurt avant d'ouvrir
    /// son socket.
    @Test("Une trace après le démarrage est une panne")
    func fatalAfterStart() {
        let log = """
        10:02:14  chargement de nyralabs/CrisperWhisper2.0_turbo sur mps …
        Traceback (most recent call last):
          File "/Users/x/engine/sofler_engine/server.py", line 161, in main
            engine.load()
          File "/Users/x/engine/sofler_engine/crisper.py", line 217, in load
            .to(self.device)
        RuntimeError: PyTorch is not linked with support for mps devices
        """
        #expect(EngineLog.fatalError(in: log)
                == "RuntimeError: PyTorch is not linked with support for mps devices")
    }

    /// Le cas de loin le plus fréquent : le service lit ses poids, il n'a rien
    /// produit d'autre, et il ne faut surtout pas parler de panne.
    @Test("Un chargement en cours n'est pas une panne")
    func loadingIsNotAFailure() {
        let log = """
        10:02:14  chargement de nyralabs/CrisperWhisper2.0_turbo sur mps …
        """
        #expect(EngineLog.fatalError(in: log) == nil)
    }

    /// Le journal est en ajout seul : la panne d'avant-hier y figure encore
    /// après qu'on l'a réparée. La ressortir enverrait chercher un problème
    /// qui n'existe plus.
    @Test("Une panne antérieure au dernier démarrage est oubliée")
    func staleFailureIgnored() {
        let log = """
        09:00:00  chargement de nyralabs/CrisperWhisper2.0_turbo sur mps …
        Traceback (most recent call last):
          File "server.py", line 161, in main
        RuntimeError: PyTorch is not linked with support for mps devices
        10:02:14  chargement de nyralabs/CrisperWhisper2.0_turbo sur cpu …
        """
        #expect(EngineLog.fatalError(in: log) == nil)
    }

    /// Un service qui a démarré, servi, puis été arrêté proprement n'a pas
    /// échoué — même si son journal contient des lignes à deux-points.
    @Test("Un arrêt normal n'est pas une panne")
    func cleanShutdown() {
        let log = """
        10:02:14  chargement de nyralabs/CrisperWhisper2.0_turbo sur mps …
        10:02:22  modèle nyralabs/CrisperWhisper2.0_turbo chargé en 8.1s sur mps
        10:45:03  arrêté
        """
        #expect(EngineLog.fatalError(in: log) == nil)
    }

    /// Journal absent ou vide : aucune conclusion. On retombe sur le conseil
    /// par défaut plutôt que d'inventer une panne.
    @Test("Un journal sans démarrage ne conclut rien")
    func emptyLog() {
        #expect(EngineLog.fatalError(in: "") == nil)
        #expect(EngineLog.fatalError(in: "Traceback (most recent call last):") == nil)
    }

    /// La ligne retenue est celle de l'exception, pas la dernière ligne de
    /// pile — celles-ci sont indentées, et illisibles pour qui n'a pas écrit
    /// le service.
    @Test("On retient l'exception, pas la pile")
    func picksTheExceptionLine() {
        let log = """
        10:02:14  chargement de turbo sur mps …
        Traceback (most recent call last):
          File "crisper.py", line 217, in load
            .to(self.device)
        OSError: [Errno 28] No space left on device
        """
        #expect(EngineLog.fatalError(in: log)
                == "OSError: [Errno 28] No space left on device")
    }
}
