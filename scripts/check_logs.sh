#!/bin/bash
echo "=== CALLER-WORKER LOGS (10.0.2.156) ==="
ssh -i /tmp/iii-key.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -i /tmp/iii-key.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ubuntu@98.84.46.0" ubuntu@10.0.2.156 "sudo journalctl -u caller-worker -n 100 --no-pager"

echo ""
echo "=== INFERENCE-WORKER LOGS (10.0.2.209) ==="
ssh -i /tmp/iii-key.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -i /tmp/iii-key.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ubuntu@98.84.46.0" ubuntu@10.0.2.209 "sudo journalctl -u inference-worker -n 100 --no-pager"
