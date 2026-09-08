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
        args = [MESON, 'setup', build, SRC, '--buildtype=release', '-Db_ndebug=true', '-Dguest_arch=arm64', '-Dlog_handler=nslog']
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
print('Runtime libraries ready; rootfs preparation is a separate verified step.')
archive = BUILD/'alpine-minirootfs-3.22.1-aarch64.tar.gz'
expected = '188416d41f9f0c9a6e9427b75149e43ccf3a89587b2d27c9ad506e7ffca78d1c'
if not archive.exists():
    urllib.request.urlretrieve('https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/aarch64/'+archive.name, archive)
if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
    raise RuntimeError('Alpine archive SHA256 mismatch; refusing import')
rootfs = ROOT/'ios-app/Runtime/AlpineRootfs'
if not rootfs.exists():
    staging = BUILD/'rootfs-staging'
    if staging.exists(): shutil.rmtree(staging)
    run(b/'tools/fakefsify', archive, staging)
    # Close the importer before copying; no live sqlite WAL is bundled.
    shutil.move(str(staging), rootfs)
print('Verified Alpine rootfs ready')
