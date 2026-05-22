#!/bin/bash
# Test Script to send an inference request to the API Gateway
set -euo pipefail

# Error recovery trap to handle failures gracefully
cleanup_on_err() {
    echo -e "\n[-] Test Execution Failed! Verify VM connectivity, security groups, and logs."
}
trap cleanup_on_err ERR

# Ensure we are running from the repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# Preflight check
for cmd in terraform curl python3; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "[-] Error: Required binary '$cmd' is not installed or not in PATH." >&2
        exit 1
    fi
done

cd terraform
ENGINE_IP=$(terraform output -raw engine_public_ip)

echo "[*] Sending inference request to https://${ENGINE_IP}/v1/chat/completions..."

RESPONSE=$(curl -skf -X POST "https://${ENGINE_IP}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "What is 2+2?"}
    ]
  }')

echo "${RESPONSE}" | python3 -m json.tool

# Validate response format
if ! echo "${RESPONSE}" | grep -q "choices"; then
    echo "[-] Error: API response did not contain expected completions 'choices'!" >&2
    exit 1
fi

echo "[✓] Inference request verified successfully."
