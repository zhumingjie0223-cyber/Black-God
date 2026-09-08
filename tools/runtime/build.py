#!/usr/bin/env python3
"""Build pinned iSH ARM64 static libraries for iOS device/simulator and a clean rootfs."""
import hashlib, os, pathlib, shutil, subprocess, sys, urllib.request
ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / 'vendor/ish'
BUILD = ROOT / '.runtime-build'
MESON = ROOT / '.runtime-build-tools/bin/meson'

def run(*args, **kwargs):
    subprocess.run([str(a) for a in args], check=True, **kwargs)

def configure(platform):
    build = BUILD / platform
    if not (build/'build.ninja').exists():
        args = [MESON, 'setup', build, SRC, '--buildtype=release', '-Db_ndebug=true', '-Dguest_arch=arm64', '-Dlog_handler=' + ('dprintf' if platform == 'host' else 'nslog')]
        if platform != 'host':
            sdk = subprocess.check_output(['xcrun', '--sdk', platform, '--show-sdk-path'], text=True).strip()
            target = 'arm64-apple-ios17.0' + ('-simulator' if platform == 'iphonesimulator' else '')
            BUILD.mkdir(exist_ok=True)
            cross = BUILD / (platform+'.ini')
            cross.write_text(f"""[binaries]
c = ['clang', '-target', '{target}', '-isysroot', '{sdk}']
ar = 'ar'
strip = 'strip'
pkg-config = 'false'
[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
needs_exe_wrapper = true
""")
            args += ['--cross-file', cross]
        run(*args)
    return build

if not MESON.exists():
    run(sys.executable, '-m', 'venv', ROOT/'.runtime-build-tools')
    run(ROOT/'.runtime-build-tools/bin/pip', 'install', 'meson==1.9.2')
for platform in ['iphoneos', 'iphonesimulator']:
    b = configure(platform)
    run('ninja', '-C', b, 'libish.a', 'libish_emu.a', 'libfakefs.a')
    dest = ROOT/'ios-app/Runtime/Libs'/platform
    dest.mkdir(parents=True, exist_ok=True)
    for name in ['libish.a','libish_emu.a','libfakefs.a']: shutil.copy2(b/name, dest/name)
# libarchive is used only by the host-side rootfs conversion tool.
b = configure('host')
run('ninja', '-C', b, 'tools/fakefsify')
run(MESON, 'configure', b, '-Dlog_handler=dprintf')
run('ninja', '-C', b, 'ish')
run(sys.executable, ROOT/'tools/runtime/prepare_image.py')
