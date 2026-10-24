#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
# Внешний маршрут читателей (ws#1365) опытом — во внешнем кластере через heavy-slot, не на машине.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
exec python3 -I "$root/scripts/remote-reader-inject.py" "$@"
