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

export const profiles = {
    [ELECOM_HUGE_PLUS.id]: ELECOM_HUGE_PLUS,
};

export function defaultProfile() {
    return ELECOM_HUGE_PLUS;
}

export function profileForVidPid(vendorId, productId) {
    for (const p of Object.values(profiles)) {
        if (p.match && p.match.vendorId === vendorId && p.match.productId === productId) {
            return p;
        }
    }
    return null;
}
