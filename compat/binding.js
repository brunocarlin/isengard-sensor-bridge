"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const { XMLParser } = require("fast-xml-parser");
const fs = require("fs");
const path = require("path");
exports.HWi_FLAG_DEBUG_MODE_ENABLE = 1 << 0;
exports.HWi_FLAG_SW_SMI_ENABLE = 1 << 1;
exports.HWi_FLAG_IDE_SAFE = 0 << 2;
exports.HWi_FLAG_IDE_ADR_1 = 1 << 2;
exports.HWi_FLAG_IDE_ADR_2 = 2 << 2;
exports.HWi_FLAG_IDE_ADR_4 = 4 << 2;
exports.HWi_FLAG_PROB_PCI_SCAN = 1 << 5;
exports.HWi_FLAG_SMBUS_ENABLE = 1 << 6;
exports.HWi_FLAG_EC_DISABLE = 1 << 7;
exports.HWi_FLAG_HPET_DISABLE = 1 << 8;
exports.HWi_FLAG_GPU_I2C_DISABLE = 1 << 10;
exports.HWi_FLAG_IOCTL_KERNEL = 1 << 11;
exports.HWi_FLAG_PERSISTENT_DRIVER = 1 << 12;
exports.HWi_FLAG_DRIVE_SCAN_DISABLE = 1 << 13;
exports.HWi_FLAG_PCI_DIRECT = 1 << 14;
exports.HWi_FLAG_CSMI_SAS_DISABLE = 1 << 15;
exports.HWi_FLAG_IME_DISABLE = 1 << 16;
exports.HWi_FLAG_GPU_WAKE_EXT = 1 << 17;
exports.HWi_FLAG_PREFER_ADL = 1 << 18;
exports.HWi_FLAG_CORSAIR_ASETEK = 1 << 19;
exports.HWi_FLAG_SNAPSHOT_POLLING = 1 << 20;
exports.HWi_FLAG_DEFAULT = exports.HWi_FLAG_SMBUS_ENABLE | exports.HWi_FLAG_CORSAIR_ASETEK;
const addon = require("bindings")("addon");
const hwinfo = new addon.hwinfo();
const bridgeDirectory = path.join(path.dirname(process.execPath), "lib");
const bridgeJson = path.join(bridgeDirectory, "CpuTempFanBridge.json");
async function init(flag = exports.HWi_FLAG_DEFAULT) {
    return hwinfo.init(flag);
}
function isInited() { return hwinfo.isInited(); }
async function status() {
    const statusJson = await hwinfo.status();
    const result = statusJson === "" ? {} : JSON.parse(statusJson);
    try {
        const bridge = JSON.parse(fs.readFileSync(bridgeJson, "utf8").replace(/^\uFEFF/, ""));
        const entries = Object.entries(result).filter(([, readings]) => readings && typeof readings === "object");
        const boardGroups = entries.filter(([name]) => /GIGABYTE X870E AORUS PRO/i.test(name));
        const cpuGroups = entries.filter(([name]) => /^CPU \[#\d+\]:/i.test(name));
        for (const [, readings] of entries) delete readings["Fan Chassis"];
        if (Number.isFinite(bridge.CpuFanRpm) && bridge.CpuFanRpm >= 0) {
            // The physical display firmware uses a fixed first-match search for Fan CPU.
            // Mirroring only this RPM key is safe and keeps it independent of clocks.
            for (const [, readings] of entries) readings["Fan CPU"] = bridge.CpuFanRpm;
        }
        if (Number.isFinite(bridge.CpuClockMhz) && bridge.CpuClockMhz > 0) {
            for (const [, readings] of cpuGroups) {
                readings["CPU Core Clock"] = bridge.CpuClockMhz;
                readings["Core 0 Clock"] = bridge.CpuClockMhz;
            }
            for (const [, readings] of boardGroups) readings["Fan Pump"] = bridge.CpuClockMhz;
        }
        // CpuTemp may select the Ryzen iGPU group before the discrete NVIDIA group.
        // Mirror the selected RTX readings into every GPU group so its fixed selector
        // receives the intended discrete-GPU values without contaminating CPU sensors.
        const gpuGroups = entries.filter(([name]) => /GPU/i.test(name));
        for (const [, readings] of gpuGroups) {
            if (Number.isFinite(bridge.GpuClockMhz)) readings["GPU Clock"] = bridge.GpuClockMhz;
            if (Number.isFinite(bridge.GpuFan1Rpm)) {
                readings["GPU Fan1"] = bridge.GpuFan1Rpm;
                readings["GPU Fan2"] = bridge.GpuFan2Rpm || 0;
            }
        }
    } catch (_) { }
    return result;
}
async function details() {
    const xml = await hwinfo.details();
    if (xml === "") return {};
    const root = new XMLParser().parse(xml);
    return root && root.HWINFO && root.HWINFO.COMPUTER ? root.HWINFO.COMPUTER : {};
}
function setLogHandler(callback) { hwinfo.setLogHandler(callback); }
function deInit() { hwinfo.deInit(); }
exports.init = init;
exports.isInited = isInited;
exports.status = status;
exports.details = details;
exports.setLogHandler = setLogHandler;
exports.deInit = deInit;
