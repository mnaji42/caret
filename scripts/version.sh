#!/usr/bin/env bash
# Source unique de la version, dérivée de git.
#
# La version était écrite en dur dans install.sh. Tant que rien n'était publié
# ça ne coûtait rien ; à partir du moment où l'app vérifie ses mises à jour en
# comparant sa propre version à celle de la dernière release, une constante
# oubliée dans un script se traduit par une app qui se croit à jour, ou qui
# réclame indéfiniment une mise à jour déjà installée. Le tag git est la seule
# chose qui soit vraie au même endroit pour l'app et pour la release.
#
# S'utilise en le sourçant :
#     . scripts/version.sh
# ce qui renseigne VERSION, BUILD, DESCRIBE et IS_RELEASE.

# --- VERSION : ce que l'utilisateur lit, et ce que compare la mise à jour ----
# Le dernier tag atteignable, sans son « v ». Pas `git describe` seul, qui y
# ajoute le nombre de commits et le hash : CFBundleShortVersionString doit
# rester des chiffres séparés par des points, sans quoi la comparaison de
# versions n'a plus de sens.
_tag="$(git describe --tags --abbrev=0 2>/dev/null || true)"
VERSION="${_tag#v}"
# Avant le premier tag il faut bien annoncer quelque chose. 0.0.0 plutôt que
# 0.1.0 : n'importe quelle release publiée lui sera supérieure, donc un build
# local d'avant le premier tag se saura périmé au lieu de se croire à jour.
VERSION="${VERSION:-0.0.0}"

# --- BUILD : distingue deux bundles de même version ------------------------
# Le nombre de commits, donc monotone. C'est ce qui sépare le build local fait
# trois commits après le tag du bundle de la release elle-même — même VERSION,
# BUILD différent.
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 0)"

# --- DESCRIBE : pour le diagnostic ------------------------------------------
# Affiché dans les Réglages sous la version. Quand quelqu'un signale un bug,
# « 0.2.0 » ne dit pas s'il a le bundle de la release ou un build maison ;
# « v0.2.0-3-gabc1234-dirty » le dit.
DESCRIBE="$(git describe --tags --always --dirty 2>/dev/null || echo inconnu)"

# --- IS_RELEASE : ce build est-il exactement un tag, arbre propre ? ---------
# Sert à ne pas harceler le développeur : une machine de dev est presque
# toujours en avance sur la dernière release, et lui proposer de « mettre à
# jour » vers du code plus ancien que le sien est absurde.
if [ -n "$_tag" ] \
   && [ "$(git rev-parse HEAD 2>/dev/null)" = "$(git rev-parse "$_tag^{commit}" 2>/dev/null)" ] \
   && [ -z "$(git status --porcelain 2>/dev/null)" ]; then
    IS_RELEASE=1
else
    IS_RELEASE=0
fi
unset _tag

# Exécuté directement plutôt que sourcé : afficher, pour inspection rapide.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "VERSION=$VERSION"
    echo "BUILD=$BUILD"
    echo "DESCRIBE=$DESCRIBE"
    echo "IS_RELEASE=$IS_RELEASE"
fi
