/**
 * CASPR LANDING PAGE - TRANSLATIONS (FR & EN)
 * Complete, refined French and English localization strings.
 */

const TRANSLATIONS = {
  fr: {
    // Meta & Head
    pageTitle: "Caspr — Dictée Vocale IA 100% Locale & Open Source pour macOS",
    metaDesc: "Dictée vocale locale ultra-rapide, privée et open source pour macOS. Parlez en maintenant ⌥ Option, l'IA locale nettoie vos hésitations et écrit à la vitesse de votre pensée.",
    
    // Navbar
    brandSub: "par Lyria Studio",
    navDemo: "Démo Live",
    navEngines: "Deux Moteurs",
    navFeatures: "Super-pouvoirs",
    navOpenSource: "Open Source",
    navFaq: "FAQ",
    btnDownloadNav: "Télécharger",
    
    // Hero
    heroBadge: "⚡ Dictée Vocale IA 100% Locale & Open Source pour macOS",
    heroTitlePrefix: "Parlez naturellement.",
    heroTitleGradient: "Votre Mac écrit à la vitesse de votre pensée.",
    heroSubtitle: "Maintenez <strong>⌥ Option</strong> et parlez librement. L'IA locale transcrit et nettoie vos hésitations <strong>instantanément</strong>, puis insère le texte directement là où votre curseur clignote. <strong>100% Hors-ligne. 100% Open Source. Zéro compte. Zéro latence.</strong>",
    btnDownloadHero: "Télécharger pour macOS",
    heroVersionTag: "Caspr.dmg · macOS 14+ · Apple Silicon & Intel · Gratuit",
    btnDemoHero: "Tester la démo live",
    releaseLoading: "Chargement de la dernière version…",
    releaseStatus: "Dernière version : {tag} · {size} · macOS 14+ · {downloads}",
    releaseDownloadsSuffix: "téléchargements",
    releaseAvailableNow: "Disponible immédiatement",

    // Simulator
    simWindowBadge: "Maintenez ⌥ Option pour dicter",
    simWindowTitle: "Simulation en direct du cycle d'enregistrement Caspr",
    simFileName: "compte-rendu.md",
    simColPos: "Ln 14, Col 32",
    simEditorFaded1: "# Architecture Caspr — Dictée Locale",
    simEditorFaded2: "- Inférence ultra-rapide en moins de 0.4 seconde",
    simModeMic: "Isolement",
    simBadgeCollecte: "COLLECTE",
    simTabClean: "Nettoyé",
    simTabRaw: "Brut",
    simTabCaret: "Curseur",
    simTabNotes: "Notes",
    simBtnReplay: "▶ Rejouer la dictée",
    simHint: "Live Preview en direct pendant que vous parlez, puis insertion instantanée du texte nettoyé (<0.4s)",
    simStateSpeaking: "Écoute active en cours… (Live Preview instantané)",
    simStateProcessing: "⚡ Transcription IA locale (0.3s)…",
    simStateDoneClean: "✓ Texte nettoyé et inséré au curseur en 0.38s",
    simStateDoneRaw: "✓ Texte mot à mot inséré au curseur",

    // Comparison
    compTag: "L'Intelligence au service de votre voix",
    compTitle: "Pourquoi la dictée classique est frustrante,<br>et comment Caspr la réinvente.",
    compSubtitle: "Les dictées classiques écrivent chaque 'euh', répétition et bégaiement. Caspr écoute votre flux de pensée et restitue un texte propre, structuré et ponctué.",
    compClassicBadge: "❌ Dictée Standard (Cloud / Native)",
    compClassicTitle: "Brute & Remplie d'hésitations",
    compClassicSpeech: "\"Alors euh attends, on va faire la fonction euh <span class='highlight-bad'>get user data</span> enfin non <span class='highlight-bad'>fetch user data</span> avec un try catch virgule et euh si ça plante on renvoie nul point d'interrogation\"",
    compClassicP1: "Aucun nettoyage des bégaiements ou faux départs",
    compClassicP2: "Ponctuation orale lourde à devoir dicter à voix haute",
    compClassicP3: "Mélange catastrophique du code et de l'anglais technique",
    compCasprBadge: "✨ Avec Caspr (CrisperWhisper IA)",
    compCasprTitle: "Nettoyée, Structurée & Ponctuée",
    compCasprSpeech: "\"On va créer la fonction <code>fetchUserData</code> avec un bloc try/catch, et renvoyer <code>null</code> en cas d'erreur.\"",
    compCasprP1: "Suppression automatique des 'euh', bégaiements et hésitations",
    compCasprP2: "Ponctuation naturelle et majuscules inférées par le sens",
    compCasprP3: "Reconnaissance parfaite des termes de code et du franglais",

    // Dual Engines Section
    enginesTag: "Flexibilité & Performance",
    enginesTitle: "Deux Moteurs au Choix.<br>Adaptez Caspr à vos Besoins.",
    enginesSubtitle: "Basculez d'un clic dans les Réglages selon que vous cherchiez l'instantanéité absolue à 0 Mo de RAM ou la puissance d'une IA de restructuration de texte.",
    engineAppleBadge: "🚀 Zéro RAM · Instantané",
    engineAppleTitle: "Moteur macOS Natif",
    engineAppleDesc: "Exploite directement les frameworks de reconnaissance vocale intégrés d'Apple (Speech Recognition / Apple Intelligence).",
    engineAppleF1: "<strong>0 Mo de RAM supplémentaire :</strong> Utilise les modèles système macOS déjà en mémoire.",
    engineAppleF2: "<strong>Instantanéité totale :</strong> Aucune phase d'attente, transcription mot à mot au fil de l'eau.",
    engineAppleF3: "<strong>Ultra-léger :</strong> Idéal pour les configurations modestes ou les dictées courtes.",
    engineCrisperBadge: "✨ IA de Pointe · Nettoyage Intelligent",
    engineCrisperTitle: "Moteur CrisperWhisper IA",
    engineCrisperDesc: "Fait tourner un modèle Whisper local optimisé avec accélération matérielle Metal GPU / Neural Engine.",
    engineCrisperF1: "<strong>Suppression des hésitations :</strong> Efface automatiquement les 'euh', bafouillages et répétitions.",
    engineCrisperF2: "<strong>Ponctuation & Majuscules automatiques :</strong> Inférées selon le contexte et la syntaxe.",
    engineCrisperF3: "<strong>Vocabulaire Tech & Franglais :</strong> Reconnaît les termes de code et noms propres sans faille.",

    // Bento Features
    bentoTag: "Super-pouvoirs",
    bentoTitle: "Une application macOS conçue pour la vitesse.",
    bentoSubtitle: "Un condensé d'ingénierie native en Swift et d'IA locale optimisée sur Neural Engine et GPU.",
    
    bento1Tag: "Confidentialité Absolue",
    bento1Title: "100% Local. Zéro Cloud. Zéro Fuite.",
    bento1Desc: "Votre voix et vos textes ne quittent jamais votre Mac. L'inférence tourne localement sur Apple Silicon (Metal/MPS) ou CPU Intel. Coupez votre Wi-Fi : Caspr fonctionne exactement pareil.",
    bento1Pill1: "0 octet envoyé sur Internet",
    bento1Pill2: "Aucune télémétrie ni tracker",
    bento1Pill3: "Aucun compte requis",

    bento2Tag: "Hold-to-talk Instantané",
    bento2Title: "Touche ⌥ Option ou Raccourci",
    bento2Desc: "Maintenez la touche Option (ou votre raccourci), dictez votre phrase, relâchez : le texte est écrit en moins de 0.4s. Aucun clic ni sélection de fenêtre nécessaire.",

    bento3Tag: "Routage Intelligent",
    bento3Title: "Au curseur ou dans un journal Notes",
    bento3Desc: "Dictez directement dans VS Code, Slack, Notion, Word... Ou accumulez automatiquement vos idées dans un fichier Markdown journalier sans quitter votre travail en cours.",

    bento4Tag: "HUD Non-Intrusif",
    bento4Title: "Barre d'Écoute sans vol de focus",
    bento4Desc: "Panneau flottant non-activant (NSPanel) : il affiche vos ondes sonores et le texte live sous vos yeux sans jamais désactiver l'application dans laquelle vous tapez.",

    bento5Tag: "Polyglotte & Franglais",
    bento5Title: "24+ Langues & Dictionnaire Métier",
    bento5Desc: "Prise en charge de 24+ langues avec bascule rapide. Ajoutez vos acronymes, noms de code, hotwords et termes techniques dans votre lexique personnalisé pour une précision chirurgicale.",

    // Open Source
    osTag: "Transparence & Liberté",
    osTitle: "100% Open Source. Gratuit. Auditable.",
    osSubtitle: "Caspr appartient à la communauté. Aucun abonnement caché, aucun bridage payant, aucun code propriétaire opaque.",
    osCard1Title: "Code Source Public sur GitHub",
    osCard1Desc: "Tout le code Swift (AppKit, SwiftUI) et le moteur Python (uv, PyTorch, Whisper) est public. Vous pouvez inspecter chaque ligne, cloner le dépôt et compiler l'app vous-même.",
    osCard2Title: "Forkable & Personnalisable",
    osCard2Desc: "Créez vos propres modèles, personnalisez les invites de transcription ou intégrez de nouveaux pipelines audio selon vos besoins de développement.",
    osCard3Title: "Désinstallation Propre & Zéro Résidu",
    osCard3Desc: "Caspr intègre un désinstallateur propre qui supprime l'environnement Python, les caches et modèles sans laisser le moindre fichier orphelin sur votre Mac.",
    btnViewGithub: "Voir le dépôt GitHub",

    // Download Modal
    modalTitle: "Téléchargement de Caspr en cours… 🚀",
    modalSubtitle: "Votre fichier <code>Caspr.dmg</code> est en cours de téléchargement. Suivez ces étapes simples pour l'ouvrir sur votre Mac :",
    modalWhyTitle: "💡 Pourquoi ces étapes spécifiques ?",
    modalWhyDesc: "Caspr est un projet <strong>100% open source et gratuit</strong>. Nous ne payons pas l'abonnement Apple Developer à 99$/an, ce qui fait que macOS affiche un avertissement de sécurité par défaut. Suivre ces étapes ne prend que <strong>30 secondes</strong> et n'est à faire qu'une seule fois !",
    modalStep1Title: "1. Double-cliquez sur le DMG",
    modalStep1Desc: "Ouvrez le fichier <code>Caspr.dmg</code> téléchargé, puis double-cliquez sur l'icône Caspr.",
    modalStep2Title: "2. Message Gatekeeper",
    modalStep2Desc: "macOS affiche « Impossible d'ouvrir car l'app n'a pas été vérifiée ». Cliquez sur <strong>Terminer</strong>.",
    modalStep3Title: "3. Autoriser dans Réglages",
    modalStep3Desc: "Allez dans <strong>Réglages Système › Confidentialité et sécurité</strong>, scrollez tout en bas et cliquez sur <strong>« Ouvrir quand même »</strong>.",
    modalStep4Title: "4. Installation Automatique",
    modalStep4Desc: "Dans la fenêtre Caspr, cliquez sur <strong>[ Installer et ouvrir ]</strong>. L'application se déplace toute seule dans <code>/Applications</code> et s'ouvre !",
    modalBtnClose: "J'ai compris !",
    modalRestartDownload: "Le téléchargement n'a pas démarré ? Cliquez ici pour relancer.",

    // FAQ
    faqTag: "Questions Fréquentes",
    faqTitle: "Tout ce que vous devez savoir sur Caspr",
    faq1Q: "Quelles sont les configurations Mac compatibles ?",
    faq1A: "Caspr est compatible avec <strong>macOS 14 (Sonoma)</strong>, <strong>macOS 15 (Sequoia)</strong> et supérieur. Il fonctionne à pleine vitesse sur les puces <strong>Apple Silicon (M1, M2, M3, M4)</strong> grâce à l'accélération matérielle, et prend également en charge les processeurs <strong>Intel</strong>.",
    faq2Q: "Mes données audio ou transcriptions peuvent-elles être envoyées sur Internet ?",
    faq2A: "<strong>Non, jamais.</strong> Caspr fonctionne en circuit 100% fermé. L'application ne possède aucun serveur backend, aucun compte utilisateur, aucune connexion API cloud et aucun outil de télémétrie. Votre voix reste strictement confinée dans la mémoire vive de votre Mac.",
    faq3Q: "Pourquoi macOS affiche-t-il un message lors de la première ouverture ?",
    faq3A: "Pour distribuer une application sans avertissement Gatekeeper, Apple exige un compte développeur payant annuel de 99$/an. En tant que projet 100% open source et gratuit, Caspr est distribué librement. Suivre le guide en 1 clic (Ouvrir quand même dans Réglages Système) suffit à autoriser l'application de façon permanente.",
    faq4Q: "Comment fonctionne la touche ⌥ Option pour dicter ?",
    faq4A: "C'est le mode <em>Hold-to-talk</em> : maintenez la touche Option enfoncée pendant que vous parlez, puis relâchez-la. Dès le relâchement, Caspr nettoie le texte et l'injecte instantanément sous votre curseur actif.",
    faq5Q: "Puis-je utiliser Caspr dans du code ou en Franglais ?",
    faq5A: "Absolument ! C'est l'un des points forts majeurs de CrisperWhisper. Il reconnaît nativement les termes de programmation (<code>async/await</code>, <code>useState</code>, <code>try/catch</code>), les acronymes et les noms techniques anglais au milieu d'une phrase en français.",

    // Bottom CTA
    bottomTitle: "Prêt à dicter plus vite que vous ne tapez ?",
    bottomDesc: "Téléchargez Caspr gratuitement et découvrez la puissance d'une dictée vocale locale nouvelle génération sur votre Mac.",
    bottomBtn: "Télécharger Caspr pour macOS",
    bottomNote: "✓ 100% Gratuit · Open Source sur GitHub · macOS 14+",

    // Footer
    footerDesc: "Dictée vocale IA locale, confidentielle et ultra-rapide pour macOS.",
    footerReleaseLink: "Releases & Changelog",
    footerReportLink: "Signaler un bug",
    footerCopyright: "© 2026 Lyria Studio · Projet Open Source pour macOS."
  },

  en: {
    // Meta & Head
    pageTitle: "Caspr — 100% Local & Open Source AI Voice Dictation for macOS",
    metaDesc: "Ultra-fast, private and open-source local AI dictation for macOS. Hold ⌥ Option, local AI cleans your speech hesitations and types at the speed of thought.",
    
    // Navbar
    brandSub: "by Lyria Studio",
    navDemo: "Live Demo",
    navEngines: "Dual Engines",
    navFeatures: "Superpowers",
    navOpenSource: "Open Source",
    navFaq: "FAQ",
    btnDownloadNav: "Download",
    
    // Hero
    heroBadge: "⚡ 100% Local & Open Source AI Voice Dictation for macOS",
    heroTitlePrefix: "Speak naturally.",
    heroTitleGradient: "Your Mac writes at the speed of your thought.",
    heroSubtitle: "Hold <strong>⌥ Option</strong> and speak freely. Local AI transcribes and cleans speech hesitations <strong>instantly</strong>, typing directly wherever your cursor blinks. <strong>100% Offline. 100% Open Source. Zero accounts. Zero latency.</strong>",
    btnDownloadHero: "Download for macOS",
    heroVersionTag: "Caspr.dmg · macOS 14+ · Apple Silicon & Intel · Free",
    btnDemoHero: "Try the live demo",
    releaseLoading: "Loading latest release…",
    releaseStatus: "Latest release: {tag} · {size} · macOS 14+ · {downloads}",
    releaseDownloadsSuffix: "downloads",
    releaseAvailableNow: "Available now",

    // Simulator
    simWindowBadge: "Hold ⌥ Option to dictate",
    simWindowTitle: "Live simulation of the Caspr recording lifecycle",
    simFileName: "meeting-notes.md",
    simColPos: "Ln 14, Col 32",
    simEditorFaded1: "# Caspr Architecture — Local Dictation",
    simEditorFaded2: "- Ultra-fast inference and instant typing",
    simModeMic: "Isolation",
    simBadgeCollecte: "COLLECT",
    simTabClean: "Cleaned",
    simTabRaw: "Raw",
    simTabCaret: "Cursor",
    simTabNotes: "Notes",
    simBtnReplay: "▶ Replay dictation",
    simHint: "Instant Live Preview while speaking, followed by instant insertion of cleaned text",
    simStateSpeaking: "Listening in progress… (Instant Live Preview)",
    simStateProcessing: "⚡ Local AI transcription…",
    simStateDoneClean: "✓ Cleaned text inserted at cursor instantly",
    simStateDoneRaw: "✓ Verbatim text inserted at cursor",

    // Comparison
    compTag: "Intelligence applied to your voice",
    compTitle: "Why standard dictation is frustrating,<br>and how Caspr reinvents it.",
    compSubtitle: "Classic dictation engines write every 'um', repetition, and stutter. Caspr understands your train of thought and delivers clean, structured, and punctuated text.",
    compClassicBadge: "❌ Standard Dictation (Cloud / Built-in)",
    compClassicTitle: "Raw & Cluttered with Hesitations",
    compClassicSpeech: "\"So um wait, let's create the function um <span class='highlight-bad'>get user data</span> no wait <span class='highlight-bad'>fetch user data</span> with a try catch comma and um if it fails return null question mark\"",
    compClassicP1: "No removal of stutters or false starts",
    compClassicP2: "Awkward oral punctuation you have to say out loud",
    compClassicP3: "Catastrophic handling of code terms and technical jargon",
    compCasprBadge: "✨ With Caspr (CrisperWhisper AI)",
    compCasprTitle: "Cleaned, Structured & Punctuated",
    compCasprSpeech: "\"Let's create the <code>fetchUserData</code> function with a try/catch block, and return <code>null</code> on error.\"",
    compCasprP1: "Automatic removal of 'ums', repetitions and false starts",
    compCasprP2: "Natural punctuation and capitalization inferred from sentence context",
    compCasprP3: "Flawless recognition of code variables, acronyms and tech terms",

    // Dual Engines Section
    enginesTag: "Flexibility & Performance",
    enginesTitle: "Two Engines Included.<br>Tailor Caspr to your Workflow.",
    enginesSubtitle: "Switch in 1 click in Settings depending on whether you want instant 0 MB RAM speed or the power of AI text restructuring.",
    engineAppleBadge: "🚀 Zero RAM · Instant",
    engineAppleTitle: "macOS Native Engine",
    engineAppleDesc: "Leverages Apple's built-in system speech frameworks (Speech Recognition / Apple Intelligence).",
    engineAppleF1: "<strong>0 MB extra RAM:</strong> Utilizes system macOS speech models already in memory.",
    engineAppleF2: "<strong>Total zero latency:</strong> Instant word-by-word streaming dictation.",
    engineAppleF3: "<strong>Ultra lightweight:</strong> Ideal for battery saving or quick short phrases.",
    engineCrisperBadge: "✨ Next-Gen AI · Smart Cleanup",
    engineCrisperTitle: "CrisperWhisper AI Engine",
    engineCrisperDesc: "Runs a local Whisper model optimized with Metal GPU & Neural Engine hardware acceleration.",
    engineCrisperF1: "<strong>Removes hesitations:</strong> Strips out 'ums', filler words, stutters, and repetitions.",
    engineCrisperF2: "<strong>Auto punctuation & capitalization:</strong> Inferred from grammatical context.",
    engineCrisperF3: "<strong>Code & Technical terms:</strong> Understands programming keywords and mixed languages flawlessly.",

    // Bento Features
    bentoTag: "Superpowers",
    bentoTitle: "A macOS app engineered for raw speed.",
    bentoSubtitle: "Pure native Swift engineering combined with local AI models optimized for Neural Engine and GPU.",
    
    bento1Tag: "Absolute Privacy",
    bento1Title: "100% Local. Zero Cloud. Zero Data Leaks.",
    bento1Desc: "Your voice and text never leave your Mac. Inference runs locally on Apple Silicon (Metal/MPS) or Intel CPU. Turn off your Wi-Fi: Caspr runs exactly the same.",
    bento1Pill1: "0 bytes sent over the Internet",
    bento1Pill2: "Zero telemetry or trackers",
    bento1Pill3: "No account required",

    bento2Tag: "Instant Hold-to-Talk",
    bento2Title: "⌥ Option Key or Custom Shortcut",
    bento2Desc: "Hold the Option key (or your custom shortcut), speak your thought, and release: text is typed in under 0.4s. No clicking, no switching windows.",

    bento3Tag: "Smart Routing",
    bento3Title: "At Cursor or Append to Notes",
    bento3Desc: "Dictate directly into VS Code, Slack, Notion, Word... Or continuously append your thoughts to a daily Markdown <code>journal.md</code> without interrupting your current task.",

    bento4Tag: "Non-Intrusive HUD",
    bento4Title: "Floating Overlay without focus stealing",
    bento4Desc: "A lightweight non-activating panel (NSPanel): it displays your live audio waves and streaming text without ever unfocusing the app you are currently typing in.",

    bento5Tag: "Polyglot & Custom Lexicon",
    bento5Title: "24+ Languages & Hotwords Dictionary",
    bento5Desc: "Native support for 24+ languages with instant switching. Add your custom acronyms, code names, and technical terms to your custom dictionary for pinpoint accuracy.",

    // Open Source
    osTag: "Transparency & Freedom",
    osTitle: "100% Open Source. Free. Auditable.",
    osSubtitle: "Caspr belongs to the community. No hidden subscriptions, no paywalled features, no opaque proprietary code.",
    osCard1Title: "Public Source Code on GitHub",
    osCard1Desc: "All Swift code (AppKit, SwiftUI) and the Python engine (uv, PyTorch, Whisper) are open source. Inspect every single line, fork the repo, or build it yourself.",
    osCard2Title: "Forkable & Customizable",
    osCard2Desc: "Train custom models, tweak transcription prompts, or integrate custom audio pipelines to fit your exact developer workflow.",
    osCard3Title: "Clean Uninstaller & Zero Residue",
    osCard3Desc: "Caspr includes a dedicated clean uninstaller that completely wipes the Python environment, caches, and models without leaving orphan files on your Mac.",
    btnViewGithub: "View GitHub Repository",

    // Download Modal
    modalTitle: "Downloading Caspr… 🚀",
    modalSubtitle: "Your <code>Caspr.dmg</code> file is downloading. Follow these simple steps to open it on your Mac:",
    modalWhyTitle: "💡 Why are these extra steps required?",
    modalWhyDesc: "Caspr is a <strong>100% free and open-source</strong> project. We do not pay Apple's $99/year Developer Program fee, so macOS displays a default security notice. Following these steps takes only <strong>30 seconds</strong> and is done just once!",
    modalStep1Title: "1. Double-click the DMG",
    modalStep1Desc: "Open the downloaded <code>Caspr.dmg</code> file, then double-click the Caspr app icon.",
    modalStep2Title: "2. Gatekeeper Prompt",
    modalStep2Desc: "macOS displays \"Cannot be opened because Apple cannot check it\". Click <strong>Done</strong>.",
    modalStep3Title: "3. Allow in Settings",
    modalStep3Desc: "Go to <strong>System Settings › Privacy & Security</strong>, scroll to the bottom, and click <strong>\"Open Anyway\"</strong>.",
    modalStep4Title: "4. Automatic Install",
    modalStep4Desc: "In the Caspr dialog, click <strong>[ Install and open ]</strong>. The app automatically moves itself to <code>/Applications</code> and launches!",
    modalBtnClose: "Got it!",
    modalRestartDownload: "Download didn't start? Click here to restart.",

    // FAQ
    faqTag: "Frequently Asked Questions",
    faqTitle: "Everything you need to know about Caspr",
    faq1Q: "Which Mac models and macOS versions are supported?",
    faq1A: "Caspr is compatible with <strong>macOS 14 (Sonoma)</strong>, <strong>macOS 15 (Sequoia)</strong> and later. It runs at full speed on <strong>Apple Silicon chips (M1, M2, M3, M4)</strong> using Metal/MPS GPU acceleration, and fully supports <strong>Intel</strong> Macs.",
    faq2Q: "Can my audio recordings or text ever be sent over the internet?",
    faq2A: "<strong>No, never.</strong> Caspr operates completely offline. The app has no backend servers, no user accounts, no cloud API connections, and zero telemetry. Your voice strictly remains in your Mac's memory.",
    faq3Q: "Why does macOS show a security prompt on first launch?",
    faq3A: "To distribute software without Gatekeeper prompts, Apple requires a recurring $99/year developer subscription. As a 100% free and open-source project, Caspr is distributed directly. Following the 1-click step (Open Anyway in System Settings) permanently authorizes the app on your Mac.",
    faq4Q: "How does the ⌥ Option key dictation trigger work?",
    faq4A: "It's <em>Hold-to-talk</em>: simply hold the Option key down while you speak, then release it. The moment you release, Caspr cleans the text and instantly types it right where your cursor is.",
    faq5Q: "Can I use Caspr with programming code and technical terms?",
    faq5A: "Absolutely! That's one of CrisperWhisper's biggest strengths. It natively recognizes programming keywords (<code>async/await</code>, <code>useState</code>, <code>try/catch</code>), technical acronyms, and English tech terms seamlessly.",

    // Bottom CTA
    bottomTitle: "Ready to write faster than you can type?",
    bottomDesc: "Download Caspr for free and experience the power of next-generation local voice dictation on your Mac.",
    bottomBtn: "Download Caspr for macOS",
    bottomNote: "✓ 100% Free · Open Source on GitHub · macOS 14+",

    // Footer
    footerDesc: "Local, private, and ultra-fast AI voice dictation for macOS.",
    footerReleaseLink: "Releases & Changelog",
    footerReportLink: "Report an issue",
    footerCopyright: "© 2026 Lyria Studio · Open Source Project for macOS."
  }
};
