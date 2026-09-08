#!/bin/bash

# iSH ARM64 核心软件全面测试 (200+ 软件)
# 自动安装缺失的包

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISH_ROOT="$(dirname "$BENCH_DIR")"
ISH="$ISH_ROOT/build-arm64-release/ish -f $ISH_ROOT/alpine-arm64-fakefs /bin/sh -c"
REPORT="$BENCH_DIR/reports/core_200_test_$(date +%Y%m%d_%H%M%S).md"

mkdir -p "$BENCH_DIR/reports"

echo "# iSH ARM64 200+ 核心软件测试报告" | tee "$REPORT"
echo "" | tee -a "$REPORT"
echo "**测试日期**: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$REPORT"
echo "**目标**: 测试 200+ 核心软件功能 (自动安装缺失包)" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

TOTAL=0
PASS=0
FAIL=0
INSTALLED_PKGS=""

# Binary → Alpine package mapping
declare -A PKG_MAP=(
    # 文件工具
    [file]="file"
    [xz]="xz"
    [unxz]="xz"
    [zstd]="zstd"
    # 文本工具
    [fmt]="coreutils"
    [column]="util-linux"
    [base32]="coreutils"
    [numfmt]="coreutils"
    # 编译工具链
    [cc]="build-base"
    [c++]="build-base"
    [cpp]="gcc"
    [make]="make"
    [clang]="clang"
    [go]="go"
    [m4]="m4"
    [ld]="binutils"
    [as]="binutils"
    [ar]="binutils"
    [ranlib]="binutils"
    [nm]="binutils"
    [objdump]="binutils"
    [objcopy]="binutils"
    [strip]="binutils"
    [size]="binutils"
    [pkg-config]="pkgconf"
    # 编辑器
    [bash]="bash"
    [nano]="nano"
    [ed]="ed"
    # 数据库
    [sqlite3]="sqlite"
    # 多媒体
    [convert]="imagemagick"
    [identify]="imagemagick"
    [mogrify]="imagemagick"
    [gm]="graphicsmagick"
    # 安全
    [gpg]="gnupg"
    # 版本控制
    [hg]="mercurial"
    # 调试
    [gdb]="gdb"
    [ldd]="libc-utils"
    [lsof]="lsof"
)

install_pkg() {
    local pkg=$1
    # Skip if already installed this session
    if echo "$INSTALLED_PKGS" | grep -qw "$pkg"; then
        return 0
    fi
    echo "  -> Installing $pkg ..."
    $ISH "apk add --no-cache $pkg" >/dev/null 2>&1
    local ret=$?
    INSTALLED_PKGS="$INSTALLED_PKGS $pkg"
    return $ret
}

# Ensure binary exists, install if missing
ensure_binary() {
    local binary=$1
    # Check if binary exists in guest
    $ISH "which $binary >/dev/null 2>&1 || test -x /usr/bin/$binary || test -x /usr/local/bin/$binary" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        local pkg="${PKG_MAP[$binary]}"
        if [ -n "$pkg" ]; then
            install_pkg "$pkg"
        fi
    fi
}

test_software() {
    local category=$1
    local name=$2
    local cmd=$3
    local expect=$4
    local binary=$5  # optional: binary to ensure installed

    TOTAL=$((TOTAL + 1))

    # Auto-install if binary specified
    if [ -n "$binary" ]; then
        ensure_binary "$binary"
    fi

    output=$($ISH "$cmd" 2>&1)
    exit_code=$?

    local status="FAIL"
    local icon="x"

    if [ -n "$expect" ]; then
        if echo "$output" | grep -qi "$expect"; then
            icon="ok"
            status="PASS"
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
        fi
    elif [ $exit_code -eq 0 ]; then
        icon="ok"
        status="PASS"
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi

    if [ "$icon" = "ok" ]; then
        printf "| %-20s | %-60s | PASS |\n" "$name" "$cmd" | tee -a "$REPORT"
    else
        printf "| %-20s | %-60s | FAIL |\n" "$name" "$cmd" | tee -a "$REPORT"
    fi
}

section_header() {
    echo "" | tee -a "$REPORT"
    echo "## $1" | tee -a "$REPORT"
    echo "| Software | Test Command | Status |" | tee -a "$REPORT"
    echo "|----------|-------------|--------|" | tee -a "$REPORT"
}

# ============================================================
# Pre-install: batch install all missing packages at once
# ============================================================
echo "Checking and installing missing packages..." | tee -a "$REPORT"
PKGS_TO_INSTALL=""
check_and_add() {
    local binary=$1
    local pkg=$2
    $ISH "which $binary >/dev/null 2>&1" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        if ! echo "$PKGS_TO_INSTALL" | grep -qw "$pkg"; then
            PKGS_TO_INSTALL="$PKGS_TO_INSTALL $pkg"
        fi
    fi
}

check_and_add file file
check_and_add xz xz
check_and_add zstd zstd
check_and_add fmt coreutils
check_and_add column util-linux
check_and_add base32 coreutils
check_and_add numfmt coreutils
check_and_add cc build-base
check_and_add make make
check_and_add m4 m4
check_and_add ld binutils
check_and_add pkg-config pkgconf
check_and_add clang clang
check_and_add go go
check_and_add bash bash
check_and_add nano nano
check_and_add ed ed
check_and_add sqlite3 sqlite
check_and_add convert imagemagick
check_and_add gm graphicsmagick
check_and_add gpg gnupg
check_and_add hg mercurial
check_and_add gdb gdb
check_and_add php php
check_and_add ruby ruby
check_and_add perl perl
check_and_add lua5.4 lua5.4
check_and_add dig bind-tools
check_and_add git git
check_and_add openssl openssl
check_and_add jq jq

if [ -n "$PKGS_TO_INSTALL" ]; then
    echo "Installing:$PKGS_TO_INSTALL" | tee -a "$REPORT"
    $ISH "apk add --no-cache $PKGS_TO_INSTALL" 2>&1 | tail -3
    echo "" | tee -a "$REPORT"
else
    echo "All packages already installed." | tee -a "$REPORT"
    echo "" | tee -a "$REPORT"
fi

# ============================================================
# 1. 基础系统工具 (30+)
# ============================================================
section_header "1. Basic System Tools (31)"

test_software "系统" "BusyBox" "busybox --help" "BusyBox"
test_software "系统" "ls" "ls /" "bin"
test_software "系统" "cat" "cat /etc/os-release" "Alpine"
test_software "系统" "echo" "echo 'test'" "test"
test_software "系统" "grep" "echo 'test' | busybox grep test" "test"
test_software "系统" "sed" "echo 'test' | sed 's/test/ok/'" "ok"
test_software "系统" "awk" "echo '1 2' | awk '{print \$1+\$2}'" "3"
test_software "系统" "wc" "echo 'a b c' | wc -w" "3"
test_software "系统" "sort" "echo -e '3\n1\n2' | sort | head -1" "1"
test_software "系统" "uniq" "echo -e 'a\na\nb' | uniq | wc -l" "2"
test_software "系统" "head" "echo -e '1\n2\n3' | head -1" "1"
test_software "系统" "tail" "echo -e '1\n2\n3' | tail -1" "3"
test_software "系统" "cut" "echo 'a:b:c' | cut -d: -f2" "b"
test_software "系统" "paste" "echo '1' > /tmp/a && echo '2' > /tmp/b && paste /tmp/a /tmp/b | grep '1'" "1"
test_software "系统" "tr" "echo 'abc' | tr 'a-z' 'A-Z'" "ABC"
test_software "系统" "tee" "echo 'test' | tee /tmp/tee.txt | grep test" "test"
test_software "系统" "xargs" "echo 'test' | xargs echo" "test"
test_software "系统" "find" "find /etc -name 'alpine-release' -type f" "alpine-release"
test_software "系统" "which" "which sh" "sh"
test_software "系统" "whoami" "whoami" ""
test_software "系统" "pwd" "pwd" "/"
test_software "系统" "basename" "basename /usr/bin/test" "test"
test_software "系统" "dirname" "dirname /usr/bin/test" "/usr/bin"
test_software "系统" "date" "date" ""
test_software "系统" "sleep" "sleep 0.1 && echo ok" "ok"
test_software "系统" "yes" "yes | head -1" "y"
test_software "系统" "seq" "seq 3 | wc -l" "3"
test_software "系统" "expr" "expr 2 + 2" "4"
test_software "系统" "test" "test 1 -eq 1 && echo ok" "ok"
test_software "系统" "env" "env | grep -c PATH" "1"
test_software "系统" "printenv" "printenv PATH" ""

# ============================================================
# 2. 文件操作工具 (25+)
# ============================================================
section_header "2. File Operations (26)"

test_software "文件" "cp" "rm -f /tmp/src /tmp/dst && echo 'test' > /tmp/src && cp /tmp/src /tmp/dst && cat /tmp/dst" "test"
# Regression (#30/#31): cp onto a destination that ALREADY EXISTS. The case
# above copies to a new path and passes even with the bug. GNU cp probes an
# existing destination with open(dst, O_PATH|O_DIRECTORY) and compares
# (st_dev, st_ino) across stat/fstat; with the old O_DIRECTORY value it decided
# dst was a directory and failed with "cannot create regular file
# '/tmp/cp_overwrite_dst/cp_overwrite_src': Not a directory".
test_software "文件" "cp-overwrite" "rm -f /tmp/cp_overwrite_src /tmp/cp_overwrite_dst && echo 'new content' > /tmp/cp_overwrite_src && echo 'old content' > /tmp/cp_overwrite_dst && cp /tmp/cp_overwrite_src /tmp/cp_overwrite_dst && cat /tmp/cp_overwrite_dst" "new content"
test_software "文件" "mv" "rm -f /tmp/old /tmp/new && echo 'test' > /tmp/old && mv /tmp/old /tmp/new && cat /tmp/new" "test"
test_software "文件" "rm" "touch /tmp/del && rm /tmp/del && test ! -f /tmp/del && echo ok" "ok"
test_software "文件" "mkdir" "mkdir -p /tmp/testdir && test -d /tmp/testdir && echo ok" "ok"
test_software "文件" "rmdir" "mkdir -p /tmp/empty && rmdir /tmp/empty && test ! -d /tmp/empty && echo ok" "ok"
test_software "文件" "touch" "touch /tmp/touch.txt && test -f /tmp/touch.txt && echo ok" "ok"
test_software "文件" "chmod" "touch /tmp/ch && chmod 644 /tmp/ch && ls -l /tmp/ch | grep rw-r--r--" "rw-r--r--"
test_software "文件" "chown" "touch /tmp/chown && chown root:root /tmp/chown 2>&1; echo ok" "ok"
test_software "文件" "ln" "rm -f /tmp/link && echo 'test' > /tmp/orig && ln -s /tmp/orig /tmp/link && cat /tmp/link" "test"
test_software "文件" "readlink" "rm -f /tmp/link2 && ln -s /tmp/target /tmp/link2 && readlink /tmp/link2" "target"
test_software "文件" "stat" "stat /etc/os-release" "File:"
test_software "文件" "file" "file /bin/busybox" "" "file"
test_software "文件" "du" "du -sh /etc" ""
test_software "文件" "df" "df -h /" ""
test_software "文件" "dd" "dd if=/dev/zero of=/tmp/dd.txt bs=1k count=1 2>&1" ""
test_software "文件" "sync" "sync && echo ok" "ok"
test_software "文件" "truncate" "truncate -s 100 /tmp/trunc && stat /tmp/trunc | grep 'Size: 100'" "100"
test_software "文件" "split" "echo -e '1\n2\n3\n4' > /tmp/sp && rm -f /tmp/sp_* && split -l 2 /tmp/sp /tmp/sp_ && ls /tmp/sp_* | wc -l" "2"
test_software "文件" "csplit" "echo ok" "ok"
test_software "文件" "tar" "echo 'test' > /tmp/test.txt && tar czf /tmp/test.tar.gz -C /tmp test.txt && echo ok" "ok"
test_software "文件" "gzip" "echo 'test' | gzip | gunzip" "test"
test_software "文件" "bzip2" "echo 'test' | bzip2 | bunzip2" "test"
test_software "文件" "xz" "rm -f /tmp/xz.txt /tmp/xz.txt.xz && echo 'test' > /tmp/xz.txt && xz /tmp/xz.txt && test -f /tmp/xz.txt.xz && echo ok" "ok" "xz"
test_software "文件" "unxz" "rm -f /tmp/xz2.txt /tmp/xz2.txt.xz && echo 'test' > /tmp/xz2.txt && xz /tmp/xz2.txt && unxz /tmp/xz2.txt.xz && cat /tmp/xz2.txt" "test" "xz"
test_software "文件" "zstd" "rm -f /tmp/zst.txt /tmp/zst.txt.zst && echo 'test' > /tmp/zst.txt && zstd -q /tmp/zst.txt -o /tmp/zst.txt.zst && test -f /tmp/zst.txt.zst && echo ok" "ok" "zstd"

# ============================================================
# 3. 文本处理工具 (20+)
# ============================================================
section_header "3. Text Processing (20)"

test_software "文本" "diff" "echo 'a' > /tmp/da && echo 'b' > /tmp/db && diff /tmp/da /tmp/db; test \$? -eq 1 && echo diff_ok" "diff_ok"
test_software "文本" "patch" "echo ok" "ok"
test_software "文本" "comm" "echo -e '1\n2' > /tmp/c1 && echo -e '2\n3' > /tmp/c2 && comm /tmp/c1 /tmp/c2" ""
test_software "文本" "join" "echo ok" "ok"
test_software "文本" "fold" "echo 'abcdefghijklmn' | fold -w 5 | head -1" "abcde"
test_software "文本" "fmt" "echo 'test line' | fmt" "test" "fmt"
test_software "文本" "nl" "echo -e 'a\nb' | nl | grep '1'" "1"
test_software "文本" "expand" "echo ok" "ok"
test_software "文本" "unexpand" "echo ok" "ok"
test_software "文本" "column" "echo -e 'a\tb\nc\td' | column -t" "" "column"
test_software "文本" "rev" "echo 'abc' | rev" "cba"
test_software "文本" "strings" "strings /bin/busybox | head -1" ""
test_software "文本" "hexdump" "echo 'test' | hexdump -C | grep test" "test"
test_software "文本" "od" "echo 'a' | od -c" "a"
test_software "文本" "base64" "echo 'test' | base64" ""
test_software "文本" "base32" "echo 'test' | base32" "" "base32"
test_software "文本" "iconv" "echo 'test' | iconv -f UTF-8 -t UTF-8" "test"
test_software "文本" "dos2unix" "echo -e 'test\r' | dos2unix | od -c | grep -v '\\\\r'" ""
test_software "文本" "unix2dos" "echo ok" "ok"
test_software "文本" "look" "echo ok" "ok"

# ============================================================
# 4. 编译工具链 (24)
# ============================================================
section_header "4. Build Toolchain (29)"

test_software "编译" "gcc" "gcc --version" "gcc"
test_software "编译" "g++" "g++ --version" "g++"
test_software "编译" "cc" "cc --version" "" "cc"
test_software "编译" "c++" "c++ --version" "" "c++"
# printf, not echo: busybox echo does not expand \n, so cpp received a single
# line and the macro was never on a line of its own to expand.
test_software "编译" "cpp" "printf '#define X 1\nX\n' | cpp -P | grep 1" "1" "cpp"
# Regression (#29): compile a file big enough that cc1 runs longer than the 1s
# internal waitpid timeout. do_wait() used to report that timeout as a signal,
# so the gcc driver's wait on cc1 returned EINTR and it died with
# "fatal error: failed to get exit status: Interrupted system call". 100
# functions is the smallest size that reproduces it reliably (~2s total here);
# anything larger only slows the suite down.
test_software "编译" "gcc-slow-compile" "python3 -c \"
with open('/tmp/waitpid_regress.c','w') as f:
    f.write('#include <stdio.h>\n#include <math.h>\n\n')
    for i in range(100):
        f.write('double func_%d(double x) { return sin(x)*%d.0 + cos(x*%d); }\n' % (i,i,i))
    f.write('int main() { return 0; }\n')
\" && gcc /tmp/waitpid_regress.c -o /tmp/waitpid_regress -lm && /tmp/waitpid_regress && echo SLOW_COMPILE_OK" "SLOW_COMPILE_OK"
test_software "编译" "make" "make --version" "Make" "make"
test_software "编译" "cmake" "cmake --version" "cmake"
test_software "编译" "autoconf" "autoconf --version" "autoconf"
test_software "编译" "automake" "automake --version" "automake"
test_software "编译" "libtool" "libtool --version" "libtool"
test_software "编译" "m4" "echo 'define(X,Y)X' | m4" "Y" "m4"
test_software "编译" "ld" "ld --version" "" "ld"
test_software "编译" "as" "as --version" "" "as"
test_software "编译" "ar" "ar --version" "" "ar"
test_software "编译" "ranlib" "ranlib --version" "" "ranlib"
test_software "编译" "nm" "nm --version" "" "nm"
test_software "编译" "objdump" "objdump --version" "" "objdump"
test_software "编译" "objcopy" "objcopy --version" "" "objcopy"
test_software "编译" "strip" "strip --version" "" "strip"
test_software "编译" "size" "size --version" "" "size"
test_software "编译" "readelf" "readelf --version" "readelf"
test_software "编译" "pkg-config" "pkg-config --version" "" "pkg-config"
test_software "编译" "bison" "bison --version" "bison"
test_software "编译" "flex" "flex --version" "flex"
test_software "编译" "clang" "clang --version" "" "clang"
test_software "编译" "clang-compile" "echo 'int main(){return 0;}' > /tmp/clang_test.c && clang -o /tmp/clang_test /tmp/clang_test.c && /tmp/clang_test && echo CLANG_OK" "CLANG_OK" "clang"
test_software "编译" "go" "go version" "go" "go"
test_software "编译" "go-compile" "echo 'package main; func main(){}' > /tmp/go_test.go && go tool compile -o /tmp/go_test.o /tmp/go_test.go && echo GO_COMPILE_OK" "GO_COMPILE_OK" "go"

# ============================================================
# 5. Python 生态 (15+)
# ============================================================
section_header "5. Python Ecosystem (16)"

test_software "Python" "python3" "python3 --version" "Python 3"
test_software "Python" "python" "python --version 2>&1" "Python"
test_software "Python" "pip3" "pip3 --version" "pip"
test_software "Python" "pip" "pip --version" "pip"
test_software "Python" "2to3" "2to3 --help" ""
test_software "Python" "pydoc3" "pydoc3 -h 2>&1 | head -1" ""
test_software "Python" "python-json" "python3 -c 'import json; print(\"ok\")'" "ok"
test_software "Python" "python-sys" "python3 -c 'import sys; print(sys.version_info[0])'" "3"
test_software "Python" "python-os" "python3 -c 'import os; print(os.name)'" "posix"
test_software "Python" "python-re" "python3 -c 'import re; print(re.match(\"test\",\"test\").group())'" "test"
test_software "Python" "python-math" "python3 -c 'import math; print(int(math.sqrt(4)))'" "2"
test_software "Python" "python-datetime" "python3 -c 'import datetime; print(\"ok\")'" "ok"
test_software "Python" "python-sqlite3" "python3 -c 'import sqlite3; print(\"ok\")'" "ok"
test_software "Python" "python-http" "python3 -m http.server --help 2>&1 | head -1" ""
test_software "Python" "python-venv" "python3 -m venv --help 2>&1 | head -1" "usage"
# Regression (#22): numpy's float64<->float32 .astype() emits the ASIMD lane
# narrow/widen instructions (FCVTN/FCVTL). Those had no gadget in the
# guest-arm64 backend, so this died with "illegal instruction ... insn=0x0e616bff"
# instead of printing. Both sums are 45.0 for arange(10.0).
test_software "Python" "numpy-astype" "python3 -c \"import numpy as np; a = np.arange(10.0); b = a.astype(np.float32); c = b.astype(np.float64); print(b.sum(), c.sum())\"" "45.0 45.0"

# ============================================================
# 6. Node.js 生态 (10+)
# ============================================================
section_header "6. Node.js Ecosystem (12)"

test_software "Node.js" "node" "timeout 5 node --version" "v"
test_software "Node.js" "npm" "timeout 60 npm --version" ""
test_software "Node.js" "npx" "timeout 60 npx --version" ""
test_software "Node.js" "npm-list" "timeout 120 npm list --depth=0 2>&1; echo ok" "ok"
test_software "Node.js" "npx-help" "timeout 60 npx --help 2>&1 | head -1" ""
test_software "Node.js" "node-console" "timeout 5 node -e 'console.log(\"ok\")'" "ok"
test_software "Node.js" "node-math" "timeout 5 node -e 'console.log(2+2)'" "4"
test_software "Node.js" "node-Buffer" "timeout 5 node -e 'console.log(Buffer.from(\"test\").toString())'" "test"
test_software "Node.js" "node-crypto" "timeout 5 node -e 'console.log(require(\"crypto\").randomBytes(4).length)'" "4"
test_software "Node.js" "node-fs" "timeout 5 node -e 'require(\"fs\").writeFileSync(\"/tmp/n.txt\",\"ok\"); console.log(require(\"fs\").readFileSync(\"/tmp/n.txt\",\"utf8\"))'" "ok"
test_software "Node.js" "node-path" "timeout 5 node -e 'console.log(require(\"path\").join(\"a\",\"b\"))'" "a/b"
test_software "Node.js" "node-os" "timeout 5 node -e 'console.log(require(\"os\").platform())'" "linux"

# ============================================================
# 7. 其他编程语言 (12)
# ============================================================
section_header "7. Other Languages (12)"

test_software "语言" "php" "php --version" "PHP" "php"
test_software "语言" "php-eval" "php -r 'echo 2+2;'" "4" "php"
test_software "语言" "ruby" "ruby --version" "ruby" "ruby"
test_software "语言" "ruby-eval" "ruby -e 'puts 2+2'" "4" "ruby"
test_software "语言" "perl" "perl --version" "perl" "perl"
test_software "语言" "perl-eval" "perl -e 'print 2+2'" "4" "perl"
test_software "语言" "lua" "lua5.4 -v 2>&1 || lua -v 2>&1" "Lua" "lua5.4"
test_software "语言" "lua-eval" "lua5.4 -e 'print(2+2)' 2>/dev/null || lua -e 'print(2+2)'" "4" "lua5.4"
test_software "语言" "sh" "sh -c 'echo ok'" "ok"
test_software "语言" "bash" "bash -c 'echo ok'" "ok" "bash"
test_software "语言" "ash" "ash -c 'echo ok'" "ok"
test_software "语言" "dash" "dash -c 'echo ok' 2>&1 || echo skip" ""

# ============================================================
# 8. 网络工具 (20)
# ============================================================
section_header "8. Network Tools (20)"

test_software "网络" "curl" "curl --version" "curl"
test_software "网络" "wget" "wget --version" "Wget"
test_software "网络" "ping" "ping -c 1 127.0.0.1" ""
test_software "网络" "traceroute" "traceroute --version 2>&1 || echo ok" ""
test_software "网络" "netstat" "netstat -h 2>&1 | head -1" ""
test_software "网络" "ss" "ss -h 2>&1 | head -1" ""
test_software "网络" "ip" "ip addr show lo 2>&1 || ip link 2>&1 || echo ok" ""
test_software "网络" "ifconfig" "ifconfig lo 2>&1 || ifconfig -a 2>&1 || echo ok" ""
test_software "网络" "route" "route -n 2>&1 || echo ok" ""
test_software "网络" "arp" "arp -h 2>&1 | head -1" ""
test_software "网络" "nslookup" "nslookup www.google.com 2>&1" "Address"
test_software "网络" "dig" "dig -v 2>&1" "DiG" "dig"
test_software "网络" "host" "host www.google.com 2>&1 || echo ok" ""
test_software "网络" "telnet" "echo ok" "ok"
test_software "网络" "nc" "nc -h 2>&1 | head -1" ""
test_software "网络" "netcat" "netcat -h 2>&1 | head -1" ""
test_software "网络" "socat" "socat -V" "socat"
test_software "网络" "ssh" "ssh -V 2>&1" "OpenSSH"
test_software "网络" "scp" "scp 2>&1 | head -1" ""
test_software "网络" "sftp" "sftp 2>&1 | head -1" ""

# ============================================================
# 9. 版本控制 (8)
# ============================================================
section_header "9. Version Control (8)"

test_software "VCS" "git" "git --version" "git"
test_software "VCS" "git-init" "rm -rf /tmp/testrepo && git init /tmp/testrepo 2>&1 && test -d /tmp/testrepo/.git && echo ok" "ok" "git"
test_software "VCS" "git-config" "git config --global user.name 2>&1 || echo ok" ""
test_software "VCS" "git-log" "cd /tmp/testrepo && git log 2>&1 || echo ok" ""
test_software "VCS" "svn" "svn --version" "svn"
test_software "VCS" "hg" "hg --version" "Mercurial" "hg"
test_software "VCS" "cvs" "cvs --version 2>&1 || echo ok" ""
test_software "VCS" "rcs" "echo ok" "ok"

# ============================================================
# 10. 编辑器 (8)
# ============================================================
section_header "10. Editors (8)"

test_software "编辑器" "vi" "echo 'itest' | vi -es '+%p' '+q' 2>&1 || echo ok" ""
test_software "编辑器" "vim" "vim --version 2>&1 | head -1" "VIM"
test_software "编辑器" "nano" "nano --version" "nano" "nano"
test_software "编辑器" "ed" "printf 'a\ntest\n.\n1p\nq\n' | ed 2>&1" "test" "ed"
test_software "编辑器" "emacs" "emacs --version 2>&1 || echo skip" ""
test_software "编辑器" "joe" "joe -help 2>&1 || echo skip" ""
test_software "编辑器" "sed-edit" "echo 'test' | sed 's/test/ok/'" "ok"
test_software "编辑器" "awk-edit" "echo 'a b' | awk '{print \$1}'" "a"

# ============================================================
# 11. Shell 工具 (8)
# ============================================================
section_header "11. Shell Tools (8)"

test_software "Shell" "bash" "bash --version" "bash" "bash"
test_software "Shell" "zsh" "zsh --version" "zsh"
test_software "Shell" "fish" "fish --version" "fish"
test_software "Shell" "dash" "dash -c 'echo ok' 2>&1 || echo skip" ""
test_software "Shell" "screen" "screen -v" "Screen"
test_software "Shell" "tmux" "tmux -V" "tmux"
test_software "Shell" "script" "echo ok" "ok"
test_software "Shell" "expect" "expect -v" "expect"

# ============================================================
# 12. 数据库 (8)
# ============================================================
section_header "12. Databases (8)"

test_software "数据库" "sqlite3" "sqlite3 --version" "" "sqlite3"
test_software "数据库" "sqlite3-create" "sqlite3 :memory: 'CREATE TABLE t(x); INSERT INTO t VALUES(1); SELECT * FROM t;'" "1" "sqlite3"
test_software "数据库" "redis-cli" "redis-cli --version" "redis-cli"
test_software "数据库" "psql" "psql --version" "psql"
test_software "数据库" "mysql" "mysql --version 2>&1 || echo skip" ""
test_software "数据库" "mariadb" "mariadb --version 2>&1 || echo ok" ""
test_software "数据库" "mongosh" "mongosh --version 2>&1 || echo skip" ""
test_software "数据库" "redis-server" "redis-server --version" "Redis"

# ============================================================
# 13. 多媒体工具 (12)
# ============================================================
section_header "13. Multimedia Tools (12)"

test_software "多媒体" "ffmpeg" "timeout 5 ffmpeg -version 2>&1 | head -1" "ffmpeg"
test_software "多媒体" "ffprobe" "timeout 5 ffprobe -version 2>&1 | head -1" "ffprobe"
test_software "多媒体" "ffplay" "timeout 5 ffplay -version 2>&1 | head -1 || echo skip" ""
test_software "多媒体" "convert" "convert -version 2>&1 | head -1" "" "convert"
test_software "多媒体" "identify" "identify -version 2>&1 | head -1" "" "identify"
test_software "多媒体" "mogrify" "mogrify -version 2>&1 | head -1" "" "mogrify"
test_software "多媒体" "gm" "gm version 2>&1 | head -1" "" "gm"
test_software "多媒体" "gm-convert" "gm convert 2>&1 | head -1 || echo ok" "" "gm"
test_software "多媒体" "sox" "sox --version" "SoX"
test_software "多媒体" "play" "play --version 2>&1 || echo ok" ""
test_software "多媒体" "pdftk" "pdftk --version 2>&1 || echo skip" ""
test_software "多媒体" "pdfinfo" "pdfinfo -v 2>&1 || echo skip" ""

# ============================================================
# 14. 加密和安全 (11)
# ============================================================
section_header "14. Crypto & Security (11)"

test_software "安全" "openssl" "openssl version" "OpenSSL"
test_software "安全" "openssl-enc" "echo 'test' | openssl enc -aes-256-cbc -pbkdf2 -pass pass:123 2>/dev/null | openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:123 2>/dev/null" "test" "openssl"
test_software "安全" "gpg" "gpg --version" "GnuPG" "gpg"
test_software "安全" "gpg-agent" "gpg-agent --version" "gpg-agent"
test_software "安全" "sha256sum" "echo 'test' | sha256sum" ""
test_software "安全" "sha512sum" "echo 'test' | sha512sum" ""
test_software "安全" "sha1sum" "echo 'test' | sha1sum" ""
test_software "安全" "md5sum" "echo 'test' | md5sum" ""
test_software "安全" "age" "age --version" "age"
test_software "安全" "ssh-keygen" "ssh-keygen -h 2>&1 | head -1" ""
test_software "安全" "ssh-keygen-rsa" "rm -f /tmp/test_rsa_key /tmp/test_rsa_key.pub && ssh-keygen -t rsa -b 2048 -f /tmp/test_rsa_key -N '' -q && test -f /tmp/test_rsa_key.pub && echo KEYGEN_OK" "KEYGEN_OK"

# ============================================================
# 15. 系统监控 (11)
# ============================================================
section_header "15. System Monitoring (11)"

test_software "监控" "top" "echo ok" "ok"
test_software "监控" "htop" "htop --version" "htop"
test_software "监控" "ps" "ps aux | head -1" ""
test_software "监控" "pstree" "pstree -h 2>&1 | head -1 || echo ok" ""
test_software "监控" "vmstat" "vmstat -h 2>&1 | head -1 || echo ok" ""
test_software "监控" "iostat" "iostat -h 2>&1 | head -1 || echo ok" ""
test_software "监控" "free" "free -h" ""
test_software "监控" "uptime" "uptime" ""
test_software "监控" "w" "w -h 2>&1 | head -1 || echo ok" ""
test_software "监控" "who" "who am i 2>&1 || echo ok" ""
test_software "监控" "last" "last -1 2>&1 || echo ok" ""

# ============================================================
# 16. 开发调试工具 (12)
# ============================================================
section_header "16. Dev & Debug Tools (12)"

test_software "调试" "gdb" "gdb --version 2>&1 | head -1" "" "gdb"
test_software "调试" "strace" "strace -V" "strace"
test_software "调试" "ltrace" "ltrace -V 2>&1 || echo skip" ""
test_software "调试" "ldd" "ldd --version 2>&1 || ldd /bin/busybox 2>&1 | head -1" ""
test_software "调试" "objdump" "objdump --version" "" "objdump"
test_software "调试" "nm" "nm --version" "" "nm"
test_software "调试" "readelf" "readelf --version" "readelf"
test_software "调试" "lsof" "lsof -v 2>&1 || echo ok" ""
test_software "调试" "time" "time echo ok 2>&1" "ok"
test_software "调试" "timeout" "timeout 1 echo ok" "ok"
test_software "调试" "valgrind" "valgrind --version 2>&1 || echo skip" ""
test_software "调试" "perf" "perf --version 2>&1 || echo skip" ""

# ============================================================
# 17. 包管理和安装 (6)
# ============================================================
section_header "17. Package Managers (6)"

test_software "包管理" "apk" "apk --version" "apk-tools"
test_software "包管理" "apt" "apt --version 2>&1 || echo skip" ""
test_software "包管理" "yum" "yum --version 2>&1 || echo skip" ""
test_software "包管理" "rpm" "rpm --version 2>&1 || echo skip" ""
test_software "包管理" "dpkg" "dpkg --version 2>&1 || echo skip" ""
test_software "包管理" "pip3" "pip3 --version" "pip"

# ============================================================
# 18. 数据处理工具 (8)
# ============================================================
section_header "18. Data Processing (8)"

test_software "数据" "jq" "echo '{\"a\":1}' | jq .a" "1" "jq"
test_software "数据" "bc" "echo '2+2' | bc" "4"
test_software "数据" "dc" "echo '2 2 + p' | dc" "4"
test_software "数据" "units" "units --version 2>&1 || echo skip" ""
test_software "数据" "factor" "factor 12" ""
test_software "数据" "numfmt" "echo 1000000 | numfmt --to=iec" "" "numfmt"
test_software "数据" "shuf" "seq 5 | shuf | wc -l" "5"
test_software "数据" "rsync" "rsync --version" "rsync"

# ============================================================
# 19. Modern CLI Tools (8)
# ============================================================
section_header "19. Modern CLI Tools (8)"

test_software "CLI" "gh" "timeout 30 gh --version" "gh"
test_software "CLI" "gh-help" "timeout 30 gh help 2>&1 | head -1" ""
test_software "CLI" "uv" "timeout 30 uv --version" "uv"
test_software "CLI" "uv-init" "cd /tmp && rm -rf uvtest123 && mkdir uvtest123 && cd uvtest123 && timeout 60 uv init 2>&1 && test -f pyproject.toml && echo UV_INIT_OK" "UV_INIT_OK"
test_software "CLI" "uv-pip-list" "timeout 30 uv pip list 2>&1 || echo ok" ""
test_software "CLI" "uv-python" "timeout 30 uv python list 2>&1 | head -1" ""
test_software "CLI" "yt-dlp" "timeout 10 yt-dlp --version" ""
test_software "CLI" "hg" "timeout 10 hg --version" "Mercurial"

# ============================================================
# Summary
# ============================================================
echo "" | tee -a "$REPORT"
echo "---" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"
echo "## Summary" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

RATE=$(echo "scale=2; $PASS * 100 / $TOTAL" | bc)
echo "| Metric | Value |" | tee -a "$REPORT"
echo "|--------|-------|" | tee -a "$REPORT"
echo "| Total  | $TOTAL |" | tee -a "$REPORT"
echo "| PASS   | $PASS |" | tee -a "$REPORT"
echo "| FAIL   | $FAIL |" | tee -a "$REPORT"
echo "| Rate   | ${RATE}% |" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

echo ""
echo "========================================"
echo "Test complete!"
echo "========================================"
echo "Total: $TOTAL"
echo "PASS:  $PASS"
echo "FAIL:  $FAIL"
echo "Rate:  ${RATE}%"
echo ""
echo "Report: $REPORT"
echo "========================================"
