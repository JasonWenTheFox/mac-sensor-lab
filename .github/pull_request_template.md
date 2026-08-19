## What changed

Describe the Provider, UI, decoder, documentation, or safety change.

## Evidence

- [ ] `swift build`
- [ ] `swift test`
- [ ] `swift run sensorlab-selftest --portable`
- [ ] App launch or relevant UI path checked

## Sensor boundary

- Data source and fixed upstream commit, if any:
- Raw, derived, estimated, or calibrated:
- Unit and expected range:
- Permission or private-interface impact:
- Unsupported/timeout behavior:
- Tested Mac model and macOS version, without unique identifiers:

## Safety checklist

- [ ] No serial number, UUID, host/user/network identifier, recording, or private fixture was added.
- [ ] No sudo, permission bypass, SPU/SMC write, fan control, or silent protected-data prompt was added.
- [ ] Third-party license and attribution requirements are satisfied.
