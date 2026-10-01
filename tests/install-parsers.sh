#!/bin/sh
# Build optional test fixtures from generated upstream C sources. No TS CLI needed.
set -eu
fixture_root=${1:?Usage: tests/install-parsers.sh /absolute/fixture/root}
mkdir -p "$fixture_root/parser"
build_tmp=$(mktemp -d)
trap 'rm -rf "$build_tmp"' EXIT HUP INT TERM
case $(uname -s) in
  Darwin) link_flag=-dynamiclib ;;
  *) link_flag=-shared ;;
esac
while read -r language revision; do
  curl --fail --silent --show-error --location --retry 3 \
    "https://codeload.github.com/tree-sitter/tree-sitter-$language/tar.gz/$revision" \
    -o "$build_tmp/$language.tar.gz"
  mkdir "$build_tmp/$language"
  tar -xzf "$build_tmp/$language.tar.gz" -C "$build_tmp/$language" --strip-components=1
  "${CC:-cc}" "$link_flag" -fPIC -O2 -I "$build_tmp/$language/src" \
    "$build_tmp/$language/src/parser.c" "$build_tmp/$language/src/scanner.c" \
    -o "$fixture_root/parser/$language.so"
done <<'PARSERS'
python v0.25.0
rust 77a3747266f4d621d0757825e6b11edcbf991ca5
javascript 58404d8cf191d69f2674a8fd507bd5776f46cb11
PARSERS

# TypeScript and TSX share a repository but have separate generated grammars.
curl --fail --silent --show-error --location --retry 3 \
  "https://codeload.github.com/tree-sitter/tree-sitter-typescript/tar.gz/v0.23.2" \
  -o "$build_tmp/typescript.tar.gz"
mkdir "$build_tmp/typescript"
tar -xzf "$build_tmp/typescript.tar.gz" -C "$build_tmp/typescript" --strip-components=1
for language in typescript tsx; do
  "${CC:-cc}" "$link_flag" -fPIC -O2 -I "$build_tmp/typescript/$language/src" \
    "$build_tmp/typescript/$language/src/parser.c" \
    "$build_tmp/typescript/$language/src/scanner.c" \
    -o "$fixture_root/parser/$language.so"
done

# The official npm release includes generated LaTeX C sources (the Git checkout
# does not). Pin the release; no npm install or Tree-sitter CLI is required.
curl --fail --silent --show-error --location --retry 3 \
  "https://registry.npmjs.org/@pfoerster/tree-sitter-latex/-/tree-sitter-latex-0.6.0.tgz" \
  -o "$build_tmp/latex.tar.gz"
mkdir "$build_tmp/latex"
tar -xzf "$build_tmp/latex.tar.gz" -C "$build_tmp/latex" --strip-components=1
"${CC:-cc}" "$link_flag" -fPIC -O2 -I "$build_tmp/latex/src" \
  "$build_tmp/latex/src/parser.c" "$build_tmp/latex/src/scanner.c" \
  -o "$fixture_root/parser/latex.so"
