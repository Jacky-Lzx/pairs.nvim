#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
nvim --headless -u NONE -i NONE --noplugin -l tests/setup_contract.lua
nvim --headless -u NONE -i NONE --noplugin -l tests/command_ownership.lua
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT HUP INT TERM
export XDG_CACHE_HOME="$task_tmp/cache"
export XDG_CONFIG_HOME="$task_tmp/config"
export XDG_STATE_HOME="$task_tmp/state"
export XDG_DATA_HOME="$task_tmp/data"
export NVIM_LOG_FILE="$task_tmp/nvim.log"
. ./tests/runner.sh

run_suite tests/run.lua "$task_tmp"
run_suite tests/rainbow_snapshot.lua "$task_tmp"
run_suite tests/rainbow_ui.lua "$task_tmp"
run_suite tests/space_ui.lua "$task_tmp"
