# Changelog

All notable changes to Mac Sensor Lab will be documented here. The project follows semantic versioning once public releases begin.

## Unreleased

No changes yet.

## 0.3.0 - 2026-09-05

### Added

- A dedicated Hardware Inventory screen backed by six independent providers for the non-unique Mac model class, Apple SoC family, CPU topology, physical/unified memory, public Metal GPU capabilities, and Touch ID capability.
- Independent `HardwareDomain`, `SensorAccessLevel`, compatibility-evidence, and five-stage readiness fields so hardware presence, decoder status, read path, stream state, and user-feature readiness are no longer collapsed into one capability label.
- Versioned full-snapshot JSON exports (`schemaVersion: 1`) and privacy-safe diagnostics schema v3; JSON, diagnostics, and CSV now carry the new semantic fields while retaining the legacy capability value.
- Search and Simplified Chinese UI coverage for hardware domains, access levels, compatibility evidence, and readiness states.

### Changed

- The live and deterministic demo registries now contain the same 21 provider IDs and matching metadata semantics.
- Demo fixtures now cover previously drifting uptime/storage kinds, SPU gyroscope and lid discovery channels, hardware-presence IDs, and conditional battery/network/disk/SMC channels.
- Presence-only SPU discovery and experimental-hardware checks explicitly report partial feature readiness instead of implying that a continuous measurement is already usable.

### Security and privacy

- Hardware inventory accepts only bounded model-level strings and counters. It does not read or export serial numbers, hardware UUIDs, host/user names, Metal registry IDs, biometric enrollment state, or authentication results.
- Touch ID capability detection uses a non-prompting LocalAuthentication check; it neither authenticates the user nor infers Secure Enclave presence.

## 0.2.0 - 2026-08-31

### Added

- A Light Spectrum experiment that normalizes the four ambient spectral channels into relative proportions, stores an optional local reference, and reports bounded similarity and the largest channel shift without claiming color temperature, wavelengths, or lux.
- A single-flight provider read gate with an independent two-second coordination boundary, preventing one blocked synchronous sensor call from freezing a full dashboard refresh or spawning duplicate reads.
- Dedicated privacy-aware bug and feature-request forms plus a private GitHub vulnerability-reporting link.
- A single offline `verify-local.sh` entry point for formatting, localization, release-boundary checks, builds, XCTest, portable self-test, Release bundle verification, and opt-in hardware/sanitizer/SPU stability checks without consuming GitHub Actions minutes.
- Component Thermals and System Power Trend experiments that reuse the fixed read-only SMC allowlist for bounded CPU/GPU comparisons and recent power averages/peaks, with internal-versus-ambient/wall-power caveats.
- Network Throughput and Disk Activity experiments with bounded, dual-series receive/send and read/write history, recent averages, and explicit aggregate-identity caveats.
- A Thermal Trend experiment that retains the public pressure-state order, recent peak, and transition count without presenting the 0–3 ordinal as temperature or a linear physical scale.
- A conservative Battery Trend experiment derived from bounded in-memory public charge history, gated on an explicit discharging state, minimum duration/sample/drop thresholds, and safe handling of charging transitions or malformed data.
- A separate public `IOPowerSources` provider for the active AC/battery/UPS source, public charge/charging state, OS low-battery warning level, and valid time estimates without reading power-source identity or adapter metadata.
- Native English and Simplified Chinese UI localization backed by a checked-in String Catalog, generated `.lproj` resources, catalog/key consistency tests, and a bounded display adapter for dynamic summaries, channel labels, enum values, units, and app-owned notes.
- An Overview provider-health summary with distinct loading, available, limited, permission-required, unavailable, and error counts, a launch-wide status-transition total, and direct Raw Sensors/Diagnostics review actions.
- A reproducible static admission audit for OpenMultitouchSupport 4.0.0, documenting its matching checksum and architecture as well as the privacy and distribution blockers that prevent direct integration.
- Selectable 1, 2, 5, and 10 second sampling cadence, pause/resume, and in-memory history clearing.
- User-initiated continuous CSV recording with per-batch synchronization and a 50 MB safety limit.
- Separate `raw_value` and `formatted_value` CSV columns.
- Ambient-light rolling raw statistics and optional one-to-eight-point, user-referenced estimated lux with normalized linear fitting and RMSE.
- Exportable `ambient_estimated_lux` channel clearly marked as `Estimated`.
- User-initiated import/export of portable, identity-free, bounded multi-point light calibration JSON with strict validation and legacy single-point import.
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
- An explicit `--demo` mode with 15 deterministic, identity-free provider fixtures, a persistent on-screen banner, and preferences isolated from live mode.
- A complete English project overview alongside the original Chinese planning and implementation documentation.
- Probe CLI options for deterministic demo snapshots, value-free diagnostics, help, and strict unknown-option rejection.
- A reusable provider/snapshot contract audit for stable IDs, registry consistency, finite values, complete display metadata, timestamps, and identifying-field exclusions.
- Runtime diagnostics-export enforcement that rejects invalid, duplicate, or identifying provider/channel IDs.
- A privacy-safe compatibility issue form and anonymous cross-model contribution guide enforced by the release audit.
- Value-free sampling health diagnostics with refresh counts/duration, per-provider status transitions, and consecutive issue counts.
- Provider contract cardinality/text bounds plus blank-label, duplicate-note, loading-state, and empty-available consistency checks.
- Separate Diagnostics counts and guidance for loading, permission-required, unavailable, and error provider states.
- A low-rate Motion Trend experiment with RMS variation and peak-to-peak acceleration statistics.

### Changed

- GitHub Actions is manual-only; pushes and pull requests no longer consume hosted-runner minutes automatically, and the local verification script remains the release authority.
- App assembly now builds and verifies a fresh same-output-filesystem staging bundle before replacing the previous generated bundle, preventing removed or renamed resources from leaking into later builds.
- System-volume storage now uses public Foundation resource keys and keeps ordinary, important-use, and opportunistic availability as separate bounded facts.
- Optimized Release app bundles now enable and verify Hardened Runtime even under local ad-hoc signing; the deterministic Demo also passes a local launch-survival smoke test.
- Existing ambient-light calibration now accepts up to eight strictly monotonic reference points, supports undoing the last point, and preserves legacy single-point JSON/UserDefaults compatibility.
- SMC temperature lookup now selects fixed M1, M2, M3, M4, or M5 key catalogs, keeps generation detection out of exports, and safely falls back to generation-neutral keys.
- CI now compiles all products in optimized Release mode and assembles/verifies the ad-hoc signed App Bundle from the Release executable.
- Demo mode now isolates lid-angle reference preferences in addition to sampling and ambient-light calibration.
- The dashboard now uses a single native window so multiple sampling loops cannot contend for the same hardware providers.
- Closing the dashboard stops an active continuous recording cleanly.
- The selected automatic sampling interval is remembered, while pause state intentionally resets on launch.
- Overview cards now show the original sample time as a live relative age, so a retained degraded SPU reading cannot look freshly sampled.
- Raw Sensors provider footers now show each snapshot's actual timestamp.

### Fixed

- SMC and lid-angle open failures now distinguish missing hardware, permission denial, transient contention, and other errors instead of classifying every failure as a privacy permission problem.
- The lid protractor now uses the provider's documented 0–360 degree range instead of clipping valid readings at 180 degrees.
- The self-test CLI now rejects unknown options and exposes explicit help; SPU stability failures still print their bounded result summary.
- GPU-memory and disk-driver counters now require exact nonnegative integer `NSNumber` payloads, preventing negative or fractional registry values from wrapping into enormous unsigned readings.
- Storage failures no longer echo system error text that could contain a local path, and impossible capacity relationships are omitted instead of becoming used-space claims.
- Display telemetry now distinguishes current-mode pixel dimensions from logical point dimensions and only derives a backing scale from consistent, bounded axes.
- Settings no longer claims that existing automatically sampled read-only HID providers are opt-in.
- The former Vibration Recorder placeholder no longer implies that 1–10 second dashboard samples can measure vibration frequency.
- Sampling health now caps both per-cycle scanning and cross-cycle provider state at the 256-provider contract limit, preventing changing malformed IDs from growing memory indefinitely.
- Contract auditing now prefix-bounds UTF-8 validation and excludes oversized IDs/text from hashing, lowercasing, metadata comparison, and issue messages.
- Chart history now retains only plotted/derived channels, caps total series at 256 and points per series at 600, and rejects stale or malformed samples.
- Snapshot, diagnostics, calibration, and recording files now use same-directory atomic replacement through an owner-only `0600` temporary file.
- Dashboard provider results now pass a fail-closed snapshot gate before reaching UI, history, or recording; malformed payloads become a fixed, non-echoing error snapshot at their registered position.
- Continuous recording now rejects contract-invalid batches before row encoding and caps cross-batch deduplication state at 256 Provider identities.
- Recording finalization now refreshes the real file-end byte count and always transitions the recorder to closed before reporting synchronization, seek, or close errors.
- Contract timestamp tolerance now treats negative, non-finite, or overflowing values as zero instead of allowing future-snapshot checks to be bypassed.
- Contract auditing now stops scanning and caps returned output at 4,096 issues even when every allowed channel violates several fields.
- Corrupt or extreme counters can no longer overflow CPU totals, network/disk/GPU aggregation, memory page conversion, fan-count conversion, sampling duration, or byte-rate formatting.
- Continuous CSV recording now preflights the complete batch size and then encodes/writes one row at a time instead of retaining a second full-batch copy in memory.
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
