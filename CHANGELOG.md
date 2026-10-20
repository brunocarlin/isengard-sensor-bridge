# Changelog

## Unreleased

- Added a reversible tray-start add-on for the supported CpuTemp 1.0.15 standalone fix.
- Suppressed automatic window display for `--startupWithMinimize`, while retaining tray/manual reopening and renderer monitoring updates.
- Preserved the existing sensor adapter, bridge task, startup task privileges, and original fan-fix rollback archive.
- Added startup visibility and reopening tests.

## 1.0.0 — 2026-08-22

- Replaced the obsolete embedded sensor path with a standalone LibreHardwareMonitor/PawnIO bridge.
- Corrected IT8696E CPU fan RPM on the GIGABYTE X870E AORUS PRO.
- Repurposed the physical Pump Speed number as CPU average MHz.
- Added dynamic NVIDIA, AMD, and Intel GPU discovery with multi-GPU preference override.
- Corrected GPU clock and fan mappings while preserving zero-RPM mode.
- Made the watcher windowless and its JSON writes atomic and BOM-free.
- Added exact-build and payload integrity checks plus verified rollback.
- Hardened the elevated task path under `Program Files`.
- Added the reusable `adapt-isengard-sensors` skill and hardware adaptation references.
