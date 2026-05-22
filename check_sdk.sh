#!/bin/bash
# Wrapper delegating to scripts/check_sdk.sh
exec "$(dirname "$0")/scripts/check_sdk.sh" "$@"
