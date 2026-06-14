#!/usr/bin/env bash
# Helper: run playbook with ansible-navigator + local AAP vars
set -euo pipefail

aap_run() {
  local playbook="$1"
  shift
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local vars_file="${root}/vars/local.yml"

  if [[ ! -f "${vars_file}" ]]; then
    echo "Error: ${vars_file} not found. Copy vars/local.yml.example to vars/local.yml." >&2
    exit 1
  fi

  cd "${root}"
  ansible-navigator run "${root}/${playbook}" \
    --mode stdout \
    -e "@vars/local.yml" \
    "$@"
}
