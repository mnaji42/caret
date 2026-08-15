# Idées et décisions en attente

> Ce que les conversations font remonter et qui n'est pas encore fait. Tenu à
> jour au fil de l'eau : le projet se pilote en dictant, donc ce fichier est
> la mémoire de ce qui a été dit sans être codé.
>
> Les décisions **prises** vont dans le README ; ici, ce qui reste ouvert.

---

## Chantiers de fond

### J9 — porter l'inférence hors de Python

**C'est le déblocage principal.** Aujourd'hui CrisperWhisper demande Python,
torch et transformers : environ 1,2 Go de bibliothèques en plus des poids.
Conséquences directes :

- une installation depuis le .dmg ne peut **pas** faire tourner CrisperWhisper
  sans passer une fois par le Terminal ;
- un bouton « Télécharger CrisperWhisper » dans l'application serait un
  mensonge, puisqu'il devrait installer un environnement Python.

Porté en Core ML ou MLX, il ne resterait que des poids à récupérer — c'est-à-
dire un simple HTTPS, donc un vrai bouton. Le choix de modèle deviendrait
trivial, et le service résident pourrait disparaître.

### V2 — une couche de compréhension après la transcription

Voir [`v2-macos27.md`](v2-macos27.md) pour le plan complet.

**À corriger dans ce document :** il présente le test « transcription → modèle
de langage » comme restant à faire, alors que le README le documente déjà
comme un échec mesuré sur les Foundation Models de macOS 26 — le modèle
répondait à la phrase au lieu de la corriger, et transformait « chunk » en
« chanter ». Le pari de macOS 27 reste valable, mais il faut partir de ce
résultat et non le redécouvrir.

---

## Interface

### Captures d'écran dans l'accueil

Retenu sur le principe, une ou deux au maximum, sur la première page, et
**uniquement de la barre en cours de dictée** dans les deux destinations.
C'est la seule chose que les mots ne rendent pas : qu'on peut changer d'avis
en pleine phrase et que ça se voit. Des captures des réglages n'apprendraient
rien.

À fournir en @2x ; il faudra les mettre dans les ressources du bundle et
ajouter une ligne à `install.sh`.

### Modèles : proposer aussi les variantes `_pro` ?

Écartées pour l'instant. Elles sont meilleures — 96,0 de F1 de disfluence
contre 89,9 — mais leur licence est commerciale et l'accès est restreint.
Les afficher reviendrait à pointer une porte fermée. À revoir si le projet
prend un jour une licence.

---

## Distribution

### Notarisation

Le seul point qui ne se règle pas techniquement. Sans compte Apple Developer
(99 €/an), chaque personne doit passer une fois par Réglages Système ›
Confidentialité et sécurité. Le certificat auto-signé stable
(`scripts/make-signing-cert.sh`) règle un problème *différent* — la perte des
autorisations à chaque mise à jour — et ne dispense pas de celle-ci.

### Tap Homebrew

Le meilleur canal pour ce public : `brew install --cask …`, une commande, et
`brew upgrade` gère les mises à jour bien mieux que la vérification maison.
À faire une fois l'application stabilisée.

---

## Questions ouvertes

- **Faut-il montrer ce que la retouche a changé ?** Si une couche de langage
  arrive un jour, un aperçu « avant / après » consultable après coup rendrait
  une dérive de sens détectable au lieu d'invisible. C'est peut-être la seule
  réponse sérieuse au risque principal de la V2.
- **Le niveau de retouche doit-il dépendre de la destination ?** Écrire dans
  un fichier de notes et écrire dans un champ de code ne demandent pas la
  même liberté.
- **Que faire quand le service moteur est retiré mais le modèle gardé ?**
  L'application le détecte et le dit désormais, mais elle ne sait pas
  réinstaller le service si le dépôt a disparu. Le descripteur
  (`engine.json`) pointe vers un dossier qui peut avoir été effacé.
