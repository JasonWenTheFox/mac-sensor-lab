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

dangerous_source_pattern='IORegistryEntrySetCFPropert|AuthorizationExecuteWithPrivileges|SMCCommand[^\n]*write|/usr/bin/sudo'
if [[ -n "$(git grep -Il -E "$dangerous_source_pattern" -- Sources scripts ':(exclude)scripts/release-audit.sh' || true)" ]]; then
  fail "source contains a forbidden privilege, registry-write, or SMC-write API"
fi

permission_key_pattern='NSMicrophoneUsageDescription|NSLocationUsageDescription|NSCameraUsageDescription|NSAppleEventsUsageDescription'
if /usr/bin/plutil -p Resources/Info.plist | /usr/bin/grep -Eq "$permission_key_pattern"; then
  fail "Info.plist declares a protected permission that this release does not implement"
fi

/usr/bin/plutil -lint Resources/Info.plist >/dev/null
/usr/bin/plutil -lint Resources/PrivacyInfo.xcprivacy >/dev/null

[[ "$(/usr/bin/plutil -extract NSPrivacyTracking raw -o - Resources/PrivacyInfo.xcprivacy)" == "false" ]] \
  || fail "privacy manifest must declare tracking disabled"
for key in NSPrivacyTrackingDomains NSPrivacyCollectedDataTypes NSPrivacyAccessedAPITypes; do
  [[ "$(/usr/bin/plutil -extract "$key" json -o - Resources/PrivacyInfo.xcprivacy)" == "[]" ]] \
    || fail "privacy manifest key $key must remain empty for this release"
done

/usr/bin/grep -Fq 'PrivacyInfo.xcprivacy' scripts/build-app.sh \
  || fail "build-app.sh does not package the privacy manifest"

for required in \
  LICENSE \
  THIRD_PARTY_NOTICES.md \
  CONTRIBUTING.md \
  SECURITY.md \
  .github/ISSUE_TEMPLATE/compatibility-report.yml \
  docs/06-匿名兼容性贡献指南.md; do
  [[ -s "$required" ]] || fail "required release file is missing or empty: $required"
done

echo "PASS: tracked-file, permission, mutation, license, and privacy release checks succeeded"
