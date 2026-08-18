#!/usr/bin/env bash
# Helper: run playbook with ansible-navigator + local AAP vars
set -euo pipefail

aap_run() {
  local playbook="$1"
  shift
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
  local repo_root
  repo_root="$(cd "${root}/../../.." && pwd -P)"
  local vars_file="${root}/vars/local.yml"

  if [[ ! -f "${vars_file}" ]]; then
    echo "Error: ${vars_file} not found. Copy vars/local.yml.example to vars/local.yml." >&2
    exit 1
  fi

  local -a nav_args=()
  local arg
  for arg in "$@"; do
    if [[ "${arg}" == @* ]]; then
      local file_path="${arg#@}"
      if [[ -f "${file_path}" && "${file_path}" == "${repo_root}/"* ]]; then
        arg="@/runner/repo/${file_path#${repo_root}/}"
      fi
    fi
    nav_args+=("${arg}")
  done

  cd "${root}"
  ansible-navigator run "${root}/${playbook}" \
    --mode stdout \
    -e "@vars/local.yml" \
    "${nav_args[@]}"
}
