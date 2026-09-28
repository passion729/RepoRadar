#!/bin/bash
set -e
cd "$(dirname "$0")"
source ./clt-env.sh
swift test "${TEST_FLAGS[@]}" "$@"
