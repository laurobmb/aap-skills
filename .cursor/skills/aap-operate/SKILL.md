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

Skill at `.cursor/skills/aap-operate/`. Complements `aap-admin` (creation) with **day-to-day operations**.

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
# From repo root
./operate launch-job.sh -e @.cursor/skills/aap-operate/vars/examples/launch-job.yml
./operate sync-project.sh -e project_name=aap_backup_automation -e organization="teste cursor"
./operate list-resources.sh -e resource_type=job_templates -e organization="teste cursor"
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
