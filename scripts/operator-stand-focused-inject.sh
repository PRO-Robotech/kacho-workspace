#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
# External-only operator producer/reader experiments. Both groups run after any failure.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$HERE/operator-stand-inject.py"; operator_rc=$?
python3 "$HERE/operator-cluster-inject.py" "$HERE/operator-stand.py" "$HERE/operator-stand-fixtures/cluster-api-shape.json"; cluster_rc=$?
printf 'OPERATOR_TEST_GROUPS hosted=%s cluster=%s\n' "$operator_rc" "$cluster_rc"
[ "$operator_rc" -eq 0 ] && [ "$cluster_rc" -eq 0 ]
