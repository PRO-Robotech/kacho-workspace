#!/usr/bin/env bash
# check-11 — ПОЛЕ `model:` ВО FRONTMATTER АГЕНТА НЕСЁТ ЗНАЧЕНИЕ, КОТОРОЕ ХАРНЕСС ПРИМЕТ.
#
# Предмет: `.claude/agents/*.md`, строка `model:` между первыми `---`. С ws#975 у
# механических агентов там стоит лёгкая модель (решение владельца 2026-09-27
# «механика на лёгкой модели»). Опечатка в этом поле не видна ни в диффе, ни в
# прогоне: харнесс получает строку, которой нет среди моделей, и агент либо не
# стартует, либо молча берёт модель родителя — то есть норма «механика на лёгкой
# модели» перестаёт исполняться, а файл продолжает её объявлять.
#
# ЗАКОННЫЕ ФОРМЫ ЗНАЧЕНИЯ — две, и обе названы описанием поля в самом харнессе
# (измерено 2026-10-08 по бинарю CC 2.1.293: «Model alias (e.g. 'fable', 'opus',
# 'sonnet', 'haiku') or full model ID (e.g. 'claude-fable-5'). 'inherit' uses the
# main model»):
#   · псевдоним: sonnet | opus | haiku | fable | inherit;
#   · полный идентификатор модели: `claude-<строчные латинские, цифры, точка,
#     дефис>` с необязательным суффиксом окна `[1m]`.
# Отсутствие поля — законно (агент берёт модель по умолчанию) и находкой не
# является; пустое значение — находка: поле объявлено, а модели в нём нет.
#
# Вердикт — в КОДЕ ВЫХОДА: 0 молчит, 1 находка, 2 отказ (агентов нет — судить
# нечего). Перепись печатается всегда: сколько агентов осмотрено и у скольких
# поле объявлено, чтобы «ноль находок» отличалось от «ноль прочитанного».
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Корень — общим швом набора (`scripts/lib/gate_root.py`, переменная
# `RULES_GATE_ROOT`), а не текущим каталогом: иначе проверку нельзя прогнать на
# копии дерева, а с чужого cwd она судила бы чужое дерево.
root="$(python3 "$SELF_DIR/../lib/gate_root.py" RULES_GATE_ROOT "${BASH_SOURCE[0]}")" || exit 2
cd "$root" 2>/dev/null || {
    echo "[VOID] check-11-agent-model-value — корень «$root» не открывается; обходить нечего" >&2
    exit 2
}

exec python3 - "$root" <<'PY'
import os, re, sys

root = sys.argv[1]
d = os.path.join(root, ".claude", "agents")
names = sorted(n for n in os.listdir(d) if n.endswith(".md")) if os.path.isdir(d) else []

ALIASES = {"sonnet", "opus", "haiku", "fable", "inherit"}
FULL_ID = re.compile(r"^claude-[a-z0-9][a-z0-9.-]*(\[1m\])?$")

rc = 0
declared = 0
for n in names:
    rel = ".claude/agents/" + n
    lines = open(os.path.join(d, n), encoding="utf-8").read().split("\n")
    if not lines or lines[0].strip() != "---":
        # Форму frontmatter агента судят соседние проверки (check-04, check-05);
        # здесь у файла без frontmatter поля `model:` просто нет.
        continue
    for i, line in enumerate(lines[1:], start=2):
        if line.strip() == "---":
            break
        m = re.match(r"^model[ \t]*:(.*)$", line)
        if not m:
            continue
        declared += 1
        raw = m.group(1).split(" #", 1)[0].strip()
        val = raw[1:-1].strip() if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'" else raw
        if not val:
            print("КРАСНОЕ %s:%d — поле model: объявлено пустым; модели в нём нет" % (rel, i))
            rc = 1
        elif val not in ALIASES and not FULL_ID.match(val):
            print("КРАСНОЕ %s:%d — model: «%s» не псевдоним (%s) и не полный идентификатор "
                  "claude-…: харнесс такой модели не знает, норма о модели агента не исполнится"
                  % (rel, i, val, "|".join(sorted(ALIASES))))
            rc = 1

print("корень %s; осмотрено агентов: %d; поле model: объявлено у %d" % (root, len(names), declared))
if not names:
    print("[VOID] ОТКАЗ — в .claude/agents нет ни одного *.md: модель судить не у кого, вердикт беспредметен")
    sys.exit(2)
sys.exit(rc)
PY
