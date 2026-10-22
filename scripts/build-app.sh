#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
cd "$project_dir"

swift build -c release

app_dir="$project_dir/build/Pomodoro Float.app"
contents_dir="$app_dir/Contents"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp ".build/release/CubeTimer" "$contents_dir/MacOS/CubeTimer"
icon_file="$project_dir/assets/branding/PomodoroFloat.icns"
if [[ ! -f "$icon_file" ]]; then
    print -u2 "Missing app icon: $icon_file"
    exit 1
fi
cp "$icon_file" "$contents_dir/Resources/PomodoroFloat.icns"
for sound_file in alarm-titititi.mp3 alarm-titititi.caf human-thud.mp3; do
    source_file="$project_dir/Sources/CubeTimer/Resources/$sound_file"
    if [[ ! -f "$source_file" ]]; then
        print -u2 "Missing bundled sound: $source_file"
        exit 1
    fi
    cp "$source_file" "$contents_dir/Resources/$sound_file"
done

cat > "$contents_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>CubeTimer</string>
    <key>CFBundleIdentifier</key><string>com.ronnel.cubetimer</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Pomodoro Float</string>
    <key>CFBundleDisplayName</key><string>Pomodoro Float</string>
    <key>CFBundleIconFile</key><string>PomodoroFloat.icns</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# An ad-hoc signature gives the local app a stable bundle identity for notification permissions.
codesign --force --sign - "$app_dir"
# Finder caches the bundle icon against the outer app directory's modification time.
touch "$app_dir"

echo "Built $app_dir"
