#!/bin/bash
ssh -i /tmp/iii-key.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ProxyCommand="ssh -i /tmp/iii-key.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ubuntu@98.84.46.0" \
    ubuntu@10.0.2.156 "grep -n -C 30 'const http =' /opt/iii/workers/caller-worker/node_modules/iii-sdk/dist/*.mjs"
