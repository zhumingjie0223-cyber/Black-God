#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -m)" != x86_64 || "$(uname -s)" != Linux ]]; then
    printf '%s\n' 'This pinned toolchain is for x86_64 Linux. On macOS use Xcode Swift.' >&2
    exit 1
fi
for command in curl gpg sha256sum tar pkg-config; do
    command -v "$command" >/dev/null || { printf 'Missing prerequisite: %s\n' "$command" >&2; exit 1; }
done
if ! pkg-config --exists openssl; then
    printf '%s\n' 'Missing OpenSSL development files. Install libssl-dev and pkg-config before downloading Swift.' >&2
    exit 1
fi
openssl_include=$(pkg-config --variable=includedir openssl)
if [[ -z "$openssl_include" || ! -r "$openssl_include/openssl/sha.h" ]]; then
    printf '%s\n' 'Missing OpenSSL SHA-256 header. Install libssl-dev before downloading Swift.' >&2
    exit 1
fi
toolchain_root=${BLACK_GOD_TOOLCHAIN_ROOT:-/workspace/.toolchains}
release=swift-6.2.1-RELEASE-ubuntu24.04
archive_sha256=4022cb64faf7e2681c19f9b62a22fb7d9055db6194d9e4a4bef9107b6ce10946
signing_fingerprint=52BB7E3DE28A71BE22EC05FFEF80A866B47A981F
base_url=https://download.swift.org/swift-6.2.1-release/ubuntu2404/swift-6.2.1-RELEASE
key_url=https://raw.githubusercontent.com/swiftlang/swift-org-website/4bd32dac6fa26bea67cfe387ac20f24237f797df/keys/all-keys.asc
download_dir="$toolchain_root/swift-6.2.1-download"
keyring_dir="$toolchain_root/gnupg"
mkdir -p "$download_dir" "$keyring_dir"
chmod 700 "$keyring_dir"

archive="$download_dir/$release.tar.gz"
if [[ ! -f "$archive" ]] || ! printf '%s  %s\n' "$archive_sha256" "$archive" | sha256sum --check --status; then
    curl --fail --location --silent --show-error --retry 2 --max-time 900 "$base_url/$release.tar.gz" -o "$archive"
fi
curl --fail --location --silent --show-error --retry 2 --max-time 60 "$base_url/$release.tar.gz.sig" -o "$archive.sig"
curl --fail --location --silent --show-error --retry 2 --max-time 60 "$key_url" -o "$download_dir/all-keys.asc"
printf '%s  %s\n' "$archive_sha256" "$archive" | sha256sum --check
gpg --homedir "$keyring_dir" --batch --import "$download_dir/all-keys.asc"
gpg --homedir "$keyring_dir" --batch --status-fd 1 --verify "$archive.sig" "$archive" > "$download_dir/signature-status.txt"
awk -v expected="$signing_fingerprint" '$2 == "VALIDSIG" && $3 == expected { valid = 1 } END { exit !valid }' "$download_dir/signature-status.txt"

# The release was signed in November 2025 before the published key expired in
# September 2026. Historical signature validity is preserved; no trust check is
# disabled, and the independently verified artifact SHA-256 is pinned above.
if [[ ! -x "$toolchain_root/$release/usr/bin/swift" ]]; then
    tar -xzf "$archive" -C "$toolchain_root"
fi
"$toolchain_root/$release/usr/bin/swift" --version
printf 'Toolchain ready: %s/%s/usr/bin/swift\n' "$toolchain_root" "$release"
