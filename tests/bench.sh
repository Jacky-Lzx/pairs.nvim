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
. ./tests/runner.sh
run_suite tests/bench.lua "$bench_tmp"
