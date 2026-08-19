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

### Changed

- The dashboard now uses a single native window so multiple sampling loops cannot contend for the same hardware providers.
- Closing the dashboard stops an active continuous recording cleanly.
- The selected automatic sampling interval is remembered, while pause state intentionally resets on launch.
- Raw Sensors provider footers now show each snapshot's actual timestamp.

### Fixed

- SPU contention is no longer reported as a privacy permission failure.
- Recent SPU samples retain their original timestamp and are not duplicated in chart history.
- Force Touch presence detection no longer unlocks the Trackpad Scale experiment.

## 0.1.0 - 2026-08-20

- Initial native SwiftUI MVP with 10 sensor providers, read-only SMC data, lid angle, best-effort SPU ambient light, JSON/CSV snapshots, diagnostics, tests, and macOS CI.
