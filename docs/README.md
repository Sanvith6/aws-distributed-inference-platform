# 📚 Documentation Index

Welcome to the documentation hub for the **Distributed AI Inference Platform on AWS**. All technical documentation lives here.

---

## Documents

| Document | Description | Audience |
|---|---|---|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Deep-dive technical architecture — VPC layout, NAT design, RPC mesh, request lifecycle, security boundaries | Engineers |
| [DEPLOYMENT.md](./DEPLOYMENT.md) | Step-by-step deployment guide from a clean AWS account to a live verified API | Everyone |
| [SECURITY.md](./SECURITY.md) | Security design, network isolation, IAM model, TLS config, systemd hardening, production hardening checklist | Security reviewers |
| [API_REFERENCE.md](./API_REFERENCE.md) | OpenAI-style API documentation — `/health` and `/v1/chat/completions` with curl, Python, and PowerShell examples | API consumers |
| [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) | Debugging journal — 12 real issues documented with root cause, diagnosis steps, and fix applied | Operators / Evaluators |
| [WRITEUP.md](./WRITEUP.md) | Production hardening recommendations + 100× model scaling architecture (assignment writeup) | Evaluators |
| [FINAL_REPORT.md](./FINAL_REPORT.md) | Project completion report — objectives, implementation, validation, lessons learned | Evaluators / Recruiters |
| [WHY.md](./WHY.md) | Overarching project motive & deep-dive technical reasoning behind chosen stacks | Evaluators / Recruiters |
| [INFRA.md](./INFRA.md) | Highly detailed cloud networking, infrastructure dynamic blueprints, and IaC mappings | DevOps Engineers |
| [PROJECT_ANALYSIS.md](./PROJECT_ANALYSIS.md) | Comprehensive static evaluation of HCL, playbook mappings, and systemd settings | DevOps Architects |
| [IMPLEMENTATION_DONE.md](./IMPLEMENTATION_DONE.md) | Actionable record of implementation verification steps, logs, and evidence of completeness | Recruiters / Leads |
| [CONFIG_AUDIT_REPORT.md](./CONFIG_AUDIT_REPORT.md) | AI Configuration Audit Agent diagnostic outputs — Health Score: **100/100** | Lead architects |
| [ALL.md](./ALL.md) | Consolidated, end-to-end master system architectural reference documentation | Evaluators / Everyone |
| [TASK.md](./TASK.md) | Historical task progress checklist mapping features from start to completion | Project managers |

---

## Quick Links

- 🏠 [Back to project root README](../README.md)
- 📸 [Screenshot capture guide](../screenshots/README.md)
- 📊 [Architecture diagrams](../diagrams/README.md)

---

## Document Descriptions

### [ARCHITECTURE.md](./ARCHITECTURE.md)
The most technical document in the repository. Covers:
- VPC topology and subnet design
- NAT instance internals (iptables, ip_forward, source/dest check)
- iii-engine RPC mesh design and worker registration flow
- Nginx reverse proxy configuration rationale
- End-to-end request trace (11 steps from `curl` to response)
- Security boundary matrix
- Failure recovery scenarios (process crash, WebSocket drop, NAT failure, engine restart)
- Full Terraform resource dependency graph
- Ansible role execution order

### [DEPLOYMENT.md](./DEPLOYMENT.md)
A beginner-friendly walkthrough. Covers:
- Prerequisites and tool installation
- AWS account setup and IAM user creation
- AWS credential configuration (env vars and `aws configure`)
- Terraform init → plan → apply with expected output
- Ansible inventory generation from Terraform output
- Running the playbook with expected progress output
- Service verification via `systemctl status`
- API smoke testing via `curl`
- One-command automated deploy
- Teardown and cleanup

### [SECURITY.md](./SECURITY.md)
A thorough security analysis. Covers:
- Defense-in-depth philosophy
- Private subnet isolation (routing-layer guarantee, not just firewall)
- Per-VM security group rules (inbound/outbound matrix)
- NAT instance security model
- TLS configuration (protocols, cipher suites, session settings)
- IAM role separation and least-privilege scoping
- Bastion jump host SSH patterns
- WebSocket isolation model (outbound-only worker connections)
- Nginx application-layer security (rate limiting, security headers)
- systemd service hardening directives
- Secrets management approach
- 13-item production hardening checklist

### [API_REFERENCE.md](./API_REFERENCE.md)
OpenAI-compatible API documentation. Covers:
- `GET /health` — request, response, notes
- `POST /v1/chat/completions` — full request/response schemas
- Example requests in curl, PowerShell, and Python
- Error response catalog (429, 502, 504)
- Rate limiting parameters
- Request timeout guidance
- OpenAI SDK compatibility notes

### [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
The most candid document — a real debugging journal. Covers 12 issues:
1. NAT instance source/dest check (silent packet drop)
2. apt dpkg lock (unattended-upgrades race condition)
3. PyTorch CUDA wheel disk exhaustion
4. WSL SSH ProxyCommand path failures
5. systemd service restart loops (3 sub-causes)
6. WebSocket registration with wrong IP (public vs. private)
7. GGUF model OOM kills (missing swap)
8. Python iii SDK Logger attribute error
9. Windows line ending corruption in Ansible inventory
10. iii-engine CLI flag changes between versions
11. Inference worker startup timeout (model download)
12. Nginx 502 during engine restart (empty worker registry)

### [WRITEUP.md](./WRITEUP.md)
Assignment writeup on production readiness and scaling. Covers:
- **Hardening:** ALB+ACM, AWS WAF, SSM-only access, IAM narrowing, Secrets Manager, CloudWatch, Packer AMIs, multi-AZ HA
- **100× scaling:** GPU instances (g5.xlarge), vLLM/TGI serving, SQS queue decoupling, EKS orchestration, model weight caching

### [FINAL_REPORT.md](./FINAL_REPORT.md)
Professional project completion report. Covers:
- Assignment objective and all acceptance criteria
- Infrastructure provisioning summary (24 Terraform resources)
- Deployment automation summary (Terraform + Ansible pipeline)
- Service configuration summary (Nginx, iii-engine, systemd)
- Testing and validation results (automated + manual)
- Operational audit table (expected vs. actual for all components)
- Debugging journey highlights
- Lessons learned (technical + process)
- 4-phase future scalability roadmap
- Full deliverables checklist against assignment requirements

### [WHY.md](./WHY.md)
Detailed architectural choices, motive, and technology stack rationalizations. Covers why multi-account splits, custom NAT instances, and quantized models are used.

### [INFRA.md](./INFRA.md)
Declarative infrastructure specifications, dynamic NAT instance packet masquerading iptables instructions, cost saving analysis, and security firewalls details.

### [PROJECT_ANALYSIS.md](./PROJECT_ANALYSIS.md)
Static layout mappings, Ansible SSH jump bastion parameters, configuration drift checking rules, and dynamic network boundaries validation.

### [CONFIG_AUDIT_REPORT.md](./CONFIG_AUDIT_REPORT.md)
Full configuration audit agent report verifying 100% compliance with security constraints, showing an audit Health Score of **100/100**.

### [ALL.md](./ALL.md)
A unified technical guide consolidating the entire ecosystem (network, edge, compute, database/files, scripts, pipelines).

### [TASK.md](./TASK.md)
Granular phase-by-phase implementation log tracking task resolution and validation checklist.
