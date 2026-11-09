#!/bin/zsh
set -eu
cd "${0:A:h}/.."
# PULSE_ADHOC=1 ignores scripts/local.env so a build never needs a certificate.
[[ "${PULSE_ADHOC:-}" == 1 || ! -f scripts/local.env ]] || source scripts/local.env
identity="${SIGN_IDENTITY:-}"
# Defaults build the shipping app; v7 builds set PULSE_OUTPUT=build/Pulse-v7.app PULSE_BUNDLE_ID=local.pulse.monitor.v7 PULSE_VERSION=0.7.0.
[[ "${PULSE_ADHOC:-}" != 1 ]] || identity="" # even an exported SIGN_IDENTITY is ignored
output="${PULSE_OUTPUT:-build/Pulse.app}"
bundle_id="${PULSE_BUNDLE_ID:-local.pulse.monitor}"
version="${PULSE_VERSION:-0.1.0}"
if [[ "${1:-}" == "--sign-identity" && $# == 2 && -n "$2" ]]; then
    identity="$2"
elif [[ $# != 0 ]]; then
    print -u2 'Usage: scripts/bundle.sh [--sign-identity <name-or-hash>]'; exit 2
fi
if [[ -n "$identity" ]]; then
    matches=$(security find-identity -p codesigning 2>/dev/null | awk -v wanted="$identity" '
        { name=$0; sub(/^[^"]*"/, "", name); sub(/"[^"]*$/, "", name)
          hash=$2
          if (length(hash)==40 && hash !~ /[^[:xdigit:]]/ &&
              (name==wanted || tolower(hash)==tolower(wanted))) print hash }
    ' | sort -u)
    identities=("${(@f)matches}")
    if [[ ${#identities} != 1 || -z "$matches" ]]; then
        print -u2 'Requested signing identity unavailable or ambiguous; existing bundle preserved.'; exit 1
    fi
    identity="$identities[1]"
fi
mkdir -p build
stage=$(mktemp -d build/.Pulse-stage.XXXXXX)
published=no
rollback() {
    if [[ -d "$stage/Previous.app" && "$published" != yes ]]; then
        mv "$stage/Previous.app" "$output" || print -u2 "Previous bundle retained in $stage/Previous.app"
    fi
}
trap rollback EXIT
mkdir -p "$stage/Pulse.app/Contents/MacOS"
cp .build/release/Pulse "$stage/Pulse.app/Contents/MacOS/Pulse"
cat > "$stage/Pulse.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$bundle_id</string>
<key>CFBundleName</key><string>Pulse</string>
<key>CFBundleDisplayName</key><string>Pulse</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleExecutable</key><string>Pulse</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>LSHasLocalizedDisplayName</key><true/>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
mkdir -p "$stage/Pulse.app/Contents/Resources/en.lproj"
python3 scripts/make-icon.py "$stage/Pulse.app/Contents/Resources/AppIcon.icns"
print -r 'CFBundleName = "Pulse";
CFBundleDisplayName = "Pulse";' > "$stage/Pulse.app/Contents/Resources/en.lproj/InfoPlist.strings"
if [[ -n "$identity" ]]; then
    codesign -s "$identity" --force --deep --timestamp=none "$stage/Pulse.app"
else
    print -u2 'WARNING: ad-hoc signing; the Full Disk Access grant may have to be turned on again'
    codesign -s - --force --deep "$stage/Pulse.app"
fi
codesign --verify --deep --strict "$stage/Pulse.app"
requirement=$(codesign -d -r- "$stage/Pulse.app" 2>&1)
print -r -- "$requirement"
if [[ -n "$identity" && "$requirement" == *cdhash* ]]; then
    print -u2 'Requested stable signing produced a cdhash requirement; existing bundle preserved.'; exit 1
fi
[[ ! -e "$output" ]] || mv "$output" "$stage/Previous.app"
mv "$stage/Pulse.app" "$output"
published=yes
rm -rf "$stage"
