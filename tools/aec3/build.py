#!/usr/bin/env python3
"""Reproducible standalone, namespace-isolated AEC3; requires meson/ninja in PATH.
Upstream: https://freedesktop.org/software/pulseaudio/webrtc-audio-processing/ (2.1)
Build outputs are outside the SDK. No changes to the Jitsi WebRTC binary.
"""
from pathlib import Path
import subprocess,sys,os,json,hashlib,urllib.request,tarfile
sdk=Path(__file__).resolve().parents[2]
root=Path(sys.argv[1]).resolve();root.mkdir(parents=True,exist_ok=True)
source=root/'webrtc-audio-processing-2.1'
archive=root/'webrtc-audio-processing-2.1.tar.xz'
if not archive.exists():
 urllib.request.urlretrieve('https://freedesktop.org/software/pulseaudio/webrtc-audio-processing/webrtc-audio-processing-2.1.tar.xz',archive)
expected='ae9302824b2038d394f10213cab05312c564a038434269f11dbf68f511f9f9fe'
assert hashlib.sha256(archive.read_bytes()).hexdigest()==expected,'Unexpected upstream APM archive'
if not source.exists():
 with tarfile.open(archive) as bundle:bundle.extractall(root,filter='data')
platform=sys.argv[2] if len(sys.argv)>2 else 'mac'
build=root/('build-'+platform)
arch='arm64'; target={'mac':'arm64-apple-macos12','ios':'arm64-apple-ios15.1','sim':'arm64-apple-ios15.1-simulator'}[platform]
platform_sdk={'mac':'macosx','ios':'iphoneos','sim':'iphonesimulator'}[platform]
sysroot=subprocess.check_output(['xcrun','--sdk',platform_sdk,'--show-sdk-path'],text=True).strip()
clang=subprocess.check_output(['xcrun','--find','clang'],text=True).strip();clangxx=clang+'++'
flags=['-target',target,'-isysroot',sysroot,'-fvisibility=hidden','-Dwebrtc=govar_webrtc','-Drtc=govar_rtc','-Dabsl=govar_absl']
cross=root/(platform+'.ini')
cross.write_text("[binaries]\nc = "+repr(clang)+"\ncpp = "+repr(clangxx)+"\nar = 'ar'\nstrip = 'strip'\n[host_machine]\nsystem = 'darwin'\ncpu_family = 'aarch64'\ncpu = 'arm64'\nendian = 'little'\n[built-in options]\nc_args = "+repr(flags)+"\ncpp_args = "+repr(flags)+"\nc_link_args = "+repr(flags[:4])+"\ncpp_link_args = "+repr(flags[:4])+"\n[properties]\nneeds_exe_wrapper = true\n")
if not (build/'build.ninja').exists():
 subprocess.run(['meson','setup',str(build),str(source),'--cross-file',str(cross),'--default-library=static','--buildtype=release','--force-fallback-for=abseil-cpp','-Dneon=enabled'],check=True)
subprocess.run(['meson','configure',str(build),'-Dc_link_args='+repr(flags[:4]),'-Dcpp_link_args='+repr(flags[:4])],check=True)
subprocess.run(['ninja','-C',str(build),'-j','4'],check=True)
incs=['-I'+str(source/'webrtc'),'-I'+str(source/'subprojects/abseil-cpp-20240722.0'),'-I'+str(sdk/'tools/aec3')]
obj=build/'GovarAEC3.o'
subprocess.run([clangxx,*flags,'-DWEBRTC_POSIX','-DWEBRTC_MAC',*(['-DWEBRTC_IOS'] if platform!='mac' else []),'-std=c++17','-O2',*incs,'-c',str(sdk/'tools/aec3/GovarAEC3.cc'),'-o',str(obj)],check=True)
# Meson folds required static dependencies into this archive. Do not add
# their original archives again (would duplicate Abseil/common objects).
libs=[build/'webrtc/modules/audio_processing/libwebrtc-audio-processing-2.a']
subprocess.run(['xcrun','libtool','-static','-o',str(root/('libGovarAEC3-'+platform+'.a')),str(obj),*[str(p) for p in libs]],check=True)
print('Built',platform)
