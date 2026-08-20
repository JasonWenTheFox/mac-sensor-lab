#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
configuration="${1:-debug}"

if /usr/bin/xcodebuild -license status >/dev/null 2>&1; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
else
    export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
fi

cd "$project_root"
./scripts/check-localizations.sh
swift build -c "$configuration" --product MacSensorLab

binary_path="$(swift build -c "$configuration" --show-bin-path)/MacSensorLab"
app_path="$project_root/outputs/Mac Sensor Lab.app"
contents_path="$app_path/Contents"

mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
cp "$binary_path" "$contents_path/MacOS/MacSensorLab"
cp "$project_root/Resources/Info.plist" "$contents_path/Info.plist"
cp "$project_root/Resources/AppIcon.icns" "$contents_path/Resources/AppIcon.icns"
cp "$project_root/Resources/PrivacyInfo.xcprivacy" "$contents_path/Resources/PrivacyInfo.xcprivacy"
/usr/bin/ditto \
    "$project_root/Resources/zh-Hans.lproj" \
    "$contents_path/Resources/zh-Hans.lproj"
chmod +x "$contents_path/MacOS/MacSensorLab"

/usr/bin/plutil -lint "$contents_path/Resources/PrivacyInfo.xcprivacy"
/usr/bin/plutil -lint "$contents_path/Resources/zh-Hans.lproj/Localizable.strings"
absolute_user_path_pattern="/""Users""/"
if [[ "$configuration" == "release" ]] \
    && /usr/bin/strings "$contents_path/MacOS/MacSensorLab" \
        | /usr/bin/grep -F "$absolute_user_path_pattern" >/dev/null; then
    echo "release build contains an absolute user path" >&2
    exit 1
fi
codesign_options=(--force --sign - --timestamp=none)
if [[ "$configuration" == "release" ]]; then
    codesign_options+=(--options runtime)
fi
/usr/bin/codesign "${codesign_options[@]}" "$app_path"
/usr/bin/plutil -lint "$contents_path/Info.plist"
/usr/bin/codesign --verify --deep --strict "$app_path"
if [[ "$configuration" == "release" ]]; then
    if /usr/bin/codesign --display --verbose=4 "$app_path" 2>&1 \
        | /usr/bin/grep -E 'flags=.*runtime' >/dev/null; then
        :
    else
        echo "release app signature is missing Hardened Runtime" >&2
        exit 1
    fi
fi

print -r -- "$app_path"
