# Changelog

All notable changes to Mac Sensor Lab will be documented here. The project follows semantic versioning once public releases begin.

## Unreleased

### Added

- Selectable 1, 2, 5, and 10 second sampling cadence, pause/resume, and in-memory history clearing.
- User-initiated continuous CSV recording with per-batch synchronization and a 50 MB safety limit.
- Separate `raw_value` and `formatted_value` CSV columns.
- Ambient-light rolling raw statistics and optional single-point, user-referenced estimated lux.
- Exportable `ambient_estimated_lux` channel clearly marked as `Estimated`.
- User-initiated import/export of portable, identity-free single-point light calibration JSON with strict validation.
- Lid-angle reference capture and signed relative change.
- Aggregate CPU utilization, load averages, raw Mach memory categories, and swap telemetry without collecting a process list.
- Aggregate receive/send throughput, packet rates, and byte counters without exporting interface or network identifiers.
- Aggregate block-storage read/write throughput, operation rates, and driver errors without reading device or volume identifiers.
- A bundled privacy manifest declaring no tracking, tracking domains, off-device collection, or required-reason API use for this macOS-only build.
- Native Raw Sensors search across providers, channels, sources, statuses, and stable IDs.
- Allowlisted battery design/full-charge capacity, derived capacity ratio, and valid controller time estimates.
- Allowlisted AGX GPU, renderer, and tiler utilization plus GPU memory counters without registry identity fields.
- User-initiated privacy-safe diagnostics JSON containing provider status and stable channel metadata but no sensor readings or free-text fields.
- A CI release audit for tracked build output, absolute user paths, secret signatures, undeclared permission expansion, forbidden mutation APIs, licenses, and privacy-manifest consistency.
- An explicit `--demo` mode with 14 deterministic, identity-free provider fixtures, a persistent on-screen banner, and preferences isolated from live mode.
- A complete English project overview alongside the original Chinese planning and implementation documentation.
- Probe CLI options for deterministic demo snapshots, value-free diagnostics, help, and strict unknown-option rejection.
- A reusable provider/snapshot contract audit for stable IDs, registry consistency, finite values, complete display metadata, timestamps, and identifying-field exclusions.
- Runtime diagnostics-export enforcement that rejects invalid, duplicate, or identifying provider/channel IDs.
- A privacy-safe compatibility issue form and anonymous cross-model contribution guide enforced by the release audit.
- Value-free sampling health diagnostics with refresh counts/duration, per-provider status transitions, and consecutive issue counts.

### Changed

- Demo mode now isolates lid-angle reference preferences in addition to sampling and ambient-light calibration.
- The dashboard now uses a single native window so multiple sampling loops cannot contend for the same hardware providers.
- Closing the dashboard stops an active continuous recording cleanly.
- The selected automatic sampling interval is remembered, while pause state intentionally resets on launch.
- Raw Sensors provider footers now show each snapshot's actual timestamp.

### Fixed

- Corrupt or extreme counters can no longer overflow CPU totals, network/disk/GPU aggregation, memory page conversion, fan-count conversion, sampling duration, or byte-rate formatting.
- Duplicate provider IDs no longer trap while constructing read or dashboard ordering; they remain visible to the contract audit.
- Network and disk rate baselines now reset when aggregate interface/device counts change or elapsed time is non-finite, preventing topology changes from becoming false throughput spikes.
- Missing battery booleans remain unknown instead of becoming false, while invalid charge percentages and non-finite electrical derivations are omitted.
- Ambient calibration, rolling statistics, and relative-angle derivations now reject arithmetic overflow even when every input is individually finite.
- Continuous CSV recording now re-seeks and recounts the real file end before every batch, preserving external appends, enforcing the size limit against actual bytes, and stopping if the header is externally truncated.
- CSV text fields now escape standalone carriage returns and formula-leading characters while preserving numeric `raw_value` cells.
- Ambient-light calibration import now performs a bounded 64 KiB local-file read before strict decoding.
- Concurrent initial and automatic recording flushes no longer duplicate an identical provider snapshot.
- SPU contention is no longer reported as a privacy permission failure.
- Recent SPU samples retain their original timestamp and are not duplicated in chart history.
- Force Touch presence detection no longer unlocks the Trackpad Scale experiment.

## 0.1.0 - 2026-08-20

- Initial native SwiftUI MVP with 10 sensor providers, read-only SMC data, lid angle, best-effort SPU ambient light, JSON/CSV snapshots, diagnostics, tests, and macOS CI.
