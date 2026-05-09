#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

KERNEL_BINARY=""
FORCE=0
DRY_RUN=0
SKIP_RESTART=0

usage() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} --binary /path/to/vmlinux [--force] [--dry-run] [--skip-restart]

Options:
  --binary <path>   Path to the guest kernel binary to install.
  --force           Do not prompt before replacing the configured kernel.
  --dry-run         Print the commands that would run without changing anything.
  --skip-restart    Set the kernel but do not restart container services.
  -h, --help        Show this help message.
EOF
}

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi

  "$@"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

print_kernel_state() {
  local label="$1"

  log ""
  log "${label}:"
  if ! run container system property get kernel.binaryPath; then
    die "could not read container kernel configuration"
  fi
}

confirm_kernel_swap() {
  [[ "$FORCE" -eq 1 ]] && return 0

  log ""
  log "This will set the default Apple container guest kernel to:"
  log "  ${KERNEL_BINARY}"
  log ""
  log "Existing containers may need to be recreated before they use the new kernel."
  read -r -p "Continue? [y/N] " reply

  case "$reply" in
    [Yy] | [Yy][Ee][Ss]) ;;
    *) die "kernel swap cancelled" ;;
  esac
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --binary)
        [[ "$#" -ge 2 ]] || die "--binary requires a path"
        KERNEL_BINARY="$2"
        shift 2
        ;;
      --force)
        FORCE=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --skip-restart)
        SKIP_RESTART=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  require_command container

  [[ -n "$KERNEL_BINARY" ]] || die "missing required --binary path"
  [[ -f "$KERNEL_BINARY" ]] || die "kernel binary does not exist: $KERNEL_BINARY"
  [[ -r "$KERNEL_BINARY" ]] || die "kernel binary is not readable: $KERNEL_BINARY"

  print_kernel_state "Kernel configuration before change"
  confirm_kernel_swap

  log ""
  log "Installing guest kernel..."
  kernel_set_args=(container system kernel set --binary "$KERNEL_BINARY")
  if [[ "$FORCE" -eq 1 ]]; then
    kernel_set_args+=(--force)
  fi
  run "${kernel_set_args[@]}"

  if [[ "$SKIP_RESTART" -eq 0 ]]; then
    log ""
    log "Restarting container services..."
    run container system stop
    run container system start --disable-kernel-install
  fi

  print_kernel_state "Kernel configuration after change"
  log ""
  log "Done."
}

main "$@"
