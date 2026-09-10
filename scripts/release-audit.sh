#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
cd "$project_root"

fail() {
  echo "release audit failed: $1" >&2
  exit 1
}

for prefix in .build .work outputs DerivedData; do
  if [[ -n "$(git ls-files "$prefix")" ]]; then
    fail "generated path is tracked: $prefix"
  fi
done

# Match source text without embedding the literal absolute-path prefix in this script itself.
user_path_pattern="/""Users""/"
if [[ -n "$(git grep -Il -E "$user_path_pattern" -- . ':(exclude)scripts/release-audit.sh' || true)" ]]; then
  fail "a tracked text file contains an absolute user path"
fi

secret_pattern='BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|AKIA[0-9A-Z]{16}'
if [[ -n "$(git grep -Il -E "$secret_pattern" -- . ':(exclude)scripts/release-audit.sh' || true)" ]]; then
  fail "a tracked text file matches a private-key or access-key signature"
fi

dangerous_source_pattern='IORegistryEntrySetCFPropert|AuthorizationExecuteWithPrivileges|SMCCommand[^\n]*write|/usr/bin/sudo|/usr/bin/tccutil'
if [[ -n "$(git grep -Il -E "$dangerous_source_pattern" -- Sources scripts ':(exclude)scripts/release-audit.sh' || true)" ]]; then
  fail "source contains a forbidden privilege, registry-write, or SMC-write API"
fi

usb_source='Sources/SensorCore/USBInventoryIOKitSource.swift'
usb_forbidden_pattern='IOUSBHostObject|IOServiceOpen|IORegistryEntryCreateCFProperties|SerialNumber|ContainerID|LocationID|ECID|UDID|Signature|VendorString|IOUSBLib|sendDeviceRequest|descriptor|endpoint|configure|reset|transfer'
if /usr/bin/grep -Eq "$usb_forbidden_pattern" "$usb_source"; then
  fail "USB inventory source contains an identity, bulk-property, open, or control path"
fi

camera_source='Sources/SensorCore/CameraInventoryAVFoundationSource.swift'
camera_forbidden_pattern='uniqueID|modelID|localizedName|manufacturer|linkedDevices|constituentDevices|userPreferredCamera|systemPreferredCamera|defaultDevice|authorizationStatus|requestAccess|AVCaptureDeviceInput|AVCaptureSession|DataOutput|PhotoOutput|MovieFileOutput|VideoPreview|MetadataOutput|lockForConfiguration|activeFormat|isInUseByAnotherApplication|isSuspended|isConnected|CMSampleBuffer|CVPixelBuffer'
if /usr/bin/grep -Eq "$camera_forbidden_pattern" "$camera_source"; then
  fail "Camera inventory source contains an identity, authorization, capture, or configuration path"
fi
for required_camera_path in \
  'AVCaptureDevice.DiscoverySession' \
  '.builtInWideAngleCamera' \
  '.external' \
  'mediaType: .video' \
  'position: .unspecified' \
  'NSCameraUseContinuityCameraDeviceType'; do
  /usr/bin/grep -Fq "$required_camera_path" "$camera_source" \
    || fail "Camera inventory source is missing reviewed path: $required_camera_path"
done

permission_key_pattern='NSLocation[A-Za-z]*UsageDescription|NSCameraUsageDescription|NSAppleEventsUsageDescription'
if /usr/bin/plutil -p Resources/Info.plist | /usr/bin/grep -Eq "$permission_key_pattern"; then
  fail "Info.plist declares an unsupported protected permission"
fi

microphone_purpose='Mac Sensor Lab uses microphone input only while you run Sound Input Check. Audio samples stay in memory and are never saved or exported.'
[[ "$(/usr/bin/plutil -extract NSMicrophoneUsageDescription raw -o - Resources/Info.plist)" == "$microphone_purpose" ]] \
  || fail "Info.plist must contain the reviewed microphone purpose string"
[[ "$(/usr/bin/plutil -extract NSCameraUseContinuityCameraDeviceType raw -o - Resources/Info.plist)" == "true" ]] \
  || fail "Info.plist must retain the Continuity Camera classification boundary"

[[ "$(/usr/bin/plutil -extract 'com\.apple\.security\.device\.audio-input' raw -o - Resources/MacSensorLab.entitlements)" == "true" ]] \
  || fail "the Audio Input entitlement must be enabled"
[[ "$(/usr/bin/plutil -p Resources/MacSensorLab.entitlements | /usr/bin/grep -c '=>')" == "1" ]] \
  || fail "the app entitlement file must contain only Audio Input"
if /usr/bin/plutil -p Resources/MacSensorLab.entitlements \
  | /usr/bin/grep -Fq 'com.apple.security.device.camera'; then
  fail "Camera Capabilities must not add a Camera entitlement"
fi

localized_microphone_purpose='Mac Sensor Lab 仅在你主动运行声音输入检查时使用麦克风。音频样本只在内存中即时处理，不会保存或导出。'
[[ "$(/usr/bin/plutil -extract NSMicrophoneUsageDescription raw -o - Resources/zh-Hans.lproj/InfoPlist.strings)" == "$localized_microphone_purpose" ]] \
  || fail "the Simplified Chinese microphone purpose string is missing or changed"

/usr/bin/plutil -lint Resources/Info.plist >/dev/null
/usr/bin/plutil -lint Resources/MacSensorLab.entitlements >/dev/null
/usr/bin/plutil -lint Resources/PrivacyInfo.xcprivacy >/dev/null
/usr/bin/plutil -lint Resources/zh-Hans.lproj/InfoPlist.strings >/dev/null
./scripts/check-localizations.sh >/dev/null

[[ "$(/usr/bin/plutil -extract NSPrivacyTracking raw -o - Resources/PrivacyInfo.xcprivacy)" == "false" ]] \
  || fail "privacy manifest must declare tracking disabled"
for key in NSPrivacyTrackingDomains NSPrivacyCollectedDataTypes NSPrivacyAccessedAPITypes; do
  [[ "$(/usr/bin/plutil -extract "$key" json -o - Resources/PrivacyInfo.xcprivacy)" == "[]" ]] \
    || fail "privacy manifest key $key must remain empty for this release"
done

/usr/bin/grep -Fq 'PrivacyInfo.xcprivacy' scripts/build-app.sh \
  || fail "build-app.sh does not package the privacy manifest"
/usr/bin/grep -Fq 'MacSensorLab.entitlements' scripts/build-app.sh \
  || fail "build-app.sh does not sign with the reviewed entitlements"

for required in \
  LICENSE \
  THIRD_PARTY_NOTICES.md \
  CONTRIBUTING.md \
  SECURITY.md \
  .github/ISSUE_TEMPLATE/bug-report.yml \
  .github/ISSUE_TEMPLATE/compatibility-report.yml \
  .github/ISSUE_TEMPLATE/feature-request.yml \
  .github/ISSUE_TEMPLATE/config.yml \
  docs/06-匿名兼容性贡献指南.md; do
  [[ -s "$required" ]] || fail "required release file is missing or empty: $required"
done

/usr/bin/grep -Fq 'workflow_dispatch:' .github/workflows/ci.yml \
  || fail "GitHub Actions must retain an explicit manual trigger"
if /usr/bin/grep -Eq '^[[:space:]]+(push|pull_request):' .github/workflows/ci.yml; then
  fail "GitHub Actions must not consume minutes automatically on push or pull request"
fi

[[ -x scripts/verify-local.sh ]] \
  || fail "scripts/verify-local.sh must exist and remain executable"

echo "PASS: tracked-file, permission, mutation, license, and privacy release checks succeeded"
