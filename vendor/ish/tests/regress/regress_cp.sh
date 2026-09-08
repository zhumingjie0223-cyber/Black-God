#!/bin/sh
# Guest-side regression tests for the cp failures behind #30 and #31.
#
# These run inside iSH and need GNU coreutils cp, not busybox cp: only GNU cp
# probes its destination with open(dst, O_PATH|O_DIRECTORY) and compares
# (st_dev, st_ino) across stat/fstat, which is what both bugs broke. If GNU
# coreutils is not installed the cp cases are skipped rather than failed.
#
# Usage (inside the guest):
#   sh regress_cp.sh [fakefs_path]
# where fakefs_path is an optional file under a fakefs mount point
# (e.g. /var/minis/shared/doc.txt) to exercise the #31 copy-out case.

pass=0
fail=0
skip=0

ok() { pass=$((pass + 1)); echo "  PASS  $1"; }
no() { fail=$((fail + 1)); echo "  FAIL  $1"; }
sk() { skip=$((skip + 1)); echo "  SKIP  $1"; }

# Locate a GNU cp. Alpine ships it as the coreutils multi-call binary.
CP=""
if command -v /usr/bin/coreutils >/dev/null 2>&1; then
    CP="/usr/bin/coreutils --coreutils-prog=cp"
elif command -v coreutils >/dev/null 2>&1; then
    CP="coreutils --coreutils-prog=cp"
elif cp --version 2>/dev/null | grep -q GNU; then
    CP="cp"
fi

echo "=== #30 GNU cp over an existing regular file ==="
if [ -z "$CP" ]; then
    sk "GNU coreutils cp not installed (busybox cp does not reproduce this)"
else
    rm -f /tmp/regress_src.txt /tmp/regress_dst.txt
    echo hello > /tmp/regress_src.txt
    echo old > /tmp/regress_dst.txt
    out=$($CP -v /tmp/regress_src.txt /tmp/regress_dst.txt 2>&1)
    rc=$?
    echo "  cp: $out"
    [ "$rc" = "0" ] && ok "cp over an existing file exits 0" \
                    || no "cp over an existing file exits 0 (rc=$rc)"
    # The signature failure was cp rewriting the target as dst/src.
    case "$out" in
        *"Not a directory"*) no "no 'Not a directory' error" ;;
        *) ok "no 'Not a directory' error" ;;
    esac
    got=$(cat /tmp/regress_dst.txt)
    [ "$got" = "hello" ] && ok "destination content overwritten" \
                         || no "destination content overwritten (got '$got')"
    rm -f /tmp/regress_src.txt /tmp/regress_dst.txt
fi

echo ""
echo "=== #30 cp -r still works (guard against breaking real directories) ==="
if [ -z "$CP" ]; then
    sk "GNU coreutils cp not installed"
else
    rm -rf /tmp/regress_rsrc /tmp/regress_rdst
    mkdir -p /tmp/regress_rsrc/sub
    echo nested > /tmp/regress_rsrc/sub/b.txt
    $CP -r /tmp/regress_rsrc /tmp/regress_rdst 2>&1
    [ "$?" = "0" ] && ok "cp -r exits 0" || no "cp -r exits 0"
    got=$(cat /tmp/regress_rdst/sub/b.txt 2>/dev/null)
    [ "$got" = "nested" ] && ok "cp -r copied nested content" \
                          || no "cp -r copied nested content (got '$got')"
    rm -rf /tmp/regress_rsrc /tmp/regress_rdst
fi

echo ""
echo "=== #31 cp out of a fakefs mount point ==="
SRC="$1"
if [ -z "$CP" ]; then
    sk "GNU coreutils cp not installed"
elif [ -z "$SRC" ]; then
    sk "no fakefs path given (pass one as \$1, e.g. /var/minis/shared/doc.txt)"
elif [ ! -f "$SRC" ]; then
    sk "fakefs path $SRC does not exist"
else
    rm -f /tmp/regress_out.txt
    out=$($CP -v "$SRC" /tmp/regress_out.txt 2>&1)
    rc=$?
    echo "  cp: $out"
    [ "$rc" = "0" ] && ok "cp out of fakefs exits 0" \
                    || no "cp out of fakefs exits 0 (rc=$rc)"
    # The st_dev mismatch made GNU cp report exactly this and skip the file.
    case "$out" in
        *"replaced while being copied"*) no "no 'replaced while being copied'" ;;
        *) ok "no 'replaced while being copied'" ;;
    esac
    if [ -s /tmp/regress_out.txt ]; then
        ok "copied file is non-empty"
    else
        no "copied file is non-empty"
    fi
    rm -f /tmp/regress_out.txt
fi

echo ""
echo "================ RESULT ================"
echo "  PASS: $pass    FAIL: $fail    SKIP: $skip"
[ "$fail" = "0" ]
