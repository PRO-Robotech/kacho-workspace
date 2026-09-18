#!/usr/bin/env bash
# Доказательство способности набора change-graph-gate УПАСТЬ — инъекцией в обе
# стороны.
#
# ЗАЧЕМ. Три зелёные проверки на сошедшемся дереве не доказывают ничего: ровно
# так же выглядит набор, потерявший способность краснеть. По каждой оси здесь
# вносится НАСТОЯЩИЙ дефект (проверка обязана покраснеть) и рядом ставится
# ЗАКОННЫЙ БЛИЗНЕЦ той же формы (проверка обязана смолчать). Без близнеца
# проверка ловила бы форму, а не существо, и первый ложный срабат её отключил бы.
#
# ТРЕТЬЯ КАТЕГОРИЯ ДОКАЗЫВАЕТСЯ ОТДЕЛЬНО. «Без предмета» (код 2) обязано
# приходить своим кодом, а не единицей: вызывающий принимает по ним прямо
# противоположные решения — находку чинят в дереве, отсутствие предмета создают
# условием. Оси VOID есть у каждой из трёх проверок.
#
# ОДИН ФАКТ НА ИНЪЕКЦИЮ. Каждая проба меняет ровно одно и меняет его там, где
# живёт предмет проверки: инъекция, попутно нарушающая соседнюю проверку,
# доказательством не является — красное пришло бы от соседа.
#
# ИЗОЛЯЦИЯ. Всё происходит во временном дереве со своим git-индексом и своим
# корнем через `CG_GATE_ROOT`. Рабочая копия не читается на запись и не меняется
# ни одной пробой. Окружение git снимается: `git push` запускает хук с
# выставленным `GIT_DIR`, и переменная сильнее рабочего каталога — без снятия
# песочница писала бы в ЭТУ рабочую копию.
#
# ЦЕНА. Пробы полосы `hook` в песочнице подменены мгновенными заглушками: предмет
# инъекции — вердикт ПРОВЕРКИ по коду пробы, а не содержимое самой пробы. Иначе
# каждая ось стоила бы минуту, и доказательство перестали бы гонять.
#
# Коды выхода: 0 — все утверждения сошлись; 1 — хотя бы одно нет.

set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0

# Пути проб полосы `hook` — выводятся из самой ведомости, а не выписываются:
# второй перечень разошёлся бы с первым молча.
mapfile -t HOOK_PROBES < <(
    python3 "$WS/scripts/change-graph-gate/lanes.py" --list hook \
        | sed -n 's/^hook  *\([^ ]*\).*/\1/p'
)

# ПРЕДПОСЫЛКА ОБЪЯВЛЯЕТСЯ, А НЕ ПОДРАЗУМЕВАЕТСЯ. Пустой вывод разбора сделал бы
# оси check-01 вакуумными: подменять было бы нечего, и «заглушка вернула 1» ни
# на что не влияло бы. Трёх мало по той же причине — индексы 1 и 2 адресуются
# явно. Ноль прочитанного обязан быть отличим от нуля находок.
if [ "${#HOOK_PROBES[@]}" -lt 3 ]; then
    echo "ОТКАЗ: разобрано проб полосы hook ${#HOOK_PROBES[@]} — предпосылка инъекций" >&2
    echo "не резолвится, доказывать нечего." >&2
    exit 1
fi
echo "предпосылка: разобрано проб полосы hook — ${#HOOK_PROBES[@]}"

# sandbox <имя> — свежая копия оснастки контура и объявления конвейера со своим
# git-индексом. Пробы полосы `hook` заменены заглушками, отвечающими нулём.
sandbox() {
    local dir="$TMP/s.$1"
    rm -rf "$dir"
    mkdir -p "$dir/scripts" "$dir/.github"
    cp -r "$WS/scripts/change-graph-gate" "$dir/scripts/"
    cp -r "$WS/.github/workflows" "$dir/.github/"
    local rel
    for rel in "${HOOK_PROBES[@]}"; do
        stub "$dir" "$rel" 0
    done
    git -C "$dir" init -q
    git -C "$dir" add -A > /dev/null 2>&1
    echo "$dir"
}

# stub <каталог> <путь пробы> <код> — заглушка на месте пробы.
#
# Заглушка ОБЯЗАНА остаться точкой входа по тому же признаку, что и настоящая
# проба (`if __name__ ==` для `.py`, шебанг для `.sh`). Первая редакция этого
# файла признак теряла — и три законных близнеца check-02 краснели от соседа, а
# не от предмета: инъекция, попутно нарушающая другую проверку, доказательством
# не является (`testing.md` §«Гейт на класс», п. 2в).
stub() {
    local dir="$1" rel="$2" code="$3" path="$1/scripts/change-graph-gate/$2"
    mkdir -p "$(dirname "$path")"
    if [ "${rel##*.}" = "py" ]; then
        printf '#!/usr/bin/env python3\nimport sys\n\n\nif __name__ == "__main__":\n    print("заглушка %s")\n    sys.exit(%s)\n' \
            "$rel" "$code" > "$path"
    else
        printf '#!/usr/bin/env bash\necho "заглушка %s"\nexit %s\n' "$rel" "$code" > "$path"
    fi
    chmod +x "$path"
}

# run <каталог> <проверка> — код возврата проверки в песочнице.
run() {
    ( cd "$1" && CG_GATE_ROOT="$1" bash "$1/scripts/change-graph-gate/$2" > /dev/null 2>&1 )
    echo $?
}

# no_yaml_root — каталог, при котором `import yaml` отказывает. Строится, а не
# отыскивается: снять разборщик из окружения нельзя, а VOID «нет разборщика» —
# самый вероятный исход в свежем клоне, и он обязан приходить кодом 2, а не 1.
no_yaml_root() {
    local dir="$TMP/noyaml"
    mkdir -p "$dir/yaml"
    printf 'raise ImportError("разборщик снят инъекцией")\n' > "$dir/yaml/__init__.py"
    echo "$dir"
}

# run_without_yaml <каталог> <проверка>
run_without_yaml() {
    ( cd "$1" && CG_GATE_ROOT="$1" PYTHONPATH="$(no_yaml_root)" \
        bash "$1/scripts/change-graph-gate/$2" > /dev/null 2>&1 )
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

C1="check-01-hook-lane-probes-are-green.sh"
C2="check-02-lane-roster-covers-every-entry-point.sh"
C3="check-03-ci-calls-every-artifact-of-the-set.sh"

echo "=== check-01: дешёвая полоса прогоняется, и её исход читается по коду ==="

d="$(sandbox c1-twin)"
assert 0 "$(run "$d" "$C1")" "законный близнец: все пробы полосы отвечают нулём -> молчит"

d="$(sandbox c1-red)"
stub "$d" "${HOOK_PROBES[1]}" 1
assert 1 "$(run "$d" "$C1")" "проба полосы вернула находку -> краснеет"

d="$(sandbox c1-void)"
stub "$d" "${HOOK_PROBES[1]}" 2
assert 2 "$(run "$d" "$C1")" "проба полосы осталась без предмета -> код 2, а не 1"

d="$(sandbox c1-mixed)"
stub "$d" "${HOOK_PROBES[1]}" 1
stub "$d" "${HOOK_PROBES[2]}" 2
assert 1 "$(run "$d" "$C1")" "находка РЯДОМ с беспредметной пробой -> по-прежнему находка"

d="$(sandbox c1-crash)"
stub "$d" "${HOOK_PROBES[1]}" 3
assert 1 "$(run "$d" "$C1")" "проба упала посторонним кодом (класс ws#503) -> находка, а не 'без предмета'"

d="$(sandbox c1-noyaml)"
assert 2 "$(run_without_yaml "$d" "$C1")" "разборщика YAML нет -> без предмета (самый вероятный исход свежего клона)"

d="$(sandbox c1-missing)"
rm -f "$d/scripts/change-graph-gate/${HOOK_PROBES[1]}"
assert 2 "$(run "$d" "$C1")" "пути ведомости в дереве нет -> без предмета"

echo
echo "=== check-02: ведомость покрывает точки входа дерева ==="

d="$(sandbox c2-twin)"
assert 0 "$(run "$d" "$C2")" "законный близнец: дерево и ведомость сходятся -> молчит"

d="$(sandbox c2-orphan)"
printf 'import sys\n\n\nif __name__ == "__main__":\n    sys.exit(0)\n' \
    > "$d/scripts/change-graph-gate/selftest/newprobe.py"
git -C "$d" add -A > /dev/null 2>&1
assert 1 "$(run "$d" "$C2")" "новая точка входа без строки ведомости -> краснеет (класс ws#504)"

d="$(sandbox c2-notentry)"
printf 'CONSTANT = 1\n' > "$d/scripts/change-graph-gate/selftest/helperdata.py"
git -C "$d" add -A > /dev/null 2>&1
assert 0 "$(run "$d" "$C2")" "законный близнец: модуль БЕЗ точки входа -> молчит"

d="$(sandbox c2-untracked)"
printf 'import sys\n\n\nif __name__ == "__main__":\n    sys.exit(0)\n' \
    > "$d/scripts/change-graph-gate/selftest/untrackedprobe.py"
assert 0 "$(run "$d" "$C2")" "законный близнец: файл не отслеживается git -> точкой входа не считается"

d="$(sandbox c2-stale)"
rm -f "$d/scripts/change-graph-gate/tests/tools/build_fixtures.py"
git -C "$d" add -A > /dev/null 2>&1
assert 1 "$(run "$d" "$C2")" "строка ведомости пережила свою точку входа -> краснеет"

d="$(sandbox c2-void)"
rm -rf "$d/scripts/change-graph-gate/selftest" "$d/scripts/change-graph-gate/tests"
git -C "$d" add -A > /dev/null 2>&1
assert 2 "$(run "$d" "$C2")" "точек входа в дереве ноль -> без предмета, а не 'находок 0'"

echo
echo "=== check-03: конвейер зовёт все артефакты набора, и зовёт на стволе ==="

d="$(sandbox c3-twin)"
assert 0 "$(run "$d" "$C3")" "законный близнец: задание объявлено и срабатывает на main -> молчит"

d="$(sandbox c3-gone)"
python3 - "$d" <<'PY'
import re
import sys
p = sys.argv[1] + "/.github/workflows/ci.yaml"
text = open(p, encoding="utf-8").read()
text = re.sub(r"^ +run: bash scripts/change-graph-gate/prove-all\.sh$",
              "        run: echo нечего", text, flags=re.M)
open(p, "w", encoding="utf-8").write(text)
PY
assert 1 "$(run "$d" "$C3")" "шаг, зовущий дорогую полосу, снят -> краснеет"

d="$(sandbox c3-cheap-gone)"
python3 - "$d" <<'PY2'
import re
import sys
# Дешёвая полоса перестала зваться конвейером: обход хука объявлен законным,
# поэтому надмножество ломается — гонять её было бы некому.
p = sys.argv[1] + "/.github/workflows/ci.yaml"
text = open(p, encoding="utf-8").read()
text = re.sub(r"^( +)run: bash scripts/change-graph-gate/run-all\.sh$",
              r"\1run: echo нечего", text, flags=re.M)
open(p, "w", encoding="utf-8").write(text)
PY2
assert 1 "$(run "$d" "$C3")" "снят вызов ДЕШЁВОЙ полосы -> краснеет: конвейер перестал быть надмножеством хука"

d="$(sandbox c3-comment)"
python3 - "$d" <<'PY'
import re
import sys
# Имя скрипта остаётся в блоке `run:`, но ТОЛЬКО комментарием. Предикат по
# подстроке зеленел бы; читающий исполняемое обязан покраснеть.
p = sys.argv[1] + "/.github/workflows/ci.yaml"
text = open(p, encoding="utf-8").read()
text = re.sub(r"^( +)run: bash scripts/change-graph-gate/prove-all\.sh$",
              r"\1run: |\n\1  # bash scripts/change-graph-gate/prove-all.sh\n\1  echo нечего",
              text, flags=re.M)
open(p, "w", encoding="utf-8").write(text)
PY
assert 1 "$(run "$d" "$C3")" "имя скрипта осталось только в комментарии блока run -> краснеет"

d="$(sandbox c3-offmain)"
python3 - "$d" <<'PY'
import sys
p = sys.argv[1] + "/.github/workflows/ci.yaml"
text = open(p, encoding="utf-8").read()
text = text.replace("    branches: [main]", "    branches: [never-fires]")
open(p, "w", encoding="utf-8").write(text)
PY
assert 1 "$(run "$d" "$C3")" "процесс перестал срабатывать на main -> задание не начнётся, краснеет"

d="$(sandbox c3-noscript)"
rm -f "$d/scripts/change-graph-gate/prove-all.sh"
git -C "$d" add -A > /dev/null 2>&1
assert 1 "$(run "$d" "$C3")" "конвейер называет скрипт, которого в дереве нет -> краснеет"

d="$(sandbox c3-noyaml)"
assert 2 "$(run_without_yaml "$d" "$C3")" "разборщика YAML нет -> объявление читать нечем, без предмета"

d="$(sandbox c3-void)"
rm -rf "$d/.github/workflows"
assert 2 "$(run "$d" "$C3")" "файлов конвейера нет -> без предмета"

echo
echo "=== перепись инъекций набора change-graph-gate ==="
echo "утверждений: $((pass + fail)) · прошло: $pass · провалено: $fail"
[ "$fail" -eq 0 ]
