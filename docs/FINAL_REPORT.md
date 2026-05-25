# Final Project Report

**Project:** Distributed AI Inference Platform on AWS  
**Assignment:** Alchemyst AI DevOps Internship Technical Assessment  
**Submitted:** May 2026  
**Deadline:** May 23, 2026  
**Status:** ✅ COMPLETE — All acceptance criteria met and verified

---

## Table of Contents

1. [Assignment Objective](#1-assignment-objective)
2. [Final Implementation Summary](#2-final-implementation-summary)
3. [Architecture Summary](#3-architecture-summary)
4. [Infrastructure Provisioning Summary](#4-infrastructure-provisioning-summary)
5. [Deployment Automation Summary](#5-deployment-automation-summary)
6. [Service Configuration Summary](#6-service-configuration-summary)
7. [Testing and Validation Summary](#7-testing-and-validation-summary)
8. [Operational Audit Summary](#8-operational-audit-summary)
9. [Challenges and Debugging Journey](#9-challenges-and-debugging-journey)
10. [Lessons Learned](#10-lessons-learned)
11. [Future Scalability Roadmap](#11-future-scalability-roadmap)
12. [Deliverables Checklist](#12-deliverables-checklist)

---

## 1. Assignment Objective

The assignment required building a **distributed inference platform** that:

1. Deploys the `quickstart` worker project across multiple VMs in a **private subnet**
2. Establishes **cross-VM RPC communication** without direct public internet exposure
3. Exposes inference through a **public HTTPS JSON API** with an OpenAI-compatible schema
4. Is **fully reproducible** via Infrastructure-as-Code
5. Includes clear documentation sufficient for a teammate to redeploy on a clean account

The assignment explicitly states that network hygiene (workers not reachable from the internet), correctness (actual inference through the RPC chain), and reproducibility (IaC works from scratch) are the primary evaluation criteria.

---

## 2. Final Implementation Summary

All assignment requirements have been fully met and validated on live AWS infrastructure.

### Completed Deliverables

| Requirement | Status | Implementation |
|---|---|---|
| VPC with private subnet | ✅ Complete | Terraform — `10.0.0.0/16`, public+private subnets |
| Workers NOT on public internet | ✅ Complete | VM2, VM3 in private subnet, no public IPs |
| Cross-VM RPC communication | ✅ Complete | iii-engine WebSocket mesh, worker registration verified |
| Public HTTPS JSON API | ✅ Complete | Nginx :443, TLS 1.2/1.3, `/v1/chat/completions` working |
| Infrastructure as Code | ✅ Complete | Full Terraform (24 resources), Ansible (5 roles) |
| One-command deployment | ✅ Complete | `./scripts/deploy.sh` and `.\scripts\deploy.ps1` |
| README with curl example | ✅ Complete | README.md with full API docs and architecture |
| Architecture diagram | ✅ Complete | ASCII + Mermaid diagrams in README + ARCHITECTURE.md |
| Production writeup | ✅ Complete | WRITEUP.md + SECURITY.md with hardening recommendations |
| Teardown capability | ✅ Complete | `./scripts/teardown.sh` destroys all resources |

---

## 3. Architecture Summary

The platform implements a **hub-and-spoke WebSocket RPC architecture** on AWS:

```
Public Internet
    │ HTTPS :443
    ▼
VM1 (Public, t3.micro)
├── Nginx reverse proxy (TLS termination, rate limiting)
├── iii-engine (HTTP :3111, WebSocket :49134)
└── IAM: iii-engine-role (SSM + CloudWatch)

Private Subnet (10.0.2.0/24)
├── VM2 (c7i-flex.large) — Python inference-worker
│   └── Outbound WS → VM1:49134, registers inference::run_inference
└── VM3 (t3.micro) — TypeScript caller-worker
    └── Outbound WS → VM1:49134, registers HTTP trigger /v1/chat/completions

VM4 (Public, t3.micro) — NAT Instance
└── Enables outbound internet for private subnet (package installs, model downloads)
```

**Key architectural decisions:**

- **Private subnet for workers** — enforces network hygiene at the routing layer, not just firewall rules
- **Self-managed NAT Instance** — saves ~88% vs. AWS Managed NAT Gateway
- **Outbound-only WebSocket connections** — workers need no inbound ports; firewall management is trivial
- **iii-engine on loopback** — HTTP port 3111 bound to 127.0.0.1; unreachable externally even if SG rules fail
- **systemd for service management** — proven, production-grade process supervision with `Restart=on-failure`

---

## 4. Infrastructure Provisioning Summary

### Terraform Resources Created (24 total)

| Category | Resources |
|---|---|
| **Networking** | VPC, 2 Subnets, Internet Gateway, 2 Route Tables, 2 RT Associations |
| **Compute** | 4 EC2 Instances (Engine, NAT, Inference, Caller) |
| **Security** | 4 Security Groups |
| **Identity** | 2 IAM Roles, 3 Policy Attachments, 2 Instance Profiles |
| **Keys** | TLS Private Key, AWS Key Pair, Local PEM File |

### Region and Instance Selection

Deployed in `us-east-1` (US East, N. Virginia) — lowest latency for downloads, best Free Tier coverage.

| VM | Instance Type | RAM | vCPU | Rationale |
|---|---|---|---|---|
| VM1 Engine | t3.micro | 1 GiB | 2 | Low load; Nginx + iii-engine are lightweight |
| VM2 Inference | c7i-flex.large | 4 GiB | 2 | Compute-optimized for CPU inference; +8GB swap |
| VM3 Caller | t3.micro | 1 GiB | 2 | TypeScript worker is extremely lightweight |
| VM4 NAT | t3.micro | 1 GiB | 2 | iptables NAT is minimal resource usage |

---

## 5. Deployment Automation Summary

### Terraform Pipeline

The Terraform configuration was structured to be **idempotent** — running `terraform apply` multiple times produces the same result without creating duplicate resources. All configuration is expressed in HCL with sensible defaults in `variables.tf` and override capability via `terraform.tfvars`.

The SSH key pair is **generated by Terraform** (not pre-created) using the `tls_private_key` resource. This eliminates the common pattern of manually creating key pairs in the AWS console — the entire infrastructure, including credentials, is code-driven.

### Ansible Automation

The Ansible playbook executes **4 plays** with **5 role dependencies**:

```
Play 1 → [all hosts]      → common role     (packages, swap, user)
Play 2 → [engine_gateway] → nginx + engine  (reverse proxy + iii runtime)
Play 3 → [inference_worker] → inference-worker (Python worker + systemd)
Play 4 → [caller_worker]   → caller-worker  (Node.js worker + systemd)
```

Dynamic inventory is generated via `generate_inventory.py` which reads Terraform JSON output — eliminating the need to manually copy IP addresses between tools.

The `--extra-vars "engine_private_ip=..."` pattern ensures the correct private IP is injected into systemd unit files via Jinja2 templates, rather than hardcoded values.

### Cross-Platform Support

Both **Bash** (`.sh`) and **PowerShell** (`.ps1`) deployment scripts are provided. The PowerShell script includes automatic WSL detection and fallback — if Ansible isn't natively installed on Windows, it runs Ansible inside WSL Ubuntu automatically.

---

## 6. Service Configuration Summary

### Nginx Configuration

- **TLS:** TLSv1.2/1.3 only, strong cipher suite (ECDHE/DHE only)
- **Rate limiting:** 10 req/s per client IP, burst 20
- **Proxy timeout:** 120 seconds (accommodates slow LLM generation)
- **Security headers:** X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, CSP
- **Health endpoint:** Returns static JSON `{"status":"healthy"}` — no engine dependency
- **Custom 502:** Returns JSON error (not HTML) for API-friendly error handling

### iii-engine Configuration

Configured via `quickstart/config.yaml`:
- **HTTP listener:** `127.0.0.1:3111` (loopback only)
- **WebSocket listener:** `0.0.0.0:49134` (all interfaces, protected by SG)
- **Built-in workers enabled:** `iii-observability`, `iii-queue`, `iii-state`, `iii-http`
- **State storage:** File-based KV store at `./data/state_store.db`

### systemd Service Hardening

All services use the following security directives:
- `NoNewPrivileges=true` — prevents privilege escalation
- `ProtectSystem=strict` — read-only filesystem except `ReadWritePaths=/opt/iii`
- `ProtectHome=true` — no access to user home directories
- `PrivateTmp=true` — isolated `/tmp` namespace
- `User=iii` — non-root execution
- `Restart=on-failure` with `RestartSec=5-10s` — automatic recovery

---

## 7. Testing and Validation Summary

### Automated Tests

| Test | Command | Result |
|---|---|---|
| Terraform validate | `terraform validate` | ✅ Pass |
| Terraform format | `terraform fmt -check` | ✅ Pass |
| Ansible connectivity | `ansible all -m ping` | ✅ All hosts reachable |
| Health endpoint | `curl -k /health` | ✅ 200 OK |
| Inference API | `curl -k POST /v1/chat/completions` | ✅ 200 OK with `choices[]` |
| Schema validation | Response contains `choices` key | ✅ Pass |

### Manual Verification

| Verification | Method | Result |
|---|---|---|
| nginx active | `systemctl status nginx` | ✅ active (running) |
| iii-engine active | `systemctl status iii-engine` | ✅ active (running) |
| inference-worker active | `systemctl status inference-worker` | ✅ active (running) |
| caller-worker active | `systemctl status caller-worker` | ✅ active (running) |
| Workers registered | `journalctl -u iii-engine` | ✅ Both workers registered |
| Private subnet isolation | Direct internet → VM2 | ✅ Connection timeout (correct) |
| Bastion SSH | ProxyCommand via VM1 | ✅ VM2 and VM3 accessible |
| NAT routing | `curl google.com` from VM2 | ✅ 200 OK |

---

## 8. Operational Audit Summary

A configuration audit was performed using the `scripts/config_audit_agent.py` tool to verify runtime state matches declared intent.

### Audit Results

| Component | Expected | Actual | Status |
|---|---|---|---|
| iii-engine service | active (running) | active (running) | ✅ |
| nginx service | active (running) | active (running) | ✅ |
| inference-worker | active (running) | active (running) | ✅ |
| caller-worker | active (running) | active (running) | ✅ |
| /health endpoint | 200 + JSON | 200 + JSON | ✅ |
| /v1/chat/completions | 200 + choices[] | 200 + choices[] | ✅ |
| VM2 public IP | None | None | ✅ |
| VM3 public IP | None | None | ✅ |
| NAT ip_forward | 1 | 1 | ✅ |
| NAT iptables MASQUERADE | Present | Present | ✅ |

---

## 9. Challenges and Debugging Journey

This section documents the most significant technical challenges encountered, as they demonstrate practical problem-solving skills.

### Challenge 1: NAT Instance Source/Dest Check

The most impactful early blocker was discovering that AWS EC2 silently drops forwarded packets when **source/destination check** is enabled (the default). There was no error — packets simply disappeared. The fix required understanding the AWS networking model at a layer below what typical tutorials explain.

*Key learning: Always verify networking assumptions at the packet level, not just the configuration level.*

### Challenge 2: Windows/WSL SSH Compatibility

Developing on Windows while deploying to Linux created friction: Ansible's ProxyCommand uses POSIX path syntax, Python's file I/O defaults to Windows line endings, and OpenSSH on Windows handles key permissions differently than Linux. Each of these caused a separate failure mode.

*Key learning: Cross-platform DevOps work requires explicitly testing on the target platform, not assuming portability.*

### Challenge 3: PyTorch/GGUF Disk Exhaustion

Attempting to use a full CUDA wheel for `llama-cpp-python` on a small instance triggered disk exhaustion mid-download. The solution was architectural: switch to CPU-only inference and add swap memory — not just increase disk size.

*Key learning: Constrained environments require understanding the full dependency chain's storage requirements, not just runtime requirements.*

### Challenge 4: systemd Startup Timing

Multiple race conditions between service startup order, model downloads, and systemd's startup timeout surfaced. The `TimeoutStartSec` extension and explicit swap configuration were the fixes, but diagnosing the *exact* cause required reading `journalctl` timestamps carefully.

*Key learning: systemd service files are not just process launchers — they're operational contracts that must account for first-boot behavior.*

### Challenge 5: WebSocket IP Confusion

Workers were "running" and connecting successfully — but to the wrong endpoint (public IP instead of private IP). This made the system appear healthy at the service level while being broken at the application level. The diagnosis required reading iii-engine's internal logs, not just systemd status.

*Key learning: Service status != application correctness. Always verify functional behavior, not just process status.*

### Challenge 6: Greedy Decoding Repetition Loops in 270M SLM

During final E2E validation of the real Gemma-3 270M model, we observed that while the RPC pipeline was 100% operational, the model produced degenerate, repeating token sequences (e.g., "oooo..."). Due to their extremely small parameter size, SLMs are highly susceptible to feedback loops under default greedy decoding. We resolved this by implementing advanced sampling controls (repetition penalty, top_k, top_p, temperature, and hard n-gram repeat bans) which enabled highly creative, context-aware completions.

*Key learning: CPU-bound SLMs require fine-tuned decoding heuristics; standard defaults often lead to permanent sequence degeneration.*

---

## 10. Lessons Learned

### Technical

1. **Private subnet isolation is a routing property, not just a firewall property.** The private route table has no route from the internet — this is fundamentally more secure than a firewall rule that could be misconfigured.

2. **Outbound WebSocket RPC is a powerful pattern for private service communication.** Workers don't need inbound firewall rules, NAT punch-throughs, or service discovery — the engine holds the registry.

3. **Swap memory is not optional for constrained inference workloads.** CPU-based inference on small instances requires swap to prevent OOM kills during context allocation.

4. **Ansible dynamic inventory generation eliminates error-prone manual IP management.** Piping `terraform output -json` into a Python inventory generator means no manual copy-paste between tools.

5. **systemd is a production-grade service supervisor.** `Restart=on-failure`, `NoNewPrivileges`, `ProtectSystem=strict` — these aren't optional extras; they're the minimum viable security posture for a production service.

### Process

1. **Debugging distributed systems requires correlating logs from multiple sources simultaneously.** A symptom on one VM often has its root cause on a different VM or service.

2. **Infrastructure changes should be incremental and verifiable.** Making multiple changes simultaneously and hoping they all work is a recipe for untraceable failures.

3. **Documentation should be written during development, not after.** Debugging notes taken in the moment are far more accurate than reconstructed from memory.

---

## 11. Future Scalability Roadmap

For a production system serving real inference traffic, the following evolution path is recommended:

### Phase 1 — Security Hardening (Week 1-2)
- Replace self-signed SSL with ACM + ALB
- Remove SSH port 22 from all SGs, use SSM exclusively
- Migrate credentials to AWS Secrets Manager
- Add VPC Flow Logs and AWS GuardDuty

### Phase 2 — Reliability (Month 1)
- Deploy engine in **active-active multi-AZ** behind ALB
- Replace NAT Instance with managed NAT Gateway
- Add CloudWatch alarms for service health
- Implement `/ready` endpoint for worker registration health check

### Phase 3 — Scale (Month 2-3)
- Convert workers to **Auto Scaling Groups** triggered by SQS queue depth
- Containerize workers with Docker and deploy to EKS
- Pre-bake worker AMIs with Packer to eliminate cold-start delays
- Add Karpenter for automatic GPU node provisioning

### Phase 4 — 100× Model (Month 3+)
- Migrate inference to GPU instances (g5.xlarge, NVIDIA A10G)
- Deploy vLLM or TGI serving backend with PagedAttention + continuous batching
- Add model weight caching on EBS/S3 for fast pod startup
- Implement request queuing and async response delivery

---

## 12. Live Verification Gallery

Below is the verified evidence of the live AWS deployment, showcasing network hygiene, IaC correctness, and end-to-end RPC completion. Click on any section to expand the high-resolution proof.

<details>
  <summary>🖥️ <b>1. EC2 Console Dashboard — All 4 Instances Running</b></summary>
  <p>Shows the 4 purpose-built EC2 instances in a fully operational state, with the workers located inside isolated subnets.</p>
  <img src="../screenshots/ec2-dashboard.png" alt="EC2 Console Dashboard" width="900" style="border-radius: 8px; border: 1px solid #ddd; margin: 10px 0;">
</details>

<details>
  <summary>🌐 <b>2. AWS VPC Resource Map — public + private subnets</b></summary>
  <p>Visualizes the network architecture: the public subnet hosts the Engine/Nginx Gateway and the NAT Instance, while the private subnet hosts the caller-worker and inference-worker.</p>
  <img src="../screenshots/vpc-topology.png" alt="VPC Resource Map" width="900" style="border-radius: 8px; border: 1px solid #ddd; margin: 10px 0;">
</details>

<details>
  <summary>🏗️ <b>3. Terraform Apply Output — 24 Resources Provisioned</b></summary>
  <p>Consolidated output of a clean <code>terraform apply</code> provisioning VPCs, IAM policies, instance profiles, and instances.</p>
  <img src="../screenshots/terraform-apply.png" alt="Terraform Apply" width="900" style="border-radius: 8px; border: 1px solid #ddd; margin: 10px 0;">
</details>

<details>
  <summary>🤖 <b>4. Ansible Playbook Recap — 0 Failures</b></summary>
  <p>Execution recap of the complete Ansible automation playbook across all roles with zero failed runs.</p>
  <img src="../screenshots/ansible-complete.png" alt="Ansible Recap" width="900" style="border-radius: 8px; border: 1px solid #ddd; margin: 10px 0;">
</details>

<details>
  <summary>🔒 <b>5. Nginx Active Service Status — Edge Proxy Terminating TLS</b></summary>
  <p>Nginx serving on port 443 with security rate-limits and proxy-passing to loopback.</p>
  <img src="../screenshots/nginx-active.png" alt="Nginx Status" width="900" style="border-radius: 8px; border: 1px solid #ddd; margin: 10px 0;">
</details>

<details>
  <summary>⚡ <b>6. Central Broker iii-Engine Service Status</b></summary>
  <p>Active central broker running systemd supervisor, ready to orchestrate bidirectional RPC channels.</p>
  <img src="../screenshots/iii-engine-active.png" alt="iii-Engine Status" width="900" style="border-radius: 8px; border: 1px solid #ddd; margin: 10px 0;">
</details>

<details>
  <summary>⚙️ <b>7. Workers Active Service Status — inference-worker & caller-worker</b></summary>
  <p>Demonstrates isolated private subnet workers supervising their WebSocket loops cleanly.</p>
  <img src="../screenshots/workers-active.png" alt="Workers Status" width="900" style="border-radius: 8px; border: 1px solid #ddd; margin: 10px 0;">
</details>

<details>
  <summary>🩺 <b>8. /health Endpoint Verification (HTTP 200)</b></summary>
  <p>Smoke test verification response confirming the gateway proxy health state.</p>
  <img src="../screenshots/health-curl.png" alt="/health response" width="900" style="border-radius: 8px; border: 1px solid #ddd; margin: 10px 0;">
</details>

<details>
  <summary>🚀 <b>9. End-to-End Chat Completions Response (THE ULTIMATE PROOF)</b></summary>
  <p>The successful dynamic arithmetic completion payload routed Nginx → Engine → TS caller → Python worker → client.</p>
  <img src="../screenshots/completions-curl.png" alt="Completions API" width="900" style="border-radius: 8px; border: 1px solid #ddd; margin: 10px 0;">
</details>

---

## 13. Deliverables Checklist

The following deliverables specified in the assignment have all been completed:

### Code Deliverables

- [x] **IaC for VPC, subnets, VMs, firewall rules** → `terraform/` (24 Terraform resources)
- [x] **Deployment scripts for each worker** → `scripts/deploy.sh`, `scripts/deploy.ps1`
- [x] **systemd units for each service** → `systemd/*.service`

### Documentation Deliverables

- [x] **Architecture diagram** → ASCII + Mermaid in `README.md` and `ARCHITECTURE.md`
- [x] **Exact curl command + sample response** → `README.md`, `API_REFERENCE.md`
- [x] **Redeploy instructions** → `DEPLOYMENT.md` (step-by-step from scratch)
- [x] **Production hardening writeup** → `WRITEUP.md`, `SECURITY.md`
- [x] **100× scaling writeup** → `WRITEUP.md` § Scaling to 100× Model Size

### Evaluation Criteria

- [x] **Correctness** — API returns inference results end-to-end through RPC chain ✅
- [x] **Network hygiene** — Workers unreachable from internet (private subnet, no public IPs) ✅
- [x] **Reproducibility** — One-command deployment from clean AWS account ✅
- [x] **Clarity** — Documentation sufficient for a teammate to redeploy and debug ✅

---

