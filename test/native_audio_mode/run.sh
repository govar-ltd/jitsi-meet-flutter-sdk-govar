#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
test_tmp="$(mktemp -d /tmp/govar-native-mode-test.XXXXXX)"
trap 'rm -rf "$test_tmp"' EXIT
for scenario in NORMAL MISSING BAD_SIGNATURE; do
  xcrun clang -fobjc-arc -Werror -Wno-incompatible-pointer-types -framework Foundation \
    -I test/native_audio_mode/stubs -D"TEST_$scenario" \
    ios/Classes/GovarJitsiAudioMode.m test/native_audio_mode/adapter_test.m -o "$test_tmp/adapter"
  "$test_tmp/adapter"
done
