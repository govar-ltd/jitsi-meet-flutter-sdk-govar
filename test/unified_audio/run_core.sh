#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${1:?Usage: run_core.sh /path/to/libGovarAEC3-mac.a}"
task_dir=$(mktemp -d /tmp/govar-unified-core.XXXXXX)
trap 'rm -rf "$task_dir"' EXIT
xcrun clang++ -std=c++17 -O2 -isysroot "$(xcrun --sdk macosx --show-sdk-path)" test/unified_audio/core_test.cc "$1" -framework CoreFoundation -o "$task_dir/test"
"$task_dir/test" "$task_dir/capture.wav"
