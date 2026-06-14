# aap-skills — Technical Specification

**Version:** 1.0  
**Platform target:** Red Hat Ansible Automation Platform (AAP) 2.6  
**Repository:** https://github.com/laurobmb/aap-skills  
**Branch:** `v2.6`  
**Language:** American English (skills, rules, playbooks, documentation)

---

## 1. Executive Summary

**aap-skills** is a Cursor AI workspace that lets AI agents safely create and operate Ansible Automation Platform resources through versioned scripts and playbooks. Instead of ad hoc API calls or manual UI navigation, the agent runs standardized shell scripts that invoke **ansible-navigator** inside a fixed **Execution Environment (EE)** container.

The project separates concerns into two skills:

| Skill | Purpose |
|-------|---------|
| **aap-admin** | Create and configure AAP resources (organizations, projects, job templates, etc.) |
| **aap-operate** | Day-to-day operations (launch jobs, sync SCM projects, list resources) |

Behavioral guardrails live in **Cursor rules** (`.cursor/rules/`) to prevent credential leaks, unauthorized deletions, and inconsistent defaults.

---

## 2. Problem Statement

Managing AAP involves many interconnected objects across organizations. AI agents without structured tooling tend to:

- Invent API parameters or use inconsistent naming
- Install Ansible collections on the host ad hoc
- Apply destructive changes (`state: absent`, HTTP DELETE) without operator awareness
- Hardcode credentials in chat or commits

**aap-skills** solves this by providing:

1. One script per resource/operation
2. Container-isolated execution via a known EE image
3. Explicit rules for security and defaults
4. Git-versioned automation patterns

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  Human operator / Cursor AI agent                               │
│  Natural language: "Create a job template for backup-aap"       │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  Repo shortcuts: ./aap  |  ./operate                            │
│  Shell scripts in .cursor/skills/<skill>/scripts/               │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  scripts/lib/aap-run.sh                                         │
│  - Loads vars/local.yml (credentials)                           │
│  - cd to skill root                                             │
│  - ansible-navigator run playbooks/<name>.yml -e @vars/local.yml│
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  ansible-navigator (host)                                       │
│  - Reads ansible-navigator.yml                                  │
│  - Spawns podman/docker container                               │
│  - Mounts skill directory → /runner/project                     │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  Execution Environment: quay.io/lagomes/ee-cac-rhel9:v7         │
│  - ansible.controller collection                                │
│  - infra.aap_configuration (reference)                            │
│  - Playbook runs against localhost → AAP Controller API         │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  AAP Controller API                                             │
│  https://ansible-automation-platform.lagomes.rhbr-lab.com       │
└─────────────────────────────────────────────────────────────────┘
```

### Design principles

- **No local collections required** on the operator workstation
- **Idempotent create/update** only (`state: present`); no delete automation
- **Credentials never in git** — `vars/local.yml` is gitignored
- **One playbook per operation** for traceability and testing

---

## 4. Technology Stack

| Layer | Technology |
|-------|------------|
| AI IDE | Cursor with Agent Skills and Project Rules |
| Automation runner | ansible-navigator 26.x |
| Container engine | podman (auto-detected) or docker |
| Execution Environment | `quay.io/lagomes/ee-cac-rhel9:v7` (~913 MB) |
| Ansible collection (primary) | `ansible.controller` 4.7.9 |
| Config-as-code (reference) | `infra.aap_configuration` 4.2.1 |
| AAP version (lab) | Controller 4.7.11 / AAP 2.6 |
| API | AAP Controller REST API v2 |
| Auth | HTTP Basic (username/password from `vars/local.yml`) |
| VCS | Git / GitHub (`laurobmb/aap-skills`) |

### Collections inside the EE image

| Collection | Version | Role in project |
|------------|---------|-----------------|
| `ansible.controller` | 4.7.9 | All create/operate playbooks |
| `infra.aap_configuration` | 4.2.1 | Reference for config-as-code patterns |
| `infra.aap_configuration_extended` | 4.2.2 | Extensions (export diff, etc.) |
| `ansible.platform` | 2.6.x | Platform integration |
| `ansible.eda` | 2.11.0 | Available; not used in scripts yet |
| `ansible.hub` | 1.0.4 | Available; not used in scripts yet |

---

## 5. Repository Structure

```
aap-skills/
├── README.md                    # User-facing overview
├── spec.md                      # This technical specification
├── aap                            # Shortcut → aap-admin scripts
├── operate                        # Shortcut → aap-operate scripts
├── .gitignore
└── .cursor/
    ├── rules/
    │   ├── aap-skills-git.mdc   # Branch v2.6, commit policy
    │   ├── aap-defaults.mdc     # Auto-resolve inventory/EE/credential
    │   └── aap-safety.mdc       # No delete without human confirmation
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

---

## 6. ansible-navigator Configuration

Both skills use identical EE settings (`ansible-navigator.yml`):

```yaml
execution-environment:
  enabled: true
  image: quay.io/lagomes/ee-cac-rhel9:v7
  container-engine: auto
  pull:
    policy: missing
  volume-mounts:
    - src: .
      dest: /runner/project
      options: Z
mode: stdout
playbook-artifact:
  enable: true
  save-as: artifacts/{playbook_name}-{time_stamp}.json
```

**Key points:**

- `src: .` mounts the **skill directory** (not the full repo root)
- Playbooks must live inside the skill folder to be visible in the container
- `--mode stdout` is used for CI/agent-friendly non-interactive output
- Run artifacts are saved under `artifacts/` (gitignored)

---

## 7. Credential Management

### File: `vars/local.yml` (gitignored)

```yaml
aap_host: https://ansible-automation-platform.lagomes.rhbr-lab.com
aap_username: admin
aap_password: <secret>
aap_validate_certs: false
```

### Loading mechanism (`aap-run.sh`)

1. **aap-admin:** requires `vars/local.yml` inside the skill
2. **aap-operate:** uses local `vars/local.yml` OR copies from `../aap-admin/vars/local.yml` if missing

### Mapping to ansible.controller modules

| local.yml variable | Module parameter |
|--------------------|------------------|
| `aap_host` | `controller_host` |
| `aap_username` | `controller_username` |
| `aap_password` | `controller_password` |
| `aap_validate_certs` | `validate_certs` |

Defined centrally in `vars/aap_defaults.yml` as `controller_connection` dict.

---

## 8. Skill: aap-admin (Resource Creation)

**Shortcut:** `./aap <script>.sh [ansible extra vars]`  
**Skill path:** `.cursor/skills/aap-admin/`

### 8.1 Scripts and Ansible modules

| Script | Playbook | ansible.controller module |
|--------|----------|----------------------------|
| `verify-aap.sh` | `verify_aap.yml` | `ansible.builtin.uri` (ping/config) |
| `create-organization.sh` | `create_organization.yml` | `organization` |
| `create-project.sh` | `create_project.yml` | `project` |
| `create-inventory.sh` | `create_inventory.yml` | `inventory` |
| `create-host.sh` | `create_host.yml` | `host` |
| `create-group.sh` | `create_group.yml` | `group` |
| `create-inventory-source.sh` | `create_inventory_source.yml` | `inventory_source` |
| `create-credential.sh` | `create_credential.yml` | `credential` |
| `create-job-template.sh` | `create_job_template.yml` | `job_template` |
| `create-workflow.sh` | `create_workflow.yml` | `workflow_job_template` |
| `create-schedule.sh` | `create_schedule.yml` | `schedule` |
| `create-execution-environment.sh` | `create_execution_environment.yml` | `execution_environment` |
| `create-team.sh` | `create_team.yml` | `team` |
| `create-user.sh` | `create_user.yml` | `user` |
| `create-label.sh` | `create_label.yml` | `label` |
| `create-notification-template.sh` | `create_notification_template.yml` | `notification_template` |
| `create-instance-group.sh` | `create_instance_group.yml` | `instance_group` |

### 8.2 Shared playbook tasks

| Task file | Purpose |
|-----------|---------|
| `tasks/validate_connection.yml` | Assert `aap_host`, `aap_username`, `aap_password` exist |
| `tasks/resolve_aap_defaults.yml` | Auto-resolve inventory, EE, credential when omitted |

### 8.3 Automatic default resolution

Used by `create_job_template.yml`, `create_workflow.yml`, and `create_project.yml`.

**Resolution order:**

| Resource | Priority |
|----------|----------|
| **Inventory** | 1) First inventory in target org (API) → 2) `Demo Inventory` fallback |
| **Execution environment** | 1) Org `default_environment` → 2) `Default execution environment` → 3) `ee-cac-rhel9` |
| **Credential** | 1) First Machine credential in org (`credential_type=1`) → 2) omit if none |

Organization default when not specified: `Default` (overridable via `-e organization="..."`).

### 8.4 Lab defaults (`vars/aap_defaults.yml`)

```yaml
aap_organization_default: Default
aap_inventory_default: Demo Inventory
aap_ee_default: ee-cac-rhel9
aap_ee_system_default: Default execution environment
```

### 8.5 Extra variables conventions

- Simple values: `-e project_name=my-project`
- Values with spaces: JSON `-e '{"inventory":"Demo Inventory","project":"Demo Project"}'`
- File-based: `-e @vars/examples/job-template.yml` (path relative to skill directory)

---

## 9. Skill: aap-operate (Day-to-Day Operations)

**Shortcut:** `./operate <script>.sh [ansible extra vars]`  
**Skill path:** `.cursor/skills/aap-operate/`

| Script | Playbook | Mechanism |
|--------|----------|-----------|
| `launch-job.sh` | `launch_job.yml` | `ansible.controller.job_launch` |
| `sync-project.sh` | `sync_project.yml` | `ansible.controller.project_update` |
| `list-resources.sh` | `list_resources.yml` | `ansible.builtin.uri` (Controller API GET) |

### 9.1 launch-job

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `job_template_name` | Yes | — | Job template to launch |
| `organization` | No | `Default` | Organization scope |
| `inventory` | No | omit | Override inventory |
| `credentials` | No | omit | Credential list |
| `extra_vars` | No | omit | Extra variables |
| `limit` | No | omit | Host limit |
| `wait` | No | `true` | Wait for job completion |
| `timeout` | No | module default | Timeout in seconds |

### 9.2 sync-project

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `project_name` | Yes | — | Project to sync from SCM |
| `organization` | No | `Default` | Organization scope |
| `wait` | No | `true` | Wait for project update |
| `timeout` | No | `300` | Timeout in seconds |

### 9.3 list-resources

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `resource_type` | Yes | — | `organizations`, `projects`, `job_templates`, `jobs`, `inventories` |
| `organization` | No | — | Filter by organization name |
| `api_query` | No | — | Extra API query params (e.g. `status: failed`) |
| `page_size` | No | `25` | Results per page |
| `order_by` | No | `name` | Sort field |

**API endpoints used:**

```
GET /api/controller/v2/organizations/
GET /api/controller/v2/projects/
GET /api/controller/v2/job_templates/
GET /api/controller/v2/jobs/
GET /api/controller/v2/inventories/
```

---

## 10. Cursor Rules (Agent Guardrails)

| Rule file | alwaysApply | Purpose |
|-----------|-------------|---------|
| `aap-skills-git.mdc` | Yes | Work on branch `v2.6`; credential commit ban |
| `aap-defaults.mdc` | Yes | Use AAP defaults when inventory/EE/credential not specified |
| `aap-safety.mdc` | Yes | **Block all deletions** without explicit human confirmation |

### Deletion policy (aap-safety)

**Forbidden without human confirmation:**

- `state: absent` on any `ansible.controller.*` module
- HTTP DELETE to Controller API
- Delete/remove scripts or ad hoc `curl -X DELETE`

**Allowed without extra confirmation:**

- `state: present` (create/update)
- List resources (GET)
- Launch jobs
- Sync projects
- Verify connectivity

---

## 11. Lab Environment (Reference Deployment)

| Item | Value |
|------|-------|
| Controller URL | `https://ansible-automation-platform.lagomes.rhbr-lab.com` |
| Controller version | 4.7.11 |
| AAP release | 2.6 |
| HA | Yes — 3 hybrid nodes |
| Nodes | `ansible-automation-platform-01/02/03.lagomes.rhbr-lab.com` |
| Default organization | `Default` |
| Test organization | `teste cursor` (ID: 4) |

### Example resources deployed via aap-skills

| Resource | Name | Organization |
|----------|------|--------------|
| Organization | `teste cursor` | — |
| Project | `aap_backup_automation` | teste cursor |
| SCM URL | `https://github.com/laurobmb/aap_backup_automation` | — |
| Inventory | `backup-inventory` | teste cursor |
| Group | `automationcontroller` | backup-inventory |
| Job template | `backup-aap` | teste cursor |
| Job template | `configure-backup-project` | teste cursor |
| Execution environment | `ee-cac-rhel9` | quay.io/lagomes/ee-cac-rhel9:v6/v7 |

### Backup automation project playbooks (from Git)

- `main-backup.yml` — targets `automationcontroller` group, uses `infra.aap_utilities.aap_backup`
- `main-configure-backup-project.yml` — runs on `localhost`, configures backup project

---

## 12. Agent Workflow (End-to-End Example)

**User request:** "Create a job template called backup-aap in org teste cursor"

1. Agent loads skill **aap-admin** and rule **aap-defaults**
2. Agent identifies script: `create-job-template.sh`
3. Agent collects missing params: `project`, `playbook` (asks user if needed)
4. Agent runs:

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

5. Playbook resolves defaults (inventory, EE) via `resolve_aap_defaults.yml`
6. `ansible.controller.job_template` creates/updates resource via API
7. Agent confirms `changed`/`ok` in playbook output

**User request:** "Run the backup job"

```bash
./operate launch-job.sh -e '{"job_template_name":"backup-aap","organization":"teste cursor"}'
```

---

## 13. Prerequisites

### Host workstation

| Requirement | Notes |
|-------------|-------|
| `ansible-navigator` | Tested with 26.1.3 |
| `podman` or `docker` | EE container runtime |
| Network access | To Controller URL and `quay.io` |
| Git | Clone `aap-skills` repo |
| Cursor | For agent skills and rules |

### NOT required on host

- `ansible-core` / `ansible-playbook`
- `ansible-galaxy collection install`
- Python dependencies for AAP modules

---

## 14. Security Model

| Control | Implementation |
|---------|----------------|
| Credential storage | `vars/local.yml` gitignored |
| No delete automation | `aap-safety.mdc` rule |
| Least privilege (recommended) | Dedicated AAP service account |
| TLS validation | `aap_validate_certs: false` in lab (self-signed) |
| Job execution risk | `launch-job.sh` runs real automation on real hosts |
| Audit trail | ansible-navigator artifacts + AAP activity stream |
| Chat exposure | Passwords must not be pasted in agent conversations |

---

## 15. Limitations and Out of Scope

**Not implemented (by design):**

- Delete/remove resources (`state: absent`)
- RBAC role assignment scripts
- EDA (Event-Driven Ansible) resource management
- Automation Hub collection publishing
- Bulk config-as-code via `infra.aap_configuration` roles
- `aap-diagnose` health-check skill (discussed, not built)

**Known constraints:**

- Values with spaces require JSON extra vars or vars files
- `-e @path` for vars files must be relative to skill directory when using navigator
- `aap-operate` copies credentials from `aap-admin` if local file missing
- Manual projects skip SCM `update_project` to avoid API errors

---

## 16. Related Personal Skills (Cursor ~/.cursor/skills)

The operator also maintains reference skills for AAP 2.6 documentation (not in this repo):

| Skill | Focus |
|-------|-------|
| `aap-26-operacao` | RBAC, auth, hardening, day-2 ops |
| `aap-26-controller-uso` | Job templates, workflows, API |
| `aap-26-automacoes` | EDA, CaC, EE builder |
| `aap-26-dev-tools` | ansible-navigator, Lightspeed |
| `aap-26-integracoes` | Vault, Hub, Terraform |
| `aap-26-instalacao` | Installation architecture |
| `aap-26-mesh-performance` | Automation Mesh, tuning |
| Others | Dashboard, analytics, self-service, developer hub |

**aap-skills** provides **executable automation**; personal skills provide **knowledge/reference**.

---

## 17. Version History

| Commit | Description |
|--------|-------------|
| `39e189f` | Initial aap-admin skill with navigator-based resource automation |
| `1f132ad` | aap-operate skill, safety rules, README introduction |
| `e9bcfb9` | Full translation to American English |

---

## 18. Quick Reference Commands

```bash
# Setup
cp .cursor/skills/aap-admin/vars/local.yml.example \
   .cursor/skills/aap-admin/vars/local.yml

# Verify connectivity
./aap verify-aap.sh

# Create job template
./aap create-job-template.sh \
  -e job_template_name=my-job \
  -e '{"inventory":"Demo Inventory","project":"Demo Project","playbook":"hello_world.yml"}'

# List job templates
./operate list-resources.sh -e resource_type=job_templates -e organization="teste cursor"

# Sync project from Git
./operate sync-project.sh -e project_name=aap_backup_automation -e organization="teste cursor"

# Launch job
./operate launch-job.sh -e job_template_name=backup-aap -e organization="teste cursor"
```

---

*Document generated for technical reference and NotebookLM presentation authoring.*
