#!/bin/bash
curl -k -i -X POST https://98.84.46.0/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"hello"}]}'
