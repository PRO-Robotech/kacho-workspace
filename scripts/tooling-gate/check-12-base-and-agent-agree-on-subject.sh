#!/usr/bin/env bash
# check-12 — база маршрутизации и тело агента не расходятся в том, ЧТО агент делает.
#
# Предмет, разбор, единица счёта, роль полярности и три исхода — в шапке
# `measure-base-agent-subject-conflict.py`; здесь они не пересказываются, чтобы
# два места об одном предмете не разошлись. Инъекция —
# `prove-base-agent-subject-conflict.sh`.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SELF_DIR/measure-base-agent-subject-conflict.py"
