#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT HUP INT TERM
export XDG_CACHE_HOME="$task_tmp/cache"
export XDG_CONFIG_HOME="$task_tmp/config"
export XDG_STATE_HOME="$task_tmp/state"
export XDG_DATA_HOME="$task_tmp/data"
export NVIM_LOG_FILE="$task_tmp/nvim.log"
"${NVIM:-nvim}" --headless -u tests/minimal_init.lua -i NONE -l tests/run.lua
