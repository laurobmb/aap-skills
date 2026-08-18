# SPEC.md — aap-skills

**Document type:** reproduction specification  
**Version:** 2.0  
**Platform:** Red Hat Ansible Automation Platform (AAP) **2.6**  
**Repository:** https://github.com/laurobmb/aap-skills  
**Working branch:** `v2.6`  
**Language of artifacts:** American English (skills, rules, playbooks, docs)

Do **not** copy `vars/local.yml` from anywhere. Credentials are never part of this spec. Use `vars/local.yml.example`.

---

## Table of contents

1. [Purpose of this specification](#1-purpose-of-this-specification)
2. [Problem and design goals](#2-problem-and-design-goals)
3. [Architecture](#3-architecture)
4. [Cursor skill contract](#4-cursor-skill-contract)
5. [Cursor rules contract](#5-cursor-rules-contract)
6. [Runtime: ansible-navigator and EE](#6-runtime-ansible-navigator-and-ee)
7. [Credentials and gitignore](#7-credentials-and-gitignore)
8. [Path resolution and volume mounts](#8-path-resolution-and-volume-mounts)
9. [Script and playbook patterns](#9-script-and-playbook-patterns)
10. [How to add a new aap-admin resource](#10-how-to-add-a-new-aap-admin-resource)
11. [aap-admin catalog](#11-aap-admin-catalog)
12. [aap-operate catalog](#12-aap-operate-catalog)
13. [Automatic defaults](#13-automatic-defaults)
14. [Deployments](#14-deployments)
15. [User-level skill installation](#15-user-level-skill-installation)
16. [Security model](#16-security-model)
17. [Reproduction procedure](#17-reproduction-procedure)
18. [Canonical source](#18-canonical-source)

---

## 1. Purpose of this specification

This document is richer than `README.md`. It defines:

- **Why** the project exists and which constraints are non-negotiable
- **How** Cursor skills, rules, wrappers, scripts, and playbooks fit together
- **The exact files** to create, with full contents in [section 18](#18-canonical-source)
- **Recipes** to extend the system (new resource, new deployment, user-skill symlink)

An engineer or an AI agent should be able to recreate this repository from this file alone (minus secrets and git history).

`README.md` presents the repository and its motivation. `SKILL.md` files remain the agent-facing runbooks. This `SPEC.md` is the build specification.

---

## 2. Problem and design goals

Operating AAP involves many linked objects (organization, project, inventory, credential, job template, workflow, EE). An unconstrained AI agent tends to invent API fields, install collections on the host, or apply `state: absent` / HTTP DELETE.

### Goals

| Goal | Implementation |
|------|----------------|
| Repeatable create/update | One shell script + one playbook per resource, always `state: present` |
| No host collections | `ansible-navigator` + fixed EE image |
| Safe agent behavior | Cursor rules: no delete without explicit human confirmation |
| Secrets out of git | `vars/local.yml` gitignored; example file only |
| GitOps stacks | Numbered vars files in `deployments/<name>/`, applied in order |
| Discoverable by Cursor | `SKILL.md` YAML frontmatter (`name` + `description`) |

### Non-goals (by design)

- Delete / remove automation (`state: absent`)
- RBAC role assignment scripts
- EDA / Automation Hub management
- Bulk config-as-code via `infra.aap_configuration` roles (collection is in the EE for reference only)
- Health-check skill (`aap-diagnose`) — discussed, not built

---

## 3. Architecture

```
Human / Cursor agent
        │  natural language
        ▼
┌───────────────────────────────────────┐
│ Cursor skills                         │
│  ~/.cursor/skills/aap-admin    ──┐    │
│  ~/.cursor/skills/aap-operate    │    │  (symlinks, optional)
│  .cursor/skills/aap-admin        │    │
│  .cursor/skills/aap-operate      ◄┘   │
│ Cursor rules  .cursor/rules/*.mdc     │
└───────────────────┬───────────────────┘
                    │  ./aap | ./operate | ./scripts/*.sh
                    ▼
┌───────────────────────────────────────┐
│ scripts/lib/aap-run.sh                │
│  pwd -P → skill root                  │
│  require/copy vars/local.yml          │
│  rewrite @/abs/repo/file → /runner/repo
│  ansible-navigator run playbook       │
└───────────────────┬───────────────────┘
                    │  podman/docker
                    ▼
┌───────────────────────────────────────┐
│ EE quay.io/lagomes/ee-cac-rhel9:v7    │
│  ansible.controller (primary)         │
│  playbooks run on localhost           │
└───────────────────┬───────────────────┘
                    │  Controller API v2
                    ▼
            AAP 2.6 Controller
```

### Layout to recreate

```
aap-skills/
├── README.md
├── SPEC.md                          # this file
├── .gitignore
├── aap                              # wrapper → aap-admin/scripts
├── operate                          # wrapper → aap-operate/scripts
├── apply-deployment                 # wrapper → apply-deployment.sh
├── deployments/
│   ├── README.md
│   ├── teste-cursor/
│   └── crucible/
└── .cursor/
    ├── rules/
    │   ├── aap-safety.mdc
    │   ├── aap-defaults.mdc
    │   └── aap-skills-git.mdc
    └── skills/
        ├── aap-admin/
        │   ├── SKILL.md
        │   ├── ansible-navigator.yml
        │   ├── playbooks/
        │   ├── scripts/
        │   └── vars/
        └── aap-operate/
            ├── SKILL.md
            ├── ansible-navigator.yml
            ├── playbooks/
            ├── scripts/
            └── vars/
```

### Component roles

| Path | Role |
|------|------|
| `.cursor/skills/aap-admin/` | **How** to create/update Controller resources |
| `.cursor/skills/aap-operate/` | **How** to launch, sync, list |
| `.cursor/rules/` | Always-on agent guardrails |
| `deployments/` | **What** to apply per environment (vars only) |
| `vars/examples/` | Generic copy-paste extra-vars templates |
| `aap` / `operate` / `apply-deployment` | Repo-root shortcuts |

---

## 4. Cursor skill contract

Cursor discovers a skill when a directory contains `SKILL.md` with YAML frontmatter.

### Required frontmatter

| Field | Rules |
|-------|--------|
| `name` | lowercase, hyphens, max 64 chars; matches directory name |
| `description` | third person; WHAT + WHEN; include trigger terms so the agent auto-selects the skill |

Do **not** set `disable-model-invocation: true` on these skills — they must auto-invoke from ambient context (create job template, launch job, list resources, …).

### Locations

| Type | Path | Scope |
|------|------|-------|
| Project | `.cursor/skills/<name>/` | This repository |
| Personal | `~/.cursor/skills/<name>/` | All Cursor workspaces |
| Forbidden | `~/.cursor/skills-cursor/` | Cursor built-in skills |

### Two skills

**aap-admin** — create/configure: organization, project, inventory, host, group, inventory source, credential, job template, workflow, schedule, team, user, label, notification template, execution environment, instance group. Also `verify-aap`.

**aap-operate** — operate existing resources: launch job, sync project, list organizations/projects/job templates/jobs/inventories.

The agent **must** run the shell scripts, never invent ad hoc `curl` or `ansible-playbook` against the host.

Full `SKILL.md` bodies are in [section 18](#18-canonical-source).

---

## 5. Cursor rules contract

Project rules live in `.cursor/rules/*.mdc` with YAML frontmatter.

All three rules use `alwaysApply: true` in this repository.

| File | Description | Why |
|------|-------------|-----|
| `aap-safety.mdc` | No delete without explicit human confirmation | Prevents `state: absent` / DELETE |
| `aap-defaults.mdc` | Auto-resolve inventory, EE, Machine credential | Agent must not invent names |
| `aap-skills-git.mdc` | Work on `v2.6`; never commit secrets | Repo policy |

### Deletion policy (normative)

**Forbidden without a clear affirmative answer to an explicit delete question:**

- `state: absent` on any `ansible.controller.*` module
- HTTP DELETE to `/api/controller/v2/...`
- `curl -X DELETE` or equivalent
- Scripts/playbooks whose purpose is delete/remove/destroy
- Replacing membership with absence (e.g. removing hosts from a group) unless asked

Vague "ok" / "yes" to a different question does **not** count.

**Allowed without extra confirmation:** `state: present`, GET/list, launch job, sync project, verify connectivity.

Do **not** copy `aap-skills-git.mdc` to `~/.cursor/rules/` (it is repo-specific). Safety and defaults **may** be copied there if the operator wants them in every workspace.

---

## 6. Runtime: ansible-navigator and EE

### Host prerequisites

| Requirement | Notes |
|-------------|-------|
| `ansible-navigator` | Tested with 26.x |
| `podman` or `docker` | `container-engine: auto` |
| Network | Controller URL + `quay.io` |
| Cursor | Skills + rules |
| Git | Clone this repo |

**Not** required on the host: `ansible-core`, `ansible-galaxy`, Python deps for `ansible.controller`.

### EE image (normative)

```
quay.io/lagomes/ee-cac-rhel9:v7
```

Pull policy: `missing`. Mode: `stdout`. Artifacts: `artifacts/{playbook_name}-{time_stamp}.json` (gitignored).

### Collections inside the EE

| Collection | Role |
|------------|------|
| `ansible.controller` | **All** create/operate playbooks |
| `infra.aap_configuration` | Reference only — not invoked by scripts |
| `ansible.platform` / `ansible.eda` / `ansible.hub` | Present in image; unused by this repo |

### ansible-navigator.yml differences

Both skills mount the skill directory to `/runner/project` with SELinux `:Z`.

**aap-admin only** also mounts the git repo root (`../../..` from the skill directory) to `/runner/repo`. That is required so `./apply-deployment` extra-vars files under `deployments/` are visible inside the container.

**aap-operate** does not mount the repo; operate extra-vars live inside the skill (`vars/examples/`).

---

## 7. Credentials and gitignore

### `vars/local.yml` (never commit)

```yaml
aap_host: https://ansible-automation-platform.example.com
aap_username: admin
aap_password: CHANGE_ME
aap_validate_certs: true   # aap-admin example; operate example uses false
```

Map to modules via `vars/aap_defaults.yml`:

| local.yml | Module / URI |
|-----------|----------------|
| `aap_host` | `controller_host` |
| `aap_username` | `controller_username` |
| `aap_password` | `controller_password` |
| `aap_validate_certs` | `validate_certs` |

### Load order

1. **aap-admin** `aap-run.sh`: fail if `vars/local.yml` is missing (tell operator to copy the example).
2. **aap-operate** `aap-run.sh`: if missing, copy `../aap-admin/vars/local.yml`; else fail.

### `.gitignore`

```
artifacts/
*.log
.env
.env.*
secrets/
__pycache__/
.ansible/
.cursor/skills/aap-admin/vars/local*.yml
.cursor/skills/aap-operate/vars/local*.yml
```

Note: `local*.yml` also matches `local.yml.example`. Keep examples tracked with `git add -f` if gitignore applies.

Lab URL used in this workspace (not a secret): `https://ansible-automation-platform.lagomes.rhbr-lab.com`. Default org: `Default`. Test org: `teste cursor`.

---

## 8. Path resolution and volume mounts

Scripts must use **physical** paths (`pwd -P`) so they still work when the skill is a symlink from `~/.cursor/skills/<name>`.

### aap-admin `aap-run.sh`

```
skill root  = dirname(lib/aap-run.sh)/../..     # pwd -P
repo root   = skill root / ../../..             # .cursor/skills/aap-admin → repo
```

For each extra-var argument starting with `@`:

- If the file exists **and** its path is under `repo_root`, rewrite to `@/runner/repo/<relative-to-repo>`.
- Otherwise leave as-is (paths relative to the skill directory work as `/runner/project/...` after `cd` to skill root).

Then:

```
cd $skill_root
ansible-navigator run $skill_root/$playbook --mode stdout -e @vars/local.yml <rewritten args>
```

### aap-operate `aap-run.sh`

Same skill-root resolution. No repo rewrite. Extra args passed through.

### Wrappers at repo root

| Wrapper | Behavior |
|---------|----------|
| `./aap <script.sh> [args]` | `exec .cursor/skills/aap-admin/scripts/<script> "$@"` |
| `./operate <script.sh> [args]` | `exec .cursor/skills/aap-operate/scripts/<script> "$@"` |
| `./apply-deployment <name>` | `exec .cursor/skills/aap-admin/scripts/apply-deployment.sh <name>` |

All wrappers: `set -euo pipefail`, first argument mandatory.

### Extra-vars conventions (normative)

- Scalars: `-e project_name=my-project`
- Values with spaces: JSON `-e '{"inventory":"Demo Inventory"}'`
- Files: `-e @vars/examples/job-template.yml` (relative to skill dir) or absolute path under the repo (admin rewrites to `/runner/repo/...`)

---

## 9. Script and playbook patterns

### Thin script (normative)

Every resource/operation script is four lines:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/<playbook>.yml "$@"
```

Do not put Controller logic in bash. The playbook is the source of truth.

### Playbook skeleton (normative)

```yaml
---
- name: Create AAP <resource>
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml
    # optional: import_tasks: tasks/resolve_aap_defaults.yml
    - name: Create or update <resource>
      ansible.controller.<module>:
        name: "{{ <name_var> }}"
        organization: "{{ organization | default(aap_organization_default) }}"
        # resource-specific fields with | default(...) or | default(omit)
        state: present
        controller_host: "{{ controller_connection.controller_host }}"
        controller_username: "{{ controller_connection.controller_username }}"
        controller_password: "{{ controller_connection.controller_password }}"
        validate_certs: "{{ controller_connection.validate_certs }}"
      vars:
        <name_var>: "{{ <name_var> | mandatory }}"
```

Rules:

- Always `hosts: localhost`, `connection: local`, `gather_facts: false`
- Always `state: present`
- Always pass the four `controller_*` / `validate_certs` keys from `controller_connection`
- Required extra-vars use Jinja `| mandatory`
- Optional extra-vars use `| default('')`, `| default(false)`, or `| default(omit)`
- Organization defaults to `aap_organization_default` except on the organization resource itself (`organization_name`)

Playbooks that import `resolve_aap_defaults.yml`: **project**, **job template**, **workflow**.

`verify_aap.yml` is special: it does **not** load `aap_defaults.yml`; it pings `/api/controller/v2/ping/` and `/api/controller/v2/config/` via `ansible.builtin.uri`.

---

## 10. How to add a new aap-admin resource

Use this checklist so the new resource matches the existing contract.

1. Pick identifiers:
   - Ansible module: `ansible.controller.<module>`
   - Playbook: `playbooks/create_<snake>.yml`
   - Script: `scripts/create-<kebab>.sh`
   - Name extra-var: `<name_var>`
2. Write the playbook from the skeleton in section 9.
3. Write the four-line script.
4. `chmod +x` the script.
5. Add `vars/examples/<kebab>.yml` with realistic sample extra-vars.
6. Add a row to `aap-admin/SKILL.md` (script table).
7. If the resource can appear in a deployment, add a `case` arm in `scripts/apply-deployment.sh` → `resolve_script`:
   - Filename: `NN-<prefix>-<name>.yml`
   - Prefix must match the `case` glob (`organization*`, `job-template*`, …)
8. Do **not** add a delete playbook.

### How to add a new operate action

Same as above but under `aap-operate/`, no `apply-deployment` mapping, and prefer `ansible.controller.*` (launch/update) or `ansible.builtin.uri` GET (list). Never DELETE.

### How to add a new deployment

```
mkdir deployments/<stack>
# files: NN-<resource-prefix>-<name>.yml
./apply-deployment <stack>
```

Order numbers encode dependencies (org → project → inventory → hosts → group → job templates).

---

## 11. aap-admin catalog

Shortcut: `./aap <script>.sh [extra vars]`

| Script | Playbook | Module | Name variable | Required extra-vars |
|--------|----------|--------|---------------|---------------------|
| `verify-aap.sh` | `verify_aap.yml` | `ansible.builtin.uri` | — | — |
| `create-organization.sh` | `create_organization.yml` | `organization` | `organization_name` | `organization_name` |
| `create-project.sh` | `create_project.yml` | `project` | `project_name` | `project_name`; `scm_url` if `scm_type` is git (default) |
| `create-inventory.sh` | `create_inventory.yml` | `inventory` | `inventory_name` | `inventory_name` |
| `create-host.sh` | `create_host.yml` | `host` | `host_name` | `host_name`, `inventory` |
| `create-group.sh` | `create_group.yml` | `group` | `group_name` | `group_name`, `inventory` |
| `create-inventory-source.sh` | `create_inventory_source.yml` | `inventory_source` | `source_name` | `source_name`, `inventory`, `source` |
| `create-credential.sh` | `create_credential.yml` | `credential` | `credential_name` | `credential_name`, `inputs` (non-empty mapping) |
| `create-job-template.sh` | `create_job_template.yml` | `job_template` | `job_template_name` | `job_template_name`, `project`, `playbook` |
| `create-workflow.sh` | `create_workflow.yml` | `workflow_job_template` | `workflow_name` | `workflow_name` |
| `create-schedule.sh` | `create_schedule.yml` | `schedule` | `schedule_name` | `schedule_name`, `unified_job_template`, `rrule` |
| `create-execution-environment.sh` | `create_execution_environment.yml` | `execution_environment` | `ee_name` | `ee_name`, `image` |
| `create-team.sh` | `create_team.yml` | `team` | `team_name` | `team_name` |
| `create-user.sh` | `create_user.yml` | `user` | `username` | `username` |
| `create-label.sh` | `create_label.yml` | `label` | `label_name` | `label_name` |
| `create-notification-template.sh` | `create_notification_template.yml` | `notification_template` | `notification_name` | `notification_name`, `notification_type`, `notification_configuration` |
| `create-instance-group.sh` | `create_instance_group.yml` | `instance_group` | `instance_group_name` | `instance_group_name` |
| `apply-deployment.sh` | (orchestrator) | — | — | deployment folder name |

### Optional extra-vars (by playbook)

**organization:** `description`

**project:** `organization`, `description`, `scm_type` (default `git`), `scm_url` (omit if manual), `scm_branch` (default `main` when git), `execution_environment` (resolved if omitted), `update_project` (default true unless manual)

**inventory:** `organization`, `description`, `kind`, `host_filter`, `variables`

**host:** `description`, `enabled` (default true), `variables`

**group:** `description`, `parent`, `variables`, `group_hosts` (list → module `hosts`)

**inventory source:** `description`, `credential`, `source_path`, `source_project`, `source_vars`, `overwrite`, `update_on_launch`

**credential:** `organization`, `credential_type` (default `Machine`), `description`, `inputs` (required mapping)

**job template:** `organization`, `inventory` (resolved), `job_type` (default `run`), `description`, `credentials` (resolved or omit), `execution_environment` (resolved), `extra_vars`, `survey_enabled` (default false), `become_enabled` (default false), `limit`

**workflow:** `organization`, `description`, `inventory` (resolved), `workflow_nodes`, `destroy_current_nodes` (default false), `survey_enabled`

**schedule:** `organization`, `description`, `enabled` (default true), `extra_data`

**execution environment:** `organization`, `description`, `pull`

**team:** `organization`, `description`

**user:** `password`, `first_name`, `last_name`, `email`, `organization`, `is_superuser` (default false)

**label:** `organization`

**notification:** `organization`, `description`, `messages`

**instance group:** `instances`, `is_container_group` (default false), `credential`, `max_concurrent_jobs`

`organization` extra-var default is `Default` except when creating the organization resource.

---

## 12. aap-operate catalog

Shortcut: `./operate <script>.sh [extra vars]`

| Script | Playbook | Mechanism | Required |
|--------|----------|-----------|----------|
| `launch-job.sh` | `launch_job.yml` | `ansible.controller.job_launch` | `job_template_name` |
| `sync-project.sh` | `sync_project.yml` | `ansible.controller.project_update` | `project_name` |
| `list-resources.sh` | `list_resources.yml` | `ansible.builtin.uri` GET | `resource_type` |

### launch-job extra-vars

| Variable | Default | Notes |
|----------|---------|-------|
| `job_template_name` | — | Required |
| `organization` | `Default` | |
| `inventory` | omit | Override |
| `credentials` | omit | |
| `extra_vars` | omit | |
| `limit` | omit | |
| `job_type` | omit | |
| `wait` | `true` | Wait for completion |
| `timeout` | omit | Module default |

### sync-project extra-vars

| Variable | Default |
|----------|---------|
| `project_name` | required |
| `organization` | `Default` |
| `wait` | `true` |
| `timeout` | `300` |

### list-resources extra-vars

| Variable | Default | Notes |
|----------|---------|-------|
| `resource_type` | required | `organizations`, `projects`, `job_templates`, `jobs`, `inventories` |
| `organization` | — | Filter by org name → org id |
| `api_query` | — | Extra query string keys |
| `page_size` | `25` | |
| `order_by` | `name` | |

Endpoints:

```
GET /api/controller/v2/organizations/
GET /api/controller/v2/projects/
GET /api/controller/v2/job_templates/
GET /api/controller/v2/jobs/
GET /api/controller/v2/inventories/
```

---

## 13. Automatic defaults

Implemented in `playbooks/tasks/resolve_aap_defaults.yml` (aap-admin). Used when `inventory`, `execution_environment`, or `credentials` is undefined.

Fallbacks from `aap-admin/vars/aap_defaults.yml`:

```yaml
aap_organization_default: Default
aap_inventory_default: Demo Inventory
aap_ee_default: ee-cac-rhel9
aap_ee_system_default: Default execution environment
```

### Resolution order

| Resource | Order |
|----------|--------|
| Organization (when omitted) | Conversation context (e.g. `teste cursor`) → `Default` |
| Inventory | First inventory in org (`order_by=name&page_size=1`) → `Demo Inventory` |
| EE | Org `summary_fields.default_environment.name` → EE named `Default execution environment` → `ee-cac-rhel9` |
| Credential | First Machine credential in org (`credential_type=1`) → **omit** (do not fail, do not invent) |

The agent must not invent credential names. In production, pass inventory/EE/credential explicitly when the default is not acceptable.

---

## 14. Deployments

Deployments are **vars files only**. The skill provides scripts; a stack describes desired resources.

### Filename contract

```
NN-<resource-prefix>-<optional-name>.yml
```

`apply-deployment.sh` strips `NN-` and `.yml`, then maps the remaining prefix:

| Filename prefix | Script |
|-----------------|--------|
| `organization*` | `create-organization.sh` |
| `project*` | `create-project.sh` |
| `inventory*` | `create-inventory.sh` |
| `host*` | `create-host.sh` |
| `group*` | `create-group.sh` |
| `job-template*` | `create-job-template.sh` |
| `credential*` | `create-credential.sh` |
| `workflow*` | `create-workflow.sh` |
| `schedule*` | `create-schedule.sh` |
| `label*` | `create-label.sh` |
| `team*` | `create-team.sh` |
| `execution-environment*` | `create-execution-environment.sh` |
| `notification-template*` | `create-notification-template.sh` |
| `inventory-source*` | `create-inventory-source.sh` |
| `instance-group*` | `create-instance-group.sh` |

Files are discovered with `find … -name '[0-9][0-9]-*.yml' | sort` (maxdepth 1). Each file is applied as `-e @<absolute path>` so admin `aap-run.sh` rewrites it to `/runner/repo/...`.

### Bundled stacks

**teste-cursor** — org `teste cursor`, backup automation:

| File | Creates |
|------|---------|
| `01-organization.yml` | org `teste cursor` |
| `02-project-aap-backup.yml` | project `aap_backup_automation` (git `laurobmb/aap_backup_automation`) |
| `03-inventory-backup.yml` | inventory `backup-inventory` |
| `04`–`06-host-controller-0N.yml` | three controller FQDNs |
| `07-host-localhost.yml` | localhost, `ansible_connection: local` |
| `08-group-automationcontroller.yml` | group with the three controller hosts |
| `09-job-template-backup-aap.yml` | JT `backup-aap` / `main-backup.yml` / limit `automationcontroller` / become |
| `10-job-template-configure-backup.yml` | JT `configure-backup-project` |

Credentials are **not** in the stack. Machine credentials for controller nodes must exist before launching `backup-aap`.

**crucible** — org `crucible`, project `crucible` from `https://github.com/laurobmb/crucible.git`.

---

## 15. User-level skill installation

To make the skills available in every Cursor workspace (alongside personal skills in `~/.cursor/skills/`):

```bash
ln -sfn /path/to/aap-skills/.cursor/skills/aap-admin \
        ~/.cursor/skills/aap-admin
ln -sfn /path/to/aap-skills/.cursor/skills/aap-operate \
        ~/.cursor/skills/aap-operate
```

Symlinks keep a single source of truth (`vars/local.yml`, playbooks, scripts). `pwd -P` in `aap-run.sh` resolves the real skill directory so the admin repo mount (`../../..` → aap-skills root) still works.

From another workspace, run scripts by skill path:

```bash
~/.cursor/skills/aap-admin/scripts/create-job-template.sh -e @vars/examples/job-template.yml
~/.cursor/skills/aap-operate/scripts/list-resources.sh -e resource_type=job_templates
```

Open a new Cursor chat after linking so the agent rediscovers user skills.

---

## 16. Security model

| Control | Implementation |
|---------|----------------|
| Secrets | `vars/local.yml` gitignored; never paste passwords in chat or commit |
| No delete automation | `aap-safety.mdc` + no absent playbooks |
| Least privilege | Dedicated AAP account (not `admin`) recommended |
| TLS | `aap_validate_certs: true` in examples; lab may use `false` for self-signed |
| Real jobs | `launch-job.sh` executes on real hosts — validate template, inventory, limit |
| Audit | navigator artifacts + Controller activity stream |
| Host isolation | collections only inside the EE |

---

## 17. Reproduction procedure

From an empty directory:

```bash
mkdir -p aap-skills
cd aap-skills
git init
git checkout -b v2.6

# Create every path listed in section 18 with the exact file contents.
# Then:

chmod +x aap operate apply-deployment \
  .cursor/skills/aap-admin/scripts/*.sh \
  .cursor/skills/aap-admin/scripts/lib/aap-run.sh \
  .cursor/skills/aap-operate/scripts/*.sh \
  .cursor/skills/aap-operate/scripts/lib/aap-run.sh

cp .cursor/skills/aap-admin/vars/local.yml.example \
   .cursor/skills/aap-admin/vars/local.yml
# edit aap_host / aap_username / aap_password / aap_validate_certs

# optional user-skill links
ln -sfn "$(pwd)/.cursor/skills/aap-admin"  ~/.cursor/skills/aap-admin
ln -sfn "$(pwd)/.cursor/skills/aap-operate" ~/.cursor/skills/aap-operate

# smoke test (requires reachable Controller + pulled EE)
./aap verify-aap.sh
```

### Agent workflow (normative)

1. Load the matching skill (`aap-admin` vs `aap-operate`) and the three rules.
2. Identify the script from the catalogs.
3. Ask only for missing **required** extra-vars.
4. Run the script (`./aap` / `./operate` in this repo, or `./scripts/` / `~/.cursor/skills/...` elsewhere).
5. Confirm `changed`/`ok` (or list output / job id).
6. Never delete unless the operator confirmed the named resource.

### Example

User: *Create job template backup-aap in org teste cursor*

```bash
./aap create-job-template.sh -e '{
  "job_template_name":"backup-aap",
  "organization":"teste cursor",
  "project":"aap_backup_automation",
  "playbook":"main-backup.yml",
  "limit":"automationcontroller",
  "become_enabled":true
}'
```

User: *Run the backup job*

```bash
./operate launch-job.sh -e '{"job_template_name":"backup-aap","organization":"teste cursor"}'
```

---

## 18. Canonical source

Every file below is the current repository content. Recreate paths relative to the repo root. Do **not** recreate `vars/local.yml`, `artifacts/`, or `*.log`.

### `.gitignore`

```text
artifacts/
*.log
.env
.env.*
secrets/
__pycache__/
.ansible/
.cursor/skills/aap-admin/vars/local*.yml
.cursor/skills/aap-operate/vars/local*.yml
```

### `aap`

```bash
#!/usr/bin/env bash
# Repo root shortcut → aap-admin skill scripts
set -euo pipefail
SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.cursor/skills/aap-admin" && pwd)"
script="${1:?Usage: ./aap <script-name.sh> [args...]}"
shift
exec "${SKILL_ROOT}/scripts/${script}" "$@"
```

### `operate`

```bash
#!/usr/bin/env bash
# Repo root shortcut → aap-operate skill scripts
set -euo pipefail
SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.cursor/skills/aap-operate" && pwd)"
script="${1:?Usage: ./operate <script-name.sh> [args...]}"
shift
exec "${SKILL_ROOT}/scripts/${script}" "$@"
```

### `apply-deployment`

```bash
#!/usr/bin/env bash
# Repo root shortcut → apply a deployment stack
set -euo pipefail
SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.cursor/skills/aap-admin" && pwd)"
deployment="${1:?Usage: ./apply-deployment <deployment-name>}"
exec "${SKILL_ROOT}/scripts/apply-deployment.sh" "${deployment}"
```

### `.cursor/rules/aap-safety.mdc`

```markdown
---
description: AAP resource removal requires explicit human confirmation
alwaysApply: true
---

# AAP — deletion protection

The agent **must never** remove AAP resources without explicit human confirmation from the user.

## Forbidden without confirmation

- `state: absent` on any `ansible.controller.*` module
- **DELETE** calls to the Controller API (`/api/controller/v2/...`)
- `curl -X DELETE`, HTTP DELETE, or equivalent against AAP
- Delete/remove/destroy scripts or playbooks
- Idempotent changes that **replace** an existing resource with absence (e.g. removing hosts from a group without being asked)

## Required human confirmation

Before any removal, the agent must:

1. **Stop** and inform the user: resource name, type, organization, and impact
2. **Ask for explicit confirmation** (e.g. "Do you confirm deleting job template X in org Y?")
3. **Execute only** after a clear affirmative response from the user

Vague answers ("ok", "yes" to the wrong question) or inferred intent **do not** count as confirmation for delete.

## Allowed without extra confirmation

- `state: present` (create or update)
- List resources (`list-resources.sh`, GET on API)
- Launch jobs (`launch-job.sh`)
- Sync projects (`sync-project.sh`)
- Verify connectivity (`verify-aap.sh`)

## Credentials

Never commit or expose credentials in deletion commands or shared logs.
```

### `.cursor/rules/aap-defaults.mdc`

```markdown
---
description: Default inventory, credential, and EE on AAP when not specified
alwaysApply: true
---

# AAP — automatic defaults

When the user **does not specify** inventory, credential, or execution environment (EE), the agent should use the **first available resource in AAP** for the target organization — without asking, unless there is critical ambiguity.

## Resolution order

### Inventory
1. First inventory in the target **organization** (via API)
2. Fallback in `vars/aap_defaults.yml`: `aap_inventory_default` (`Demo Inventory`)

### Execution environment (EE)
1. Organization **default EE** (`default_environment`)
2. Controller EE `Default execution environment`
3. Fallback: `aap_ee_default` (`ee-cac-rhel9`)

### Credential
1. First **Machine** credential in the organization
2. If none exists in the org → omit (do not fail)
3. Never invent credentials

## Organization

If not specified → `aap_organization_default` (`Default`), except when conversation context indicates another (e.g. `teste cursor`).

## Implementation

Playbooks in `.cursor/skills/aap-admin/playbooks/` include `tasks/resolve_aap_defaults.yml` when applicable. The agent **does not need** to pass `-e inventory=...` when the default is acceptable.

## Example

Request: *"Create job template X with project Y and playbook Z in org teste cursor"*

```bash
./aap create-job-template.sh -e '{
  "job_template_name":"X",
  "organization":"teste cursor",
  "project":"Y",
  "playbook":"Z"
}'
```

Inventory, EE, and credential are resolved automatically.
```

### `.cursor/rules/aap-skills-git.mdc`

```markdown
---
description: Git and commits for the aap-skills repository (v2.6 branch)
alwaysApply: true
---

# Git — v2.6 branch

This repository is the workspace for skills that administer Red Hat Ansible Automation Platform (AAP).

## Working branch

- Always work and commit on branch **`v2.6`**.
- Do not commit to `main` unless the user explicitly requests it.

## Commits

- **May commit** to this repository when the user asks or when completing a task that requires persisting changes.
- Follow the repository commit message style when history exists.
- Do not push without an explicit request.

## Sensitive files

- Never commit credentials, AAP tokens, vault passwords, or `.env` files with secrets.
- Use environment variables or local files ignored by `.gitignore`.
```

### `.cursor/skills/aap-admin/SKILL.md`

```markdown
---
name: aap-admin
description: >-
  Creates and manages resources on Ansible Automation Platform (AAP) 2.6 via
  scripts and playbooks with ansible-navigator and EE quay.io/lagomes/ee-cac-rhel9:v7.
  Use when the user asks to create or configure organization, project, inventory,
  host, group, credential, job template, workflow, schedule, team, user, label,
  notification, execution environment, or instance group on AAP.
---

# AAP Admin (2.6)

Everything in this skill lives next to this `SKILL.md` (playbooks, scripts, vars). Also available as a user skill at `~/.cursor/skills/aap-admin/`.

## Main rule

**Always** use scripts in `scripts/` — they run via `ansible-navigator` + EE (no local collections).

**Never** remove resources (`state: absent`, API DELETE) without explicit human confirmation — see `.cursor/rules/aap-safety.mdc`.

```bash
# From this skill directory
./scripts/create-<resource>.sh -e @vars/examples/<resource>.yml

# From aap-skills repo root
./aap create-job-template.sh -e @.cursor/skills/aap-admin/vars/examples/job-template.yml
```

Controller credentials: `vars/local.yml` (gitignored).

## Automatic defaults

If **inventory**, **credential**, or **EE** are not specified, playbooks resolve them automatically from AAP (see `.cursor/rules/aap-defaults.mdc`):

| Resource | Resolution order |
|----------|------------------|
| Inventory | First in organization → `Demo Inventory` |
| EE | Org default → `Default execution environment` → `ee-cac-rhel9` |
| Credential | First Machine in organization → omit if none exists |

## Agent workflow

1. Identify the requested resource (table below).
2. Collect required parameters — ask only for what is missing.
3. Run the script (via `./aap <script>` from root or `./scripts/<script>` in the skill).
4. Confirm `changed`/`ok` in the output.

Values with **spaces** (e.g. `Demo Inventory`) → use JSON or `-e @vars/...`.

## Available scripts

| Resource | Script | Name variable | Required |
|----------|--------|---------------|----------|
| Connectivity | `verify-aap.sh` | — | — |
| Organization | `create-organization.sh` | `organization_name` | `organization_name` |
| Project | `create-project.sh` | `project_name` | `project_name`, `scm_url` (if git) |
| Inventory | `create-inventory.sh` | `inventory_name` | `inventory_name` |
| Host | `create-host.sh` | `host_name` | `host_name`, `inventory` |
| Group | `create-group.sh` | `group_name` | `group_name`, `inventory` |
| Inventory source | `create-inventory-source.sh` | `source_name` | `source_name`, `inventory`, `source` |
| Credential | `create-credential.sh` | `credential_name` | `credential_name`, `inputs` |
| Job template | `create-job-template.sh` | `job_template_name` | `job_template_name`, `project`, `playbook` |
| Workflow | `create-workflow.sh` | `workflow_name` | `workflow_name` |
| Schedule | `create-schedule.sh` | `schedule_name` | `schedule_name`, `unified_job_template`, `rrule` |
| Execution env. | `create-execution-environment.sh` | `ee_name` | `ee_name`, `image` |
| Team | `create-team.sh` | `team_name` | `team_name` |
| User | `create-user.sh` | `username` | `username` |
| Label | `create-label.sh` | `label_name` | `label_name` |
| Notification | `create-notification-template.sh` | `notification_name` | `notification_name`, `notification_type`, `notification_configuration` |
| Instance group | `create-instance-group.sh` | `instance_group_name` | `instance_group_name` |

`organization` default: `Default` (except for organization resource).

## Quick examples

### Job template

```bash
./scripts/create-job-template.sh \
  -e job_template_name=deploy-web \
  -e '{"inventory":"Demo Inventory","project":"Demo Project","playbook":"hello_world.yml"}'
```

### Machine credential

```bash
./scripts/create-credential.sh \
  -e credential_name=host-01 \
  -e '{"inputs":{"username":"ansible","password":"secret"}}'
```

### Workflow with one job

```bash
./scripts/create-workflow.sh -e @vars/examples/workflow.yml
```

### Schedule

```bash
./scripts/create-schedule.sh \
  -e schedule_name=daily-backup \
  -e unified_job_template=my-job \
  -e 'rrule=DTSTART:20260614T080000Z RRULE:FREQ=DAILY;INTERVAL=1'
```

## Deployments (`deployments/` at repo root)

Versioned stacks live **outside** the skill — one folder per environment/org. The skill only provides scripts; deployments define what to apply.

```bash
# Apply entire deployment
./apply-deployment teste-cursor

# Single resource (absolute path — scripts run from skill directory)
./aap create-project.sh -e "@$(pwd)/deployments/teste-cursor/02-project-aap-backup.yml"
```

Naming convention: `NN-<resource>-<name>.yml` (e.g. `02-project-aap-backup.yml`).

| Deployment | Organization | Purpose |
|------------|--------------|---------|
| `teste-cursor` | `teste cursor` | AAP backup automation stack |
| `crucible` | `crucible` | Crucible OpenShift playbooks |

See `deployments/README.md` to add new stacks.

## Examples in vars/examples/

Generic templates (copy and adapt). For real stacks, use `deployments/<name>/`.

| File | Resource |
|------|----------|
| `organization.yml` | Organization |
| `project.yml` | Project |
| `inventory.yml` | Inventory |
| `host.yml` | Host |
| `group.yml` | Group |
| `inventory-source.yml` | Inventory source |
| `credential-machine.yml` | Credential |
| `job-template.yml` | Job template |
| `workflow.yml` | Workflow |
| `schedule.yml` | Schedule |
| `execution-environment.yml` | Execution environment |
| `team.yml` | Team |
| `label.yml` | Label |
| `notification-template.yml` | Notification |

## Controller (lab)

- URL: `https://ansible-automation-platform.lagomes.rhbr-lab.com`
- Default org: `Default`
- Local EE: `ee-cac-rhel9` / `quay.io/lagomes/ee-cac-rhel9:v7`

## Collections (inside EE)

- `ansible.controller` — modules used in playbooks
- `infra.aap_configuration` — config-as-code roles (reference)
```

### `.cursor/skills/aap-admin/ansible-navigator.yml`

```yaml
---
ansible-navigator:
  ansible:
    playbook:
      path: ./playbooks
  execution-environment:
    container-engine: auto
    enabled: true
    image: quay.io/lagomes/ee-cac-rhel9:v7
    pull:
      policy: missing
    volume-mounts:
      - src: .
        dest: /runner/project
        options: Z
      - src: ../../..
        dest: /runner/repo
        options: Z
  logging:
    level: warning
  mode: stdout
  playbook-artifact:
    enable: true
    save-as: artifacts/{playbook_name}-{time_stamp}.json
```

### `.cursor/skills/aap-admin/scripts/lib/aap-run.sh`

```bash
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
```

### `.cursor/skills/aap-admin/scripts/apply-deployment.sh`

```bash
#!/usr/bin/env bash
# Apply a numbered vars deployment from repo-root deployments/<name>/
set -euo pipefail

deployment="${1:?Usage: apply-deployment.sh <deployment-name>}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
skill_root="$(cd "${script_dir}/.." && pwd -P)"
repo_root="$(cd "${skill_root}/../../.." && pwd -P)"
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
```

### `.cursor/skills/aap-admin/scripts/verify-aap.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/verify_aap.yml "$@"
```

### `.cursor/skills/aap-admin/scripts/create-organization.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/create_organization.yml "$@"
```

### `.cursor/skills/aap-admin/scripts/create-project.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/create_project.yml "$@"
```

### `.cursor/skills/aap-admin/scripts/create-inventory.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/create_inventory.yml "$@"
```

### `.cursor/skills/aap-admin/scripts/create-host.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/create_host.yml "$@"
```

### `.cursor/skills/aap-admin/scripts/create-group.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/create_group.yml "$@"
```

### `.cursor/skills/aap-admin/scripts/create-inventory-source.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/create_inventory_source.yml "$@"
```

### `.cursor/skills/aap-admin/scripts/create-credential.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/create_credential.yml "$@"
```

### `.cursor/skills/aap-admin/scripts/create-job-template.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/create_job_template.yml "$@"
```

### `.cursor/skills/aap-admin/scripts/create-workflow.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/create_workflow.yml "$@"
```

### `.cursor/skills/aap-admin/scripts/create-schedule.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/create_schedule.yml "$@"
```

### `.cursor/skills/aap-admin/scripts/create-execution-environment.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/create_execution_environment.yml "$@"
```

### `.cursor/skills/aap-admin/scripts/create-team.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/create_team.yml "$@"
```

### `.cursor/skills/aap-admin/scripts/create-user.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/create_user.yml "$@"
```

### `.cursor/skills/aap-admin/scripts/create-label.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/create_label.yml "$@"
```

### `.cursor/skills/aap-admin/scripts/create-notification-template.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/create_notification_template.yml "$@"
```

### `.cursor/skills/aap-admin/scripts/create-instance-group.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/create_instance_group.yml "$@"
```

### `.cursor/skills/aap-admin/playbooks/tasks/validate_connection.yml`

```yaml
---
# Include at the start of each resource creation playbook
- name: Validate controller credentials
  ansible.builtin.assert:
    that:
      - aap_host is defined
      - aap_username is defined
      - aap_password is defined
    fail_msg: "Missing credentials. Configure vars/local.yml"
```

### `.cursor/skills/aap-admin/playbooks/tasks/resolve_aap_defaults.yml`

```yaml
---
# Resolve inventory, execution_environment, and credentials when not specified.
# Uses resources available in AAP for the target organization.

- name: Set target organization
  ansible.builtin.set_fact:
    _aap_org: "{{ organization | default(aap_organization_default) }}"

- name: Lookup organization ID
  ansible.builtin.uri:
    url: "{{ aap_host }}/api/controller/v2/organizations/"
    method: GET
    user: "{{ aap_username }}"
    password: "{{ aap_password }}"
    force_basic_auth: true
    validate_certs: "{{ aap_validate_certs | default(false) }}"
    status_code: 200
  register: _aap_orgs
  when: >-
    inventory is not defined or
    execution_environment is not defined or
    credentials is not defined

- name: Find organization ID
  ansible.builtin.set_fact:
    _aap_org_id: "{{ item.id }}"
  loop: "{{ _aap_orgs.json.results }}"
  when:
    - _aap_orgs is defined
    - item.name == _aap_org
  loop_control:
    label: "{{ item.name }}"

- name: Resolve default inventory
  when: inventory is not defined
  block:
    - name: List inventories in organization
      ansible.builtin.uri:
        url: "{{ aap_host }}/api/controller/v2/inventories/?organization={{ _aap_org_id }}&order_by=name&page_size=1"
        method: GET
        user: "{{ aap_username }}"
        password: "{{ aap_password }}"
        force_basic_auth: true
        validate_certs: "{{ aap_validate_certs | default(false) }}"
        status_code: 200
      register: _aap_inv_lookup
      when: _aap_org_id is defined

    - name: Use first inventory in organization
      ansible.builtin.set_fact:
        inventory: "{{ _aap_inv_lookup.json.results[0].name }}"
      when:
        - _aap_inv_lookup is defined
        - _aap_inv_lookup.json.count | int > 0

    - name: Fallback to lab inventory default
      ansible.builtin.set_fact:
        inventory: "{{ aap_inventory_default }}"
      when: inventory is not defined

- name: Resolve default execution environment
  when: execution_environment is not defined
  block:
    - name: Get organization default EE
      ansible.builtin.uri:
        url: "{{ aap_host }}/api/controller/v2/organizations/{{ _aap_org_id }}/"
        method: GET
        user: "{{ aap_username }}"
        password: "{{ aap_password }}"
        force_basic_auth: true
        validate_certs: "{{ aap_validate_certs | default(false) }}"
        status_code: 200
      register: _aap_org_detail
      when: _aap_org_id is defined

    - name: Use organization default EE
      ansible.builtin.set_fact:
        execution_environment: "{{ _aap_org_detail.json.summary_fields.default_environment.name }}"
      when:
        - _aap_org_detail is defined
        - _aap_org_detail.json.summary_fields.default_environment is defined
        - _aap_org_detail.json.summary_fields.default_environment.name | default('') | length > 0

    - name: Lookup system default EE by name
      ansible.builtin.uri:
        url: "{{ aap_host }}/api/controller/v2/execution_environments/?name={{ aap_ee_system_default | urlencode }}"
        method: GET
        user: "{{ aap_username }}"
        password: "{{ aap_password }}"
        force_basic_auth: true
        validate_certs: "{{ aap_validate_certs | default(false) }}"
        status_code: 200
      register: _aap_ee_system
      when: execution_environment is not defined

    - name: Use system default EE
      ansible.builtin.set_fact:
        execution_environment: "{{ _aap_ee_system.json.results[0].name }}"
      when:
        - execution_environment is not defined
        - _aap_ee_system is defined
        - _aap_ee_system.json.count | int > 0

    - name: Fallback to lab EE default
      ansible.builtin.set_fact:
        execution_environment: "{{ aap_ee_default }}"
      when: execution_environment is not defined

- name: Resolve default Machine credential
  when: credentials is not defined
  block:
    - name: List Machine credentials in organization
      ansible.builtin.uri:
        url: "{{ aap_host }}/api/controller/v2/credentials/?organization={{ _aap_org_id }}&credential_type=1&order_by=name&page_size=1"
        method: GET
        user: "{{ aap_username }}"
        password: "{{ aap_password }}"
        force_basic_auth: true
        validate_certs: "{{ aap_validate_certs | default(false) }}"
        status_code: 200
      register: _aap_cred_lookup
      when: _aap_org_id is defined

    - name: Use first Machine credential in organization
      ansible.builtin.set_fact:
        credentials:
          - "{{ _aap_cred_lookup.json.results[0].name }}"
      when:
        - _aap_cred_lookup is defined
        - _aap_cred_lookup.json.count | int > 0

- name: Show resolved defaults
  ansible.builtin.debug:
    msg:
      organization: "{{ _aap_org }}"
      inventory: "{{ inventory | default('n/a') }}"
      execution_environment: "{{ execution_environment | default('n/a') }}"
      credentials: "{{ credentials | default('n/a') }}"
  when: _show_resolved_defaults | default(true)
```

### `.cursor/skills/aap-admin/playbooks/verify_aap.yml`

```yaml
---
- name: Verify AAP connectivity
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Ping controller API
      ansible.builtin.uri:
        url: "{{ aap_host }}/api/controller/v2/ping/"
        method: GET
        user: "{{ aap_username }}"
        password: "{{ aap_password }}"
        force_basic_auth: true
        validate_certs: "{{ aap_validate_certs | default(true) }}"
        status_code: 200
      register: ping

    - name: Show controller version
      ansible.builtin.uri:
        url: "{{ aap_host }}/api/controller/v2/config/"
        method: GET
        user: "{{ aap_username }}"
        password: "{{ aap_password }}"
        force_basic_auth: true
        validate_certs: "{{ aap_validate_certs | default(true) }}"
        status_code: 200
      register: config

    - name: Connectivity OK
      ansible.builtin.debug:
        msg:
          - "AAP: {{ aap_host }}"
          - "Version: {{ config.json.version | default('n/a') }}"
          - "Ping: {{ ping.json }}"
```

### `.cursor/skills/aap-admin/playbooks/create_organization.yml`

```yaml
---
- name: Create AAP organization
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml

    - name: Create or update organization
      ansible.controller.organization:
        name: "{{ organization_name }}"
        description: "{{ description | default('') }}"
        state: present
        controller_host: "{{ controller_connection.controller_host }}"
        controller_username: "{{ controller_connection.controller_username }}"
        controller_password: "{{ controller_connection.controller_password }}"
        validate_certs: "{{ controller_connection.validate_certs }}"
      vars:
        organization_name: "{{ organization_name | mandatory }}"

    - ansible.builtin.debug:
        msg: "Organization '{{ organization_name }}' created/updated"
```

### `.cursor/skills/aap-admin/playbooks/create_project.yml`

```yaml
---
- name: Create AAP project
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml
    - ansible.builtin.import_tasks: tasks/resolve_aap_defaults.yml

    - name: Create or update project
      ansible.controller.project:
        name: "{{ project_name }}"
        organization: "{{ organization | default(aap_organization_default) }}"
        description: "{{ description | default('') }}"
        scm_type: "{{ scm_type | default('git') }}"
        scm_url: "{{ scm_url if (scm_type | default('git')) != 'manual' else omit }}"
        scm_branch: "{{ scm_branch | default('main') if (scm_type | default('git')) == 'git' else omit }}"
        default_environment: "{{ execution_environment | default(omit) }}"
        update_project: "{{ update_project | default((scm_type | default('git')) != 'manual') }}"
        state: present
        controller_host: "{{ controller_connection.controller_host }}"
        controller_username: "{{ controller_connection.controller_username }}"
        controller_password: "{{ controller_connection.controller_password }}"
        validate_certs: "{{ controller_connection.validate_certs }}"
      vars:
        project_name: "{{ project_name | mandatory }}"

    - name: Project created
      ansible.builtin.debug:
        msg: "Project '{{ project_name }}' in '{{ organization | default(aap_organization_default) }}'"
```

### `.cursor/skills/aap-admin/playbooks/create_inventory.yml`

```yaml
---
- name: Create AAP inventory
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml

    - name: Create or update inventory
      ansible.controller.inventory:
        name: "{{ inventory_name }}"
        organization: "{{ organization | default(aap_organization_default) }}"
        description: "{{ description | default('') }}"
        kind: "{{ kind | default('') }}"
        host_filter: "{{ host_filter | default(omit) }}"
        variables: "{{ variables | default(omit) }}"
        state: present
        controller_host: "{{ controller_connection.controller_host }}"
        controller_username: "{{ controller_connection.controller_username }}"
        controller_password: "{{ controller_connection.controller_password }}"
        validate_certs: "{{ controller_connection.validate_certs }}"
      vars:
        inventory_name: "{{ inventory_name | mandatory }}"

    - ansible.builtin.debug:
        msg: "Inventory '{{ inventory_name }}' in '{{ organization | default(aap_organization_default) }}'"
```

### `.cursor/skills/aap-admin/playbooks/create_host.yml`

```yaml
---
- name: Create AAP host
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml

    - name: Create or update host
      ansible.controller.host:
        name: "{{ host_name }}"
        inventory: "{{ inventory }}"
        description: "{{ description | default('') }}"
        enabled: "{{ enabled | default(true) }}"
        variables: "{{ variables | default(omit) }}"
        state: present
        controller_host: "{{ controller_connection.controller_host }}"
        controller_username: "{{ controller_connection.controller_username }}"
        controller_password: "{{ controller_connection.controller_password }}"
        validate_certs: "{{ controller_connection.validate_certs }}"
      vars:
        host_name: "{{ host_name | mandatory }}"
        inventory: "{{ inventory | mandatory }}"

    - ansible.builtin.debug:
        msg: "Host '{{ host_name }}' no inventory '{{ inventory }}'"
```

### `.cursor/skills/aap-admin/playbooks/create_group.yml`

```yaml
---
- name: Create AAP inventory group
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml

    - name: Create or update group
      ansible.controller.group:
        name: "{{ group_name }}"
        inventory: "{{ inventory }}"
        description: "{{ description | default('') }}"
        parent: "{{ parent | default(omit) }}"
        variables: "{{ variables | default(omit) }}"
        hosts: "{{ group_hosts | default(omit) }}"
        state: present
        controller_host: "{{ controller_connection.controller_host }}"
        controller_username: "{{ controller_connection.controller_username }}"
        controller_password: "{{ controller_connection.controller_password }}"
        validate_certs: "{{ controller_connection.validate_certs }}"
      vars:
        group_name: "{{ group_name | mandatory }}"
        inventory: "{{ inventory | mandatory }}"

    - ansible.builtin.debug:
        msg: "Group '{{ group_name }}' no inventory '{{ inventory }}'"
```

### `.cursor/skills/aap-admin/playbooks/create_inventory_source.yml`

```yaml
---
- name: Create AAP inventory source
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml

    - name: Create or update inventory source
      ansible.controller.inventory_source:
        name: "{{ source_name }}"
        inventory: "{{ inventory }}"
        source: "{{ source }}"
        description: "{{ description | default('') }}"
        credential: "{{ credential | default(omit) }}"
        source_path: "{{ source_path | default(omit) }}"
        source_project: "{{ source_project | default(omit) }}"
        source_vars: "{{ source_vars | default(omit) }}"
        overwrite: "{{ overwrite | default(omit) }}"
        update_on_launch: "{{ update_on_launch | default(omit) }}"
        state: present
        controller_host: "{{ controller_connection.controller_host }}"
        controller_username: "{{ controller_connection.controller_username }}"
        controller_password: "{{ controller_connection.controller_password }}"
        validate_certs: "{{ controller_connection.validate_certs }}"
      vars:
        source_name: "{{ source_name | mandatory }}"
        inventory: "{{ inventory | mandatory }}"
        source: "{{ source | mandatory }}"

    - ansible.builtin.debug:
        msg: "Inventory source '{{ source_name }}' ({{ source }}) in '{{ inventory }}'"
```

### `.cursor/skills/aap-admin/playbooks/create_credential.yml`

```yaml
---
- name: Create AAP credential
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml

    - name: Validate credential inputs
      ansible.builtin.assert:
        that:
          - inputs is defined
          - inputs | length > 0
        fail_msg: >-
          Set inputs with -e, e.g.:
          -e credential_name=host1 -e credential_type=Machine
          -e '{"inputs":{"username":"root","password":"secret"}}'
      vars:
        credential_name: "{{ credential_name | mandatory }}"

    - name: Create or update credential
      ansible.controller.credential:
        name: "{{ credential_name }}"
        organization: "{{ organization | default(aap_organization_default) }}"
        credential_type: "{{ credential_type | default('Machine') }}"
        description: "{{ description | default('') }}"
        inputs: "{{ inputs }}"
        state: present
        controller_host: "{{ controller_connection.controller_host }}"
        controller_username: "{{ controller_connection.controller_username }}"
        controller_password: "{{ controller_connection.controller_password }}"
        validate_certs: "{{ controller_connection.validate_certs }}"
      vars:
        credential_name: "{{ credential_name | mandatory }}"

    - name: Credential created
      ansible.builtin.debug:
        msg: >-
          Credential '{{ credential_name }}'
          ({{ credential_type | default('Machine') }})
          in '{{ organization | default(aap_organization_default) }}'
```

### `.cursor/skills/aap-admin/playbooks/create_job_template.yml`

```yaml
---
- name: Create AAP job template
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml
    - ansible.builtin.import_tasks: tasks/resolve_aap_defaults.yml

    - name: Create or update job template
      ansible.controller.job_template:
        name: "{{ job_template_name }}"
        organization: "{{ organization | default(aap_organization_default) }}"
        inventory: "{{ inventory }}"
        project: "{{ project }}"
        playbook: "{{ playbook }}"
        job_type: "{{ job_type | default('run') }}"
        description: "{{ description | default('') }}"
        credentials: "{{ credentials | default(omit) }}"
        execution_environment: "{{ execution_environment | default(omit) }}"
        extra_vars: "{{ extra_vars | default(omit) }}"
        survey_enabled: "{{ survey_enabled | default(false) }}"
        become_enabled: "{{ become_enabled | default(false) }}"
        limit: "{{ limit | default(omit) }}"
        state: present
        controller_host: "{{ controller_connection.controller_host }}"
        controller_username: "{{ controller_connection.controller_username }}"
        controller_password: "{{ controller_connection.controller_password }}"
        validate_certs: "{{ controller_connection.validate_certs }}"
      vars:
        job_template_name: "{{ job_template_name | mandatory }}"
        project: "{{ project | mandatory }}"
        playbook: "{{ playbook | mandatory }}"

    - name: Job template created
      ansible.builtin.debug:
        msg: >-
          Job template '{{ job_template_name }}':
          {{ project }}/{{ playbook }} → {{ inventory }}
```

### `.cursor/skills/aap-admin/playbooks/create_workflow.yml`

```yaml
---
- name: Create AAP workflow job template
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml
    - ansible.builtin.import_tasks: tasks/resolve_aap_defaults.yml

    - name: Create or update workflow job template
      ansible.controller.workflow_job_template:
        name: "{{ workflow_name }}"
        organization: "{{ organization | default(aap_organization_default) }}"
        description: "{{ description | default('') }}"
        inventory: "{{ inventory | default(omit) }}"
        workflow_nodes: "{{ workflow_nodes | default(omit) }}"
        destroy_current_nodes: "{{ destroy_current_nodes | default(false) }}"
        survey_enabled: "{{ survey_enabled | default(false) }}"
        state: present
        controller_host: "{{ controller_connection.controller_host }}"
        controller_username: "{{ controller_connection.controller_username }}"
        controller_password: "{{ controller_connection.controller_password }}"
        validate_certs: "{{ controller_connection.validate_certs }}"
      vars:
        workflow_name: "{{ workflow_name | mandatory }}"

    - ansible.builtin.debug:
        msg: "Workflow '{{ workflow_name }}' in '{{ organization | default(aap_organization_default) }}'"
```

### `.cursor/skills/aap-admin/playbooks/create_schedule.yml`

```yaml
---
- name: Create AAP schedule
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml

    - name: Create or update schedule
      ansible.controller.schedule:
        name: "{{ schedule_name }}"
        unified_job_template: "{{ unified_job_template }}"
        rrule: "{{ rrule }}"
        organization: "{{ organization | default(aap_organization_default) }}"
        description: "{{ description | default('') }}"
        enabled: "{{ enabled | default(true) }}"
        extra_data: "{{ extra_data | default(omit) }}"
        state: present
        controller_host: "{{ controller_connection.controller_host }}"
        controller_username: "{{ controller_connection.controller_username }}"
        controller_password: "{{ controller_connection.controller_password }}"
        validate_certs: "{{ controller_connection.validate_certs }}"
      vars:
        schedule_name: "{{ schedule_name | mandatory }}"
        unified_job_template: "{{ unified_job_template | mandatory }}"
        rrule: "{{ rrule | mandatory }}"

    - ansible.builtin.debug:
        msg: "Schedule '{{ schedule_name }}' for '{{ unified_job_template }}'"
```

### `.cursor/skills/aap-admin/playbooks/create_execution_environment.yml`

```yaml
---
- name: Create AAP execution environment
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml

    - name: Create or update execution environment
      ansible.controller.execution_environment:
        name: "{{ ee_name }}"
        image: "{{ image }}"
        organization: "{{ organization | default(aap_organization_default) }}"
        description: "{{ description | default('') }}"
        pull: "{{ pull | default(omit) }}"
        state: present
        controller_host: "{{ controller_connection.controller_host }}"
        controller_username: "{{ controller_connection.controller_username }}"
        controller_password: "{{ controller_connection.controller_password }}"
        validate_certs: "{{ controller_connection.validate_certs }}"
      vars:
        ee_name: "{{ ee_name | mandatory }}"
        image: "{{ image | mandatory }}"

    - ansible.builtin.debug:
        msg: "Execution environment '{{ ee_name }}' → {{ image }}"
```

### `.cursor/skills/aap-admin/playbooks/create_team.yml`

```yaml
---
- name: Create AAP team
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml

    - name: Create or update team
      ansible.controller.team:
        name: "{{ team_name }}"
        organization: "{{ organization | default(aap_organization_default) }}"
        description: "{{ description | default('') }}"
        state: present
        controller_host: "{{ controller_connection.controller_host }}"
        controller_username: "{{ controller_connection.controller_username }}"
        controller_password: "{{ controller_connection.controller_password }}"
        validate_certs: "{{ controller_connection.validate_certs }}"
      vars:
        team_name: "{{ team_name | mandatory }}"

    - ansible.builtin.debug:
        msg: "Team '{{ team_name }}' in '{{ organization | default(aap_organization_default) }}'"
```

### `.cursor/skills/aap-admin/playbooks/create_user.yml`

```yaml
---
- name: Create AAP user
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml

    - name: Create or update user
      ansible.controller.user:
        username: "{{ username }}"
        password: "{{ password | default(omit) }}"
        first_name: "{{ first_name | default('') }}"
        last_name: "{{ last_name | default('') }}"
        email: "{{ email | default('') }}"
        organization: "{{ organization | default(aap_organization_default) }}"
        is_superuser: "{{ is_superuser | default(false) }}"
        state: present
        controller_host: "{{ controller_connection.controller_host }}"
        controller_username: "{{ controller_connection.controller_username }}"
        controller_password: "{{ controller_connection.controller_password }}"
        validate_certs: "{{ controller_connection.validate_certs }}"
      vars:
        username: "{{ username | mandatory }}"

    - ansible.builtin.debug:
        msg: "User '{{ username }}' in '{{ organization | default(aap_organization_default) }}'"
```

### `.cursor/skills/aap-admin/playbooks/create_label.yml`

```yaml
---
- name: Create AAP label
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml

    - name: Create or update label
      ansible.controller.label:
        name: "{{ label_name }}"
        organization: "{{ organization | default(aap_organization_default) }}"
        state: present
        controller_host: "{{ controller_connection.controller_host }}"
        controller_username: "{{ controller_connection.controller_username }}"
        controller_password: "{{ controller_connection.controller_password }}"
        validate_certs: "{{ controller_connection.validate_certs }}"
      vars:
        label_name: "{{ label_name | mandatory }}"

    - ansible.builtin.debug:
        msg: "Label '{{ label_name }}' in '{{ organization | default(aap_organization_default) }}'"
```

### `.cursor/skills/aap-admin/playbooks/create_notification_template.yml`

```yaml
---
- name: Create AAP notification template
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml

    - name: Validate notification configuration
      ansible.builtin.assert:
        that:
          - notification_configuration is defined
        fail_msg: >-
          Set notification_configuration with -e, e.g.:
          -e notification_type=webhook
          -e '{"notification_configuration":{"url":"https://example.com/hook"}}'
      vars:
        notification_name: "{{ notification_name | mandatory }}"

    - name: Create or update notification template
      ansible.controller.notification_template:
        name: "{{ notification_name }}"
        organization: "{{ organization | default(aap_organization_default) }}"
        notification_type: "{{ notification_type }}"
        description: "{{ description | default('') }}"
        notification_configuration: "{{ notification_configuration }}"
        messages: "{{ messages | default(omit) }}"
        state: present
        controller_host: "{{ controller_connection.controller_host }}"
        controller_username: "{{ controller_connection.controller_username }}"
        controller_password: "{{ controller_connection.controller_password }}"
        validate_certs: "{{ controller_connection.validate_certs }}"
      vars:
        notification_name: "{{ notification_name | mandatory }}"
        notification_type: "{{ notification_type | mandatory }}"

    - ansible.builtin.debug:
        msg: "Notification '{{ notification_name }}' ({{ notification_type }})"
```

### `.cursor/skills/aap-admin/playbooks/create_instance_group.yml`

```yaml
---
- name: Create AAP instance group
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml

    - name: Create or update instance group
      ansible.controller.instance_group:
        name: "{{ instance_group_name }}"
        instances: "{{ instances | default(omit) }}"
        is_container_group: "{{ is_container_group | default(false) }}"
        credential: "{{ credential | default(omit) }}"
        max_concurrent_jobs: "{{ max_concurrent_jobs | default(omit) }}"
        state: present
        controller_host: "{{ controller_connection.controller_host }}"
        controller_username: "{{ controller_connection.controller_username }}"
        controller_password: "{{ controller_connection.controller_password }}"
        validate_certs: "{{ controller_connection.validate_certs }}"
      vars:
        instance_group_name: "{{ instance_group_name | mandatory }}"

    - ansible.builtin.debug:
        msg: "Instance group '{{ instance_group_name }}'"
```

### `.cursor/skills/aap-admin/vars/aap_defaults.yml`

```yaml
---
# Common controller connection variables (credentials from vars/local.yml)
controller_connection:
  controller_host: "{{ aap_host }}"
  controller_username: "{{ aap_username }}"
  controller_password: "{{ aap_password }}"
  validate_certs: "{{ aap_validate_certs | default(false) }}"

# Lab defaults (fallback when AAP does not set explicitly)
aap_organization_default: Default
aap_inventory_default: Demo Inventory
aap_ee_default: ee-cac-rhel9
aap_ee_system_default: Default execution environment
```

### `.cursor/skills/aap-admin/vars/local.yml.example`

```text
---
# Copy to vars/local.yml and fill in (vars/local.yml is in .gitignore)
aap_host: https://ansible-automation-platform.example.com
aap_username: admin
aap_password: CHANGE_ME
aap_validate_certs: true
```

### `.cursor/skills/aap-admin/vars/examples/organization.yml`

```yaml
---
organization_name: lab-org-02
description: Test organization via aap-skills
```

### `.cursor/skills/aap-admin/vars/examples/project.yml`

```yaml
---
# Exemplo: project Git
project_name: meu-projeto
organization: Default
scm_type: git
scm_url: https://github.com/ansible/ansible-examples.git
scm_branch: master
description: Sample project
```

### `.cursor/skills/aap-admin/vars/examples/inventory.yml`

```yaml
---
inventory_name: aap-skills-inventory
organization: Default
description: Inventory created via aap-skills
```

### `.cursor/skills/aap-admin/vars/examples/host.yml`

```yaml
---
host_name: host-test-01
inventory: aap-skills-inventory
description: Test host
variables:
  ansible_host: 192.168.1.10
```

### `.cursor/skills/aap-admin/vars/examples/group.yml`

```yaml
---
group_name: webservers
inventory: aap-skills-inventory
description: Web group
```

### `.cursor/skills/aap-admin/vars/examples/inventory-source.yml`

```yaml
---
source_name: aap-skills-scm-source
inventory: aap-skills-inventory
source: scm
source_project: Demo Project
source_path: inventories
overwrite: true
update_on_launch: true
```

### `.cursor/skills/aap-admin/vars/examples/credential-machine.yml`

```yaml
---
# Exemplo: credential Machine
credential_name: host-linux-01
organization: Default
credential_type: Machine
description: Credencial SSH para host Linux
inputs:
  username: ansible
  password: CHANGE_ME
```

### `.cursor/skills/aap-admin/vars/examples/job-template.yml`

```yaml
---
# Exemplo: job template
job_template_name: ping-demo
organization: Default
inventory: Demo Inventory
project: Demo Project
playbook: hello_world.yml
job_type: run
description: Sample job template
execution_environment: ee-cac-rhel9
```

### `.cursor/skills/aap-admin/vars/examples/workflow.yml`

```yaml
---
workflow_name: aap-skills-workflow-test
organization: Default
description: Test workflow
inventory: Demo Inventory
workflow_nodes:
  - identifier: node1
    unified_job_template:
      name: aap-skills-test-hello
      type: job_template
```

### `.cursor/skills/aap-admin/vars/examples/schedule.yml`

```yaml
---
schedule_name: aap-skills-weekly
unified_job_template: aap-skills-test-hello
organization: Default
rrule: "DTSTART:20260614T120000Z RRULE:FREQ=WEEKLY;INTERVAL=1;COUNT=10"
```

### `.cursor/skills/aap-admin/vars/examples/execution-environment.yml`

```yaml
---
ee_name: aap-skills-ee-test
organization: Default
image: quay.io/lagomes/ee-cac-rhel9:v7
description: Test EE via aap-skills
```

### `.cursor/skills/aap-admin/vars/examples/team.yml`

```yaml
---
team_name: aap-skills-team
organization: Default
description: Test team
```

### `.cursor/skills/aap-admin/vars/examples/label.yml`

```yaml
---
label_name: aap-skills-label
organization: Default
```

### `.cursor/skills/aap-admin/vars/examples/notification-template.yml`

```yaml
---
notification_name: aap-skills-webhook-test
organization: Default
notification_type: webhook
notification_configuration:
  url: https://httpbin.org/post
  http_method: POST
  headers: {}
```

### `.cursor/skills/aap-operate/SKILL.md`

```markdown
---
name: aap-operate
description: >-
  Operates existing resources on Ansible Automation Platform (AAP) 2.6: launch
  jobs, sync SCM projects, and list resources. Uses ansible-navigator and EE
  quay.io/lagomes/ee-cac-rhel9:v7. Use when the user asks to run, launch, or
  execute a job template, sync a project, or list organizations, projects,
  job templates, jobs, or inventories on AAP.
---

# AAP Operate (2.6)

Skill directory is next to this `SKILL.md` (also `~/.cursor/skills/aap-operate/`). Complements `aap-admin` (creation) with **day-to-day operations**.

**Never** remove resources (`state: absent`, API DELETE) without explicit human confirmation — see `.cursor/rules/aap-safety.mdc`.

## Scripts

| Action | Script | Required |
|--------|--------|----------|
| Launch job | `launch-job.sh` | `job_template_name` |
| Sync project | `sync-project.sh` | `project_name` |
| List resources | `list-resources.sh` | `resource_type` |

Credentials: `vars/local.yml` or shared from `../aap-admin/vars/local.yml`.

## Usage

```bash
# From this skill directory
./scripts/launch-job.sh -e @vars/examples/launch-job.yml
./scripts/sync-project.sh -e project_name=aap_backup_automation -e organization="teste cursor"
./scripts/list-resources.sh -e resource_type=job_templates -e organization="teste cursor"

# From aap-skills repo root
./operate launch-job.sh -e @.cursor/skills/aap-operate/vars/examples/launch-job.yml
```

Values with spaces → JSON or `-e @vars/examples/...` (paths relative to the skill directory).

## launch-job

```bash
./scripts/launch-job.sh \
  -e job_template_name=backup-aap \
  -e organization="teste cursor" \
  -e wait=true
```

| Variable | Default | Description |
|----------|---------|-------------|
| `job_template_name` | — | Job template name |
| `organization` | `Default` | Organization |
| `inventory` | omit | Inventory override |
| `credentials` | omit | Credential list |
| `extra_vars` | omit | Extra variables |
| `limit` | omit | Host limit |
| `wait` | `true` | Wait for completion |
| `timeout` | module default | Timeout in seconds |

## sync-project

```bash
./scripts/sync-project.sh \
  -e '{"project_name":"aap_backup_automation","organization":"teste cursor"}'
```

| Variable | Default | Description |
|----------|---------|-------------|
| `project_name` | — | Project name |
| `organization` | `Default` | Organization |
| `wait` | `true` | Wait for sync |
| `timeout` | `300` | Timeout in seconds |

## list-resources

`resource_type`: `organizations`, `projects`, `job_templates`, `jobs`, `inventories`

```bash
./scripts/list-resources.sh -e resource_type=jobs -e '{"api_query":{"status":"failed"}}'
./scripts/list-resources.sh -e resource_type=projects -e organization="teste cursor"
```

| Variable | Default | Description |
|----------|---------|-------------|
| `resource_type` | — | Resource type |
| `organization` | — | Filter by organization |
| `api_query` | — | Extra API filters (e.g. `status: failed`) |
| `page_size` | `25` | Results per page |
| `order_by` | `name` | Sort order |

## EE

`quay.io/lagomes/ee-cac-rhel9:v7` via `ansible-navigator.yml`.
```

### `.cursor/skills/aap-operate/ansible-navigator.yml`

```yaml
---
ansible-navigator:
  ansible:
    playbook:
      path: ./playbooks
  execution-environment:
    container-engine: auto
    enabled: true
    image: quay.io/lagomes/ee-cac-rhel9:v7
    pull:
      policy: missing
    volume-mounts:
      - src: .
        dest: /runner/project
        options: Z
  logging:
    level: warning
  mode: stdout
  playbook-artifact:
    enable: true
    save-as: artifacts/{playbook_name}-{time_stamp}.json
```

### `.cursor/skills/aap-operate/scripts/lib/aap-run.sh`

```bash
#!/usr/bin/env bash
# Helper: run playbook with ansible-navigator + local AAP vars
set -euo pipefail

aap_run() {
  local playbook="$1"
  shift
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
  local vars_file="${root}/vars/local.yml"
  local shared_vars="${root}/../aap-admin/vars/local.yml"

  if [[ ! -f "${vars_file}" ]]; then
    if [[ -f "${shared_vars}" ]]; then
      cp "${shared_vars}" "${vars_file}"
    else
      echo "Error: credentials not found." >&2
      echo "Configure ${root}/vars/local.yml or ../aap-admin/vars/local.yml" >&2
      exit 1
    fi
  fi

  cd "${root}"
  ansible-navigator run "${root}/${playbook}" \
    --mode stdout \
    -e "@vars/local.yml" \
    "$@"
}
```

### `.cursor/skills/aap-operate/scripts/launch-job.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/launch_job.yml "$@"
```

### `.cursor/skills/aap-operate/scripts/sync-project.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/sync_project.yml "$@"
```

### `.cursor/skills/aap-operate/scripts/list-resources.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/aap-run.sh"
aap_run playbooks/list_resources.yml "$@"
```

### `.cursor/skills/aap-operate/playbooks/tasks/validate_connection.yml`

```yaml
---
- name: Validate controller credentials
  ansible.builtin.assert:
    that:
      - aap_host is defined
      - aap_username is defined
      - aap_password is defined
    fail_msg: "Missing credentials. Configure vars/local.yml"
```

### `.cursor/skills/aap-operate/playbooks/launch_job.yml`

```yaml
---
- name: Launch AAP job
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml

    - name: Launch job template
      ansible.controller.job_launch:
        job_template: "{{ job_template_name }}"
        organization: "{{ organization | default(aap_organization_default) }}"
        inventory: "{{ inventory | default(omit) }}"
        credentials: "{{ credentials | default(omit) }}"
        extra_vars: "{{ extra_vars | default(omit) }}"
        limit: "{{ limit | default(omit) }}"
        job_type: "{{ job_type | default(omit) }}"
        wait: "{{ wait | default(true) }}"
        timeout: "{{ timeout | default(omit) }}"
        controller_host: "{{ controller_connection.controller_host }}"
        controller_username: "{{ controller_connection.controller_username }}"
        controller_password: "{{ controller_connection.controller_password }}"
        validate_certs: "{{ controller_connection.validate_certs }}"
      register: launched_job
      vars:
        job_template_name: "{{ job_template_name | mandatory }}"

    - name: Job launched
      ansible.builtin.debug:
        msg:
          - "Job ID: {{ launched_job.id }}"
          - "Status: {{ launched_job.status }}"
          - "Template: {{ job_template_name }}"
```

### `.cursor/skills/aap-operate/playbooks/sync_project.yml`

```yaml
---
- name: Sync AAP project (SCM update)
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml

    - name: Update project from SCM
      ansible.controller.project_update:
        name: "{{ project_name }}"
        organization: "{{ organization | default(aap_organization_default) }}"
        wait: "{{ wait | default(true) }}"
        timeout: "{{ timeout | default(300) }}"
        controller_host: "{{ controller_connection.controller_host }}"
        controller_username: "{{ controller_connection.controller_username }}"
        controller_password: "{{ controller_connection.controller_password }}"
        validate_certs: "{{ controller_connection.validate_certs }}"
      register: project_sync
      vars:
        project_name: "{{ project_name | mandatory }}"

    - name: Project sync result
      ansible.builtin.debug:
        msg:
          - "Project: {{ project_name }}"
          - "Status: {{ project_sync.status | default('updated') }}"
          - "Job ID: {{ project_sync.id | default('n/a') }}"
```

### `.cursor/skills/aap-operate/playbooks/list_resources.yml`

```yaml
---
- name: List AAP resources
  hosts: localhost
  connection: local
  gather_facts: false
  vars_files:
    - ../vars/aap_defaults.yml
  vars:
    _resource_endpoints:
      organizations: /api/controller/v2/organizations/
      projects: /api/controller/v2/projects/
      job_templates: /api/controller/v2/job_templates/
      jobs: /api/controller/v2/jobs/
      inventories: /api/controller/v2/inventories/
  tasks:
    - ansible.builtin.import_tasks: tasks/validate_connection.yml

    - name: Validate resource type
      ansible.builtin.assert:
        that:
          - resource_type in _resource_endpoints
        fail_msg: >-
          Invalid resource_type. Use:
          organizations, projects, job_templates, jobs, inventories
      vars:
        resource_type: "{{ resource_type | mandatory }}"

    - name: Resolve organization ID for filter
      when: organization is defined
      block:
        - name: Lookup organizations
          ansible.builtin.uri:
            url: "{{ aap_host }}/api/controller/v2/organizations/"
            method: GET
            user: "{{ aap_username }}"
            password: "{{ aap_password }}"
            force_basic_auth: true
            validate_certs: "{{ aap_validate_certs | default(false) }}"
            status_code: 200
          register: _orgs

        - name: Set organization ID
          ansible.builtin.set_fact:
            _org_id: "{{ (_orgs.json.results | selectattr('name', 'equalto', organization) | list | first).id }}"
          when: _orgs.json.results | selectattr('name', 'equalto', organization) | list | length > 0

    - name: Build API URL
      ansible.builtin.set_fact:
        _api_url: >-
          {{ aap_host }}{{ _resource_endpoints[resource_type] }}?page_size={{ page_size | default(25) }}&order_by={{ order_by | default('name') }}
          {%- if _org_id is defined -%}&organization={{ _org_id }}{%- endif -%}
          {%- if api_query is defined -%}
          {%- for k, v in api_query.items() -%}&{{ k }}={{ v | urlencode }}{%- endfor -%}
          {%- endif -%}

    - name: Fetch resources
      ansible.builtin.uri:
        url: "{{ _api_url }}"
        method: GET
        user: "{{ aap_username }}"
        password: "{{ aap_password }}"
        force_basic_auth: true
        validate_certs: "{{ aap_validate_certs | default(false) }}"
        status_code: 200
      register: _resource_list

    - name: Show resources
      ansible.builtin.debug:
        msg: >-
          id={{ item.id }} | name={{ item.name | default('n/a') }}
          {%- if item.status is defined %} | status={{ item.status }}{%- endif -%}
          {%- if item.summary_fields.organization is defined %} | org={{ item.summary_fields.organization.name }}{%- endif -%}
      loop: "{{ _resource_list.json.results }}"
      loop_control:
        label: "{{ item.id }}"

    - name: Total count
      ansible.builtin.debug:
        msg: "{{ resource_type }}: {{ _resource_list.json.count }} found"
```

### `.cursor/skills/aap-operate/vars/aap_defaults.yml`

```yaml
---
controller_connection:
  controller_host: "{{ aap_host }}"
  controller_username: "{{ aap_username }}"
  controller_password: "{{ aap_password }}"
  validate_certs: "{{ aap_validate_certs | default(false) }}"

aap_organization_default: Default
```

### `.cursor/skills/aap-operate/vars/local.yml.example`

```text
---
# Credentials — copy from ../aap-admin/vars/local.yml.example if needed
aap_host: https://ansible-automation-platform.example.com
aap_username: admin
aap_password: CHANGE_ME
aap_validate_certs: false
```

### `.cursor/skills/aap-operate/vars/examples/launch-job.yml`

```yaml
---
job_template_name: backup-aap
organization: teste cursor
```

### `.cursor/skills/aap-operate/vars/examples/sync-project.yml`

```yaml
---
project_name: aap_backup_automation
organization: teste cursor
```

### `.cursor/skills/aap-operate/vars/examples/list-job-templates.yml`

```yaml
---
resource_type: job_templates
organization: teste cursor
```

### `deployments/README.md`

```markdown
# Deployments

Versioned AAP resource stacks — environment configuration, separate from skill logic.

```
deployments/
├── README.md
├── teste-cursor/          # org "teste cursor" — backup automation
├── crucible/              # org "crucible" — OpenShift Crucible playbooks
│   ├── README.md
│   ├── 01-organization.yml
│   └── ...
└── <another-stack>/       # add more as needed
```

## Why here (repo root)?

| Location | Role |
|----------|------|
| `.cursor/skills/aap-admin/` | **How** to create resources (scripts, playbooks) |
| `deployments/` | **What** to deploy per environment/org/stack |
| `vars/examples/` (in skill) | Generic templates to copy |

Deployments can grow without bloating the skill. Multiple stacks (labs, customers, DR) live side by side.

## Apply a stack

```bash
./apply-deployment teste-cursor
```

## Apply one resource

Use an absolute path (skill scripts run from inside `aap-admin`):

```bash
./aap create-project.sh -e "@$(pwd)/deployments/teste-cursor/02-project-aap-backup.yml"
```

## Naming convention

`NN-<resource>-<name>.yml` — number sets order; resource prefix maps to `create-<resource>.sh`.

Supported prefixes: `organization`, `project`, `inventory`, `host`, `group`, `job-template`, `credential`, `workflow`, `schedule`, `label`, `team`, `execution-environment`, `notification-template`, `inventory-source`, `instance-group`.

## Add a new deployment

```bash
mkdir deployments/my-stack
cp deployments/teste-cursor/01-organization.yml deployments/my-stack/
# edit and add numbered files...
./apply-deployment my-stack
```
```

### `deployments/teste-cursor/README.md`

```markdown
# Deployment: teste-cursor

Lab stack for organization **teste cursor** — AAP backup automation.

| Resource | Name |
|----------|------|
| Organization | `teste cursor` |
| Project | `aap_backup_automation` |
| Inventory | `backup-inventory` |
| Group | `automationcontroller` |
| Job templates | `backup-aap`, `configure-backup-project` |

## Apply entire stack

From repo root:

```bash
./apply-deployment teste-cursor
```

## Apply a single resource

```bash
./aap create-project.sh -e "@$(pwd)/deployments/teste-cursor/02-project-aap-backup.yml"
```

## File order

Files are numbered for dependency order (org → project → inventory → hosts → group → job templates).

## Notes

- Idempotent: safe to re-run (`state: present` on all resources).
- Credentials are not included — add Machine credentials manually or extend with a new `NN-credential-*.yml` file.
- `backup-aap` requires a Machine credential on the controller nodes before launch.
```

### `deployments/teste-cursor/01-organization.yml`

```yaml
---
organization_name: teste cursor
description: Organization created via Cursor agent
```

### `deployments/teste-cursor/02-project-aap-backup.yml`

```yaml
---
project_name: aap_backup_automation
organization: teste cursor
scm_type: git
scm_url: https://github.com/laurobmb/aap_backup_automation
scm_branch: main
description: Backup automation AAP - https://github.com/laurobmb/aap_backup_automation
```

### `deployments/teste-cursor/03-inventory-backup.yml`

```yaml
---
inventory_name: backup-inventory
organization: teste cursor
description: Inventory for AAP backup jobs
```

### `deployments/teste-cursor/04-host-controller-01.yml`

```yaml
---
host_name: ansible-automation-platform-01.lagomes.rhbr-lab.com
inventory: backup-inventory
variables:
  ansible_host: ansible-automation-platform-01.lagomes.rhbr-lab.com
```

### `deployments/teste-cursor/05-host-controller-02.yml`

```yaml
---
host_name: ansible-automation-platform-02.lagomes.rhbr-lab.com
inventory: backup-inventory
variables:
  ansible_host: ansible-automation-platform-02.lagomes.rhbr-lab.com
```

### `deployments/teste-cursor/06-host-controller-03.yml`

```yaml
---
host_name: ansible-automation-platform-03.lagomes.rhbr-lab.com
inventory: backup-inventory
variables:
  ansible_host: ansible-automation-platform-03.lagomes.rhbr-lab.com
```

### `deployments/teste-cursor/07-host-localhost.yml`

```yaml
---
host_name: localhost
inventory: backup-inventory
variables:
  ansible_connection: local
```

### `deployments/teste-cursor/08-group-automationcontroller.yml`

```yaml
---
group_name: automationcontroller
inventory: backup-inventory
description: Automation Controller cluster nodes
group_hosts:
  - ansible-automation-platform-01.lagomes.rhbr-lab.com
  - ansible-automation-platform-02.lagomes.rhbr-lab.com
  - ansible-automation-platform-03.lagomes.rhbr-lab.com
```

### `deployments/teste-cursor/09-job-template-backup-aap.yml`

```yaml
---
job_template_name: backup-aap
organization: teste cursor
inventory: backup-inventory
project: aap_backup_automation
playbook: main-backup.yml
execution_environment: ee-cac-rhel9
limit: automationcontroller
become_enabled: true
description: Run AAP backup against automationcontroller nodes
```

### `deployments/teste-cursor/10-job-template-configure-backup.yml`

```yaml
---
job_template_name: configure-backup-project
organization: teste cursor
inventory: backup-inventory
project: aap_backup_automation
playbook: main-configure-backup-project.yml
execution_environment: ee-cac-rhel9
description: Configure backup project settings on localhost
```

### `deployments/crucible/README.md`

```markdown
# Deployment: crucible

Stack for organization **crucible** — [laurobmb/crucible](https://github.com/laurobmb/crucible) playbooks.

| Resource | Name |
|----------|------|
| Organization | `crucible` |
| Project | `crucible` |

## Apply entire stack

```bash
./apply-deployment crucible
```

## Apply a single resource

```bash
./aap create-project.sh -e "@$(pwd)/deployments/crucible/02-project-crucible.yml"
```
```

### `deployments/crucible/01-organization.yml`

```yaml
---
organization_name: crucible
description: Crucible OpenShift deployment organization
```

### `deployments/crucible/02-project-crucible.yml`

```yaml
---
project_name: crucible
organization: crucible
scm_type: git
scm_url: https://github.com/laurobmb/crucible.git
scm_branch: main
description: Crucible - OpenShift management cluster seed playbooks
```

---

*End of canonical source. Rebuild from section 17 using the files in section 18.*
