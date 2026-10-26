#!/usr/bin/env bash
# pr-body.sh <владелец/имя | имя из ведомости стволов> <база> <голова> — тело PR из git, в stdout (ws#1146, ws#1418).
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
#
# На машине владельца — Job-ом внешнего кластера (ws#1365, scripts/remote-reader.sh: там же — где
# маршрута нет); здесь — в pod, на ранере конвейера и на стороне pod драйвера.
set -uo pipefail
if [ -z "${KUBERNETES_SERVICE_HOST:-}" ] && [ "${GITHUB_ACTIONS:-}" != true ] && [ "${KACHO_REMOTE_READER_POD:-}" != 1 ] &&
   [ -z "${HEAVY_SLOT_P:-}" ]; then
    exec bash "$(dirname "${BASH_SOURCE[0]}")/remote-reader.sh" scripts/pr-body.sh "$@"
fi
exec python3 "$(dirname "${BASH_SOURCE[0]}")/rituals/rituals.py" pr-body "$@"
