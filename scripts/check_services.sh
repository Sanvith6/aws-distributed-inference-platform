#!/bin/bash
set -e

echo "=== VM2 Inference Worker Service Status ==="
ssh -i /tmp/iii-key.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ProxyCommand="ssh -i /tmp/iii-key.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ubuntu@98.84.46.0" \
    ubuntu@10.0.2.209 "sudo systemctl status inference-worker --no-pager" || true

echo -e "\n=== VM2 Inference Worker Recent Logs ==="
ssh -i /tmp/iii-key.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ProxyCommand="ssh -i /tmp/iii-key.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ubuntu@98.84.46.0" \
    ubuntu@10.0.2.209 "sudo journalctl -u inference-worker -n 50 --no-pager" || true
