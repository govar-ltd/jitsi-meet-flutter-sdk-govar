#!/usr/bin/env python3
from pathlib import Path
import sys,subprocess,hashlib,json,shutil
sdk=Path(__file__).resolve().parents[2];root=Path(sys.argv[1]).resolve();source=root/'webrtc-audio-processing-2.1'
headers=root/'public-headers';headers.mkdir(exist_ok=True);shutil.copy2(sdk/'tools/aec3/GovarAEC3.h',headers/'GovarAEC3.h')
out=sdk/'ios/Frameworks/GovarAEC3.xcframework'
assert not out.exists(),'Refusing to overwrite an existing framework; archive it before rebuilding'
for platform in ['ios','sim']:
 folder=root/'package-input'/platform;folder.mkdir(parents=True,exist_ok=True)
 shutil.copy2(root/('libGovarAEC3-'+platform+'.a'),folder/'libGovarAEC3.a')
subprocess.run(['xcrun','xcodebuild','-create-xcframework','-library',str(root/'package-input/ios/libGovarAEC3.a'),'-headers',str(headers),'-library',str(root/'package-input/sim/libGovarAEC3.a'),'-headers',str(headers),'-output',str(out)],check=True)
licenses=['COPYING','webrtc/LICENSE','webrtc/PATENTS','webrtc/common_audio/third_party/spl_sqrt_floor/LICENSE','webrtc/common_audio/third_party/ooura/LICENSE','webrtc/modules/third_party/fft/LICENSE','webrtc/third_party/rnnoise/COPYING','webrtc/third_party/pffft/LICENSE','subprojects/abseil-cpp-20240722.0/LICENSE']
text='Govar standalone AEC3. Upstream webrtc-audio-processing 2.1 (WebRTC M131), Abseil 20240722.0.\nSources and reproducible build: tools/aec3/build.py in the Govar Jitsi Flutter SDK.\n\n'
for path in licenses:text+='\n===== '+path+' =====\n'+(source/path).read_text()+'\n'
(sdk/'ios/Assets/GovarAEC3-LICENSES.txt').write_text(text)
manifest={'module':'GovarAEC3','version':'webrtc-audio-processing-2.1','upstream':'https://freedesktop.org/software/pulseaudio/webrtc-audio-processing/','sourceSHA256':'ae9302824b2038d394f10213cab05312c564a038434269f11dbf68f511f9f9fe','abseil':'20240722.0','namespaces':['govar_webrtc','govar_rtc','govar_absl'],'format':'PCM16 mono 48000 Hz; 480-sample frames','aec':True,'ns':False,'agc1':False,'agc2':False,'hpf':False,'libraries':{}}
for platform in ['ios','sim']:
 p=root/('libGovarAEC3-'+platform+'.a');manifest['libraries'][platform]={'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'size':p.stat().st_size}
(sdk/'ios/Assets/GovarAEC3-build-identity.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Packaged isolated AEC3 XCFramework and complete dependency licenses')
