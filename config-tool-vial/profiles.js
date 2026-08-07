// Device profiles describe the inputs of a device as a simple, ordered list so
// the UI can show them and let you program each one. HID Remapper merges inputs
// from every connected device, so a profile is about identification, labels and
// sensible defaults, not about gating which device is active. Adding a device =
// adding a profile here; no firmware change.

// Elecom Huge / Huge Plus. Button numbers follow the device's HID usages
// (source_0). Physical hints come from the real layout:
//   Thumb side: scroll wheel + middle click (Btn 3) + tilt, the large left
//     click (Btn 1) below it, and the half-size Back/Forward pair (Btn 4/5)
//     above it.
//   Top: Fn1 (Btn 6) in front of Fn2 (Btn 7) on the left of the ball; right of
//     the ball, left to right, right click (Btn 2) then Fn3 (Btn 8).
export const ELECOM_HUGE_PLUS = {
    id: 'elecom_huge_plus',
    name: 'Elecom Huge Plus',
    match: { vendorId: 0x056E, productId: 0x01AB },

    // Plain buttons: directly remappable as mapping sources.
    buttons: [
        { id: 'b1', label: 'Button 1', native: 'Left click', source: '0x00090001', hint: 'Thumb · large lower button' },
        { id: 'b2', label: 'Button 2', native: 'Right click', source: '0x00090002', hint: 'Top · right of ball' },
        { id: 'b3', label: 'Button 3', native: 'Middle / wheel click', source: '0x00090003', hint: 'Thumb · scroll-wheel click' },
        { id: 'b4', label: 'Button 4', native: 'Back', source: '0x00090004', hint: 'Thumb · upper, half-size' },
        { id: 'b5', label: 'Button 5', native: 'Forward', source: '0x00090005', hint: 'Thumb · upper, half-size' },
        { id: 'b6', label: 'Button 6 · Fn1', native: 'Button 6', source: '0x00090006', hint: 'Top · left of ball, front' },
        { id: 'b7', label: 'Button 7 · Fn2', native: 'Button 7', source: '0x00090007', hint: 'Top · left of ball, back' },
        { id: 'b8', label: 'Button 8 · Fn3', native: 'Button 8', source: '0x00090008', hint: 'Top · right of ball' },
    ],

    // Top-view geometry for the visual layout editor (SVG user units).
    // Thumb cluster on the left, ball center-right, front (palm) at bottom.
    // Even margins, consistent gaps, room for a label line on every shape
    // taller than 40 units.
    layout: {
        viewBox: '0 0 480 330',
        outline: { x: 10, y: 14, w: 460, h: 302, rx: 48 },
        ball: { cx: 258, cy: 180, r: 78 },
        wheel: { x: 36, y: 116, w: 44, h: 72, rx: 12, label: 'Wheel' },
        buttons: [
            { id: 'b4', x: 30, y: 56, w: 42, h: 30, tag: 'B4' },
            { id: 'b5', x: 82, y: 56, w: 42, h: 30, tag: 'B5' },
            { id: 'b3', x: 36, y: 116, w: 44, h: 72, tag: 'B3', isWheelClick: true },
            { id: 'b1', x: 30, y: 216, w: 88, h: 66, tag: 'B1' },
            { id: 'b7', x: 140, y: 56, w: 66, h: 44, tag: 'B7' },
            { id: 'b6', x: 140, y: 110, w: 66, h: 44, tag: 'B6' },
            { id: 'b2', x: 352, y: 56, w: 56, h: 44, tag: 'B2' },
            { id: 'b8', x: 414, y: 56, w: 50, h: 44, tag: 'B8' },
        ],
    },

    // Axis inputs. These carry a signed value (one usage for both directions),
    // so per-direction keycodes are produced by the directional-mapping
    // behavior (behaviors.js), not a plain mapping. dir: -1 / +1 = the two ends.
    axes: [
        {
            id: 'cursor', label: 'Cursor', native: 'Pointer movement', kind: 'cursor',
            hint: 'Trackball · X / Y passthrough',
            dirs: [
                { id: 'cur_x', label: 'Cursor X', axis: '0x00010030' },
                { id: 'cur_y', label: 'Cursor Y', axis: '0x00010031' },
            ],
        },
        {
            id: 'wheel', label: 'Scroll wheel', native: 'Wheel up / down', kind: 'scroll',
            axis: '0x00010038', hint: 'Thumb scroll wheel',
            dirs: [
                { id: 'wh_ccw', label: 'Wheel up (CCW)', axis: '0x00010038', dir: -1, native: 'Wheel up' },
                { id: 'wh_cw', label: 'Wheel down (CW)', axis: '0x00010038', dir: +1, native: 'Wheel down' },
            ],
        },
        {
            id: 'tilt', label: 'Tilt', native: 'Wheel left / right', kind: 'tilt',
            axis: '0x000c0238', hint: 'Scroll-wheel tilt',
            dirs: [
                { id: 'tilt_l', label: 'Tilt left', axis: '0x000c0238', dir: -1, native: 'Wheel left' },
                { id: 'tilt_r', label: 'Tilt right', axis: '0x000c0238', dir: +1, native: 'Wheel right' },
            ],
        },
    ],
};

// Corsair Nightsword (v2). Right-handed gaming mouse, top view, front at top.
// The five standard buttons and the wheel/tilt arrive as ordinary mouse
// usages. The other four buttons are programmed by the mouse's ONBOARD
// (iCUE) profile to send keyboard keys, so through the remapper they arrive
// as keyboard usages — remap those usages, not button numbers:
//   Sniper (left side, below the thumb pair) -> Grave `   (0x00070035)
//   Behind the scroll wheel                  -> Backslash (0x00070031)
//   Index fingertip, front                   -> Home      (0x0007004a)
//   Index fingertip, rear                    -> End       (0x0007004d)
// If the onboard profile is ever changed in iCUE, these sources move with it
// (verify with the Monitor / press-to-identify in the wizard).
// No `match` VID/PID: auto-detect PIDs vary across Nightsword revisions and a
// wrong guess is worse than selecting the profile by hand once.
export const CORSAIR_NIGHTSWORD = {
    id: 'corsair_nightsword',
    name: 'Corsair Nightsword',

    buttons: [
        { id: 'b1', label: 'Button 1', native: 'Left click', short: 'Left', source: '0x00090001', hint: 'Main · left plate' },
        { id: 'b2', label: 'Button 2', native: 'Right click', short: 'Right', source: '0x00090002', hint: 'Main · right plate' },
        { id: 'b3', label: 'Button 3', native: 'Middle / wheel click', short: 'Middle', source: '0x00090003', hint: 'Scroll-wheel click' },
        { id: 'b4', label: 'Button 4', native: 'Back', source: '0x00090004', hint: 'Thumb · rear side button' },
        { id: 'b5', label: 'Button 5', native: 'Forward', source: '0x00090005', hint: 'Thumb · front side button' },
        { id: 'sniper', label: 'Sniper', native: 'Grave ` (onboard mapping)', source: '0x00070035', hint: 'Left side · in front of the thumb pair' },
        { id: 'bw', label: 'Behind wheel', native: 'Backslash \\ (onboard mapping)', short: '\\', source: '0x00070031', hint: 'Top · behind the scroll wheel' },
        { id: 'ft1', label: 'Fingertip front', native: 'Home (onboard mapping)', source: '0x0007004a', hint: 'Index fingertip · front edge' },
        { id: 'ft2', label: 'Fingertip rear', native: 'End (onboard mapping)', source: '0x0007004d', hint: 'Index fingertip · behind front' },
    ],

    // Vial/QMK-style key grid: uniform key caps in a loose spatial echo of
    // the hardware, no device silhouette. Coordinates are in key units
    // (x, y, optional w/h). `id` = a profile button; `dir` = a wheel/tilt
    // direction (assignable rows on the Keymap tab). Column story: fingertips
    // and thumb cluster left, left plate, wheel column, right plate; tilt
    // flanks the wheel-down key it sits beside physically.
    layout: {
        keys: [
            { id: 'ft1', x: 0, y: 0, tag: 'F1' },
            { id: 'ft2', x: 0, y: 1, tag: 'F2' },
            { id: 'b1', x: 1, y: 0, h: 2, tag: 'B1' },
            { dir: 'wh_up', x: 2, y: 0, tag: 'W↑' },
            { id: 'b3', x: 2, y: 1, tag: 'B3' },
            { id: 'b2', x: 3, y: 0, h: 2, tag: 'B2' },
            { dir: 'tilt_l', x: 1, y: 2, tag: 'T←' },
            { dir: 'wh_dn', x: 2, y: 2, tag: 'W↓' },
            { dir: 'tilt_r', x: 3, y: 2, tag: 'T→' },
            { id: 'bw', x: 2, y: 3, tag: 'BW' },
            { id: 'sniper', x: 0, y: 2.35, tag: 'SNP' },
            { id: 'b5', x: 0, y: 3.35, tag: 'B5' },
            { id: 'b4', x: 0, y: 4.35, tag: 'B4' },
        ],
    },

    axes: [
        {
            id: 'cursor', label: 'Cursor', native: 'Pointer movement', kind: 'cursor',
            hint: 'Sensor · X / Y passthrough',
            dirs: [
                { id: 'cur_x', label: 'Cursor X', axis: '0x00010030' },
                { id: 'cur_y', label: 'Cursor Y', axis: '0x00010031' },
            ],
        },
        {
            id: 'wheel', label: 'Scroll wheel', native: 'Wheel up / down', kind: 'scroll',
            axis: '0x00010038', hint: 'Main scroll wheel',
            // Standard mouse polarity: wheel up = positive (the Elecom thumb
            // wheel profile is inverted; don't copy dirs between them).
            dirs: [
                { id: 'wh_up', label: 'Wheel up', axis: '0x00010038', dir: +1, native: 'Wheel up' },
                { id: 'wh_dn', label: 'Wheel down', axis: '0x00010038', dir: -1, native: 'Wheel down' },
            ],
        },
        {
            id: 'tilt', label: 'Tilt', native: 'Wheel left / right', kind: 'tilt',
            axis: '0x000c0238', hint: 'Scroll-wheel tilt',
            dirs: [
                { id: 'tilt_l', label: 'Tilt left', axis: '0x000c0238', dir: -1, native: 'Wheel left' },
                { id: 'tilt_r', label: 'Tilt right', axis: '0x000c0238', dir: +1, native: 'Wheel right' },
            ],
        },
    ],
};

export const profiles = {
    [CORSAIR_NIGHTSWORD.id]: CORSAIR_NIGHTSWORD,
    [ELECOM_HUGE_PLUS.id]: ELECOM_HUGE_PLUS,
};

export function defaultProfile() {
    // The device currently on the desk. The Elecom profile stays available
    // in Settings -> Device profile.
    return CORSAIR_NIGHTSWORD;
}

export function profileForVidPid(vendorId, productId) {
    for (const p of Object.values(profiles)) {
        if (p.match && p.match.vendorId === vendorId && p.match.productId === productId) {
            return p;
        }
    }
    return null;
}

// --- custom profiles (created by the new-device wizard) ----------------------
// Stored in localStorage; exported project files embed the profile so they
// stay portable across machines.

const CUSTOM_KEY = 'hrv-custom-profiles';

export function loadCustomProfiles() {
    try {
        const raw = localStorage.getItem(CUSTOM_KEY);
        const list = raw ? JSON.parse(raw) : [];
        return Array.isArray(list) ? list.filter((p) => p && p.id && Array.isArray(p.buttons)) : [];
    } catch {
        return [];
    }
}

export function saveCustomProfile(profile) {
    const list = loadCustomProfiles().filter((p) => p.id !== profile.id);
    list.push(profile);
    localStorage.setItem(CUSTOM_KEY, JSON.stringify(list));
}

export function deleteCustomProfile(id) {
    localStorage.setItem(CUSTOM_KEY, JSON.stringify(loadCustomProfiles().filter((p) => p.id !== id)));
}

export function allProfiles() {
    const out = { ...profiles };
    for (const p of loadCustomProfiles()) out[p.id] = p;
    return out;
}

export function profileById(id) {
    return allProfiles()[id] || null;
}

// Generic top-view layout for wizard-made profiles: buttons in a grid on the
// left, a ball circle on the right when the device reports cursor axes.
export function genericLayout(buttonCount, hasCursor) {
    const perRow = 4, bw = 74, bh = 42, gapX = 14, gapY = 16, x0 = 26, y0 = 40;
    const rows = Math.max(1, Math.ceil(buttonCount / perRow));
    const gridW = perRow * (bw + gapX) - gapX;
    const height = Math.max(200, y0 + rows * (bh + gapY) + 30);
    const width = x0 + gridW + (hasCursor ? 190 : 30);
    const buttons = [];
    for (let i = 0; i < buttonCount; i++) {
        buttons.push({
            id: 'b' + (i + 1),
            x: x0 + (i % perRow) * (bw + gapX),
            y: y0 + Math.floor(i / perRow) * (bh + gapY),
            w: bw, h: bh, tag: 'B' + (i + 1),
        });
    }
    const layout = {
        viewBox: `0 0 ${width} ${height}`,
        outline: { x: 8, y: 12, w: width - 16, h: height - 24, rx: 30 },
        buttons,
    };
    if (hasCursor) {
        const r = Math.min(70, (height - 80) / 2);
        layout.ball = { cx: width - r - 40, cy: height / 2, r };
    }
    return layout;
}

// Builds a wizard profile from named button usages and detected axes.
export function buildCustomProfile(id, name, buttonDefs, axesDetected) {
    const buttons = buttonDefs.map((b, i) => ({
        id: 'b' + (i + 1),
        label: b.label || 'Button ' + (i + 1),
        native: b.native || ('Button ' + ((parseInt(b.source, 16) & 0xFFFF) || (i + 1))),
        source: b.source,
        hint: b.hint || '',
    }));
    const axes = [];
    if (axesDetected.cursor) {
        axes.push({
            id: 'cursor', label: 'Cursor', native: 'Pointer movement', kind: 'cursor',
            hint: 'X / Y passthrough',
            dirs: [
                { id: 'cur_x', label: 'Cursor X', axis: '0x00010030' },
                { id: 'cur_y', label: 'Cursor Y', axis: '0x00010031' },
            ],
        });
    }
    if (axesDetected.wheel) {
        axes.push({
            id: 'wheel', label: 'Scroll wheel', native: 'Wheel up / down', kind: 'scroll',
            axis: '0x00010038', hint: 'Scroll wheel',
            dirs: [
                { id: 'wh_ccw', label: 'Wheel up (CCW)', axis: '0x00010038', dir: -1, native: 'Wheel up' },
                { id: 'wh_cw', label: 'Wheel down (CW)', axis: '0x00010038', dir: +1, native: 'Wheel down' },
            ],
        });
    }
    if (axesDetected.tilt) {
        axes.push({
            id: 'tilt', label: 'Tilt / AC pan', native: 'Wheel left / right', kind: 'tilt',
            axis: '0x000c0238', hint: 'Horizontal wheel',
            dirs: [
                { id: 'tilt_l', label: 'Tilt left', axis: '0x000c0238', dir: -1, native: 'Wheel left' },
                { id: 'tilt_r', label: 'Tilt right', axis: '0x000c0238', dir: +1, native: 'Wheel right' },
            ],
        });
    }
    return {
        id, name, custom: true,
        buttons, axes,
        layout: genericLayout(buttons.length, !!axesDetected.cursor),
    };
}
