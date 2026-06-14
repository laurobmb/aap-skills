#!/usr/bin/env bash
# Apply a numbered vars deployment from repo-root deployments/<name>/
set -euo pipefail

deployment="${1:?Usage: apply-deployment.sh <deployment-name>}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "${script_dir}/.." && pwd)"
repo_root="$(cd "${skill_root}/../../.." && pwd)"
deploy_dir="${repo_root}/deployments/${deployment}"

if [[ ! -d "${deploy_dir}" ]]; then
  echo "Error: deployment not found: ${deploy_dir}" >&2
  exit 1
fi

resolve_script() {
  local resource="$1"
  case "${resource}" in
    organization*) echo "create-organization.sh" ;;
    project*) echo "create-project.sh" ;;
    inventory*) echo "create-inventory.sh" ;;
    host*) echo "create-host.sh" ;;
    group*) echo "create-group.sh" ;;
    job-template*) echo "create-job-template.sh" ;;
    credential*) echo "create-credential.sh" ;;
    workflow*) echo "create-workflow.sh" ;;
    schedule*) echo "create-schedule.sh" ;;
    label*) echo "create-label.sh" ;;
    team*) echo "create-team.sh" ;;
    execution-environment*) echo "create-execution-environment.sh" ;;
    notification-template*) echo "create-notification-template.sh" ;;
    inventory-source*) echo "create-inventory-source.sh" ;;
    instance-group*) echo "create-instance-group.sh" ;;
    *)
      echo "Error: unknown resource type in filename: ${resource}" >&2
      return 1
      ;;
  esac
}

mapfile -t vars_files < <(find "${deploy_dir}" -maxdepth 1 -name '[0-9][0-9]-*.yml' | sort)

if [[ ${#vars_files[@]} -eq 0 ]]; then
  echo "Error: no numbered vars files (NN-<resource>.yml) in ${deploy_dir}" >&2
  exit 1
fi

echo "Applying deployment '${deployment}' (${#vars_files[@]} steps)..."

for vars_file in "${vars_files[@]}"; do
  basename="$(basename "${vars_file}")"
  resource="${basename#*-}"
  resource="${resource%.yml}"
  script="$(resolve_script "${resource}")"

  echo ""
  echo "==> ${basename} → ${script}"
  "${skill_root}/scripts/${script}" -e "@${vars_file}"
done

echo ""
echo "Deployment '${deployment}' applied."
