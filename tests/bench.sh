#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
bench_tmp=$(mktemp -d)
trap 'rm -rf "$bench_tmp"' EXIT HUP INT TERM
export XDG_CACHE_HOME="$bench_tmp/cache"
export XDG_CONFIG_HOME="$bench_tmp/config"
export XDG_STATE_HOME="$bench_tmp/state"
export XDG_DATA_HOME="$bench_tmp/data"
export NVIM_LOG_FILE="$bench_tmp/nvim.log"
"${NVIM:-nvim}" --headless -u tests/minimal_init.lua -i NONE -l tests/bench.lua
