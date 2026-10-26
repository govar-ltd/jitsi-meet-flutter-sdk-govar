#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
test_dir="$(mktemp -d /tmp/govar-system-aec-test.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
stubs=test/voice_processing_bypass/stubs
xcrun clang -dynamiclib -I "$stubs" test/voice_processing_bypass/mock_audio.c -o "$test_dir/libMockAudio.dylib" -install_name "$test_dir/libMockAudio.dylib"
xcrun clang -c ios/Classes/vendor/fishhook/fishhook.c -o "$test_dir/fishhook.o"
xcrun clang -fobjc-arc -I "$stubs" -framework Foundation ios/Classes/GovarSystemVoiceProcessing.m test/system_voice_processing/observer_test.m "$test_dir/fishhook.o" "$test_dir/libMockAudio.dylib" -o "$test_dir/test"
mkdir -p "$test_dir/normal/WebRTC.framework" "$test_dir/partial/WebRTC.framework"
for scenario in normal partial; do
  test_define=-DTEST_NORMAL
  if [ "$scenario" = partial ]; then test_define=-DTEST_PARTIAL; fi
  xcrun clang -dynamiclib -I "$stubs" "$test_define" test/voice_processing_bypass/mock_webrtc.c "$test_dir/libMockAudio.dylib" -o "$test_dir/$scenario/WebRTC.framework/WebRTC" -install_name "$test_dir/$scenario/WebRTC.framework/WebRTC"
  "$test_dir/test" "$scenario" "$test_dir/$scenario/WebRTC.framework/WebRTC"
done
"$test_dir/test" missing
