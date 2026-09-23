#!/usr/bin/env python3
"""Run the real guest uname implementation under host AddressSanitizer."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(source=None):
    source = source or ROOT / "vendor/ish/kernel/uname.c"
    with tempfile.TemporaryDirectory(prefix="blackgod-uname-") as directory:
        executable = Path(directory) / "test-uname"
        subprocess.run([
            "clang", "-std=gnu11", "-O1", "-g", "-fsanitize=address,undefined",
            "-fno-omit-frame-pointer", "-DGUEST_ARM64=1", "-DENGINE_ASBESTOS=1",
            "-DLOG_HANDLER_DPRINTF=1", "-I", str(ROOT / "vendor/ish"),
            str(source), str(ROOT / "tools/runtime/test_uname.c"),
            "-o", str(executable),
        ], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    run()
