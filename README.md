# aap-skills

Cursor skills to help administer **Red Hat Ansible Automation Platform (AAP) 2.6**.

## Motivation

Administering AAP means creating and operating many related resources — organizations, projects, inventories, credentials, job templates, workflows, and execution environments. Doing that by hand in the UI is slow. Asking an AI agent without a dedicated skill is risky: invented parameters, inconsistent API calls, or accidental deletes.

This repository exists so a Cursor agent can **create and operate AAP** through tested skills (`aap-admin` and `aap-operate`), instead of improvising against the Controller.

- **aap-admin** — create and configure resources
- **aap-operate** — launch jobs, sync projects, and list what already exists

Full specification (how to rebuild the skills, scripts, and playbooks): [SPEC.md](SPEC.md)
