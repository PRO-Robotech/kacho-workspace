#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
# Пробы производителя и читателя — только внешним маршрутом; все группы идут после отказа.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
shellcheck --version
lint_rc=0
if [ "$(shellcheck --version | sed -n 's/^version: //p')" != 0.11.0 ]; then
  lint_rc=2
else
  shellcheck -x -- "$HERE"/remote-heavy/*.sh || lint_rc=$?
fi
python3 -I "$HERE/operator-capture-chain-inject.py" "$HERE/remote-heavy/run.sh"; capture_rc=$?
python3 "$HERE/operator-stand-inject.py"; operator_rc=$?
python3 "$HERE/operator-cluster-inject.py" "$HERE/operator-stand.py" "$HERE/operator-stand-fixtures/cluster-api-shape.json"; cluster_rc=$?
bash "$HERE/operator-archive-inject.sh"; archive_rc=$?
printf 'OPERATOR_TEST_GROUPS hosted=%s cluster=%s shellcheck=%s capture=%s archive=%s\n' "$operator_rc" "$cluster_rc" "$lint_rc" "$capture_rc" "$archive_rc"
[ "$operator_rc" -eq 0 ] && [ "$cluster_rc" -eq 0 ] && [ "$lint_rc" -eq 0 ] && [ "$capture_rc" -eq 0 ] && [ "$archive_rc" -eq 0 ]
