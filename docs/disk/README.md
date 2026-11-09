# Disk usage estimates

Inputs: discovered home folders, installed dev caches/Homebrew, optional session projects,
optional `~/Library/Application Support/Pulse/config.json` (`{"extraRoots":["~/work"]}`),
a silent FDA result, and whole-pass limits. No project or account name is assumed.
[DiskRootPlan](../../Sources/PulseCore/Sampling/DiskRootPlan.swift) owns root discovery and the allocated Docker.raw stat.
[ProtectedPaths](../../Sources/PulseCore/Sampling/ProtectedPaths.swift) and the FDA probe are unchanged;
roots and directory children are gated before traversal. Parent descriptors reject symlinks.
Bulk metadata is used only below policy-safe parents; sensitive parents filter names first.
The planner always omits home Trash, including configured roots and aliases, before metadata access.

Output: `DiskEstimate` has canonical path, optional allocated bytes, completion, date,
partition ownership and an unchanged-empty-directory skip label. Nested roots and
node_modules are excluded from parent totals; `pulse:node_modules` aggregates the latter.
Hardlinks are deduplicated within each root; APFS sharing can differ from capacity use.
Physical traversal counts symlink allocation without following targets and skips cross-device directories.
Unreadable paths or safety limits remain partial; filesystem syscalls cannot be preempted.

[DiskEstimates](../../Sources/PulseCore/Sampling/DiskEstimates.swift) owns cursors on its actor.
[getattrlistbulk bridge](../../Sources/CSensors/DiskBulk.c) reads allocated-size metadata without per-file URL resource queries.
Passes share ≤3 seconds/200,000 entries, rotate unfinished roots, and reclaim completed roots' slices.
Containing workspace roots receive priority; other unfinished roots rotate through a reserved share.
The visible loader uses a utility queue and whole-process CPU credit capped at 1.95%.
Rendering/sampling spend the same credit. Credit is bounded so idle time cannot fund a burst.
Glance-only mode uses cached totals; hidden consumers stop scheduling work. Progress
publishes at the existing two-second cadence. Home/default-root discovery resumes across slices.
Completed estimates and node_modules totals remain visible, labelled cached during refresh.
Root mtime/identity checks reuse fresh snapshots within five minutes; expired snapshots
rescan to detect file changes that do not change a directory mtime. Only overlapping
roots lose progress when ownership changes. A single active root retains at most 12 directory handles; older frames/root switches suspend.
One home-discovery handle and transient traversal handles keep the total below 16.

[DiskCacheStore](../../Sources/PulseCore/Sampling/DiskCacheStore.swift) writes versioned atomic
checkpoints to `~/Library/Application Support/Pulse/disk-cache.json`, ≤256 KiB and ≤one write/30 seconds.
Corrupt, oversized, incompatible or different-home caches are ignored. FDA changes invalidate restored results.
Reopened directory identities/mtimes must match; otherwise that root restarts.
APFS stream cookies are never reused across opens: frames save absolute entry indexes.
Cache version 2 rejects earlier snapshots that could contain inflated totals.
A deferred checkpoint captures final progress after the 30-second write throttle;
quitting sooner can retain the prior checkpoint. FDA is re-probed per pass and on open.
Only unchanged empty directories skip traversal. Parent mtimes alone cannot validate descendant files.
If an oversized checkpoint still exceeds the cap after dropping optional empty-folder acceleration,
the previous checkpoint is retained. Unavailable storage disables persistence without prompting.

Actual consumer: [DiskUsageModel](../../Sources/PulseApp/DiskUsageModel.swift) publishes saved totals
before scanning, then feeds DiskBreakdown → DiskComposition → DiskBreakdownView in both windows.
Partial totals remain labelled; the unmeasured remainder is never a protected-folder measurement.

Checks: [cache/resume/mtime](../../Tests/PulseCoreTests/V60DiskCacheTests.swift),
[portable roots](../../Tests/PulseCoreTests/V60PortabilityTests.swift), existing v5.8/v5.9 safety,
partition and real visible-model tests; run `scripts/test.sh`.
`--disk-bench --root <path> --until-complete` prints completion wall/CPU seconds and
CPU seconds per 10k entries (up to 300 seconds). `--cache <path>` tests the real
checkpoint/relaunch flow, waiting for the throttled final save; `--steady` adds 30
two-second cached-pass observations. `--window-cadence` applies the production CPU-credit policy
to the selected root, without a GUI renderer. Initial scan CPU is separate from steady CPU.
All evidence paths redact the home prefix in code. Headless checks do not measure
the presented UI or cold OS filesystem cache.
Acceptance for window-open completion and live budgets requires desktop evidence on the machine under test.
