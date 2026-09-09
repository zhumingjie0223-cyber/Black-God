# Embedded runtime source and notices

- iSH ARM64: https://github.com/OpenMinis/ish-arm64 at 3f6384c70eefd1a370f121d3492a5f21f7767df9. Source snapshot is in vendor/ish. Preserve LICENSE.md, LICENSE.IOS and all upstream notices. iSH identifies its license as GPLv3 with the additional iOS terms.
- ISHShellExecutor.h/.m: adapted from https://github.com/OpenMinis/OpenMinis at 4ef29002e88db1e20e462ec2ff46916e8a7dcb45, src/ios/iSH. License text is LICENSE.OpenMinis. Modifications: bounded output, registration before process start, removal of Minis-specific environment, and maintained integration with Black God lifecycle cleanup.
- ISHKernel.m: Black God minimal host, with guest fault recovery adapted from the pinned iSH main.c. Uses type-derived offsets rather than Minis' outdated numeric offsets. No Minis native device offloads are linked or registered.
- Alpine minirootfs 3.22.1 aarch64: https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/aarch64/alpine-minirootfs-3.22.1-aarch64.tar.gz. SHA256: 188416d41f9f0c9a6e9427b75149e43ccf3a89587b2d27c9ad506e7ffca78d1c. This clean distribution has its own package licenses, including BusyBox and musl; see the Alpine package metadata and corresponding source packages. No preconfigured Minis image or user data is copied.

Original Black God source retains its existing MIT notices. A linked runtime build includes GPL components and must not be described or distributed as an MIT-only binary. The 1.2.0 (3) binary has been privately uploaded to App Store Connect for processing; no public App Store release has been verified. Before distribution, include applicable notices and complete corresponding source (including modifications/build scripts and sources required for bundled Alpine packages) and validate the distribution process. The repository root LICENSE does not replace any third-party license.


Black God local changes to the pinned kernel snapshot (2026-09-09):
- fs/path.c: per-task filesystem root for absolute/relative paths and symlink expansion, length guards, sandbox cache bypass, and parent mutation permission checks.
- fs/generic.c: defer truncation until guest access checks succeed; creation permission checks for missing targets.
- kernel/fs.c: require all requested permission bits; restrict sandbox chroot, mknod, ownership/mode changes, and truncation to authorized writable files.
- fs/mount.c, kernel/ptrace.c, kernel/exec.c, kernel/signal.c: restrict sandbox mounts, tracing, set-ID execution and signals to host init.
- ISHShellExecutor.m also reaps children on failed executable launch, fixes split UTF-8 output, and uses C11 atomic reader bookkeeping.

These changes are development hardening, not a completed security certification. The original source and notices remain in vendor/ish. The complete corresponding-source and public-distribution checklist remains open; do not treat a private upload as completing it.

- fs/real.c: replaces host statfs values visible to guest commands with atomic logical workspace budget/usage counters; no physical device disk statistics are returned to guest tools. NexusLinuxRuntime updates these counters before execution and during its storage monitor. This is a soft budget, not a hard filesystem quota.
