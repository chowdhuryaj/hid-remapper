// Vial-style configurator controller. Manages a project (base keymap +
// high-level behaviors), two tabs (Keymap, Behaviors), and a shared keycode
// picker. Saving compiles base + behaviors into one device config.

import { RemapperDevice, PERSIST_CONFIG_SUCCESS, PERSIST_CONFIG_CONFIG_TOO_BIG } from './device.js';
import { migrateConfig } from './model.js';
import {
    NLAYERS, NMACROS, defaultPointerFx, PFX_DIRECTIONS,
    PFX_FLAG_SMOOTHING, PFX_FLAG_ACCEL, PFX_FLAG_WIGGLE, PFX_FLAG_ASC_INVERTED,
    PFX_FLAG_CHORDS, PFX_FLAG_GESTURES,
} from './protocol.js';
import { defaultProfile } from './profiles.js?v=2';
import { getActions, addAction, removeAction, clearActions, explodeLayers } from './keymap.js';
import { targetCategories, sourceCategories, readableTargetName, readableSourceName, NOTHING_USAGE } from './keycodes.js';
import { defaultProject, compileProject, projectFromJson, newBehaviorId } from './project.js';
import { OS_SHORTCUT_CHOICES } from './behaviors.js';

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

const dev = new RemapperDevice();
const $ = (id) => document.getElementById(id);
const base = () => project.base;
const nativeBySource = {};
for (const b of profile.buttons) nativeBySource[b.source] = b.native;

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
        afterProjectChanged();
        showNotice('Loaded the device config as the base keymap. Note: behaviors can’t be read back from a device — keep your project file.', 'info');
    } catch (e) { showNotice(errMsg(e)); }
}

async function saveToDevice() {
    clearNotice();
    let compiled;
    try {
        normalizeBehaviors();
        compiled = compileProject(project);
    } catch (e) {
        showNotice('Could not compile behaviors: ' + errMsg(e));
        return;
    }
    try {
        const code = await dev.save(compiled);
        if (code === PERSIST_CONFIG_SUCCESS) flashSaved();
        else if (code === PERSIST_CONFIG_CONFIG_TOO_BIG) showNotice('Configuration is too big to persist on the device.');
        else showNotice('Unexpected save result (' + code + ').');
    } catch (e) { showNotice(errMsg(e)); }
}

function onConnected() {
    $('status').textContent = (dev.productName || 'HID Remapper') + ' connected' + (dev.isFork ? ' (Flask fork)' : '');
    $('status').className = 'status on';
    $('load').disabled = false;
    $('save').disabled = false;
    if (dev.isFork) {
        dev.loadPointerFx().then((p) => { pointerFx = p; if (currentTab === 'pointer') renderPointer(); })
            .catch((e) => showNotice('Could not read Pointer FX parameters: ' + errMsg(e)));
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
    if (currentTab === 'pointer') renderPointer();
}

// --- import / export (project = source of truth) ---
function exportJson() {
    clearNotice();
    normalizeBehaviors();
    const blob = new Blob([JSON.stringify(project, null, 4)], { type: 'application/json' });
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
        try { project = projectFromJson(JSON.parse(e.target.result)); afterProjectChanged(); }
        catch (err) { showNotice('Could not read that file: ' + errMsg(err)); }
    };
    reader.readAsText(file);
    $('file').value = '';
}

function afterProjectChanged() {
    explodeLayers(base());
    categories = targetCategories(base().our_descriptor_number || 0);
    if (!categories.some((c) => c.name === currentCat)) currentCat = categories[0].name;
    selected = null; pickerTarget = null; focusedAction = null;
    renderAll();
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
    const ball = lay.ball;
    svg.append(svgEl('circle', {
        class: 'ballshape', cx: ball.cx, cy: ball.cy, r: ball.r,
        onclick: () => switchTab('behaviors'),
    }, svgEl('title', { text: 'Trackball — programmed in the Behaviors tab' })));
    svg.append(svgEl('text', { class: 'biglbl', x: ball.cx, y: ball.cy + 4, 'text-anchor': 'middle', text: 'Ball' }));

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
            onclick: () => selectSlot(btn.source, btn.label),
        }, svgEl('title', { text: btn.label + ' — ' + view.text })));
        const cx = s.x + s.w / 2;
        const roomy = s.h >= 34;
        svg.append(svgEl('text', { class: 'tag', x: cx, y: s.y + (roomy ? s.h / 2 - 4 : s.h / 2 + 4), 'text-anchor': 'middle', text: s.tag }));
        if (roomy) {
            svg.append(svgEl('text', { class: 'lbl', x: cx, y: s.y + s.h / 2 + 10, 'text-anchor': 'middle', text: truncate(view.text, 13) }));
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
        box.append(el('div', { class: 'actionrow' + (a === focusedAction ? ' focus' : '') },
            el('button', { class: 'keybtn', text: readableTargetName(a.target_usage, base().our_descriptor_number), onclick: () => { focusedAction = a; renderKeyOptions(); } }),
            flagBox('Sticky', a.sticky, (v) => { a.sticky = v; renderButtons(); }),
            flagBox('Tap', a.tap, (v) => { a.tap = v; renderButtons(); }),
            flagBox('Hold', a.hold, (v) => { a.hold = v; renderButtons(); }),
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
    const firstBtn = profile.buttons[0].source;
    if (type === 'dpi_shift') return { id, type, button: profile.buttons[4].source, mode: 'hold', factor: 0.4 };
    if (type === 'cursor_keys') return { id, type, gate: { mode: 'hold', button: profile.buttons[5].source }, sens: 8, keys: { ...ARROWS } };
    if (type === 'chord_set') return { id, type, members: [], chords: [{ id: newBehaviorId(), members: [profile.buttons[0].source, profile.buttons[1].source], output: '0x00070006' }] };
    if (type === 'scroll_text') return { id, type, glyphs: ['0x00070004', '0x00070005', '0x00070006'], scroll: '0x00010038', accept: firstBtn };
    if (type === 'tap_dance') return { id, type, button: profile.buttons[2].source, tap1: '0x00070004', tap2: null, tap3: null, hold: '0xfff10001', window: 200 };
    if (type === 'drag_scroll') return { id, type, trigger: profile.buttons[5].source, mode: 'sticky', divisorV: 32, divisorH: 40, horizontal: true, invert: false, wiggleToggle: false };
    if (type === 'gesture_set') return { id, type, set: 0, trigger: profile.buttons[6] ? profile.buttons[6].source : firstBtn, mode: 'sticky', slots: { ...emptySlots(), E: '0x0007004f', W: '0x00070050', N: '0x00070052', S: '0x00070051' } };
    if (type === 'wheel_chords') return { id, type, button: 0, slots: emptySlots() };
    if (type === 'shake_action') return { id, type, action: '0xfff10001', sticky: true };
    if (type === 'os_shortcut') return { id, type, trigger: profile.buttons[3].source, action: 'copy', os: 'mac' };
    throw new Error('unknown behavior ' + type);
}

function addBehavior(type) {
    const b = defaultBehavior(type);
    b.layers = [0, 1, 2, 3, 4, 5, 6, 7];
    project.behaviors.push(b);
    switchTab('behaviors');
    renderBehaviors();
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
        drag_scroll: 'Drag scroll', gesture_set: 'Gestures', wheel_chords: 'Wheel chords', shake_action: 'Shake action',
        os_shortcut: 'OS shortcut',
    };
    const head = el('div', { class: 'bhead' },
        el('div', {}, el('span', { class: 'btitle', text: titles[b.type] }), el('span', { class: 'btype', text: b.type })),
        el('button', { class: 'iconbtn', text: 'Remove', onclick: () => removeBehavior(b) }));
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
    return el('div', { class: 'bcard' }, head, body);
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
    return [
        field('Button', selectFrom(profile.buttons.slice(0, 8).map((pb, i) => [String(i), pb.label]), String(b.button), (v) => { b.button = parseInt(v, 10); })),
        ...directionSlotFields(b, 'Chord'),
        el('div', { class: 'bcaption', text: 'Hold the button and roll the ball to fire direction keys; a quick click still clicks (hold delay in the Pointer tab). Needs the Flask-parity fork firmware.' }),
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
        field('OS', selectFrom([['mac', 'macOS (⌘)'], ['pc', 'Windows / Linux (Ctrl)']], b.os, (v) => { b.os = v; })),
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
    return [
        field('Glyphs', glyphs),
        field('Scroll source', selectFrom([['0x00010038', 'V scroll wheel'], ['0x000c0238', 'Tilt left / right']], b.scroll, (v) => { b.scroll = v; })),
        field('Accept button', sourceButton(b.accept, 'Accept button', (u) => { b.accept = u; renderBehaviors(); })),
        el('div', { class: 'bcaption', text: 'Scroll to choose a glyph, press accept to type it. Compiles to 2 expression channels + 1 mapping per glyph.' }),
    ];
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
}

// --- pointer tab (fork firmware live tuning) ---
// Parameters live on the device, not in the project: every change is sent
// live (debounced), and "Persist" snapshots them into device flash — the
// same GET/SET/SAVE model Flask uses over its raw-HID channels.
function pfxChanged() {
    if (!dev.isOpen || !dev.isFork || !pointerFx) return;
    if (pfxSendTimer) clearTimeout(pfxSendTimer);
    pfxSendTimer = setTimeout(async () => {
        try { await dev.savePointerFx(pointerFx); }
        catch (e) { showNotice('Pointer FX write failed: ' + errMsg(e)); }
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

    f.append(h('Wheel chords'));
    f.append(pfxToggle('Wheel chords', 'Hold a button + roll the ball for direction keys (Behaviors tab assigns them).', PFX_FLAG_CHORDS));
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
                    await dev.savePointerFx(pointerFx);
                    const code = await dev.persistOnly();
                    if (code === PERSIST_CONFIG_SUCCESS) flashSaved(); else showNotice('Persist failed (' + code + ').');
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

init();
