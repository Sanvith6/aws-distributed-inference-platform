#!/bin/bash
# Teardown Script to clean up and destroy all provisioned infrastructure
set -euo pipefail

# Error recovery trap to handle failures gracefully
cleanup_on_err() {
    echo -e "\n=========================================================================="
    echo " [-] Teardown Pipeline Failed! Check the logs above for specific error traces."
    echo "=========================================================================="
}
trap cleanup_on_err ERR

# Ensure we are running from the repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

echo "=========================================================================="
echo " Starting Teardown of Distributed Inference Infrastructure (AWS)"
echo "=========================================================================="

# Preflight Tool Check
if ! command -v terraform &>/dev/null; then
    echo "[-] Error: Terraform is not installed or not in PATH." >&2
    exit 1
fi

cd terraform
terraform destroy -auto-approve

echo "=========================================================================="
echo " [✓] Infrastructure successfully destroyed!"
echo "=========================================================================="
