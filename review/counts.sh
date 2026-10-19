#!/bin/sh
# Counts quoted by the review's section A, from the checked-out tree.  Run from the
# repository root: sh review/counts.sh.  Prints one "name: value" per line.
set -eu
echo "commit: $(git rev-parse --short HEAD) ($(git log -1 --format=%ad --date=short))"
echo "commits: $(git rev-list --count HEAD)"
echo "own_lisp_lines: $(cat init.el early-init.el lisp/*.el | wc -l) (init.el, early-init.el, lisp/*.el)"
echo "own_lisp_files: $(ls lisp/*.el | wc -l)"
echo "test_lisp_lines: $(cat test/*.el | wc -l)"
echo "ert_tests: $(grep -h -c '^(ert-deftest' test/*.el | awk '{s+=$1} END {print s}')"
echo "lisp_compiled: $(ls lisp/*.elc 2>/dev/null | wc -l) .elc files in lisp/"
echo "packages_pinned: $(git submodule status | wc -l) submodules in lib/"
echo "patch_files: $(ls packaging/*/*.patch patches/*/*.patch | wc -l)"
echo "patch_lines: $(cat packaging/*/*.patch patches/*/*.patch | wc -l)"
for d in packaging/*/ patches/*/; do
    n=$(ls "$d"*.patch 2>/dev/null | wc -l)
    [ "$n" -gt 0 ] && echo "  $d: $n files, $(cat "$d"*.patch | wc -l) lines"
done
echo "clangd_patches_with_unit_tests: $(grep -l 'unittests/' packaging/clangd-index-nav/*.patch | wc -l) of $(ls packaging/clangd-index-nav/*.patch | wc -l)"
echo "llvm_pin: $(grep -n 'llvm-libs=' packaging/clangd-index-nav/PKGBUILD | head -1)"
echo "llvm_pkgver: $(grep -n '^pkgver=' packaging/clangd-index-nav/PKGBUILD)"
# A package's "--" names: the package name at a symbol's start (so consult-eglot's are
# consult-eglot's, not eglot's), then "--" and the rest.
pat='(^|[^a-zA-Z0-9-])(consult-eglot|consult|eglot|jsonrpc|orderless|vertico|projectile|corfu|cape|dape|magit|treemacs)--[a-zA-Z-]+'
syms() { grep -ohE "$pat" lisp/*.el | sed -E 's/^[^a-zA-Z]//'; }
echo "internal_symbols: $(syms | sort -u | wc -l) distinct, $(syms | wc -l) uses (lisp/*.el; -- names of the packages)"
echo "internal_symbols_by_package:"
syms | sed -E 's/--.*//' | sort | uniq -c | awk '{print "  " $2 ": " $1 " uses"}'
echo "internal_symbols_by_file:"
grep -cE "$pat" lisp/*.el | grep -v ':0$' | sed 's/^/  /'
echo "internal_symbols_list:"
syms | sort | uniq -c | awk '{print "  " $2 " " $1}'
echo "lisp_claim: $(grep -n 'under ~600 lines' DESIGN.md | cut -c1-80)"
echo "standard_stamp: $(sed -n 3p CLAUDE.md)"
echo "license: $(ls LICENSE* COPYING* 2>/dev/null || echo none)"
echo "research_files: $(ls RESEARCH_*.md | wc -l), design_lines: $(wc -l < DESIGN.md), decisions: $(grep -c '^| D-[0-9]' DESIGN.md)"
