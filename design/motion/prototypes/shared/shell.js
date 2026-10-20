// shared/shell.js: constroi a janela do Racky (sidebar 280, tab bar, workspace, status bar) em HTML,
// e o contrato de timeline com o renderizador (window.DUR, window.MARK, window.seek(t), window.ready).
// Nenhum valor de tempo/curva aqui: tudo vem de MOTION/Motion.
(function () {
  const Q = new URLSearchParams(location.search);
  const RM = Q.get('rm') === '1';
  const VAR = (Q.get('v') || 'A').toUpperCase();
  const clamp = Motion.clamp, lerp = Motion.lerp;

  const P = {
    search: 'M11 11l3.5 3.5M7 12.5a5.5 5.5 0 100-11 5.5 5.5 0 000 11z',
    inbox: 'M2 9l2-6h8l2 6v4H2V9zm0 0h4l1 2h2l1-2h4',
    monitor: 'M2 3h12v8H2zM6 14h4M8 11v3',
    library: 'M3 2v12M7 2v12M11 3l3 11',
    plus: 'M8 3v10M3 8h10',
    list: 'M3 4h10M3 8h10M3 12h10',
    folder: 'M2 4.5h4l1.5 1.5H14v6.5H2z',
    sliders: 'M3 4h10M3 8h10M3 12h10M6 2.5v3M10 6.5v3M5 10.5v3',
    chev: 'M4 6l4 4 4-4',
    chevr: 'M6 4l4 4-4 4',
    x: 'M4 4l8 8M12 4l-8 8',
    gear: 'M8 5.5a2.5 2.5 0 100 5 2.5 2.5 0 000-5zM8 1.5v2M8 12.5v2M1.5 8h2M12.5 8h2M3.4 3.4l1.4 1.4M11.2 11.2l1.4 1.4M3.4 12.6l1.4-1.4M11.2 4.8l1.4-1.4',
    panel: 'M2 3h12v10H2zM10 3v10',
    bell: 'M4 11V7a4 4 0 118 0v4l1 1H3zM6.5 14h3',
    git: 'M5 3v10M5 6a2 2 0 002 2h2a2 2 0 002-2V5',
    check: 'M3.5 8.5l3 3 6-7',
  };
  function ic(n, s = 16, extra = '') {
    return `<svg class="ic" width="${s}" height="${s}" viewBox="0 0 16 16" ${extra}><path d="${P[n]}"/></svg>`;
  }
  // logo Claude (estrela de 8 pontas), cor da marca
  function claudeLogo(s = 16) {
    let d = '';
    for (let i = 0; i < 8; i++) { const a = i * Math.PI / 4; d += `M12 12L${(12 + 10.5 * Math.cos(a)).toFixed(2)} ${(12 + 10.5 * Math.sin(a)).toFixed(2)}`; }
    return `<svg class="lg" width="${s}" height="${s}" viewBox="0 0 24 24"><path d="${d}" stroke="#d97757" stroke-width="3.2" stroke-linecap="round" fill="none"/></svg>`;
  }
  // anel do spinner (2 pt, topo transparente). RM: anel completo parado.
  function ring(color, s = 16) {
    const r = (s - 2) / 2, c = 2 * Math.PI * r;
    return `<svg class="ring" width="${s}" height="${s}" viewBox="0 0 ${s} ${s}"><circle cx="${s / 2}" cy="${s / 2}" r="${r}" fill="none" stroke="${color}" stroke-width="2" stroke-linecap="butt" data-c="${c}" stroke-dasharray="${RM ? 'none' : (c * 0.75) + ' ' + (c * 0.25)}"/></svg>`;
  }
  function checkSvg(color, s = 16) {
    return `<svg class="chk" width="${s}" height="${s}" viewBox="0 0 16 16"><path d="M3.5 8.5l3 3 6-7" fill="none" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" pathLength="1" stroke-dasharray="1" stroke-dashoffset="1"/></svg>`;
  }

  function el(parent, cls, css, html, tag) {
    const d = document.createElement(tag || 'div');
    if (cls) d.className = cls;
    if (css) d.style.cssText = css;
    if (html != null) d.innerHTML = html;
    parent.appendChild(d);
    return d;
  }
  // transform helper: origin em px (ox, oy relativos ao elemento) ou centro
  function T(e, { x = 0, y = 0, s = 1, sx, sy, o = 1, ox, oy } = {}) {
    if (ox != null) e.style.transformOrigin = `${ox}px ${oy}px`;
    e.style.transform = `translate(${x}px,${y}px) scale(${sx != null ? sx : s},${sy != null ? sy : s})`;
    e.style.opacity = o;
    e.style.visibility = o <= 0.001 ? 'hidden' : 'visible';
  }
  function rectIn(e, ref) {
    const a = e.getBoundingClientRect(), b = ref.getBoundingClientRect();
    return { x: a.left - b.left, y: a.top - b.top, w: a.width, h: a.height, cx: a.left - b.left + a.width / 2, cy: a.top - b.top + a.height / 2 };
  }

  const TERM_OLD = `<span class="dim">╭─ Claude Code ───────────────────────────────────────────────────╮</span>
<span class="dim">│</span> <span class="b">✻</span> stacktax-pr-bronze                                              <span class="dim">│</span>
<span class="dim">╰─────────────────────────────────────────────────────────────────╯</span>

<span class="u">&gt; add retry with backoff to the bronze loader and open a PR</span>

<span class="b">●</span> I'll add exponential backoff to <span class="c">bronze/loader.py</span> and cover it with a test.
  <span class="dim">Read(bronze/loader.py)</span>
  <span class="dim">Update(bronze/loader.py)</span>
  <span class="dim">  ⎿  Added 18 lines, removed 3 lines</span>
<span class="b">●</span> Running the test suite to confirm the retry path.
  <span class="dim">Bash(pytest tests/bronze -q)</span>
  <span class="dim">  ⎿  14 passed in 3.82s</span>
<span class="b">●</span> <span class="g">Opened PR #412</span>: checks are running. I'll watch them and report back.

<span class="u">&gt;</span> <span class="cursor"></span>`;
  const TERM_NEW = `<span class="dim">╭─────────────────────────────────────────────────────────────────╮</span>
<span class="dim">│</span> <span class="b">✻</span> Welcome to Claude Code                                         <span class="dim">│</span>
<span class="dim">│</span>   <span class="dim">/Users/gabriel/orca/workspaces/otter/fix-arcgis-pagination</span>      <span class="dim">│</span>
<span class="dim">╰─────────────────────────────────────────────────────────────────╯</span>

<span class="u">&gt; Fix the ArcGIS pagination: the last page is dropped when</span>
<span class="u">  resultOffset lands on a multiple of maxRecordCount.</span>

<span class="b">●</span> I'll start by reading how the crawler pages through the feature layer.
  <span class="dim">Search(resultOffset)</span>
  <span class="dim">  ⎿  Found 4 files</span>`;

  // monta a janela. opts: {launch:true} adiciona workspace novo + slot pendente
  function build(opts = {}) {
    const stage = document.getElementById('stage');
    const sidebar = el(stage, '', '', '', 'div'); sidebar.id = 'sidebar';
    const strip = el(sidebar, 'titlebar-strip');
    ['#ff5f57', '#febc2e', '#28c840'].forEach((c, i) => el(strip, 'tl', `left:${10 + i * 20}px;background:${c}`));
    const toggle = el(strip, '', '', ic('panel', 16)); toggle.id = 'sidebar-toggle';
    const pad = el(sidebar, 'sb-pad');
    el(pad, 'nav-row search', '', `${ic('search', 16)}Search<span class="k">⌘J</span>`);
    el(pad, 'nav-row', '', `${ic('inbox', 16)}Inbox<span class="badge">2</span>`);
    el(pad, 'nav-row', '', `${ic('monitor', 16)}Computers<span class="badge">3</span>`);
    el(pad, 'nav-row', '', `${ic('library', 16)}Library`);
    const head = el(pad, 'proj-head', '', `Projects<span class="tools"><span class="icon-btn">${ic('list', 14)}</span><span class="icon-btn">${ic('sliders', 14)}</span><span class="icon-btn" id="btn-plus">${ic('plus', 14)}</span></span>`);
    el(pad, 'proj-row', '', `${ic('chev', 12)}${ic('folder', 14)}otter`);
    const slot = el(pad, '', '', ''); slot.id = 'pending-slot';
    const cards = el(pad, 'card-wrap');
    const mk = (name, l2, col, sel) => el(cards, 'sess' + (sel ? ' sel' : ''), '', `<div class="l1"><span class="dot" style="background:${col}"></span>${name}<span class="age">5d</span></div><div class="l2">${l2}</div>`);
    const cardSel = mk('stacktax-pr-bronze', 'gabrielgreco1/stacktax  ●↑2  #412', '#00bb7f', true);
    mk('arizona-data-request', 'Opened PR #412; 2 checks passing', '#00bb7f');
    mk('sandperch', 'sandperch', '#737373');
    mk('shaq-ia-dias-slack', 'Artefato da call IA Dias', '#00bb7f');
    el(sidebar, 'sb-footer', '', `${ic('gear', 16)}${ic('bell', 16)}`);

    const main = el(stage, '', '', ''); main.id = 'main';
    const tabbar = el(main, '', '', ''); tabbar.id = 'tabbar';
    const tabs = el(tabbar, '', '', ''); tabs.id = 'tabs';
    const tabOld = el(tabs, 'tab active', '', `<span class="dot" style="background:#00bb7f"></span>Claude<span class="x">${ic('x', 12)}</span>`);
    const tplus = el(tabbar, '', '', ic('plus', 14)); tplus.id = 'tab-plus'; tplus.style.left = '192px';
    const work = el(main, '', '', ''); work.id = 'work';
    const wsOld = el(work, 'ws'); const termOld = el(wsOld, 'term', 'width:1160px', TERM_OLD); termOld.id = 'term-old';
    const sb = el(main, '', '', `<span>stacktax-pr-bronze</span><span>⎇ gabrielgreco1/stacktax</span><span style="margin-left:auto">Claude Code · Skip permissions</span>`); sb.id = 'statusbar';
    return { stage, sidebar, toggle, pad, slot, cardSel, cards, main, tabbar, tabs, tabOld, tplus, work, wsOld, termOld, TERM_NEW, TERM_OLD };
  }

  // contrato de timeline. fn(t) aplica o estado; mark = {NOME: tempo}
  function setup({ dur, marks, seek }) {
    window.DUR = dur; window.MARK = marks || {};
    window.seek = (t) => { seek(t); };
    window.ready = false;
    (document.fonts ? document.fonts.ready : Promise.resolve()).then(() => {
      seek(Number(Q.get('t') || 0));
      window.ready = true;
      if (Q.get('play') === '1') {
        const t0 = performance.now();
        const loop = () => { const t = ((performance.now() - t0) / 1000) % dur; seek(t); requestAnimationFrame(loop); };
        requestAnimationFrame(loop);
      }
    });
  }

  window.Shell = { Q, RM, VAR, ic, claudeLogo, ring, checkSvg, el, T, rectIn, build, setup, clamp, lerp, TERM_NEW, TERM_OLD };
})();
