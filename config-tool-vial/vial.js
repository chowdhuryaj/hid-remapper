// Vial-style configurator controller. Manages a project (base keymap +
// high-level behaviors), two tabs (Keymap, Behaviors), and a shared keycode
// picker. Saving compiles base + behaviors into one device config.

import { RemapperDevice, PERSIST_CONFIG_SUCCESS, PERSIST_CONFIG_CONFIG_TOO_BIG, PERSIST_CONFIG_SAFE_MODE } from './device.js?v=5';
import { migrateConfig } from './model.js?v=5';
import {
    NLAYERS, NMACROS, defaultPointerFx, PFX_DIRECTIONS,
    PFX_FLAG_SMOOTHING, PFX_FLAG_ACCEL, PFX_FLAG_WIGGLE, PFX_FLAG_ASC_INVERTED,
    PFX_FLAG_CHORDS, PFX_FLAG_GESTURES, PFX_FLAG_MASTER, PFX_EFFECT_FLAGS,
} from './protocol.js?v=5';
import {
    defaultProfile, profileById, allProfiles, saveCustomProfile, deleteCustomProfile,
    buildCustomProfile,
} from './profiles.js?v=5';
import { usagePage } from './model.js?v=5';
import { getActions, addAction, removeAction, clearActions, explodeLayers } from './keymap.js?v=5';
import { targetCategories, sourceCategories, readableTargetName, readableSourceName, NOTHING_USAGE } from './keycodes.js?v=5';
import { defaultProject, compileProject, projectFromJson, newBehaviorId } from './project.js?v=6';
import { OS_SHORTCUT_CHOICES } from './behaviors.js?v=5';

const TRANSPARENT = '__transparent__';
const ARROWS = { up: '0x00070052', down: '0x00070051', left: '0x00070050', right: '0x0007004f' };
// The desktop app loads this page with ?native=1 and provides a Python HID
// bridge (window.pywebview.api) instead of WebHID.
const NATIVE = new URLSearchParams(location.search).has('native');

let project = defaultProject();
let profile = defaultProfile();
let currentLayer = 0;
let currentTab = 'keymap';
let selected = null;          // keymap slot {source,label}
let focusedAction = null;     // the action (mapping) the picker currently edits
let pickerTarget = null;      // {kind:'slot'} or {kind:'callback', fn, label}
let categories = targetCategories(0);
let currentCat = categories[0].name;
let pointerFx = null;         // live Pointer FX params (fork firmware only)
let pfxSendTimer = null;
let diagTimer = null;
let hudOpen = false;          // desktop-only HUD overlay window
let hudPoll = null;
let hudRecent = [];           // last few pressed inputs for the HUD
// Monitor stream refcount: wizard and HUD both consume it; the device's
// monitor mode stays on while anyone needs it.
const monitorUsers = new Set();
function requestMonitor(tag, on) {
    if (on) monitorUsers.add(tag); else monitorUsers.delete(tag);
    if (dev.isOpen) dev.setMonitorEnabled(monitorUsers.size > 0).catch(() => {});
}
let liveApply = true;         // Vial-style: push keymap/behavior edits to device RAM as you make them
let applyTimer = null;
let applying = false;
let lastApplied = null;       // JSON of the last config pushed/loaded, to skip no-op applies

// --- themes & zoom (Flask/Pipette-style, persisted per browser) ---
// 'classic' clears every override so the stylesheet's light/dark auto-switch
// applies; every other theme pins the full palette.
const THEME_VARS = ['bg', 'surface', 'surface2', 'text', 'muted', 'faint', 'border', 'border2',
    'accent', 'accent-bg', 'accent-text', 'ok', 'ok-bg', 'danger', 'danger-bg'];
const THEMES = {
    aloo: {
        label: 'Aloo (default)',
        // Palette from Aloo the tabby: silver-gray fur neutrals, hazel-gold
        // eyes as accent, teal blanket for OK, pink nose for danger.
        vars: { 'bg': '#26282c', 'surface': '#2f3237', 'surface2': '#383c42', 'text': '#ecedee', 'muted': '#a8adb4', 'faint': '#7c828a', 'border': '#3f444b', 'border2': '#4d535b', 'accent': '#d4b458', 'accent-bg': '#3a3423', 'accent-text': '#ecd9a0', 'ok': '#7fc8a9', 'ok-bg': '#23392f', 'danger': '#e8a0a8', 'danger-bg': '#3d2426' },
    },
    classic: { label: 'Classic (auto light/dark)' },
    light: {
        label: 'Light',
        vars: { 'bg': '#f5f5f4', 'surface': '#ffffff', 'surface2': '#fafaf9', 'text': '#1c1c1a', 'muted': '#6b6b66', 'faint': '#9a9a93', 'border': '#e2e2dd', 'border2': '#cfcfc8', 'accent': '#2563eb', 'accent-bg': '#e8f0fe', 'accent-text': '#14458a', 'ok': '#15803d', 'ok-bg': '#e7f6ec', 'danger': '#b42318', 'danger-bg': '#fdeceb' },
    },
    dark: {
        label: 'Dark',
        vars: { 'bg': '#1a1a18', 'surface': '#242422', 'surface2': '#2c2c29', 'text': '#ececea', 'muted': '#a3a39d', 'faint': '#76766f', 'border': '#36352f', 'border2': '#45443d', 'accent': '#5b9aff', 'accent-bg': '#1c2a44', 'accent-text': '#bcd4ff', 'ok': '#69d28c', 'ok-bg': '#15301f', 'danger': '#f1857c', 'danger-bg': '#3a1714' },
    },
    nord: {
        label: 'Nord',
        vars: { 'bg': '#2e3440', 'surface': '#3b4252', 'surface2': '#434c5e', 'text': '#eceff4', 'muted': '#aeb8cc', 'faint': '#7b869c', 'border': '#4c566a', 'border2': '#596580', 'accent': '#88c0d0', 'accent-bg': '#274552', 'accent-text': '#c8e4ec', 'ok': '#a3be8c', 'ok-bg': '#33402c', 'danger': '#bf616a', 'danger-bg': '#40272b' },
    },
    dracula: {
        label: 'Dracula',
        vars: { 'bg': '#282a36', 'surface': '#313342', 'surface2': '#3a3d4f', 'text': '#f8f8f2', 'muted': '#b6b8c8', 'faint': '#7e8195', 'border': '#44475a', 'border2': '#565a72', 'accent': '#bd93f9', 'accent-bg': '#3b3354', 'accent-text': '#e3d3ff', 'ok': '#50fa7b', 'ok-bg': '#1f4030', 'danger': '#ff5555', 'danger-bg': '#4a2020' },
    },
    solarized: {
        label: 'Solarized Light',
        vars: { 'bg': '#fdf6e3', 'surface': '#fefbf0', 'surface2': '#f5efdc', 'text': '#073642', 'muted': '#657b83', 'faint': '#93a1a1', 'border': '#e6dfc8', 'border2': '#d3cbb0', 'accent': '#268bd2', 'accent-bg': '#e0eef8', 'accent-text': '#0d5a8f', 'ok': '#859900', 'ok-bg': '#eef0d8', 'danger': '#dc322f', 'danger-bg': '#fbe3e2' },
    },
};

function applyTheme(name) {
    const theme = THEMES[name] || THEMES.classic;
    const root = document.documentElement;
    for (const v of THEME_VARS) root.style.removeProperty('--' + v);
    if (theme.vars) {
        for (const [k, val] of Object.entries(theme.vars)) root.style.setProperty('--' + k, val);
    }
    localStorage.setItem('hrv-theme', name);
}

function applyZoom(pct) {
    pct = Math.min(150, Math.max(70, Math.round(pct)));
    document.body.style.zoom = pct / 100;
    localStorage.setItem('hrv-zoom', String(pct));
    return pct;
}

function currentTheme() { return localStorage.getItem('hrv-theme') || 'aloo'; }
function currentZoom() { return parseInt(localStorage.getItem('hrv-zoom') || '100', 10) || 100; }

const dev = new RemapperDevice();
const $ = (id) => document.getElementById(id);
const base = () => project.base;
let nativeBySource = {};
function rebuildNativeBySource() {
    nativeBySource = {};
    for (const b of profile.buttons) nativeBySource[b.source] = b.native;
}
rebuildNativeBySource();
// Safe button lookup for behavior defaults — custom profiles may have fewer
// buttons than the Elecom's 8.
const btnAt = (i) => (profile.buttons[i] || profile.buttons[0]).source;

// --- tiny DOM helper ---
function el(tag, attrs, ...kids) {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
        if (v == null) continue;
        if (k === 'class') e.className = v;
        else if (k === 'text') e.textContent = v;
        else if (k.startsWith('on') && typeof v === 'function') e.addEventListener(k.slice(2), v);
        else if (v === true) e.setAttribute(k, '');
        else e.setAttribute(k, v);
    }
    for (const kid of kids.flat()) {
        if (kid == null) continue;
        e.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
    }
    return e;
}

function init() {
    $('connect').addEventListener('click', connect);
    $('load').addEventListener('click', loadFromDevice);
    $('save').addEventListener('click', saveToDevice);
    $('import').addEventListener('click', () => $('file').click());
    $('export').addEventListener('click', exportJson);
    $('file').addEventListener('change', importJson);
    $('search').addEventListener('input', renderCodes);
    $('mt-keymap').addEventListener('click', () => switchTab('keymap'));
    $('mt-behaviors').addEventListener('click', () => switchTab('behaviors'));
    $('mt-pointer').addEventListener('click', () => switchTab('pointer'));
    $('mt-macros').addEventListener('click', () => switchTab('macros'));
    $('mt-settings').addEventListener('click', () => switchTab('settings'));
    for (const b of document.querySelectorAll('[data-add]')) {
        b.addEventListener('click', () => addBehavior(b.getAttribute('data-add')));
    }
    $('live').addEventListener('change', () => {
        liveApply = $('live').checked;
        if (liveApply) scheduleApply();
    });
    // Vial-style live apply + undo snapshots: any interaction inside the
    // editing surfaces may have mutated the project; schedule a (debounced,
    // diffed) push and a history snapshot. No-op interactions are filtered
    // out by the JSON comparisons.
    for (const id of ['panel-keymap', 'panel-behaviors', 'panel-macros', 'panel-settings', 'picker']) {
        const p = $(id);
        for (const ev of ['change', 'click', 'input']) {
            p.addEventListener(ev, () => { scheduleApply(); scheduleSnapshot(); });
        }
    }
    $('undo').addEventListener('click', undo);
    $('redo').addEventListener('click', redo);
    window.addEventListener('keydown', (e) => {
        if (!(e.metaKey || e.ctrlKey)) return;
        if (isTextEditingTarget(e.target)) return;  // let text fields keep native undo
        const k = e.key.toLowerCase();
        if (k === 'z') { e.preventDefault(); if (e.shiftKey) redo(); else undo(); }
        else if (k === 'y') { e.preventDefault(); redo(); }
    });
    historyInit();

    applyTheme(currentTheme());
    applyZoom(currentZoom());
    renderStatusBar();

    // Single monitor dispatcher — wizard and HUD both feed off it.
    dev.onMonitor = (items) => { wizardMonitor(items); hudMonitor(items); };
    if (NATIVE) {
        $('hudbtn').classList.remove('hidden');
        $('hudbtn').addEventListener('click', toggleHud);
    }

    dev.onDisconnect = onDisconnected;
    if (NATIVE) {
        // Desktop app: auto-connect once the Python bridge is ready.
        if (window.pywebview && window.pywebview.api) connectNative();
        else window.addEventListener('pywebviewready', connectNative);
    } else if ('hid' in navigator) {
        navigator.hid.addEventListener('disconnect', (e) => dev.handleDisconnect(e));
    } else {
        showNotice('WebHID is not available here. Use the desktop app, or Chrome / a Chromium browser.');
    }
    renderAll();
}

// --- device flows ---
async function connect() {
    clearNotice();
    if (NATIVE) return connectNative();
    if (!('hid' in navigator)) {
        showNotice('WebHID is not available here. Use the desktop app, or Chrome / a Chromium browser.');
        return;
    }
    try {
        if (await dev.requestAndOpen()) onConnected();
    } catch (e) { showNotice(errMsg(e)); }
}

async function connectNative() {
    clearNotice();
    try {
        if (await dev.openNative()) onConnected();
    } catch (e) { showNotice(errMsg(e)); }
}

async function loadFromDevice() {
    clearNotice();
    try {
        project = projectFromJson(migrateConfig(await dev.load()));
        // What's on the device is now what the project compiles to — don't
        // immediately re-push it.
        try { lastApplied = JSON.stringify(compileProject(project)); } catch { lastApplied = null; }
        afterProjectChanged();
        showNotice('Loaded the device config as the base keymap. Note: behaviors can’t be read back from a device — keep your project file.', 'info');
    } catch (e) { showNotice(errMsg(e)); }
}

// --- undo / redo ---
// Snapshot stack over the whole project (keymap, behaviors, macros, settings).
// Snapshots are taken debounced after any editing interaction; undo/redo
// restore, re-render and live-apply.
let history = [];
let histIndex = -1;
let histTimer = null;
const HIST_MAX = 100;

function historyInit() {
    history = [JSON.stringify(project)];
    histIndex = 0;
    updateHistoryButtons();
}

function scheduleSnapshot() {
    if (histTimer) clearTimeout(histTimer);
    histTimer = setTimeout(takeSnapshot, 350);
}

function takeSnapshot() {
    histTimer = null;
    if (histIndex < 0) return historyInit();
    const snap = JSON.stringify(project);
    if (snap === history[histIndex]) return;
    history = history.slice(0, histIndex + 1);
    history.push(snap);
    if (history.length > HIST_MAX) history.shift();
    histIndex = history.length - 1;
    updateHistoryButtons();
}

function restoreHistory(i) {
    histIndex = i;
    project = JSON.parse(history[i]);
    afterProjectChanged();  // re-render; its scheduleSnapshot no-ops (state == history entry)
    scheduleApply();
    updateHistoryButtons();
}

function undo() {
    if (histTimer) { clearTimeout(histTimer); takeSnapshot(); }  // capture pending edits so redo can return to them
    if (histIndex > 0) restoreHistory(histIndex - 1);
}

function redo() {
    if (histIndex < history.length - 1) restoreHistory(histIndex + 1);
}

function updateHistoryButtons() {
    if ($('undo')) $('undo').disabled = !(histIndex > 0);
    if ($('redo')) $('redo').disabled = !(histIndex < history.length - 1);
}

function isTextEditingTarget(t) {
    if (!t) return false;
    if (t.tagName === 'TEXTAREA') return true;
    return t.tagName === 'INPUT' && ['text', 'number', 'search'].includes(t.type);
}

// --- Vial-style live apply ---
// Debounced compile-and-push to device RAM. Explicit "Save to device" is what
// persists to flash (power-cycle safe); live applies deliberately never do.
function scheduleApply() {
    if (!liveApply || !dev.isOpen) return;
    if (applyTimer) clearTimeout(applyTimer);
    applyTimer = setTimeout(doApply, 350);
}

async function doApply() {
    if (!dev.isOpen || !liveApply) return;
    if (applying) { scheduleApply(); return; }  // one in flight; retry after
    let compiled;
    try {
        normalizeBehaviors();
        compiled = compileProject(project);
    } catch (e) {
        setApplyState('err', 'Compile: ' + errMsg(e));
        return;
    }
    const snapshot = JSON.stringify(compiled);
    if (snapshot === lastApplied) return;
    applying = true;
    setApplyState('busy', 'Applying…');
    try {
        await dev.apply(compiled);
        lastApplied = snapshot;
        // Mappings may have started (or stopped) using Pointer FX usages —
        // keep the firmware's master gate in sync.
        if (dev.isFork && pointerFx) {
            const before = pointerFx.flags;
            applyPfxMaster();
            if (pointerFx.flags !== before) await dev.savePointerFx(pointerFx);
        }
        setApplyState('ok', 'Applied (not yet persisted — Save to keep across power cycles)');
    } catch (e) {
        setApplyState('err', 'Apply failed: ' + errMsg(e));
    } finally {
        applying = false;
    }
}

function setApplyState(kind, title) {
    const dot = $('applystate');
    if (!dot) return;
    dot.className = 'applystate ' + kind;
    dot.title = title || '';
    if ($('sb-apply')) $('sb-apply').textContent = title || '';
}

function renderStatusBar() {
    if (!$('sb-conn')) return;
    $('sb-conn').textContent = dev.isOpen
        ? (dev.productName + ' · config v' + (dev.configVersion || '?') + (dev.isFork ? ' (Flask fork)' : ' (stock)'))
        : 'Not connected';
    $('sb-profile').textContent = profile ? profile.name : '';
    $('sb-hud').textContent = hudOpen ? 'HUD on' : '';
}

async function saveToDevice() {
    clearNotice();
    // Don't interleave with a live apply already on the wire — the two
    // suspend/rewrite/resume sequences would corrupt each other.
    if (applyTimer) { clearTimeout(applyTimer); applyTimer = null; }
    while (applying) await new Promise((r) => setTimeout(r, 50));
    let compiled;
    try {
        normalizeBehaviors();
        compiled = compileProject(project);
    } catch (e) {
        showNotice('Could not compile behaviors: ' + errMsg(e));
        return;
    }
    applying = true;
    try {
        // Sync the Pointer FX master gate first — persist snapshots device
        // RAM, so the flag must be correct before the save.
        if (dev.isFork && pointerFx) {
            const before = pointerFx.flags;
            applyPfxMaster();
            if (pointerFx.flags !== before) await dev.savePointerFx(pointerFx);
        }
        const code = await dev.save(compiled);
        lastApplied = JSON.stringify(compiled);
        setApplyState('ok', 'Saved and persisted');
        if (code === PERSIST_CONFIG_SUCCESS) flashSaved();
        else if (code === PERSIST_CONFIG_CONFIG_TOO_BIG) showNotice('Configuration is too big to persist on the device.');
        else if (code === PERSIST_CONFIG_SAFE_MODE) showNotice('Device is in safe mode (recovery boot) — persisting is disabled so recovery can’t overwrite your saved config. Power-cycle the device to exit safe mode.');
        else showNotice('Unexpected save result (' + code + ').');
    } catch (e) { showNotice(errMsg(e)); }
    finally { applying = false; }
}

function onConnected() {
    $('status').textContent = (dev.productName || 'HID Remapper') + ' connected' + (dev.isFork ? ' (Flask fork)' : '');
    $('status').className = 'status on';
    $('load').disabled = false;
    $('save').disabled = false;
    renderStatusBar();
    if (monitorUsers.size > 0) dev.setMonitorEnabled(true).catch(() => {});
    // Don't auto-push the local project over an unseen device config; the
    // first edit (or an explicit Save/Load) decides whose state wins.
    lastApplied = null;
    setApplyState('', 'Live apply armed — first edit pushes the whole local project');
    if (dev.isFork) {
        dev.loadPointerFx().then((p) => { pointerFx = p; if (currentTab === 'pointer') renderPointer(); })
            .catch((e) => showNotice('Could not read Pointer FX parameters: ' + errMsg(e)));
        if (dev.forkStatus && dev.forkStatus.safeMode) {
            showNotice('Device is in SAFE MODE: booted with factory defaults, your saved config untouched (and protected — persisting is disabled). Power-cycle the device to return to the saved config.', 'info');
        }
    } else {
        pointerFx = null;
        if (currentTab === 'pointer') renderPointer();
    }
}
function onDisconnected() {
    $('status').textContent = 'Not connected';
    $('status').className = 'status off';
    $('load').disabled = true;
    $('save').disabled = true;
    pointerFx = null;
    renderStatusBar();
    if (currentTab === 'pointer') renderPointer();
}

// --- import / export (project = source of truth) ---
function exportJson() {
    clearNotice();
    normalizeBehaviors();
    // Embed a custom profile so the file opens on machines that lack it.
    const doc = { ...project };
    if (profile.custom) doc.profileData = profile;
    const blob = new Blob([JSON.stringify(doc, null, 4)], { type: 'application/json' });
    const a = el('a', { href: URL.createObjectURL(blob), download: 'hid-remapper-vial-project.json' });
    document.body.appendChild(a); a.click(); document.body.removeChild(a);
    URL.revokeObjectURL(a.href);
}
function importJson() {
    clearNotice();
    const file = $('file').files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (e) => {
        try {
            const json = JSON.parse(e.target.result);
            if (json && json.profileData && json.profileData.id) {
                saveCustomProfile(json.profileData);  // make the embedded profile resolvable
            }
            project = projectFromJson(json);
            afterProjectChanged();
        } catch (err) { showNotice('Could not read that file: ' + errMsg(err)); }
    };
    reader.readAsText(file);
    $('file').value = '';
}

function afterProjectChanged() {
    explodeLayers(base());
    profile = profileById(project.profile) || defaultProfile();
    rebuildNativeBySource();
    categories = targetCategories(base().our_descriptor_number || 0);
    if (!categories.some((c) => c.name === currentCat)) currentCat = categories[0].name;
    selected = null; pickerTarget = null; focusedAction = null;
    renderAll();
    scheduleSnapshot();
}

// --- main tabs ---
function switchTab(tab) {
    currentTab = tab;
    for (const t of ['keymap', 'behaviors', 'pointer', 'macros', 'settings']) {
        $('mt-' + t).classList.toggle('on', tab === t);
        $('panel-' + t).classList.toggle('hidden', tab !== t);
    }
    selected = null; pickerTarget = null; focusedAction = null;
    $('pickfor').textContent = '— select an input or field';
    $('picker').classList.add('disabled');
    $('keyoptions').classList.add('hidden');
    if (tab === 'behaviors') renderBehaviors();
    if (tab === 'pointer') renderPointer();
    if (tab === 'macros') renderMacros();
    if (tab === 'settings') renderSettings();
}

function renderAll() {
    renderTabs();
    renderButtons();
    renderAxes();
    renderBehaviors();
    renderPicker();
}

// --- visual layout diagram (spatial keymap editing) ---
const SVG_NS = 'http://www.w3.org/2000/svg';
function svgEl(tag, attrs, ...kids) {
    const e = document.createElementNS(SVG_NS, tag);
    for (const [k, v] of Object.entries(attrs || {})) {
        if (k.startsWith('on') && typeof v === 'function') e.addEventListener(k.slice(2), v);
        else if (k === 'text') e.textContent = v;
        else e.setAttribute(k, v);
    }
    for (const kid of kids.flat()) if (kid != null) e.append(kid);
    return e;
}

function truncate(s, n) {
    return s.length > n ? s.slice(0, n - 1) + '…' : s;
}

function renderDiagram() {
    const host = $('diagram');
    if (!host) return;
    host.replaceChildren();
    const lay = profile.layout;
    if (!lay) return;

    const svg = svgEl('svg', { viewBox: lay.viewBox });
    const o = lay.outline;
    svg.append(svgEl('rect', { class: 'outline', x: o.x, y: o.y, width: o.w, height: o.h, rx: o.rx }));

    // Ball and wheel are programmed via behaviors (they're axes, not buttons).
    // Wizard-made profiles may have neither.
    const ball = lay.ball;
    if (ball) {
        svg.append(svgEl('circle', {
            class: 'ballshape', cx: ball.cx, cy: ball.cy, r: ball.r,
            onclick: () => switchTab('behaviors'),
        }, svgEl('title', { text: 'Trackball — programmed in the Behaviors tab' })));
        svg.append(svgEl('text', { class: 'biglbl', x: ball.cx, y: ball.cy + 4, 'text-anchor': 'middle', text: 'Ball' }));
    }

    const byId = {};
    for (const b of profile.buttons) byId[b.id] = b;
    for (const s of lay.buttons) {
        const btn = byId[s.id];
        if (!btn) continue;
        const view = assignmentView(btn.source);
        const isSel = selected && selected.source === btn.source;
        const cls = 'btnshape' + (isSel ? ' sel' : '') + (view.cls === 'transparent' ? '' : ' assigned');
        svg.append(svgEl('rect', {
            class: cls, x: s.x, y: s.y, width: s.w, height: s.h, rx: s.rx || 7,
            // The device card is visible on every tab (Flask layout); clicking
            // a control jumps to its editor.
            onclick: () => { if (currentTab !== 'keymap') switchTab('keymap'); selectSlot(btn.source, btn.label); },
        }, svgEl('title', { text: btn.label + ' — ' + view.text })));
        const cx = s.x + s.w / 2;
        const roomy = s.h >= 40;
        svg.append(svgEl('text', { class: 'tag', x: cx, y: s.y + (roomy ? s.h / 2 - 4 : s.h / 2 + 4), 'text-anchor': 'middle', text: s.tag }));
        if (roomy) {
            // Label budget scales with the shape so text never spills out.
            const budget = Math.max(4, Math.floor(s.w / 5.5));
            svg.append(svgEl('text', { class: 'lbl', x: cx, y: s.y + s.h / 2 + 11, 'text-anchor': 'middle', text: truncate(view.text, budget) }));
        }
    }
    if (lay.wheel && lay.wheel.label) {
        svg.append(svgEl('text', { class: 'lbl', x: lay.wheel.x + lay.wheel.w / 2, y: lay.wheel.y - 5, 'text-anchor': 'middle', text: lay.wheel.label }));
    }
    host.append(svg);
}

// --- keymap tab ---
function renderTabs() {
    const tabs = $('tabs');
    tabs.replaceChildren();
    for (let i = 0; i < NLAYERS; i++) {
        tabs.append(el('button', {
            class: 'tab' + (i === currentLayer ? ' on' : ''), text: 'Layer ' + i,
            onclick: () => { currentLayer = i; renderTabs(); renderButtons(); },
        }));
    }
}

function assignmentView(source) {
    const acts = getActions(base(), source, currentLayer);
    const name = (u) => readableTargetName(u, base().our_descriptor_number);
    if (acts.length === 0) return { text: (nativeBySource[source] || 'passthrough'), cls: 'transparent' };
    const tap = acts.find((a) => a.tap);
    const hold = acts.find((a) => a.hold);
    if (tap || hold) {
        const parts = [];
        if (tap) parts.push('Tap ' + name(tap.target_usage));
        if (hold) parts.push('Hold ' + name(hold.target_usage));
        for (const a of acts) if (!a.tap && !a.hold) parts.push(name(a.target_usage));
        return { text: parts.join(' · '), cls: '' };
    }
    const a = acts[0];
    const extra = acts.length > 1 ? ' +' + (acts.length - 1) : '';
    return { text: name(a.target_usage) + (a.sticky ? ' · sticky' : '') + extra, cls: '' };
}

function renderButtons() {
    const list = $('buttons');
    list.replaceChildren();
    for (const b of profile.buttons) {
        const view = assignmentView(b.source);
        const row = el('div', { class: 'row' + (selected && selected.source === b.source ? ' sel' : ''), onclick: () => selectSlot(b.source, b.label) },
            el('div', { class: 'id' }, el('div', { class: 'name', text: b.label }), el('div', { class: 'hint', text: b.hint })),
            el('div', { class: 'native', text: 'Default: ' + b.native }),
            el('div', { class: 'assign ' + view.cls, text: view.text }));
        list.append(row);
    }
    renderDiagram();
}

function renderAxes() {
    const list = $('axes');
    list.replaceChildren();
    for (const a of profile.axes) {
        list.append(el('div', { class: 'row static', onclick: () => switchTab('behaviors') },
            el('div', { class: 'id' }, el('div', { class: 'name', text: a.label }), el('div', { class: 'hint', text: a.hint })),
            el('div', { class: 'native', text: 'Default: ' + a.native }),
            el('span', { class: 'badge', text: 'Behaviors tab' })));
    }
}

function selectSlot(source, label) {
    selected = { source, label };
    pickerTarget = { kind: 'slot', source: false };
    const acts = getActions(base(), source, currentLayer);
    focusedAction = acts.length ? acts[0] : null;
    $('picker').classList.remove('disabled');
    $('pickfor').textContent = '— ' + label + ' on layer ' + currentLayer;
    renderButtons();
    renderKeyOptions();
    renderPicker();
}

// The per-key actions editor (target + sticky/tap/hold flags), HID Remapper's
// native model. Several actions on one key = tap-hold (one Tap, one Hold).
function renderKeyOptions() {
    const box = $('keyoptions');
    if (!selected || !pickerTarget || pickerTarget.kind !== 'slot') {
        box.classList.add('hidden');
        box.replaceChildren();
        return;
    }
    box.classList.remove('hidden');
    box.replaceChildren();
    box.append(el('div', { class: 'koh', text: 'Actions on layer ' + currentLayer + '. Pick a keycode below to set the highlighted action. For tap-hold, add a second action and flag one Tap, one Hold.' }));
    const acts = getActions(base(), selected.source, currentLayer);
    if (acts.length === 0) {
        box.append(el('div', { class: 'hint', text: 'Transparent — passes through to the default. Pick a keycode below to assign.' }));
    }
    for (const a of acts) {
        // Per-action source port: 0 = the input from any device; 1..4 pin the
        // action to a specific hub port (multi-device setups). Renamable in
        // Settings.
        const portSel = selectFrom(
            [['0', 'Any device'], ...[1, 2, 3, 4].map((p) => [String(p), portName(p)])],
            String(a.source_port || 0), (v) => { a.source_port = parseInt(v, 10); renderButtons(); });
        portSel.title = 'Which hub port this input must come from';
        box.append(el('div', { class: 'actionrow' + (a === focusedAction ? ' focus' : '') },
            el('button', { class: 'keybtn', text: readableTargetName(a.target_usage, base().our_descriptor_number), onclick: () => { focusedAction = a; renderKeyOptions(); } }),
            flagBox('Sticky', a.sticky, (v) => { a.sticky = v; renderButtons(); }),
            flagBox('Tap', a.tap, (v) => { a.tap = v; renderButtons(); }),
            flagBox('Hold', a.hold, (v) => { a.hold = v; renderButtons(); }),
            portSel,
            el('button', { class: 'iconbtn', text: '✕', title: 'Remove action', onclick: () => { removeAction(base(), a); if (focusedAction === a) focusedAction = null; renderButtons(); renderKeyOptions(); } })));
    }
    box.append(el('button', { class: 'iconbtn', text: '+ Add action', onclick: () => { focusedAction = addAction(base(), selected.source, currentLayer); renderButtons(); renderKeyOptions(); } }));
}

function flagBox(label, checked, onChange) {
    const cb = el('input', { type: 'checkbox' });
    cb.checked = checked;
    cb.addEventListener('change', () => onChange(cb.checked));
    return el('label', { class: 'flag' }, cb, label);
}

// --- shared keycode picker ---
function pickKeycode(label, fn) {
    openFieldPicker(label, fn, false);
}

// Opens the picker to choose a source input (a trigger) rather than a keycode.
function pickSource(label, fn) {
    openFieldPicker(label, fn, true);
}

function openFieldPicker(label, fn, source) {
    pickerTarget = { kind: 'callback', fn, label, source };
    selected = null;
    focusedAction = null;
    $('keyoptions').classList.add('hidden');
    $('picker').classList.remove('disabled');
    $('pickfor').textContent = '— ' + label;
    renderPicker();
    $('picker').scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

function sourceName(usage) {
    const b = profile.buttons.find((x) => x.source === usage);
    return b ? b.label : readableSourceName(usage);
}

function sourceButton(usage, label, onPick) {
    return el('button', { class: 'keybtn', text: sourceName(usage), onclick: () => pickSource(label, onPick) });
}

// The picker shows target keycodes by default, or source inputs when a behavior
// trigger is being chosen (pickerTarget.source).
function currentCats() {
    return (pickerTarget && pickerTarget.source) ? sourceCategories(profile, dev.extraUsages.source) : categories;
}

function renderPicker() {
    const cats = currentCats();
    if (!cats.some((c) => c.name === currentCat)) currentCat = cats[0].name;
    const chips = $('chips');
    chips.replaceChildren();
    for (const cat of cats) {
        chips.append(el('button', {
            class: 'chip' + (cat.name === currentCat ? ' on' : ''), text: cat.name,
            onclick: () => { currentCat = cat.name; $('search').value = ''; renderPicker(); },
        }));
    }
    renderCodes();
}

function renderCodes() {
    const cats = currentCats();
    const sourceMode = !!(pickerTarget && pickerTarget.source);
    const grid = $('codes');
    grid.replaceChildren();
    if (!sourceMode) {
        grid.append(el('div', { class: 'code special', text: '▽ Transparent', title: 'Remove this layer’s mapping (passthrough)', onclick: () => assign(TRANSPARENT) }));
    }
    const query = $('search').value.trim().toLowerCase();
    let items;
    if (query) {
        items = [];
        for (const cat of cats) for (const it of cat.items) if (it.label.toLowerCase().includes(query)) items.push(it);
    } else {
        items = (cats.find((c) => c.name === currentCat) || cats[0]).items;
    }
    for (const it of items) {
        grid.append(el('div', { class: 'code' + (it.usage === NOTHING_USAGE ? ' special' : ''), text: it.label, title: it.usage, onclick: () => assign(it.usage) }));
    }
    if (query && items.length === 0) grid.append(el('div', { class: 'hint', text: 'No matches' }));
}

function assign(usage) {
    if (pickerTarget && pickerTarget.kind === 'callback') {
        pickerTarget.fn(usage === TRANSPARENT ? null : usage);
        return;
    }
    if (!selected) return;
    if (usage === TRANSPARENT) {
        clearActions(base(), selected.source, currentLayer);
        focusedAction = null;
    } else if (focusedAction) {
        focusedAction.target_usage = usage;
    } else {
        focusedAction = addAction(base(), selected.source, currentLayer, usage);
    }
    renderButtons();
    renderKeyOptions();
}

// --- behaviors tab ---
function buttonSelect(value, onChange) {
    const s = el('select', { onchange: (e) => onChange(e.target.value) });
    for (const b of profile.buttons) {
        const o = el('option', { value: b.source, text: b.label });
        if (b.source === value) o.selected = true;
        s.append(o);
    }
    return s;
}
function selectFrom(opts, value, onChange) {
    const s = el('select', { onchange: (e) => onChange(e.target.value) });
    for (const [val, label] of opts) {
        const o = el('option', { value: val, text: label });
        if (val === value) o.selected = true;
        s.append(o);
    }
    return s;
}
function field(label, ...controls) {
    return el('div', { class: 'field' }, el('label', { text: label }), ...controls);
}
function slider(min, max, step, value, fmt, onInput) {
    const out = el('span', { class: 'readout', text: fmt(value) });
    const r = el('input', { type: 'range', min, max, step, value, oninput: (e) => { const v = Number(e.target.value); out.textContent = fmt(v); onInput(v); } });
    return [r, out];
}
function keyButton(usage, label, onPick) {
    return el('button', { class: 'keybtn', text: usage ? readableTargetName(usage, base().our_descriptor_number) : 'None', onclick: () => pickKeycode(label, onPick) });
}

function emptySlots() {
    const s = {};
    for (const d of PFX_DIRECTIONS) s[d] = null;
    return s;
}

function defaultBehavior(type) {
    const id = newBehaviorId();
    if (type === 'dpi_shift') return { id, type, button: btnAt(4), mode: 'hold', factor: 0.4 };
    if (type === 'cursor_keys') return { id, type, gate: { mode: 'hold', button: btnAt(5) }, sens: 8, keys: { ...ARROWS } };
    if (type === 'chord_set') return { id, type, members: [], chords: [{ id: newBehaviorId(), members: [btnAt(0), btnAt(1)], output: '0x00070006' }] };
    if (type === 'scroll_text') {
        // Default set: digits 1..9, 0 with dwell confirm (200 ms or any
        // button), gated behind a sticky toggle so normal scrolling never
        // types digits by accident.
        const digits = [0x1e, 0x1f, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27]
            .map((c) => '0x000700' + c.toString(16).padStart(2, '0'));
        return {
            id, type, glyphs: digits, scroll: '0x00010038',
            confirm: 'dwell', timeout: 200, accept: btnAt(0),
            gate: { mode: 'sticky', button: btnAt(4) },
            confirmButtons: profile.buttons.map((pb) => pb.source),
        };
    }
    if (type === 'tap_dance') return { id, type, button: btnAt(2), tap1: '0x00070004', tap2: null, tap3: null, hold: '0xfff10001', window: 200 };
    if (type === 'drag_scroll') return { id, type, trigger: btnAt(5), mode: 'sticky', divisorV: 32, divisorH: 40, horizontal: true, invert: false, wiggleToggle: false };
    if (type === 'gesture_set') return { id, type, set: 0, trigger: btnAt(6), mode: 'sticky', slots: { ...emptySlots(), E: '0x0007004f', W: '0x00070050', N: '0x00070052', S: '0x00070051' } };
    if (type === 'wheel_chords') return { id, type, button: 0, slots: emptySlots() };
    if (type === 'shake_action') return { id, type, action: '0xfff10001', sticky: true };
    if (type === 'os_shortcut') return { id, type, trigger: btnAt(3), action: 'copy', os: 'inherit' };
    throw new Error('unknown behavior ' + type);
}

// Add-bar buttons navigate: if a behavior of that type already exists, jump
// to its card instead of silently creating a duplicate. "Duplicate" on the
// card is the explicit way to get a second instance.
function addBehavior(type) {
    switchTab('behaviors');
    const existing = project.behaviors.find((x) => x.type === type);
    if (existing) {
        flashBehavior(existing);
        return;
    }
    const b = defaultBehavior(type);
    b.layers = [0, 1, 2, 3, 4, 5, 6, 7];
    b.enabled = true;
    project.behaviors.push(b);
    renderBehaviors();
    flashBehavior(b);
}

function flashBehavior(b) {
    const card = document.querySelector('[data-bid="' + b.id + '"]');
    if (!card) return;
    card.scrollIntoView({ behavior: 'smooth', block: 'center' });
    card.classList.add('flash');
    setTimeout(() => card.classList.remove('flash'), 1200);
}

function duplicateBehavior(b) {
    const copy = JSON.parse(JSON.stringify(b));
    copy.id = newBehaviorId();
    project.behaviors.splice(project.behaviors.indexOf(b) + 1, 0, copy);
    renderBehaviors();
    flashBehavior(copy);
}

// "Active on layers" selector shared by every behavior — scopes the behavior's
// outputs/triggers to the chosen layers instead of all of them.
function layerField(b) {
    if (!b.layers) b.layers = [0, 1, 2, 3, 4, 5, 6, 7];
    const checks = el('div', { class: 'layerchecks' });
    for (let i = 0; i < NLAYERS; i++) {
        const cb = el('input', { type: 'checkbox' });
        cb.checked = b.layers.includes(i);
        cb.addEventListener('change', () => {
            const s = new Set(b.layers);
            if (cb.checked) s.add(i); else s.delete(i);
            b.layers = [...s].sort((x, y) => x - y);
        });
        checks.append(el('label', {}, cb, 'L' + i));
    }
    return el('div', { class: 'field' }, el('label', { text: 'Active on layers' }), checks);
}
function removeBehavior(b) {
    project.behaviors = project.behaviors.filter((x) => x !== b);
    renderBehaviors();
}

// Keeps each chord set's member list (which defines bit order) in sync with the
// buttons actually used in its rows, in stable profile order.
function normalizeBehaviors() {
    for (const b of project.behaviors) {
        if (b.type === 'chord_set') {
            b.members = profile.buttons.map((x) => x.source).filter((src) => b.chords.some((c) => c.members.includes(src)));
        }
    }
}

function renderBehaviors() {
    const list = $('behaviors-list');
    if (!list) return;
    list.replaceChildren();
    if (project.behaviors.length === 0) {
        list.append(el('div', { class: 'hint', text: 'No behaviors yet. Use “Add behavior” above.' }));
        return;
    }
    for (const b of project.behaviors) list.append(behaviorCard(b));
}

function behaviorCard(b) {
    const titles = {
        dpi_shift: 'DPI shift', cursor_keys: 'Cursor → keys', chord_set: 'Chord',
        scroll_text: 'Scroll-wheel text', tap_dance: 'Tap dance',
        drag_scroll: 'Drag scroll', gesture_set: 'Gestures', wheel_chords: 'Mouse chords', shake_action: 'Shake action',
        os_shortcut: 'OS shortcut',
    };
    const enabled = b.enabled !== false;
    const en = el('input', { type: 'checkbox' });
    en.checked = enabled;
    en.addEventListener('change', () => { b.enabled = en.checked; renderBehaviors(); });
    const head = el('div', { class: 'bhead' },
        el('div', {}, el('span', { class: 'btitle', text: titles[b.type] }), el('span', { class: 'btype', text: b.type })),
        el('div', { style: 'display:flex;gap:8px;align-items:center' },
            el('label', { class: 'flag', title: 'Compile this behavior into the device config' }, en, 'On'),
            el('button', { class: 'iconbtn', text: 'Duplicate', onclick: () => duplicateBehavior(b) }),
            el('button', { class: 'iconbtn', text: 'Remove', onclick: () => removeBehavior(b) })));
    const body = el('div', {});
    if (b.type === 'dpi_shift') body.append(...dpiBody(b));
    else if (b.type === 'cursor_keys') body.append(...cursorBody(b));
    else if (b.type === 'chord_set') body.append(...chordBody(b));
    else if (b.type === 'tap_dance') body.append(...tapDanceBody(b));
    else if (b.type === 'scroll_text') body.append(...scrollBody(b));
    else if (b.type === 'drag_scroll') body.append(...dragScrollBody(b));
    else if (b.type === 'gesture_set') body.append(...gestureSetBody(b));
    else if (b.type === 'wheel_chords') body.append(...wheelChordsBody(b));
    else if (b.type === 'shake_action') body.append(...shakeActionBody(b));
    else if (b.type === 'os_shortcut') body.append(...osShortcutBody(b));
    body.insertBefore(layerField(b), body.firstChild);
    return el('div', { class: 'bcard' + (enabled ? '' : ' offb'), 'data-bid': b.id }, head, body);
}

// Compass-ordered direction slot editor shared by gestures and wheel chords.
// b.slots is keyed by the firmware direction names (E SE S SW W NW N NE).
function directionSlotFields(b, labelPrefix) {
    const display = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return display.map((d) => field(d, keyButton(b.slots[d], labelPrefix + ' ' + d, (u) => { b.slots[d] = u; renderBehaviors(); })));
}

function dragScrollBody(b) {
    const rows = [
        field('Trigger', sourceButton(b.trigger, 'Drag scroll trigger', (u) => { b.trigger = u; renderBehaviors(); })),
        field('Mode', selectFrom([['sticky', 'Toggle (sticky tap)'], ['hold', 'Hold (momentary)']], b.mode, (v) => { b.mode = v; })),
        field('Vertical divisor', ...slider(1, 64, 1, b.divisorV, (v) => String(v), (v) => { b.divisorV = v; })),
        field('Horizontal', flagBox('Scroll sideways too', b.horizontal, (v) => { b.horizontal = v; renderBehaviors(); })),
    ];
    if (b.horizontal) rows.push(field('Horizontal divisor', ...slider(1, 64, 1, b.divisorH, (v) => String(v), (v) => { b.divisorH = v; })));
    rows.push(field('Invert', flagBox('Reverse scroll direction', b.invert, (v) => { b.invert = v; })));
    rows.push(field('Shake toggle', flagBox('Wiggle the ball to toggle (fork firmware)', b.wiggleToggle, (v) => { b.wiggleToggle = v; })));
    rows.push(el('div', { class: 'bcaption', text: 'Ball motion becomes the scroll wheel while active. Runs on stock firmware (1 spare layer + 3 mappings); the shake toggle needs the Flask-parity fork.' }));
    return rows;
}

function gestureSetBody(b) {
    return [
        field('Set', selectFrom([0, 1, 2, 3, 4, 5, 6, 7].map((i) => [String(i), 'Set ' + (i + 1)]), String(b.set), (v) => { b.set = parseInt(v, 10); })),
        field('Trigger', sourceButton(b.trigger, 'Gesture set trigger', (u) => { b.trigger = u; renderBehaviors(); })),
        field('Mode', selectFrom([['sticky', 'Toggle (sticky tap)'], ['hold', 'Hold (momentary)']], b.mode, (v) => { b.mode = v; })),
        ...directionSlotFields(b, 'Gesture'),
        el('div', { class: 'bcaption', text: 'While the set is active the ball stops moving the cursor; each ratchet step of travel fires the key for its direction (empty diagonals fall back to the nearest cardinal). Ratchet distance is tuned in the Pointer tab. Needs the Flask-parity fork firmware.' }),
    ];
}

function wheelChordsBody(b) {
    const wheelKeys = [['WU', 'Wheel ↑'], ['WD', 'Wheel ↓'], ['TL', 'Tilt ←'], ['TR', 'Tilt →']];
    return [
        field('Button', selectFrom(profile.buttons.slice(0, 8).map((pb, i) => [String(i), pb.label]), String(b.button), (v) => { b.button = parseInt(v, 10); })),
        ...directionSlotFields(b, 'Chord'),
        ...wheelKeys.map(([k, label]) => field(label, keyButton(b.slots[k], 'Chord ' + label, (u) => { b.slots[k] = u; renderBehaviors(); }))),
        el('div', { class: 'bcaption', text: 'Hold the button, then roll the ball (8 directions, ratchet) or turn/tilt the wheel (per detent) to fire keys; a quick click still clicks (hold delay in the Pointer tab). Needs the Flask-parity fork firmware.' }),
    ];
}

function shakeActionBody(b) {
    return [
        field('Action', keyButton(b.action, 'Shake action', (u) => { b.action = u; renderBehaviors(); })),
        field('Sticky', flagBox('Toggle on each shake (for layers)', b.sticky, (v) => { b.sticky = v; })),
        el('div', { class: 'bcaption', text: 'Wiggle the ball left-right to fire the action. Detection thresholds are tuned in the Pointer tab. Needs the Flask-parity fork firmware.' }),
    ];
}

function osShortcutBody(b) {
    return [
        field('Trigger', sourceButton(b.trigger, 'Shortcut trigger', (u) => { b.trigger = u; renderBehaviors(); })),
        field('Shortcut', selectFrom(OS_SHORTCUT_CHOICES, b.action, (v) => { b.action = v; })),
        field('OS', selectFrom([['inherit', 'Project default (Settings tab)'], ['mac', 'macOS (⌘)'], ['pc', 'Windows / Linux (Ctrl)']], b.os, (v) => { b.os = v; })),
        el('div', { class: 'bcaption', text: 'Cut/Copy/Paste/Undo/Redo, app switcher, select word/line and friends, with the right modifiers for your OS. Fills one of the top macro slots at compile time; runs on stock firmware.' }),
    ];
}

function dpiBody(b) {
    return [
        field('Button', sourceButton(b.button, 'Trigger button', (u) => { b.button = u; renderBehaviors(); })),
        field('Speed', ...slider(10, 200, 5, Math.round(b.factor * 100), (v) => v + '%', (v) => { b.factor = v / 100; })),
        field('Mode', selectFrom([['hold', 'Hold (momentary)'], ['sticky', 'Sticky tap (toggle)']], b.mode, (v) => { b.mode = v; })),
        el('div', { class: 'bcaption', text: 'Compiles to 1 spare layer + 3 mappings.' }),
    ];
}

function cursorBody(b) {
    const rows = [
        field('Active when', selectFrom([['hold', 'While button held'], ['sticky', 'Sticky toggle'], ['always', 'Always on']], b.gate.mode, (v) => { b.gate.mode = v; renderBehaviors(); })),
    ];
    if (b.gate.mode !== 'always') rows.push(field('Button', sourceButton(b.gate.button, 'Gate button', (u) => { b.gate.button = u; renderBehaviors(); })));
    rows.push(field('Sensitivity', ...slider(1, 20, 1, b.sens, (v) => String(v), (v) => { b.sens = v; })));
    rows.push(field('Up', keyButton(b.keys.up, 'Up key', (u) => { b.keys.up = u; renderBehaviors(); })));
    rows.push(field('Down', keyButton(b.keys.down, 'Down key', (u) => { b.keys.down = u; renderBehaviors(); })));
    rows.push(field('Left', keyButton(b.keys.left, 'Left key', (u) => { b.keys.left = u; renderBehaviors(); })));
    rows.push(field('Right', keyButton(b.keys.right, 'Right key', (u) => { b.keys.right = u; renderBehaviors(); })));
    rows.push(el('div', { class: 'bcaption', text: 'Compiles to up to 5 expression channels + 4 mappings (cursor motion is suppressed while active).' }));
    return rows;
}

function chordBody(b) {
    const rows = [];
    b.chords.forEach((c) => {
        const chips = profile.buttons.map((pb) => el('button', {
            class: 'mchip' + (c.members.includes(pb.source) ? ' on' : ''), text: pb.id.toUpperCase(), title: pb.label,
            onclick: () => {
                if (c.members.includes(pb.source)) c.members = c.members.filter((x) => x !== pb.source);
                else if (c.members.length < 4) c.members.push(pb.source);
                renderBehaviors();
            },
        }));
        rows.push(el('div', { class: 'chordrow' },
            el('div', { class: 'glyphs' }, ...chips),
            el('span', { class: 'hint', text: '→' }),
            keyButton(c.output, 'Chord output', (u) => { c.output = u; renderBehaviors(); }),
            el('button', { class: 'iconbtn', text: '✕', title: 'Delete chord', onclick: () => { b.chords = b.chords.filter((x) => x !== c); renderBehaviors(); } })));
    });
    rows.push(el('button', { class: 'iconbtn', text: '+ Add chord', onclick: () => { b.chords.push({ id: newBehaviorId(), members: [], output: '0x00070028' }); renderBehaviors(); } }));
    rows.push(el('div', { class: 'bcaption', text: 'Press 2–4 buttons together; fires on release. Compiles to 1 expression + 1 mapping per chord.' }));
    return rows;
}

function tapDanceBody(b) {
    return [
        field('Button', sourceButton(b.button, 'Trigger button', (u) => { b.button = u; renderBehaviors(); })),
        field('1 tap', keyButton(b.tap1, '1-tap action', (u) => { b.tap1 = u; renderBehaviors(); })),
        field('2 taps', keyButton(b.tap2, '2-tap action', (u) => { b.tap2 = u; renderBehaviors(); })),
        field('3 taps', keyButton(b.tap3, '3-tap action', (u) => { b.tap3 = u; renderBehaviors(); })),
        field('Hold', keyButton(b.hold, 'Hold action', (u) => { b.hold = u; renderBehaviors(); })),
        field('Window', ...slider(100, 500, 10, b.window, (v) => v + ' ms', (v) => { b.window = v; })),
        el('div', { class: 'bcaption', text: 'Counts taps within the window, then fires the matching action — or Hold if held past the window. Takes over the button (don’t also map it in the keymap). Leave a stage as None to skip it.' }),
    ];
}

function scrollBody(b) {
    const glyphs = el('div', { class: 'glyphs' });
    b.glyphs.forEach((g, i) => {
        glyphs.append(el('span', { class: 'glyphs' },
            keyButton(g, 'Glyph ' + (i + 1), (u) => { b.glyphs[i] = u; renderBehaviors(); }),
            el('button', { class: 'iconbtn', text: '✕', title: 'Remove glyph', onclick: () => { b.glyphs.splice(i, 1); renderBehaviors(); } })));
    });
    glyphs.append(el('button', { class: 'iconbtn', text: '+ Add glyph', onclick: () => { b.glyphs.push('0x00070004'); renderBehaviors(); } }));
    if (!b.gate) b.gate = { mode: 'always', button: btnAt(4) };
    const rows = [
        field('Glyphs', glyphs),
        field('Scroll source', selectFrom([['0x00010038', 'V scroll wheel'], ['0x000c0238', 'Tilt left / right']], b.scroll, (v) => { b.scroll = v; })),
        field('Active when', selectFrom([['sticky', 'Toggled on (sticky tap)'], ['hold', 'While button held'], ['always', 'Always on']], b.gate.mode, (v) => { b.gate.mode = v; renderBehaviors(); })),
    ];
    if (b.gate.mode !== 'always') {
        rows.push(field('Toggle button', sourceButton(b.gate.button, 'Scroll-text toggle', (u) => { b.gate.button = u; renderBehaviors(); })));
    }
    rows.push(field('Confirm', selectFrom([['dwell', 'Pause (timeout) or any button'], ['button', 'Accept button only']], b.confirm || 'dwell', (v) => { b.confirm = v; renderBehaviors(); })));
    if ((b.confirm || 'dwell') === 'dwell') {
        rows.push(field('Timeout', ...slider(50, 1000, 25, b.timeout || 200, (v) => v + ' ms', (v) => { b.timeout = v; })));
        rows.push(el('div', { class: 'bcaption', text: 'Scroll to a glyph; it types after the pause, or instantly when you press any device button (the button still does its own action). E.g. toggle on, spin to a PACS window/level number, pause — it types — toggle off.' }));
    } else {
        rows.push(field('Accept button', sourceButton(b.accept, 'Accept button', (u) => { b.accept = u; renderBehaviors(); })));
        rows.push(el('div', { class: 'bcaption', text: 'Scroll to choose a glyph, press accept to type it.' }));
    }
    rows.push(el('div', { class: 'bcaption', text: 'While toggled on, normal scrolling is suppressed. Compiles to 2 expression channels + 1 mapping per glyph (+1 layer unless “Always on”).' }));
    return rows;
}

// --- macros tab ---
// HID Remapper macro = an ordered list of steps; each step is a set of keycodes
// held together for the macro step duration (Settings), then released. Assign a
// macro to a button as "Macro N" in the keymap picker.
let expandedMacro = null;

function macroPreview(macro) {
    return macro.map((step) => step.map((u) => readableTargetName(u, base().our_descriptor_number)).join('+')).join(' · ');
}

function renderMacros() {
    const list = $('macros-list');
    if (!list) return;
    list.replaceChildren();
    const macros = base().macros;
    for (let i = 0; i < NMACROS; i++) {
        if (!macros[i]) macros[i] = [];
        const macro = macros[i];
        const head = el('div', { class: 'macrohead', onclick: () => { expandedMacro = expandedMacro === i ? null : i; renderMacros(); } },
            el('span', { class: 'mname', text: 'Macro ' + (i + 1) }),
            el('span', { class: 'mprev', text: macro.length ? macroPreview(macro) : '(empty)' }),
            el('span', { class: 'badge', text: expandedMacro === i ? 'Close' : 'Edit' }));
        const row = el('div', { class: 'macrorow' }, head);
        if (expandedMacro === i) row.append(macroEditor(i, macro));
        list.append(row);
    }
}

function macroEditor(i, macro) {
    const box = el('div', { style: 'margin-top:10px' });
    macro.forEach((step, si) => {
        const stepEl = el('div', { class: 'macrostep' }, el('span', { class: 'slabel', text: 'Step ' + (si + 1) }));
        step.forEach((u, ki) => {
            stepEl.append(el('span', { class: 'kchip' },
                readableTargetName(u, base().our_descriptor_number),
                el('span', { class: 'x', text: '✕', title: 'Remove key', onclick: () => { step.splice(ki, 1); if (step.length === 0) macro.splice(si, 1); renderMacros(); } })));
        });
        stepEl.append(el('button', { class: 'iconbtn', text: '+ key', onclick: () => pickKeycode('Macro ' + (i + 1) + ' · step ' + (si + 1), (u) => { if (u) { step.push(u); renderMacros(); } }) }));
        box.append(stepEl);
    });
    box.append(el('div', { style: 'display:flex;gap:8px;flex-wrap:wrap;margin-top:10px' },
        el('button', { class: 'iconbtn', text: '+ Add step', onclick: () => { macro.push([]); renderMacros(); } }),
        el('button', { class: 'iconbtn', text: 'Clear', onclick: () => { macro.length = 0; renderMacros(); } })));

    // Inline "type text -> keystrokes" (window.prompt is unavailable in webviews).
    const textInput = el('input', {
        type: 'text', placeholder: 'Type text, e.g. Hello, world!',
        style: 'flex:1;min-width:200px;font:inherit;font-size:14px;padding:8px 10px;border-radius:var(--radius);border:1px solid var(--border2);background:var(--surface2);color:var(--text)',
    });
    const addText = () => { const t = textInput.value; if (t) { for (const s of textToMacroSteps(t)) macro.push(s); renderMacros(); } };
    textInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); addText(); } });
    box.append(el('div', { style: 'display:flex;gap:8px;flex-wrap:wrap;margin-top:8px;align-items:center' },
        textInput,
        el('button', { class: 'iconbtn', text: 'Add as keystrokes', onclick: addText })));
    box.append(el('div', { class: 'bcaption', text: 'Each step is a set of keys held together, then released. Assign this as “Macro ' + (i + 1) + '” to any button in the Keymap tab.' }));
    return box;
}

// Converts typed text into macro steps (one keystroke per character, with Left
// Shift held for uppercase/shifted symbols). Unsupported characters are skipped.
const KB = (code) => '0x000700' + code.toString(16).padStart(2, '0');
const LEFT_SHIFT = '0x000700e1';
const UNSHIFTED = (() => {
    const m = {};
    for (let i = 0; i < 26; i++) m[String.fromCharCode(97 + i)] = 0x04 + i; // a-z
    const digits = { '1': 0x1e, '2': 0x1f, '3': 0x20, '4': 0x21, '5': 0x22, '6': 0x23, '7': 0x24, '8': 0x25, '9': 0x26, '0': 0x27 };
    const punct = { ' ': 0x2c, '\n': 0x28, '\t': 0x2b, '-': 0x2d, '=': 0x2e, '[': 0x2f, ']': 0x30, '\\': 0x31, ';': 0x33, "'": 0x34, '`': 0x35, ',': 0x36, '.': 0x37, '/': 0x38 };
    return { ...m, ...digits, ...punct };
})();
const SHIFTED = { '!': '1', '@': '2', '#': '3', '$': '4', '%': '5', '^': '6', '&': '7', '*': '8', '(': '9', ')': '0', '_': '-', '+': '=', '{': '[', '}': ']', '|': '\\', ':': ';', '"': "'", '~': '`', '<': ',', '>': '.', '?': '/' };

function textToMacroSteps(text) {
    const steps = [];
    for (const ch of text) {
        if (ch >= 'A' && ch <= 'Z') {
            steps.push([LEFT_SHIFT, KB(UNSHIFTED[ch.toLowerCase()])]);
        } else if (ch in UNSHIFTED) {
            steps.push([KB(UNSHIFTED[ch])]);
        } else if (ch in SHIFTED) {
            steps.push([LEFT_SHIFT, KB(UNSHIFTED[SHIFTED[ch]])]);
        }
    }
    return steps;
}

// --- settings tab ---
function settingNum(label, desc, value, onChange) {
    const inp = el('input', { type: 'number', value });
    inp.addEventListener('change', () => { const v = parseFloat(inp.value); if (!isNaN(v)) onChange(v); });
    return el('div', { class: 'settingrow' }, el('label', { text: label }), inp, el('div', { class: 'desc', text: desc }));
}
function settingSelect(label, desc, opts, value, onChange) {
    const s = selectFrom(opts, value, onChange);
    s.style.width = '160px';
    return el('div', { class: 'settingrow' }, el('label', { text: label }), s, el('div', { class: 'desc', text: desc }));
}
function settingToggle(label, desc, checked, onChange) {
    const cb = el('input', { type: 'checkbox' });
    cb.checked = checked;
    cb.addEventListener('change', () => onChange(cb.checked));
    return el('div', { class: 'settingrow' }, el('label', { text: label }), el('label', { class: 'flag' }, cb, 'Enabled'), el('div', { class: 'desc', text: desc }));
}

function renderSettings() {
    const f = $('settings-form');
    if (!f) return;
    f.replaceChildren();
    const c = base();
    f.append(settingNum('Tap-hold threshold (ms)', 'How long a press must be held to count as “hold” instead of “tap”.', Math.round(c.tap_hold_threshold / 1000), (v) => { c.tap_hold_threshold = Math.max(0, Math.round(v * 1000)); }));
    f.append(settingNum('Partial scroll timeout (ms)', 'How long fractional scroll movement accumulates before being discarded.', Math.round(c.partial_scroll_timeout / 1000), (v) => { c.partial_scroll_timeout = Math.max(0, Math.round(v * 1000)); }));
    f.append(settingNum('Macro step duration (ms)', 'How long each step of a macro is held before the next.', c.macro_entry_duration, (v) => { c.macro_entry_duration = Math.min(256, Math.max(1, Math.round(v))); }));
    f.append(settingNum('GPIO debounce (ms)', 'Debounce time for GPIO buttons (custom boards only).', c.gpio_debounce_time_ms, (v) => { c.gpio_debounce_time_ms = Math.max(0, Math.round(v)); }));

    const checks = el('div', { class: 'layerchecks' });
    for (let i = 0; i < NLAYERS; i++) {
        const cb = el('input', { type: 'checkbox' });
        cb.checked = c.unmapped_passthrough_layers.includes(i);
        cb.addEventListener('change', () => {
            const s = new Set(c.unmapped_passthrough_layers);
            if (cb.checked) s.add(i); else s.delete(i);
            c.unmapped_passthrough_layers = [...s].sort((a, b) => a - b);
        });
        checks.append(el('label', {}, cb, 'L' + i));
    }
    f.append(el('div', { class: 'settingrow' }, el('label', { text: 'Unmapped passthrough' }), checks,
        el('div', { class: 'desc', text: 'Layers on which inputs you haven’t mapped pass through to their default function. Usually all on.' })));

    f.append(settingSelect('Output polling rate', 'Force the polling interval reported to the PC. “Device default” leaves it unchanged.',
        [['0', 'Device default'], ['1', '1000 Hz'], ['2', '500 Hz'], ['4', '250 Hz'], ['8', '125 Hz']], String(c.interval_override), (v) => { c.interval_override = parseInt(v, 10); }));
    f.append(settingToggle('Normalize gamepad inputs', 'Rescale analog gamepad axes to a standard range.', !!c.normalize_gamepad_inputs, (v) => { c.normalize_gamepad_inputs = v; }));
    f.append(settingSelect('Shortcut OS', 'Which modifier set “OS shortcut” behaviors use when set to “Project default”. Changing this recompiles them on the next apply/save.',
        [['mac', 'macOS (⌘)'], ['pc', 'Windows / Linux (Ctrl)']], project.os || 'mac', (v) => { project.os = v; }));

    // --- appearance ---
    f.append(el('h2', { text: 'Appearance', style: 'margin-top:26px' }));
    f.append(settingSelect('Theme', 'Color palette for this tool (stored in this browser).',
        Object.entries(THEMES).map(([k, t]) => [k, t.label]), currentTheme(), (v) => applyTheme(v)));
    const zoomRow = (() => {
        const [r, out] = slider(70, 150, 10, currentZoom(), (v) => v + '%', (v) => applyZoom(v));
        return el('div', { class: 'settingrow' }, el('label', { text: 'Zoom' }), el('span', {}, r, out),
            el('div', { class: 'desc', text: 'UI scale (stored in this browser).' }));
    })();
    f.append(zoomRow);

    // --- device profile ---
    f.append(el('h2', { text: 'Device profile', style: 'margin-top:26px' }));
    const profs = allProfiles();
    f.append(settingSelect('Profile', 'Which device layout the Keymap tab shows. Built-in: Elecom Huge Plus. Add others with the wizard below.',
        Object.values(profs).map((p) => [p.id, p.name + (p.custom ? ' (custom)' : '')]), profile.id, (v) => setProfile(v)));
    if (profile.custom) {
        f.append(el('div', { class: 'settingrow' }, el('label', { text: 'This profile' }),
            el('button', { class: 'iconbtn', text: 'Delete profile', onclick: () => { deleteCustomProfile(profile.id); setProfile(defaultProfile().id); renderSettings(); } }),
            el('div', { class: 'desc', text: 'Removes the custom profile from this browser. The keymap itself is unaffected.' })));
    }
    f.append(el('div', { class: 'settingrow' }, el('label', { text: 'New device' }),
        el('button', { class: 'btn', text: wizard ? 'Wizard in progress below…' : 'New profile from device…', onclick: startWizard }),
        el('div', { class: 'desc', text: 'Build a layout profile for whatever is plugged into the remapper. Works best connected (auto-detects buttons; press a button on the device to identify a row).' })));
    if (wizard) f.append(wizardCard());

    // --- hub ports ---
    f.append(el('h2', { text: 'Hub ports', style: 'margin-top:26px' }));
    if (!project.ports) project.ports = {};
    const portRow = el('div', { class: 'layerchecks' });
    for (const p of [1, 2, 3, 4]) {
        const inp = el('input', { type: 'text', value: project.ports[p] || '', placeholder: 'Port ' + p, style: 'width:110px' });
        inp.addEventListener('change', () => {
            if (inp.value.trim()) project.ports[p] = inp.value.trim();
            else delete project.ports[p];
        });
        portRow.append(inp);
    }
    f.append(el('div', { class: 'settingrow' }, el('label', { text: 'Port names' }), portRow,
        el('div', { class: 'desc', text: 'Plug several devices in through a USB hub and they all feed the same engine (split-keyboard style). Name the ports here; per-action “from device” pickers in the Keymap tab use these names.' })));

    // --- device actions ---
    f.append(el('h2', { text: 'Device', style: 'margin-top:26px' }));
    if (dev.isOpen && dev.forkGeneration >= 2) {
        const diagOut = el('div', { class: 'desc', text: 'Reading…' });
        f.append(el('div', { class: 'settingrow' }, el('label', { text: 'Diagnostics' }), diagOut,
            el('div', { class: 'desc', text: 'Live from the device. “Drops” counts downstream disconnects since power-on — if it climbs while you use the mouse, the mouse↔dongle link is unstable (power or USB timing), not the computer side.' })));
        if (diagTimer) clearInterval(diagTimer);
        let prev = null;
        diagTimer = setInterval(async () => {
            if (currentTab !== 'settings' || !dev.isOpen) { clearInterval(diagTimer); diagTimer = null; return; }
            try {
                const d = await dev.readDiag();
                if (!d) return;
                const rate = prev ? Math.max(0, d.reportsIn - prev.reportsIn) : 0;
                prev = d;
                diagOut.textContent =
                    `Downstream interfaces: ${d.hidItfCount} · reports: ${rate}/s · ` +
                    `drops since power-on: ${d.umounts} · worst tick: ${d.maxTickUs} µs`;
            } catch (e) { /* transient read failure — keep polling */ }
        }, 1000);
    }
    f.append(el('div', { class: 'settingrow' }, el('label', { text: 'Reboot' }),
        el('button', {
            class: 'btn', text: 'Reboot device', disabled: !(dev.isOpen && dev.forkGeneration >= 2) || undefined,
            onclick: async () => {
                try { await dev.reboot(); showNotice('Rebooting — the device will drop off USB and come back in a couple of seconds. Reconnect when it does.', 'info'); }
                catch (e) { showNotice(errMsg(e)); }
            },
        }),
        el('div', { class: 'desc', text: 'Clean restart (fork firmware). Needed after changing the emulated device type; also a handy first fix. Your persisted config is untouched.' })));
    f.append(el('div', { class: 'settingrow' }, el('label', { text: 'Firmware' }),
        el('button', {
            class: 'btn', text: 'Reset into bootloader', disabled: !dev.isOpen || undefined,
            onclick: async () => {
                if (!confirm('Reset into the UF2 bootloader? The device will disconnect and show up as a USB drive (RPI-RP2). Drag a .uf2 firmware file onto it to flash; power-cycle to abort.')) return;
                try { await dev.resetIntoBootsel(); } catch (e) { /* device drops off USB mid-command; that's success */ }
                showNotice('Device is in bootloader mode — look for an “RPI-RP2” drive.', 'info');
            },
        }),
        el('div', { class: 'desc', text: 'Reflash firmware without touching the physical BOOTSEL button. Works on stock and fork firmware.' })));
}

// Renamable hub-port labels (multi-device setups: mouse on port 1, macropad
// on port 2, …). Stored in the project so exports carry them.
function portName(p) {
    return (project.ports && project.ports[p]) || ('Port ' + p);
}

// --- new-device profile wizard ---
let wizard = null;  // { name, buttons: [{source,label,hint}], axes: {cursor,wheel,tilt}, highlight }

function startWizard() {
    const detected = (dev.isOpen && dev.extraUsages.source) || [];
    const btnUsages = detected.filter((u) => usagePage(u) === 0x00090000).sort();
    wizard = {
        name: dev.isOpen ? (dev.productName + ' device') : 'My device',
        buttons: btnUsages.map((u, i) => ({ source: u, label: 'Button ' + (i + 1), hint: '' })),
        axes: {
            cursor: detected.includes('0x00010030'),
            wheel: detected.includes('0x00010038'),
            tilt: detected.includes('0x000c0238'),
        },
        highlight: null,
    };
    if (wizard.buttons.length === 0) {
        wizard.buttons.push({ source: '0x00090001', label: 'Button 1', hint: '' });
    }
    requestMonitor('wizard', true);
    renderSettings();
}

// Press-to-identify: monitor traffic highlights the row of the pressed
// button. Highlight-only updates touch styles directly instead of
// re-rendering — a full render would steal focus from the label input the
// user is typing in every time monitor traffic arrives.
function wizardMonitor(items) {
    if (!wizard) return;
    for (const it of items) {
        if (usagePage(it.usage) === 0x00090000 && it.value) {
            wizard.highlight = it.usage;
            if (!wizard.buttons.some((b) => b.source === it.usage)) {
                wizard.buttons.push({ source: it.usage, label: 'Button ' + (wizard.buttons.length + 1), hint: '' });
                renderSettings();  // new row genuinely needs a render
                return;
            }
            for (const row of document.querySelectorAll('[data-wsrc]')) {
                const on = row.getAttribute('data-wsrc') === it.usage;
                row.style.outline = on ? '2px solid var(--accent)' : '';
                row.style.borderRadius = on ? '6px' : '';
            }
            return;
        }
    }
}

function endWizard() {
    wizard = null;
    requestMonitor('wizard', false);
    renderSettings();
}

function wizardCard() {
    const card = el('div', { class: 'bcard', style: 'margin-top:12px' });
    card.append(el('div', { class: 'bhead' },
        el('div', {}, el('span', { class: 'btitle', text: 'New device profile' })),
        el('button', { class: 'iconbtn', text: 'Cancel', onclick: endWizard })));
    const nameInput = el('input', { type: 'text', value: wizard.name });
    nameInput.addEventListener('change', () => { wizard.name = nameInput.value; });
    card.append(field('Name', nameInput));
    card.append(el('div', { class: 'koh', text: dev.isOpen ? 'Press a button on the device to highlight its row, then label it.' : 'Not connected — add buttons manually; connect to auto-detect instead.' }));
    for (const b of wizard.buttons) {
        const lab = el('input', { type: 'text', value: b.label, style: 'width:150px' });
        lab.addEventListener('change', () => { b.label = lab.value; });
        const hint = el('input', { type: 'text', value: b.hint, placeholder: 'position hint (optional)', style: 'width:190px' });
        hint.addEventListener('change', () => { b.hint = hint.value; });
        card.append(el('div', {
            class: 'actionrow', 'data-wsrc': b.source,
            style: wizard.highlight === b.source ? 'outline:2px solid var(--accent);border-radius:6px' : '',
        },
            el('span', { class: 'badge', text: b.source }), lab, hint,
            el('button', { class: 'iconbtn', text: '✕', onclick: () => { wizard.buttons = wizard.buttons.filter((x) => x !== b); renderSettings(); } })));
    }
    card.append(el('button', {
        class: 'iconbtn', text: '+ Add button', onclick: () => {
            const next = wizard.buttons.length + 1;
            wizard.buttons.push({ source: '0x0009000' + next.toString(16), label: 'Button ' + next, hint: '' });
            renderSettings();
        },
    }));
    card.append(field('Axes',
        flagBox('Cursor', wizard.axes.cursor, (v) => { wizard.axes.cursor = v; }),
        flagBox('Wheel', wizard.axes.wheel, (v) => { wizard.axes.wheel = v; }),
        flagBox('Tilt', wizard.axes.tilt, (v) => { wizard.axes.tilt = v; })));
    card.append(el('div', { style: 'margin-top:12px' },
        el('button', {
            class: 'btn primary', text: 'Create profile', onclick: () => {
                if (wizard.buttons.length === 0) { showNotice('Add at least one button.'); return; }
                const id = 'custom_' + wizard.name.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
                const p = buildCustomProfile(id || 'custom_device', wizard.name, wizard.buttons, wizard.axes);
                saveCustomProfile(p);
                endWizard();
                setProfile(p.id);
                switchTab('keymap');
            },
        })));
    card.append(el('div', { class: 'bcaption', text: 'The wizard makes a generic grid layout for the diagram. Exported project files embed the profile, so they open anywhere.' }));
    return card;
}

function setProfile(id) {
    profile = profileById(id) || defaultProfile();
    project.profile = profile.id;
    rebuildNativeBySource();
    selected = null; pickerTarget = null; focusedAction = null;
    renderAll();
    renderStatusBar();
    scheduleSnapshot();
}

// --- HUD overlay (desktop app only) ---
// Flask-style always-on-top panel: active layers live from the fork firmware
// (Pointer FX page 2), recently pressed inputs from the Monitor stream, and
// the pointer setup at a glance.
async function toggleHud() {
    if (!NATIVE || !window.pywebview) return;
    try {
        const res = await window.pywebview.api.toggle_hud();
        hudOpen = !!(res && res.open);
    } catch (e) { showNotice('HUD: ' + errMsg(e)); return; }
    requestMonitor('hud', hudOpen);
    if (hudOpen && !hudPoll) {
        hudPoll = setInterval(hudTick, 180);
    } else if (!hudOpen && hudPoll) {
        clearInterval(hudPoll);
        hudPoll = null;
    }
    renderStatusBar();
}

function hudMonitor(items) {
    if (!hudOpen) return;
    for (const it of items) {
        if (usagePage(it.usage) === 0x00090000 && it.value) {
            const btn = profile.buttons.find((b) => b.source === it.usage);
            hudRecent.unshift(btn ? btn.label : readableSourceName(it.usage));
            hudRecent = hudRecent.slice(0, 5);
        }
    }
}

async function hudTick() {
    if (!hudOpen || !window.pywebview) return;
    let layers = null;
    // Skip the layer read while a config write is on the wire — feature-report
    // send/read pairs must not interleave.
    if (dev.isOpen && dev.isFork && !applying) {
        try { layers = await dev.readLayerState(); } catch { layers = null; }
    }
    const state = {
        connected: dev.isOpen,
        profile: profile ? profile.name : '',
        layers,
        recent: hudRecent,
        speed: pointerFx ? Math.round(pointerFx.cursor_gain / 10) : null,
        accel: pointerFx ? !!(pointerFx.flags & PFX_FLAG_ACCEL) : null,
        smooth: pointerFx ? !!(pointerFx.flags & PFX_FLAG_SMOOTHING) : null,
        apply: $('sb-apply') ? $('sb-apply').textContent : '',
    };
    try { await window.pywebview.api.hud_push(state); } catch { /* HUD closed */ }
}

// --- pointer tab (fork firmware live tuning) ---
// Parameters live on the device, not in the project: every change is sent
// live (debounced), and "Persist" snapshots them into device flash — the
// same GET/SET/SAVE model Flask uses over its raw-HID channels.
// The firmware's master gate (PFX_FLAG_MASTER): with it clear the device
// runs the exact upstream code path. The tool derives it — never the user:
// on whenever any effect is enabled, pointer speed is non-default, or the
// project maps any Pointer FX usage (0xFFFB…, e.g. autoscroll/gesture
// triggers, which have no effect flag of their own). Off otherwise, so an
// unconfigured device stays byte-for-byte stock in behavior.
function applyPfxMaster() {
    if (!pointerFx) return;
    let needs = (pointerFx.flags & PFX_EFFECT_FLAGS) != 0 ||
        (pointerFx.cursor_gain != null && pointerFx.cursor_gain != 1000);
    if (!needs) {
        try {
            needs = compileProject(project).mappings.some((m) =>
                String(m.source_usage || '').toLowerCase().startsWith('0xfffb') ||
                String(m.target_usage || '').toLowerCase().startsWith('0xfffb'));
        } catch (e) { /* uncompilable project: leave the gate as derived from flags */ }
    }
    if (needs) pointerFx.flags |= PFX_FLAG_MASTER;
    else pointerFx.flags &= ~PFX_FLAG_MASTER;
}

function pfxChanged() {
    if (!dev.isOpen || !dev.isFork || !pointerFx) return;
    if (pfxSendTimer) clearTimeout(pfxSendTimer);
    pfxSendTimer = setTimeout(async () => {
        try {
            applyPfxMaster();
            await dev.savePointerFx(pointerFx);
        } catch (e) { showNotice('Pointer FX write failed: ' + errMsg(e)); }
    }, 150);
}

function pfxToggle(label, desc, bit) {
    const cb = el('input', { type: 'checkbox' });
    cb.checked = !!(pointerFx.flags & bit);
    cb.addEventListener('change', () => {
        if (cb.checked) pointerFx.flags |= bit; else pointerFx.flags &= ~bit;
        pfxChanged();
    });
    return el('div', { class: 'settingrow' }, el('label', { text: label }), el('label', { class: 'flag' }, cb, 'Enabled'), el('div', { class: 'desc', text: desc }));
}

function pfxSlider(label, desc, key, min, max, step, fmt) {
    const [r, out] = slider(min, max, step, pointerFx[key], fmt, (v) => { pointerFx[key] = v; pfxChanged(); });
    return el('div', { class: 'settingrow' }, el('label', { text: label }), el('span', {}, r, out), el('div', { class: 'desc', text: desc }));
}

const x1000 = (v) => (v / 1000).toFixed(2);

function renderPointer() {
    const f = $('pointer-form');
    if (!f) return;
    f.replaceChildren();
    if (!dev.isOpen) {
        f.append(el('div', { class: 'hint', text: 'Connect a device to tune pointer processing. These parameters live on the device itself (Flask-parity fork firmware), not in the project file.' }));
        return;
    }
    if (!dev.isFork) {
        f.append(el('div', { class: 'hint', text: 'This device runs stock HID Remapper firmware. Flash the Flask-parity fork to unlock acceleration, smoothing, gestures, wheel chords, shake detection and autoscroll. (Everything else in this tool still works.)' }));
        return;
    }
    if (!pointerFx) {
        f.append(el('div', { class: 'hint', text: 'Reading parameters from the device…' }));
        dev.loadPointerFx().then((p) => { pointerFx = p; renderPointer(); }).catch((e) => showNotice(errMsg(e)));
        return;
    }

    const h = (t) => el('h2', { text: t, style: 'margin:18px 0 6px' });

    f.append(h('Pointer speed'));
    f.append(pfxSlider('Pointer speed', 'Software “DPI”: scales all cursor movement. The trackball’s real sensor CPI can only be changed with its hardware switch.', 'cursor_gain', 100, 4000, 50, (v) => (v / 10).toFixed(0) + '%'));

    f.append(h('Acceleration'));
    f.append(pfxToggle('Acceleration', 'Sigmoid gain curve on cursor speed (ported from Flask/pd_accel).', PFX_FLAG_ACCEL));
    f.append(pfxSlider('Takeoff', 'How abruptly acceleration kicks in (sigmoid k).', 'accel_takeoff', 500, 10000, 100, x1000));
    f.append(pfxSlider('Growth rate', 'How fast the gain grows past takeoff (sigmoid g).', 'accel_growth', 0, 2000, 50, x1000));
    f.append(pfxSlider('Offset', 'Velocity where acceleration centers (sigmoid s).', 'accel_offset', -10000, 10000, 100, x1000));
    f.append(pfxSlider('Low-speed gain', 'Gain floor at very slow speeds (m). 1.00 = no accel.', 'accel_limit', 0, 1000, 25, x1000));
    f.append(pfxSlider('Device CPI', 'Your trackball’s CPI, for velocity normalization — the converter can’t query it.', 'device_cpi', 100, 8000, 100, String));

    f.append(h('Smoothing'));
    f.append(pfxToggle('Smoothing', 'Per-axis exponential moving average (ported from Flask).', PFX_FLAG_SMOOTHING));
    f.append(pfxSlider('EMA factor', 'Lower = smoother but laggier. Flask default 0.40.', 'smooth_factor', 25, 1000, 25, x1000));
    f.append(pfxSlider('Idle reset', 'Clear the average after this much stillness (ms).', 'smooth_timeout', 0, 1000, 25, String));

    f.append(h('Gestures'));
    f.append(pfxToggle('Gestures', 'Flick the ball to fire keys while a set is latched (Behaviors tab defines sets).', PFX_FLAG_GESTURES));
    f.append(pfxSlider('Ratchet step', 'Ball travel (counts) per fired key.', 'gesture_ratchet', 50, 2000, 25, String));

    f.append(h('Mouse chords'));
    f.append(pfxToggle('Mouse chords', 'Hold a button + roll the ball or turn the wheel for direction keys (Behaviors tab assigns them).', PFX_FLAG_CHORDS));
    f.append(pfxSlider('Chord step', 'Ball travel (counts) per fired key.', 'chord_step', 50, 2000, 25, String));
    f.append(pfxSlider('Hold delay', 'How long a button must be held before the ball is captured (ms). 0 = immediately.', 'chord_hold', 0, 2000, 50, String));

    f.append(h('Shake detection'));
    f.append(pfxToggle('Shake detection', 'Wiggle left-right to fire the “Wiggle triggered” input (Behaviors tab assigns the action).', PFX_FLAG_WIGGLE));
    f.append(pfxSlider('Reversal window', 'Max ms between direction reversals for them to count as one shake.', 'wiggle_switch', 10, 2000, 10, String));
    f.append(pfxSlider('Cooldown', 'Ignore shakes for this long after one triggers (ms).', 'wiggle_cooldown', 50, 2000, 50, String));
    f.append(pfxSlider('Y-quiet threshold', 'Vertical motion (counts) that disqualifies a shake.', 'wiggle_threshold', 0, 20, 1, String));

    f.append(h('Autoscroll'));
    f.append(pfxToggle('Invert direction', 'Flip autoscroll direction.', PFX_FLAG_ASC_INVERTED));
    f.append(pfxSlider('Speed scale', 'Global autoscroll speed (%).', 'asc_speed', 25, 400, 5, (v) => v + '%'));
    f.append(pfxSlider('Jog deadzone', 'Ball deflection (counts) before jog scrolling starts.', 'asc_deadzone', 0, 200, 5, String));
    f.append(pfxSlider('Jog range', 'Deflection (counts) for maximum jog speed.', 'asc_range', 50, 2000, 25, String));
    f.append(el('div', { class: 'desc', text: 'Map buttons to “Autoscroll jog / speed + / speed − / stop” in the Keymap tab (Pointer FX category) to drive autoscroll.' }));

    f.append(el('div', { style: 'display:flex;gap:8px;margin-top:18px' },
        el('button', { class: 'btn', text: 'Re-read from device', onclick: async () => { try { pointerFx = await dev.loadPointerFx(); renderPointer(); } catch (e) { showNotice(errMsg(e)); } } }),
        el('button', {
            class: 'btn primary', text: 'Persist on device', onclick: async () => {
                try {
                    if (pfxSendTimer) { clearTimeout(pfxSendTimer); pfxSendTimer = null; }
                    applyPfxMaster();
                    await dev.savePointerFx(pointerFx);
                    const code = await dev.persistOnly();
                    if (code === PERSIST_CONFIG_SUCCESS) flashSaved();
                    else if (code === PERSIST_CONFIG_SAFE_MODE) showNotice('Device is in safe mode — persisting is disabled. Power-cycle to exit safe mode.');
                    else showNotice('Persist failed (' + code + ').');
                } catch (e) { showNotice(errMsg(e)); }
            },
        })));
    f.append(el('div', { class: 'desc', text: 'Changes apply live as you drag. “Persist on device” keeps them across power cycles (a normal “Save to device” persists them too).' }));
}

// --- helpers ---
let savedTimer = null;
function flashSaved() {
    $('saveok').classList.remove('hidden');
    if (savedTimer) clearTimeout(savedTimer);
    savedTimer = setTimeout(() => $('saveok').classList.add('hidden'), 2500);
}
function showNotice(msg, kind) {
    const n = $('notice');
    n.textContent = msg;
    n.style.background = kind === 'info' ? 'var(--accent-bg)' : 'var(--danger-bg)';
    n.style.color = kind === 'info' ? 'var(--accent-text)' : 'var(--danger)';
    n.classList.remove('hidden');
}
function clearNotice() { $('notice').classList.add('hidden'); }
function errMsg(e) { return (e && e.message) ? e.message : String(e); }

window.vialDebug = { get project() { return project; }, compile: () => { normalizeBehaviors(); return compileProject(project); } };

// A startup crash used to leave a silently dead page (seen in the wild when a
// browser served a stale-cached index.html against fresh modules: a missing
// element made init() throw before any handler was bound). Surface it loudly
// and name the likely fix instead.
function fatal(msg) {
    const div = document.createElement('div');
    div.style.cssText = 'margin:16px;padding:14px;border-radius:8px;background:#fdeceb;color:#b42318;font:14px -apple-system,sans-serif';
    div.textContent = 'The configurator failed to start: ' + msg +
        ' — This usually means your browser cached an old version of the tool. Hard-reload the page (Cmd+Shift+R / Ctrl+Shift+R).';
    document.body.prepend(div);
}
window.addEventListener('error', (e) => fatal(e.message));

try {
    init();
} catch (e) {
    fatal(errMsg(e));
    throw e;
}
