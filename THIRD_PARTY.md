# Method references

Pulse has no third-party packages or copied implementations.

- [macmon sources.rs](https://github.com/vladkens/macmon/blob/main/src/sources.rs), MIT: studied HID usage page `0xff00`, usage `5`, temperature event `15`, dynamic API signatures, and SMC request ABI. Pulse's C implementation was independently written.
- [Stats SMC/smc.swift](https://github.com/exelban/stats/blob/master/SMC/smc.swift), MIT: checked SMC selector `2`, metadata/read commands `9`/`5`, data type decoding and fan key names. No fan-control/write command is implemented in Pulse.
- [Apple memory_pressure.c](https://github.com/apple-oss-distributions/system_cmds/blob/main/memory_pressure/memory_pressure.c), APSL 2.0: confirmed `memorystatus_get_level` is the system-wide free percentage source. Only the API method was used, no source copied.
- Apple SDK headers and local Liquid Glass design references: API contracts for Mach, libproc, IOKit and SwiftUI.

Source review date: 2026-10-28. Sources inform implementation methods; live readings and acceptance evidence are recorded separately.
