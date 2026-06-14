#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/create_team.yml "$@"
