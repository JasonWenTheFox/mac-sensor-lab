# Mac Sensor Lab

[简体中文](README.md) | English

A fact-first, offline, native macOS sensor viewer and experiment lab.

> **0.3.0 Hardware Foundation source preview:** the repository is ready for review, cloning, and local builds, but there is no notarized end-user download yet. The locally assembled app is ad-hoc signed for development verification. A public binary still needs Developer ID signing, notarization, and broader hardware testing.

![Mac Sensor Lab Overview using deterministic demo providers](docs/images/overview-demo.png)

The screenshot uses visibly labeled `--demo` fixtures and contains no readings or identifiers from the development Mac.

## What it does

Mac Sensor Lab separates sensor work into three layers and preserves provenance throughout the UI and exports:

1. **Raw facts:** 21 independent providers covering non-unique Mac model class, SoC, CPU topology, unified memory, Metal GPU and Touch ID capabilities, plus system performance, aggregate network/disk activity, battery/power, thermal pressure, display, storage, read-only SMC, best-effort SPU ambient-light/motion reports, and lid angle.
2. **Human-readable views:** a dedicated Hardware Inventory screen plus status, units, source, hardware domain, access level, compatibility evidence, five-stage readiness, Raw/Derived/Estimated/Calibrated labels, bounded history, search, and versioned JSON/CSV exports.
3. **Experiments:** level/motion trends, lid protractor, referenced light calibration, a four-channel ambient spectral fingerprint, battery and thermal trends, component thermals, internal power, and network/disk activity.

The spectral fingerprint compares only the relative proportions of four channels with undocumented response curves. It can save a local reference and report similarity, but it is not color temperature, wavelength-resolved spectroscopy, or lux. Ambient lux appears only after an external reference and remains `Estimated`. Internal temperatures are not room temperature, internal power is not wall-plug power, and the 1–10 second dashboard cadence is not vibration-frequency analysis.

Each slow provider has an independent two-second coordination boundary. A timeout degrades only that provider, does not freeze the whole refresh, and does not start duplicate reads while a synchronous call is still occupied.

The legacy `capability` field remains available, while the new model distinguishes TCC, entitlement, undocumented ordinary access, and private experimental access. Hardware presence, decoder, read path, stream, and user-facing feature readiness are also represented independently; see [docs/07-硬件清单与能力语义.md](docs/07-硬件清单与能力语义.md).

## Safety and privacy

- Offline by default: no tracking, uploads, or automatic recording.
- No root app, `sudo`, SMC/SPU writes, fan control, or system-setting changes.
- This version does not request microphone, location, camera, Accessibility, Input Monitoring, or Full Disk Access.
- No collection of serial numbers, hardware UUIDs, user/host names, network identifiers, precise location, process lists, or audio.
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
- Hardware inventory, capability semantics, and export schemas are described in [docs/07-硬件清单与能力语义.md](docs/07-硬件清单与能力语义.md). Detailed implementation status and boundaries are in [docs/05-当前实现与后续路线.md](docs/05-当前实现与后续路线.md); the anonymous compatibility workflow is in [docs/06-匿名兼容性贡献指南.md](docs/06-匿名兼容性贡献指南.md).
- See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) before contributing.

Original code and artwork are MIT licensed. Adapted and referenced upstream material remains under its recorded license.
