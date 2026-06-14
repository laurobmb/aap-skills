# aap-skills

Skills and rules to administer **Ansible Automation Platform (AAP) 2.6** with AI agents (Cursor), in a repeatable and auditable way.

## Why skills and rules for AAP?

Operating AAP involves dozens of interconnected resources — organizations, projects, inventories, credentials, job templates, workflows, and execution environments. An AI agent without context may invent parameters, call the API inconsistently, or apply destructive changes due to a misinterpreted request.

This repository addresses that with:

- **Skills** (`aap-admin`, `aap-operate`) — tested scripts and playbooks the agent runs via `ansible-navigator` and a fixed EE (`quay.io/lagomes/ee-cac-rhel9:v7`), without installing collections on the host
- **Rules** (`.cursor/rules/`) — behavioral guardrails: working branch, automatic defaults, **no delete without human confirmation**, credential protection

### Benefits

| Benefit | How |
|---------|-----|
| **Repeatability** | The same natural-language request produces the same script/playbook |
| **Isolation** | Everything runs inside the EE; the host only needs `ansible-navigator` and `podman` |
| **Fewer API errors** | `ansible.controller` modules instead of ad hoc malformed calls |
| **Faster onboarding** | New operators ask the agent to "create a job template" instead of navigating the full UI |
| **GitOps-friendly** | Versioned scripts; stacks in `deployments/`; templates in `vars/examples/` |

### Security considerations

- **Credentials** live in `vars/local.yml` (gitignored) — never in the repository or chat
- **Deletion blocked by rule** — the agent cannot use `state: absent` or API DELETE without explicit human confirmation (see `.cursor/rules/aap-safety.mdc`)
- **Jobs are real execution** — `launch-job.sh` runs automation on hosts; validate template, inventory, and limit before launching
- **Automatic defaults** — inventory, EE, and credential may be inferred; in production, specify explicitly when the default is not acceptable
- **Least privilege** — use a dedicated AAP account for the agent, not `admin`, when possible
- **Audit** — review ansible-navigator artifacts and the controller activity stream after sensitive changes

The goal is not to replace the human operator, but to **speed up routine tasks** with clear guardrails.

---

## Skills

| Skill | Shortcut | Purpose |
|-------|----------|---------|
| `aap-admin` | `./aap` | **Create** resources (org, project, JT, etc.) |
| `aap-operate` | `./operate` | **Operate** (launch job, sync project, list) |

```
.cursor/skills/aap-admin/     # resource creation
.cursor/skills/aap-operate/   # day-to-day operations
.cursor/rules/                # guardrails for the agent
deployments/                  # versioned stacks per org/environment
```

**No Ansible collections required on the host** — everything runs via `ansible-navigator` + EE `quay.io/lagomes/ee-cac-rhel9:v7`.

## Deployments

Reusable stacks (vars files) live at repo root — separate from skill logic:

```bash
./apply-deployment teste-cursor
```

See `deployments/README.md`.

## Setup

```bash
cp .cursor/skills/aap-admin/vars/local.yml.example \
   .cursor/skills/aap-admin/vars/local.yml

chmod +x .cursor/skills/aap-admin/scripts/*.sh \
         .cursor/skills/aap-operate/scripts/*.sh aap operate apply-deployment
```

## Usage — create (aap-admin)

```bash
./aap verify-aap.sh

./aap create-job-template.sh \
  -e job_template_name=my-job \
  -e '{"inventory":"Demo Inventory","project":"Demo Project","playbook":"hello_world.yml"}'
```

## Usage — operate (aap-operate)

```bash
./operate list-resources.sh -e resource_type=job_templates -e organization="teste cursor"

./operate sync-project.sh -e project_name=aap_backup_automation -e organization="teste cursor"

./operate launch-job.sh -e job_template_name=backup-aap -e organization="teste cursor"
```

See `.cursor/skills/aap-admin/SKILL.md` and `.cursor/skills/aap-operate/SKILL.md`.

## Branch

Development on branch **`v2.6`**.
