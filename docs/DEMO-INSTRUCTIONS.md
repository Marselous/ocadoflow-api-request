# OcadoFlow — Demo & Usage Instructions

**Project:** `ocadoflow-api-request`  
**Author:** Stanislav Vainer  
**Purpose:** Portfolio demonstration for the DevOps Engineer role at Ocado Retail (VN1230)

---

## What This Project Is

OcadoFlow is a portfolio demonstration of an **enterprise API Gateway with microservices**, showing production-grade DevOps practices across four deliverables:

| File | What It Is |
|------|-----------|
| `demo/ocadoflow-app.html` | Interactive live demo — runs entirely in a browser |
| `infra/terraform/main.tf` | Real AWS infrastructure (deployable) |
| `ansible/playbook.yml` | Configuration management and security hardening |
| `.gitlab-ci.yml` | Full 6-stage CI/CD pipeline |

---

## Part 1 — Running the Interactive Demo

The demo requires no installation. It runs entirely in your browser.

### How to Open It

1. Download `ocadoflow-app.html` (or find it in `demo/` after running setup)
2. Open it in any modern browser — double-click the file, or drag it into a browser tab
3. The full application loads immediately — no server needed

### What You're Looking At

The screen is divided into three panels:

**Left panel — Identity & Auth**
This is where you control who you are. Four identities are available, each representing a different OAuth2 role with different JWT scopes.

**Centre panel — API Gateway**
This is the interactive core. You can see the architecture diagram at the top, the request builder in the middle, and the response viewer below.

**Right panel — Access Logs & RBAC Matrix**
Every request you fire is logged here. The RBAC Matrix tab shows the full permission table.

---

### Step-by-Step Walkthrough

#### Step 1 — Understand the roles

Click each identity card in the left panel and watch the JWT token update:

| Identity | Role | What they can do |
|----------|------|-----------------|
| `admin@ocado.com` | admin | Everything — products, orders, IAM management |
| `ops@ocado.com` | ops | Read products, manage orders — no IAM |
| `viewer@ocado.com` | viewer | Read-only — products and orders only |
| `anonymous` | — | No token — all requests rejected |

#### Step 2 — Fire a successful request

1. Make sure **admin@ocado.com** is selected (left panel)
2. In the centre panel, click the chip: `GET /products`
3. Click **▶ SEND**
4. Watch: the architecture arrows animate, showing the request flow through the gateway to the Products microservice
5. The response panel shows a `200 OK` with a JSON product catalogue
6. The right panel logs the request with role and scope information

#### Step 3 — Trigger a 403 Forbidden (RBAC enforcement)

This is the key demo moment — showing real access control:

1. Click **viewer@ocado.com** in the left panel
2. Notice the JWT token updates — scope is now `["products:r","orders:r"]`
3. Click the chip: `POST /orders` (requires `orders:write` scope)
4. Click **▶ SEND**
5. Watch: the gateway rejects the request — **403 Forbidden**
6. The response shows `ERR_INSUFFICIENT_SCOPE` with the required vs held scopes
7. The log panel records a WARN entry

#### Step 4 — Trigger a 401 Unauthorized (no token)

1. Click **anonymous** in the left panel
2. The token panel shows "No token present"
3. Fire any request
4. Result: **401 Unauthorized** — `ERR_NO_TOKEN`
5. This simulates what happens when a client hasn't completed the OAuth2 flow

#### Step 5 — Try the IAM endpoints (admin only)

1. Switch back to **admin@ocado.com**
2. Click chip: `GET /iam/users`
3. `200 OK` — returns a list of platform users with roles and last login times
4. Now switch to **ops@ocado.com** and try the same request
5. `403 Forbidden` — ops role lacks `iam:read` scope

#### Step 6 — Review the RBAC Matrix

1. In the right panel, click the **RBAC Matrix** tab
2. This shows the full permission table — every role vs every scope
3. This is the policy-as-code defined in `services/iam/rbac-policy.yaml`

---

### What to Say When Presenting This

When showing this to an interviewer or including it in a portfolio, explain:

> *"The gateway enforces OAuth2 token validation and RBAC policy at a single enforcement point — rather than in each individual service. This is the same pattern used in enterprise iPaaS platforms like MuleSoft: centralised auth, decoupled services. The RBAC policy is defined as YAML in the IAM service, synced via Ansible on every deployment, and tested in the CI pipeline before any code reaches staging."*

---

## Part 2 — Understanding the Infrastructure Code

### Terraform (`infra/terraform/main.tf`)

The Terraform file is real and deployable to AWS. Key things to point out:

**The `for_each` pattern** — all three services are defined from a single variable:
```hcl
variable "services" {
  default = {
    products = { port=8081, cpu=256, memory=512, desired_count=2 }
    orders   = { port=8082, cpu=512, memory=1024, desired_count=3 }
    iam      = { port=8083, cpu=256, memory=512, desired_count=2 }
  }
}
```
Adding a fourth service means adding four lines. This is infrastructure-as-code done right.

**Per-service IAM task roles** — each ECS task has its own IAM role, and each role only has permission to read its own secret from Secrets Manager. The products service cannot read the IAM service's database password. This is least-privilege at the container level.

**Deployment circuit breaker** — if a new task definition fails to start, ECS automatically rolls back to the previous version. Zero manual intervention.

**To inspect it**, open `infra/terraform/main.tf` in any text editor or IDE. It's fully commented.

---

### Ansible (`ansible/playbook.yml`)

The playbook has three plays — you can run them independently:

```bash
# Run everything
ansible-playbook ansible/playbook.yml -i ansible/inventory.example

# Run only the RBAC sync (safe to run anytime)
ansible-playbook ansible/playbook.yml -i ansible/inventory.example --tags rbac

# Run only health checks
ansible-playbook ansible/playbook.yml -i ansible/inventory.example --limit localhost
```

**What it does:**
- Play 1 — Hardens ECS hosts: locks down SSH, configures auditd rules, sets kernel security parameters, deploys CloudWatch agent
- Play 2 — Validates that all three service endpoints are responding correctly post-deployment
- Play 3 — Syncs the RBAC role definitions from `rbac-policy.yaml` to the live IAM service via its API

---

### CI/CD Pipeline (`.gitlab-ci.yml`)

The pipeline runs automatically on every push to `main` or `release/*` branches. It has six stages:

```
commit
  │
  ├── build      Maven compile all 3 services in parallel
  ├── test       Unit tests + integration tests + RBAC policy tests
  ├── security   Semgrep (SAST) + OWASP dep-check + tfsec + TruffleHog + Trivy
  ├── package    Docker build + ECR push + container vulnerability scan
  ├── staging    Terraform apply + ECS deploy + wait for stability
  ├── verify     Smoke tests against live staging environment
  └── production Manual approval → Terraform apply → ECS deploy
```

**The security stage is blocking** — if any tool finds a HIGH severity issue, the pipeline fails and nothing gets deployed. This is the key point: security is enforced by the pipeline, not by convention.

**Production requires manual approval** — click the play button in GitLab after staging has been verified. This is an intentional gate.

---

## Part 3 — Setting Up the Project Locally

### Prerequisites

- Git installed
- A GitHub account
- (Optional) GitHub CLI (`gh`) for the easiest push experience

### Setup Steps

1. **Download all files** from this conversation into one folder on your computer

2. **Run the setup script:**
   ```bash
   bash setup-and-push.sh your-github-username
   ```
   This creates the full project directory, copies files into the correct locations, and initialises a git repository with proper commit history.

3. **Push to GitHub** using one of:
   ```bash
   # Option A — GitHub CLI (easiest, creates the repo automatically)
   gh repo create ocadoflow-api-request --public --source=. --remote=origin --push

   # Option B — if you already created the repo on github.com manually
   git remote add origin https://github.com/YOUR_USERNAME/ocadoflow-api-request.git
   git branch -M main
   git push -u origin main
   ```

4. **Verify** — visit `https://github.com/YOUR_USERNAME/ocadoflow-api-request` to confirm all files are there with the commit history

### Project Location After Setup

```
~/Documents/my-projects/ocadoflow-api-request/
├── demo/
│   └── ocadoflow-app.html        ← Open this in a browser
├── infra/terraform/
│   ├── main.tf
│   └── terraform.tfvars.example
├── ansible/
│   ├── playbook.yml
│   └── inventory.example
├── services/
│   ├── products/
│   ├── orders/
│   └── iam/
│       └── rbac-policy.yaml      ← RBAC policy as code
├── tests/
│   └── smoke/
│       └── test_endpoints.py
├── docs/
│   └── DEMO-INSTRUCTIONS.md      ← This file
├── .gitlab-ci.yml
├── .gitignore
├── docker-compose.yml
└── README.md
```

---

## Part 4 — How to Present This in an Interview

### What Each File Demonstrates

| Ocado JD Requirement | What to Show |
|---------------------|-------------|
| "OAUTH2 credential management" | Demo: switch to `anonymous`, show 401. Switch to `viewer`, show 403 on write endpoint |
| "Implement and enforce security policies" | `ansible/playbook.yml` plays 1 and 3 — SSH hardening + RBAC policy sync |
| "Maintain and improve CI/CD pipelines" | `.gitlab-ci.yml` — point to security stage blocking on HIGH CVEs |
| "Automate routine tasks" | Ansible play 3 — RBAC sync automated on every deploy |
| "Access management, RBAC" | `services/iam/rbac-policy.yaml` + the live RBAC Matrix in the demo |
| "Cloud environments (AWS)" | `infra/terraform/main.tf` — VPC, ECS Fargate, ALB, IAM, ECR |
| "Troubleshoot and resolve issues" | Access log panel in demo — shows exactly why a request failed |

### Suggested Talking Points

**On security:**
> "Access control is enforced at the gateway — a single policy enforcement point. The RBAC policy lives in YAML in the repository, gets tested by pytest in the CI pipeline, and is synced to the live IAM service by Ansible on every deployment. Policy changes go through code review."

**On CI/CD:**
> "The pipeline has a dedicated security stage that runs four tools in parallel: Semgrep for static analysis, OWASP for dependency CVEs, tfsec for Terraform misconfigurations, and TruffleHog to prevent secrets ever reaching the repo. Any HIGH severity finding blocks the deploy."

**On infrastructure:**
> "All three services are defined from a single Terraform variable using `for_each`. Each ECS task has its own IAM role with access only to its own secrets — if the products container is compromised, it can't read the IAM database credentials. Deployment circuit breakers mean a bad deploy auto-rolls back without human intervention."

---

## Troubleshooting

**Demo doesn't load in browser:**
Make sure you're opening the `.html` file directly — not from a file path with spaces. If that fails, serve it locally: `python3 -m http.server 8080` in the `demo/` folder, then open `http://localhost:8080/ocadoflow-app.html`

**Setup script permission denied:**
Run `chmod +x setup-and-push.sh` first, then `./setup-and-push.sh`

**Git push rejected:**
Make sure the GitHub repo exists. With GitHub CLI, `gh repo create` handles this. Manually, go to github.com, create a new empty repo named `ocadoflow-api-request`, then run the Option B commands.

**`gh` command not found:**
Install GitHub CLI from https://cli.github.com, or use Option B (manual push) instead.

---

*OcadoFlow — Built by Stanislav Vainer as part of the DevOps Engineer application to Ocado Retail (VN1230)*
