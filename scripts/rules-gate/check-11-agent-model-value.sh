#!/usr/bin/env bash
# check-11 — ПОЛЕ `model:` ВО FRONTMATTER АГЕНТА НЕСЁТ ЗНАЧЕНИЕ, КОТОРОЕ ХАРНЕСС ПРИМЕТ.
#
# Предмет: `.claude/agents/*.md`, строка `model:` между первыми `---`. С ws#975 у
# механических агентов там стоит лёгкая модель (решение владельца 2026-09-27
# «механика на лёгкой модели»). Опечатка в этом поле не видна ни в диффе, ни в
# прогоне: харнесс получает строку, которой нет среди моделей, и агент либо не
# стартует (строка уходит в запрос как имя модели), либо берёт модель родителя
# (ветка списка разрешённых моделей) — то есть норма «механика на лёгкой модели»
# перестаёт исполняться, а файл продолжает её объявлять.
#
# ЗАКОННЫЕ ФОРМЫ ЗНАЧЕНИЯ ВЫВЕДЕНЫ ИЗ КОДА ХАРНЕССА, а не из описания поля
# (ревизия CC 2.1.293, бинарь ~/.local/share/claude/versions/2.1.293, 2026-10-08).
# Модель агента разрешает функция подбора модели сабагента; она зовёт резолвер
# псевдонима и, если значение не псевдоним, отдаёт строку как есть — то есть
# неизвестная строка не отвергается харнессом, а уходит дальше чужой моделью.
# Поэтому проверка судит по тем двум распознавателям, которыми харнесс отличает
# модель от произвольной строки:
#   · ПСЕВДОНИМ — резолвер приводит значение к нижнему регистру, снимает суффикс
#     окна `[1m]` и сверяет основу со списком псевдонимов харнесса:
#     sonnet | opus | haiku | fable | best | opusplan (список целиком:
#     `grep -ao '\["sonnet","opus","haiku","fable","best",[^;]*"opusplan"\]' <бинарь>`
#     → ["sonnet","opus","haiku","fable","best","sonnet[1m]","opus[1m]","fable[1m]","opusplan"]);
#     плюс `inherit` из схемы определения агента (тоже без учёта регистра);
#   · ПОЛНЫЙ ИДЕНТИФИКАТОР — разборщик идентификатора модели харнесса: нижний
#     регистр, без пробелов, необязательный суффикс `[1m]`/`[2m]`, необязательный
#     путь до последнего `/`, необязательный префикс `<регион>.anthropic.`
#     (регион из us|eu|apac|jp|au|us-gov|global), затем `claude-<семейство>-<мажор>
#     [-<минор>]` или `claude-<мажор>[-<минор>]-<семейство>`, а хвост после основы
#     пуст либо начинается с `-` или `@`. `claude-haiko` (нет версии) и
#     `claude-sonnet-4-5x` (хвост без разделителя) этот разборщик отвергает.
# Отсутствие поля — законно (агент берёт модель по умолчанию) и находкой не
# является; пустое значение — находка: поле объявлено, а модели в нём нет.
# `model:haiku` без пробела после двоеточия — не пара «ключ: значение» YAML:
# харнесс поля не увидит, и это находка, а не законное объявление.
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

ALIAS_BASES = {"sonnet", "opus", "haiku", "fable", "best", "opusplan"}
REGIONS = {"us", "eu", "apac", "jp", "au", "us-gov", "global"}
ID_FAMILY_FIRST = re.compile(r"^claude-([a-z]+)-(\d{1,2})(?!\d)(?:-(\d{1,2})(?!\d))?")
ID_VERSION_FIRST = re.compile(r"^claude-(\d{1,2})(?!\d)(?:-(\d{1,2})(?!\d))?-([a-z]+)")


def is_alias(v):
    n = v.strip().lower()
    if n == "inherit":
        return True
    return re.sub(r"\[1m\]$", "", n).strip() in ALIAS_BASES


def is_model_id(v):
    n = v.strip().lower()
    if n == "" or re.search(r"\s", n):
        return False
    n = re.sub(r"\[[12]m\]$", "", n)
    n = n[n.rfind("/") + 1:]
    m = re.match(r"^(?:([a-z-]+)\.)?anthropic\.(claude-.*)$", n)
    if m:
        if m.group(1) is not None and m.group(1) not in REGIONS:
            return False
        n = m.group(2)
    base = ID_FAMILY_FIRST.match(n) or ID_VERSION_FIRST.match(n)
    if not base:
        return False
    tail = n[base.end():]
    return tail == "" or tail[0] in "-@"


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
        if m.group(1) and m.group(1)[0] not in " \t":
            print("КРАСНОЕ %s:%d — «%s»: после двоеточия нет пробела — это не пара «ключ: значение» "
                  "YAML, харнесс поля model: не увидит" % (rel, i, line.strip()))
            rc = 1
            continue
        raw = m.group(1).split(" #", 1)[0].strip()
        val = raw[1:-1].strip() if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'" else raw
        if not val:
            print("КРАСНОЕ %s:%d — поле model: объявлено пустым; модели в нём нет" % (rel, i))
            rc = 1
        elif not is_alias(val) and not is_model_id(val):
            print("КРАСНОЕ %s:%d — model: «%s» не псевдоним харнесса (%s[1m]|inherit) и не "
                  "идентификатор claude-<семейство>-<версия>: харнесс отдаст строку как есть, "
                  "норма о модели агента не исполнится"
                  % (rel, i, val, "|".join(sorted(ALIAS_BASES))))
            rc = 1

print("корень %s; осмотрено агентов: %d; поле model: объявлено у %d" % (root, len(names), declared))
if not names:
    print("[VOID] ОТКАЗ — в .claude/agents нет ни одного *.md: модель судить не у кого, вердикт беспредметен")
    sys.exit(2)
sys.exit(rc)
PY
