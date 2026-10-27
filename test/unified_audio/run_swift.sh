#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
task_dir=$(mktemp -d /tmp/govar-unified-swift.XXXXXX)
trap 'rm -rf "$task_dir"' EXIT
xcrun swiftc -emit-library -emit-module -module-name AVFoundation test/unified_audio/swift/AVFoundation.swift -o "$task_dir/libAVFoundation.dylib" -emit-module-path "$task_dir/AVFoundation.swiftmodule"
xcrun swiftc -emit-library -emit-module -module-name Flutter test/unified_audio/swift/Flutter.swift -o "$task_dir/libFlutter.dylib" -emit-module-path "$task_dir/Flutter.swiftmodule"
xcrun swiftc -I "$task_dir" -L "$task_dir" -lAVFoundation -lFlutter ios/Classes/NativeWavCapture.swift test/unified_audio/swift/main.swift -o "$task_dir/test"
DYLD_LIBRARY_PATH="$task_dir" "$task_dir/test" "$task_dir/files"
