// RemapperDevice: a clean, UI-agnostic wrapper around a connected HID Remapper.
//
// Ported from the stock tool's config-tool-web/code.js (open_device,
// load_from_device, save_to_device, get_usages_from_device, the monitor input
// report handling). The UI hands us plain config objects (see model.js) and we
// translate to/from the wire protocol (protocol.js).

import {
    UINT8, UINT16, UINT32, INT32,
    CONFIG_SIZE, CONFIG_VERSION, FORK_VERSIONS, CONFIG_USAGE_PAGE, CONFIG_USAGE,
    REPORT_ID_MONITOR, NMACROS, NEXPRESSIONS, MACRO_ITEMS_IN_PACKET, HUB_PORT_NONE,
    STICKY_FLAG, TAP_FLAG, HOLD_FLAG,
    IGNORE_AUTH_DEV_INPUTS_FLAG, GPIO_OUTPUT_MODE_FLAG, NORMALIZE_GAMEPAD_INPUTS_FLAG,
    QUIRK_FLAG_RELATIVE_MASK, QUIRK_FLAG_SIGNED_MASK, QUIRK_SIZE_MASK,
    RESET_INTO_BOOTSEL, SET_CONFIG, GET_CONFIG, CLEAR_MAPPING, ADD_MAPPING, GET_MAPPING,
    PERSIST_CONFIG, GET_OUR_USAGES, GET_THEIR_USAGES, SUSPEND, RESUME,
    CLEAR_MACROS, APPEND_TO_MACRO, GET_MACRO, CLEAR_EXPRESSIONS, APPEND_TO_EXPRESSION,
    GET_EXPRESSION, SET_MONITOR_ENABLED, CLEAR_QUIRKS, ADD_QUIRK, GET_QUIRK,
    PERSIST_CONFIG_SUCCESS, PERSIST_CONFIG_CONFIG_TOO_BIG, PERSIST_CONFIG_SAFE_MODE,
    GET_POINTER_FX, REBOOT,
    sendFeatureCommand, readConfigFeature, maskToLayerList, layerListToMask,
    setActiveConfigVersion, setForkGeneration, readPointerFx, writePointerFx,
    readForkStatus, readDiagnostics,
} from './protocol.js?v=7';
import { exprToElems, elemToToken, ops, OP_PUSH, OP_PUSH_USAGE } from './expr.js?v=7';
import { usageToHex } from './model.js?v=7';

// Native (desktop) transport: speaks the same sendFeatureReport /
// receiveFeatureReport surface as a WebHID HIDDevice, but routes through the
// pywebview Python bridge (hidapi). Lets the exact same protocol code run in
// the no-Chromium desktop app.
class PyHidDevice {
    constructor(api) { this.api = api; this.opened = true; }
    async sendFeatureReport(reportId, buffer) {
        await this.api.send_feature(reportId, Array.from(new Uint8Array(buffer)));
    }
    async receiveFeatureReport(reportId) {
        const arr = await this.api.get_feature(reportId, CONFIG_SIZE + 1);
        const u8 = new Uint8Array(arr && arr.length ? arr : [0]);
        return new DataView(u8.buffer);
    }
}

export class RemapperDevice {
    constructor() {
        this.device = null;          // WebHID HIDDevice (browser), else null
        this.io = null;              // active transport (HIDDevice or PyHidDevice)
        this._open = false;
        this._nativeName = '';
        this.extraUsages = { source: [], target: [] };
        this.onMonitor = null;       // (list of {usage, value, hubPort}) => void
        this.onDisconnect = null;    // () => void
        this.monitorEnabled = false;
        this._inputHandler = (e) => this._onInputReport(e);
    }

    get isOpen() {
        return this._open;
    }

    get productName() {
        return this.device ? this.device.productName : (this._nativeName || 'HID Remapper');
    }

    get isBluetooth() {
        return this.productName.includes('Bluetooth');
    }

    // Must be called from a user gesture. Returns true on success; throws with a
    // human-readable message on an incompatible firmware version.
    async requestAndOpen() {
        const devices = await navigator.hid.requestDevice({
            filters: [{ usagePage: CONFIG_USAGE_PAGE, usage: CONFIG_USAGE }],
        });
        const iface = devices?.find((d) => d.collections.some((c) => c.usagePage == CONFIG_USAGE_PAGE));
        if (iface === undefined) {
            return false;
        }
        this.device = iface;
        if (!this.device.opened) {
            await this.device.open();
        }
        if (!this.device.opened) {
            this.device = null;
            return false;
        }
        this.io = this.device;
        this._open = true;
        await this._checkDeviceVersion();
        this.device.addEventListener('inputreport', this._inputHandler);
        await this.setMonitorEnabled(this.monitorEnabled);
        await this.getUsages();
        return true;
    }

    // Opens the device through the native (pywebview + hidapi) bridge in the
    // desktop app. No user gesture or WebHID needed.
    async openNative() {
        const api = window.pywebview && window.pywebview.api;
        if (!api) throw new Error('Native HID bridge not available.');
        const res = await api.open();
        if (!res || !res.ok) {
            throw new Error((res && res.error) || 'Could not open a HID Remapper.');
        }
        this.io = new PyHidDevice(api);
        this.device = null;
        this._nativeName = res.product || 'HID Remapper';
        this._open = true;
        // The Python side pushes input reports (first byte = report id) via
        // this global; route them through the same monitor parsing WebHID
        // events use, so press-to-identify and the HUD work natively too.
        window.__nativeInputReport = (bytes) => {
            if (!bytes || bytes.length < 2) return;
            const u8 = new Uint8Array(bytes);
            this._onInputReport({
                reportId: u8[0],
                data: new DataView(u8.buffer, 1),
            });
        };
        // Fired by the Python reader thread when its read loop dies (real
        // unplug); intentional close() never triggers it.
        window.__nativeDisconnected = () => this.handleNativeDisconnect();
        await this._checkDeviceVersion();
        await this.setMonitorEnabled(this.monitorEnabled);
        await this.getUsages();
        return true;
    }

    handleDisconnect(event) {
        if (this.device != null && event.device === this.device) {
            this._markClosed();
        }
    }

    // Native (pywebview) path: the Python reader thread calls
    // window.__nativeDisconnected() when its read loop dies.
    handleNativeDisconnect() {
        if (this._open && this.device == null) {
            this._markClosed();
        }
    }

    _markClosed() {
        // isOpen must go false HERE, not just the UI banner — every poller
        // (status bar, diagnostics interval, HUD tick, live apply) gates on
        // it, and a stale true leaves them hammering a dead handle forever.
        this._open = false;
        this.device = null;
        this.io = null;
        if (this.onDisconnect) {
            this.onDisconnect();
        }
    }

    async _checkDeviceVersion() {
        // Current fork firmware deliberately speaks stock version 18 (so
        // remapper.org always works as a fallback); fork capability is a
        // separate probe below. Legacy fork firmware (100/101) still
        // negotiates by version.
        for (const version of [CONFIG_VERSION, ...FORK_VERSIONS, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2]) {
            await sendFeatureCommand(this.io, GET_CONFIG, [], version);
            const [received_version] = await readConfigFeature(this.io, [UINT8]);
            if (received_version == version) {
                if (version == CONFIG_VERSION) {
                    this.configVersion = version;
                    setActiveConfigVersion(version);
                    // Stock wire version: fork features present only if the
                    // status page answers with the 'PFX' signature.
                    let status = null;
                    try {
                        status = await readForkStatus(this.io);
                    } catch (e) {
                        status = null;  // stock firmware variants that reject the command outright
                    }
                    this.forkGeneration = status ? status.generation : 0;
                    this.forkStatus = status;
                    setForkGeneration(this.forkGeneration);
                    return;
                }
                if (FORK_VERSIONS.includes(version)) {
                    this.configVersion = version;
                    setActiveConfigVersion(version);
                    this.forkGeneration = 1;  // legacy fork: no status page
                    this.forkStatus = null;
                    setForkGeneration(1);
                    return;
                }
                throw new Error(
                    'Incompatible firmware version (' + version + '). This tool targets config ' +
                    'version ' + CONFIG_VERSION + ' (stock or current fork) and the legacy fork versions ' +
                    FORK_VERSIONS.join('/') + '.');
            }
        }
        throw new Error('Incompatible firmware version (could not negotiate).');
    }

    // Fork firmware only: Pointer FX live tuning parameters.
    get isFork() {
        return (this.forkGeneration || 0) > 0;
    }

    // The firmware's config protocol is a two-step SET(command)/GET(answer)
    // with ONE global command slot: any transaction that interleaves with
    // another (HUD layer poll vs a Pointer write, diagnostics poll vs Save)
    // reads the wrong answer or throws. Every wire transaction therefore
    // queues through this one promise chain. Errors propagate to the caller
    // but never wedge the chain.
    _serial(fn) {
        const run = (this._txq || Promise.resolve()).then(fn, fn);
        this._txq = run.catch(() => {});
        return run;
    }

    // Sidecar-era fork: live status {layerMask, generation, descriptorPending,
    // safeMode}, or null on stock / legacy-fork firmware.
    async readStatus() {
        if ((this.forkGeneration || 0) < 2) return null;
        const status = await this._serial(() => readForkStatus(this.io));
        this.forkStatus = status;
        return status;
    }

    // Sidecar-era fork: diagnostics counters, or null.
    async readDiag() {
        if ((this.forkGeneration || 0) < 2) return null;
        return await this._serial(() => readDiagnostics(this.io));
    }

    // Fork: clean device reboot (applies a pending descriptor-number change
    // without replugging). The device drops off USB and re-enumerates.
    async reboot() {
        await this._serial(() => sendFeatureCommand(this.io, REBOOT));
    }

    async loadPointerFx() {
        return await this._serial(() => readPointerFx(this.io));
    }

    // Fork firmware: live layer bitmask (Pointer FX read-only page 2).
    async readLayerState() {
        return await this._serial(async () => {
            await sendFeatureCommand(this.io, GET_POINTER_FX, [[UINT32, 2]]);
            const [mask] = await readConfigFeature(this.io, [UINT8]);
            return mask;
        });
    }

    async savePointerFx(params) {
        await this._serial(() => writePointerFx(this.io, params));
    }

    // Persists the device's current live state (including Pointer FX params)
    // without rewriting mappings — used by the Pointer tab's save button.
    async persistOnly() {
        return await this._serial(async () => {
            await sendFeatureCommand(this.io, PERSIST_CONFIG);
            const [code] = await readConfigFeature(this.io, [UINT8]);
            return code;
        });
    }

    async _readGlobalConfig() {
        await sendFeatureCommand(this.io, GET_CONFIG);
        const [config_version, flags, unmapped_mask, partial_scroll_timeout, mapping_count,
            our_usage_count, their_usage_count, interval_override, tap_hold_threshold,
            gpio_debounce_time_ms, our_descriptor_number, macro_entry_duration, quirk_count] =
            await readConfigFeature(this.io,
                [UINT8, UINT8, UINT8, UINT32, UINT16, UINT32, UINT32, UINT8, UINT32, UINT8, UINT8, UINT8, UINT16]);
        return {
            config_version, flags, unmapped_mask, partial_scroll_timeout, mapping_count,
            our_usage_count, their_usage_count, interval_override, tap_hold_threshold,
            gpio_debounce_time_ms, our_descriptor_number, macro_entry_duration, quirk_count,
        };
    }

    // Reads the full config from the device into a plain object (model shape).
    async load() { return this._serial(() => this._loadInner()); }
    async _loadInner() {
        const g = await this._readGlobalConfig();
        const config = {
            'version': g.config_version,
            'unmapped_passthrough_layers': maskToLayerList(g.unmapped_mask),
            'partial_scroll_timeout': g.partial_scroll_timeout,
            'tap_hold_threshold': g.tap_hold_threshold,
            'gpio_debounce_time_ms': g.gpio_debounce_time_ms,
            'interval_override': g.interval_override,
            'our_descriptor_number': g.our_descriptor_number,
            'ignore_auth_dev_inputs': !!(g.flags & IGNORE_AUTH_DEV_INPUTS_FLAG),
            'gpio_output_mode': (g.flags & GPIO_OUTPUT_MODE_FLAG) ? 1 : 0,
            'normalize_gamepad_inputs': !!(g.flags & NORMALIZE_GAMEPAD_INPUTS_FLAG),
            'macro_entry_duration': g.macro_entry_duration + 1,
            'input_labels': 0,
            'mappings': [],
            'macros': [],
            'expressions': [],
            'quirks': [],
        };

        for (let i = 0; i < g.mapping_count; i++) {
            await sendFeatureCommand(this.io, GET_MAPPING, [[UINT32, i]]);
            const [target_usage, source_usage, scaling, layer_mask, mapping_flags, hub_ports] =
                await readConfigFeature(this.io, [UINT32, UINT32, INT32, UINT8, UINT8, UINT8]);
            config['mappings'].push({
                'target_usage': usageToHex(target_usage),
                'source_usage': usageToHex(source_usage),
                'scaling': scaling,
                'layers': maskToLayerList(layer_mask),
                'sticky': (mapping_flags & STICKY_FLAG) != 0,
                'tap': (mapping_flags & TAP_FLAG) != 0,
                'hold': (mapping_flags & HOLD_FLAG) != 0,
                'source_port': hub_ports & 0x0F,
                'target_port': (hub_ports >> 4) & 0x0F,
            });
        }

        for (let macro_i = 0; macro_i < NMACROS; macro_i++) {
            let macro = [];
            let i = 0;
            let keep_going = true;
            while (keep_going) {
                await sendFeatureCommand(this.io, GET_MACRO, [[UINT32, macro_i], [UINT32, i]]);
                const fields = await readConfigFeature(this.io, [UINT8, UINT32, UINT32, UINT32, UINT32, UINT32, UINT32]);
                const nitems = fields[0];
                const usages_ = fields.slice(1);
                if (nitems < MACRO_ITEMS_IN_PACKET) {
                    keep_going = false;
                }
                if ((macro.length == 0) && (nitems > 0)) {
                    macro = [[]];
                }
                for (const usage of usages_.slice(0, nitems)) {
                    if (usage == 0) {
                        macro.push([]);
                    } else {
                        macro.at(-1).push(usageToHex(usage));
                    }
                }
                i += MACRO_ITEMS_IN_PACKET;
            }
            config['macros'].push(macro);
        }

        for (let expr_i = 0; expr_i < NEXPRESSIONS; expr_i++) {
            let expression = [];
            let i = 0;
            while (true) {
                await sendFeatureCommand(this.io, GET_EXPRESSION, [[UINT32, expr_i], [UINT32, i]]);
                const fields = await readConfigFeature(this.io, new Array(28).fill(UINT8));
                const nelems = fields[0];
                if (nelems == 0) {
                    break;
                }
                let elems = fields.slice(1);
                for (let j = 0; j < nelems; j++) {
                    const elem = elems[0];
                    elems = elems.slice(1);
                    if ([OP_PUSH, OP_PUSH_USAGE].includes(elem)) {
                        const val = elems[3] << 24 | elems[2] << 16 | elems[1] << 8 | elems[0];
                        elems = elems.slice(4);
                        expression.push(elemToToken(elem, val));
                    } else {
                        expression.push(elemToToken(elem));
                    }
                }
                i += nelems;
            }
            config['expressions'].push(expression.join(' '));
        }

        for (let quirk_i = 0; quirk_i < g.quirk_count; quirk_i++) {
            await sendFeatureCommand(this.io, GET_QUIRK, [[UINT32, quirk_i]]);
            const [vendor_id, product_id, interface_, report_id, usage, bitpos, size_flags] =
                await readConfigFeature(this.io, [UINT16, UINT16, UINT8, UINT8, UINT32, UINT16, UINT8]);
            config['quirks'].push({
                'vendor_id': '0x' + vendor_id.toString(16).padStart(4, '0'),
                'product_id': '0x' + product_id.toString(16).padStart(4, '0'),
                'interface': interface_,
                'report_id': report_id,
                'usage': usageToHex(usage),
                'bitpos': bitpos,
                'size': size_flags & QUIRK_SIZE_MASK,
                'relative': (size_flags & QUIRK_FLAG_RELATIVE_MASK) != 0,
                'signed': (size_flags & QUIRK_FLAG_SIGNED_MASK) != 0,
            });
        }

        return config;
    }

    // Writes the config to the device and persists it. Returns a code; throws on
    // communication errors.
    async save(config) { return this._serial(() => this._saveInner(config)); }
    async _saveInner(config) {
        return await this._push(config, true);
    }

    // Vial-style live apply: writes the config to the device's RAM only — no
    // flash write (persist_config erases a whole sector; auto-persisting on
    // every edit would wear it out and add latency). Changes take effect
    // immediately but are lost on power-cycle until save() persists them.
    async apply(config) {
        await this._push(config, false);
    }

    async _push(config, persist) {
        await sendFeatureCommand(this.io, SUSPEND);
        try {
            const flags = (config['ignore_auth_dev_inputs'] ? IGNORE_AUTH_DEV_INPUTS_FLAG : 0) |
                (config['gpio_output_mode'] ? GPIO_OUTPUT_MODE_FLAG : 0) |
                (config['normalize_gamepad_inputs'] ? NORMALIZE_GAMEPAD_INPUTS_FLAG : 0);
            await sendFeatureCommand(this.io, SET_CONFIG, [
                [UINT8, flags],
                [UINT8, layerListToMask(config['unmapped_passthrough_layers'])],
                [UINT32, config['partial_scroll_timeout']],
                [UINT8, config['interval_override']],
                [UINT32, config['tap_hold_threshold']],
                [UINT8, config['gpio_debounce_time_ms']],
                [UINT8, config['our_descriptor_number']],
                [UINT8, config['macro_entry_duration'] - 1],
            ]);

            await sendFeatureCommand(this.io, CLEAR_MAPPING);
            for (const mapping of config['mappings']) {
                await sendFeatureCommand(this.io, ADD_MAPPING, [
                    [UINT32, parseInt(mapping['target_usage'], 16)],
                    [UINT32, parseInt(mapping['source_usage'], 16)],
                    [INT32, mapping['scaling']],
                    [UINT8, layerListToMask(mapping['layers'])],
                    [UINT8, (mapping['sticky'] ? STICKY_FLAG : 0) | (mapping['tap'] ? TAP_FLAG : 0) | (mapping['hold'] ? HOLD_FLAG : 0)],
                    [UINT8, ((mapping['target_port'] & 0x0F) << 4) | (mapping['source_port'] & 0x0F)],
                ]);
            }

            await sendFeatureCommand(this.io, CLEAR_MACROS);
            let macro_i = 0;
            for (const macro of config['macros']) {
                if (macro_i >= NMACROS) break;
                const flat = macro.map((x) => x.concat(['0x00'])).flat().slice(0, -1);
                for (let i = 0; i < flat.length; i += MACRO_ITEMS_IN_PACKET) {
                    const chunk_size = Math.min(MACRO_ITEMS_IN_PACKET, flat.length - i);
                    await sendFeatureCommand(this.io, APPEND_TO_MACRO,
                        [[UINT8, macro_i], [UINT8, chunk_size]].concat(
                            flat.slice(i, i + chunk_size).map((x) => [UINT32, parseInt(x, 16)])));
                }
                macro_i++;
            }

            await sendFeatureCommand(this.io, CLEAR_EXPRESSIONS);
            let expr_i = 0;
            for (const expr of config['expressions']) {
                if (expr_i >= NEXPRESSIONS) break;
                let elems = exprToElems(expr);
                while (elems.length > 0) {
                    let bytes_left = 24;
                    let items_to_send = [];
                    let nelems = 0;
                    while ((elems.length > 0) && (bytes_left > 0)) {
                        const elem = elems[0];
                        if ([OP_PUSH, OP_PUSH_USAGE].includes(elem[0])) {
                            if (bytes_left >= 5) {
                                items_to_send.push([UINT8, elem[0]]);
                                items_to_send.push([UINT32, elem[1] >>> 0]);
                                bytes_left -= 5;
                                nelems++;
                                elems = elems.slice(1);
                            } else {
                                break;
                            }
                        } else {
                            items_to_send.push([UINT8, elem[0]]);
                            bytes_left--;
                            nelems++;
                            elems = elems.slice(1);
                        }
                    }
                    await sendFeatureCommand(this.io, APPEND_TO_EXPRESSION,
                        [[UINT8, expr_i], [UINT8, nelems]].concat(items_to_send));
                }
                expr_i++;
            }

            await sendFeatureCommand(this.io, CLEAR_QUIRKS);
            for (const quirk of config['quirks']) {
                const size_flags = (quirk['size'] & QUIRK_SIZE_MASK) |
                    (quirk['relative'] ? QUIRK_FLAG_RELATIVE_MASK : 0) |
                    (quirk['signed'] ? QUIRK_FLAG_SIGNED_MASK : 0);
                await sendFeatureCommand(this.io, ADD_QUIRK, [
                    [UINT16, parseInt(quirk['vendor_id'], 16)],
                    [UINT16, parseInt(quirk['product_id'], 16)],
                    [UINT8, quirk['interface']],
                    [UINT8, quirk['report_id']],
                    [UINT32, parseInt(quirk['usage'], 16)],
                    [UINT16, quirk['bitpos']],
                    [UINT8, size_flags],
                ]);
            }

            if (persist) {
                await sendFeatureCommand(this.io, PERSIST_CONFIG);
                const [code] = await readConfigFeature(this.io, [UINT8]);
                return code;
            }
            return undefined;
        } finally {
            await sendFeatureCommand(this.io, RESUME);
        }
    }

    async getUsages() { return this._serial(() => this._getUsagesInner()); }
    async _getUsagesInner() {
        const g = await this._readGlobalConfig();
        this.extraUsages['target'] = await this._doGetUsages(GET_OUR_USAGES, g.our_usage_count);
        this.extraUsages['source'] = await this._doGetUsages(GET_THEIR_USAGES, g.their_usage_count);
        return this.extraUsages;
    }

    async _doGetUsages(command, rle_count) {
        const set = new Set();
        let i = 0;
        while (i < rle_count) {
            await sendFeatureCommand(this.io, command, [[UINT32, i]]);
            const fields = await readConfigFeature(this.io, [UINT32, UINT32, UINT32, UINT32, UINT32, UINT32]);
            for (let j = 0; j < 3; j++) {
                const usage = fields[2 * j];
                const count = fields[2 * j + 1];
                if (usage != 0) {
                    for (let k = 0; k < count; k++) {
                        set.add(usageToHex(usage + k));
                    }
                }
            }
            i += 3;
        }
        const out = Array.from(set);
        out.sort();
        return out;
    }

    async setMonitorEnabled(enabled) { return this._serial(() => this._setMonitorEnabledInner(enabled)); }
    async _setMonitorEnabledInner(enabled) {
        this.monitorEnabled = enabled;
        if (this.io != null) {
            await sendFeatureCommand(this.io, SET_MONITOR_ENABLED, [[UINT8, enabled ? 1 : 0]]);
        }
    }

    async resetIntoBootsel() {
        await sendFeatureCommand(this.io, RESET_INTO_BOOTSEL);
    }

    _onInputReport(event) {
        if (event.reportId != REPORT_ID_MONITOR || !this.onMonitor) {
            return;
        }
        const list = [];
        for (let i = 0; i < 7 && (i + 1) * 9 <= event.data.byteLength; i++) {
            const usage = usageToHex(event.data.getUint32(i * 9, true));
            const value = event.data.getInt32(i * 9 + 4, true);
            const hubPort = event.data.getUint8(i * 9 + 8);
            if (parseInt(usage, 16) != 0) {
                list.push({ usage, value, hubPort });
            }
        }
        if (list.length > 0) {
            this.onMonitor(list);
        }
    }
}

export { PERSIST_CONFIG_SUCCESS, PERSIST_CONFIG_CONFIG_TOO_BIG, PERSIST_CONFIG_SAFE_MODE, HUB_PORT_NONE };
