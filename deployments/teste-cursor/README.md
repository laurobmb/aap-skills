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
