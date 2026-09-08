# fs/wait syscall regression tests

These pin the observable behaviour of five fixes so a future change that
reintroduces one of them fails here instead of in a user's shell.

| Fix | What broke before it | Covered by |
| --- | --- | --- |
| #30 `O_DIRECTORY` flag value | `O_DIRECTORY_` carried the x86 value `1<<16` instead of aarch64's `0x4000`, so the `ENOTDIR` check never fired and `O_DIRECT` (`1<<16` on arm64) was misread as `O_DIRECTORY`. GNU `cp` over an existing file failed with `cannot create regular file '<dst>/<src>': Not a directory`. | `regress_syscall.c`, `regress_cp.sh` |
| #30 `O_NOFOLLOW` | Translated to the host `open()`, but `generic_openat()` resolves the last path component first, so the flag was a no-op and `open(symlink, O_NOFOLLOW)` returned an fd to the target. | `regress_syscall.c` |
| #31 fakefs `stat`/`fstat` | The hook-routed branch of `fakefs_stat()` never set `dev` (nor `nlink`/`blksize`), so `stat()` and `fstat()` disagreed on `st_dev` for one file. GNU `cp` reads that as `skipping file '...', as it was replaced while being copied`. | `regress_syscall.c`, `regress_cp.sh` |
| #29 `waitpid` EINTR | `do_wait()` treated its internal 1s timeout (`_ETIMEDOUT`) as a signal, so any child running longer than a second made its parent's wait fail with `EINTR`. gcc died with `failed to get exit status: Interrupted system call`. | `regress_syscall.c` |
| `waitid` siginfo | `sys_waitid` returned the raw wait status instead of decoding it: `si_status` was `7936` for `exit(31)` and `si_code` was always 0, so a killed child looked like an exited one. `si_uid` was never set at all. | `regress_syscall.c` |

## Running

```sh
tests/regress/run.sh                          # against alpine-arm64-321 via -r
tests/regress/run.sh -i build/ish -r myrootfs # pick binary / rootfs
tests/regress/run.sh -m -f -r alpine-arm64-fakefs   # fakefs: runs the cp cases
```

`run.sh` cross-compiles `regress_syscall.c` for the guest with
`aarch64-linux-musl-gcc` (override with `$CC_GUEST`). If no cross-compiler is
installed it skips rather than fails, since the toolchain is not vendored here.

Every assertion in `regress_syscall.c` is mount-independent, so `-r` mode is the
one that matters for the syscall cases. `-f` mode exists for the `cp` cases,
which need GNU coreutils — usually only present in the fakefs rootfs. Staging a
static binary into a fakefs means registering it in `meta.db`, which is slow, so
`-f` skips the syscall binary and runs only `regress_cp.sh`.

`regress_cp.sh` needs GNU coreutils `cp`, not busybox `cp`: only GNU `cp` probes
its destination with `open(dst, O_PATH|O_DIRECTORY)` and compares
`(st_dev, st_ino)` across `stat`/`fstat`. Without it the `cp` cases skip.

To exercise #31 against a real fakefs mount point, pass the guest path of a file
under one:

```sh
tests/regress/run.sh -m -f -r alpine-arm64-fakefs -f /var/minis/shared/doc.txt
```

That requires a path-translate hook, which only the iOS app installs, so it is
optional — the `stat`/`fstat` assertions still run against the rootfs without it.

## Verifying the tests actually catch the bugs

Run the built binary against an iSH built from a commit before these fixes; it
should report 16 failures across all five areas:

```sh
aarch64-linux-musl-gcc -static -O0 -o <rootfs>/tmp/regress_syscall \
    tests/regress/regress_syscall.c
<old-ish> -r <rootfs> /tmp/regress_syscall
```
