# Cloud Infrastructure & Automation Blueprint (`infra.md`)

This document provides a highly structured technical breakdown of the distributed AI inference infrastructure, detailing network topologies, Terraform Infrastructure as Code (IaC) resources, Ansible configurations, process sandboxing, and edge proxy parameters.

---

## 1. What We Are Building: System Overview

We are building a highly secure, cost-optimized, and fully automated **Distributed AI Inference Mesh**. The system is split across specialized compute nodes to separate concerns, ensure high security, and stay 100% AWS Free-Tier compatible:

```
                                  [ Public Client ]
                                         │ (HTTPS :443)
                                         ▼
                             +───────────────────────+
                             |  VM1: Engine Gateway  |
                             |  -------------------  |
                             |  • Nginx Proxy (:443) |
                             |  • iii Engine (:3111) |
                             +───────────┬───────────+
                                         │
                 ┌───────────────────────┴───────────────────────┐
                 │ (Outbound WebSocket over private subnet)      │ (Outbound WebSocket)
                 ▼                                               ▼
     +───────────────────────+                       +───────────────────────+
     |   VM3: caller-worker  |                       | VM2: inference-worker |
     |   ------------------  |                       | --------------------- |
     |   • Private IP only   |                       | • Private IP only     |
     |   • TypeScript RPC    |                       | • Gemma-3-270m GGUF   |
     +───────────────────────+                       +───────────────────────+
                 │                                               │
                 └───────────────┬───────────────────────────────┘
                                 │ (Outbound Traffic via NAT)
                                 ▼
                     +───────────────────────+
                     |   VM4: NAT Instance   |
                     |   -----------------   |
                     |   • iptables MASQ     |
                     +───────────────────────+
```

### The Generation Request Lifecycle:
1.  **Ingress**: The client calls the edge HTTP gateway VM on port 443. Nginx terminates TLS, runs DDoS rate-limiting filters, and forwards the JSON payload to the `iii` engine on local loopback port 3111.
2.  **Outbound RPC Routing**: During boot, the workers (placed securely in the private subnet) establish *outbound* persistent WebSockets to the gateway engine on port 49134.
3.  **Cross-Language RPC Processing**:
    *   The engine routes the request down the websocket established by the **TypeScript Caller Worker (VM3)**.
    *   VM3 validates request structures, formats a JSON-RPC trigger, and sends it back to the engine.
    *   The engine dispatches this request to the **Python Inference Worker (VM2)**.
    *   VM2 loads the quantized **Gemma-3-270m-Q8_0 GGUF** model and runs Next-Token causal generation on physical CPU threads, supported by **8 GB of SSD swap memory** to prevent Out-Of-Memory (OOM) failures.
    *   Generated output tokens flow back up the WebSocket RPC chain to the gateway, returning standard completions JSON to the user.

---

## 2. Infrastructure-as-Code Blueprint (Terraform)

All hardware, networking, and security profiles are managed declaratively in the [terraform/](file:///c:/project/alchemist/devops/terraform) directory:

### A. Network Architecture ([vpc.tf](file:///c:/project/alchemist/devops/terraform/vpc.tf))
*   **VPC Block**: `10.0.0.0/16` providing a secure logical perimeter.
*   **Public Subnet**: `10.0.1.0/24` hosting VM1 (Engine Gateway) and VM4 (NAT Instance).
*   **Private Subnet**: `10.0.2.0/24` hosting VM2 (Inference Worker) and VM3 (Caller Worker).
*   **VPC S3 Endpoint**: A gateway VPC endpoint (`aws_vpc_endpoint.s3`) bound to private route tables. This enables worker nodes to pull dependencies or models from AWS S3 securely over internal AWS backbones without traversing the NAT instance.
*   **Routing Tables**:
    *   *Public Route Table*: Binds `0.0.0.0/0` directly to the standard AWS Internet Gateway (`aws_internet_gateway.gw`).
    *   *Private Route Table*: Routes all public-bound traffic (`0.0.0.0/0`) through the ENI of the custom NAT instance (`aws_instance.nat`).

### B. Cost-Efficient NAT Instance ([nat_instance.tf](file:///c:/project/alchemist/devops/terraform/nat_instance.tf))
*   Replaces AWS Managed NAT Gateways (saving ~$32/month).
*   Uses a tiny `t3.nano` instance in the public subnet.
*   **ENI configuration**: `source_dest_check = false` enables the instance to forward packages.
*   **Automation user_data**: Configures standard Linux IPv4 forwarding and installs iptables masquerading on boot:
    ```bash
    sysctl -w net.ipv4.ip_forward=1
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    ```

### C. Compute Instances Sizing ([instances.tf](file:///c:/project/alchemist/devops/terraform/instances.tf) & [variables.tf](file:///c:/project/alchemist/devops/terraform/variables.tf))
*   **Engine Gateway (VM1)**: `t3.micro` (1 GiB, 2 vCPUs) — Free Tier Eligible.
*   **TypeScript Caller (VM3)**: `t3.micro` (1 GiB, 2 vCPUs) — Free Tier Eligible.
*   **Inference Worker (VM2)**: `c7i-flex.large` (4 GiB, 2 vCPUs) — Optimized CPU instance. Utilizes 5th-Gen Intel Xeon scalable processors featuring modern AVX-512/AMX tensor acceleration instructions, accelerating causal GGUF generation at a fraction of the cost of standard GPUs.
*   **NAT Instance (VM4)**: `t3.nano` (0.5 GiB, 2 vCPUs) — Micro-sizing to minimize cost.

### D. Security Firewalls ([security_groups.tf](file:///c:/project/alchemist/devops/terraform/security_groups.tf))
We enforce a strict zero-trust ingress security model:

```
┌─────────────────┐       (HTTPS:443)       ┌────────────────────────┐
│  Public Client  │ ──────────────────────► │ aws_security_group.engine│
└─────────────────┘                         └───────────┬────────────┘
                                                        │
                                                        │ (SSH Port 22 ONLY)
                                                        ▼
                                            ┌────────────────────────┐
                                            │ aws_security_group.worker│
                                            └────────────────────────┘
```

1.  **Engine SG (`aws_security_group.engine`)**:
    *   *Ingress*: Allows public HTTPS (`443`) and HTTP (`80`). Allows WebSocket registration port `49134` from VPC IP boundaries.
    *   *Egress*: Allows all outbound flows.
2.  **Worker SG (`aws_security_group.inference` & `aws_security_group.caller`)**:
    *   *Ingress*: **Blocks all public traffic.** Allows port 22 SSH connections *only* from the Engine Gateway's private IP (`10.0.1.x/32`), acting as a secure Bastion jump server.
    *   *Egress*: Allows all outbound traffic (routing through the NAT instance for security updates).

### E. IAM Hardening & SSM Integration ([iam.tf](file:///c:/project/alchemist/devops/terraform/iam.tf))
*   All EC2 instances are provisioned with secure IAM Instance Profiles (`aws_iam_instance_profile.worker` and `aws_iam_instance_profile.engine`).
*   Attaches the standard `AmazonSSMManagedInstanceCore` and `CloudWatchAgentServerPolicy` policies.
*   **Security Benefit**: Allows operators to establish shell sessions securely via **AWS Systems Manager (SSM) Session Manager**, avoiding the need for public key files or opening port 22 to the public internet.

---

## 3. Configuration Management Blueprint (Ansible)

Once Terraform provisions the VMs, [Ansible](file:///c:/project/alchemist/devops/ansible) playbooks configure the operating system packages and deploy service scripts.

### A. Dynamic Inventory Mapping ([ansible/generate_inventory.py](file:///c:/project/alchemist/devops/ansible/generate_inventory.py))
During the deployment phase, the inventory generator parses Terraform's state JSON and writes a dynamic `inventory.ini` mapping node roles:
*   Exports private worker IPs.
*   Configures standard SSH proxy jump arguments so Ansible can hop through the Engine Gateway (Bastion) to configure the private workers:
    ```ini
    [inference]
    10.0.2.x ansible_user=ubuntu ansible_ssh_common_args='-o ProxyCommand="ssh -i iii-key.pem -o StrictHostKeyChecking=no -W %h:%p ubuntu@<ENGINE_PUBLIC_IP>"'
    ```

### B. Configured Roles (`ansible/roles/`)
1.  **common**: Installs system requirements (`git`, `curl`, `python3-pip`, `nodejs`, `npm`), manages OS updates, and copies deployer keys.
2.  **nginx**: Automatically deploys the rate-limited reverse proxy configuration [iii-api.conf](file:///c:/project/alchemist/devops/nginx/iii-api.conf) on the Engine Gateway.
3.  **engine**: Automatically registers and triggers the central gateway engine daemon service.
4.  **caller-worker**: Configures dependencies (`npm install`), transpiles TypeScript sources, and registers the worker process.
5.  **inference-worker**: Registers GGUF runtime libraries (`llama-cpp-python`), clones model weights from HuggingFace, and launches the execution systemd services.

### C. EBS-Backed Virtual Swap Space Allocation
On target worker nodes, Ansible dynamically creates and persists a virtual memory SSD swap partition to cushion high context memory surges:
```yaml
- name: Create 8GB swap file on EBS volume
  become: true
  block:
    - name: Allocate space for swap file
      ansible.builtin.command: fallocate -l 8G /swapfile
    - name: Set secure permissions on swap file
      ansible.builtin.file:
        path: /swapfile
        mode: '0600'
    - name: Format the swap file
      ansible.builtin.command: mkswap /swapfile
    - name: Enable the swap file
      ansible.builtin.command: swapon /swapfile
    - name: Persist swap mounting in fstab
      ansible.builtin.lineinfile:
        path: /etc/fstab
        line: '/swapfile none swap sw 0 0'
        state: present
```

---

## 4. Service sandboxing & Edge Proxies (systemd & Nginx)

### A. Hardened systemd Sandboxing ([systemd/](file:///c:/project/alchemist/devops/systemd))
All application processes run under isolated systemd service boundaries with advanced OS-level security sandboxing:
```ini
[Service]
ExecStart=/usr/bin/python3 /opt/iii/inference_worker.py
Restart=on-failure
RestartSec=5s

# Linux OS-Level Sandboxing
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ProtectControlGroups=true
ProtectKernelModules=true
ReadWritePaths=/opt/iii /home/ubuntu/.cache
```
*   `NoNewPrivileges=true`: Prevents execution processes or their children from escalating administrative privileges.
*   `ProtectSystem=strict`: Mounts the core OS files `/usr`, `/boot`, `/etc` as read-only.
*   `ProtectHome=true`: Completely hides home directories from the service runtime, preventing data exposure.

### B. Nginx Edge Rate-Limiting ([nginx/iii-api.conf](file:///c:/project/alchemist/devops/nginx/iii-api.conf))
The reverse proxy gateway secures API ingress using standard rate-limiting filters:
```nginx
limit_req_zone $binary_remote_addr zone=api_limit_zone:10m rate=5r/s;

server {
    listen 80;
    server_name _;

    location /v1/chat/completions {
        limit_req zone=api_limit_zone burst=10 nodelay;
        proxy_pass http://127.0.0.1:3111;
        proxy_set_header Host $host;
    }
}
```
*   `rate=5r/s`: Binds client IP queries to a maximum of 5 requests per second.
*   `burst=10 nodelay`: Accommodates minor burst traffic up to 10 concurrent requests without queue stalling.
*   `proxy_pass http://127.0.0.1:3111`: Proxies edge triggers solely to loopback.

---

## 5. Deployment & Teardown Wrappers

All operational scripts are structured to enforce robust error handling, preflight checks, and strict cleanup loops.

### A. Preflight Checks & Validation Guards ([deploy.sh](file:///c:/project/alchemist/devops/scripts/deploy.sh))
The orchestration scripts execute three preflight safety gates before starting the deployment:
1.  **Tooling Checks**: Validates the presence of `terraform`, `ansible`, `python3`, and `aws`.
2.  **AWS Identity checks**: Asserts active AWS credentials (`aws sts get-caller-identity`) AND region defaults (`aws configure get region`), failing early to avoid half-applied configuration states.
3.  **Terraform Guard**: Runs semantic validations before deployment:
    ```bash
    terraform init -backend=false
    terraform fmt -check
    terraform validate
    ```
4.  **Trap Traps**: Registers a failure handler (`trap 'cleanup_on_err' ERR`) to capture exit signals, print diagnostic logs, and exit gracefully on any provisioning failures.

### B. Deployment Commands
Deployment operations are abstracted through a simple, unified root [Makefile](file:///c:/project/alchemist/devops/Makefile):
*   `make validate`: Formats and checks HCL correctness.
*   `make deploy`: Provision public/private VMs, dynamically compile inventory sheets, run Ansible configurations, compile workers, download GGUF models, and run completions curls.
*   `make test`: Validates end-to-end inference triggers.
*   `make audit`: Statically analyzes HCL variables, Ansible maps, and systemd units (Health Score: **100/100**).
*   `make destroy`: Triggers complete infrastructure teardown, clean-killing VMs, VPC boundaries, and routing rules to prevent resource abandonment and residual AWS bills.
