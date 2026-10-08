#!/usr/bin/env bash
# check-11 — ПОЛЕ `model:` ВО FRONTMATTER АГЕНТА: ТОЛЬКО ПСЕВДОНИМ ИЗ ЗАКРЫТОГО
# ПЕРЕЧНЯ, И ЛЁГКАЯ МОДЕЛЬ — ТОЛЬКО У АГЕНТОВ, КОТОРЫМ ЕЁ ОТВЁЛ ВЛАДЕЛЕЦ.
#
# Предмет: `.claude/agents/*.md`, строка `model:` между первыми `---`. Норма —
# ai-tooling.md at-agent-model-value. Харнесс неизвестную строку не отвергает:
# функция подбора модели сабагента зовёт резолвер псевдонима, а не-псевдоним
# отдаёт как есть (CC 2.1.293) — опечатка не видна ни в диффе, ни в прогоне.
#
# ПОЛНЫЙ ИДЕНТИФИКАТОР ЗАПРЕЩЁН (ws#975, круг 3, вариант «Б»). Два круга
# распознаватель полного id по форме пропускал опечатку в семействе
# (claude-haiko → claude-haikuu-4-5, claude-sonet-4-5, claude-opsu-4-5): форма
# `claude-<слово>-<версия>` не знает, какие слова — модели. Перечень id из
# бинаря (вариант «А») — второе представление чужого каталога, которое стареет с
# каждой версией CC. Псевдоним же — закрытое множество, и опечатка в нём — просто
# слово вне множества. Перечень — по норме: sonnet | opus | haiku | fable, каждый
# с окном `[1m]`, плюс best | opusplan | inherit; регистр любой (резолвер
# приводит к нижнему). Сверка с бинарём, если CC сменит список:
#   grep -ao '\["sonnet","opus","haiku","fable","best",[^;]*"opusplan"\]' <бинарь>
#
# ЛЁГКАЯ МОДЕЛЬ (`haiku`, `haiku[1m]`) — только у агентов из LIGHT (владелец
# 2026-10-08: «Только ci-watcher»). Сверка в обе стороны: `haiku` у агента вне
# перечня — находка; агент перечня без `haiku` (поле снято или иное) — находка.
#
# ГРАНИЦЫ (что check-11 НЕ судит — намеренно):
# - модель, переданная параметром запуска (`model:` в вызове агента, напр.
#   MECH в .claude/workflows/wave.js: git-operator на haiku для механических
#   шагов), — не frontmatter; владелец 2026-10-08: «git-operator и vault-scribe
#   остаются на полной модели, а механические шаги git-operator идут на haiku
#   через параметр запуска, как в wave.js». Предмет check-11 — только файл агента.
# - `opusplan[1m]`: харнесс его принимает (CC 2.1.294, ветка opusplan|opusplan[1m]
#   в подборе модели), а перечень ALIASES — нет
#   (окно `[1m]` — только у WINDOWED). Перечень не расширяется: агентов с
#   opusplan нет, расширение — решением, а не заодно (ws#975).
#
# Формы записи значения: простое, в кавычках, с комментарием ` #`, блочный
# скаляр `>`/`|` (с индикатором `-`/`+`) — значение берётся из строк продолжения.
# `model:x` без пробела — не пара YAML, харнесс поля не увидит: находка. Пустое
# значение — находка. Отсутствие поля законно (кроме агентов LIGHT).
#
# Вердикт — в КОДЕ ВЫХОДА: 0 молчит, 1 находка, 2 отказ (агентов нет — судить
# нечего). Перепись печатается всегда.
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

WINDOWED = {"sonnet", "opus", "haiku", "fable"}
ALIASES = WINDOWED | {w + "[1m]" for w in WINDOWED} | {"best", "opusplan", "inherit"}
LIGHT_ALIASES = {"haiku", "haiku[1m]"}
LIGHT = {"ci-watcher"}  # владелец 2026-10-08: «Только ci-watcher»
BLOCK = re.compile(r"^[>|](?:[+-]?[1-9]?|[1-9][+-])$")


rc = 0
declared = 0
light_seen = set()
for n in names:
    rel = ".claude/agents/" + n
    agent = n[:-3]
    lines = open(os.path.join(d, n), encoding="utf-8").read().split("\n")
    if not lines or lines[0].strip() != "---":
        # Форму frontmatter агента судят соседние проверки (check-04, check-05).
        continue
    try:
        end = lines.index("---", 1)
    except ValueError:
        end = len(lines)
    for i in range(1, end):
        m = re.match(r"^model[ \t]*:(.*)$", lines[i])
        if not m:
            continue
        declared += 1
        at = "%s:%d" % (rel, i + 1)
        if m.group(1) and m.group(1)[0] not in " \t":
            print("КРАСНОЕ %s — «%s»: после двоеточия нет пробела — это не пара «ключ: значение» "
                  "YAML, харнесс поля model: не увидит" % (at, lines[i].strip()))
            rc = 1
            continue
        raw = m.group(1).split(" #", 1)[0].strip()
        if BLOCK.match(raw):
            cont = []
            for j in range(i + 1, end):
                if lines[j].strip() and lines[j][0] not in " \t":
                    break
                if lines[j].strip():
                    cont.append(lines[j].strip())
            raw = ("\n" if raw[0] == "|" else " ").join(cont)
        val = raw[1:-1].strip() if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'" else raw
        low = val.lower()
        if not val:
            print("КРАСНОЕ %s — поле model: объявлено пустым; модели в нём нет" % at)
            rc = 1
        elif low not in ALIASES:
            why = ("полный идентификатор модели запрещён нормой at-agent-model-value — только псевдоним"
                   if low.startswith("claude-") or ".anthropic." in low or "/" in low
                   else "не псевдоним из перечня нормы")
            print("КРАСНОЕ %s — model: «%s»: %s (%s); харнесс отдаст строку как есть"
                  % (at, val, why, "|".join(sorted(ALIASES))))
            rc = 1
        elif low in LIGHT_ALIASES:
            light_seen.add(agent)
            if agent not in LIGHT:
                print("КРАСНОЕ %s — model: «%s»: лёгкая модель у агента «%s», а владелец отвёл её "
                      "только %s (2026-10-08)" % (at, val, agent, ", ".join(sorted(LIGHT))))
                rc = 1

for agent in sorted(LIGHT - light_seen):
    if agent + ".md" in names:
        print("КРАСНОЕ .claude/agents/%s.md — агенту отведена лёгкая модель (владелец 2026-10-08), "
              "а model: haiku во frontmatter нет: норма объявлена, не исполняется" % agent)
    else:
        print("КРАСНОЕ — перечень лёгкой модели называет агента «%s», которого в .claude/agents нет" % agent)
    rc = 1

print("корень %s; осмотрено агентов: %d; поле model: объявлено у %d" % (root, len(names), declared))
if not names:
    print("[VOID] ОТКАЗ — в .claude/agents нет ни одного *.md: модель судить не у кого, вердикт беспредметен")
    sys.exit(2)
sys.exit(rc)
PY
