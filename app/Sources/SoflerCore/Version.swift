import Foundation

/// Comparaison de numéros de version, sans dépendance système.
///
/// Ici plutôt qu'à côté du vérificateur de mises à jour, pour la raison qui a
/// fait naître ce module : c'est une règle pure, et c'est exactement le genre
/// de règle qui se casse sans bruit. Une comparaison fausse ne plante pas ;
/// elle propose indéfiniment une mise à jour déjà installée, ou n'en propose
/// jamais aucune — deux pannes qu'on ne découvre qu'en les subissant.
public enum Version {

    /// `candidate` est-il strictement postérieur à `current` ?
    ///
    /// Les composantes sont comparées comme des **nombres**, pas comme du
    /// texte. C'est tout l'intérêt de la fonction : l'ordre lexicographique
    /// place « 0.10.0 » *avant* « 0.9.0 », puisqu'il compare « 1 » à « 9 ».
    /// Le bug ne se manifesterait qu'à la dixième version mineure, donc bien
    /// après que le code ait cessé d'être suspect.
    ///
    /// Les longueurs inégales sont complétées par des zéros : « 1.2 » et
    /// « 1.2.0 » désignent la même version.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate)
        let b = components(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Découpe « v1.2.3 » en [1, 2, 3].
    ///
    /// Le « v » du tag git est toléré : les tags s'écrivent `v0.2.0` par
    /// convention, alors que CFBundleShortVersionString ne peut pas contenir
    /// de lettre. Les deux formes finissent ici et doivent se comparer.
    ///
    /// Tout ce qui n'est pas un nombre vaut zéro. Une pré-version comme
    /// « 1.2.0-beta1 » est donc lue « 1.2.0 » : Sofler ne publie pas de
    /// pré-versions, et les traiter à moitié serait pire que pas du tout.
    static func components(_ version: String) -> [Int] {
        let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return trimmed.split(separator: ".").map { Int($0) ?? 0 }
    }
}
