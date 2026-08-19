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
swift build -c "$configuration" --product MacSensorLab

binary_path="$(swift build -c "$configuration" --show-bin-path)/MacSensorLab"
app_path="$project_root/outputs/Mac Sensor Lab.app"
contents_path="$app_path/Contents"

mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
cp "$binary_path" "$contents_path/MacOS/MacSensorLab"
cp "$project_root/Resources/Info.plist" "$contents_path/Info.plist"
cp "$project_root/Resources/AppIcon.icns" "$contents_path/Resources/AppIcon.icns"
chmod +x "$contents_path/MacOS/MacSensorLab"

/usr/bin/codesign --force --sign - --timestamp=none "$app_path"
/usr/bin/plutil -lint "$contents_path/Info.plist"
/usr/bin/codesign --verify --deep --strict "$app_path"

print -r -- "$app_path"
