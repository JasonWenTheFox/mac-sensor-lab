# Mac Sensor Lab

[简体中文](README.md) | English

A fact-first, offline, native macOS sensor viewer and experiment lab.

> **0.3.1 Display & Storage Hardware Foundation source preview:** the repository is ready for review, cloning, and local builds, but there is no notarized end-user download yet. The locally assembled app is ad-hoc signed for development verification. A public binary still needs Developer ID signing, notarization, and broader hardware testing.

![Mac Sensor Lab Overview using deterministic demo providers](docs/images/overview-demo.png)

The screenshot uses visibly labeled `--demo` fixtures and contains no readings or identifiers from the development Mac.

## What it does

Mac Sensor Lab separates sensor work into three layers and preserves provenance throughout the UI and exports:

1. **Raw facts:** 26 independent providers covering non-unique Mac model class, SoC, CPU topology, unified memory, Metal GPU and Touch ID capabilities; a public Core Audio device inventory; per-display modes, gamut, EDR, and estimated geometry; system-disk media properties and NVMe SMART scalars/lossless cumulative counters; the current Wi-Fi radio link; plus system performance, aggregate network/disk activity, battery/power, thermal pressure, read-only SMC, best-effort SPU ambient-light/motion reports, and lid angle.
2. **Human-readable views:** a dedicated Hardware Inventory screen with expandable fact cards, plus status, units, source, hardware domain, access level, compatibility evidence, five-stage readiness, Raw/Derived/Estimated/Calibrated labels, bounded history, search, and versioned JSON/CSV exports.
3. **Experiments:** a session-only physical display ruler, a Force Touch normalized-pressure/stage visualizer, Wi-Fi signal/noise trends, a user-started nearby Wi-Fi channel snapshot and Sound Input Check, level/motion trends, lid protractor, referenced light calibration, a four-channel ambient spectral fingerprint, battery and thermal trends, component thermals, internal power, and network/disk activity.

The spectral fingerprint compares only the relative proportions of four channels with undocumented response curves. It can save a local reference and report similarity, but it is not color temperature, wavelength-resolved spectroscopy, or lux. Ambient lux appears only after an external reference and remains `Estimated`. Internal temperatures are not room temperature, internal power is not wall-plug power, and the 1–10 second dashboard cadence is not vibration-frequency analysis.

Physical display dimensions may be CoreGraphics' 72-DPI estimate when EDID is unavailable, so system dimensions, diagonal, and PPI always remain `Estimated`. The Experiments ruler lets the user match a real ruler against the current display's horizontal axis and compares `System Estimated` with `User Calibrated` results. It does not infer vertical size or diagonal; calibration remains limited to the current app session and display mode and is excluded from snapshots and exports. Storage hardware includes only fixed categories and bounded numeric facts from the whole disk associated with the system volume and does not infer SMART from Disk Arbitration metadata. A separate NVMe SMART provider calls only Apple's public `SMARTReadData` API to show warning bits, composite temperature, spare capacity, the controller's lifetime-use estimate, and ten 128-bit cumulative counters. Counters use lossless decimal text instead of `Double`. Data-unit byte channels are exact conversions of the reported unit counts, but the source units are rounded up and therefore do not claim exact historical I/O bytes. The provider excludes device model, serial, UUID, volume name, paths, identify data, and detailed error logs, and it does not collapse those fields into a single “health score.”

The Force Touch Pressure Lab starts only on an explicit user action and receives public AppKit `pressure`, `stage`, and `stageTransition` events only inside the app's interaction area. Its chart splits on every stage change and retains at most 240 in-memory samples; stopped data is cleared on request or when the page is left. It installs no input monitor, reads no raw contacts or device IDs, and adds nothing to snapshots or exports. Pressure from 0 to 1 is normalized within each stage and is not force, weight, grams, or a calibrated physical measurement.

The Wi-Fi Radio provider uses public CoreWLAN getters for power/service/association state, RSSI, noise, derived SNR, channel, width, band, PHY, security mode, negotiated transmit rate, and transmit power. Error sentinels and unknown enum values are omitted. A separate Nearby Wi-Fi Channels experiment runs one public CoreWLAN scan only after a second user confirmation, then immediately reduces at most 512 results to band, channel, reported-record count, RSSI, and width summaries. It reads no network name, access-point address, MAC/IP address, interface name, country code, information elements, or location; requests no Location permission; and sends no scan data to providers, snapshots, diagnostics, persistence, or exports. Negotiated PHY rate is not application throughput, and a scan snapshot is not airtime use or a complete congestion measurement.

The Audio Hardware provider queries only public Core Audio HAL properties. It reports current visible/available and input/output/duplex device counts plus the default input/output connection class, channel count, nominal sample rate, and device-level latency. Numeric AudioDevice handles exist only within one read; device/model UIDs, names, manufacturers, and free-form driver text are not queried. The provider does not open an audio stream, capture PCM, record audio, or request microphone permission. Nominal sample rate is configuration rather than recorded data, and device latency excludes additional stream latency and safety offset.

Sound Input Check is a separate `publicTCC` experiment. It never runs at launch or during automatic provider sampling: the first button shows a purpose explanation, and only a second user confirmation can ask macOS for microphone access. An authorized session is limited to five minutes and releases its input stream on stop, page exit, audio-configuration change, or system sleep. Each Float32 PCM buffer is reduced inside the audio callback to at most 128 channel-averaged min/max waveform bins, all-channel RMS/peak amplitudes, and dBFS relative to digital full scale 1.0; level history is capped at 300 points. The spectrum selects the largest fixed 256/512/1024/2048-frame window that fits the current buffer, removes its mean, applies a Hann window, and reduces the positive-frequency DFT to at most 128 relative bins. Its current non-DC peak is 0 dB, its display floor is −80 dB, and it updates at no more than 10 Hz. Raw samples never leave the callback and are not retained, played, written, or exported, while derived values remain outside snapshots and diagnostics and are cleared on page exit. dBFS is not dBA, dB SPL, or calibrated loudness. The “strongest non-DC bin center” is a finite-resolution frequency bin, not sound-source, pitch, speech, or environment recognition.

Each slow provider has an independent two-second coordination boundary. A timeout degrades only that provider, does not freeze the whole refresh, and does not start duplicate reads while a synchronous call is still occupied.

The legacy `capability` field remains available, while the new model distinguishes TCC, entitlement, undocumented ordinary access, and private experimental access. Hardware presence, decoder, read path, stream, and user-facing feature readiness are also represented independently; see [docs/07-硬件清单与能力语义.md](docs/07-硬件清单与能力语义.md).

## Safety and privacy

- Offline by default: no tracking, uploads, or automatic recording.
- No root app, `sudo`, SMC/SPU writes, fan control, or system-setting changes.
- Microphone permission can be requested only after a second confirmation inside Sound Input Check. This version does not request Location, Camera, Accessibility, Input Monitoring, or Full Disk Access.
- No collection of serial numbers, hardware UUIDs, user/host names, network identifiers, precise location, process lists, or recordings. Sound Input Check retains or exports no PCM samples.
- Missing, denied, busy, timed-out, and malformed sources remain explicit states instead of simulated readings.

Undocumented HID, SMC, and AGX behavior can change across models and macOS releases. This is not a medical, legal-metrology, industrial-safety, or certified measurement instrument.

## Build locally

Requires macOS 14+ and an Xcode installation that has completed first-launch setup:

```bash
swift build
swift test
./scripts/verify-local.sh
./scripts/build-app.sh release
open "outputs/Mac Sensor Lab.app" --args --demo
```

`scripts/verify-local.sh` performs formatting, localization, release-boundary checks, a Debug build, all XCTest cases, the portable self-test, and Release app/Hardened Runtime verification locally without contacting GitHub. Hardware reads, sanitizers, and SPU stability checks are opt-in. GitHub Actions is manual-only and does not run automatically on pushes or pull requests.

Live hardware checks and probes:

```bash
swift run sensorlab-selftest
swift run sensorlab-selftest --spu-stability
swift run sensorlab-probe
swift run sensorlab-probe -- --diagnostics
```

Live commands may read local sensors and the unfiltered probe can print a full snapshot. Public issues should attach only an explicitly exported, manually reviewed **Privacy-Safe Diagnostics** report.

## Contributing and documentation

- Use the privacy-safe compatibility form for model-specific problems and GitHub private vulnerability reporting for security issues.
- New providers require stable non-identifying IDs, documented units/provenance/failure behavior, fixture tests, and truthful data-nature labels.
- Hardware inventory, capability semantics, and export schemas are described in [docs/07-硬件清单与能力语义.md](docs/07-硬件清单与能力语义.md). Detailed implementation status and boundaries are in [docs/05-当前实现与后续路线.md](docs/05-当前实现与后续路线.md); the Display/NVMe, IOReport, Wi-Fi, and Audio records are [docs/08-显示校准与NVMe健康可行性.md](docs/08-显示校准与NVMe健康可行性.md), [docs/09-IOReport普通权限可行性.md](docs/09-IOReport普通权限可行性.md), [docs/10-Wi-Fi无线电边界.md](docs/10-Wi-Fi无线电边界.md), and [docs/11-Audio硬件清单边界.md](docs/11-Audio硬件清单边界.md); the anonymous compatibility workflow is in [docs/06-匿名兼容性贡献指南.md](docs/06-匿名兼容性贡献指南.md).
- See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) before contributing.

Original code and artwork are MIT licensed. Adapted and referenced upstream material remains under its recorded license.
