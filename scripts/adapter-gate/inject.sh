#!/usr/bin/env bash
# Доказательство способности набора adapter-gate УПАСТЬ — инъекцией в обе стороны.
#
# ЗАЧЕМ. Семь зелёных проверок на сошедшемся дереве не доказывают ничего: ровно
# так же выглядит набор, потерявший способность краснеть. Здесь по каждой оси
# вносится НАСТОЯЩИЙ дефект (проверка обязана покраснеть и НАЗВАТЬ координату) и
# рядом ставится ЗАКОННЫЙ БЛИЗНЕЦ той же формы (проверка обязана смолчать). Без
# близнеца проверка ловила бы форму, а не существо, и первый ложный срабат её
# отключил бы.
#
# ОДИН ФАКТ НА ИНЪЕКЦИЮ. Каждая проба меняет ровно одно, и меняет его в том
# месте, где живёт предмет проверки: инъекция, попутно нарушающая соседнюю
# проверку, доказательством не является — красное пришло бы от соседа.
#
# ИЗОЛЯЦИЯ. Всё происходит во временном дереве: копия оснастки, свой git-индекс,
# свой корень через ADAPTER_GATE_ROOT. Рабочее дерево не читается на запись и не
# меняется ни одной пробой.
#
# Коды выхода: 0 — все утверждения сошлись; 1 — хотя бы одно нет.

set -uo pipefail

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$WS/scripts/adapter-gate"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0

# sandbox — свежая копия дерева оснастки со своим git-индексом.
sandbox() {
    local dir="$TMP/s.$1"
    rm -rf "$dir"; mkdir -p "$dir/scripts"
    cp "$WS/CLAUDE.md" "$dir/"
    cp "$WS/AGENTS.md" "$dir/" 2>/dev/null || true
    cp -r "$WS/.claude" "$dir/"
    cp -r "$WS/.agents" "$dir/" 2>/dev/null || true
    cp -r "$WS/.codex" "$dir/" 2>/dev/null || true
    cp -r "$WS/scripts/adapter" "$dir/scripts/"
    cp -r "$WS/scripts/adapter-gate" "$dir/scripts/"
    cp "$WS/.gitignore" "$dir/" 2>/dev/null || true
    git -C "$dir" init -q
    git -C "$dir" add -A >/dev/null 2>&1
    echo "$dir"
}

# run <каталог> <проверка> — код возврата проверки в песочнице.
run() {
    ( cd "$1" && ADAPTER_GATE_ROOT="$1" bash "$GATE/$2" >/dev/null 2>&1 )
    echo $?
}

# assert <ожидаемый код> <фактический> <утверждение>
assert() {
    if [ "$1" = "$2" ]; then
        echo "  [OK]   $3"
        pass=$((pass + 1))
    else
        echo "  [FAIL] $3 — ожидался код $1, получен $2" >&2
        fail=$((fail + 1))
    fi
}

echo "== контроль: нетронутая копия — все проверки молчат =="
d="$(sandbox control)"
checks=0
for c in "$GATE"/check-*.sh; do
    [ -f "$c" ] || continue
    checks=$((checks + 1))
    n="$(basename "$c")"
    assert 0 "$(run "$d" "$n")" "нетронутая копия · $n"
done

# Пустой обход — ОТКАЗ, а не молчаливый успех. Без этой строки инъекция,
# потерявшая свои проверки (каталог переехал, глоб перестал совпадать), вышла бы
# нулём и объявила бы доказанным то, чего не прогоняла ни разу.
if [ "$checks" -eq 0 ]; then
    echo "инъекция adapter-gate: проверок в $GATE не найдено — доказывать нечего" >&2
    exit 1
fi

echo
echo "== ось 1: точный набор манифеста против дерева =="
d="$(sandbox extra)"
printf 'name = "x"\n' > "$d/.codex/agents/лишний.toml"
git -C "$d" add -A >/dev/null 2>&1
assert 1 "$(run "$d" check-01-manifest-matches-tree.sh)" \
    "ДЕФЕКТ: лишний отслеживаемый выход во владеемом пространстве"

d="$(sandbox missing)"
rm -f "$d/.codex/hooks.json"
git -C "$d" add -A >/dev/null 2>&1
assert 1 "$(run "$d" check-01-manifest-matches-tree.sh)" \
    "ДЕФЕКТ: объявленный выход снят из дерева"

d="$(sandbox foreign)"
mkdir -p "$d/.agents/skills/superpowers/references"
printf -- '---\nname: superpowers\n---\nчужая установка\n' \
    > "$d/.agents/skills/superpowers/SKILL.md"
printf 'чужой вложенный ресурс\n' \
    > "$d/.agents/skills/superpowers/references/EXAMPLES.md"
git -C "$d" add -A >/dev/null 2>&1
assert 0 "$(run "$d" check-01-manifest-matches-tree.sh)" \
    "БЛИЗНЕЦ: чужой пакет вне манифеста лишним выходом НЕ считается"

echo
echo "== ось 2: производное против регенерации =="
d="$(sandbox drift)"
printf '\nодин лишний байт\n' >> "$d/AGENTS.md"
git -C "$d" add -A >/dev/null 2>&1
assert 1 "$(run "$d" check-02-derived-matches-regeneration.sh)" \
    "ДЕФЕКТ: правка производного руками"

d="$(sandbox stale)"
printf '\n<!-- правка канонического входа без регенерации -->\n' >> "$d/CLAUDE.md"
git -C "$d" add -A >/dev/null 2>&1
assert 1 "$(run "$d" check-02-derived-matches-regeneration.sh)" \
    "ДЕФЕКТ: вход правлен, производное не перегенерировано"

d="$(sandbox foreigndrift)"
mkdir -p "$d/.agents/skills/superpowers"
printf 'чужой пакет изменён\n' > "$d/.agents/skills/superpowers/SKILL.md"
git -C "$d" add -A >/dev/null 2>&1
assert 0 "$(run "$d" check-02-derived-matches-regeneration.sh)" \
    "БЛИЗНЕЦ: правка чужого пакета расхождением владеемого НЕ является"

# Несущее утверждение приёмки: чужой пакет не МАСКИРУЕТ расхождение владеемого.
d="$(sandbox maskattempt)"
mkdir -p "$d/.agents/skills/superpowers"
printf 'чужой пакет на месте\n' > "$d/.agents/skills/superpowers/SKILL.md"
printf '\nодин лишний байт\n' >> "$d/AGENTS.md"
git -C "$d" add -A >/dev/null 2>&1
assert 1 "$(run "$d" check-02-derived-matches-regeneration.sh)" \
    "ДЕФЕКТ: при неизменном чужом пакете расхождение владеемого всё равно найдено"

echo
echo "== ось 3: детерминизм регенерации =="
d="$(sandbox nondet)"
python3 - "$d/scripts/adapter/generate.py" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = '    produced["AGENTS.md"] = render_agents_md(reader, manifest).encode("utf-8")'
new = ('    import time\n'
       '    produced["AGENTS.md"] = (render_agents_md(reader, manifest)\n'
       '        + ("\\n<!-- %s -->\\n" % time.time_ns())).encode("utf-8")')
assert s.count(old) == 1
io.open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
assert 1 "$(run "$d" check-03-regeneration-deterministic.sh)" \
    "ДЕФЕКТ: генератор вносит отметку времени"

d="$(sandbox det)"
python3 - "$d/scripts/adapter/generate.py" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = '    produced["AGENTS.md"] = render_agents_md(reader, manifest).encode("utf-8")'
new = ('    produced["AGENTS.md"] = (render_agents_md(reader, manifest)\n'
       '        + "\\n<!-- постоянная приписка -->\\n").encode("utf-8")')
assert s.count(old) == 1
io.open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
assert 0 "$(run "$d" check-03-regeneration-deterministic.sh)" \
    "БЛИЗНЕЦ: постоянная приписка той же формы детерминизма не нарушает"

echo
echo "== ось 4: заглавная форма имени второй среды =="
d="$(sandbox upper)"
printf '\nкоордината .Codex/hooks/x.sh в теле агента\n' \
    >> "$d/.claude/agents/proto-sync.md"
( cd "$d" && python3 scripts/adapter/generate.py --quiet >/dev/null 2>&1 )
git -C "$d" add -A >/dev/null 2>&1
assert 1 "$(run "$d" check-04-canonical-case.sh)" \
    "ДЕФЕКТ: заглавная форма доехала до производного"

d="$(sandbox lower)"
printf '\nкоордината .codex/hooks/x.sh в теле агента\n' \
    >> "$d/.claude/agents/proto-sync.md"
( cd "$d" && python3 scripts/adapter/generate.py --quiet >/dev/null 2>&1 )
git -C "$d" add -A >/dev/null 2>&1
assert 0 "$(run "$d" check-04-canonical-case.sh)" \
    "БЛИЗНЕЦ: строчная форма той же координаты законна"

echo
echo "== ось 5: абсолютный путь, ВНЕСЁННЫЙ генератором =="
d="$(sandbox abspath)"
python3 - "$d/scripts/adapter/generate.py" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = r'CANONICAL=\"$ROOT/.claude/hooks/%s\"'
new = r'CANONICAL=\"/home/выдуманный-оператор/kacho/.claude/hooks/%s\"'
assert s.count(old) == 1
io.open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
( cd "$d" && python3 scripts/adapter/generate.py --quiet >/dev/null 2>&1 )
git -C "$d" add -A >/dev/null 2>&1
assert 1 "$(run "$d" check-05-generated-paths-portable.sh)" \
    "ДЕФЕКТ: генератор вписал абсолютный путь машины"

d="$(sandbox absquote)"
printf '\nнаблюдалось в рабочей копии /home/выдуманный-оператор/kacho\n' \
    >> "$d/.claude/agents/proto-sync.md"
( cd "$d" && python3 scripts/adapter/generate.py --quiet >/dev/null 2>&1 )
git -C "$d" add -A >/dev/null 2>&1
assert 0 "$(run "$d" check-05-generated-paths-portable.sh)" \
    "БЛИЗНЕЦ: тот же путь ЦИТАТОЙ из канонического входа находкой не является"

echo
echo "== ось 6: каноничность входов =="
d="$(sandbox openinput)"
python3 - "$d/scripts/adapter/generate.py" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = "        if not self.manifest.is_canonical(relpath):\n            raise GeneratorError(\n                \"попытка прочитать неканонический вход: %s \""
new = "        if False:\n            raise GeneratorError(\n                \"попытка прочитать неканонический вход: %s \""
assert s.count(old) == 1
io.open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
assert 1 "$(run "$d" check-06-inputs-are-canonical.sh)" \
    "ДЕФЕКТ: снята проверка каноничности в генераторе"

d="$(sandbox ghostinput)"
python3 - "$d/.claude/adapters.yaml" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = "  - .claude/settings.json\n"
assert s.count(old) >= 1
io.open(p, "w", encoding="utf-8").write(
    s.replace(old, old + "  - docs/несуществующий-вход.md\n", 1))
PY
assert 1 "$(run "$d" check-06-inputs-are-canonical.sh)" \
    "ДЕФЕКТ: объявлен вход, которого нет в дереве"

echo
echo "== ось 7: перечень пакетов против оснастки =="
d="$(sandbox newskill)"
mkdir -p "$d/.claude/skills/новый-скил"
printf -- '---\nname: новый-скил\ndescription: проба\n---\n\nтело\n' \
    > "$d/.claude/skills/новый-скил/SKILL.md"
git -C "$d" add -A >/dev/null 2>&1
assert 1 "$(run "$d" check-07-skills-roster-matches-tree.sh)" \
    "ДЕФЕКТ: скил оснастки не объявлен пакетом манифеста"

d="$(sandbox foreignskill)"
mkdir -p "$d/.claude/skills/defuddle"
printf -- '---\nname: defuddle\n---\n\nчужая установка\n' \
    > "$d/.claude/skills/defuddle/SKILL.md"
git -C "$d" add -A >/dev/null 2>&1
assert 0 "$(run "$d" check-07-skills-roster-matches-tree.sh)" \
    "БЛИЗНЕЦ: сторонний скил, объявленный чужим в .gitignore, в перечень не входит"

echo
echo "== предпосылка: без манифеста набор БЕЗ ПРЕДМЕТА, а не зелёный =="
d="$(sandbox nomanifest)"
rm -f "$d/.claude/adapters.yaml"
assert 2 "$(run "$d" check-01-manifest-matches-tree.sh)" \
    "манифеста нет — код 2 (без предмета), не 0"

echo
# Перепись объёма осмотренного — отдельным утверждением, а не подразумеваемым:
# «утверждений 0, разошлось 0» иначе печаталось бы как успех.
echo "перепись инъекции: проверок набора осмотрено $checks; осей инъекции 7;" \
     "утверждений $((pass + fail)) — сошлось $pass, разошлось $fail"
if [ "$((pass + fail))" -eq 0 ]; then
    echo "инъекция adapter-gate: не прогнано ни одного утверждения — это НЕ успех" >&2
    exit 1
fi
[ "$fail" -eq 0 ] || exit 1
exit 0
