# aap-skills

Workspace de **Cursor Skills** para administrar o Ansible Automation Platform (AAP) 2.6.

Tudo vive dentro da skill:

```
.cursor/skills/aap-admin/
├── SKILL.md                 # instruções para o agente
├── ansible-navigator.yml    # EE quay.io/lagomes/ee-cac-rhel9:v7
├── playbooks/               # um playbook por recurso AAP
├── scripts/                 # um script por recurso → ansible-navigator
└── vars/
    ├── local.yml            # credenciais (gitignored)
    └── examples/            # exemplos de variáveis
```

**Não precisa de collections Ansible no host** — os scripts usam `ansible-navigator` + EE em container.

## Setup

```bash
cp .cursor/skills/aap-admin/vars/local.yml.example \
   .cursor/skills/aap-admin/vars/local.yml

chmod +x .cursor/skills/aap-admin/scripts/*.sh aap
```

## Uso

A partir da raiz do repo (atalho `./aap`):

```bash
./aap verify-aap.sh

./aap create-job-template.sh \
  -e job_template_name=meu-job \
  -e '{"inventory":"Demo Inventory","project":"Demo Project","playbook":"hello_world.yml"}'
```

Ou diretamente na skill:

```bash
cd .cursor/skills/aap-admin
./scripts/create-workflow.sh -e @vars/examples/workflow.yml
```

## Recursos

Organization, project, inventory, host, group, inventory source, credential, job template, workflow, schedule, execution environment, team, user, label, notification template, instance group.

Ver tabela completa em `.cursor/skills/aap-admin/SKILL.md`.

## Branch

Desenvolvimento na branch **`v2.6`**.
