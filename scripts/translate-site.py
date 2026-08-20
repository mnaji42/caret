#!/usr/bin/env python3
"""Fabrique en.html à partir de index.html.

Une seule source : la page française. Toute chaîne visible non traduite ici
ressort dans le contrôle final, ce qui empêche les deux pages de diverger.
"""
import pathlib, re, sys

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
src = (ROOT / "index.html").read_text(encoding="utf-8")

PAIRS = [
# ---- tête ------------------------------------------------------------------
('<html lang="fr">', '<html lang="en">'),
("<title>Caspr — dictée vocale locale et hors-ligne pour macOS</title>",
 "<title>Caspr — local, offline dictation for macOS</title>"),
("Caspr transcrit votre voix sur votre Mac, sans cloud ni compte. Il écrit les mots de votre métier — franglais, acronymes, noms propres — sans essayer de les traduire.",
 "Caspr turns speech into text on your own Mac, with no cloud and no account. It cleans up the way people actually talk, and writes the words of your trade without translating them."),
('<link rel="canonical" href="https://caspr.lyriastudio.fr/">',
 '<link rel="canonical" href="https://caspr.lyriastudio.fr/en.html">'),
('<meta property="og:locale" content="fr_FR">', '<meta property="og:locale" content="en_US">'),
('<meta property="og:locale:alternate" content="en_US">', '<meta property="og:locale:alternate" content="fr_FR">'),
('<meta property="og:url" content="https://caspr.lyriastudio.fr/">',
 '<meta property="og:url" content="https://caspr.lyriastudio.fr/en.html">'),
("Caspr — dictée vocale locale et hors-ligne pour macOS", "Caspr — local, offline dictation for macOS"),
("Parlez naturellement. Caspr écrit les mots de votre métier sans les traduire. Tout tourne sur votre Mac : pas de cloud, pas de compte, pas de télémétrie.",
 "Speak naturally. Caspr writes at the speed of your thoughts, and never leaves your Mac: no cloud, no account, no telemetry."),
("Parlez naturellement. Caspr écrit les mots de votre métier sans les traduire.",
 "Speak naturally. Caspr writes at the speed of your thoughts."),
("https://caspr.lyriastudio.fr/images/og-preview.png", "https://caspr.lyriastudio.fr/images/og-preview-en.png"),
("Caspr — dictée vocale locale pour macOS", "Caspr — local dictation for macOS"),
('"inLanguage": "fr-FR"', '"inLanguage": "en"'),
('"@id": "https://caspr.lyriastudio.fr/#site"', '"@id": "https://caspr.lyriastudio.fr/#site-en"'),
('"@id": "https://caspr.lyriastudio.fr/#faq"', '"@id": "https://caspr.lyriastudio.fr/en.html#faq"'),
('"url": "https://caspr.lyriastudio.fr/",\n      "name": "Caspr"',
 '"url": "https://caspr.lyriastudio.fr/en.html",\n      "name": "Caspr"'),
('"operatingSystem": "macOS 14 ou plus récent"', '"operatingSystem": "macOS 14 or later"'),
("Application de dictée vocale locale pour macOS, conçue pour la parole mêlant plusieurs langues et le vocabulaire de métier. La transcription s'exécute sur la machine, sans service distant.",
 "Local dictation app for macOS: it removes the hesitations of real speech and keeps the vocabulary of your trade. Transcription runs on the machine, with no remote service."),
("Transcription entièrement locale, sans connexion réseau", "Fully local transcription, no network connection required"),
("Lexique personnel pour le vocabulaire de métier", "A personal lexicon for the vocabulary of your trade"),
("Parole mêlant français et anglais dans une même phrase", "Speech mixing two languages within a single sentence"),
("Insertion du texte au curseur de l'application active", "Text inserted at the caret of the active app"),
("Accumulation des dictées dans un fichier Markdown daté", "Dictations appended to a dated Markdown file"),
("Moteurs de macOS ou CrisperWhisper, au choix", "The macOS engines or CrisperWhisper, your choice"),
('"name": "De quel Mac ai-je besoin ?"', '"name": "Which Mac do I need?"'),
("Caspr demande macOS 14 ou plus récent. Avec les moteurs de macOS, il fonctionne sur toute machine où la dictée du système fonctionne, Mac Intel compris : la Dictée existe depuis macOS 10.15, et Apple Intelligence s'y ajoute à partir de macOS 26 sur les Mac qui en disposent. Seul CrisperWhisper impose une puce Apple Silicon, avec environ 1,6 Go de poids à télécharger et 3 Go de mémoire résidente.",
 "Caspr needs macOS 14 or later. With the macOS engines it runs on any machine where system dictation works, Intel Macs included: Dictation has existed since macOS 10.15, and Apple Intelligence adds to it from macOS 26 on the Macs that support it. Only CrisperWhisper requires an Apple Silicon chip, with about 1.6 GB of weights to download and 3 GB resident in memory."),
('"name": "Ma voix ou mes textes partent-ils sur un serveur ?"', '"name": "Does my voice or text leave my machine?"'),
("Non. La transcription s'exécute sur votre machine, avec tous les moteurs. Il n'y a ni compte, ni serveur, ni télémétrie. Coupez le Wi-Fi et Caspr fonctionne à l'identique. La seule requête réseau que fait l'application est la vérification des mises à jour sur GitHub, et elle se désactive dans les réglages.",
 "No. Transcription runs on your machine with every engine. There is no account, no server and no telemetry. Turn off Wi-Fi and Caspr behaves identically. The only network request the app makes is the update check against GitHub, and it can be switched off in settings."),
('"name": "Pourquoi macOS refuse-t-il d\'ouvrir l\'application la première fois ?"',
 '"name": "Why does macOS refuse to open the app the first time?"'),
("Parce que l'application n'est pas notariée par Apple, ce qui suppose un compte développeur payant. Caspr est signé de façon ad hoc. macOS affiche donc un avertissement au premier lancement, et l'autorisation se donne une fois dans Réglages Système, rubrique Confidentialité et sécurité. Le guide d'installation détaille chaque étape.",
 "Because the app is not notarised by Apple, which requires a paid developer account. Caspr is ad-hoc signed, so macOS warns on first launch. You grant permission once in System Settings, under Privacy & Security. The install guide walks through every step."),
('"name": "Caspr comprend-il le vocabulaire de mon métier ?"', '"name": "Does Caspr understand the vocabulary of my trade?"'),
("C'est la raison d'être du projet. CrisperWhisper accepte un lexique qui oriente le décodage vers les termes que vous lui donnez, quel que soit le domaine. Mesuré sur de la parole réelle mêlant français et anglais, 32 termes techniques sur 34 sont préservés avec lexique, contre 29 sur 34 sans, et sans régression sur les phrases en français simple.",
 "That is the reason the project exists. CrisperWhisper accepts a lexicon that biases decoding toward the terms you supply, whatever the field. Measured on real speech mixing French and English, 32 of 34 technical terms survive with a lexicon, against 29 of 34 without, and with no regression on plain sentences."),
('"name": "Quelle est la licence de Caspr ?"', '"name": "What is the licence?"'),
("Le code de Caspr est sous licence MIT, tout comme le code d'inférence de CrisperWhisper. Les poids du modèle CrisperWhisper 2.0 relèvent en revanche d'une licence de recherche non commerciale de Nyra Health. Caspr n'embarque donc pas ces poids et ne les télécharge jamais en silence : la licence est présentée avant tout téléchargement, et le choix vous revient.",
 "Caspr's own code is MIT, as is CrisperWhisper's inference code. The CrisperWhisper 2.0 model weights are not: they fall under a Nyra Health non-commercial research licence. Caspr therefore does not bundle those weights and never downloads them silently: the licence is shown before any download, and the choice is yours."),
('"name": "Puis-je désinstaller proprement ?"', '"name": "Can I uninstall cleanly?"'),
("Oui. L'application inclut un désinstallateur qui retire l'environnement Python, les poids du modèle, les caches et les préférences. Il ne propose de supprimer que ce qui est effectivement installé.",
 "Yes. The app ships an uninstaller that removes the Python environment, the model weights, the caches and the preferences. It only offers to remove what is actually installed."),
# ---- chrome ----------------------------------------------------------------
("Passer au contenu", "Skip to content"),
('href="/" aria-label="Caspr, retour à l\'accueil"', 'href="en.html" aria-label="Caspr, back to home"'),
('aria-label="Sections du site"', 'aria-label="Site sections"'),
('href="#dictee">La dictée</a>', 'href="#dictation">Dictation</a>'),
('href="#vocabulaire">Le vocabulaire</a>', 'href="#vocabulary">Vocabulary</a>'),
('href="#barre">La barre</a>', 'href="#bar">The bar</a>'),
('href="#notes">Les notes</a>', 'href="#notes">Notes</a>'),
('href="#moteurs">Les moteurs</a>', 'href="#engines">Engines</a>'),
('href="#mesures">Les mesures</a>', 'href="#numbers">Measurements</a>'),
('<a href="/" aria-current="true" lang="fr">FR</a>\n        <a href="en.html" hreflang="en" lang="en">EN</a>',
 '<a href="/" hreflang="fr" lang="fr">FR</a>\n        <a href="en.html" aria-current="true" lang="en">EN</a>'),
("Voir Caspr sur ", "View Caspr on "),
(">\n        Télécharger\n      </button>", ">\n        Download\n      </button>"),
# ---- hero ------------------------------------------------------------------
("Parlez naturellement.\n          <span class=\"hero-sub\">Caspr écrit",
 "Speak naturally.\n          <span class=\"hero-sub\">Caspr writes"),
(">votre franglais sans traduire</span>", ">at the speed of your thoughts</span>"),
("""          Une dictée pour macOS qui retire vos hésitations et garde vos mots —
          ceux du métier, ceux qu'on emprunte à l'anglais. Rapide, gratuite,
          open source, et entièrement sur votre Mac : pas de cloud, pas de compte,
          pas de télémétrie.""",
 """          A dictation app for macOS that takes out your hesitations and keeps your
          words — the ones from your trade, the ones borrowed from another language.
          Fast, free, open source, and entirely on your Mac: no cloud, no account,
          no telemetry."""),
("Télécharger pour macOS", "Download for macOS"),
("Lire le code source", "Read the source"),
("Gratuit, sous licence MIT, sur GitHub.", "Free, MIT licensed, on GitHub."),
("macOS 14 ou plus récent, Mac Intel compris", "macOS 14 or later, Intel Macs included"),
("Détail par moteur", "Requirements by engine"),
# ---- scène -----------------------------------------------------------------
("compte-rendu.md", "meeting-notes.md"),
("# Comité du 20 août", "# Board meeting, 20 August"),
("- le budget tient, la roadmap glisse d'un mois", "- budget holds, the roadmap slips by a month"),
('- valider le <span class="term term--ok">churn</span> avant le prochain <span class="term term--ok">board</span>',
 '- confirm the <span class="term term--ok">churn</span> before the next <span class="term term--ok">board</span>'),
('aria-label="La barre de Caspr pendant un enregistrement : minuteur à 42 secondes, micro en mode standard, collecte éteinte, l\'aperçu de ce qui est entendu, et sous la carte le français sélectionné à gauche, le curseur comme destination à droite."',
 'aria-label="The Caspr bar during a recording: timer at 42 seconds, microphone in standard mode, collection off, a preview of what is being heard, and below the card French selected on the left and the caret as destination on the right."'),
(">Collecte</span>", ">Collecting</span>"),
("valider le churn avant le prochain bord", "confirm the churn before the next bored"),
(">Curseur</span>", ">Caret</span>"),
("L'aperçu de la barre vient du moteur de macOS, pas de CrisperWhisper : il n'a pas votre lexique, d'où le «&nbsp;bord&nbsp;» à la place de <span class=\"term term--ok\">board</span>. Il répond à «&nbsp;le micro m'entend-il&nbsp;», pas à «&nbsp;la transcription sera-t-elle juste&nbsp;».",
 "The bar's preview comes from the macOS engine, not from CrisperWhisper: it has no lexicon, hence “bored” where the inserted text will write <span class=\"term term--ok\">board</span>. It answers “is the mic hearing me”, not “will the transcription be right”."),
# ---- atouts ----------------------------------------------------------------
("<b>100 % local</b> — rien ne sort de votre Mac", "<b>100% local</b> — nothing leaves your Mac"),
("<b>425 ms</b> pour 13 secondes de parole", "<b>425 ms</b> for 13 seconds of speech"),
("<b>Open source</b> — code sous licence MIT", "<b>Open source</b> — MIT licensed code"),
("<b>Sans compte</b> ni abonnement", "<b>No account</b>, no subscription"),
# ---- avant / après ---------------------------------------------------------
('id="dictee" aria-labelledby="dictee-titre"', 'id="dictation" aria-labelledby="dictation-title"'),
('<h2 id="dictee-titre">Vous ne parlez pas comme vous écrivez</h2>',
 '<h2 id="dictation-title">You don\'t speak the way you write</h2>'),
("""          On hésite, on se reprend, on repart en arrière. Une dictée classique
          écrit tout, «&nbsp;euh&nbsp;» compris, et vous relisez pour nettoyer.
          Caspr rend ce que vous vouliez dire.""",
 """          We hesitate, we backtrack, we start the sentence again. Ordinary
          dictation writes all of it down, every “er” included, and then you reread
          it to clean it up. Caspr writes what you meant."""),
("Une dictée classique", "Ordinary dictation"),
("""            «&nbsp;Alors <span class="filler">euh</span> attends, on va
            <span class="filler">on va</span> décaler la réunion à jeudi
            <span class="filler">enfin non</span> vendredi matin
            <span class="filler">euh</span> et prévenir Sarah&nbsp;»""",
 """            “So <span class="filler">er</span> hang on, we'll
            <span class="filler">we'll</span> push the meeting to Thursday
            <span class="filler">no wait</span> Friday morning
            <span class="filler">er</span> and let Sarah know”"""),
("""            Vous relisez, vous coupez, vous ponctuez. Le temps gagné à la dictée
            se reperd à la correction.""",
 """            You reread it, you cut, you punctuate. The time dictation saved goes
            straight back into fixing it."""),
("Avec Caspr", "With Caspr"),
("«&nbsp;On va décaler la réunion à vendredi matin, et prévenir Sarah.&nbsp;»",
 "“We'll push the meeting to Friday morning, and let Sarah know.”"),
("""            Les hésitations, les reprises et les faux départs sont retirés ; la
            ponctuation et les majuscules sont déduites du sens.""",
 """            Hesitations, restarts and false starts are removed; punctuation and
            capitals are inferred from the meaning."""),
("""        Le mode «&nbsp;texte nettoyé&nbsp;» vient de CrisperWhisper, et il est celui par
        défaut. Le mode «&nbsp;mot à mot&nbsp;» écrit à l'inverse exactement ce qui a été
        dit, hésitations comprises — utile en entretien. Les moteurs de macOS, eux,
        rendent un seul texte, sans passe de nettoyage.""",
 """        The “clean text” mode comes from CrisperWhisper, and it is the default.
        “Word for word” does the opposite and writes exactly what was said,
        hesitations included — useful for interviews. The macOS engines return a
        single text, with no cleanup pass."""),
# ---- vocabulaire -----------------------------------------------------------
('id="vocabulaire" aria-labelledby="vocabulaire-titre"', 'id="vocabulary" aria-labelledby="vocabulary-title"'),
('<h2 id="vocabulaire-titre">Et les mots que les autres écorchent</h2>',
 '<h2 id="vocabulary-title">And the words other engines mangle</h2>'),
("""          Beaucoup de métiers empruntent leur vocabulaire à l'anglais. Un trader dit
          «&nbsp;le <i lang="en">spread</i> s'est écarté sur le <i lang="en">forward</i>&nbsp;»,
          une chercheuse «&nbsp;le <i lang="en">peer review</i> a retoqué le protocole&nbsp;»,
          un développeur «&nbsp;les <i lang="en">dependencies</i> dans le
          <i lang="en">useEffect</i>&nbsp;». Les modèles de reconnaissance vocale
          imposent une langue par segment : en mode français, ces mots sont absorbés
          phonétiquement.""",
 """          Plenty of trades borrow their vocabulary from another language. A French
          trader says “le <i lang="fr">spread</i> s'est écarté sur le forward”, a
          researcher “le peer review a retoqué le protocole”, a developer “les
          dependencies dans le useEffect”. Speech models force one language per
          segment, so in French mode those words get absorbed phonetically."""),
("Comparaison de la transcription de trois termes techniques par les modèles de la famille Whisper en mode français et par Caspr",
 "How three technical terms are transcribed by Whisper-family models in French mode and by Caspr"),
("Ce que vous dites", "What you say"),
("Reconnaissance vocale, mode français", "Speech recognition, French mode"),
("Caspr, avec lexique", "Caspr, with a lexicon"),
("<span>Mesuré sur de la parole réelle, français et anglais mêlés :</span>",
 "<span>Measured on real speech mixing French and English:</span>"),
("<b>32 termes sur 34</b> préservés avec lexique", "<b>32 of 34 terms</b> preserved with a lexicon"),
("contre <b>29 sur 34</b> sans", "against <b>29 of 34</b> without"),
("— et aucune régression sur les phrases en français simple.", "— and no regression on plain sentences."),
("""        Le mécanisme s'appelle le conditionnement par lexique : le moteur accepte une
        liste de termes qui oriente le décodage. Le vôtre s'écrit dans les réglages —
        noms de clients, molécules, tickers, jargon de la maison — et la transcription
        cesse de les traduire. Les trois exemples ci-dessus viennent du corpus de test ;
        le mécanisme, lui, ne connaît aucun domaine en particulier.""",
 """        The mechanism is called vocabulary conditioning: the engine accepts a list of
        terms that biases decoding. Yours goes into settings — client names, molecules,
        tickers, in-house jargon — and the transcription stops translating them. The three
        examples above come from the test corpus; the mechanism itself knows no particular
        field."""),
]

PAIRS += [
# ---- la barre --------------------------------------------------------------
('id="barre" aria-labelledby="barre-titre"', 'id="bar" aria-labelledby="bar-title"'),
('<h2 id="barre-titre">Vous changez d\'avis en cours de phrase. La barre suit.</h2>',
 '<h2 id="bar-title">You change your mind mid-sentence. The bar keeps up.</h2>'),
("""          Dicter n'est pas une commande qu'on lance et qu'on subit. On réalise au
          milieu d'une phrase que le texte ne doit pas aller là où il va. Une barre
          flotte au bas de l'écran pendant que vous parlez, et tout ce qu'elle
          porte se change sans vous interrompre.""",
 """          Dictation is not a command you fire and endure. Halfway through a sentence you
          realise the text should not go where it is going. A bar floats at the bottom of
          the screen while you talk, and everything on it can change without
          interrupting you."""),
('<span class="control-name">Le mode</span>', '<span class="control-name">Mode</span>'),
("<dd>Texte nettoyé, ou mot à mot. Le premier retire les hésitations et les faux départs, le second écrit exactement ce qui a été dit.</dd>",
 "<dd>Clean text, or word for word. The first removes hesitations and false starts, the second writes exactly what was said.</dd>"),
('<span class="control-name">La destination</span>', '<span class="control-name">Destination</span>'),
("<dd>Le curseur de l'application où vous êtes, ou un fichier. Le fichier de notes est mémorisé à part : l'aller-retour coûte un clic.</dd>",
 "<dd>The caret of whatever app you are in, or a file. The note file is remembered separately: the round trip costs one click.</dd>"),
('<span class="control-name">L\'aperçu en direct</span>', '<span class="control-name">Live preview</span>'),
("<dd>Ce qui est entendu, pendant que vous le dites. Il répond à «&nbsp;le micro m'entend-il&nbsp;», pas à «&nbsp;le texte sera-t-il juste&nbsp;».</dd>",
 "<dd>What is being heard, as you say it. It answers “is the mic hearing me”, not “will the text be right”.</dd>"),
('<span class="control-name">La collecte</span>', '<span class="control-name">Collection</span>'),
("<dd>Désactivée par défaut. Une fois active, elle archive les dictées sur votre disque pour mesurer les moteurs — et rien ne quitte la machine.</dd>",
 "<dd>Off by default. Once enabled it archives dictations on your disk so engines can be measured — and nothing leaves the machine.</dd>"),
("""          Le mode et la destination sont lus <strong>à la fin de l'enregistrement</strong>,
          jamais au début. Appuyer sur <strong>Notes</strong> au milieu d'une phrase envoie
          cette dictée-là dans le fichier, et l'inverse fonctionne aussi. C'est ce qui rend
          la barre utile plutôt que décorative — et elle ne prend jamais le focus, pour que
          le texte atterrisse là où votre curseur se trouve déjà.""",
 """          Mode and destination are read <strong>when the recording ends</strong>, never when
          it starts. Pressing <strong>Notes</strong> halfway through a sentence sends that
          dictation to the file, and the reverse works too. That is what makes the bar
          useful rather than decorative — and it never takes focus, so the text lands where
          your caret already is."""),
# ---- notes -----------------------------------------------------------------
('aria-labelledby="notes-titre"', 'aria-labelledby="notes-title"'),
('<h2 id="notes-titre">Parlez maintenant, triez plus tard</h2>', '<h2 id="notes-title">Speak now, sort it out later</h2>'),
("""          Toutes les phrases n'ont pas de destination au moment où elles vous viennent.
          Basculez sur <strong>Notes</strong> : le texte part dans un fichier Markdown daté
          au lieu du curseur, sans ouvrir d'application ni quitter ce que vous faisiez.
          La journée s'accumule, et vous la relisez quand c'est le moment.""",
 """          Not every sentence has a destination the moment it occurs to you. Switch to
          <strong>Notes</strong> and the text goes to a dated Markdown file instead of the
          caret — no app to open, nothing to leave behind. The day accumulates, and you
          read it back when the time comes."""),
("Rappeler à Sarah que le dossier attend sa relecture.", "Remind Sarah the file is waiting on her review."),
("Le churn remonte sur la cohorte de mars, creuser avant vendredi.", "Churn is up on the March cohort, dig in before Friday."),
("Idée : reprendre le protocole après le changement de seuil.", "Idea: revisit the protocol after the threshold change."),
("Vérifier le spread sur les échéances longues.", "Check the spread on the long maturities."),
("""        Le fichier reste un fichier texte, sur votre disque, lisible par n'importe quel
        éditeur. Rien à exporter le jour où vous changez d'outil.""",
 """        The file stays a text file, on your disk, readable by any editor. Nothing to
        export the day you change tools."""),
# ---- moteurs ---------------------------------------------------------------
('id="moteurs" aria-labelledby="moteurs-titre"', 'id="engines" aria-labelledby="engines-title"'),
('<h2 id="moteurs-titre">Le choix tient en une question</h2>', '<h2 id="engines-title">The choice comes down to one question</h2>'),
("""          macOS, ou CrisperWhisper. Le premier est déjà là et ne demande rien.
          Le second connaît votre lexique, mais il a des exigences.""",
 """          macOS, or CrisperWhisper. The first is already there and asks for nothing.
          The second knows your lexicon, but it has requirements."""),
("Prérequis comparés des moteurs de macOS et du moteur CrisperWhisper", "Requirements compared for the macOS engines and the CrisperWhisper engine"),
('<span class="sr-only">Critère</span>', '<span class="sr-only">Criterion</span>'),
('<span class="col-note">La reconnaissance vocale du système</span>', '<span class="col-note">The system\'s speech recognition</span>'),
('<span class="col-note">Le moteur qui connaît votre lexique</span>', '<span class="col-note">The engine that knows your lexicon</span>'),
('<th scope="row">Version de macOS</th>', '<th scope="row">macOS version</th>'),
('<td data-col="macOS"><strong>14</strong> ou plus récent, comme l\'application</td>', '<td data-col="macOS"><strong>14</strong> or later, same as the app</td>'),
('<td data-col="CrisperWhisper"><strong>14</strong> ou plus récent</td>', '<td data-col="CrisperWhisper"><strong>14</strong> or later</td>'),
('<td data-col="macOS">Toute machine où la dictée du système fonctionne — <strong>Mac Intel compris</strong></td>',
 '<td data-col="macOS">Any machine where system dictation works — <strong>Intel Macs included</strong></td>'),
('<td data-col="CrisperWhisper"><strong>Apple Silicon</strong> (M1 et au-delà)</td>', '<td data-col="CrisperWhisper"><strong>Apple Silicon</strong> (M1 and up)</td>'),
('<th scope="row">À télécharger</th>', '<th scope="row">To download</th>'),
('<td data-col="macOS">Rien, ou les modèles de langue depuis les Réglages Système</td>', '<td data-col="macOS">Nothing, or the language models from System Settings</td>'),
('<td data-col="CrisperWhisper">Environ <strong>1,6 Go</strong> de poids</td>', '<td data-col="CrisperWhisper">About <strong>1.6 GB</strong> of weights</td>'),
('<th scope="row">Mémoire</th>', '<th scope="row">Memory</th>'),
('<td data-col="macOS">Négligeable</td>', '<td data-col="macOS">Negligible</td>'),
('<td data-col="CrisperWhisper">Environ <strong>3 Go</strong> résidents</td>', '<td data-col="CrisperWhisper">About <strong>3 GB</strong> resident</td>'),
('<th scope="row">Installation</th>', '<th scope="row">Setup</th>'),
('<td data-col="macOS">Aucune, c\'est le réglage par défaut</td>', '<td data-col="macOS">None, it is the default</td>'),
('<td data-col="CrisperWhisper">Un script, depuis l\'application</td>', '<td data-col="CrisperWhisper">One script, from the app</td>'),
('<th scope="row">Vocabulaire de métier</th>', '<th scope="row">Trade vocabulary</th>'),
('<td data-col="macOS">Non — il écrira «&nbsp;use effect&nbsp;»</td>', '<td data-col="macOS">No — it will write “use effect”</td>'),
('<td data-col="CrisperWhisper"><strong>Oui</strong>, par conditionnement du décodage</td>', '<td data-col="CrisperWhisper"><strong>Yes</strong>, by conditioning the decoder</td>'),
('<td data-col="macOS">Un seul rendu</td>', '<td data-col="macOS">A single rendering</td>'),
('<td data-col="CrisperWhisper">Texte nettoyé, ou mot à mot</td>', '<td data-col="CrisperWhisper">Clean text, or word for word</td>'),
('<th scope="row">Licence</th>', '<th scope="row">Licence</th>'),
('<td data-col="macOS">Fournie avec macOS</td>', '<td data-col="macOS">Ships with macOS</td>'),
("Poids en <strong>recherche non commerciale</strong>", "Weights are <strong>non-commercial research</strong>"),
("À lire avant de l'installer", "Read before installing"),
("""        Côté macOS il y a en fait deux versions, et Caspr prend la meilleure que votre
        machine sait faire tourner, sans rien vous demander : la <strong>Dictée</strong>
        du système, présente depuis macOS 10.15 et jusque sur les Mac Intel, et
        <strong>Apple Intelligence</strong>, apparue avec macOS 26, plus fine sur les
        passages longs. La disponibilité est mesurée sur la machine, jamais déduite
        d'un numéro de version.""",
 """        On the macOS side there are in fact two versions, and Caspr picks the best one your
        machine can run without asking you: system <strong>Dictation</strong>, present
        since macOS 10.15 and all the way down to Intel Macs, and
        <strong>Apple Intelligence</strong>, introduced with macOS 26 and finer on long
        passages. Availability is measured on the machine, never inferred from a version
        number."""),
("""        Les poids de CrisperWhisper 2.0 relèvent d'une licence de recherche non commerciale
        de Nyra Health. Caspr ne les embarque pas et ne les télécharge jamais en silence :
        la licence s'affiche avant tout téléchargement, et le choix vous revient.""",
 """        CrisperWhisper 2.0's weights fall under a Nyra Health non-commercial research licence.
        Caspr does not bundle them and never downloads them silently: the licence is shown
        before any download, and the choice is yours."""),
("Lire la licence", "Read the licence"),
# ---- mesures ---------------------------------------------------------------
('id="mesures" aria-labelledby="mesures-titre"', 'id="numbers" aria-labelledby="numbers-title"'),
('<h2 id="mesures-titre">Ce qui a été mesuré</h2>', '<h2 id="numbers-title">What was measured</h2>'),
("""          Sur des enregistrements de voix réelle, et non de la parole synthétique.
          Les scripts qui reproduisent ces chiffres sont dans le dépôt.""",
 """          On real voice recordings rather than synthetic speech. The scripts that reproduce
          these numbers are in the repository."""),
("Aller-retour complet pour 13 secondes de parole, modèle déjà chaud", "Full round trip for 13 seconds of speech, model kept warm"),
("4 à 5×", "4–5×"),
("Plus rapide que la chaîne Python de référence, pour un texte identique à l'octet près", "Faster than the reference Python pipeline, for byte-identical text"),
("94 %", "94%"),
("Des termes techniques préservés avec lexique, contre 85 % sans", "Of technical terms preserved with a lexicon, against 85% without"),
("Octet envoyé sur le réseau pendant une transcription, quel que soit le moteur", "Bytes sent over the network during a transcription, with any engine"),
("""        Relevés sur un MacBook Pro M4 Pro, 48 Go, macOS 26.6. Deux points expliquent l'écart
        avec la chaîne de référence : celle-ci coûte environ 1,5 seconde de surcouche par
        transcription, et Whisper encode toujours 30 secondes même quand vous en avez dit 5 —
        réduire cette fenêtre à 15 secondes retire près de la moitié du temps d'encodage sans
        changer une lettre du résultat. En dessous de 15 secondes le modèle sort de son
        domaine d'entraînement, et Caspr n'y descend pas.""",
 """        Measured on a MacBook Pro M4 Pro, 48 GB, macOS 26.6. Two things explain the gap with
        the reference pipeline: it costs roughly 1.5 seconds of overhead per transcription,
        and Whisper always encodes 30 seconds even when you spoke for 5 — shrinking that
        window to 15 seconds removes nearly half the encoder time without changing a letter
        of the output. Below 15 seconds the model leaves its training distribution, and
        Caspr does not go there."""),
# ---- local / open source ---------------------------------------------------
('aria-labelledby="local-titre"', 'aria-labelledby="local-title"'),
('<h2 id="local-titre">Local par construction, open source par principe</h2>',
 '<h2 id="local-title">Local by construction, open source on principle</h2>'),
("""          La confidentialité n'est pas une promesse que Caspr vous demande de croire,
          c'est une conséquence de son architecture : il n'y a pas de serveur à qui
          envoyer quoi que ce soit. Et vous n'avez pas à me croire sur parole —
          l'intégralité du code est publique, sous licence MIT, lisible et compilable
          par vous.""",
 """          Privacy is not a promise Caspr asks you to take on trust, it is a consequence of
          how it is built: there is no server to send anything to. And you don't have to
          take my word for it — the whole codebase is public, MIT licensed, yours to read
          and to build."""),
("<strong>Gratuit et open source.</strong> Code Swift et moteur Python sous licence MIT, sur GitHub. Aucun bridage, aucun abonnement, aucun compte.",
 "<strong>Free and open source.</strong> The Swift app and the Python engine are MIT licensed, on GitHub. Nothing held back, no subscription, no account."),
("<strong>Aucune télémétrie.</strong> Pas de statistiques d'usage, pas de traceur, pas de rapport d'incident silencieux.",
 "<strong>No telemetry.</strong> No usage statistics, no tracker, no silent crash reports."),
("<strong>Hors-ligne pour de bon.</strong> Coupez le Wi-Fi : la dictée fonctionne à l'identique.",
 "<strong>Offline for real.</strong> Turn off Wi-Fi and dictation behaves identically."),
("<strong>Une seule requête, facultative.</strong> La vérification des mises à jour interroge GitHub, et se désactive dans les réglages.",
 "<strong>One optional request.</strong> The update check queries GitHub, and switches off in settings."),
("<strong>Une désinstallation qui désinstalle.</strong> L'environnement Python, les poids, les caches et les préférences partent avec — et seulement ce qui est réellement présent.",
 "<strong>An uninstaller that uninstalls.</strong> The Python environment, the weights, the caches and the preferences go with it — and only what is actually there."),
("Lire le code sur GitHub", "Read the code on GitHub"),
]

PAIRS += [
# ---- questions -------------------------------------------------------------
('aria-labelledby="questions-titre"', 'aria-labelledby="questions-title"'),
('<h2 id="questions-titre">Questions</h2>', '<h2 id="questions-title">Questions</h2>'),
("<span>De quel Mac ai-je besoin&nbsp;?</span>", "<span>Which Mac do I need?</span>"),
("<p>Caspr demande <strong>macOS 14 ou plus récent</strong>. Avec les moteurs de macOS, il fonctionne partout où la dictée du système fonctionne, <strong>Mac Intel compris</strong> : la Dictée existe depuis macOS 10.15, et Apple Intelligence s'y ajoute à partir de macOS 26 sur les Mac qui en disposent.</p>",
 "<p>Caspr needs <strong>macOS 14 or later</strong>. With the macOS engines it works anywhere system dictation works, <strong>Intel Macs included</strong>: Dictation has existed since macOS 10.15, and Apple Intelligence adds to it from macOS 26 on the Macs that support it.</p>"),
("<p>Seul <strong>CrisperWhisper</strong> impose une puce Apple Silicon (M1 et au-delà), parce qu'il s'exécute sur Metal — avec environ 1,6 Go de poids à télécharger et 3 Go de mémoire résidente pendant l'usage.</p>",
 "<p>Only <strong>CrisperWhisper</strong> requires an Apple Silicon chip (M1 and up), because it runs on Metal — with about 1.6 GB of weights to download and 3 GB resident in memory while in use.</p>"),
("<span>Ma voix ou mes textes partent-ils sur un serveur&nbsp;?</span>", "<span>Does my voice or text leave my machine?</span>"),
("<p>Non. La transcription s'exécute sur votre machine, avec tous les moteurs. Il n'y a ni compte, ni serveur, ni télémétrie. Coupez le Wi-Fi et Caspr fonctionne à l'identique.</p>",
 "<p>No. Transcription runs on your machine with every engine. There is no account, no server and no telemetry. Turn off Wi-Fi and Caspr behaves identically.</p>"),
("<p>La seule requête réseau de l'application est la vérification des mises à jour sur GitHub, et elle se désactive dans les réglages.</p>",
 "<p>The only network request the app makes is the update check against GitHub, and it switches off in settings.</p>"),
("<span>Pourquoi macOS refuse-t-il d'ouvrir l'application la première fois&nbsp;?</span>", "<span>Why does macOS refuse to open the app the first time?</span>"),
("<p>Parce que l'application n'est pas notariée par Apple — la notarisation suppose un compte développeur payant. Caspr est signé de façon ad hoc, alors macOS affiche un avertissement au premier lancement.</p>",
 "<p>Because the app is not notarised by Apple — notarisation requires a paid developer account. Caspr is ad-hoc signed, so macOS warns on first launch.</p>"),
("<p>L'autorisation se donne une fois, dans Réglages Système, rubrique Confidentialité et sécurité. Le guide qui s'ouvre au téléchargement montre chaque étape en image.</p>",
 "<p>You grant permission once, in System Settings under Privacy &amp; Security. The guide that opens on download shows every step in pictures.</p>"),
("<span>Caspr comprend-il le vocabulaire de mon métier&nbsp;?</span>", "<span>Does Caspr understand the vocabulary of my trade?</span>"),
("<p>C'est la raison d'être du projet. CrisperWhisper accepte un lexique qui oriente le décodage vers les termes que vous lui donnez : noms de clients, molécules, tickers, acronymes maison, jargon de la profession. Le mécanisme ne connaît aucun domaine en particulier.</p>",
 "<p>That is the reason the project exists. CrisperWhisper accepts a lexicon that biases decoding toward the terms you supply: client names, molecules, tickers, in-house acronyms, the jargon of the profession. The mechanism knows no particular field.</p>"),
("<p>Mesuré sur de la parole réelle mêlant français et anglais, <strong>32 termes sur 34</strong> sont préservés avec lexique, contre 29 sur 34 sans — et sans régression sur les phrases en français simple. Les moteurs de macOS, eux, n'ont pas ce mécanisme.</p>",
 "<p>Measured on real speech mixing French and English, <strong>32 of 34 terms</strong> survive with a lexicon, against 29 of 34 without — with no regression on plain sentences. The macOS engines have no such mechanism.</p>"),
("<span>Quelle est la licence&nbsp;?</span>", "<span>What is the licence?</span>"),
("<p>Le code de Caspr est sous licence MIT, comme le code d'inférence de CrisperWhisper. <strong>Les poids du modèle ne le sont pas</strong> : ils relèvent d'une licence de recherche non commerciale de Nyra Health.</p>",
 "<p>Caspr's own code is MIT, as is CrisperWhisper's inference code. <strong>The model weights are not</strong>: they fall under a Nyra Health non-commercial research licence.</p>"),
("<p>Caspr n'embarque donc pas ces poids et ne les télécharge jamais en silence. La licence s'affiche avant tout téléchargement et le choix vous revient. Sous une lecture stricte, dicter un courriel professionnel peut relever de l'usage commercial — ce qui est dit ici est un résumé, pas un avis juridique.</p>",
 "<p>Caspr therefore does not bundle those weights and never downloads them silently. The licence is shown before any download and the choice is yours. Under a strict reading, dictating work email may itself count as commercial use — this is a summary, not legal advice.</p>"),
("<span>Puis-je désinstaller proprement&nbsp;?</span>", "<span>Can I uninstall cleanly?</span>"),
("<p>Oui. L'application inclut un désinstallateur qui retire l'environnement Python, les poids du modèle, les caches et les préférences — et il ne propose de supprimer que ce qui est effectivement installé.</p>",
 "<p>Yes. The app ships an uninstaller that removes the Python environment, the model weights, the caches and the preferences — and it only offers to remove what is actually installed.</p>"),
# ---- appel final -----------------------------------------------------------
('aria-labelledby="final-titre"', 'aria-labelledby="final-title"'),
('<h2 id="final-titre">Essayez-le sur une phrase que vous n\'auriez pas osé dicter</h2>',
 '<h2 id="final-title">Try it on a sentence you would not have dared dictate</h2>'),
("""        Celle avec deux mots anglais au milieu, un nom propre et une hésitation.
        C'est le cas pour lequel Caspr a été écrit.""",
 """        The one with two borrowed words in the middle, a proper noun and a hesitation.
        That is the case Caspr was written for."""),
("Voir toutes les versions", "See all releases"),
("Gratuit et open source · macOS 14 ou plus récent · aucun compte", "Free and open source · macOS 14 or later · no account"),
# ---- pied de page ----------------------------------------------------------
("Dictée vocale locale pour macOS. Rapide, privée, open source. Zéro cloud, zéro abonnement.",
 "Local dictation for macOS. Fast, private, open source. No cloud, no subscription."),
("Un projet de <b>Lyria Studio</b>", "A project by <b>Lyria Studio</b>"),
('aria-labelledby="foot-produit"', 'aria-labelledby="foot-product"'),
('<h2 id="foot-produit">Le produit</h2>', '<h2 id="foot-product">Product</h2>'),
('<li><a href="#dictee">La dictée</a></li>', '<li><a href="#dictation">Dictation</a></li>'),
('<li><a href="#vocabulaire">Le vocabulaire</a></li>', '<li><a href="#vocabulary">Vocabulary</a></li>'),
('<li><a href="#barre">La barre</a></li>', '<li><a href="#bar">The bar</a></li>'),
('<li><a href="#notes">Les notes</a></li>', '<li><a href="#notes">Notes</a></li>'),
('<li><a href="#moteurs">Les moteurs</a></li>', '<li><a href="#engines">Engines</a></li>'),
('<li><a href="#mesures">Les mesures</a></li>', '<li><a href="#numbers">Measurements</a></li>'),
('<h2 id="foot-code">Le code</h2>', '<h2 id="foot-code">Code</h2>'),
("Dépôt GitHub", "GitHub repository"),
(">Versions</a>", ">Releases</a>"),
("Signaler un problème", "Report an issue"),
("Licence MIT du code", "MIT licence"),
('<h2 id="foot-site">Le site</h2>', '<h2 id="foot-site">Site</h2>'),
('<li><a href="en.html" hreflang="en" lang="en">English version</a></li>', '<li><a href="/" hreflang="fr" lang="fr">Version française</a></li>'),
('<li><a href="mentions-legales.html">Mentions légales</a></li>', '<li><a href="legal.html">Legal notice</a></li>'),
('<li><a href="politique-de-confidentialite.html">Confidentialité</a></li>', '<li><a href="privacy.html">Privacy</a></li>'),
('© 2026 Caspr — un projet <a href="https://lyriastudio.fr" rel="noopener">Lyria Studio</a>. Code sous licence MIT.',
 '© 2026 Caspr — a <a href="https://lyriastudio.fr" rel="noopener">Lyria Studio</a> project. Code under the MIT licence.'),
('<a href="mentions-legales.html">Mentions légales</a>\n        <a href="politique-de-confidentialite.html">Politique de confidentialité</a>',
 '<a href="legal.html">Legal notice</a>\n        <a href="privacy.html">Privacy policy</a>'),
# ---- fenêtre d'installation ------------------------------------------------
('aria-labelledby="modal-titre"', 'aria-labelledby="modal-title"'),
('aria-label="Fermer le guide d\'installation"', 'aria-label="Close the install guide"'),
('<h2 id="modal-titre">Le téléchargement a commencé</h2>', '<h2 id="modal-title">Your download has started</h2>'),
("<p>Votre fichier <code>Caspr.dmg</code> arrive. Voici comment l'ouvrir, en huit étapes illustrées.</p>",
 "<p>Your <code>Caspr.dmg</code> file is on its way. Here is how to open it, in eight illustrated steps.</p>"),
("<p><strong>Pourquoi ces étapes ?</strong> Caspr n'est pas notarié par Apple, ce qui suppose un compte développeur payant. macOS affiche donc un avertissement au premier lancement. L'autorisation se donne une fois, et prend une trentaine de secondes.</p>",
 "<p><strong>Why these steps?</strong> Caspr is not notarised by Apple, which requires a paid developer account. macOS therefore warns you on first launch. You grant permission once, and it takes about thirty seconds.</p>"),
('id="step-title">Ouvrez le fichier téléchargé</span>', 'id="step-title">Open the downloaded file</span>'),
("Double-cliquez sur <code>Caspr.dmg</code> dans vos téléchargements pour monter l'image disque.",
 "Double-click <code>Caspr.dmg</code> in your downloads to mount the disk image."),
('id="step-prev">Précédente</button>', 'id="step-prev">Previous</button>'),
('aria-label="Aller à une étape"', 'aria-label="Go to a step"'),
('id="step-next">Suivante</button>', 'id="step-next">Next</button>'),
("Le téléchargement n'a pas démarré ?", "Download didn't start?"),
('id="modal-done">J\'ai terminé</button>', 'id="modal-done">I\'m done</button>'),
]

out = src
for a, b in PAIRS:
    out = out.replace(a, b)

# Les ancres restantes suivent les identifiants anglais.
for a, b in [("#dictee", "#dictation"), ("#vocabulaire", "#vocabulary"), ("#barre", "#bar"),
             ("#moteurs", "#engines"), ("#mesures", "#numbers")]:
    out = out.replace(f'href="{a}"', f'href="{b}"')

(ROOT / "en.html").write_text(out, encoding="utf-8")

# --- contrôle : plus un mot de français dans le texte visible ---------------
from html.parser import HTMLParser
class Visible(HTMLParser):
    def __init__(s):
        super().__init__(); s.t=[]; s.skip=0; s.a=[]
    def handle_starttag(s, tag, at):
        if tag in ("script", "style"): s.skip += 1
        d = dict(at)
        for k in ("alt", "aria-label", "title", "content"):
            if d.get(k): s.a.append(d[k])
    def handle_endtag(s, tag):
        if tag in ("script", "style"): s.skip = max(0, s.skip - 1)
    def handle_data(s, d):
        if not s.skip and d.strip(): s.t.append(d.strip())

v = Visible(); v.feed(out)
blob = " ".join(v.t) + " " + " ".join(v.a)
# Les citations françaises sont l'exemple : elles doivent rester.
for keep in ["s'est écarté sur le forward", "a retoqué le protocole",
             "les dependencies dans le useEffect", "dépendances", "français", "French"]:
    blob = blob.replace(keep, "")
left = sorted(set(re.findall(r"\b[A-Za-zÀ-ÿ']*(?:é|è|ê|à|ù|ç|û|ô|î|É)[A-Za-zÀ-ÿ']*\b", blob)))
print("en.html — French left in visible text:", left if left else "none")
