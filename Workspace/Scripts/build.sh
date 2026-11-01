#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TASK_OUTPUT="${1:-$TASK_ROOT/../Notch Workspace.app}"
TASK_DESTINATION="$TASK_OUTPUT"
# Build and sign outside cloud-backed Documents, which can automatically attach
# Finder metadata while a bundle is being signed.
TASK_STAGING="$(mktemp -d /private/tmp/notch-workspace.XXXXXX)"
trap 'rm -rf "$TASK_STAGING"' EXIT
TASK_OUTPUT="$TASK_STAGING/Notch Workspace.app"
TASK_BINARY_DIR="$TASK_ROOT/build/Workspace"
mkdir -p "$TASK_BINARY_DIR" "$TASK_OUTPUT/Contents/MacOS" "$TASK_OUTPUT/Contents/Resources" "$TASK_OUTPUT/Contents/Frameworks"
TASK_SDK="$(xcrun --sdk macosx --show-sdk-path)"
# The standalone Command Line Tools omit the SwiftUI macro plugin required by
# the macOS 27 SDK. Prefer their installed macOS 26 SDK for this macOS 14+ app.
TASK_CLT_SDK="$(xcode-select -p)/SDKs/MacOSX26.sdk"
if [[ -d "$TASK_CLT_SDK" ]]; then TASK_SDK="$TASK_CLT_SDK"; fi
# Xcode's canvas preview is not part of the application build.
sed '/^#Preview/,$d' "$TASK_ROOT/boringNotch/components/Notch/NotchShape.swift" > "$TASK_BINARY_DIR/NotchShape.swift"
printf 'Building Notch Workspace for %s…\n' "$(uname -m)"
swiftc -swift-version 5 -O -parse-as-library \
    -sdk "$TASK_SDK" -target "$(uname -m)-apple-macosx14.0" \
    -module-name NotchWorkspace \
    "$TASK_ROOT"/Workspace/Sources/*.swift \
    "$TASK_ROOT/Workspace/Tests/WorkspaceTests.swift" \
    "$TASK_BINARY_DIR/NotchShape.swift" \
    -o "$TASK_BINARY_DIR/NotchWorkspace"
cp "$TASK_BINARY_DIR/NotchWorkspace" "$TASK_OUTPUT/Contents/MacOS/NotchWorkspace"
cp "$TASK_ROOT/Workspace/Resources/Info.plist" "$TASK_OUTPUT/Contents/Info.plist"
cp "$TASK_ROOT/LICENSE" "$TASK_OUTPUT/Contents/Resources/LICENSE"
cp "$TASK_ROOT/Workspace/NOTICE.md" "$TASK_OUTPUT/Contents/Resources/NOTICE.md"
cp "$TASK_ROOT/mediaremote-adapter/mediaremote-adapter.pl" "$TASK_OUTPUT/Contents/Resources/"
ditto "$TASK_ROOT/mediaremote-adapter/MediaRemoteAdapter.framework" "$TASK_OUTPUT/Contents/Frameworks/MediaRemoteAdapter.framework"
cp "$TASK_ROOT/Workspace/Resources/MediaRemoteAdapter-LICENSE" "$TASK_OUTPUT/Contents/Resources/"
cp "$TASK_ROOT/Workspace/Resources/DynamicNotchKit-LICENSE" "$TASK_OUTPUT/Contents/Resources/"
swift "$TASK_ROOT/Workspace/Scripts/Icon.swift" "$TASK_BINARY_DIR/AppIcon.iconset"
iconutil -c icns "$TASK_BINARY_DIR/AppIcon.iconset" -o "$TASK_OUTPUT/Contents/Resources/AppIcon.icns"
# Cloud-backed Documents can attach Finder metadata as bundles are created.
# Remove only signing-incompatible metadata; leave security attributes intact.
xattr -r -d com.apple.FinderInfo "$TASK_OUTPUT" 2>/dev/null || true
xattr -r -d com.apple.ResourceFork "$TASK_OUTPUT" 2>/dev/null || true
codesign --force --sign - "$TASK_OUTPUT"
codesign --verify --deep --strict "$TASK_OUTPUT"
ditto --norsrc --noextattr "$TASK_OUTPUT" "$TASK_DESTINATION"
ditto -c -k --keepParent --norsrc --noextattr "$TASK_OUTPUT" "${TASK_DESTINATION%.app}.zip"
printf 'Built: %s\n' "$TASK_DESTINATION"
