# Shared output handling for tests/run.sh and tests/bench.sh (sourced).
# NVIM is the parent Neovim's RPC address in terminals/jobs, not an executable.
nvim_bin=${NVIM_BIN:-nvim}
green= red= reset=
if [ -z "${NO_COLOR:-}" ] && { [ -t 1 ] && [ "${TERM:-}" != dumb ] || [ "${FORCE_COLOR:-0}" = 1 ]; }; then
  green=$(printf '\033[32m')
  red=$(printf '\033[31m')
  reset=$(printf '\033[0m')
fi

run_suite() {
  # Neovim writes edit messages and interactive prompts to stderr. Keep those
  # for failures; successful suites write their report directly to stdout.
  if "$nvim_bin" --headless -u tests/minimal_init.lua -i NONE -l "$1" \
    >"$2/stdout" 2>"$2/stderr"; then
    while IFS= read -r line; do
      case "$line" in
        PASS:*) printf '%sPASS%s:%s\n' "$green" "$reset" "${line#PASS:}" ;;
        *) printf '%s\n' "$line" ;;
      esac
    done <"$2/stdout"
  else
    status=$?
    cat "$2/stdout" "$2/stderr" >&2
    printf '\n%sFAIL%s: %s (exit %s)\n' "$red" "$reset" "$1" "$status" >&2
    exit "$status"
  fi
}
