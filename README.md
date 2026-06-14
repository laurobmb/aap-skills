# aap-skills

Skills e rules para administrar o **Ansible Automation Platform (AAP) 2.6** com agentes de IA (Cursor), de forma repetível e auditável.

## Porquê skills e rules para o AAP?

Operar um AAP envolve dezenas de recursos interligados — organizations, projects, inventories, credentials, job templates, workflows e execution environments. Um agente de IA sem contexto pode inventar parâmetros, usar a API de forma inconsistente ou aplicar alterações destrutivas por interpretação errada de um pedido.

Este repositório resolve isso com:

- **Skills** (`aap-admin`, `aap-operate`) — scripts e playbooks testados que o agente executa via `ansible-navigator` e uma EE fixa (`quay.io/lagomes/ee-cac-rhel9:v7`), sem instalar collections no host
- **Rules** (`.cursor/rules/`) — limites de comportamento: branch de trabalho, defaults automáticos, **proibição de delete sem confirmação humana**, proteção de credenciais

### Vantagens

| Vantagem | Como |
|----------|------|
| **Repetibilidade** | O mesmo pedido em linguagem natural gera o mesmo script/playbook |
| **Isolamento** | Tudo corre dentro da EE; o host só precisa de `ansible-navigator` e `podman` |
| **Menos erros de API** | Módulos `ansible.controller` em vez de chamadas ad hoc mal formadas |
| **Onboarding rápido** | Novos operadores pedem ao agente "cria um job template" em vez de navegar toda a UI |
| **GitOps-friendly** | Scripts versionados; exemplos em `vars/examples/` |

### Cuidados de segurança na operação

- **Credenciais** ficam em `vars/local.yml` (gitignored) — nunca no repositório nem no chat
- **Remoção bloqueada por rule** — o agente não pode usar `state: absent` nem DELETE na API sem confirmação humana explícita (ver `.cursor/rules/aap-safety.mdc`)
- **Jobs são execução real** — `launch-job.sh` dispara automação nos hosts; validar template, inventory e limit antes de lançar
- **Defaults automáticos** — inventory, EE e credential podem ser inferidos; em produção, especificar explicitamente quando o default não for aceitável
- **Princípio do menor privilégio** — usar conta AAP dedicada ao agente, não `admin`, quando possível
- **Auditoria** — rever artifacts do ansible-navigator e o activity stream do controller após alterações sensíveis

O objetivo não é substituir o operador humano, mas **acelerar tarefas rotineiras** mantendo guardrails claros.

---

## Skills

| Skill | Atalho | Função |
|-------|--------|--------|
| `aap-admin` | `./aap` | **Criar** recursos (org, project, JT, etc.) |
| `aap-operate` | `./operate` | **Operar** (launch job, sync project, listar) |

```
.cursor/skills/aap-admin/     # criação de recursos
.cursor/skills/aap-operate/   # operação do dia-a-dia
.cursor/rules/                # guardrails para o agente
```

**Não precisa de collections Ansible no host** — tudo via `ansible-navigator` + EE `quay.io/lagomes/ee-cac-rhel9:v7`.

## Setup

```bash
cp .cursor/skills/aap-admin/vars/local.yml.example \
   .cursor/skills/aap-admin/vars/local.yml

chmod +x .cursor/skills/aap-admin/scripts/*.sh \
         .cursor/skills/aap-operate/scripts/*.sh aap operate
```

## Uso — criar (aap-admin)

```bash
./aap verify-aap.sh

./aap create-job-template.sh \
  -e job_template_name=meu-job \
  -e '{"inventory":"Demo Inventory","project":"Demo Project","playbook":"hello_world.yml"}'
```

## Uso — operar (aap-operate)

```bash
./operate list-resources.sh -e resource_type=job_templates -e organization="teste cursor"

./operate sync-project.sh -e project_name=aap_backup_automation -e organization="teste cursor"

./operate launch-job.sh -e job_template_name=backup-aap -e organization="teste cursor"
```

Ver `.cursor/skills/aap-admin/SKILL.md` e `.cursor/skills/aap-operate/SKILL.md`.

## Branch

Desenvolvimento na branch **`v2.6`**.
