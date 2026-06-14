#!/usr/bin/env bash
# Helper: corre playbook com ansible-navigator + vars locais do AAP
set -euo pipefail

aap_run() {
  local playbook="$1"
  shift
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local vars_file="${root}/vars/local.yml"

  if [[ ! -f "${vars_file}" ]]; then
    echo "Erro: ${vars_file} não existe. Copie vars/local.yml.example para vars/local.yml." >&2
    exit 1
  fi

  cd "${root}"
  ansible-navigator run "${root}/${playbook}" \
    --mode stdout \
    -e "@${vars_file}" \
    "$@"
}
