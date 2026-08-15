import Testing
@testable import SoflerCore

@Suite("Comparaison de versions")
struct VersionTests {

    @Test("Une version supérieure est détectée")
    func detectsNewer() {
        #expect(Version.isNewer("0.2.0", than: "0.1.0"))
        #expect(Version.isNewer("1.0.0", than: "0.9.9"))
        #expect(Version.isNewer("0.1.1", than: "0.1.0"))
    }

    @Test("Une version identique n'en est pas une nouvelle")
    func rejectsEqual() {
        #expect(!Version.isNewer("0.2.0", than: "0.2.0"))
    }

    @Test("Une version antérieure n'est jamais proposée")
    func rejectsOlder() {
        #expect(!Version.isNewer("0.1.0", than: "0.2.0"))
        #expect(!Version.isNewer("0.9.9", than: "1.0.0"))
    }

    /// Le piège pour lequel cette fonction existe : comparées comme du texte,
    /// « 0.10.0 » et « 0.9.0 » sont dans le mauvais ordre, parce que « 1 »
    /// précède « 9 ».
    @Test("La dixième version mineure dépasse la neuvième")
    func comparesNumericallyNotLexically() {
        #expect(Version.isNewer("0.10.0", than: "0.9.0"))
        #expect(!Version.isNewer("0.9.0", than: "0.10.0"))
        #expect(Version.isNewer("1.0.10", than: "1.0.9"))
    }

    @Test("Le « v » des tags git ne change rien")
    func toleratesTagPrefix() {
        #expect(Version.isNewer("v0.2.0", than: "0.1.0"))
        #expect(!Version.isNewer("v0.1.0", than: "0.1.0"))
    }

    @Test("Les longueurs inégales se complètent par des zéros")
    func padsMissingComponents() {
        #expect(!Version.isNewer("1.2", than: "1.2.0"))
        #expect(!Version.isNewer("1.2.0", than: "1.2"))
        #expect(Version.isNewer("1.2.1", than: "1.2"))
    }

    /// Un build local d'avant le premier tag s'annonce en 0.0.0 : il doit se
    /// savoir périmé dès qu'une release existe, sans quoi personne ne verrait
    /// jamais la première mise à jour.
    @Test("Un build sans tag est dépassé par n'importe quelle release")
    func untaggedBuildIsAlwaysBehind() {
        #expect(Version.isNewer("0.1.0", than: "0.0.0"))
    }
}
