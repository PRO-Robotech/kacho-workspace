#!/usr/bin/env bash
# pr-body.sh <владелец/имя> <база> <голова> — тело PR из git, в stdout (ws#1146).
#
# Состав — коммиты `база..голова` по полосам (слияния первого родителя); `#N` — только
# номера первых строк коммитов диапазона; `Closes` — лишь открытой задаче с
# комментарием `DoD-proof @<ревизия>`, чья ревизия — коммит диапазона, и не держателю
# записи долга; закрывающие строки последними. Ничего не публикует: тело — для
# `gh pr create|edit --body-file`, применяет git-operator.
#
# Git — рабочей копии `RITUAL_REPO_DIR` (по умолчанию текущий каталог); трекер — `RITUAL_GH`
# (по умолчанию `gh`); ведомости чужого репозитория — `origin/main` клона под
# `RITUAL_LEDGER_CLONES` (по умолчанию `project/` воркспейса).
# Логика, исходы (0 · 1 отказ · 2 не выполнилось) и самопробы — `scripts/rituals/`
# (`rituals.py`, `check-01-pr-body.py`, `inject.sh`).
set -uo pipefail
exec python3 "$(dirname "${BASH_SOURCE[0]}")/rituals/rituals.py" pr-body "$@"
