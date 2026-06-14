---
name: aap-admin
description: >-
  Cria e gere recursos no Ansible Automation Platform (AAP) 2.6 via scripts
  e playbooks com ansible-navigator e EE quay.io/lagomes/ee-cac-rhel9:v7.
  Usar quando o utilizador pedir criar ou configurar organization, project,
  inventory, host, group, credential, job template, workflow, schedule, team,
  user, label, notification, execution environment ou instance group no AAP.
---

# AAP Admin (2.6)

Tudo nesta skill vive em `.cursor/skills/aap-admin/` (playbooks, scripts, vars).

## Regra principal

**Sempre** usar os scripts em `.cursor/skills/aap-admin/scripts/` — correm via `ansible-navigator` + EE (sem collections locais).

**Nunca** remover recursos (`state: absent`, DELETE na API) sem confirmação humana explícita — ver `.cursor/rules/aap-safety.mdc`.

```bash
# Da raiz do repo
./aap create-job-template.sh -e @.cursor/skills/aap-admin/vars/examples/job-template.yml

# Ou dentro da skill
cd .cursor/skills/aap-admin
./scripts/create-<recurso>.sh -e @vars/examples/<recurso>.yml
```

Credenciais do controller: `.cursor/skills/aap-admin/vars/local.yml` (gitignored).

## Defaults automáticos

Se **inventory**, **credential** ou **EE** não forem informados, os playbooks resolvem automaticamente a partir do AAP (ver `.cursor/rules/aap-defaults.mdc`):

| Recurso | Ordem de resolução |
|---------|-------------------|
| Inventory | 1º da organização → `Demo Inventory` |
| EE | default da org → `Default execution environment` → `ee-cac-rhel9` |
| Credential | 1ª Machine da organização → omitir se não existir |

## Fluxo do agente

1. Identificar o recurso pedido (tabela abaixo).
2. Recolher parâmetros obrigatórios — perguntar só o que faltar.
3. Executar o script (via `./aap <script>` na raiz ou `./scripts/<script>` na skill).
4. Confirmar `changed`/`ok` no output.

Valores com **espaços** (ex.: `Demo Inventory`) → usar JSON ou ficheiro `-e @vars/...`.

## Scripts disponíveis

| Recurso | Script | Variável nome | Obrigatórios |
|---------|--------|---------------|--------------|
| Ligação | `verify-aap.sh` | — | — |
| Organization | `create-organization.sh` | `organization_name` | `organization_name` |
| Project | `create-project.sh` | `project_name` | `project_name`, `scm_url` (se git) |
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

`organization` default: `Default` (exceto organization).

## Exemplos rápidos

### Job template

```bash
./scripts/create-job-template.sh \
  -e job_template_name=deploy-web \
  -e '{"inventory":"Demo Inventory","project":"Demo Project","playbook":"hello_world.yml"}'
```

### Credential Machine

```bash
./scripts/create-credential.sh \
  -e credential_name=host-01 \
  -e '{"inputs":{"username":"ansible","password":"secret"}}'
```

### Workflow com um job

```bash
./scripts/create-workflow.sh -e @vars/examples/workflow.yml
```

### Schedule

```bash
./scripts/create-schedule.sh \
  -e schedule_name=daily-backup \
  -e unified_job_template=meu-job \
  -e 'rrule=DTSTART:20260614T080000Z RRULE:FREQ=DAILY;INTERVAL=1'
```

## Exemplos em vars/examples/

| Ficheiro | Recurso |
|----------|---------|
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
- Org default: `Default`
- EE local: `ee-cac-rhel9` / `quay.io/lagomes/ee-cac-rhel9:v7`

## Collections (dentro da EE)

- `ansible.controller` — módulos usados nos playbooks
- `infra.aap_configuration` — roles config-as-code (referência)
