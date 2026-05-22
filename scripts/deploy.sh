#!/bin/bash
# End-to-end Deployment Orchestration Script for Distributed Inference
set -euo pipefail

# Error recovery trap to handle pipeline failures gracefully
cleanup_on_err() {
    echo -e "\n=========================================================================="
    echo " [-] Deployment Pipeline Failed! Review the logs above for details."
    echo "=========================================================================="
}
trap cleanup_on_err ERR

# Ensure we are running from the repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

echo "=========================================================================="
echo " Starting Distributed Inference End-to-End Deployment (AWS + Terraform)"
echo "=========================================================================="

# 0. Preflight System and Tool Checks
echo "[*] Step 0: Running Preflight Checks..."

for cmd in terraform ansible python3 aws curl; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "[-] Error: Required binary '$cmd' is not installed or not in PATH." >&2
        exit 1
    fi
done
echo "[+] All required binaries are available."

echo "[*] Verifying AWS CLI authentication state..."
aws sts get-caller-identity >/dev/null 2>&1 || {
    echo "[-] Error: AWS CLI is not authenticated or lacks connectivity." >&2
    echo "    Please run 'aws configure' to set up credentials." >&2
    exit 1
}

echo "[*] Verifying AWS Region configuration..."
AWS_REGION=$(aws configure get region 2>/dev/null || echo "")
if [ -z "${AWS_REGION}" ]; then
    echo "[-] Error: No default AWS region configured." >&2
    echo "    Please configure a region via 'aws configure' or set the AWS_DEFAULT_REGION environment variable." >&2
    exit 1
fi
echo "[+] AWS CLI is configured with region: ${AWS_REGION}"

# 1. Provision Infrastructure via Terraform
echo -e "\n[*] Step 1: Running Terraform Lint Guards & Provisioning..."
cd terraform

echo "[*] Running Terraform Validation Guard (backend-less)..."
terraform init -backend=false
terraform fmt -check
terraform validate

if [ ! -f "iii-key.pem" ]; then
    echo "[*] Initializing Terraform state..."
fi

terraform init
terraform apply -auto-approve

# Extract IP addresses
ENGINE_PUB_IP=$(terraform output -raw engine_public_ip)
ENGINE_PRIV_IP=$(terraform output -raw engine_private_ip)
INFERENCE_PRIV_IP=$(terraform output -raw inference_worker_private_ip)
CALLER_PRIV_IP=$(terraform output -raw caller_worker_private_ip)

echo "[+] Infrastructure Provisioned Successfully:"
echo "    - Engine Public IP:        ${ENGINE_PUB_IP}"
echo "    - Engine Private IP:       ${ENGINE_PRIV_IP}"
echo "    - Inference Worker IP:     ${INFERENCE_PRIV_IP}"
echo "    - Caller Worker IP:        ${CALLER_PRIV_IP}"

# 2. Generate Ansible Inventory
echo -e "\n[*] Step 2: Generating Ansible Inventory..."
cd ../ansible
terraform -chdir=../terraform output -json | python3 generate_inventory.py > inventory.ini
echo "[+] Created ansible/inventory.ini"

# 3. Execute Ansible Playbook
echo -e "\n[*] Step 3: Running Ansible Playbook..."
# Note: AWS instances might need a few seconds to let SSH service boot
echo "[*] Waiting 60 seconds for SSH ports to become available on VMs..."
sleep 60

ansible-playbook -i inventory.ini playbook.yml \
  --extra-vars "engine_private_ip=${ENGINE_PRIV_IP}"

# 4. Verification and Readiness Tests
echo -e "\n[*] Step 4: Verification and Smoke Testing..."
echo "[*] Waiting 60 seconds for workers to establish WebSockets and load the SLM model..."
sleep 60

echo "[*] Querying /health readiness endpoint..."
curl -skf "https://${ENGINE_PUB_IP}/health" | python3 -m json.tool

echo -e "\n[*] Querying JSON API Completion Endpoint (/v1/chat/completions)..."
RESPONSE=$(curl -skf -X POST "https://${ENGINE_PUB_IP}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "Tell me a 1-sentence joke."}
    ]
  }')

echo "${RESPONSE}" | python3 -m json.tool

# Validate response schema
if ! echo "${RESPONSE}" | grep -q "choices"; then
    echo "[-] Error: API response did not contain expected completions 'choices'!" >&2
    exit 1
fi

echo -e "\n=========================================================================="
echo " [✓] Deployment and Verification Completed successfully!"
echo "=========================================================================="
