#!/bin/bash
# Wrapper delegating to scripts/test_curl.sh
exec "$(dirname "$0")/scripts/test_curl.sh" "$@"
