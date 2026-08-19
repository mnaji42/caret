/**
 * CASPR LANDING PAGE - JAVASCRIPT
 * Hero Typewriter, Large 8-Step Carousel Modal, Download Controller, GitHub Releases API
 */

document.addEventListener('DOMContentLoaded', () => {

  // Current page language (fr on index.html, en on en.html)
  const isEnglishPage = document.documentElement.lang === 'en' || window.location.pathname.endsWith('en.html');
  const currentLang = isEnglishPage ? 'en' : 'fr';

  // =========================================================================
  // 1. FAST HERO TYPEWRITER ANIMATION (SINGLE LINE GUARANTEED)
  // =========================================================================
  const typewriterText = document.getElementById('typewriter-phrase');
  
  const phrases = isEnglishPage ? [
    "writes at the speed of thought.",
    "cleans your speech in real time.",
    "runs 100% offline and private.",
    "understands code & tech terms."
  ] : [
    "écrit à la vitesse de votre pensée.",
    "nettoie vos hésitations en direct.",
    "fonctionne 100% hors-ligne.",
    "comprend votre code et vos termes."
  ];

  let phraseIdx = 0;
  let charIdx = 0;
  let isDeleting = false;
  let typeSpeed = 50;

  function runTypewriter() {
    if (!typewriterText) return;

    const currentPhrase = phrases[phraseIdx];

    if (isDeleting) {
      typewriterText.textContent = currentPhrase.substring(0, charIdx - 1);
      charIdx--;
      typeSpeed = 25;
    } else {
      typewriterText.textContent = currentPhrase.substring(0, charIdx + 1);
      charIdx++;
      typeSpeed = 40; // Super fast typing
    }

    if (!isDeleting && charIdx === currentPhrase.length) {
      // Pause at full sentence
      typeSpeed = 2200;
      isDeleting = true;
    } else if (isDeleting && charIdx === 0) {
      isDeleting = false;
      phraseIdx = (phraseIdx + 1) % phrases.length;
      typeSpeed = 400;
    }

    setTimeout(runTypewriter, typeSpeed);
  }

  runTypewriter();


  // =========================================================================
  // 2. GITHUB RELEASES API - LIVE STATS & LATEST VERSION
  // =========================================================================
  const releaseInfoText = document.getElementById('release-info-text');
  const heroVersionTag = document.getElementById('hero-version-tag');

  // TODO: Once Claude renames the DMG in the build pipeline, change DMG_ASSET_NAME to "Caspr.dmg"
  const GITHUB_REPO = "mnaji42/caspr";
  const DMG_ASSET_NAME = "Caspr.dmg";             // ← change to "Caspr.dmg" after Swift migration
  const DOWNLOAD_URL = `https://github.com/${GITHUB_REPO}/releases/latest/download/${DMG_ASSET_NAME}`;

  fetch(`https://api.github.com/repos/${GITHUB_REPO}/releases`)
    .then(res => {
      if (!res.ok) throw new Error('API Indisponible');
      return res.json();
    })
    .then(releases => {
      if (!releases || !releases.length) return;

      const latestRelease = releases[0];
      const versionTag = latestRelease.tag_name || 'v0.1.0';

      const totalDownloads = releases.reduce((acc, rel) => {
        return acc + (rel.assets || []).reduce((sum, asset) => sum + (asset.download_count || 0), 0);
      }, 0);

      const dmgAsset = (latestRelease.assets || []).find(a => a.name === DMG_ASSET_NAME || a.name === 'Caspr.dmg');
      const sizeMo = dmgAsset ? (dmgAsset.size / (1024 * 1024)).toFixed(1) + ' Mo' : '';

      if (releaseInfoText) {
        const parts = [`macOS 14+ · ${versionTag}`];
        if (sizeMo) parts.push(sizeMo);
        if (totalDownloads > 0) {
          parts.push(isEnglishPage ? `${totalDownloads} downloads` : `${totalDownloads} téléchargements`);
        }
        releaseInfoText.textContent = parts.join(' · ');
      }
    })
    .catch(() => {
      if (releaseInfoText) {
        releaseInfoText.textContent = isEnglishPage 
          ? 'macOS 14+ · Apple Silicon & Intel · Free'
          : 'macOS 14+ · Apple Silicon & Intel · Gratuit';
      }
    });


  // =========================================================================
  // 3. LARGE 8-STEP INSTALLATION CAROUSEL INSIDE MODAL
  // =========================================================================
  const carouselSteps = [
    {
      img: 'images/01-fichier-telecharger-doubleclick.png',
      fr: {
        title: '1. Téléchargez et ouvrez Caspr.dmg',
        desc: 'Récupérez le fichier <code>Caspr.dmg</code> puis double-cliquez dessus pour monter l\'image disque dans votre Finder.'
      },
      en: {
        title: '1. Download and open Caspr.dmg',
        desc: 'Download the <code>Caspr.dmg</code> file and double-click it to mount the disk image in your Finder.'
      }
    },
    {
      img: 'images/02-dmg-ouvert-doubleclick.png',
      fr: {
        title: '2. Double-cliquez sur l\'icône Caspr',
        desc: 'Dans la fenêtre qui apparaît, double-cliquez directement sur l\'icône Caspr. (Inutile de glisser l\'application, Caspr s\'installera tout seul à l\'étape 7).'
      },
      en: {
        title: '2. Double-click the Caspr icon',
        desc: 'In the window that appears, double-click the Caspr icon directly. (No manual drag needed; Caspr installs itself in Step 7).'
      }
    },
    {
      img: 'images/03-erreur-car-car-pas-verifier-par-apple-terminer.png',
      fr: {
        title: '3. Message de sécurité Gatekeeper',
        desc: 'Comme Caspr est open-source et distribué sans compte payant Apple, macOS affiche ce message de sécurité standard. Cliquez simplement sur <strong>Terminer</strong>.'
      },
      en: {
        title: '3. Gatekeeper Security Prompt',
        desc: 'Since Caspr is open-source and distributed without an Apple Developer fee, macOS displays this security notice. Simply click <strong>Done</strong>.'
      }
    },
    {
      img: 'images/04-pomme-puis-reglage-system.png',
      fr: {
        title: '4. Menu Pomme  › Réglages Système',
        desc: 'Cliquez sur le menu Pomme  tout en haut à gauche de votre écran, puis sélectionnez <strong>Réglages Système…</strong>.'
      },
      en: {
        title: '4. Apple Menu  › System Settings',
        desc: 'Click the Apple menu  at the top-left of your screen, then select <strong>System Settings…</strong>.'
      }
    },
    {
      img: 'images/05-cliquer-sur-confidentialite-et-securite.png',
      fr: {
        title: '5. Confidentialité et sécurité',
        desc: 'Dans la colonne de gauche de vos Réglages Système, cliquez sur la rubrique <strong>Confidentialité et sécurité</strong>.'
      },
      en: {
        title: '5. Privacy & Security',
        desc: 'In the left sidebar of your System Settings, click on <strong>Privacy & Security</strong>.'
      }
    },
    {
      img: 'images/06-scroller-tout-en-bas-cliquer-ouvrir-quand-meme.png',
      fr: {
        title: '6. Scrollez tout en bas et cliquez « Ouvrir quand même »',
        desc: 'Descendez jusqu\'à la section <em>Sécurité</em>, repérez la mention indiquant le blocage de Caspr, puis cliquez sur <strong>« Ouvrir quand même »</strong> et validez avec votre mot de passe ou Touch ID.'
      },
      en: {
        title: '6. Scroll down and click "Open Anyway"',
        desc: 'Scroll down to the <em>Security</em> section, find the blocked notice for Caspr, click <strong>"Open Anyway"</strong>, and confirm with your password or Touch ID.'
      }
    },
    {
      img: 'images/07-Popup-souvre-installer-dans-application.png',
      fr: {
        title: '7. Pop-up Caspr : « Installer et ouvrir »',
        desc: 'Le dialogue officiel de Caspr apparaît ! Cliquez sur <strong>[ Installer et ouvrir ]</strong> : l\'application se copie dans <code>/Applications</code>, retire la quarantaine et s\'ouvre toute seule.'
      },
      en: {
        title: '7. Caspr Dialog: "Install and Open"',
        desc: 'Caspr\'s installer dialog appears! Click <strong>[ Install and open ]</strong>: the app copies itself to <code>/Applications</code>, removes quarantine, and relaunches.'
      }
    },
    {
      img: 'images/08-attendre-quelque-seconde-onboarding-souvre.png',
      fr: {
        title: '8. L\'Onboarding en 5 étapes s\'ouvre !',
        desc: 'L\'accueil interactif de Caspr s\'ouvre : accordez l\'accès micro, choisissez votre touche ⌥ Option et profitez d\'une dictée locale ultra-rapide !'
      },
      en: {
        title: '8. 5-Step Onboarding is Ready!',
        desc: 'Caspr\'s interactive setup opens: grant microphone access, pick your ⌥ Option trigger, and enjoy private, ultra-fast local dictation!'
      }
    }
  ];

  let currentCarouselStep = 0;
  const carouselImg = document.getElementById('carousel-img');
  const carouselBadge = document.getElementById('carousel-step-badge');
  const carouselTitle = document.getElementById('carousel-step-title');
  const carouselDesc = document.getElementById('carousel-step-desc');
  const carouselPrevBtn = document.getElementById('carousel-prev-btn');
  const carouselNextBtn = document.getElementById('carousel-next-btn');
  const carouselDotsContainer = document.getElementById('carousel-dots');

  // Build dots
  if (carouselDotsContainer) {
    carouselDotsContainer.innerHTML = '';
    carouselSteps.forEach((_, i) => {
      const dot = document.createElement('button');
      dot.type = 'button';
      dot.className = `carousel-dot ${i === 0 ? 'active' : ''}`;
      dot.setAttribute('aria-label', isEnglishPage ? `Go to step ${i + 1} of ${carouselSteps.length}` : `Aller à l'étape ${i + 1} sur ${carouselSteps.length}`);
      dot.addEventListener('click', () => updateCarousel(i));
      carouselDotsContainer.appendChild(dot);
    });
  }

  function updateCarousel(index) {
    currentCarouselStep = Math.max(0, Math.min(carouselSteps.length - 1, index));
    const stepData = carouselSteps[currentCarouselStep];
    const langObj = isEnglishPage ? stepData.en : stepData.fr;

    if (carouselImg) carouselImg.src = stepData.img;
    if (carouselBadge) carouselBadge.textContent = isEnglishPage ? `Step ${currentCarouselStep + 1} of 8` : `Étape ${currentCarouselStep + 1} sur 8`;
    if (carouselTitle) carouselTitle.textContent = langObj.title;
    if (carouselDesc) carouselDesc.innerHTML = langObj.desc;

    // Update dots
    if (carouselDotsContainer) {
      const dots = carouselDotsContainer.querySelectorAll('.carousel-dot');
      dots.forEach((d, i) => {
        d.classList.toggle('active', i === currentCarouselStep);
      });
    }

    // Disable/Enable Nav buttons
    if (carouselPrevBtn) carouselPrevBtn.disabled = currentCarouselStep === 0;
    if (carouselNextBtn) {
      carouselNextBtn.textContent = currentCarouselStep === carouselSteps.length - 1 
        ? (isEnglishPage ? 'Finished ✓' : 'Terminé ✓')
        : (isEnglishPage ? 'Next ›' : 'Suivant ›');
    }
  }

  if (carouselPrevBtn) {
    carouselPrevBtn.addEventListener('click', () => updateCarousel(currentCarouselStep - 1));
  }
  if (carouselNextBtn) {
    carouselNextBtn.addEventListener('click', () => {
      if (currentCarouselStep < carouselSteps.length - 1) {
        updateCarousel(currentCarouselStep + 1);
      } else {
        closeDownloadModal();
      }
    });
  }

  // Initialize carousel on Step 1
  updateCarousel(0);


  // =========================================================================
  // 4. DOWNLOAD MODAL CONTROLLER
  // =========================================================================
  const downloadModal = document.getElementById('download-modal');
  const modalCloseBtn = document.getElementById('modal-close-btn');
  const modalConfirmBtn = document.getElementById('modal-confirm-btn');
  const downloadTriggerButtons = document.querySelectorAll('.download-trigger-btn');

  function openDownloadModalAndTrigger() {
    // 1. Programmatically trigger DMG download
    const tempLink = document.createElement('a');
    tempLink.href = DOWNLOAD_URL;
    tempLink.setAttribute('download', 'Caspr.dmg');
    document.body.appendChild(tempLink);
    tempLink.click();
    document.body.removeChild(tempLink);

    // 2. Reset carousel to Step 1 & open modal
    updateCarousel(0);
    if (downloadModal) {
      downloadModal.classList.add('open');
      document.body.style.overflow = 'hidden';
    }
  }

  function closeDownloadModal() {
    if (downloadModal) {
      downloadModal.classList.remove('open');
      document.body.style.overflow = '';
    }
  }

  downloadTriggerButtons.forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      openDownloadModalAndTrigger();
    });
  });

  if (modalCloseBtn) modalCloseBtn.addEventListener('click', closeDownloadModal);
  if (modalConfirmBtn) modalConfirmBtn.addEventListener('click', closeDownloadModal);

  if (downloadModal) {
    downloadModal.addEventListener('click', (e) => {
      if (e.target === downloadModal) {
        closeDownloadModal();
      }
    });
  }

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && downloadModal && downloadModal.classList.contains('open')) {
      closeDownloadModal();
    }
  });


  // =========================================================================
  // 5. AUTHENTIC HUD RECORDER & DICTATION LIFECYCLE SIMULATOR
  // =========================================================================
  const hudDot = document.getElementById('hud-dot');
  const hudTimer = document.getElementById('hud-timer');
  const hudVumeter = document.getElementById('hud-vumeter');
  const hudLiveText = document.getElementById('hud-live-text');
  const mockInsertedText = document.getElementById('mock-inserted-text');
  const btnTriggerDictate = document.getElementById('btn-trigger-dictate');
  
  const tabClean = document.getElementById('tab-clean');
  const tabRaw = document.getElementById('tab-raw');
  const tabCaret = document.getElementById('tab-caret');
  const tabNotes = document.getElementById('tab-notes');
  const btnMicMode = document.getElementById('btn-mic-mode');
  const btnCollecte = document.getElementById('btn-collecte');

  let isWhisperClean = true;
  let vuInterval = null;
  let animTimeout = null;

  const sentences = isEnglishPage ? {
    liveWords: ["We configured", "the local", "inference engine", "and transcripts", "remain 100%", "on the machine", "without cloud."],
    rawSentence: "So um we configured the the inference engine locally and um the transcripts yeah.",
    cleanSentence: "We configured the inference engine locally, and all transcriptions strictly remain on the machine with zero data leaks."
  } : {
    liveWords: ["On a", "configuré", "le serveur", "d'inférence", "en local", "et les", "transcriptions restent", "100% sur", "la machine."],
    rawSentence: "Alors euh on a configuré le le serveur d'inférence en local et euh les transcriptions voilà.",
    cleanSentence: "On a configuré le serveur d'inférence en local, et les transcriptions restent 100% sur la machine sans fuite de données."
  };

  function startVumeter() {
    if (vuInterval) clearInterval(vuInterval);
    const bars = hudVumeter ? hudVumeter.querySelectorAll('.vu-bar') : [];
    vuInterval = setInterval(() => {
      bars.forEach(bar => {
        const h = Math.floor(3 + Math.random() * 15);
        bar.style.height = `${h}px`;
      });
    }, 120);
  }

  function stopVumeter() {
    if (vuInterval) clearInterval(vuInterval);
    const bars = hudVumeter ? hudVumeter.querySelectorAll('.vu-bar') : [];
    bars.forEach(bar => { bar.style.height = '3px'; });
  }

  function runDictationSimulation() {
    if (animTimeout) clearTimeout(animTimeout);

    if (hudDot) {
      hudDot.className = 'hud-rec-dot';
      hudDot.style.display = 'inline-block';
    }
    if (hudTimer) hudTimer.textContent = '0:02';
    if (mockInsertedText) mockInsertedText.textContent = '';
    if (hudLiveText) hudLiveText.textContent = '…';
    startVumeter();

    let step = 0;
    function streamNextWord() {
      if (step < sentences.liveWords.length) {
        if (hudLiveText) {
          hudLiveText.textContent = '… ' + sentences.liveWords.slice(0, step + 1).join(' ');
        }
        step++;
        animTimeout = setTimeout(streamNextWord, 240);
      } else {
        stopVumeter();
        if (hudDot) hudDot.className = 'hud-rec-dot processing';
        if (hudTimer) hudTimer.textContent = '⚡';
        if (hudLiveText) {
          hudLiveText.textContent = isEnglishPage ? '⚡ Local AI transcription…' : '⚡ Transcription IA locale…';
        }

        animTimeout = setTimeout(() => {
          if (hudTimer) hudTimer.textContent = '0:03';
          if (mockInsertedText) {
            mockInsertedText.textContent = isWhisperClean ? sentences.cleanSentence : sentences.rawSentence;
          }
          if (hudLiveText) {
            hudLiveText.textContent = isWhisperClean 
              ? (isEnglishPage ? '✓ Cleaned text inserted at cursor instantly' : '✓ Texte nettoyé et inséré au curseur instantanément')
              : (isEnglishPage ? '✓ Verbatim text inserted at cursor' : '✓ Texte mot à mot inséré au curseur');
          }
          if (hudDot) hudDot.className = 'hud-rec-dot';
        }, 350);
      }
    }

    streamNextWord();
  }

  runDictationSimulation();

  if (btnTriggerDictate) {
    btnTriggerDictate.addEventListener('click', runDictationSimulation);
  }

  if (tabClean && tabRaw) {
    tabClean.addEventListener('click', () => {
      isWhisperClean = true;
      tabClean.classList.add('active');
      tabRaw.classList.remove('active');
      runDictationSimulation();
    });

    tabRaw.addEventListener('click', () => {
      isWhisperClean = false;
      tabRaw.classList.add('active');
      tabClean.classList.remove('active');
      runDictationSimulation();
    });
  }

  if (tabCaret && tabNotes) {
    tabCaret.addEventListener('click', () => {
      tabCaret.classList.add('active');
      tabNotes.classList.remove('active');
    });

    tabNotes.addEventListener('click', () => {
      tabNotes.classList.add('active');
      tabCaret.classList.remove('active');
    });
  }

  if (btnMicMode) {
    const modes = isEnglishPage ? ['Isolation', 'Standard', 'Wide'] : ['Isolement', 'Standard', 'Large'];
    let modeIdx = 0;
    btnMicMode.addEventListener('click', () => {
      modeIdx = (modeIdx + 1) % modes.length;
      btnMicMode.textContent = modes[modeIdx];
    });
  }

  if (btnCollecte) {
    let isCollectActive = true;
    btnCollecte.addEventListener('click', () => {
      isCollectActive = !isCollectActive;
      if (isCollectActive) {
        btnCollecte.style.background = 'rgba(249, 115, 22, 0.14)';
        btnCollecte.style.borderColor = 'rgba(249, 115, 22, 0.6)';
        btnCollecte.style.color = '#fb923c';
      } else {
        btnCollecte.style.background = 'transparent';
        btnCollecte.style.borderColor = 'rgba(255, 255, 255, 0.2)';
        btnCollecte.style.color = 'rgba(255, 255, 255, 0.5)';
      }
    });
  }


  // =========================================================================
  // 6. FAQ ACCORDION
  // =========================================================================
  const faqQuestions = document.querySelectorAll('.faq-question');

  faqQuestions.forEach(question => {
    question.addEventListener('click', () => {
      const faqItem = question.parentElement;
      const isActive = faqItem.classList.contains('active');

      document.querySelectorAll('.faq-item').forEach(item => {
        item.classList.remove('active');
        const qBtn = item.querySelector('.faq-question');
        if (qBtn) qBtn.setAttribute('aria-expanded', 'false');
      });

      if (!isActive) {
        faqItem.classList.add('active');
        question.setAttribute('aria-expanded', 'true');
      }
    });
  });

});
