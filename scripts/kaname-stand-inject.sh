#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
# Tracked portable suite: execute through heavy-slot, never as a local test shortcut.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
exec python3 -I "$root/scripts/kaname-stand-inject.py"
