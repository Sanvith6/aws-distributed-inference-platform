# 📸 Screenshot Capture Guide — Live Commands

> **Engine Public IP:** `98.84.46.0`  
> **Engine Private IP:** `10.0.1.80`  
> **Inference Worker:** `10.0.2.209`  
> **Caller Worker:** `10.0.2.156`
>
> All commands below use your **real live IPs**. Run each in PowerShell, take a screenshot of the output, and save it to this `screenshots/` folder.

---

## 📋 HOW TO TAKE SCREENSHOTS ON WINDOWS

- **Quick snip:** Press `Win + Shift + S` → drag to select region → auto-saves to clipboard → paste into Paint / paste into file
- **Full terminal window:** `Win + Shift + S` then select the whole terminal
- **Save shortcut:** After `Win + Shift + S`, open `screenshots/` folder in File Explorer, press `Ctrl + V` to paste as PNG
- **Naming tip:** Use the numbered filenames listed below each section

---

## BLOCK 1 — Infrastructure Proofs (Local PowerShell)

### Screenshot 01 — Terraform Outputs (All IPs)

**File name:** `01-terraform-outputs.png`

Run in PowerShell from the `devops/` folder:
```powershell
cd c:\project\alchemist\devops\terraform
terraform output
```

**What you'll see:**
```
caller_worker_private_ip = "10.0.2.156"
engine_private_ip        = "10.0.1.80"
engine_public_ip         = "98.84.46.0"
inference_worker_private_ip = "10.0.2.209"
ssh_command_engine       = "ssh -i iii-key.pem ubuntu@98.84.46.0"
...
```
✅ **Why it's proof:** Shows Terraform successfully provisioned all 4 VMs with correct IP assignments.

---

### Screenshot 02 — Terraform State Resource Count

**File name:** `02-terraform-state-list.png`

```powershell
cd c:\project\alchemist\devops\terraform
terraform state list
```

✅ **Why it's proof:** Lists all 24 AWS resources Terraform is managing (VPC, subnets, EC2s, SGs, IAM, etc.).

---

### Screenshot 03 — AWS CLI — All EC2 Instances Running

**File name:** `03-ec2-instances-running.png`

```powershell
aws ec2 describe-instances `
  --filters "Name=tag:Name,Values=iii-*" `
  --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value, State:State.Name, Type:InstanceType, PublicIP:PublicIpAddress, PrivateIP:PrivateIpAddress}" `
  --output table
```

**What you'll see:** A table with all 4 VMs, their state (`running`), and IPs.  
✅ **Why it's proof:** Confirms all instances are live and VM2/VM3 have no public IP.

---

### Screenshot 04 — Health Check (API Gateway Working)

**File name:** `04-health-check.png`

```powershell
curl.exe -k "https://98.84.46.0/health"
```

**Expected output:**
```json
{"status":"healthy","uptime":"active"}
```
✅ **Why it's proof:** Proves Nginx + iii-engine are live and serving HTTPS traffic.

---

### Screenshot 05 — End-to-End Inference API (THE MOST IMPORTANT)

**File name:** `05-inference-api-response.png`

```powershell
curl.exe -k -X POST "https://98.84.46.0/v1/chat/completions" `
  -H "Content-Type: application/json" `
  -d '{"messages": [{"role": "user", "content": "What is 2+2? Answer briefly."}]}'
```

**Expected output:**
```json
{
  "choices": [{"message": {"role": "assistant", "content": "..."}}],
  "text": "...",
  "success": "You've connected two workers..."
}
```
✅ **Why it's proof:** Full end-to-end RPC chain — Nginx → Engine → TypeScript → Python → response.

---

### Screenshot 06 — Private Workers Have NO Public IP

**File name:** `06-private-worker-no-public-ip.png`

```powershell
aws ec2 describe-instances `
  --filters "Name=tag:Name,Values=iii-inference-worker" `
  --query "Reservations[0].Instances[0].{Name:Tags[?Key=='Name']|[0].Value, PublicIP:PublicIpAddress, PrivateIP:PrivateIpAddress, Subnet:SubnetId, State:State.Name}" `
  --output table
```

✅ **Why it's proof:** Shows `PublicIP: None` — proves network hygiene / private subnet isolation.

---

### Screenshot 07 — VPC and Subnet Info

**File name:** `07-vpc-subnet-info.png`

```powershell
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=iii-devops-vpc" --query "Vpcs[0].{VpcId:VpcId, CIDR:CidrBlock, Name:Tags[?Key=='Name']|[0].Value}" --output table

aws ec2 describe-subnets --filters "Name=vpc-id,Values=$(aws ec2 describe-vpcs --filters 'Name=tag:Name,Values=iii-devops-vpc' --query 'Vpcs[0].VpcId' --output text)" --query "Subnets[].{Name:Tags[?Key=='Name']|[0].Value, CIDR:CidrBlock, Public:MapPublicIpOnLaunch}" --output table
```

✅ **Why it's proof:** Shows the VPC layout with public and private subnets.

---

### Screenshot 08 — Security Group Rules (Engine)

**File name:** `08-security-group-engine.png`

```powershell
aws ec2 describe-security-groups --filters "Name=group-name,Values=iii-engine-sg" --query "SecurityGroups[0].IpPermissions[].{Port:FromPort, Protocol:IpProtocol, Source:IpRanges[0].CidrIp}" --output table
```

✅ **Why it's proof:** Shows :80, :443 open publicly + :49134 restricted to private subnet only.

---

### Screenshot 09 — Security Group Rules (Workers — No Public Ports)

**File name:** `09-security-group-workers.png`

```powershell
aws ec2 describe-security-groups --filters "Name=group-name,Values=iii-inference-sg" --query "SecurityGroups[0].{Name:GroupName, InboundRules:IpPermissions}" --output table
```

✅ **Why it's proof:** Shows workers have NO public HTTP/HTTPS ports — only SSH from bastion.

---

### Screenshot 10 — IAM Roles Created

**File name:** `10-iam-roles.png`

```powershell
aws iam list-roles --query "Roles[?contains(RoleName,'iii')].{Role:RoleName, Created:CreateDate}" --output table
```

✅ **Why it's proof:** Shows `iii-engine-role` and `iii-worker-role` with least-privilege IAM.

---

## BLOCK 2 — SSH Into VMs (Service Status Proofs)

> These commands SSH into the running VMs. Run them from:
> `c:\project\alchemist\devops\terraform\`

---

### Screenshot 11 — Nginx Active on VM1

**File name:** `11-nginx-active.png`

```powershell
cd c:\project\alchemist\devops\terraform
ssh -i iii-key.pem -o StrictHostKeyChecking=no ubuntu@98.84.46.0 "sudo systemctl status nginx --no-pager"
```

✅ Shows: `Active: active (running)` in green.

---

### Screenshot 12 — iii-engine Active on VM1

**File name:** `12-iii-engine-active.png`

```powershell
cd c:\project\alchemist\devops\terraform
ssh -i iii-key.pem -o StrictHostKeyChecking=no ubuntu@98.84.46.0 "sudo systemctl status iii-engine --no-pager"
```

✅ Shows: `Active: active (running)`.

---

### Screenshot 13 — Both Services Summary on VM1

**File name:** `13-vm1-services-summary.png`

```powershell
cd c:\project\alchemist\devops\terraform
ssh -i iii-key.pem -o StrictHostKeyChecking=no ubuntu@98.84.46.0 "sudo systemctl is-active nginx iii-engine && echo '✓ Both services ACTIVE'"
```

---

### Screenshot 14 — inference-worker Active on VM2

**File name:** `14-inference-worker-active.png`

```powershell
cd c:\project\alchemist\devops\terraform
ssh -i iii-key.pem -o StrictHostKeyChecking=no `
  -o ProxyCommand="ssh -i iii-key.pem -o StrictHostKeyChecking=no -W %h:%p ubuntu@98.84.46.0" `
  ubuntu@10.0.2.209 "sudo systemctl status inference-worker --no-pager"
```

✅ Shows VM2 is in private subnet, reachable only via bastion jump.

---

### Screenshot 15 — caller-worker Active on VM3

**File name:** `15-caller-worker-active.png`

```powershell
cd c:\project\alchemist\devops\terraform
ssh -i iii-key.pem -o StrictHostKeyChecking=no `
  -o ProxyCommand="ssh -i iii-key.pem -o StrictHostKeyChecking=no -W %h:%p ubuntu@98.84.46.0" `
  ubuntu@10.0.2.156 "sudo systemctl status caller-worker --no-pager"
```

---

### Screenshot 16 — Worker Registration in Engine Logs

**File name:** `16-worker-registration-logs.png`

```powershell
cd c:\project\alchemist\devops\terraform
ssh -i iii-key.pem -o StrictHostKeyChecking=no ubuntu@98.84.46.0 `
  "sudo journalctl -u iii-engine --no-pager -n 40 2>&1 | tail -30"
```

✅ **Why it's proof:** Shows WebSocket connections and worker function registrations in the engine logs.

---

### Screenshot 17 — NAT Instance Routing Works (Private VM reaches internet)

**File name:** `17-nat-routing-proof.png`

```powershell
cd c:\project\alchemist\devops\terraform
ssh -i iii-key.pem -o StrictHostKeyChecking=no `
  -o ProxyCommand="ssh -i iii-key.pem -o StrictHostKeyChecking=no -W %h:%p ubuntu@98.84.46.0" `
  ubuntu@10.0.2.209 "curl -s -o /dev/null -w 'HTTP Status: %{http_code}\nIP used: %{remote_ip}' https://httpbin.org/get && echo ' [NAT routing WORKS]'"
```

✅ **Why it's proof:** A VM with NO public IP successfully reached the internet through the NAT instance.

---

### Screenshot 18 — Private VM IP Confirmation (No Public IP)

**File name:** `18-private-vm-ip-proof.png`

```powershell
cd c:\project\alchemist\devops\terraform
ssh -i iii-key.pem -o StrictHostKeyChecking=no `
  -o ProxyCommand="ssh -i iii-key.pem -o StrictHostKeyChecking=no -W %h:%p ubuntu@98.84.46.0" `
  ubuntu@10.0.2.209 "echo 'Private IP:' && hostname -I && echo 'Public IP check (should fail/show NAT):' && curl -s --max-time 5 ifconfig.me"
```

✅ Shows `10.0.2.209` as the local IP — confirming no public IP on the inference worker.

---

### Screenshot 19 — Ansible Inventory (Dynamic IP Assignment)

**File name:** `19-ansible-inventory.png`

```powershell
cat c:\project\alchemist\devops\ansible\inventory.ini
```

✅ Shows the auto-generated inventory with bastion ProxyCommand for private VMs.

---

### Screenshot 20 — Full API Test via Test Script

**File name:** `20-test-script-pass.png`

```powershell
cd c:\project\alchemist\devops
.\scripts\test-api.ps1
```

✅ Shows the automated test script running and passing all validations.

---

## BLOCK 3 — AWS Console Screenshots (Browser)

Open **https://console.aws.amazon.com** and take these:

| # | Where to go | What to screenshot | File name |
|---|---|---|---|
| 21 | EC2 → Instances | All 4 instances green/Running | `21-ec2-dashboard.png` |
| 22 | EC2 → Instances → click inference-worker | Details panel: Public IP = blank, Private IP = 10.0.2.209 | `22-inference-worker-no-public-ip.png` |
| 23 | VPC → Your VPCs → iii-devops-vpc → Resource map tab | Full VPC topology showing public + private subnets | `23-vpc-resource-map.png` |
| 24 | VPC → Subnets | Both subnets: public (auto-assign IP = Yes) vs private (auto-assign IP = No) | `24-subnets-comparison.png` |
| 25 | VPC → Route tables → iii-private-rt → Routes tab | Shows 0.0.0.0/0 → eni-xxxx (NAT instance) | `25-private-route-table.png` |
| 26 | EC2 → Security Groups → iii-engine-sg → Inbound | Shows :80 :443 public + :49134 from 10.0.2.0/24 only | `26-engine-sg-rules.png` |
| 27 | EC2 → Security Groups → iii-inference-sg → Inbound | Shows only SSH from VM1 private IP | `27-worker-sg-rules.png` |
| 28 | IAM → Roles → search "iii" | Shows iii-engine-role and iii-worker-role | `28-iam-roles.png` |

---

## QUICK BATCH — Run All Local Commands at Once

Copy-paste this entire block into PowerShell to run all local proofs in sequence:

```powershell
$KEY = "c:\project\alchemist\devops\terraform\iii-key.pem"
$ENGINE = "98.84.46.0"
$VM2 = "10.0.2.209"
$VM3 = "10.0.2.156"

Write-Host "`n=== [1] TERRAFORM OUTPUTS ===" -ForegroundColor Cyan
cd c:\project\alchemist\devops\terraform; terraform output

Write-Host "`n=== [2] HEALTH CHECK ===" -ForegroundColor Cyan
curl.exe -k "https://$ENGINE/health"

Write-Host "`n=== [3] INFERENCE API ===" -ForegroundColor Cyan
curl.exe -k -X POST "https://$ENGINE/v1/chat/completions" -H "Content-Type: application/json" -d '{"messages":[{"role":"user","content":"What is 2+2?"}]}'

Write-Host "`n=== [4] EC2 INSTANCES ===" -ForegroundColor Cyan
aws ec2 describe-instances --filters "Name=tag:Name,Values=iii-*" --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,State:State.Name,Type:InstanceType,PublicIP:PublicIpAddress,PrivateIP:PrivateIpAddress}" --output table

Write-Host "`n=== [5] NGINX STATUS (VM1) ===" -ForegroundColor Cyan
ssh -i $KEY -o StrictHostKeyChecking=no ubuntu@$ENGINE "sudo systemctl status nginx --no-pager -l"

Write-Host "`n=== [6] ENGINE STATUS (VM1) ===" -ForegroundColor Cyan
ssh -i $KEY -o StrictHostKeyChecking=no ubuntu@$ENGINE "sudo systemctl status iii-engine --no-pager -l"

Write-Host "`n=== [7] INFERENCE-WORKER STATUS (VM2 via bastion) ===" -ForegroundColor Cyan
ssh -i $KEY -o StrictHostKeyChecking=no -o "ProxyCommand=ssh -i $KEY -o StrictHostKeyChecking=no -W %h:%p ubuntu@$ENGINE" ubuntu@$VM2 "sudo systemctl status inference-worker --no-pager -l"

Write-Host "`n=== [8] CALLER-WORKER STATUS (VM3 via bastion) ===" -ForegroundColor Cyan
ssh -i $KEY -o StrictHostKeyChecking=no -o "ProxyCommand=ssh -i $KEY -o StrictHostKeyChecking=no -W %h:%p ubuntu@$ENGINE" ubuntu@$VM3 "sudo systemctl status caller-worker --no-pager -l"

Write-Host "`n=== [9] ENGINE LOGS (worker registrations) ===" -ForegroundColor Cyan
ssh -i $KEY -o StrictHostKeyChecking=no ubuntu@$ENGINE "sudo journalctl -u iii-engine --no-pager -n 30"

Write-Host "`n=== [10] TERRAFORM STATE LIST ===" -ForegroundColor Cyan
cd c:\project\alchemist\devops\terraform; terraform state list

Write-Host "`n=== ALL CHECKS COMPLETE ===" -ForegroundColor Green
```

> 💡 **Tip:** Take **one big screenshot** of the entire terminal after running this batch — it shows everything at once.

---

## Priority Order (If Short on Time)

Take these 5 screenshots FIRST — they cover 100% of assignment evaluation criteria:

| Priority | Screenshot | Proves |
|---|---|---|
| 🥇 1 | `05-inference-api-response.png` | E2E RPC inference chain works |
| 🥈 2 | `03-ec2-instances-running.png` | All 4 VMs provisioned and running |
| 🥉 3 | `06-private-worker-no-public-ip.png` | Network hygiene — private subnet isolation |
| 4 | `11-nginx-active.png` + `12-iii-engine-active.png` | Services running on VM1 |
| 5 | `14-inference-worker-active.png` | Worker alive and reachable via bastion |
