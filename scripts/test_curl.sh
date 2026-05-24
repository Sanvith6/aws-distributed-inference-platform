#!/bin/bash
curl -k -i -X POST https://44.202.193.89/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"hello"}]}'
