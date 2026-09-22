#!/usr/bin/env bash
# ДОКАЗЫВАЕТ: check-16-base-and-agent-agree-on-subject.sh (зовётся из inject.sh; строку читает его перепись доказанности)
# Инъекция для `measure-base-agent-subject-conflict.py` — в обе стороны.
#
# Миры СИНТЕТИЧЕСКИЕ (`mktemp -d`), а не живая запись дерева: самопроверка,
# построенная на настоящем агенте, краснеет от чужой правки и зеленеет от
# починки предмета, то есть меряет не себя.
#
# Каждый мир отличается от законного близнеца ОДНИМ фактом; полярность
# утверждения ни в один факт не входит — она сама предмет оси A'.
#
#   A    предмет стоит и в `Когда:`, и в `НЕ запускать:`, полярность ОДНА  -> 1
#   A'   тот же предмет, полярность РАЗНАЯ (стороны дополняют друг друга)  -> 0
#   B    предметы разные                                                   -> 0
#   VOID у агентов нет `НЕ запускать:` — предмета нет, и это не зелёное    -> 2
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$SELF_DIR/measure-base-agent-subject-conflict.py"
PASS=0
FAIL=0

sandbox() {
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/probe-bas-XXXXXX")"
  mkdir -p "$dir/scripts/tooling-gate" "$dir/.claude/agents"
  cp "$TOOL" "$dir/scripts/tooling-gate/"
  printf '%s\n' "# База маршрутизации" "" "## 5. Каталог агентов" "" > "$dir/.claude/agents/dispatcher.md"
  echo "$dir"
}

entry() { # <dir> <агент> <строка Когда>
  printf '%s\n' "### $2" "Когда: $3" "Нет: предмета нет." "" >> "$1/.claude/agents/dispatcher.md"
}

agent() { # <dir> <агент> <строка НЕ запускать>
  cat > "$1/.claude/agents/$2.md" <<AEOF
---
name: $2
description: "Проба. НЕ запускать: $3. Не коммитит."
disallowedTools: Agent
---

# Проба
AEOF
}

run_probe() { python3 "$1/scripts/tooling-gate/measure-base-agent-subject-conflict.py" >/dev/null 2>&1; echo $?; }

assert_code() { # <ожидаемый> <фактический> <что доказано>
  if [ "$1" = "$2" ]; then
    echo "  ✔ $3 (код $2)"; PASS=$((PASS+1))
  else
    echo "  ✘ $3 — ожидался код $1, получен $2"; FAIL=$((FAIL+1))
  fi
}

echo "инъекция measure-base-agent-subject-conflict:"

# ── ось A: предмет в обоих списках, полярность одна ─────────────────────────
d="$(sandbox)"
entry "$d" probe-agent "замысел и маршрут работ контура"
agent "$d" probe-agent "нужен технический замысел или маршрут работ"
assert_code 1 "$(run_probe "$d")" "ДЕФЕКТ: предмет и в \`Когда:\`, и в \`НЕ запускать:\` — краснеет"
rm -rf "$d"

# ── ось A': ТОТ ЖЕ предмет, но полярность разная ────────────────────────────
# Стороны согласны: база запускает, когда предмета НЕТ; агент запрещает, когда
# он ЕСТЬ. Отличие от оси A — ровно одно слово отрицания.
d="$(sandbox)"
entry "$d" probe-agent "нет действующего замысла и маршрута работ"
agent "$d" probe-agent "действующий замысел и маршрут работ уже есть"
assert_code 0 "$(run_probe "$d")" "БЛИЗНЕЦ: тот же предмет, полярности разные — молчит"
rm -rf "$d"

# ── ось B: предметы разные ──────────────────────────────────────────────────
d="$(sandbox)"
entry "$d" probe-agent "замысел и маршрут работ контура"
agent "$d" probe-agent "нужен вердикт приёмки на этот отпечаток"
assert_code 0 "$(run_probe "$d")" "БЛИЗНЕЦ: предметы разные — молчит"
rm -rf "$d"

# ── ось VOID: предмета нет — код 2, а не зелёное ────────────────────────────
d="$(sandbox)"
entry "$d" probe-agent "замысел и маршрут работ контура"
cat > "$d/.claude/agents/probe-agent.md" <<'AEOF'
---
name: probe-agent
description: "Проба без половины запрета."
disallowedTools: Agent
---

# Проба
AEOF
assert_code 2 "$(run_probe "$d")" "ПРЕДМЕТА НЕТ: ни одной пары клауз — код 2, не зелёное"
rm -rf "$d"

echo "инъекция: пройдено $PASS, провалено $FAIL"
[ "$FAIL" -eq 0 ]
