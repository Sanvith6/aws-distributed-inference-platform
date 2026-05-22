# PowerShell Deployment Orchestration Script for Distributed Inference
$ErrorActionPreference = "Stop"

# Error handling block
trap {
    Write-Host "`n==========================================================================" -ForegroundColor Red
    Write-Host " [-] Deployment Pipeline Failed! Review the logs above for details." -ForegroundColor Red
    Write-Host "==========================================================================" -ForegroundColor Red
    exit 1
}

Write-Host "==========================================================================" -ForegroundColor Green
Write-Host " Starting Distributed Inference End-to-End Deployment (PowerShell)" -ForegroundColor Green
Write-Host "==========================================================================" -ForegroundColor Green

# Ensure we are running from the repository root
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..")
Set-Location $RepoRoot

# 0. Preflight System and Tool Checks
Write-Host "[*] Step 0: Running Preflight Checks..." -ForegroundColor Cyan

$UseWSLAnsible = $false
$RequiredCommands = @("terraform", "python", "aws")
foreach ($cmd in $RequiredCommands) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Throw "Required binary '$cmd' is not installed or not in PATH."
    }
}

if (Get-Command "ansible-playbook" -ErrorAction SilentlyContinue) {
    Write-Host "[+] Native Ansible is available on Windows." -ForegroundColor Green
} else {
    Write-Host "[*] Native 'ansible-playbook' not found on Windows. Checking for WSL Ubuntu Ansible..." -ForegroundColor Yellow
    if (Get-Command "wsl" -ErrorAction SilentlyContinue) {
        $wslAnsibleCheck = wsl -d Ubuntu which ansible-playbook 2>$null
        if ($LASTEXITCODE -eq 0) {
            $UseWSLAnsible = $true
            Write-Host "[+] Found Ansible inside WSL Ubuntu. Will use WSL fallback for Ansible configuration." -ForegroundColor Green
        } else {
            Throw "Required binary 'ansible-playbook' is not installed on Windows or inside WSL Ubuntu."
        }
    } else {
        Throw "Required binary 'ansible-playbook' is not installed on Windows and 'wsl' is not available."
    }
}
Write-Host "[+] All required binaries are available." -ForegroundColor Green

Write-Host "[*] Verifying AWS CLI authentication state..." -ForegroundColor Cyan
aws sts get-caller-identity >$null 2>&1
if ($LASTEXITCODE -ne 0) {
    Throw "AWS CLI is not authenticated or lacks connectivity. Please run 'aws configure'."
}

Write-Host "[*] Verifying AWS Region configuration..." -ForegroundColor Cyan
$awsRegion = (aws configure get region 2>$null)
if ([string]::IsNullOrEmpty($awsRegion)) {
    Throw "No default AWS region configured. Please configure a region via 'aws configure' or set the AWS_DEFAULT_REGION environment variable."
}
Write-Host "[+] AWS CLI is configured with region: $awsRegion" -ForegroundColor Green

# 1. Provision Infrastructure via Terraform
Write-Host "`n[*] Step 1: Running Terraform Lint Guards & Provisioning..." -ForegroundColor Cyan
Push-Location terraform

Write-Host "[*] Running Terraform Validation Guard (backend-less)..." -ForegroundColor Cyan
terraform init -backend=false
terraform fmt -check
terraform validate
if ($LASTEXITCODE -ne 0) {
    Throw "Terraform validation checks failed."
}

if (-not (Test-Path "iii-key.pem")) {
    Write-Host "[*] Initializing Terraform state..." -ForegroundColor Cyan
}

terraform init
terraform apply -auto-approve

# Extract IP addresses
$enginePubIp = (terraform output -raw engine_public_ip).Trim()
$enginePrivIp = (terraform output -raw engine_private_ip).Trim()
$inferencePrivIp = (terraform output -raw inference_worker_private_ip).Trim()
$callerPrivIp = (terraform output -raw caller_worker_private_ip).Trim()
$tfJson = (terraform output -json)

Write-Host "[+] Infrastructure Provisioned Successfully:" -ForegroundColor Green
Write-Host "    - Engine Public IP:        $enginePubIp"
Write-Host "    - Engine Private IP:       $enginePrivIp"
Write-Host "    - Inference Worker IP:     $inferencePrivIp"
Write-Host "    - Caller Worker IP:        $callerPrivIp"

# 2. Generate Ansible Inventory
Write-Host "`n[*] Step 2: Generating Ansible Inventory..." -ForegroundColor Cyan
Pop-Location
Push-Location ansible

$tfJson | python generate_inventory.py > inventory.ini
Write-Host "[+] Created ansible/inventory.ini" -ForegroundColor Green

# 3. Execute Ansible Playbook
Write-Host "`n[*] Step 3: Running Ansible Playbook..." -ForegroundColor Cyan
Write-Host "[*] Waiting 60 seconds for SSH ports to become available on VMs..."
Start-Sleep -Seconds 60

if ($UseWSLAnsible) {
    Write-Host "[*] Preparing WSL SSH key, config, and inventory..." -ForegroundColor Cyan
    # Copy the ssh key to WSL /tmp directory and make it secure
    wsl -d Ubuntu sh -c "rm -f /tmp/iii-key.pem && cp ../terraform/iii-key.pem /tmp/iii-key.pem && chmod 400 /tmp/iii-key.pem"
    if ($LASTEXITCODE -ne 0) {
        Throw "Failed to secure SSH key inside WSL."
    }
    
    # Copy the ansible config to WSL /tmp directory and make it secure
    wsl -d Ubuntu sh -c "rm -f /tmp/ansible.cfg && cp ansible.cfg /tmp/ansible.cfg && chmod 600 /tmp/ansible.cfg"
    if ($LASTEXITCODE -ne 0) {
        Throw "Failed to secure Ansible config inside WSL."
    }
    
    # Generate an inventory_wsl.ini with path referencing the WSL key file
    (Get-Content inventory.ini) -replace '\.\./terraform/iii-key\.pem', '/tmp/iii-key.pem' | Out-File -Encoding ascii inventory_wsl.ini
    
    Write-Host "[*] Executing Ansible Playbook in WSL..." -ForegroundColor Cyan
    wsl -d Ubuntu sh -c "ANSIBLE_CONFIG=/tmp/ansible.cfg ansible-playbook -i inventory_wsl.ini playbook.yml --extra-vars 'engine_private_ip=$enginePrivIp'"
    if ($LASTEXITCODE -ne 0) {
        Throw "Ansible playbook execution in WSL failed."
    }
} else {
    ansible-playbook -i inventory.ini playbook.yml --extra-vars "engine_private_ip=$enginePrivIp"
    if ($LASTEXITCODE -ne 0) {
        Throw "Ansible playbook execution failed."
    }
}

# 4. Verification and Readiness Tests
Write-Host "`n[*] Step 4: Verification and Smoke Testing..." -ForegroundColor Cyan
Write-Host "[*] Waiting 60 seconds for workers to establish WebSockets and load the SLM model..."
Start-Sleep -Seconds 60

# Trust all self-signed certificates for testing session
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

Write-Host "[*] Querying /health readiness endpoint..." -ForegroundColor Cyan
try {
    $healthRes = curl.exe -k -s "https://$enginePubIp/health"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($healthRes)) {
        Throw "Health check query failed with exit code $LASTEXITCODE"
    }
    $healthRes | Write-Host
} catch {
    Throw "Health check query failed: $_"
}

Write-Host "`n[*] Querying JSON API Completion Endpoint (/v1/chat/completions)..." -ForegroundColor Cyan
$body = '{"messages": [{"role": "user", "content": "Tell me a 1-sentence joke."}]}'

try {
    $inferenceRes = curl.exe -k -s -X POST "https://$enginePubIp/v1/chat/completions" -H "Content-Type: application/json" -d $body --max-time 120
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($inferenceRes)) {
        Throw "Inference test failed with exit code $LASTEXITCODE"
    }
    $inferenceRes | Write-Host
    
    if (-not ($inferenceRes -match "choices")) {
        Throw "API response did not contain expected completions 'choices'!"
    }
} catch {
    Throw "Inference test failed: $_"
}

Pop-Location
Write-Host "`n==========================================================================" -ForegroundColor Green
Write-Host " [OK] Deployment and Verification Completed successfully!" -ForegroundColor Green
Write-Host "==========================================================================" -ForegroundColor Green
