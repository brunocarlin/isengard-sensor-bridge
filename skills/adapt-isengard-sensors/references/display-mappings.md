# Display mappings

CpuTemp consumes HWiNFO-style group objects and fixed sensor-key names. The adapter is `compat/binding.js`; bridge output is `CpuTempFanBridge.json`.

## Known keys

| Desired field | Compatibility key |
|---|---|
| CPU frequency | `CPU Core Clock` and `Core 0 Clock` inside CPU groups |
| Repurposed pump number | `Fan Pump` inside matching motherboard groups |
| CPU fan | `Fan CPU`; safe to mirror when fixed first-match logic requires it |
| GPU frequency | `GPU Clock` inside GPU groups |
| GPU fans | `GPU Fan1` and `GPU Fan2` inside GPU groups |

Keep clock keys scoped to their hardware groups. A previous broad injection put CPU clock keys into GPU groups and caused the GPU field to display CPU MHz.

## Physical-display limitation

The device firmware appears to render field labels and units. Supplying CPU MHz through `Fan Pump` changes the numeric value but leaves `Pump Speed` and `RPM` on the physical display. Do not claim those strings can be changed through sensor mapping. Firmware or USB-protocol research is a separate, higher-risk project.

## Adding a value

1. Identify the LibreHardwareMonitor sensor by hardware name, sensor type, sensor name, and identifier.
2. Add a nullable JSON field to `StandaloneSnapshot`.
3. Select it semantically; use an exact identifier only as a tested preference with a generic fallback.
4. Map it to the smallest correct set of CpuTemp groups.
5. Validate that unrelated CPU/GPU fields remain unchanged.
6. Rebuild and update every embedded SHA-256 value.

Do not change physical firmware, weaken archive checks, or inject arbitrary strings from the snapshot into executable paths or commands.
