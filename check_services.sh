#!/bin/bash
# Wrapper delegating to scripts/check_services.sh
exec "$(dirname "$0")/scripts/check_services.sh" "$@"
