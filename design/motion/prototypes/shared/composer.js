// shared/composer.js: overlay "New Session" (03 §6, DS §12.17), 560 pt, centrado na janela.
(function () {
  const { el, ic, claudeLogo } = Shell;
  function build(stage) {
    const overlay = el(stage, '', '', ''); overlay.id = 'overlay';
    const scrim = el(overlay, '', '', ''); scrim.id = 'scrim';
    const card = el(overlay, 'card', '', ''); card.id = 'composer';
    el(card, '', '', '', 'h2').textContent = 'New Session';
    const g1 = el(card, 'grp', '', `
      <div class="fld"><div class="lbl">Project</div><div class="ctl">${ic('folder', 14)}otter<span class="mono" style="margin-left:8px">~/orca/workspaces/otter</span><span class="r">${ic('chev', 14)}</span></div></div>
      <div class="fld"><div class="lbl">Where</div><div class="seg"><div class="on">New Worktree</div><div>Existing Worktree</div><div>Main Checkout</div></div></div>`);
    const g2 = el(card, 'grp', '', `
      <div class="fld"><div class="lbl">Create from<span class="hint">origin/main ⌄</span></div><div class="ctl" style="color:var(--text3)">Branch name, #123 or a PR / issue URL</div></div>`);
    const g3 = el(card, 'grp', '', `
      <div class="fld" style="display:flex;gap:12px"><div style="flex:1"><div class="lbl">Agent</div><div class="ctl">${claudeLogo(14)}Claude Code<span class="r">${ic('chev', 14)}</span></div></div>
        <div style="flex:1"><div class="lbl">Profile</div><div class="ctl">Claude · Skip permissions<span class="r">${ic('chev', 14)}</span></div></div></div>
      <div class="fld"><div class="lbl">Prompt</div><div class="prompt" id="prompt">Fix the ArcGIS pagination: the last page is dropped when resultOffset lands on a multiple of maxRecordCount.<div class="focusring" id="focusring"></div></div></div>
      <div class="adv">${ic('chevr', 12)}Advanced</div>
      <div class="summary">claude --dangerously-skip-permissions "Fix the ArcGIS pagination…" in ~/orca/workspaces/otter/fix-arcgis-pagination</div>
      <div class="footer"><div class="switch"><i></i>Create More</div><div class="btn outline">Cancel <span class="kc">esc</span></div><div class="btn primary" id="btn-create">Create Session <span class="kc">⌘↵</span></div></div>`);
    return { overlay, scrim, card, g1, g2, g3, groups: [g1, g2, g3] };
  }
  window.Composer = { build };
})();
