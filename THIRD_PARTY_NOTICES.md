# Third-party notices

Mac Sensor Lab is MIT-licensed. The following third-party terms apply independently to the identified portions.

## LidAngleSensor

- Project: <https://github.com/samhenrigold/LidAngleSensor>
- Fixed source commit: `f7e4e5cb46fe13a518091ce5d47f0ec2e3fecd80`
- Copyright: Sam Henry Gold and contributors
- License: Apache License 2.0
- Use: HID matching and one-shot lid-angle feature-report approach in `LidAngleProvider.swift`

The complete license text is included at `LICENSES/Apache-2.0.txt`. The implementation is substantially modified and says so in its source header.

## apple-silicon-accelerometer

- Project: <https://github.com/olvvier/apple-silicon-accelerometer>
- Fixed source commit: `203685640287449eaecf521c24d1f5e52486ecb7`
- Copyright: Copyright (c) 2026 olvvier
- License: MIT
- Use: Apple SPU HID report lengths, offsets and scaling references in `SPULiveProvider.swift`

The complete upstream license is included at `LICENSES/apple-silicon-accelerometer-MIT.txt`. Mac Sensor Lab omits the upstream driver-property writes and implements an ordinary-permission, best-effort listener in Swift.

## Stats

- Project: <https://github.com/exelban/stats>
- Fixed source commit: `db5fee1eae913e24a7e0c4a0395092d867cf902d`
- Copyright: Copyright (c) 2019 Serhiy Mytrovtsiy
- License: MIT
- Use: read-only AppleSMC connection, key decoding and M5 sensor-key references

The working implementation intentionally omits all SMC write and fan-control methods.
The complete upstream license is included at `LICENSES/Stats-MIT.txt`.

## Research references not included in the product source

See `references/upstreams.md` for the exact commits and licenses of additional projects reviewed during architecture research.
