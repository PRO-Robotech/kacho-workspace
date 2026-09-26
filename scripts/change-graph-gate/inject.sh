#!/usr/bin/env bash
# Доказательство способности набора change-graph-gate УПАСТЬ — инъекцией в обе
# стороны.
#
# ЗАЧЕМ. Зелёные проверки на сошедшемся дереве не доказывают ничего: ровно
# так же выглядит набор, потерявший способность краснеть. По каждой оси здесь
# вносится НАСТОЯЩИЙ дефект (проверка обязана покраснеть) и рядом ставится
# ЗАКОННЫЙ БЛИЗНЕЦ той же формы (проверка обязана смолчать). Без близнеца
# проверка ловила бы форму, а не существо, и первый ложный срабат её отключил бы.
#
# ТРЕТЬЯ КАТЕГОРИЯ ДОКАЗЫВАЕТСЯ ОТДЕЛЬНО. «Без предмета» (код 2) обязано
# приходить своим кодом, а не единицей: вызывающий принимает по ним прямо
# противоположные решения — находку чинят в дереве, отсутствие предмета создают
# условием. Оси VOID есть у каждой проверки набора.
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
C4="check-04-package-releases-reproduce.sh"

# commit_all <каталог> <сообщение> — коммит песочницы. Подпись — в конфиге
# выброшенного репозитория: он живёт до конца пробы и на origin не попадает.
commit_all() {
    git -C "$1" config user.name 'cg-gate probe'
    git -C "$1" config user.email 'probe@invalid'
    git -C "$1" add -A > /dev/null 2>&1
    git -C "$1" commit -q --allow-empty -m "$2" > /dev/null 2>&1
}

# world4 <каталог> — мир check-04: корень-cutover, затем реестр и пакет
# `pkg-a`, сходящиеся друг с другом (роль замысла освобождена канонической
# строкой, роль схождения применима и держится `human-convergence`), и соседний
# пакет `pkg-b` без документов и без holders.yaml.
# Предмет check-04 — СВЕРКА; способность производителя отказать доказывает
# полоса hook (`selftest/prove_applicability.py`), здесь она не повторяется.
world4() {
    commit_all "$1" cutover
    python3 - "$1" "$(git -C "$1" rev-parse HEAD)" <<'PYW4'
import os
import sys
root, cutover = sys.argv[1], sys.argv[2]
def write(rel, text):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write(text)
write("docs/changes/policy.yaml", f"""schema_version: 1
repositories:
  - repo: PRO-Robotech/kacho-workspace
    cutover_commit: {cutover}
  - repo: PRO-Robotech/kacho
    cutover_commit: {"0" * 40}
review_authority:
  design-reviewer: [probe]
  convergence-reviewer: [probe]
applicability_predicates:
  - id: no-design-document-in-change
    role: design-reviewer
    evidence_field: design_documents_referenced
    satisfied_when: equals
    value: 0
""")
for pkg in ("pkg-a", "pkg-b"):
    write(f"docs/changes/{pkg}/change.yaml",
          f"schema_version: 1\nchange_id: {pkg}\nhashes:\n  design_sha256: null\n")
write("docs/changes/pkg-a/holders.yaml", """schema_version: 1
change_id: pkg-a
role_applicability:
  design-reviewer:
    status: not-applicable
    predicate_id: no-design-document-in-change
    evidence_field: design_documents_referenced
    evidence_value: 0
    evidence_command: >-
      python3 scripts/change-graph-gate/applicability.py field
      design_documents_referenced --package docs/changes/pkg-a --rev HEAD
  convergence-reviewer:
    status: applicable
    holder: human-convergence
required_holders:
  human-convergence:
    kind: human-external
    owner: convergence-reviewer
""")
PYW4
    commit_all "$1" world
}

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

# ФИКСТУРА ЗАВОДИТ АВТОЗАПУСК САМА. С решения владельца 2026-09-20 его в дереве нет
# вовсе, и близнец на нетронутой копии доказывал бы «ось спит», а не «задание
# объявлено и срабатывает со ствола».
d="$(sandbox c3-twin)"
python3 - "$d" <<'PYWF'
import sys
p = sys.argv[1] + "/.github/workflows/ci.yaml"
text = open(p, encoding="utf-8").read()
text = text.replace("on:\n  workflow_dispatch:",
                    "on:\n  push:\n    branches: [main]\n  workflow_dispatch:", 1)
open(p, "w", encoding="utf-8").write(text)
PYWF
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

# Предмет оси — автозапуск, который ЕСТЬ и идёт МИМО ствола. Прежде фикстура правила
# строку `branches: [main]`; строки больше нет, правка стала пустой операцией — и
# проба зеленела, ничего не доказав.
d="$(sandbox c3-offmain)"
python3 - "$d" <<'PYWF'
import sys
p = sys.argv[1] + "/.github/workflows/ci.yaml"
text = open(p, encoding="utf-8").read()
text = text.replace("on:\n  workflow_dispatch:",
                    "on:\n  push:\n    branches: [never-fires]\n  workflow_dispatch:", 1)
open(p, "w", encoding="utf-8").write(text)
PYWF
assert 1 "$(run "$d" "$C3")" "автозапуск есть, но мимо ствола -> задание не начнётся, краснеет"

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
echo "=== check-04: освобождения ролей в пакетах пересчитаны по реестру ==="

d="$(sandbox c4-twin)"
world4 "$d"
assert 0 "$(run "$d" "$C4")" "законный близнец: пакет и реестр сходятся -> молчит"

d="$(sandbox c4-design)"
world4 "$d"
printf '# замысел\n' > "$d/docs/changes/pkg-a/design.md"
commit_all "$d" "документ замысла при заявленном освобождении"
assert 1 "$(run "$d" "$C4")" "документ замысла появился, освобождение заявлено -> краснеет"

d="$(sandbox c4-staged)"
world4 "$d"
printf '# замысел\n' > "$d/docs/changes/pkg-a/design.md"
git -C "$d" add -A > /dev/null 2>&1
assert 0 "$(run "$d" "$C4")" "законный близнец: документ в индексе, но не в коммите -> молчит (судится коммит)"

d="$(sandbox c4-foreign-package)"
world4 "$d"
sed -i 's|--package docs/changes/pkg-a|--package docs/changes/pkg-b|' "$d/docs/changes/pkg-a/holders.yaml"
commit_all "$d" "команда свидетельства называет чужой существующий пакет"
assert 1 "$(run "$d" "$C4")" "команда называет чужой пакет (опыт N2) -> краснеет, хотя там тоже 0"

d="$(sandbox c4-role-missing)"
world4 "$d"
python3 - "$d/docs/changes/policy.yaml" <<'PYR'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
t = t.replace("  convergence-reviewer: [probe]\n",
              "  convergence-reviewer: [probe]\n  wave-reviewer: [probe]\n", 1)
open(p, "w", encoding="utf-8").write(t)
PYR
commit_all "$d" "роль в реестре, строки в пакете нет"
assert 1 "$(run "$d" "$C4")" "роль реестра без строки role_applicability -> краснеет"

# Покрытие ролей держателями (опыты S1 и W7 приёмки, круг 2): пакет без раздела
# освобождений не имеет, и держатель нужен каждой роли; держатель освобождённой
# роли — находка без всяких файлов свидетельства.
d="$(sandbox c4-no-section)"
world4 "$d"
printf 'schema_version: 1\nchange_id: pkg-b\n' > "$d/docs/changes/pkg-b/holders.yaml"
commit_all "$d" "пакет без раздела role_applicability и без держателей"
assert 1 "$(run "$d" "$C4")" "пакет без раздела и без держателей (опыт S1) -> краснеет"

d="$(sandbox c4-no-section-held)"
world4 "$d"
printf 'schema_version: 1\nchange_id: pkg-b\nrequired_holders:\n  h-design:\n    owner: design-reviewer\n  h-conv:\n    owner: convergence-reviewer\n' \
    > "$d/docs/changes/pkg-b/holders.yaml"
commit_all "$d" "пакет без раздела, у каждой роли держатель"
assert 0 "$(run "$d" "$C4")" "законный близнец: пакет без раздела, каждая роль держится -> молчит"

d="$(sandbox c4-released-held)"
world4 "$d"
printf '  human-design:\n    kind: human-external\n    owner: design-reviewer\n' \
    >> "$d/docs/changes/pkg-a/holders.yaml"
commit_all "$d" "держатель освобождённой роли остался в required_holders"
assert 1 "$(run "$d" "$C4")" "освобождённая роль держит держателя (опыт W7) -> краснеет"

d="$(sandbox c4-applicable-unheld)"
world4 "$d"
python3 - "$d/docs/changes/pkg-a/holders.yaml" <<'PYU'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
head, sep, _ = t.partition("required_holders:\n")
assert sep, "раздела required_holders в мире нет — опыт не ставится"
open(p, "w", encoding="utf-8").write(head + "required_holders: {}\n")
PYU
commit_all "$d" "у применимой роли держателя нет"
assert 1 "$(run "$d" "$C4")" "применимая роль без держателя -> краснеет"

d="$(sandbox c4-void)"
world4 "$d"
rm -f "$d/docs/changes/pkg-a/holders.yaml"
commit_all "$d" "пакетов с holders.yaml нет"
assert 2 "$(run "$d" "$C4")" "пакетов с holders.yaml нет -> без предмета, а не 'находок 0'"

d="$(sandbox c4-nocommit)"
assert 2 "$(run "$d" "$C4")" "в песочнице нет ни одного коммита -> без предмета"

d="$(sandbox c4-noyaml)"
world4 "$d"
assert 2 "$(run_without_yaml "$d" "$C4")" "разборщика YAML нет -> без предмета"

echo
echo "=== check-05: команда дайджеста в новых записях ревью несёт --full-index ==="

C5="check-05-review-digest-is-full-index.sh"

# rec <каталог> <путь> <текст> — запись ревью в песочнице.
rec() { mkdir -p "$(dirname "$1/$2")"; printf '%s\n' "$3" >> "$1/$2"; }

# world5 <каталог> [<текст унаследованной записи>] — граница: коммит с записью,
# чья команда без --full-index. Граница вписывается в ЕДИНСТВЕННОЕ место, где
# гейт её объявляет; не вписалась — пробы о другом гейте, отказ.
world5() {
    local g="$1/scripts/change-graph-gate/digestform.py" b
    rec "$1" docs/changes/p/reviews/post-diff/r/old.yaml \
        "${2-command: git diff aaa...bbb | sha256sum}"
    commit_all "$1" boundary
    b="$(git -C "$1" rev-parse HEAD)"
    sed -i "s/^BOUNDARY = \"[0-9a-f]\{40\}\"$/BOUNDARY = \"$b\"/" "$g" 2> /dev/null
    grep -qx "BOUNDARY = \"$b\"" "$g" 2> /dev/null \
        || { echo "ОТКАЗ: границы в $g вписать некуда" >&2; exit 1; }
}

# says <каталог> <код> <подстрока> <утверждение> — код И текст: находка обязана
# назвать координату, а не симптом.
says() {
    local out rc
    out="$(cd "$1" && CG_GATE_ROOT="$1" bash "$1/scripts/change-graph-gate/$C5" 2>&1)"; rc=$?
    case "$out" in *"$3"*) ;; *) rc="$rc без «$3» в выводе" ;; esac
    assert "$2" "$rc" "$4"
}

NEW=docs/specs/reviews/x-acceptance/new.yaml

d="$(sandbox c5-twin)"; world5 "$d"
says "$d" 0 "записей 1" "законный близнец: новых записей нет, унаследованная команда не судится -> молчит"

d="$(sandbox c5-bad)"; world5 "$d"
rec "$d" "$NEW" "command: git diff aaa...ccc | sha256sum"; commit_all "$d" new
says "$d" 1 "$NEW" "новая запись без --full-index -> краснеет и называет путь"

d="$(sandbox c5-good)"; world5 "$d"
rec "$d" "$NEW" "command: git diff --full-index aaa...ccc | sha256sum"; commit_all "$d" new
says "$d" 0 "без --full-index 1" "законный близнец: та же запись с --full-index -> молчит"

d="$(sandbox c5-folded)"; world5 "$d"
rec "$d" "$NEW" $'command: >-\n  git diff aaa...ccc\n  | sha256sum'; commit_all "$d" new
says "$d" 1 "$NEW" "команда разнесена по строкам свёрнутого скаляра -> краснеет"

d="$(sandbox c5-option)"; world5 "$d"
rec "$d" "$NEW" "command: git -C project/kacho diff aaa...ccc | sha256sum"; commit_all "$d" new
says "$d" 1 "$NEW" "форма git -C <клон> diff -> краснеет"

# form5 <имя> <команда до diff> <форма> — пара по форме записи опции git перед
# diff: без --full-index краснеет находкой распознавателя (а не нераспознанной
# формой), с ним молчит И сосчитана — близнец зелен потому, что увиден.
# Формы: из обхода записей дерева (-C с заполнителем в пробелах — ws#827) и из
# грамматики git 2.53 для опций с отдельным аргументом.
form5() {
    local d
    d="$(sandbox "c5-form-$1")"; world5 "$d"
    rec "$d" "$NEW" "command: $2 diff aaa...ccc | sha256sum"; commit_all "$d" new
    says "$d" 1 "без --full-index: $NEW" "форма $3 без --full-index -> краснеет и называет путь"
    d="$(sandbox "c5-form-$1-full")"; world5 "$d"
    rec "$d" "$NEW" "command: $2 diff --full-index aaa...ccc | sha256sum"; commit_all "$d" new
    says "$d" 0 "с --full-index 1," "законный близнец: форма $3 с --full-index -> молчит и сосчитана"
}
form5 placeholder 'git -C <копия полосы>' 'git -C <заполнитель с пробелом>'
form5 dquote 'git -C "<путь с пробелом>"' 'git -C "<путь в двойных кавычках>"'
form5 squote "git -C '/srv/копия полосы'" "git -C '<путь в одинарных кавычках>'"
form5 eqvalue 'git --git-dir="<копия полосы>/.git"' 'git --опция="<значение с пробелом>"'
for o in git-dir work-tree namespace config-env attr-source; do
    form5 "sep-$o" "git --$o <копия полосы>" "git --$o <отдельный аргумент>"
done

d="$(sandbox c5-lane-copy)"; world5 "$d"
rec "$d" "$NEW" $'digest_definition: >-\n  git -C <копия полосы> diff 253c...51ab\n  -- . \':!docs/specs/reviews\' | sha256sum — перемерено своей командой'
commit_all "$d" new
says "$d" 1 "без --full-index: $NEW" "форма записи ws#827 (свёрнутый скаляр, -C <копия полосы>, pathspec) без --full-index -> краснеет"

# Прямое звено `git … diff … | хеш`, которого распознаватель не разбирает, —
# находка с координатой, и с --full-index тоже: форму гейт не судит, и «ноль
# находок» о ней было бы ложью. Унаследованное с границы — сосчитано, молчит.
d="$(sandbox c5-unparsed)"; world5 "$d"
rec "$d" "$NEW" 'command: git -C $(git rev-parse --show-toplevel) diff --full-index aaa...ccc | sha256sum'
commit_all "$d" new
says "$d" 1 "не разобрана распознавателем: $NEW" "звено git … diff | хеш вне распознавателя -> краснеет, а не молчит"

d="$(sandbox c5-unparsed-old)"
world5 "$d" $'command: git diff aaa...bbb | sha256sum\nodd: git -C $(git rev-parse --show-toplevel) diff aaa...bbb | sha256sum'
says "$d" 0 "не разобрано 1 (унаследовано 1, новых 0)" "законный близнец: то же звено на границе в том же пути -> молчит и сосчитано"

d="$(sandbox c5-chain)"; world5 "$d"
rec "$d" "$NEW" "set: git diff --raw --no-abbrev aaa...ccc | LC_ALL=C sort | sha256sum"; commit_all "$d" new
says "$d" 0 "иных труб 1 · записей с трубой без команды дайджеста 1" "цепочка diff | звено | хеш не судится (объявлено) -> молчит, но сосчитана"

d="$(sandbox c5-edit)"; world5 "$d"
rec "$d" docs/changes/p/reviews/post-diff/r/old.yaml "again: git diff aaa...ddd | sha256sum"
commit_all "$d" edit
says "$d" 1 "old.yaml" "в унаследованную запись дописана вторая команда без --full-index -> краснеет"

d="$(sandbox c5-inline)"; world5 "$d"
rec "$d" "$NEW" 'note: "`git diff --quiet aaa bbb -- x` → 0; `git show aaa:x | sha256sum`"'
commit_all "$d" new
says "$d" 0 "записей 2" "законный близнец: git diff без трубы в хеш, граница инлайн-кода -> молчит"

d="$(sandbox c5-staged)"; world5 "$d"
rec "$d" "$NEW" "command: git diff aaa...ccc | sha256sum"; git -C "$d" add -A > /dev/null 2>&1
says "$d" 0 "записей 1" "законный близнец: запись в индексе, не в коммите -> молчит (судится коммит)"

d="$(sandbox c5-empty)"; world5 "$d"
git -C "$d" rm -rq docs; commit_all "$d" empty
says "$d" 1 "записей 0" "записей на ревизии ноль -> пустой обход — находка, а не зелёное"

d="$(sandbox c5-blind)"; world5 "$d" "command: none"
says "$d" 1 "контроль" "на границе не распознано ни одной команды -> распознаватель слеп, краснеет"

d="$(sandbox c5-noboundary)"; world5 "$d"
sed -i "s/^BOUNDARY = \"[0-9a-f]\{40\}\"$/BOUNDARY = \"$(printf '0%.0s' {1..40})\"/" \
    "$d/scripts/change-graph-gate/digestform.py"
says "$d" 2 "граница" "граница не разрешается в клоне -> без предмета, а не 'находок 0'"

d="$(sandbox c5-nocommit)"
says "$d" 2 "HEAD" "в песочнице нет ни одного коммита -> без предмета"

echo
echo "=== перепись инъекций набора change-graph-gate ==="
echo "утверждений: $((pass + fail)) · прошло: $pass · провалено: $fail"
[ "$fail" -eq 0 ]
