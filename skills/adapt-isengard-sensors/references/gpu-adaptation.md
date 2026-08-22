# GPU adaptation

## Discover sensors

Run the bridge elevated:

```powershell
CpuTempFanBridge.exe --list-lhm-file sensors.txt
```

Inspect rows whose hardware type begins with `Gpu`. A usable GPU needs a `Clock / GPU Core` sensor. Fan sensors are optional because zero-RPM and fanless devices are valid.

LibreHardwareMonitor commonly reports:

- `GpuNvidia` with identifiers below `/gpu-nvidia/<index>/`;
- `GpuAmd` below `/gpu-amd/<index>/`;
- `GpuIntel` below `/gpu-intel/<index>/`.

Do not encode the numeric index as identity. Group readings by `HardwareType + HardwareName`, then select the group.

## Selection policy

The default bridge scores:

1. an explicit case-insensitive `PreferredGpu` name match;
2. devices exposing fan tachometers, which usually identifies a discrete GPU;
3. NVIDIA, AMD, then Intel as a deterministic tie-break only;
4. generic AMD `Radeon(TM) Graphics` lower than named discrete devices.

The vendor order is not a quality judgment. It only makes ambiguous enumeration deterministic and may be overridden.

Example `CpuTempFanBridge.config.json` beside the generated snapshot:

```json
{
  "PreferredGpu": "GeForce RTX 4090"
}
```

## Validate

Compare the JSON `GpuName`, `GpuClockMhz`, and fan readings with another monitor at idle and under load. Clock readings sampled at different moments will differ; validate direction and plausible ranges rather than demanding identical timestamps.

For dual-GPU systems, confirm CpuTemp may enumerate the integrated GPU first. The compatibility adapter mirrors the selected discrete-GPU values only into GPU groups so the fixed application selector cannot accidentally read CPU clocks.
