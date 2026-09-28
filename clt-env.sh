# Sourced by build.sh and test.sh.
TEST_FLAGS=()
# ponytail: workaround for a half-upgraded Command Line Tools install (stale 2024
# PackageDescription *.private.swiftinterface + macOS 27 SDK whose @State macro plugin
# ships only with Xcode). Only kicks in when the manifest fails to load; delete once CLT is reinstalled.
CLT=/Library/Developer/CommandLineTools
if ! swift package describe >/dev/null 2>&1 && ls "$CLT"/usr/lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule/*.private.swiftinterface >/dev/null 2>&1; then
    echo "⚠︎ Broken CLT detected, using patched ManifestAPI copy + macOS 26 SDK"
    export SWIFTPM_CUSTOM_LIBS_DIR="${TMPDIR:-/tmp}/reporadar-swiftpm-libs"
    rm -rf "$SWIFTPM_CUSTOM_LIBS_DIR" && mkdir -p "$SWIFTPM_CUSTOM_LIBS_DIR"
    cp -R "$CLT"/usr/lib/swift/pm/* "$SWIFTPM_CUSTOM_LIBS_DIR"/
    rm -f "$SWIFTPM_CUSTOM_LIBS_DIR"/ManifestAPI/PackageDescription.swiftmodule/*.private.swiftinterface
    SDK=$(ls -d "$CLT"/SDKs/MacOSX26*.sdk 2>/dev/null | sort | tail -1)
    [ -n "$SDK" ] && export SDKROOT="$SDK"
    # Deployment target 26 stops SwiftPM from finding the swift-testing macro plugin.
    TEST_FLAGS=(-Xswiftc -load-plugin-library -Xswiftc "$CLT/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib")
fi

