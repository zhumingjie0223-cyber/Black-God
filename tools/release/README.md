# Black God release source package

The source package includes the current iOS source, generated Shuyu bundle and its source, the modified iSH snapshot, original notices, runtime build scripts, and Alpine package recipes and source archives. It excludes credentials, application containers, signing identities, Xcode caches, and IPA files.

Alpine 3.22.1 contains 16 installed binary packages from 10 source origins. Obtain each origin's `main/<origin>` directory from the exact aports commit in its installed APK database. Keep all recipe files. Fetch the distfiles named by each APKBUILD and verify every SHA-512 checksum without executing the APKBUILD on the host. The alpine-base recipe generates release metadata and has no external source archive. Record packages, origin commits and checked files in `manifest.json`; incomplete or mismatched collections are rejected by the packager.

Run:

```
python3 tools/release/package_source.py --alpine-dir /path/to/verified-alpine-sources --output /path/to/Black-God-1.2.0-build3-source.tar.gz
```

The packager writes a SHA-256 file manifest, normalizes archive ownership/times and reads every archive member back for verification. Rebuild the App with `make generate`, then the Xcode project and scheme documented in `ios-app/AppStore/SUBMIT_GUIDE.md`. Build tools (Xcode, Python, ninja, Meson, llvm, libarchive, pkg-config and XcodeGen) are prerequisites; the runtime build verifies the original Alpine rootfs download before conversion.

Source packaging does not validate API credentials, authorize public CLI OAuth client identities, certify GPL compliance, or submit App Review. Public access to the source and applicable notices must be established before public binary distribution. Preserve original third-party licensing; do not label the linked App MIT-only.
