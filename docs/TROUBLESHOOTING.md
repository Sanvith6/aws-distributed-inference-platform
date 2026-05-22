# Troubleshooting Guide — Debugging Journal

This document chronicles every significant issue encountered during the build and deployment of this distributed inference platform, along with the exact diagnosis steps and fixes applied. It serves as both an operational runbook and a candid record of the debugging journey.

> **A note on transparency:** Real DevOps work involves diagnosing unexpected failures. This journal is intentionally candid — documenting the root causes, not just the fixes — because understanding *why* failures happen is more valuable than knowing just *what* to run.

---

## Table of Contents

1. [NAT Instance Routing Failure](#1-nat-instance-routing-failure)
2. [apt Package Lock (dpkg Busy)](#2-apt-package-lock-dpkg-busy)
3. [PyTorch CUDA Wheel Disk Exhaustion](#3-pytorch-cuda-wheel-disk-exhaustion)
4. [WSL SSH ProxyCommand Failures](#4-wsl-ssh-proxycommand-failures)
5. [systemd Service Restart Loops](#5-systemd-service-restart-loops)
6. [WebSocket Registration Failures](#6-websocket-registration-failures)
7. [GGUF Runtime Instability](#7-gguf-runtime-instability)
8. [Python Logger Crash (AttributeError)](#8-python-logger-crash-attributeerror)
9. [Ansible Inventory Encoding Issues](#9-ansible-inventory-encoding-issues)
10. [iii-engine CLI Flag Incompatibility](#10-iii-engine-cli-flag-incompatibility)
11. [inference-worker Startup Timeout](#11-inference-worker-startup-timeout)
12. [Nginx 502 Bad Gateway on Engine Restart](#12-nginx-502-bad-gateway-on-engine-restart)

---

## 1. NAT Instance Routing Failure

### Symptoms
- Private subnet instances (VM2, VM3) cannot reach the internet
- `apt-get update` hangs indefinitely on the inference worker
- `curl https://pypi.org` times out from the private VM
- Package installation never completes via Ansible

### Root Cause
AWS EC2 instances have **source/destination check** enabled by default. This means an instance only accepts packets where the source or destination IP matches its own assigned IP. A NAT instance needs to *forward* packets for other IPs — but AWS was silently dropping them because the check was still enabled.

Additionally, the kernel's IP forwarding sysctl was confirmed to be set (`net.ipv4.ip_forward=1`) but the `iptables MASQUERADE` rule was missing — packets were being forwarded but not having their source IP rewritten, so responses couldn't return correctly.

### Diagnosis Steps

```bash
# 1. Check if private VM can reach anything at all
ssh <bastion> ubuntu@<private-vm> "ping -c 3 8.8.8.8"
# Result: 100% packet loss

# 2. Verify route table is pointing to NAT ENI
aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=iii-private-rt" \
  --query "RouteTables[0].Routes"
# Result: 0.0.0.0/0 → eni-xxxxxxxx (NAT instance ENI)

# 3. SSH into NAT instance and verify forwarding
ssh ubuntu@<nat-public-ip>
cat /proc/sys/net/ipv4/ip_forward   # Expected: 1
sudo iptables -t nat -L -n -v        # Expected: MASQUERADE rule
# Result: ip_forward = 1 but NO MASQUERADE rule

# 4. Check AWS console: source/dest check
aws ec2 describe-instance-attribute \
  --instance-id <nat-instance-id> \
  --attribute sourceDestCheck
# Result: {"SourceDestCheck": {"Value": true}}  ← BUG
```

### Fix Applied

In `terraform/nat_instance.tf`:

```hcl
resource "aws_instance" "nat" {
  # ...
  source_dest_check = false   # CRITICAL — must be false for NAT routing
}
```

And in the `user_data` bootstrap script:

```bash
# Ensure iptables MASQUERADE is applied on the correct interface
DEFAULT_INTERFACE=$(ip route show | awk '/default/ {print $5}')
iptables -t nat -A POSTROUTING -o "$DEFAULT_INTERFACE" -j MASQUERADE
```

### Prevention Strategy
- Always set `source_dest_check = false` in Terraform for NAT instances — it's easy to miss because there's no visible error; packets are silently dropped
- Add an explicit check in the deployment pipeline: SSH into NAT instance and verify `iptables -t nat -L` before running Ansible
- Consider adding a Terraform check or Ansible pre-task that validates internet connectivity from private VMs before proceeding

---

## 2. apt Package Lock (dpkg Busy)

### Symptoms
- Ansible tasks fail with: `E: Could not get lock /var/lib/dpkg/lock-frontend`
- Affects the `common` role's `apt-get update` and `apt-get install` tasks
- Occurs intermittently — sometimes the same playbook succeeds without changes

### Root Cause
Ubuntu cloud instances run **`unattended-upgrades`** automatically shortly after boot. This background process holds an exclusive lock on the dpkg database. When Ansible runs apt tasks concurrently, both processes try to acquire the same lock and one fails.

### Diagnosis Steps

```bash
# SSH into affected VM
ssh ubuntu@<vm-ip>

# Check what's holding the lock
sudo lsof /var/lib/dpkg/lock-frontend
# Result: unattended-upgrades process PID

# Check if auto-upgrade is running
systemctl status unattended-upgrades
# Result: active (running) — exactly when dpkg is locked
```

### Fix Applied

Added a pre-task in the Ansible `common` role to wait for the lock to be released:

```yaml
- name: Wait for apt lock to be released
  shell: |
    while fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock >/dev/null 2>&1; do
      echo "Waiting for apt lock..."
      sleep 5
    done
  changed_when: false
```

### Prevention Strategy
- Always wait for apt lock in the `common` role — this is a standard pattern for cloud instance configuration
- Alternatively, increase `WaitForConnection` delays in Ansible before running apt tasks
- Add `DEBIAN_FRONTEND=noninteractive` to apt commands to prevent interactive prompts

---

## 3. PyTorch CUDA Wheel Disk Exhaustion

### Symptoms
- `pip install llama-cpp-python` or `pip install torch` fails partway through
- Error: `No space left on device` during wheel extraction
- Ansible task for Python package installation fails and rolls back
- VM2 (inference worker) runs out of disk space mid-deployment

### Root Cause
The CUDA-enabled wheel for PyTorch is approximately **800MB–2GB** uncompressed. The default root volume on `t3.micro` / `c7i-flex.large` is typically **8GB** — which is consumed by the OS, Python packages, and the model download combined. The wheel would begin extracting and then fail when disk space ran out.

Additionally, pip's default temporary directory is `/tmp` — itself on the root volume — so even the extraction stage exhausted space before installation completed.

### Diagnosis Steps

```bash
# Check disk usage
df -h
# Result: /dev/root 7.9G 7.8G 0 100% /

# Check what's using the space
sudo du -sh /opt/iii /tmp /var/cache/apt
# Result: /tmp had 1.8GB of partially extracted wheels

# Check pip download cache
pip cache info
# Result: cache directory at ~/.cache/pip with several GB of wheels
```

### Fix Applied

**Strategy shift:** Abandoned CUDA wheel entirely and used the CPU-only llama.cpp backend. The inference worker runs SLM inference on CPU cores (with swap memory to compensate for RAM limits):

```bash
# CPU-only build — avoids GPU wheel entirely
pip install llama-cpp-python --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cpu

# Also: add swap to prevent OOM during inference
fallocate -l 8G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

**Root volume size** is also set to `20GB` in the Terraform instances config to provide headroom.

### Prevention Strategy
- Always configure swap on inference VMs — 8GB swap makes CPU-only inference stable on 4GB RAM instances
- Use `pip install --no-cache-dir` to avoid pip's cache filling the disk
- Size the root EBS volume appropriately (20GB minimum for inference workers)
- Consider placing pip cache on a separate EBS volume

---

## 4. WSL SSH ProxyCommand Failures

### Symptoms
- Ansible `ping` to private subnet VMs fails when running from Windows PowerShell
- Error: `ssh: connect to host ... port 22: Connection refused` (through the ProxyCommand)
- Direct SSH to VM1 (public) works fine
- The exact same Ansible inventory works fine when run from Linux/macOS

### Root Cause
Windows does not natively support the Ansible `ProxyCommand` syntax for SSH bastion hops. The inventory's `ProxyCommand` uses Linux-style paths (e.g., `../terraform/iii-key.pem`), which Windows OpenSSH interprets as Windows paths — causing path resolution failures.

Additionally, the PEM file written by Terraform on Windows has Windows line endings (`\r\n`) and Windows file permissions — both of which cause OpenSSH to reject the key with `WARNING: UNPROTECTED PRIVATE KEY FILE!`.

### Diagnosis Steps

```powershell
# Try running ansible ping manually
ansible all -i inventory.ini -m ping -vvv
# Error: Permission denied (publickey)

# Check SSH key permissions in WSL
wsl ls -la /tmp/iii-key.pem
# Result: -rw-rw-rw- (permissions too open — SSH rejects it)

# Try the ProxyCommand manually from Windows CMD
ssh -o "ProxyCommand=ssh -i C:\path\key.pem -W %h:%p ubuntu@<public-ip>" ubuntu@<private-ip>
# Error: path resolution fails
```

### Fix Applied

The `deploy.ps1` PowerShell script implements a **WSL fallback strategy**:

```powershell
if ($UseWSLAnsible) {
    # Copy key to WSL /tmp with correct permissions
    wsl -d Ubuntu sh -c "cp ../terraform/iii-key.pem /tmp/iii-key.pem && chmod 400 /tmp/iii-key.pem"

    # Generate WSL-compatible inventory (Linux paths)
    (Get-Content inventory.ini) -replace '\.\.\/terraform\/iii-key\.pem', '/tmp/iii-key.pem' |
      Out-File -Encoding ascii inventory_wsl.ini

    # Run Ansible inside WSL
    wsl -d Ubuntu sh -c "ansible-playbook -i inventory_wsl.ini playbook.yml ..."
}
```

### Prevention Strategy
- On Windows, **always run Ansible from inside WSL** for projects that use SSH ProxyCommand
- Use `chmod 400` immediately after copying SSH keys to WSL — never run with open permissions
- The `deploy.ps1` auto-detects WSL and handles this automatically — this is the recommended Windows path

---

## 5. systemd Service Restart Loops

### Symptoms
- `sudo systemctl status inference-worker` shows `activating (start)` repeatedly
- `sudo journalctl -u inference-worker -n 50` shows the service starting and immediately exiting
- Service appears "active" momentarily and then crashes within seconds
- `Active: activating (start) ... 3 restarts`

### Root Cause
Multiple sub-causes were found and fixed individually:

**A) Wrong `III_URL` environment variable:** The systemd unit file was templated with a placeholder `ENGINE_PRIVATE_IP` that wasn't substituted during deployment. The worker connected to `ws://ENGINE_PRIVATE_IP:49134` literally, which failed DNS resolution instantly.

**B) Missing Python virtual environment:** The `ExecStart` path pointed to `/opt/iii/workers/inference-worker/venv/bin/python` before the Ansible role had created the venv, causing an immediate `No such file or directory` exit.

**C) Insufficient startup timeout:** The model download (540MB GGUF) takes 2-3 minutes on a slow NAT connection. The default `TimeoutStartSec=90` expired before the model finished loading, and systemd killed the process.

### Diagnosis Steps

```bash
# Check the last few log lines with timestamps
sudo journalctl -u inference-worker -n 50 --no-pager

# Check the exact error
sudo journalctl -u inference-worker -n 5 --no-pager | grep -E "Error|Failed|No such"

# Verify environment variable substitution
sudo systemctl show inference-worker -p Environment
# Result: Environment=III_URL=ws://ENGINE_PRIVATE_IP:49134  ← literal placeholder!

# Verify venv exists
ls -la /opt/iii/workers/inference-worker/venv/bin/python
```

### Fix Applied

**A)** Ansible templates the service file with Jinja2 variable substitution:

```yaml
# ansible/roles/inference-worker/tasks/main.yml
- name: Deploy inference-worker systemd service
  template:
    src: inference-worker.service.j2
    dest: /etc/systemd/system/inference-worker.service
  vars:
    engine_private_ip: "{{ engine_private_ip }}"   # passed via --extra-vars
```

**B)** Added explicit venv creation step *before* the service deployment task in the Ansible role.

**C)** Extended `TimeoutStartSec` to 300 seconds in the service unit:

```ini
[Service]
TimeoutStartSec=300    # Allow 5 minutes for model download on first boot
```

### Prevention Strategy
- Always verify Jinja2 template substitution in Ansible by running `ansible-playbook --check` first
- Check service unit `ExecStart` paths match the actual deployment paths before starting
- For services that download large files on first boot, always set generous `TimeoutStartSec`

---

## 6. WebSocket Registration Failures

### Symptoms
- `/v1/chat/completions` returns `502 Bad Gateway` or `{"error": "No handler registered"}`
- `/health` returns 200 (Nginx and engine are up) but inference fails
- `sudo journalctl -u iii-engine` shows no connected workers in the registry
- Both workers appear `active (running)` in systemctl but nothing works

### Root Cause
The workers were running but connecting to the **wrong WebSocket address**. The `III_URL` environment variable in the systemd service was set to the engine's *public IP* (`ws://54.x.x.x:49134`) instead of its *private IP* (`ws://10.0.1.x:49134`).

The engine's security group restricted WebSocket port 49134 to `10.0.2.0/24` (private subnet CIDR) only — so connections from the workers' private IPs to the engine's *public IP* were being routed via the internet and rejected by the security group.

### Diagnosis Steps

```bash
# From the inference worker VM
curl -I https://engine-public-ip:49134  # Should fail
curl -I http://engine-private-ip:49134  # Should succeed

# Check what III_URL is actually set to
sudo systemctl show inference-worker -p Environment
# Result: III_URL=ws://54.x.x.x:49134  ← public IP, wrong!

# Check iii-engine logs for connection attempts
sudo journalctl -u iii-engine -n 100 --no-pager | grep -E "connect|register|worker"
```

### Fix Applied

Updated the Ansible template to always use the **private IP** of the engine:

```ini
# inference-worker.service.j2
[Service]
Environment=III_URL=ws://{{ engine_private_ip }}:49134
```

And added the engine private IP as a required `--extra-vars` in the playbook:

```bash
ansible-playbook -i inventory.ini playbook.yml \
  --extra-vars "engine_private_ip=$(terraform output -raw engine_private_ip)"
```

### Prevention Strategy
- Always use **private IPs** for intra-VPC communication — public IPs incur data transfer costs and traverse the internet
- Validate `III_URL` substitution before starting services
- Add a health check in Ansible that verifies worker registration after service start

---

## 7. GGUF Runtime Instability

### Symptoms
- `inference-worker` starts successfully, loads model, then crashes after 1-2 inference calls
- OOM killer terminates the Python process: `dmesg | grep -i oom` shows kills
- Model loading itself succeeds (no error during startup) but fails under load
- Memory usage spikes to 100% during token generation

### Root Cause
The `gemma-3-270m-Q8_0.gguf` model consumes approximately **290MB** of RAM when loaded. During active inference, `llama.cpp` allocates additional memory for the KV-cache and context buffers. On a 4GB RAM instance *without swap*, this pushed total memory beyond available physical RAM, triggering Linux OOM kills.

### Diagnosis Steps

```bash
# Check OOM events
sudo dmesg | grep -E "oom|killed" | tail -20
# Result: "Out of memory: Killed process XXXX (python)"

# Check memory usage during inference
free -h
# Result: total: 3.8G, used: 3.7G, free: 0.1G

# Check swap status
swapon --show
# Result: (empty) — no swap configured!
```

### Fix Applied

Added an 8GB swap file configuration in the `common` Ansible role:

```yaml
- name: Create 8GB swap file
  command: fallocate -l 8G /swapfile
  args:
    creates: /swapfile

- name: Set swap file permissions
  file:
    path: /swapfile
    mode: '0600'

- name: Configure swap file
  command: mkswap /swapfile
  when: ansible_swaptotal_mb < 1024

- name: Enable swap
  command: swapon /swapfile

- name: Persist swap in fstab
  lineinfile:
    path: /etc/fstab
    line: '/swapfile none swap sw 0 0'
    state: present
```

### Prevention Strategy
- **Always configure swap on inference VMs** — non-negotiable for any LLM deployment on commodity hardware
- Monitor memory usage during the first inference call using `htop` before declaring the deployment stable
- For production, use instance types with sufficient RAM (e.g., `r6i.xlarge` with 32 GiB RAM)

---

## 8. Python Logger Crash (AttributeError)

### Symptoms
- Inference worker crashes immediately on startup with:
  ```
  AttributeError: 'Logger' object has no attribute 'warning'
  ```
- The traceback points to `inference_worker.py` at the logger initialization
- The `iii` Python SDK Logger class doesn't expose the expected `.warning()` method

### Root Cause
The `iii` SDK's `Logger` class is a thin wrapper that exposes only `.info()`, `.error()`, and `.debug()` methods — not the standard Python `logging.Logger` interface. Early versions of the inference worker script used `logger.warning(...)` calls which matched the Python stdlib logger but not the iii SDK logger.

### Diagnosis Steps

```bash
# Reproduce by running the script manually in the venv
cd /opt/iii/workers/inference-worker
./venv/bin/python inference_worker.py
# AttributeError: 'Logger' object has no attribute 'warning'

# Inspect the iii SDK logger
./venv/bin/python -c "from iii import Logger; l = Logger(); print(dir(l))"
# ['__class__', ..., 'debug', 'error', 'info']  — no 'warning'
```

### Fix Applied

Replaced all `logger.warning(...)` calls with `logger.info(...)` or native Python `print()`:

```python
# Before
logger.warning("Model download may take several minutes...")

# After
logger.info("Model download may take several minutes...")
```

### Prevention Strategy
- When using third-party SDK loggers, inspect the available methods before using them
- Write a quick smoke test that imports and initializes the logger before deploying
- The iii SDK documentation clarifies supported log levels

---

## 9. Ansible Inventory Encoding Issues

### Symptoms
- Ansible inventory file generated by `generate_inventory.py` contains Windows-style `\r\n` line endings when run from PowerShell
- Ansible fails to parse the inventory with cryptic errors about invalid characters
- Running the same script from WSL/Bash produces a working inventory; PowerShell version fails

### Root Cause
Python's default file I/O on Windows uses the system's default line ending (`\r\n`). When `generate_inventory.py` writes to stdout and PowerShell redirects that output to a file, Windows inserts `\r\n` line endings. The OpenSSH `ProxyCommand` string in the inventory contains embedded quotes and spaces — with `\r` characters injected, the SSH command parsing breaks.

### Diagnosis Steps

```powershell
# Check the file for Windows line endings
Format-Hex ansible/inventory.ini | Select-String "0d 0a"
# Result: Found — confirms \r\n line endings

# Check what ansible-inventory sees
ansible-inventory -i inventory.ini --list
# Error: invalid or unexpected token at line X
```

### Fix Applied

Updated the PowerShell deploy script to explicitly write ASCII with Unix line endings:

```powershell
# deploy.ps1
$tfJson | python generate_inventory.py > inventory.ini

# Convert to Unix line endings for Ansible
(Get-Content inventory.ini -Raw).Replace("`r`n", "`n") | 
  [System.IO.File]::WriteAllText("$PWD\inventory.ini", $_)
```

Also added the `Out-File -Encoding ascii` flag to the WSL inventory generation:

```powershell
(Get-Content inventory.ini) -replace '\.\.\/terraform\/iii-key\.pem', '/tmp/iii-key.pem' | 
  Out-File -Encoding ascii inventory_wsl.ini
```

### Prevention Strategy
- Always use explicit encoding when writing Ansible inventory files from Windows
- Test inventory parsing with `ansible-inventory -i inventory.ini --list` before running the playbook
- Consider using `.gitattributes` to enforce Unix line endings for `.ini` files in the repository

---

## 10. iii-engine CLI Flag Incompatibility

### Symptoms
- `iii-engine.service` fails to start with error: `unknown flag: --no-watch`
- Installed iii-engine version is newer than expected
- The service start command `iii start --no-watch` is rejected

### Root Cause
The `iii` CLI changed its command interface between versions. The `--no-watch` flag that disables file watching (needed in production to prevent CPU overhead) was renamed or removed in a newer release.

### Diagnosis Steps

```bash
# Check iii version
iii --version

# Check available flags
iii start --help
# Result: flag provided but not defined: --no-watch
```

### Fix Applied

Removed the `--no-watch` flag from the systemd `ExecStart`:

```ini
# Before
ExecStart=/usr/local/bin/iii start --no-watch

# After
ExecStart=/usr/local/bin/iii start
```

The production mode (watching disabled) is configured via the `config.yaml` environment setting `NODE_ENV=production`.

### Prevention Strategy
- Pin the iii-engine npm version in the Ansible install task to avoid breaking changes
- Run `iii start --help` as a validation step in the Ansible role before writing the service file

---

## 11. inference-worker Startup Timeout

### Symptoms
- On first deployment, `inference-worker.service` enters `failed` state
- `sudo journalctl -u inference-worker` shows: `Timeout waiting for service start`
- The service starts fine on `systemctl restart` after the model is already cached

### Root Cause
The HuggingFace model download (~540MB GGUF file) happens on the **first startup** of the inference worker. Over the NAT instance (`t3.nano`), download speed is limited. The model takes 2-5 minutes to download, but the default systemd `TimeoutStartSec` was 90 seconds — not enough.

On subsequent starts (model already cached in `HF_HOME`), startup completes in seconds.

### Fix Applied

```ini
[Service]
# Generous startup timeout - worker downloads ~540MB GGUF model from HuggingFace on first boot
TimeoutStartSec=300
```

### Prevention Strategy
- Always set `TimeoutStartSec=300` (or higher) for services that download large files at startup
- Add a pre-download step in Ansible that downloads the model *before* the service starts, eliminating the startup-time download entirely
- Monitor first-boot startup with `journalctl -u inference-worker -f` to confirm model download completes

---

## 12. Nginx 502 Bad Gateway on Engine Restart

### Symptoms
- After restarting `iii-engine.service`, all API requests return `502 Bad Gateway`
- This persists for 10-30 seconds even after the engine service shows `active (running)`
- Workers eventually reconnect and requests succeed again

### Root Cause
After the iii-engine restarts, its WebSocket registry is **cleared** — all worker function registrations are lost. Workers detect the disconnection and begin reconnecting (with exponential backoff), but there's a brief window where the engine has no registered handlers. During this window, Nginx's proxy_pass to port 3111 succeeds (engine is up) but the engine has no handlers for `/v1/chat/completions`, returning a 502-equivalent.

### Fix Applied

This is a known limitation of the architecture. Mitigation strategies applied:

1. **Increased systemd restart delay** for the engine to allow workers to reconnect before accepting traffic:
   ```ini
   [Service]
   RestartSec=5    # Brief delay before restart to let workers detect and reconnect
   ```

2. **Extended Nginx 502 grace period** with a retry directive:
   ```nginx
   location /v1/ {
       proxy_next_upstream error timeout http_502;
       proxy_next_upstream_tries 3;
   }
   ```

3. **Documented the behavior** — operators should wait 15-30 seconds after an engine restart before testing the API.

### Prevention Strategy
- In production, use a **multi-engine active-active** setup behind an ALB — individual engine restarts don't affect availability
- Implement a `/ready` endpoint on the engine that returns 200 only when at least one worker is registered
- Configure Nginx `proxy_next_upstream` to retry on 502 automatically

---

## Quick Reference — Diagnostic Commands

```bash
# --- Service Status ---
sudo systemctl status nginx iii-engine inference-worker caller-worker

# --- Live Logs ---
sudo journalctl -u iii-engine -f
sudo journalctl -u inference-worker -f
sudo journalctl -u caller-worker -f
sudo journalctl -u nginx -f

# --- Recent Errors ---
sudo journalctl -u inference-worker -n 100 --no-pager | grep -E "Error|Failed|Exception"

# --- Memory Status ---
free -h
swapon --show

# --- Disk Usage ---
df -h

# --- Network Connectivity (from private VM) ---
curl -I https://www.google.com
curl -I https://pypi.org

# --- NAT Status ---
cat /proc/sys/net/ipv4/ip_forward
sudo iptables -t nat -L -n -v

# --- Nginx Config Test ---
sudo nginx -t

# --- Restart All Services ---
sudo systemctl restart inference-worker caller-worker iii-engine nginx
```
