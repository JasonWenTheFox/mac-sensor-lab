#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
run_hardware=false
run_sanitizers=false
run_spu_stability=false

usage() {
  cat <<'EOF'
Usage: ./scripts/verify-local.sh [options]

Runs the release-equivalent checks locally without contacting GitHub.

Options:
  --hardware       Also audit live hardware snapshots (values are not printed).
  --sanitizers     Also run the XCTest suite with AddressSanitizer and ThreadSanitizer.
  --spu-stability  Also run the bounded read-only SPU stability check.
  --all            Enable every optional local check.
  --help           Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hardware)
      run_hardware=true
      ;;
    --sanitizers)
      run_sanitizers=true
      ;;
    --spu-stability)
      run_spu_stability=true
      ;;
    --all)
      run_hardware=true
      run_sanitizers=true
      run_spu_stability=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
  shift
done

if ! /usr/bin/xcodebuild -license status >/dev/null 2>&1; then
  echo "local verification requires Xcode with its license accepted" >&2
  exit 1
fi

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
cd "$project_root"

phase() {
  printf '\n==> %s\n' "$1"
}

phase "Formatting"
xcrun swift-format lint --recursive Sources Tests Package.swift

phase "Localization and release boundaries"
./scripts/check-localizations.sh
./scripts/release-audit.sh

phase "Debug build and XCTest"
swift build
swift test

phase "Portable contract and export self-test"
swift run --skip-build sensorlab-selftest --portable

if [[ "$run_hardware" == true ]]; then
  phase "Live hardware contract self-test"
  swift run --skip-build sensorlab-selftest
fi

if [[ "$run_spu_stability" == true ]]; then
  phase "Bounded read-only SPU stability self-test"
  swift run --skip-build sensorlab-selftest --spu-stability
fi

if [[ "$run_sanitizers" == true ]]; then
  phase "AddressSanitizer XCTest"
  swift test --sanitize address
  phase "ThreadSanitizer XCTest"
  swift test --sanitize thread
fi

phase "Optimized app bundle and Hardened Runtime"
./scripts/build-app.sh release

phase "Complete"
echo "PASS: local verification succeeded without contacting GitHub"
