"""Construit la page de comparaison des moteurs sur le corpus réel.

Sortie : un fichier HTML autonome, à ouvrir dans un navigateur. Il n'y a pas de
vérité terrain sur ce corpus (cf. engine_stats), donc la page ne classe pas :
elle **donne à lire**, et elle range les dictées de façon que celles où les
moteurs divergent le plus arrivent en premier.

Usage :
    engine/.venv/bin/python poc/report_engines.py
    engine/.venv/bin/python poc/report_engines.py --out /tmp/comparaison.html
"""

from __future__ import annotations

import argparse
import difflib
import html
import json
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import engine_stats as st

CORPUS = Path.home() / "Library/Application Support/Caspr/corpus"
VOXTRAL_RUN = Path(__file__).parent / "voxtral-run.json"

# Les moteurs, dans l'ordre où ils s'affichent. La clé est celle du corpus :
# (engine, mode). La couleur encode la **famille** — deux nuances d'indigo pour
# les deux modes de CrisperWhisper, deux gris pour les deux macOS — parce que
# c'est vrai du sujet : ce sont deux réglages d'un même moteur, pas quatre
# moteurs.
ENGINES = [
    {"key": "voxtral",      "name": "Voxtral",     "sub": "Mistral · Mini 3B",   "hue": "amber"},
    {"key": "crisper:intended", "name": "CrisperWhisper", "sub": "turbo · nettoyé", "hue": "indigo"},
    {"key": "crisper:verbatim", "name": "CrisperWhisper", "sub": "turbo · mot à mot", "hue": "violet"},
    {"key": "apple",        "name": "macOS",       "sub": "Apple Intelligence", "hue": "slate"},
    {"key": "apple-legacy", "name": "macOS",       "sub": "Dictée",             "hue": "steel"},
]


def engine_key(t: dict) -> str:
    e = t.get("engine")
    if e == "crisperwhisper":
        return f"crisper:{t.get('mode') or 'intended'}"
    if e == "apple-legacy":
        return "apple-legacy"
    return "apple" if e == "apple" else e


def load() -> list[dict]:
    rows = [json.loads(l) for l in (CORPUS / "sessions.jsonl").read_text().splitlines() if l.strip()]
    vox = {}
    if VOXTRAL_RUN.exists():
        data = json.loads(VOXTRAL_RUN.read_text())
        vox = {r["id"]: r for r in data["results"] if r.get("text")}

    entries = []
    for r in rows:
        texts: dict[str, dict] = {}
        for t in r["transcriptions"]:
            k = engine_key(t)
            if t.get("text") and k not in texts:
                texts[k] = {"text": t["text"], "latencyMs": t.get("latencyMs"),
                            "model": t.get("model")}
        if r["id"] in vox:
            v = vox[r["id"]]
            texts["voxtral"] = {"text": v["text"], "latencyMs": v["latencyMs"],
                                "model": "mistralai/Voxtral-Mini-3B-2507"}
        if not texts:
            continue
        longest = max(len(v["text"].split()) for v in texts.values())
        for v in texts.values():
            v["words"] = st.word_count(v["text"])
            v["repetition"] = st.repetition(v["text"])
            v["terms"] = st.terms(v["text"])
            v["coverage"] = round(v["words"] / longest, 3) if longest else 0.0

        # Termes isolés : présents chez **un seul** moteur sur cette dictée.
        # Le signal coupe dans les deux sens, et c'est pour ça qu'il vaut le
        # détour — soit ce moteur a inventé le mot (CrisperWhisper glisse son
        # lexique dans le texte : « Effect la feature » pour « parce que la
        # feature »), soit il est le seul à l'avoir bien écrit. Dans les deux
        # cas c'est là qu'il faut aller lire. Sans deux autres moteurs pour
        # faire quorum, la question ne se pose pas.
        for k, v in texts.items():
            others = [o for kk, o in texts.items() if kk != k]
            v["lonely"] = sorted(
                t for t in v["terms"]
                if len(others) >= 2 and not any(t in o["terms"] for o in others)
            ) if len(others) >= 2 else []
        entries.append({
            "id": r["id"], "date": r["date"], "duration": r["durationSeconds"],
            "language": r.get("language", "fr"), "audioFile": r.get("audioFile"),
            "texts": texts,
        })
    return entries


def diff_spans(a: str, b: str) -> tuple[str, str]:
    """Deux textes balisés mot à mot : ce qui diffère est marqué de part et
    d'autre. C'est ce qui remplace la lecture de deux paragraphes entiers."""
    aw, bw = a.split(), b.split()
    sm = difflib.SequenceMatcher(None, [st._fold(w) for w in aw],
                                 [st._fold(w) for w in bw])
    out_a: list[str] = []
    out_b: list[str] = []
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        ta = html.escape(" ".join(aw[i1:i2]))
        tb = html.escape(" ".join(bw[j1:j2]))
        if tag == "equal":
            out_a.append(ta); out_b.append(tb)
        else:
            if ta: out_a.append(f'<mark class="d">{ta}</mark>')
            if tb: out_b.append(f'<mark class="d">{tb}</mark>')
    return " ".join(out_a), " ".join(out_b)


CSS = """
/* Fondations — le gris tire légèrement vers le bleu de l'écran, pas vers le
   beige : le sujet est un instrument, pas un imprimé. */
:root{
  --ground:#F7F8FB; --surface:#FFFFFF; --sunken:#EEF0F6;
  --ink:#151821; --ink-soft:#4A5162; --ink-faint:#7C8497;
  --line:#E2E5EE; --line-soft:#EDEFF5;
  --amber:#B45309; --amber-bg:#FDF3E3;
  --indigo:#4338CA; --indigo-bg:#EDECFC;
  --violet:#6D28D9; --violet-bg:#F2ECFD;
  --slate:#334155; --slate-bg:#EDF0F4;
  --steel:#5B7189; --steel-bg:#EDF1F6;
  --warn:#B42318; --warn-bg:#FDECEA;
  --diff:#FDE68A; --diff-ink:#4A3400;
  --shadow:0 1px 2px rgba(21,24,33,.05), 0 8px 24px -12px rgba(21,24,33,.18);
}
@media (prefers-color-scheme:dark){ :root:not([data-theme="light"]){
  --ground:#0F1116; --surface:#171A21; --sunken:#1E222B;
  --ink:#E7EAF2; --ink-soft:#A7B0C2; --ink-faint:#767F92;
  --line:#282D38; --line-soft:#20242D;
  --amber:#F0B357; --amber-bg:#2E2213;
  --indigo:#A5A0F5; --indigo-bg:#1E1D3A;
  --violet:#C4A5F7; --violet-bg:#251B38;
  --slate:#A8B6CA; --slate-bg:#1C222B;
  --steel:#93A9C2; --steel-bg:#1A212A;
  --warn:#F2938C; --warn-bg:#33191A;
  --diff:#5C4A12; --diff-ink:#FBE7A8;
  --shadow:0 1px 2px rgba(0,0,0,.4), 0 8px 24px -12px rgba(0,0,0,.6);
}}
:root[data-theme="dark"]{
  --ground:#0F1116; --surface:#171A21; --sunken:#1E222B;
  --ink:#E7EAF2; --ink-soft:#A7B0C2; --ink-faint:#767F92;
  --line:#282D38; --line-soft:#20242D;
  --amber:#F0B357; --amber-bg:#2E2213;
  --indigo:#A5A0F5; --indigo-bg:#1E1D3A;
  --violet:#C4A5F7; --violet-bg:#251B38;
  --slate:#A8B6CA; --slate-bg:#1C222B;
  --steel:#93A9C2; --steel-bg:#1A212A;
  --warn:#F2938C; --warn-bg:#33191A;
  --diff:#5C4A12; --diff-ink:#FBE7A8;
  --shadow:0 1px 2px rgba(0,0,0,.4), 0 8px 24px -12px rgba(0,0,0,.6);
}
*{box-sizing:border-box}
body{
  margin:0; background:var(--ground); color:var(--ink);
  font:400 15px/1.6 -apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",system-ui,sans-serif;
  -webkit-font-smoothing:antialiased;
}
/* La chrome de données est en mono, la parole transcrite reste en humanist :
   c'est l'idée du sujet — un instrument d'ingénieur qui lit du langage. */
.mono{font-family:ui-monospace,"SF Mono",Menlo,monospace; font-variant-numeric:tabular-nums}
.wrap{max-width:1340px; margin:0 auto; padding:0 24px}

header.top{border-bottom:1px solid var(--line); background:var(--surface)}
.masthead{padding:40px 0 28px}
h1{
  margin:0 0 6px; font-size:clamp(26px,3.4vw,38px); line-height:1.1;
  letter-spacing:-.028em; font-weight:640; text-wrap:balance;
}
.lede{margin:0; max-width:64ch; color:var(--ink-soft); font-size:15.5px}
.corpusline{
  margin-top:18px; display:flex; flex-wrap:wrap; gap:8px 22px;
  font-size:12px; letter-spacing:.04em; text-transform:uppercase; color:var(--ink-faint);
}
.corpusline b{color:var(--ink); font-weight:600}

/* Panneau agrégé — les chiffres qu'on lit avant d'ouvrir une dictée. */
section.summary{padding:30px 0 34px}
h2{
  margin:0 0 4px; font-size:13px; letter-spacing:.09em; text-transform:uppercase;
  color:var(--ink-faint); font-weight:640;
}
.note{margin:0 0 18px; color:var(--ink-soft); font-size:13.5px; max-width:70ch}
.tablewrap{overflow-x:auto; border:1px solid var(--line); border-radius:12px; background:var(--surface)}
table{border-collapse:collapse; width:100%; min-width:760px; font-size:13.5px}
th,td{padding:11px 14px; text-align:right; border-bottom:1px solid var(--line-soft); white-space:nowrap}
th{
  font-size:11px; letter-spacing:.06em; text-transform:uppercase;
  color:var(--ink-faint); font-weight:600; background:var(--sunken);
}
th:first-child,td:first-child{text-align:left}
tbody tr:last-child td{border-bottom:none}
.ename{display:flex; align-items:baseline; gap:8px}
.dot{width:9px; height:9px; border-radius:3px; flex:none; transform:translateY(-1px)}
.esub{color:var(--ink-faint); font-size:11.5px}
.bar{position:relative; height:5px; border-radius:3px; background:var(--sunken); min-width:64px}
.bar i{position:absolute; inset:0 auto 0 0; border-radius:3px}

/* Contrôles */
.controls{
  position:sticky; top:0; z-index:20; background:var(--surface);
  border-bottom:1px solid var(--line); padding:12px 0;
}
.ctlrow{display:flex; flex-wrap:wrap; gap:10px 16px; align-items:center}
.field{display:flex; align-items:center; gap:7px}
label{font-size:11px; letter-spacing:.06em; text-transform:uppercase; color:var(--ink-faint); font-weight:600}
select,input[type=search]{
  font:inherit; font-size:13px; color:var(--ink); background:var(--surface);
  border:1px solid var(--line); border-radius:8px; padding:6px 9px;
}
input[type=search]{min-width:180px}
select:focus-visible,input:focus-visible,button:focus-visible{
  outline:2px solid var(--ink); outline-offset:2px;
}
.seg{display:flex; border:1px solid var(--line); border-radius:8px; overflow:hidden}
.seg button{
  font:inherit; font-size:12.5px; padding:6px 11px; border:0; cursor:pointer;
  background:var(--surface); color:var(--ink-soft); border-right:1px solid var(--line);
}
.seg button:last-child{border-right:0}
.seg button[aria-pressed=true]{background:var(--ink); color:var(--ground)}
.count{margin-left:auto; font-size:12px; color:var(--ink-faint)}

/* Une dictée */
.entries{padding:26px 0 80px; display:flex; flex-direction:column; gap:16px}
article.entry{
  background:var(--surface); border:1px solid var(--line);
  border-radius:14px; box-shadow:var(--shadow); overflow:hidden;
}
.ehead{
  display:flex; flex-wrap:wrap; align-items:center; gap:8px 14px;
  padding:12px 18px; border-bottom:1px solid var(--line-soft); background:var(--sunken);
  font-size:12px; color:var(--ink-faint);
}
.eid{color:var(--ink); font-weight:600; font-size:12.5px}
.chip{
  display:inline-flex; align-items:center; gap:5px; padding:2px 8px;
  border-radius:999px; font-size:11px; font-weight:600; letter-spacing:.02em;
  background:var(--sunken); color:var(--ink-soft); border:1px solid var(--line);
}
.chip.warn{background:var(--warn-bg); color:var(--warn); border-color:transparent}
.chip.gap{background:var(--diff); color:var(--diff-ink); border-color:transparent}
.pair{display:grid; grid-template-columns:1fr 1fr; gap:0}
@media (max-width:900px){ .pair{grid-template-columns:1fr} }
.side{padding:16px 18px 20px; min-width:0}
.side + .side{border-left:1px solid var(--line-soft)}
@media (max-width:900px){ .side + .side{border-left:0; border-top:1px solid var(--line-soft)} }
.sidehead{display:flex; align-items:baseline; gap:8px; margin-bottom:9px; flex-wrap:wrap}
.sidename{font-size:12.5px; font-weight:650; letter-spacing:.01em}
.metrics{margin-left:auto; display:flex; gap:10px; font-size:11px; color:var(--ink-faint)}
.text{font-size:14.5px; line-height:1.68; color:var(--ink); overflow-wrap:break-word}
.text.small{font-size:13.5px}
mark.d{background:var(--diff); color:var(--diff-ink); border-radius:2px; padding:.5px 1px}
.lonely{margin:0 0 9px; font-size:11px; color:var(--ink-faint); display:flex;
        flex-wrap:wrap; gap:5px; align-items:center}
.tchip{background:var(--sunken); border:1px solid var(--line); border-radius:5px;
       padding:1px 6px; color:var(--ink-soft); font-weight:600}
.missing{color:var(--ink-faint); font-style:italic; font-size:13.5px}
.allbtn{
  font:inherit; font-size:12px; background:none; border:0; cursor:pointer;
  color:var(--ink-soft); text-decoration:underline; text-underline-offset:3px; padding:0;
}
.others{padding:0 18px 18px; display:none; flex-direction:column; gap:14px}
.others.open{display:flex}
.other{border-top:1px solid var(--line-soft); padding-top:13px}
.empty{padding:60px 0; text-align:center; color:var(--ink-faint)}
footer{border-top:1px solid var(--line); padding:22px 0 40px; color:var(--ink-faint); font-size:12.5px}
@media (prefers-reduced-motion:reduce){ *{animation:none!important; transition:none!important} }
"""


JS = r"""
const $ = s => document.querySelector(s);
const HUE = {amber:'--amber',indigo:'--indigo',violet:'--violet',slate:'--slate',steel:'--steel'};
const esc = s => s.replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const fold = w => w.normalize('NFKD').replace(/[̀-ͯ]/g,'')
                   .toLowerCase().replace(/[^a-z0-9]+/g,'');

/* Diff mot à mot par plus longue sous-séquence commune. Écrit ici plutôt que
   pré-calculé côté Python : dix paires de moteurs pré-rendues pèseraient dix
   fois le corpus, et on veut pouvoir comparer n'importe quel couple. */
function wordDiff(a, b){
  const A = a.split(/\s+/).filter(Boolean), B = b.split(/\s+/).filter(Boolean);
  const fa = A.map(fold), fb = B.map(fold);
  const n = fa.length, m = fb.length;
  if (n * m > 4e6) return [esc(a), esc(b)];      // garde-fou sur les très longues
  const L = Array.from({length:n+1}, () => new Uint32Array(m+1));
  for (let i=n-1;i>=0;i--) for (let j=m-1;j>=0;j--)
    L[i][j] = fa[i]===fb[j] ? L[i+1][j+1]+1 : Math.max(L[i+1][j], L[i][j+1]);
  const oa=[], ob=[]; let i=0, j=0;
  const push=(arr,w,same)=>arr.push(same?esc(w):'<mark class="d">'+esc(w)+'</mark>');
  while(i<n && j<m){
    if(fa[i]===fb[j]){ push(oa,A[i],1); push(ob,B[j],1); i++; j++; }
    else if(L[i+1][j] >= L[i][j+1]){ push(oa,A[i],0); i++; }
    else { push(ob,B[j],0); j++; }
  }
  while(i<n) push(oa,A[i++],0);
  while(j<m) push(ob,B[j++],0);
  return [oa.join(' '), ob.join(' ')];
}

function agreement(a, b){
  if(!a || !b) return 0;
  const A=a.split(/\s+/).map(fold).filter(Boolean), B=b.split(/\s+/).map(fold).filter(Boolean);
  const n=A.length,m=B.length; if(!n||!m) return 0;
  if(n*m>4e6) return 0.5;
  const L=Array.from({length:n+1},()=>new Uint32Array(m+1));
  for(let i=n-1;i>=0;i--) for(let j=m-1;j>=0;j--)
    L[i][j]= A[i]===B[j] ? L[i+1][j+1]+1 : Math.max(L[i+1][j],L[i][j+1]);
  return 2*L[0][0]/(n+m);
}

const state = {a:null, b:null, sort:'disagree', lang:'', q:'', onlyGap:false};

function engineMeta(k){ return DATA.engines.find(e=>e.key===k); }
function label(k){ const e=engineMeta(k); return e ? e.name+' · '+e.sub : k; }

function metricsHTML(t){
  const bits = [t.words+' mots'];
  if(t.latencyMs) bits.push((t.latencyMs/1000).toFixed(1)+' s');
  if(t.repetition >= 0.15) bits.push('<span style="color:var(--warn)">boucle '+Math.round(t.repetition*100)+'%</span>');
  const nt = Object.values(t.terms||{}).reduce((s,v)=>s+v,0);
  if(nt) bits.push(nt+' termes');
  return bits.join(' &middot; ');
}

/* Les termes qu'aucun autre moteur n'a produits sur cette dictée : la piste la
   plus rentable à lire, puisqu'elle isole soit une invention, soit la seule
   graphie correcte. */
function lonelyHTML(t){
  if(!t || !t.lonely || !t.lonely.length) return '';
  return '<div class="lonely mono">seul à écrire '
    + t.lonely.map(x => '<span class="tchip">'+esc(x)+'</span>').join('') + '</div>';
}

function sideHTML(key, marked, t){
  const e = engineMeta(key);
  if(!t) return '<div class="side"><div class="sidehead"><span class="dot" style="background:var(--line)"></span>'
    + '<span class="sidename">'+esc(label(key))+'</span></div>'
    + '<p class="missing">Pas de transcription pour cette dictée.</p></div>';
  return '<div class="side">'
    + '<div class="sidehead"><span class="dot" style="background:var('+HUE[e.hue]+')"></span>'
    + '<span class="sidename">'+esc(e.name)+'</span>'
    + '<span class="esub mono">'+esc(e.sub)+'</span>'
    + '<span class="metrics mono">'+metricsHTML(t)+'</span></div>'
    + lonelyHTML(t)
    + '<p class="text">'+marked+'</p></div>';
}

function entryHTML(en){
  const ta = en.texts[state.a], tb = en.texts[state.b];
  let ma = ta ? esc(ta.text) : '', mb = tb ? esc(tb.text) : '';
  let agr = null;
  if(ta && tb){ [ma, mb] = wordDiff(ta.text, tb.text); agr = agreement(ta.text, tb.text); }
  const d = new Date(en.date);
  const chips = [];
  chips.push('<span class="chip mono">'+en.duration.toFixed(0)+' s</span>');
  chips.push('<span class="chip mono">'+en.language+'</span>');
  if(agr !== null){
    const cls = agr < 0.65 ? 'chip gap mono' : 'chip mono';
    chips.push('<span class="'+cls+'">accord '+Math.round(agr*100)+'%</span>');
  }
  for(const [k,t] of Object.entries(en.texts))
    if(t.repetition >= 0.15)
      chips.push('<span class="chip warn mono">boucle · '+esc(engineMeta(k).sub)+'</span>');

  const others = Object.keys(en.texts).filter(k => k!==state.a && k!==state.b);
  const othersHTML = others.map(k => {
    const t = en.texts[k], e = engineMeta(k);
    return '<div class="other"><div class="sidehead">'
      + '<span class="dot" style="background:var('+HUE[e.hue]+')"></span>'
      + '<span class="sidename">'+esc(e.name)+'</span>'
      + '<span class="esub mono">'+esc(e.sub)+'</span>'
      + '<span class="metrics mono">'+metricsHTML(t)+'</span></div>'
      + lonelyHTML(t)
      + '<p class="text small">'+esc(t.text)+'</p></div>';
  }).join('');

  return '<article class="entry"><div class="ehead">'
    + '<span class="eid mono">'+esc(en.id)+'</span>'
    + chips.join('')
    + (others.length ? '<button class="allbtn" data-id="'+esc(en.id)+'">'
        + others.length+' autre'+(others.length>1?'s':'')+' moteur'+(others.length>1?'s':'')+'</button>' : '')
    + '</div><div class="pair">'
    + sideHTML(state.a, ma, ta) + sideHTML(state.b, mb, tb)
    + '</div>'
    + (others.length ? '<div class="others" id="o-'+esc(en.id)+'">'+othersHTML+'</div>' : '')
    + '</article>';
}

function visible(){
  let rows = DATA.entries.slice();
  if(state.lang) rows = rows.filter(e => e.language === state.lang);
  if(state.q){
    const q = state.q.toLowerCase();
    rows = rows.filter(e => Object.values(e.texts).some(t => t.text.toLowerCase().includes(q)));
  }
  rows.forEach(e => {
    const a = e.texts[state.a], b = e.texts[state.b];
    e._agr = (a && b) ? agreement(a.text, b.text) : null;
  });
  if(state.onlyGap) rows = rows.filter(e => e._agr !== null && e._agr < 0.75);
  const by = {
    disagree: (x,y) => (x._agr ?? 2) - (y._agr ?? 2),
    date:     (x,y) => x.date.localeCompare(y.date),
    longest:  (x,y) => y.duration - x.duration,
  }[state.sort];
  return rows.sort(by);
}

function render(){
  const rows = visible();
  $('#count').textContent = rows.length + ' / ' + DATA.entries.length + ' dictées';
  $('#entries').innerHTML = rows.length
    ? rows.map(entryHTML).join('')
    : '<p class="empty">Aucune dictée ne correspond à ce filtre.</p>';
  document.querySelectorAll('.allbtn').forEach(b => b.addEventListener('click', () => {
    const box = document.getElementById('o-' + b.dataset.id);
    const open = box.classList.toggle('open');
    b.textContent = open ? 'masquer' : b.dataset.lbl;
  }));
  document.querySelectorAll('.allbtn').forEach(b => { b.dataset.lbl = b.textContent; });
}

function boot(){
  const sa = $('#selA'), sb = $('#selB');
  DATA.engines.forEach(e => {
    for(const s of [sa, sb]){
      const o = document.createElement('option');
      o.value = e.key; o.textContent = e.name + ' · ' + e.sub;
      s.appendChild(o);
    }
  });
  state.a = DATA.defaultPair[0]; state.b = DATA.defaultPair[1];
  sa.value = state.a; sb.value = state.b;
  sa.onchange = () => { state.a = sa.value; render(); };
  sb.onchange = () => { state.b = sb.value; render(); };
  $('#sort').onchange = e => { state.sort = e.target.value; render(); };
  $('#lang').onchange = e => { state.lang = e.target.value; render(); };
  $('#q').oninput = e => { state.q = e.target.value.trim(); render(); };
  $('#gap').onclick = e => {
    state.onlyGap = !state.onlyGap;
    e.currentTarget.setAttribute('aria-pressed', String(state.onlyGap));
    render();
  };
  render();
}
document.addEventListener('DOMContentLoaded', boot);
"""


def aggregate(entries: list[dict]) -> list[dict]:
    """Une ligne par moteur, sur les dictées qu'il a réellement transcrites."""
    out = []
    for spec in ENGINES:
        ts = [e["texts"][spec["key"]] for e in entries if spec["key"] in e["texts"]]
        if not ts:
            continue
        lat = sorted(t["latencyMs"] for t in ts if t.get("latencyMs"))
        terms_total = sum(sum(t["terms"].values()) for t in ts)
        out.append({
            **spec,
            "n": len(ts),
            "medianLatency": lat[len(lat) // 2] if lat else None,
            "medianWords": sorted(t["words"] for t in ts)[len(ts) // 2],
            "coverage": round(sum(t["coverage"] for t in ts) / len(ts), 3),
            "loops": sum(1 for t in ts if t["repetition"] >= 0.15),
            "terms": terms_total,
            "distinctTerms": len({k for t in ts for k in t["terms"]}),
            "lonely": sum(len(t["lonely"]) for t in ts),
        })
    return out


def render_html(entries: list[dict]) -> str:
    agg = aggregate(entries)
    keys = {a["key"] for a in agg}
    default = ("voxtral", "crisper:intended") if "voxtral" in keys \
        else ("crisper:intended", "apple")
    total_min = sum(e["duration"] for e in entries) / 60
    langs = sorted({e["language"] for e in entries})
    has_vox = "voxtral" in keys

    maxlat = max([a["medianLatency"] or 0 for a in agg] + [1])
    rows = []
    for a in agg:
        lat = f'{a["medianLatency"]/1000:.2f} s' if a["medianLatency"] else "—"
        barw = round(100 * (a["medianLatency"] or 0) / maxlat)
        rows.append(f"""<tr>
  <td><span class="ename"><span class="dot" style="background:var(--{a['hue']})"></span>
    <span><b>{html.escape(a['name'])}</b> <span class="esub mono">{html.escape(a['sub'])}</span></span></span></td>
  <td class="mono">{a['n']}</td>
  <td class="mono">{lat}</td>
  <td><div class="bar"><i style="width:{barw}%;background:var(--{a['hue']})"></i></div></td>
  <td class="mono">{a['medianWords']}</td>
  <td class="mono">{round(a['coverage']*100)}%</td>
  <td class="mono">{a['terms']} <span class="esub">/ {a['distinctTerms']}</span></td>
  <td class="mono">{a['lonely']}</td>
  <td class="mono">{'<span style="color:var(--warn)">'+str(a['loops'])+'</span>' if a['loops'] else '0'}</td>
</tr>""")

    payload = {
        "engines": [a for a in agg],
        "defaultPair": list(default),
        "entries": [{
            "id": e["id"], "date": e["date"], "duration": round(e["duration"], 1),
            "language": e["language"],
            "texts": {k: {"text": v["text"], "words": v["words"],
                          "latencyMs": v["latencyMs"], "repetition": v["repetition"],
                          "terms": v["terms"], "lonely": v["lonely"]}
                      for k, v in e["texts"].items()},
        } for e in entries],
    }

    vox_note = ("" if has_vox else
                '<p class="note" style="color:var(--warn)"><b>Voxtral n\'est pas '
                'encore dans ce tableau</b> — le banc n\'a pas été exécuté, ou il '
                'n\'a rien produit. La page compare les moteurs déjà présents dans '
                'le corpus.</p>')

    return f"""<!doctype html>
<html lang="fr"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Les moteurs face au corpus</title>
<style>{CSS}</style>
</head><body>

<header class="top">
  <div class="wrap masthead">
    <h1>Les moteurs face au corpus</h1>
    <p class="lede">Les mêmes {len(entries)} dictées, transcrites par chaque moteur.
      Le corpus n'a pas de vérité terrain — ce sont des dictées spontanées, jamais
      retranscrites à la main. Cette page ne classe donc pas : elle met les textes
      côte à côte, marque ce qui diffère, et fait remonter en premier les dictées
      où les moteurs ne s'accordent pas.</p>
    <div class="corpusline mono">
      <span><b>{len(entries)}</b> dictées</span>
      <span><b>{total_min:.0f}</b> minutes</span>
      <span><b>{len(agg)}</b> moteurs</span>
      <span><b>{', '.join(langs)}</b></span>
      <span>généré le <b>{datetime.now():%d/%m/%Y à %H:%M}</b></span>
    </div>
  </div>
</header>

<div class="wrap">
<section class="summary">
  <h2>Vue d'ensemble</h2>
  <p class="note"><b>Couverture</b> — longueur du texte rapportée au plus long
    produit sur la même dictée ; nettement en dessous, le moteur avale des mots.
    <b>Termes</b> — mots techniques à l'orthographe et à la casse exactes : total,
    puis nombre de termes distincts. <b>Isolés</b> — termes qu'un seul moteur a
    produits sur une dictée où deux autres au moins ont travaillé ; le signal
    coupe dans les deux sens, soit le moteur a inventé le mot, soit il est le seul
    à l'avoir bien écrit, et c'est précisément là qu'il faut aller lire.
    <b>Boucles</b> — dictées contenant un passage où le vocabulaire s'effondre,
    au seuil que le moteur applique lui-même en production (32 mots glissants,
    25 % de diversité).</p>
  {vox_note}
  <div class="tablewrap"><table>
    <thead><tr>
      <th>Moteur</th><th>Dictées</th><th>Latence méd.</th><th></th>
      <th>Mots méd.</th><th>Couverture</th><th>Termes</th><th>Isolés</th><th>Boucles</th>
    </tr></thead>
    <tbody>{''.join(rows)}</tbody>
  </table></div>
</section>
</div>

<div class="controls"><div class="wrap ctlrow">
  <div class="field"><label for="selA">Gauche</label><select id="selA"></select></div>
  <div class="field"><label for="selB">Droite</label><select id="selB"></select></div>
  <div class="field"><label for="sort">Trier</label>
    <select id="sort">
      <option value="disagree">Désaccord d'abord</option>
      <option value="date">Chronologique</option>
      <option value="longest">Plus longues d'abord</option>
    </select></div>
  <div class="field"><label for="lang">Langue</label>
    <select id="lang"><option value="">toutes</option>
      {''.join(f'<option value="{l}">{l}</option>' for l in langs)}
    </select></div>
  <div class="seg"><button id="gap" aria-pressed="false">Désaccord marqué seulement</button></div>
  <div class="field"><label for="q" class="sr">Chercher</label>
    <input type="search" id="q" placeholder="chercher dans les textes…"></div>
  <span class="count mono" id="count"></span>
</div></div>

<div class="wrap"><div class="entries" id="entries"></div></div>

<footer><div class="wrap">
  Corpus de Caspr — surligné en jaune : les mots où les deux moteurs choisis
  divergent. Aucun audio n'est embarqué dans cette page.
</div></footer>

<script>const DATA = {json.dumps(payload, ensure_ascii=False)};</script>
<script>{JS}</script>
</body></html>"""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(Path(__file__).parent / "comparaison-moteurs.html"))
    args = ap.parse_args()
    entries = load()
    out = Path(args.out)
    out.write_text(render_html(entries), encoding="utf-8")
    size = out.stat().st_size / 1e6
    print(f"{len(entries)} dictées → {out} ({size:.1f} Mo)")
    for a in aggregate(entries):
        lat = f"{a['medianLatency']/1000:.2f}s" if a["medianLatency"] else "—"
        print(f"  {a['name']:16s} {a['sub']:22s} n={a['n']:3d}  lat={lat:>7s}  "
              f"couv={a['coverage']*100:3.0f}%  termes={a['terms']:4d}  boucles={a['loops']}")


if __name__ == "__main__":
    main()
