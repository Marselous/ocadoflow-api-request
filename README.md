# OcadoFlow 🌐

**API Gateway + Microservices Platform with OAuth2/RBAC, IaC, and Full CI/CD**

> A portfolio project by [Stanislav Vainer](https://linkedin.com/in/stanislavvainer) — demonstrating production-grade DevOps practices aligned with enterprise integration platform engineering.

[![Pipeline](https://img.shields.io/badge/pipeline-passing-39d98a?style=flat-square&logo=gitlab)](https://gitlab.com)
[![Terraform](https://img.shields.io/badge/terraform-1.6-7B42BC?style=flat-square&logo=terraform)](https://terraform.io)
[![AWS](https://img.shields.io/badge/AWS-ECS%20Fargate-FF9900?style=flat-square&logo=amazon-aws)](https://aws.amazon.com)
[![Security](https://img.shields.io/badge/security-OAuth2%20%2B%20RBAC-00e5b4?style=flat-square)](.)

---

## What is OcadoFlow?

OcadoFlow simulates the infrastructure and security model of an **enterprise integration platform** — the kind that underpins systems like MuleSoft at scale. It consists of:

- An **API Gateway** (AWS ALB) handling authentication, routing, and rate-limiting
- **Three microservices** (Products, Orders, IAM) running on ECS Fargate
- **OAuth2 + RBAC** access control enforced at the gateway layer
- **Full CI/CD pipeline** (GitLab CI) from commit to production
- **Infrastructure as Code** (Terraform + Ansible) for repeatable, auditable deployments

---

## Architecture

```
                         ┌─────────────────────────────────────────┐
                         │           AWS eu-west-1                 │
                         │                                         │
  Client ──HTTPS──▶  ALB/API Gateway  ──OAuth2 validate──▶  Cognito│
                         │                                         │
              ┌──────────┼──────────┐                              │
              ▼          ▼          ▼                              │
        ┌──────────┐ ┌────────┐ ┌────────┐   ECS Fargate          │
        │ Products │ │ Orders │ │  IAM   │   Private Subnets       │
        │ :8081    │ │ :8082  │ │ :8083  │                         │
        └────┬─────┘ └───┬────┘ └───┬────┘                        │
             │           │          │                              │
        RDS Postgres  RDS Postgres  DynamoDB                       │
             │           │          │                              │
        CloudWatch ◀──── All services ────▶ SNS Alerts            │
                         │                                         │
                    S3 (logs, artifacts)                           │
                         └─────────────────────────────────────────┘
```

---

## Repository Structure

```
ocadoflow/
├── services/
│   ├── products/          # Product catalogue microservice (Spring Boot)
│   │   ├── src/
│   │   ├── Dockerfile
│   │   └── pom.xml
│   ├── orders/            # Order management microservice (Spring Boot)
│   │   ├── src/
│   │   ├── Dockerfile
│   │   └── pom.xml
│   └── iam/               # Identity & access management service
│       ├── src/
│       ├── rbac-policy.yaml
│       ├── Dockerfile
│       └── pom.xml
│
├── infra/
│   └── terraform/
│       ├── main.tf            # VPC, ECS, ALB, IAM, ECR, S3, CloudWatch
│       ├── variables.tf
│       └── outputs.tf
│
├── ansible/
│   └── playbook.yml           # Host hardening, RBAC sync, health checks
│
├── .gitlab-ci.yml             # Full CI/CD pipeline (6 stages)
│
└── tests/
    ├── rbac/                  # RBAC policy unit + live tests
    └── smoke/                 # Post-deploy smoke tests
```

---

## Security Architecture

### OAuth2 Token Flow

```
Client → POST /oauth2/token (client_credentials)
       ← JWT {sub, role, scope[], exp}

Client → GET /api/v1/products
         Authorization: Bearer <JWT>

Gateway → Validates JWT signature (JWKS endpoint)
        → Extracts scope[]
        → Checks RBAC policy
        → ✓ Routes to service  OR  ✗ 401/403
```

### RBAC Permission Matrix

| Scope             | admin | ops | viewer | anonymous |
|-------------------|:-----:|:---:|:------:|:---------:|
| `products:read`   | ✓ | ✓ | ✓ | ✗ |
| `products:write`  | ✓ | ✗ | ✗ | ✗ |
| `orders:read`     | ✓ | ✓ | ✓ | ✗ |
| `orders:write`    | ✓ | ✓ | ✗ | ✗ |
| `iam:read`        | ✓ | ✗ | ✗ | ✗ |
| `iam:manage`      | ✓ | ✗ | ✗ | ✗ |

---

## CI/CD Pipeline

```
commit → build → test → security scan → package → deploy:staging → verify → deploy:prod
                  │           │
                  │      tfsec + trivy + semgrep + dependency-check
                  │
              unit + integration + rbac-policy tests
```

### Stages

| Stage | Tools | Gate |
|-------|-------|------|
| **build** | Maven 3.9 + JDK 21 | Compile all 3 services |
| **test** | JUnit 5, pytest | Unit + integration + RBAC policy tests |
| **security** | Semgrep, OWASP, tfsec, TruffleHog | No HIGH CVEs, no secrets in code |
| **package** | Docker BuildKit, ECR, Trivy | Image scan — no CRITICAL vulns |
| **deploy:staging** | Terraform, AWS CLI | Auto-deploy to staging |
| **verify** | pytest smoke tests | All endpoints respond correctly |
| **deploy:production** | Terraform | **Manual approval gate** |

---

## Infrastructure as Code

### Terraform — Key Resources

```hcl
# All 3 services defined once, instantiated via for_each
variable "services" {
  default = {
    products = { port=8081, cpu=256, memory=512, desired_count=2 }
    orders   = { port=8082, cpu=512, memory=1024, desired_count=3 }
    iam      = { port=8083, cpu=256, memory=512, desired_count=2 }
  }
}
```

- **Remote state** in S3 with DynamoDB locking
- **Per-service IAM roles** with least-privilege secrets access
- **Auto Scaling** — CPU-triggered, 60s scale-out / 5min scale-in
- **Deployment circuit breaker** — auto-rollback on failed deploys
- **KMS encryption** on ECR, S3, Secrets Manager, SNS

### Ansible — What It Does

1. **Host hardening** — SSH lockdown, auditd rules, kernel params
2. **Docker security config** — `no-new-privileges`, user namespace remapping
3. **CloudWatch agent** — custom metrics and log forwarding
4. **RBAC policy sync** — pushes role definitions to IAM service via API
5. **Health validation** — end-to-end service checks post-deploy

---

## Local Development

```bash
# Clone
git clone https://gitlab.com/stanislavvainer/ocadoflow.git
cd ocadoflow

# Start all services
docker compose up -d

# Run tests
mvn test -pl services/products,services/orders,services/iam

# Test RBAC policies
pytest tests/rbac/ -v

# View API docs
open http://localhost:8080/swagger-ui
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `AWS_REGION` | AWS region (default: eu-west-1) |
| `OAUTH2_ISSUER` | JWT issuer URL |
| `DB_PASSWORD` | Injected from Secrets Manager |
| `JWT_SECRET` | Injected from Secrets Manager |

---

## Key Engineering Decisions

**Why ALB as API Gateway?**
Keeps the routing layer in AWS-native tooling — easy to integrate with Cognito, WAF, and CloudWatch. Maps directly to the kind of integration platform infrastructure Ocado already runs.

**Why per-service IAM task roles?**
Least-privilege at the container level. The products service cannot read IAM secrets. The IAM service cannot access the orders database. Compromising one container doesn't compromise the platform.

**Why manual approval for production?**
Staging is fully automated for speed. Production requires a human gate — an intentional tradeoff between velocity and safety appropriate for a customer-facing platform.

**Why RBAC at the gateway, not in each service?**
Single enforcement point. Simpler to audit, simpler to change policy without redeploying services. A pattern directly aligned with enterprise iPaaS platforms like MuleSoft.

---

## Author

**Stanislav Vainer** — DevOps Engineer  
📍 London, UK | ✉️ stanislav.vainer@outlook.com  
🔗 [LinkedIn](https://linkedin.com/in/stanislavvainer) | Applying for DevOps Engineer @ Ocado Retail (VN1230)
