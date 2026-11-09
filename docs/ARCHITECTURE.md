# Pulse architecture

Core inputs are read-only system counters and verified process identities from CSensors.
SamplingSession → Attribution → Snapshot/PlotHistory → Monitor → shared SwiftUI views.
Core sampling works without any integration, account, developer folder, or FDA grant.

| Capability | Canonical input/output | Consumer/check |
|---|---|---|
| Vitals and owner groups | System/process samples → Snapshot and ProcessGroup | Monitor, Glance, Overview; core tests |
| Disk estimates | Discovered/cache/config roots → DiskEstimate | DiskUsageModel → DiskBreakdown/Composition; docs/disk/README.md |
| Metric detail | Existing ProcessGroup → ProcessMetric ranking | ProcessList/OwnerDisclosure; V60DrilldownTests |
| Group history | KeyedRingBuffer<Key, Value>, dated observations | ProcessDrilldownModel → Shape sparkline; ≤24 retained keys × 60 samples; top 12 render |

Disk scans use physical descriptor-relative bulk metadata, allocated sizes, and bounded passes.
ProtectedPaths and the silent FDA probe gate scans; app-owned configuration/checkpoints are separate.
Home top-level folders and installed standard caches are discovered; no project name is assumed.
Optional `~/Library/Application Support/Pulse/config.json`: `{"extraRoots":["~/work"]}`.
The versioned atomic disk cache has a 256 KiB cap and a 30-second write throttle.
Persisted directory cookies are reopened only after directory identity/mtime validation.
Only unchanged empty directories are skipped: parent mtimes cannot validate descendants.
Utility scans share a bounded 1.95% whole-process CPU-credit budget with rendering/sampling.
Glance-only uses cached totals; published progress stays at the existing two-second cadence.
Completed totals survive refresh; only overlapping partition changes reset progress.
Root mtime checks reuse snapshots within TTL; absolute indexes resume APFS streams.
At most 12 active scan handles plus discovery/transient handles stay below 16.
FDA is rechecked and process-wide dataless materialization is disabled at launch.

PulseProvider declares id, cheap availability, cadence, and an optional section.
ProviderRegistry detects once at Monitor launch and rechecks at most every 15 minutes.
Absent integrations have no polling timer, subprocess, sample buffer, or UI section.
Core sampling is independent of the registry; cadence declarations reserve optional sampling slots.

| Optional provider | v6 implementation | v7 status |
|---|---|---|
| HerdrProvider | PATH detection; supplied PID/pane-map adapter | Session pane labels and uptime; live pane snapshot acquisition deferred |
| AgentAccountsProvider | Installed config detection; whitelisted config-home/cwd resolver | Claude/Codex session account labels; per-process environment acquisition deferred |
| UsageStripProvider | Executable detection; explicit bounded `--swiftbar` reader | Account usage strip; automatic sampling and UI deferred |
| Generic core | Existing process/memory counters and keyed buffer | Leak watch; longer pressure/swap history; persisted/downsampled timelines |
| Generic disk scanner | Persistent folder estimates and disk capacity | Disk growth and runway calculations |
| Generic thermal sampler | Existing temperature/fan/thermal-state readings | Heat/throttling detail and notification inputs |

Integration UI sections are nil in v6; these are optional stubs/adapters, not finished v7 features.
The explicit usage reader has a one-second timeout, 64 KiB cap and an isolated process group.
Timeout kills the group, including non-exec grandchildren.
It stores no credentials or output; the registry never executes it automatically.
Process environments are caller-supplied to the account adapter; only configuration-home variables are used.

DetailDestination is the reusable window detail route; Back/Escape discard drill-down history.
The CLI `--show-window --show-drilldown memory|cpu` selects the same route as the tiles.
Closed recording returns immediately; dropped owners retain a 60-second grace, capped at 24 keys.
The keyed buffer is independent of process names, metrics, and providers.
No longer history, leak policy, account UI, runway estimate, or new thermal integration is implemented here.

## v7 additions
| Capability | Input → output | Where |
|---|---|---|
| Timeline | Every sample → 30-second `TimelineSample` buckets (worst pressure/thermal kept), 2880-slot ring | `TimelineStore`, `Insights.timeline` |
| Leak watch | Owner resident bytes at each process refresh → least-squares slope, fit and rise tests over 10–30 minutes | `LeakWatch` |
| Disk runway | Free-space buckets of the newest 6 hours → fill rate, days to full / to 5 GB free | `DiskRunway` |
| Throttling events | Thermal state ≥ serious or `CPU_Speed_Limit` < 100 → open/closed events, 50 kept | `TimelineStore.events`, `pulse_thermal` |
| Agent context | `KERN_PROCARGS2` of AI processes → whitelisted `CLAUDE_CONFIG_DIR`/`CODEX_HOME`/`HERDR_PANE_ID` only | `pulse_process_env`, `ProcessSampler` |
| Usage strip | Explicit usage-reader `--swiftbar` run while the window is open → `UsageReport` (display only) | `UsageStripProvider`, `UsageModel` |
Insights are built on the sampling queue and published only while a window is open. Provider detection can be redirected with `PULSE_PROVIDER_HOME` / `PULSE_PROVIDER_PATH` / `PULSE_USAGE_EXECUTABLE`.
