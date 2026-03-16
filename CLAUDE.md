# CLAUDE.md — OcadoFlow

This file is the single source of truth for Claude Code across all sessions on this project.
Read it fully at the start of every conversation.

---

## Project Overview

**OcadoFlow** is a portfolio project by Stanislav Vainer (DevOps Engineer, London).
It simulates an enterprise integration platform with:

- AWS ALB as API Gateway with OAuth2 + RBAC enforcement
- Three Spring Boot microservices (Products :8081, Orders :8082, IAM :8083) on ECS Fargate
- Full IaC via Terraform + Ansible
- GitLab CI/CD pipeline (6 stages: build → test → security → package → deploy:staging → deploy:prod)

Target role: **DevOps Engineer @ Ocado Retail (VN1230)**

---

## Repository Structure

```
ocadoflow/
├── services/
│   ├── products/        # Spring Boot, port 8081, RDS Postgres
│   ├── orders/          # Spring Boot, port 8082, RDS Postgres
│   └── iam/             # Spring Boot, port 8083, DynamoDB, RBAC policy
├── infra/terraform/     # main.tf, variables.tf, outputs.tf
├── ansible/             # playbook.yml — hardening, RBAC sync, health checks
├── tests/
│   ├── rbac/            # RBAC policy unit + live tests (pytest)
│   └── smoke/           # Post-deploy smoke tests (pytest)
├── demo/                # Interactive OAuth2/RBAC gateway simulator (HTML)
├── docs/                # DEMO-INSTRUCTIONS.md
├── .gitlab-ci.yml       # Full pipeline definition
└── README.md
```

---

## Common Commands

```bash
# Local dev — start all services
docker compose up -d

# Run Java service tests
mvn test -pl services/products,services/orders,services/iam

# Run RBAC policy tests
pytest tests/rbac/ -v

# Run smoke tests
pytest tests/smoke/ -v

# Terraform plan
cd infra/terraform && terraform plan -var-file=terraform.tfvars

# Run demo locally
open demo/ocadoflow-app.html
```

---

## Architecture Decisions (ADRs)

| Decision | Rationale |
|----------|-----------|
| ALB as API Gateway | AWS-native, integrates with Cognito/WAF/CloudWatch; mirrors Ocado's iPaaS infra |
| RBAC enforced at gateway | Single enforcement point — audit-friendly, no per-service policy drift |
| Per-service IAM task roles | Least-privilege: Products can't read IAM secrets, IAM can't touch Orders DB |
| Manual gate for production | Safety tradeoff: staging is fully automated, prod requires human approval |
| Remote Terraform state | S3 + DynamoDB locking for team-safe state management |

---

## Working Conventions

- **Branch naming**: `feature/<ticket-or-topic>`, `fix/<description>`, `docs/<topic>`
- **Commit style**: Conventional Commits — `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`
- **No direct pushes to `main`** — always PR from a feature branch
- **CI must pass** before merging — do not skip pipeline stages
- **Secrets** never committed — all injected via AWS Secrets Manager or env vars

---

## Claude Behavior Guidelines

- Read this file and the relevant source files before suggesting any changes
- Prefer editing existing files over creating new ones
- Keep changes minimal and focused — no unrequested refactors or cleanup
- Do not add comments, docstrings, or type hints to code you didn't change
- Do not add error handling for scenarios that can't happen in this stack
- Ask before running destructive commands (terraform destroy, git reset --hard, etc.)
- When writing Terraform: use `for_each` over `count`, follow existing variable patterns in `variables.tf`
- When writing CI: follow the existing `.gitlab-ci.yml` stage structure and naming

---

## Progress & Session Log

| Date | Branch | What was done |
|------|--------|---------------|
| 2026-03-16 | `feature/cl-init` | Created CLAUDE.md — baseline context, conventions, ADRs |
| 2026-03-16 | `demo/ocado-test` | Built `demo/ocado-engineer-flows.html` — 7-tab interactive demo (Daily Duties, CI/CD, Security, API Gateway, Terraform, Access Management, Incident Response) aligned to Ocado VN1230 role |

> Update this table at the end of every session with a one-line summary of what changed.

---

## Open Work / Known TODOs

- [ ] Add `docker-compose.yml` for full local dev stack
- [ ] Add Swagger/OpenAPI specs for all three services
- [ ] Wire Terraform outputs to Ansible inventory dynamically
- [ ] Add GitHub Actions mirror of GitLab CI (for portfolio visibility)
- [ ] Add `tests/integration/` layer with Testcontainers

---

## Environment Variables Reference

| Variable | Where set | Used by |
|----------|-----------|---------|
| `AWS_REGION` | CI env / local `.env` | Terraform, AWS CLI |
| `OAUTH2_ISSUER` | Secrets Manager | Gateway, IAM service |
| `DB_PASSWORD` | Secrets Manager | Products, Orders |
| `JWT_SECRET` | Secrets Manager | IAM service |

---

## Security Notes

- All ECR images scanned with Trivy — no CRITICAL CVEs gate
- Semgrep + OWASP dependency-check + TruffleHog run in CI `security` stage
- KMS encryption on ECR, S3, Secrets Manager, SNS
- SSH locked down via Ansible hardening playbook
- Docker containers run with `no-new-privileges` + user namespace remapping
