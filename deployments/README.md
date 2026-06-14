# Deployments

Versioned AAP resource stacks — environment configuration, separate from skill logic.

```
deployments/
├── README.md
├── teste-cursor/          # org "teste cursor" — backup automation
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
