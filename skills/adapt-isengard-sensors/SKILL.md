---
name: adapt-isengard-sensors
description: Adapt the Isengard Sensor Bridge to NVIDIA, AMD, Intel, multi-GPU, motherboard, or display-mapping changes while preserving exact-build checks, privilege safety, and rollback. Use for hardware compatibility work in this repository; do not use for ordinary Fan Control configuration.
---

# Adapt Isengard Sensors

Work from observed LibreHardwareMonitor sensor output, not assumed indexes. Preserve these invariants:

- Keep the scheduled-task executable under administrator-protected `Program Files`.
- Keep original, payload, and final ASAR SHA-256 checks fail-closed.
- Never ship CpuTemp, HWiNFO, PawnIO, or firmware vendor binaries.
- Keep writes atomic and the watcher windowless.
- Do not run CpuTemp itself elevated.
- Maintain a tested `Restore.cmd` path before changing a live installation.

For GPU detection, multi-GPU selection, AMD/NVIDIA/Intel adaptation, or `PreferredGpu`, read [references/gpu-adaptation.md](references/gpu-adaptation.md).

For changing values shown in CpuTemp or on the physical display, read [references/display-mappings.md](references/display-mappings.md).

After a compatibility change:

1. Build the self-contained `win-x64` bridge.
2. Exercise `--list-lhm-file` and a watcher snapshot on the target machine.
3. Confirm CPU and GPU values at idle and under load against an independent monitor.
4. Patch only the supported original archive and record the new final hash.
5. Test install, logon task, invisible execution, and restore.
6. Update the payload hashes, compatibility table, manifest, and release checksum.

Stop rather than bypassing a hash gate when the application build or hardware mapping is unknown.
