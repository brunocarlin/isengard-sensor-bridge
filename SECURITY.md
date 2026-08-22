# Security policy

## Supported release

Only the latest GitHub release and the exact CpuTemp build documented in the README are supported.

## Privilege model

PawnIO hardware access requires elevation. The installer registers a highest-privilege logon task for the current user. To prevent task-path hijacking, `CpuTempFanBridge.exe` is installed under `%ProgramFiles%\CpuTempSensorBridge`, where a normal user cannot replace it without elevation.

Sensor JSON is intentionally written to the CpuTemp `lib` directory and treated as untrusted input by the JavaScript adapter. Only finite numeric fields are accepted.

## Integrity and rollback

- The installer verifies the original application and both payload hashes.
- The patcher updates ASAR integrity metadata and verifies the final archive hash.
- The original archive is retained as a hash-verified rollback backup.
- Unknown application builds fail closed.

Do not weaken hash checks, move the task executable into a user-writable directory, or run CpuTemp itself as administrator.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature. Do not include credentials, private paths, serial numbers, or proprietary vendor binaries in a public issue.
