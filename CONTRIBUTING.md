# Contributing

Bug reports and hardware compatibility results are welcome.

Include:

- Windows and CpuTemp versions;
- motherboard and GPU models;
- original `app.asar` SHA-256;
- sanitized `--list-lhm-file` output;
- expected and observed values.

Never upload the original CpuTemp package, `app.asar`, HWiNFO DLLs, firmware dumps, credentials, or files containing personal paths. New application builds must retain exact hash gates and a tested rollback path.

Code changes should build with .NET 10, preserve atomic snapshot writes, keep the watcher windowless, and avoid hard-coded GPU indexes when discovery is possible.
