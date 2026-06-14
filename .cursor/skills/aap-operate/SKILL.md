---
name: aap-operate
description: >-
  Opera recursos existentes no Ansible Automation Platform (AAP) 2.6: lançar
  jobs, sincronizar projects SCM e listar recursos. Usa ansible-navigator e EE
  quay.io/lagomes/ee-cac-rhel9:v7. Aplicar quando o utilizador pedir executar,
  lançar ou correr job template, sync de project, listar organizations,
  projects, job templates, jobs ou inventories no AAP.
---

# AAP Operate (2.6)

Skill em `.cursor/skills/aap-operate/`. Complementa `aap-admin` (criação) com **operação** do dia-a-dia.

**Nunca** remover recursos (`state: absent`, DELETE na API) sem confirmação humana explícita — ver `.cursor/rules/aap-safety.mdc`.

## Scripts

| Ação | Script | Obrigatórios |
|------|--------|--------------|
| Lançar job | `launch-job.sh` | `job_template_name` |
| Sync project | `sync-project.sh` | `project_name` |
| Listar recursos | `list-resources.sh` | `resource_type` |

Credenciais: `vars/local.yml` ou partilhadas de `../aap-admin/vars/local.yml`.

## Uso

```bash
# Da raiz do repo
./operate launch-job.sh -e @.cursor/skills/aap-operate/vars/examples/launch-job.yml
./operate sync-project.sh -e project_name=aap_backup_automation -e organization="teste cursor"
./operate list-resources.sh -e resource_type=job_templates -e organization="teste cursor"
```

Valores com espaços → JSON ou `-e @vars/examples/...`.

## launch-job

```bash
./scripts/launch-job.sh \
  -e job_template_name=backup-aap \
  -e organization="teste cursor" \
  -e wait=true
```

| Variável | Default | Descrição |
|----------|---------|-----------|
| `job_template_name` | — | Nome do job template |
| `organization` | `Default` | Organização |
| `inventory` | omit | Override de inventory |
| `credentials` | omit | Lista de credenciais |
| `extra_vars` | omit | Variáveis extra |
| `limit` | omit | Limit de hosts |
| `wait` | `true` | Aguardar conclusão |
| `timeout` | módulo default | Timeout em segundos |

## sync-project

```bash
./scripts/sync-project.sh \
  -e '{"project_name":"aap_backup_automation","organization":"teste cursor"}'
```

| Variável | Default | Descrição |
|----------|---------|-----------|
| `project_name` | — | Nome do project |
| `organization` | `Default` | Organização |
| `wait` | `true` | Aguardar sync |
| `timeout` | `300` | Timeout em segundos |

## list-resources

`resource_type`: `organizations`, `projects`, `job_templates`, `jobs`, `inventories`

```bash
./scripts/list-resources.sh -e resource_type=jobs -e '{"api_query":{"status":"failed"}}'
./scripts/list-resources.sh -e resource_type=projects -e organization="teste cursor"
```

| Variável | Default | Descrição |
|----------|---------|-----------|
| `resource_type` | — | Tipo de recurso |
| `organization` | — | Filtrar por organização |
| `api_query` | — | Filtros API extra (ex. `status: failed`) |
| `page_size` | `25` | Resultados por página |
| `order_by` | `name` | Ordenação |

## EE

`quay.io/lagomes/ee-cac-rhel9:v7` via `ansible-navigator.yml`.
