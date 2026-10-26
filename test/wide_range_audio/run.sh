#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
test_dir="$(mktemp -d /tmp/govar-wide-aec-test.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
stubs=test/voice_processing_bypass/stubs
cp test/voice_processing_bypass/mock_audio.c "$test_dir/mock_audio.c"
echo 'OSStatus AudioComponentInstanceDispose(AudioUnit u) { return 0; }' >> "$test_dir/mock_audio.c"
cp test/voice_processing_bypass/mock_webrtc.c "$test_dir/mock_webrtc.c"
echo 'OSStatus AudioComponentInstanceDispose(AudioUnit); OSStatus RTCTestDispose(AudioUnit u) { return AudioComponentInstanceDispose(u); }' >> "$test_dir/mock_webrtc.c"
xcrun clang -dynamiclib -I "$stubs" "$test_dir/mock_audio.c" -o "$test_dir/libMockAudio.dylib" -install_name "$test_dir/libMockAudio.dylib"
xcrun clang -c ios/Classes/vendor/fishhook/fishhook.c -o "$test_dir/fishhook.o"
xcrun clang -fobjc-arc -fblocks -I test/wide_range_audio/stubs -I "$stubs" -framework Foundation ios/Classes/GovarWideRangeAudio.m test/wide_range_audio/policy_test.m "$test_dir/fishhook.o" "$test_dir/libMockAudio.dylib" -o "$test_dir/test"
mkdir -p "$test_dir/normal/WebRTC.framework" "$test_dir/partial/WebRTC.framework"
for kind in normal partial; do
 define=-DTEST_NORMAL
 if [ "$kind" = partial ]; then define=-DTEST_PARTIAL; fi
 xcrun clang -dynamiclib -I "$stubs" "$define" "$test_dir/mock_webrtc.c" "$test_dir/libMockAudio.dylib" -o "$test_dir/$kind/WebRTC.framework/WebRTC" -install_name "$test_dir/$kind/WebRTC.framework/WebRTC"
done
for scenario in supported running_first unavailable rejected not_enabled bypass_rejected read_failed start_failed route_lost capture_lost; do
 "$test_dir/test" "$scenario" "$test_dir/normal/WebRTC.framework/WebRTC"
done
"$test_dir/test" partial "$test_dir/partial/WebRTC.framework/WebRTC"
"$test_dir/test" missing
