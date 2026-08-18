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
