#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
catalog="$project_root/Resources/Localizable.xcstrings"
tracked_strings="$project_root/Resources/zh-Hans.lproj/Localizable.strings"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/mac-sensor-l10n.XXXXXX")"

cleanup() {
    rm -R "$temporary_directory"
}
trap cleanup EXIT

xcrun xcstringstool compile "$catalog" \
    --output-directory "$temporary_directory" \
    --language zh-Hans \
    --serialization-format text

generated_strings="$temporary_directory/zh-Hans.lproj/Localizable.strings"
if ! cmp -s "$tracked_strings" "$generated_strings"; then
    echo "localization check failed: generated zh-Hans strings are out of date" >&2
    echo "run: xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory Resources --language zh-Hans --serialization-format text" >&2
    exit 1
fi

/usr/bin/plutil -lint "$tracked_strings" >/dev/null
echo "PASS: String Catalog and generated Simplified Chinese resources are in sync"
