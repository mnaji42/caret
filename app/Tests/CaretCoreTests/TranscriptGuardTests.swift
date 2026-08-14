import Testing
@testable import CaretCore

@Suite("Garde-fou de relecture")
struct TranscriptGuardTests {

    @Test("Une correction de quelques mots est acceptée")
    func acceptsSmallFix() {
        let verdict = TranscriptGuard.review(
            original: "Je regarde le Tarot de map du projet.",
            rewritten: "Je regarde la roadmap du projet.")
        #expect(verdict == .accepted("Je regarde la roadmap du projet."))
    }

    @Test("Un texte inchangé passe")
    func acceptsIdentical() {
        let text = "Je vais modifier le component React."
        #expect(TranscriptGuard.review(original: text, rewritten: text)
                == .accepted(text))
    }

    @Test("Une réponse à la phrase est rejetée")
    func rejectsAnswering() {
        // Cas réel : le modèle a répondu au lieu de corriger.
        let verdict = TranscriptGuard.review(
            original: "dis-moi ce qu'il reste dans le Tarot de map",
            rewritten: """
            Le Tarot de map contient les informations suivantes :
            - Les objectifs du projet
            - Les fonctionnalités à développer
            """)
        if case .rejected = verdict {} else {
            Issue.record("aurait dû être rejeté : \(verdict)")
        }
    }

    @Test("Le formatage ajouté est rejeté")
    func rejectsFormatting() {
        let verdict = TranscriptGuard.review(
            original: "Je regarde la roadmap du projet.",
            rewritten: "Je regarde la **roadmap** du projet.")
        if case .rejected(let reason) = verdict {
            #expect(reason.contains("formatage"))
        } else {
            Issue.record("aurait dû être rejeté")
        }
    }

    @Test("Une reformulation complète est rejetée")
    func rejectsRewrite() {
        let verdict = TranscriptGuard.review(
            original: "Je vais modifier le component parce que le hook bugue.",
            rewritten: "Il faudrait revoir entièrement cette partie du code source.")
        if case .rejected = verdict {} else {
            Issue.record("aurait dû être rejeté")
        }
    }

    @Test("Une réponse vide est rejetée")
    func rejectsEmpty() {
        let verdict = TranscriptGuard.review(original: "Bonjour.", rewritten: "  ")
        if case .rejected = verdict {} else {
            Issue.record("aurait dû être rejeté")
        }
    }

    @Test("L'écart de mots est mesuré correctement")
    func measuresDrift() {
        #expect(TranscriptGuard.wordDrift("un deux trois", "un deux trois") == 0)
        #expect(TranscriptGuard.wordDrift("un deux trois", "un deux quatre") > 0.2)
        #expect(TranscriptGuard.wordDrift("un deux trois", "a b c") == 1)
    }
}
