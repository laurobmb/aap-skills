#!/usr/bin/env bash
# Helper: corre playbook com ansible-navigator + vars locais do AAP
set -euo pipefail

aap_run() {
  local playbook="$1"
  shift
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local vars_file="${root}/vars/local.yml"
  local shared_vars="${root}/../aap-admin/vars/local.yml"

  if [[ ! -f "${vars_file}" ]]; then
    if [[ -f "${shared_vars}" ]]; then
      cp "${shared_vars}" "${vars_file}"
    else
      echo "Erro: credenciais não encontradas." >&2
      echo "Configure ${root}/vars/local.yml ou ../aap-admin/vars/local.yml" >&2
      exit 1
    fi
  fi

  cd "${root}"
  ansible-navigator run "${root}/${playbook}" \
    --mode stdout \
    -e "@vars/local.yml" \
    "$@"
}
