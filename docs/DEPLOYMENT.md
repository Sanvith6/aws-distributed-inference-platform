# Deployment Guide

This guide walks through the complete process of deploying the distributed AI inference platform from scratch — from AWS account setup through to live API verification. Each step includes commands, expected output, and what to do if something goes wrong.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [AWS Account Setup](#2-aws-account-setup)
3. [Configure Local Environment](#3-configure-local-environment)
4. [Terraform Infrastructure Provisioning](#4-terraform-infrastructure-provisioning)
5. [Ansible Configuration & Deployment](#5-ansible-configuration--deployment)
6. [Verify Deployment](#6-verify-deployment)
7. [SSH Access to Private VMs](#7-ssh-access-to-private-vms)
8. [One-Command Automated Deploy](#8-one-command-automated-deploy)
9. [Teardown & Cleanup](#9-teardown--cleanup)
10. [Redeployment from Scratch](#10-redeployment-from-scratch)

---

## 1. Prerequisites

### Required Tools

Install the following on your **local administrator machine** before starting:

| Tool | Required Version | Install Guide |
|---|---|---|
| **Terraform** | ≥ 1.5.0 | https://developer.hashicorp.com/terraform/install |
| **Ansible** | ≥ 2.15.0 | https://docs.ansible.com/ansible/latest/installation_guide/ |
| **Python** | ≥ 3.9 | https://www.python.org/downloads/ |
| **AWS CLI** | Any recent | https://aws.amazon.com/cli/ |
| **OpenSSH** | Any | Included on macOS/Linux; Git Bash/WSL on Windows |

### Verify Installations

```bash
terraform --version
# Terraform v1.5.0 or higher

ansible --version
# ansible [core 2.15.x] or higher

python3 --version
# Python 3.9.x or higher

aws --version
# aws-cli/2.x.x ...

ssh -V
# OpenSSH_8.x ...
```

### Windows Users

This project supports **both** native Ansible and WSL-based Ansible on Windows:

- **Option A (Recommended):** Install WSL2 with Ubuntu and run everything inside WSL
- **Option B:** Use the PowerShell scripts (`deploy.ps1`, `teardown.ps1`) which auto-detect WSL Ansible as a fallback

---

## 2. AWS Account Setup

### Create AWS Account

1. Sign up at https://aws.amazon.com
2. You receive **$100 free credits** plus Free Tier eligibility
3. Enable **MFA** on the root account immediately

### Create IAM User for Deployment

> **Never use the root account for deployments.**

1. Go to **IAM → Users → Create User**
2. Username: `devops-deployer`
3. Permissions: Attach these policies:
   - `AmazonEC2FullAccess`
   - `AmazonVPCFullAccess`
   - `IAMFullAccess`
   - `AmazonSSMFullAccess`
4. Create **Access Key** → Download CSV securely
5. **Store credentials safely** — you will need them in Step 3

### Verify IAM Permissions

```bash
aws iam get-user
# Should return your IAM user details
```

---

## 3. Configure Local Environment

### Set AWS Credentials

**Option A: Environment Variables (Recommended)**

```powershell
# PowerShell (Windows)
$env:AWS_ACCESS_KEY_ID     = "AKIA..."
$env:AWS_SECRET_ACCESS_KEY = "your-secret..."
$env:AWS_DEFAULT_REGION    = "us-east-1"
```

```bash
# Bash / WSL / macOS
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="your-secret..."
export AWS_DEFAULT_REGION="us-east-1"
```

**Option B: AWS CLI Configure**

```bash
aws configure
# AWS Access Key ID: AKIA...
# AWS Secret Access Key: ...
# Default region name: us-east-1
# Default output format: json
```

### Verify Authentication

```bash
aws sts get-caller-identity
```

Expected output:
```json
{
    "UserId": "AIDA...",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/devops-deployer"
}
```

### Clone Repository

```bash
git clone <your-repo-url>
cd devops
```

---

## 4. Terraform Infrastructure Provisioning

### Step 4.1 — Review Variables

Inspect `terraform/variables.tf` for configurable values. Optionally create a `terraform/terraform.tfvars` file:

```hcl
# terraform/terraform.tfvars (optional)

aws_region = "us-east-1"

# Restrict SSH to your IP for better security
my_ip = "1.2.3.4/32"    # Replace with your public IP

# Override instance types if needed
instance_types = {
  engine    = "t3.micro"
  caller    = "t3.micro"
  inference = "c7i-flex.large"
  nat       = "t3.micro"
}
```

Get your public IP:
```bash
curl -s https://ifconfig.me
```

### Step 4.2 — Initialize Terraform

```bash
cd terraform
terraform init
```

Expected output:
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Finding hashicorp/tls versions matching "~> 4.0"...
...
Terraform has been successfully initialized!
```

### Step 4.3 — Validate Configuration

```bash
terraform validate
terraform fmt -check
```

Expected: `Success! The configuration is valid.`

### Step 4.4 — Plan Infrastructure

```bash
terraform plan
```

Review the plan. You should see approximately **20 resources** to be created:
- 1 VPC
- 2 Subnets (public, private)
- 1 Internet Gateway
- 2 Route Tables + Associations
- 4 Security Groups
- 4 EC2 Instances
- 2 IAM Roles + 3 Policy Attachments + 2 Instance Profiles
- 1 Key Pair + 1 TLS Private Key + 1 Local File

### Step 4.5 — Apply Infrastructure

```bash
terraform apply -auto-approve
```

This takes approximately **2-4 minutes**. Expected final output:

```
Apply complete! Resources: 24 added, 0 changed, 0 destroyed.

Outputs:

engine_public_ip               = "54.x.x.x"
engine_private_ip              = "10.0.1.x"
inference_worker_private_ip    = "10.0.2.x"
caller_worker_private_ip       = "10.0.2.y"
ssh_command_engine             = "ssh -i iii-key.pem ubuntu@54.x.x.x"
ssh_command_inference          = "ssh -i iii-key.pem -o ProxyCommand=..."
ssh_command_caller             = "ssh -i iii-key.pem -o ProxyCommand=..."
```

> ✅ **Save the IP addresses** — you'll need them in the next steps.

### Step 4.6 — Verify EC2 Instances Are Running

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=iii-*" \
  --query "Reservations[].Instances[].{Name: Tags[?Key=='Name']|[0].Value, State: State.Name, IP: PublicIpAddress}" \
  --output table
```

All 4 instances should show `State: running`.

---

## 5. Ansible Configuration & Deployment

### Step 5.1 — Wait for SSH to Become Available

Instances need about 30-60 seconds after `terraform apply` before SSH is ready:

```bash
# Wait for SSH on the engine VM
ENGINE_IP=$(terraform output -raw engine_public_ip)
until ssh -i iii-key.pem -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$ENGINE_IP echo "SSH ready"; do
  echo "Waiting for SSH..."; sleep 10;
done
```

### Step 5.2 — Generate Ansible Inventory

The inventory file is generated dynamically from Terraform outputs:

```bash
cd ../ansible
terraform -chdir=../terraform output -json | python3 generate_inventory.py > inventory.ini
```

Verify the generated inventory:
```bash
cat inventory.ini
```

Expected structure:
```ini
[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=../terraform/iii-key.pem
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

[engine_gateway]
engine_gateway_vm ansible_host=54.x.x.x

[inference_worker]
inference_worker_vm ansible_host=10.0.2.x ansible_ssh_common_args='... ProxyCommand="ssh ... ubuntu@54.x.x.x"'

[caller_worker]
caller_worker_vm ansible_host=10.0.2.y ansible_ssh_common_args='... ProxyCommand="ssh ... ubuntu@54.x.x.x"'
```

### Step 5.3 — Test Ansible Connectivity

```bash
ENGINE_PRIV_IP=$(cd ../terraform && terraform output -raw engine_private_ip)

ansible all -i inventory.ini -m ping
```

Expected output:
```
engine_gateway_vm | SUCCESS => {"ping": "pong"}
inference_worker_vm | SUCCESS => {"ping": "pong"}
caller_worker_vm | SUCCESS => {"ping": "pong"}
```

> If connectivity fails, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md#wsl-ssh-issues).

### Step 5.4 — Run the Ansible Playbook

```bash
ENGINE_PRIV_IP=$(cd ../terraform && terraform output -raw engine_private_ip)

ansible-playbook -i inventory.ini playbook.yml \
  --extra-vars "engine_private_ip=$ENGINE_PRIV_IP"
```

The playbook executes **4 plays** across **5 roles**. This takes approximately **5-15 minutes** depending on network speed and package download times.

**What to expect during execution:**

```
PLAY [Apply common configurations to all nodes] ****
...
TASK [common : Install system packages] ***   (may take 2-3 min)

PLAY [Deploy Engine & Nginx API Gateway on VM1] ****
...
TASK [nginx : Generate self-signed SSL certificate] ***
TASK [engine : Install iii-engine globally] ***

PLAY [Deploy Python inference worker on VM2] ****
...
TASK [inference-worker : Install Python packages] ***  (may take 2-5 min)

PLAY [Deploy TypeScript caller worker on VM3] ****
...
TASK [caller-worker : Run npm install] ***

PLAY RECAP *****
engine_gateway_vm    : ok=XX   changed=YY   unreachable=0   failed=0
inference_worker_vm  : ok=XX   changed=YY   unreachable=0   failed=0
caller_worker_vm     : ok=XX   changed=YY   unreachable=0   failed=0
```

> ✅ All hosts must show `failed=0` and `unreachable=0`.

---

## 6. Verify Deployment

### Step 6.1 — Get the Engine Public IP

```bash
ENGINE_IP=$(cd terraform && terraform output -raw engine_public_ip)
echo "Engine IP: $ENGINE_IP"
```

### Step 6.2 — Health Check

```bash
curl -k "https://$ENGINE_IP/health"
```

Expected:
```json
{"status":"healthy","uptime":"active"}
```

### Step 6.3 — Inference API Test

```bash
curl -k -X POST "https://$ENGINE_IP/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "What is 2+2?"}
    ]
  }'
```

Expected response contains `choices[]`:
```json
{
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "The answer is 4."
      }
    }
  ],
  "text": "The answer is 4.",
  "success": "You've connected two workers..."
}
```

Exact wording can vary because this response is generated by the Gemma-3 270M GGUF model on the private inference worker. A successful deployment should not return the old hardcoded mock response or a `chat_template is not set` error.

### Step 6.4 — Verify systemd Services

SSH into VM1 and check service status:

```bash
ssh -i terraform/iii-key.pem ubuntu@$ENGINE_IP

# On VM1:
sudo systemctl status nginx
sudo systemctl status iii-engine
```

Both should show `active (running)`.

To verify worker services (via bastion hop):

```bash
# Get private IPs
INFERENCE_IP=$(cd terraform && terraform output -raw inference_worker_private_ip)
CALLER_IP=$(cd terraform && terraform output -raw caller_worker_private_ip)

# SSH to inference worker
ssh -i terraform/iii-key.pem \
  -o "ProxyCommand=ssh -i terraform/iii-key.pem -W %h:%p ubuntu@$ENGINE_IP" \
  ubuntu@$INFERENCE_IP \
  "sudo systemctl status inference-worker"

# SSH to caller worker
ssh -i terraform/iii-key.pem \
  -o "ProxyCommand=ssh -i terraform/iii-key.pem -W %h:%p ubuntu@$ENGINE_IP" \
  ubuntu@$CALLER_IP \
  "sudo systemctl status caller-worker"
```

Both should show `active (running)`.

### Step 6.5 — Use the Automated Test Script

```bash
# Bash
chmod +x scripts/test-api.sh && ./scripts/test-api.sh

# PowerShell
.\scripts\test-api.ps1

# Make
make test
```

---

## 7. SSH Access to Private VMs

Private VMs (VM2, VM3) have no public IPs. Access them through VM1 as a bastion jump host.

### Direct SSH Commands (from Terraform output)

```bash
# Engine (VM1) — direct
ssh -i terraform/iii-key.pem ubuntu@<ENGINE_PUBLIC_IP>

# Inference Worker (VM2) — via bastion
ssh -i terraform/iii-key.pem \
  -o StrictHostKeyChecking=no \
  -o ProxyCommand="ssh -i terraform/iii-key.pem -o StrictHostKeyChecking=no -W %h:%p ubuntu@<ENGINE_PUBLIC_IP>" \
  ubuntu@<INFERENCE_WORKER_PRIVATE_IP>

# Caller Worker (VM3) — via bastion
ssh -i terraform/iii-key.pem \
  -o StrictHostKeyChecking=no \
  -o ProxyCommand="ssh -i terraform/iii-key.pem -o StrictHostKeyChecking=no -W %h:%p ubuntu@<ENGINE_PUBLIC_IP>" \
  ubuntu@<CALLER_WORKER_PRIVATE_IP>
```

The exact SSH commands are in the Terraform outputs:

```bash
terraform output ssh_command_engine
terraform output ssh_command_inference
terraform output ssh_command_caller
```

### AWS Systems Manager (No SSH Key Required)

```bash
# List managed instances
aws ssm describe-instance-information --output table

# Open session
aws ssm start-session --target <INSTANCE_ID>
```

---

## 8. One-Command Automated Deploy

The `scripts/deploy.sh` (Bash) and `scripts/deploy.ps1` (PowerShell) scripts automate all steps above:

```bash
# Bash (macOS/Linux/WSL/Git Bash)
chmod +x scripts/deploy.sh
./scripts/deploy.sh

# PowerShell (Windows)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\deploy.ps1

# Make (Bash)
make deploy
```

The script:
1. Checks all prerequisite binaries
2. Verifies AWS CLI authentication
3. Runs `terraform init && apply`
4. Generates Ansible inventory
5. Waits 60s for SSH readiness
6. Runs Ansible playbook
7. Waits 60s for workers to connect
8. Verifies `/health` endpoint
9. Tests `/v1/chat/completions` with validation

---

## 9. Teardown & Cleanup

```bash
# Bash
chmod +x scripts/teardown.sh
./scripts/teardown.sh

# PowerShell
.\scripts\teardown.ps1

# Make
make destroy
```

This runs `terraform destroy -auto-approve` and deletes all AWS resources. **Verify in the AWS Console that all EC2 instances are terminated** to avoid unexpected charges.

---

## 10. Redeployment from Scratch

To completely rebuild the stack on a clean account:

```bash
# 1. Ensure Terraform state is clean
cd terraform
terraform show | head -5
# If state exists from a different account, remove it:
rm terraform.tfstate terraform.tfstate.backup

# 2. Re-run the full pipeline
cd ..
./scripts/deploy.sh

# 3. Verify
make test
```

---

## Common Deployment Issues

| Issue | Likely Cause | Solution |
|---|---|---|
| `Error: No valid credential sources found` | AWS creds not set | Run `aws configure` or set env vars |
| `UnauthorizedOperation` on EC2 | IAM user lacks EC2 permissions | Attach `AmazonEC2FullAccess` to IAM user |
| Ansible ping fails | SSH not ready yet | Wait 60s and retry |
| Ansible ping fails via ProxyCommand | Key permissions | Run `chmod 400 terraform/iii-key.pem` |
| `/health` returns 502 | iii-engine not started | SSH in, check `sudo journalctl -u iii-engine -n 50` |
| `/v1/chat/completions` times out | Workers not connected | Wait 2 min for worker registration, check logs |

> 📘 For detailed debugging of every failure mode, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).
