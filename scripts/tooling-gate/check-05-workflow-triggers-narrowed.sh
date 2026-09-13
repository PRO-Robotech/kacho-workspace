#!/usr/bin/env bash
# check-05 — рабочий процесс не тратит ранер на ветку, которую правило объявило
# непроверяемой, и НЕ перестаёт производить контексты, которых требует защита ствола.
#
# Что запрещает эта проверка (#282). `.claude/rules/git-issues.md` §«Накопительная
# релизная ветка» и `.claude/rules/multi-agent-flow.md` §8 обещают: конвейер тратится
# ОДИН раз — на MR релизной ветки в `main`; PR внутрь релизной не проверяется. До
# 2026-08-19 обещание не исполнялось ЗДЕСЬ: `on: [push, pull_request]` без сужения
# покрывал каждую ветку и каждый PR, причём дважды — событием `push` и событием
# `pull_request`. Правило описывало намерение, дерево исполняло обратное.
#
# Утверждений три, и третье — контроль в обратную сторону:
#   A. `push`/`pull_request`/`pull_request_target` СУЖЕНЫ по ветке
#      (`branches` либо `branches-ignore`, непустые). Иначе ветка задачи
#      оплачивается полным прогоном.
#   B. `pull_request*` ПРОПУСКАЕТ `main`. Иначе на MR в ствол контексты не
#      появятся вовсе, а защита ветки требует их поимённо.
#   C. `pull_request*` НЕ сужен по `paths`/`paths-ignore`. Контекст, который не
#      начался, не зеленеет и не краснеет — он остаётся «ожидается», и слияние
#      блокируется навсегда. Это не то же самое, что красный: красное чинится.
#
# Законные близнецы, на которых проверка МОЛЧИТ: `schedule`, `workflow_dispatch`,
# `workflow_run`, `workflow_call`, `release`, `issues`, `issue_comment` — ни один
# не тратит ранер на ветку задачи, и сужать их по ветке нечем.
#
# Читается ОБЪЯВЛЕНИЕ, разобранное как YAML, а не подстрока: слово `pull_request`
# стоит в комментариях этого же файла конвейера, и текстовый предикат считал бы
# их триггерами (`gate-authoring` §Читать исполняемое).
#
# Предпосылки (объявляются исходом VOID, а не молчаливым успехом): в дереве есть
# файлы конвейера · разборщик YAML доступен · разобран хотя бы один триггер.
#
# Сетевая половина контроля B — по ручке `KACHO_BRANCH_PROTECTION_CHECK=1`: сверить
# перечень обязательных контекстов защиты `main` с именами job'ов, которые процессы
# на `main` производят. Состояние этой сверки печатается ВСЕГДА — иначе «сверено 0»
# было бы неотличимо от «сверено».
set -uo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WS="$(tooling_gate_workspace_root)"
NAME="check-05-workflow-triggers-narrowed"

mapfile -t WORKFLOWS < <(tooling_gate_files "$WS" '.github/workflows/*')
if [ "${#WORKFLOWS[@]}" -eq 0 ]; then
    tooling_gate_void "$NAME" "файлов конвейера в дереве нет — проверять нечего"
    exit 2
fi

if ! python3 -c 'import yaml' 2>/dev/null; then
    tooling_gate_void "$NAME" "разборщик YAML недоступен — объявление триггеров читать нечем"
    exit 2
fi

REQUIRED_CONTEXTS=""
PROTECTION_STATE="ручка KACHO_BRANCH_PROTECTION_CHECK выключена"
if [ -n "${TOOLING_GATE_REQUIRED_CONTEXTS:-}" ]; then
    # Перечень задан извне. Этим пользуется ТОЛЬКО inject.sh — так же, как
    # `TOOLING_GATE_ROOT`: доказать обе стороны сетевой половины офлайн, без
    # похода в сеть с ранера, где у токена нет права читать защиту ветки.
    REQUIRED_CONTEXTS="$TOOLING_GATE_REQUIRED_CONTEXTS"
    PROTECTION_STATE="перечень контекстов задан извне (инъекция)"
elif [ "${KACHO_BRANCH_PROTECTION_CHECK:-0}" = "1" ]; then
    if ! command -v gh > /dev/null 2>&1; then
        PROTECTION_STATE="ручка включена, но gh недоступен — сверки НЕ БЫЛО"
    else
        repo="${KACHO_WORKSPACE_REPO:-PRO-Robotech/kacho-workspace}"
        if REQUIRED_CONTEXTS="$(timeout 60 gh api "repos/$repo/branches/main/protection" \
                --jq '.required_status_checks.contexts[]' 2>/dev/null)" \
           && [ -n "$REQUIRED_CONTEXTS" ]; then
            PROTECTION_STATE="сверено с защитой ветки $repo"
        else
            REQUIRED_CONTEXTS=""
            PROTECTION_STATE="ручка включена, но перечень контекстов не получен — сверки НЕ БЫЛО"
        fi
    fi
fi

WS="$WS" NAME="$NAME" PROTECTION_STATE="$PROTECTION_STATE" \
REQUIRED_CONTEXTS="$REQUIRED_CONTEXTS" \
python3 - "${WORKFLOWS[@]}" <<'PY'
import os
import sys

import yaml

ws = os.environ["WS"]
name = os.environ["NAME"]
protection_state = os.environ["PROTECTION_STATE"]
required = [c for c in os.environ["REQUIRED_CONTEXTS"].splitlines() if c.strip()]

# События, которые тратят ранер на ВЕТКУ и потому обязаны быть сужены.
BRANCH_EVENTS = ("push", "pull_request", "pull_request_target")
# Из них — те, что производят контексты для защиты ствола.
PR_EVENTS = ("pull_request", "pull_request_target")

findings = []
triggers = 0
jobs_total = 0
produced = set()          # имена контекстов, которые процессы на `main` производят
files_read = 0


def line_of(path, needle):
    """Номер строки, где событие объявлено. Координата обязана быть настоящей:
    находка без неё заставляет читателя искать предмет глазами."""
    try:
        with open(path, encoding="utf-8") as fh:
            for i, raw in enumerate(fh, 1):
                stripped = raw.strip()
                if stripped.startswith("#"):
                    continue          # комментарий объявлением не является
                if needle in stripped:
                    return i
    except OSError:
        pass
    return 0


def matches_main(patterns):
    """`main` попадает под перечень. Шаблоны GitHub — glob; проверяем вхождением
    имени ствола, а не сравнением строк, иначе `ma*` читалось бы как промах."""
    import fnmatch
    return any(fnmatch.fnmatch("main", str(p)) for p in patterns)


for rel in sys.argv[1:]:
    path = os.path.join(ws, rel)
    try:
        with open(path, encoding="utf-8") as fh:
            doc = yaml.safe_load(fh)
    except (OSError, yaml.YAMLError) as exc:
        findings.append(f"{rel} — объявление не разбирается как YAML: {exc}")
        continue
    if not isinstance(doc, dict):
        findings.append(f"{rel} — объявление процесса не является отображением")
        continue
    files_read += 1

    jobs = doc.get("jobs") or {}
    if isinstance(jobs, dict):
        jobs_total += len(jobs)

    # PyYAML разбирает голое `on:` как булево True (YAML 1.1, «on» = yes).
    on = doc.get("on", doc.get(True))

    # Списочная и строковая формы (`on: [push, pull_request]`) сужения не несут
    # BY CONSTRUCTION — им негде его нести.
    if isinstance(on, str):
        on = {on: None}
    elif isinstance(on, list):
        on = {str(ev): None for ev in on}
    if not isinstance(on, dict):
        findings.append(f"{rel} — у процесса нет разбираемого объявления `on`")
        continue

    fires_on_main = False
    for event, spec in on.items():
        event = str(event)
        if event not in BRANCH_EVENTS:
            continue                      # законный близнец: ранер на ветку не тратит
        triggers += 1
        lineno = line_of(path, f"{event}:")
        coord = f"{rel}:{lineno}" if lineno else rel

        if not isinstance(spec, dict):
            findings.append(
                f"{coord} — `{event}` без сужения по ветке: срабатывает на КАЖДОЙ, "
                f"при обещанном нуле прогонов вне ствола"
            )
            continue

        branches = spec.get("branches")
        ignore = spec.get("branches-ignore")
        if not branches and not ignore:
            findings.append(
                f"{coord} — `{event}` без сужения по ветке: срабатывает на КАЖДОЙ, "
                f"при обещанном нуле прогонов вне ствола"
            )
            continue

        if event in PR_EVENTS:
            if branches and not matches_main(branches):
                findings.append(
                    f"{coord} — `{event}` не пропускает `main`: на MR в ствол контексты "
                    f"не появятся, а защита ветки требует их поимённо"
                )
                continue
            if spec.get("paths") or spec.get("paths-ignore"):
                findings.append(
                    f"{coord} — `{event}` сужен по `paths`: контекст, который не начался, "
                    f"остаётся «ожидается» — слияние блокируется навсегда, а не краснеет"
                )
                continue
            if branches and matches_main(branches):
                fires_on_main = True
            elif ignore and not matches_main(ignore):
                fires_on_main = True

    if fires_on_main and isinstance(jobs, dict):
        for job_id, job in jobs.items():
            title = job.get("name") if isinstance(job, dict) else None
            produced.add(str(title or job_id))

print(f"[CENSUS] {name}: прочитано процессов {files_read}, "
      f"разобрано триггеров по ветке {triggers}, job'ов {jobs_total}, "
      f"контекстов на `main` {len(produced)}; защита ветки — {protection_state}")

if triggers == 0:
    print(f"[VOID] {name} — ни одного триггера по ветке не разобрано: "
          f"предикат остался без предмета", file=sys.stderr)
    sys.exit(2)

# Контроль в обратную сторону, сетевая половина. Имя контекста GitHub УСЕКАЕТ в
# ответе API — длинное русское имя приходит как «конвейер и агенты ... в ...», —
# поэтому сверяем ПРЕФИКСОМ, а не равенством: равенство давало бы находку на
# КАЖДОМ прогоне и на исправном дереве, то есть проверку отключили бы первой же.
# Многоточие бывает и одним знаком, и тремя точками — снимаются оба.
for ctx in required:
    probe = ctx
    for tail in ("\u2026", "..."):
        if probe.endswith(tail):
            probe = probe[: -len(tail)]
    probe = probe.rstrip()
    if not any(p == ctx or p.startswith(probe) for p in produced):
        findings.append(
            f"защита ветки требует контекст «{ctx}», но ни один процесс на `main` "
            f"его не производит — слияние стало бы невозможным"
        )

for f in findings:
    print(f"[FAIL] {name} — {f}", file=sys.stderr)

if findings:
    print(f"[FAIL] {name} — находок {len(findings)}", file=sys.stderr)
    sys.exit(1)

print(f"[PASS] {name} — осмотрено триггеров {triggers}, находок 0")
PY
