#!/bin/sh
# portable-bench.sh - the review's numbers on your own machine, for the reviewer to
# compare with theirs.  Run from the repository root after `make packages`:
#   sh review/portable-bench.sh [runs]            (default 10)
# Prints one block to standard output and nothing else; paste it back.  It names
# no host, user or path: Emacs's and clangd's versions, the OS family and the
# processor count, the load, then the startup times of scripts/measure-startup.sh
# (upstream's own method: `emacs -nw` in a private tmux server with a throwaway
# HOME, the time from `before-init-time` to the end of `after-init-hook`), and the
# wall time and counts of `make test`.  Never touches ~/.emacs.d (both steps use a
# throwaway HOME).  Run on an idle machine; POSIX sh, Linux or macOS.
set -eu
LC_ALL=C
export LC_ALL
RUNS=${1:-10}
REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO"
fail() { echo "portable-bench: $*" >&2; exit 1; }
command -v emacs > /dev/null || fail "emacs is not on PATH"
command -v tmux > /dev/null || fail "tmux is not on PATH (measure-startup.sh needs it)"
[ -f lib/load-path.el ] || fail "lib/load-path.el is missing: run make packages first"
[ -f scripts/measure-startup.sh ] || fail "scripts/measure-startup.sh is missing"
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# Seconds with a fraction, where date supports %N (GNU); whole seconds elsewhere (macOS).
seconds() {
    s=$(date +%s.%N 2>/dev/null)
    case $s in *N*|'') date +%s ;; *) echo "$s" ;; esac
}
echo "portable-bench: $(now), runs $RUNS"
echo "commit: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "emacs: $(emacs --version | head -1)"
if [ -n "${EMACS_CPP_CLANGD:-}" ] && [ -x "$EMACS_CPP_CLANGD" ]; then
    echo "clangd: $("$EMACS_CPP_CLANGD" --version | head -1) (EMACS_CPP_CLANGD)"
elif command -v clangd > /dev/null; then
    echo "clangd: $(clangd --version | head -1) (PATH)"
else
    echo "clangd: none on PATH"
fi
echo "os: $(uname -s) $(uname -m)"
if [ -r /proc/cpuinfo ]; then
    echo "cpus: $(grep -c ^processor /proc/cpuinfo)"
else
    echo "cpus: $(sysctl -n hw.ncpu 2>/dev/null || echo unknown)"
fi
echo "startup: scripts/measure-startup.sh $RUNS"
sh scripts/measure-startup.sh "$RUNS" | sed 's/^/  /'
echo "make test:"
T0=$(seconds)
# The suite's own exit status is reported, never fatal here.
if make -s test > "${TMPDIR:-/tmp}/portable-bench-test.$$" 2>&1; then STATUS=0; else STATUS=$?; fi
T1=$(seconds)
grep -E "^Ran [0-9]+ tests|^[0-9]+ unexpected|^[0-9]+ skipped|^[0-9]+ expected failures" \
    "${TMPDIR:-/tmp}/portable-bench-test.$$" | sed 's/^/  /' || true
rm -f "${TMPDIR:-/tmp}/portable-bench-test.$$"
echo "  exit $STATUS, wall $(echo "$T1 $T0" | awk '{ printf "%.1f", $1 - $2 }') s"
echo "portable-bench: done $(now)"
