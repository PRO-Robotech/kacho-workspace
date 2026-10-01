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
# Окружение — своё: `KACHO_HOME_*` читает `applicability.py` (check-04), и
# унаследованный дом был бы сильнее мира песочницы (scripts/lib/proofs.sh).
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/proofs.sh
. "$WS/scripts/lib/proofs.sh"
proof_own_environment

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Подпись песочниц — их HOME со своим `.gitconfig` (ws#785), без переопределения.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/sandbox-git-home.sh
. "$WS/scripts/lib/sandbox-git-home.sh"
sandbox_git_home "$TMP/home" || { echo "ОТКАЗ: корневой подписи нет — коммитам песочниц не с чего взять подпись" >&2; exit 2; }

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
    # Общая библиотека наборов — предпосылка копии: корень проверки берётся
    # через `scripts/lib/gate_root.py` (ws#757), и без неё копия набора не
    # запустилась бы вовсе, а проба судила бы раскладку песочницы.
    cp -r "$WS/scripts/lib" "$dir/scripts/"
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

# commit_all <каталог> <сообщение> — коммит песочницы. Подпись — HOME песочницы
# со своим `.gitconfig`: правило подписи действует и на репозиторий, который на
# origin не попадает никогда (ws#785).
commit_all() {
    git -C "$1" add -A > /dev/null 2>&1
    sandbox_git -C "$1" commit -q --allow-empty -m "$2" > /dev/null 2>&1
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
echo "=== check-03: конвейер зовёт все артефакты набора, а при автозапуске — на стволе ==="

# ФИКСТУРА ЗАДАЁТ АВТОЗАПУСК САМА — ЦЕЛИКОМ ЗАМЕНЯЯ БЛОК `on:`, а не вставляя строку
# перед известным образцом. Объявление менялось решениями владельца (2026-09-20 снято,
# 2026-10-01 возвращено), и вставка, чей образец перестал совпадать, была бы пустой
# операцией: проба судила бы дерево как есть. Блок не найден — провал фикстуры.
# set_on <песочница> <новый блок on>
set_on() {
    WF_ON="$2" python3 - "$1" <<'PYWF'
import os
import re
import sys
p = sys.argv[1] + "/.github/workflows/ci.yaml"
text = open(p, encoding="utf-8").read()
text, n = re.subn(r"^on:\n(?:[ \t]+\S.*\n)+", os.environ["WF_ON"], text, count=1, flags=re.M)
if n != 1:
    sys.exit("фикстура НЕ ВНЕСЕНА: блок on: в ci.yaml песочницы не найден")
open(p, "w", encoding="utf-8").write(text)
PYWF
}

d="$(sandbox c3-twin)"
set_on "$d" $'on:\n  push:\n    branches: [main]\n  workflow_dispatch:\n' || exit 2
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

# Дешёвую полосу и доказательство набора зовёт ВЫВОД ПЕРЕЧНЯ наборов по заданию
# (ws#753; по заданиям — возврат по #816): шаг задания `change-graph-proofs`, которое
# набор объявил файлом `scripts/change-graph-gate/ci-job`. Это их единственный дом.
# Тот же вызов стоит в КАЖДОМ задании наборов, поэтому фикстура адресует шаг по его
# имени вместе со строкой `run:` — правка первого вхождения тронула бы чужое задание
# и доказывала бы не то. Каждая фикстура меняет один факт этого дома и обязана
# ИЗМЕНИТЬ файл: правка, не нашедшая строки, доказывала бы «на нетронутом молчит», а
# не «на дефекте краснеет».
# wf_edit <каталог> <старое> <новое> — замена в объявлении; строки нет — отказ.
wf_edit() {
    python3 - "$1/.github/workflows/ci.yaml" "$2" "$3" <<'PYE'
import sys
p, old, new = sys.argv[1:4]
text = open(p, encoding="utf-8").read()
if old not in text:
    sys.exit("фикстура не нашла строки: " + old)
open(p, "w", encoding="utf-8").write(text.replace(old, new, 1))
PYE
}
# Строки ниже — ТЕКСТ шага конвейера, а не команда этой оболочки: подстановка в них
# на этапе записи была бы дефектом.
# shellcheck disable=SC2016
DERIVED_CALL='KACHO_MONOREPO="$PWD/project/kacho" bash scripts/lib/run-suites.sh --proofs --void-is-failure --job "$GITHUB_JOB"'
# shellcheck disable=SC2016
NOPROOFS_CALL='bash scripts/lib/run-suites.sh --void-is-failure --job "$GITHUB_JOB"'
# shellcheck disable=SC2016
FOREIGN_CALL='KACHO_MONOREPO="$PWD/project/kacho" bash scripts/lib/run-suites.sh --proofs --void-is-failure --job tooling-gate'
CG_STEP_NAME='      - name: дешёвая полоса контура и её доказательство — выводом перечня по заданию'
CG_STEP="$CG_STEP_NAME
        run: $DERIVED_CALL"
# cg_step <строка run> — тот же шаг с другой строкой `run:`.
cg_step() { printf '%s\n        run: %s' "$CG_STEP_NAME" "$1"; }

# said <каталог> <проверка> <подстрока> — 0, если вердикт называет подстроку.
said() {
    local out
    out="$( cd "$1" && CG_GATE_ROOT="$1" bash "$1/scripts/change-graph-gate/$2" 2>&1 )"
    if grep -qF -- "$3" <<<"$out"; then echo 0; else echo 1; fi
}

d="$(sandbox c3-cheap-gone)"
# Вывод перечня снят: дешёвая полоса и доказательство набора перестали зваться
# конвейером — обход хука законен, и гонять их было бы некому.
if wf_edit "$d" "$CG_STEP" "$(cg_step "echo нечего")"; then
    assert 1 "$(run "$d" "$C3")" "снят вывод перечня -> краснеет: конвейер перестал быть надмножеством хука"
    assert 0 "$(said "$d" "$C3" "объявлено задание change-graph-proofs, а оно не зовёт вывод перечня")" \
        "снят вывод перечня -> находка называет объявленное задание, которое его больше не зовёт"
else
    assert 1 2 "фикстура «снят вывод перечня» не изменила объявление"
fi

d="$(sandbox c3-noproofs)"
if wf_edit "$d" "$CG_STEP" "$(cg_step "$NOPROOFS_CALL")"; then
    assert 1 "$(run "$d" "$C3")" "вывод перечня без --proofs -> доказательство набора не исполняется, краснеет"
    assert 0 "$(said "$d" "$C3" "ни одно задание конвейера не зовёт scripts/change-graph-gate/inject.sh")" \
        "вывод перечня без --proofs -> находка называет доказательство набора"
else
    assert 1 2 "фикстура «без --proofs» не изменила объявление"
fi

# Вызов вывода есть, вердикт не доходит (круг 1): echo, `|| true`,
# `continue-on-error`, `if: false` проходили подстрокой; `--job` чужого задания
# исполнил бы наборы под именем чужого контекста (возврат по #816). Распознаватель
# общий с suites-gate/check-04 (`scripts/lib/ci_calls.py`, выбор задания —
# `scripts/lib/ci_suites.py`); каждая форма — однофактная правка.
c3_swallowed() {
    local form="$1" d
    d="$(sandbox "c3-$form")"
    case "$form" in
        echo) wf_edit "$d" "$CG_STEP" "$(cg_step "echo '$DERIVED_CALL'")" ;;
        ortrue) wf_edit "$d" "$CG_STEP" "$(cg_step "$DERIVED_CALL || true")" ;;
        coe) wf_edit "$d" "$CG_STEP_NAME" "$CG_STEP_NAME
        continue-on-error: true" ;;
        iffalse) wf_edit "$d" "  change-graph-proofs:
    name:" "  change-graph-proofs:
    if: false
    name:" ;;
        foreign) wf_edit "$d" "$CG_STEP" "$(cg_step "$FOREIGN_CALL")" ;;
    esac || { assert 1 2 "фикстура «$form» не изменила объявление"; return; }
    assert 1 "$(run "$d" "$C3")" "вызов вывода перечня в форме «$form» -> вердикт до задания не доходит, краснеет"
    if [ "$form" != echo ]; then
        assert 0 "$(said "$d" "$C3" "вызов scripts/lib/run-suites.sh не засчитан")" \
            "форма «$form» -> находка называет незасчитанный вызов и причину"
    fi
}
for form in echo ortrue coe iffalse foreign; do c3_swallowed "$form"; done

# Набор выпал из вывода: строка вызова цела, но перепись наборов его не видит
# (прогонщик не в индексе и игнорируется) — вывод его не исполнит.
d="$(sandbox c3-dropped)"
printf 'scripts/change-graph-gate/run-all.sh\n' >> "$d/.git/info/exclude"
git -C "$d" rm -q --cached scripts/change-graph-gate/run-all.sh > /dev/null 2>&1
assert 1 "$(run "$d" "$C3")" "набор выпал из переписи наборов -> вывод его не исполнит, краснеет"
assert 0 "$(said "$d" "$C3" "набора change-graph-gate в переписи нет")" \
    "набор выпал из переписи -> находка называет причину"

# Принадлежность заданию объявляет набор (`scripts/change-graph-gate/ci-job`): снятое
# объявление — вывод по заданиям набор не исполнит, хотя шаг вызова цел. Близнец —
# тот же набор, объявивший ДРУГОЕ задание, которое вывод по заданию зовёт: законный
# дом, и проверка молчит.
d="$(sandbox c3-undeclared)"
git -C "$d" rm -q -f scripts/change-graph-gate/ci-job > /dev/null 2>&1
assert 1 "$(run "$d" "$C3")" "объявление задания снято -> вывод по заданиям набор не исполнит, краснеет"
assert 0 "$(said "$d" "$C3" "объявления scripts/change-graph-gate/ci-job нет")" \
    "объявление снято -> находка называет причину"

d="$(sandbox c3-declared-elsewhere)"
printf '# близнец: набор объявил другое задание\ntooling-gate\n' > "$d/scripts/change-graph-gate/ci-job"
git -C "$d" add -A > /dev/null 2>&1
assert 0 "$(run "$d" "$C3")" "законный близнец: набор объявил другое задание, зовущее вывод по заданию -> молчит"

# Второй дом: тот же прогон зовётся и выводом перечня, и поимённым шагом.
d="$(sandbox c3-dup)"
if wf_edit "$d" "      - name: дорогая полоса — доказательства падучести контура" \
    "      - name: дубль
        run: bash scripts/change-graph-gate/run-all.sh
      - name: дорогая полоса — доказательства падучести контура"; then
    assert 1 "$(run "$d" "$C3")" "поимённый вызов рядом с выводом перечня -> второй дом, краснеет"
    assert 0 "$(said "$d" "$C3" "run-all.sh зовётся дважды")" "второй дом -> находка называет оба места"
else
    assert 1 2 "фикстура «второй дом» не изменила объявление"
fi

# Законный близнец второй оси: дом ОДИН, но поимённый — вывода перечня нет,
# прогон и доказательство вписаны шагами.
d="$(sandbox c3-by-name)"
if wf_edit "$d" "$CG_STEP" "$(cg_step "echo нечего")" &&
   wf_edit "$d" "      - name: дорогая полоса — доказательства падучести контура" \
    "      - name: дешёвая полоса поимённо
        run: bash scripts/change-graph-gate/run-all.sh
      - name: доказательство набора поимённо
        run: bash scripts/change-graph-gate/inject.sh
      - name: дорогая полоса — доказательства падучести контура"; then
    assert 0 "$(run "$d" "$C3")" "законный близнец: дом один и поимённый -> молчит"
else
    assert 0 2 "фикстура «дом поимённый» не изменила объявление"
fi

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

# Предмет оси — автозапуск, который ЕСТЬ и идёт МИМО ствола. Блок `on:` заменяется
# целиком: оставь фикстура живые триггеры на `main` рядом с посторонним, задание
# срабатывало бы со ствола, и проба судила бы не свою ось.
d="$(sandbox c3-offmain)"
set_on "$d" $'on:\n  push:\n    branches: [never-fires]\n  workflow_dispatch:\n' || exit 2
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

# const5 <каталог> <имя> <sha> — константа гейта (BOUNDARY, RULE) вписывается в
# ЕДИНСТВЕННОЕ место, где гейт её объявляет; не вписалась — пробы о другом
# гейте, отказ.
const5() {
    local g="$1/scripts/change-graph-gate/digestform.py"
    sed -i "s/^$2 = \"[0-9a-f]\{40\}\"$/$2 = \"$3\"/" "$g" 2> /dev/null
    grep -qx "$2 = \"$3\"" "$g" 2> /dev/null \
        || { echo "ОТКАЗ: константы $2 в $g вписать некуда" >&2; exit 1; }
}

# tips5 <каталог> [<sha>…] — перечень вершин линий до правила целиком; пустой
# вызов делает мир песочницы независимым от вершин настоящего дерева.
tips5() {
    local g="$1/scripts/change-graph-gate/digestform.py"; shift
    python3 - "$g" "$@" << 'PY' \
        || { echo "ОТКАЗ: перечня PRE_RULE_TIPS в $g вписать некуда" >&2; exit 1; }
import re
import sys
path, tips = sys.argv[1], sys.argv[2:]
with open(path, encoding="utf-8") as f:
    text = f.read()
body = "".join('    "%s",\n' % t for t in tips)
new, n = re.subn(r"^PRE_RULE_TIPS = \(\n(?:    .*\n)*?\)$",
                 lambda _m: "PRE_RULE_TIPS = (\n" + body + ")", text,
                 count=1, flags=re.M)
if n != 1:
    sys.exit(1)
with open(path, "w", encoding="utf-8") as f:
    f.write(new)
PY
}

# anchors5 <каталог> [<путь здесь> <репозиторий> <якорь> <путь в источнике>]…
# — перечень якорей целиком; пустой вызов делает мир песочницы независимым от
# якорей настоящего дерева.
anchors5() {
    local g="$1/scripts/change-graph-gate/digestform.py"; shift
    python3 - "$g" "$@" << 'PY' \
        || { echo "ОТКАЗ: перечня FOREIGN_ANCHORS в $g вписать некуда" >&2; exit 1; }
import re
import sys
path, rows = sys.argv[1], sys.argv[2:]
with open(path, encoding="utf-8") as f:
    text = f.read()
body = "".join('    ("%s", "%s", "%s", "%s"),\n' % tuple(rows[i:i + 4])
               for i in range(0, len(rows), 4))
new, n = re.subn(r"^FOREIGN_ANCHORS = \(\n(?:    .*\n)*?\)$",
                 lambda _m: "FOREIGN_ANCHORS = (\n" + body + ")", text,
                 count=1, flags=re.M)
if n != 1:
    sys.exit(1)
with open(path, "w", encoding="utf-8") as f:
    f.write(new)
PY
}

# world5 <каталог> [<текст унаследованной записи>] — граница: коммит с записью,
# чья команда без --full-index. Тот же коммит объявлен коммитом правила,
# перечень вершин линий до правила пуст.
world5() {
    local b
    rec "$1" docs/changes/p/reviews/post-diff/r/old.yaml \
        "${2-command: git diff aaa...bbb | sha256sum}"
    commit_all "$1" boundary
    b="$(git -C "$1" rev-parse HEAD)"
    const5 "$1" BOUNDARY "$b"
    const5 "$1" RULE "$b"
    tips5 "$1"
    anchors5 "$1"
}

# commit_at / merge_at <каталог> <дата> … — коммит и сведение с датой автора и
# коммиттера: «до правила» в пробе задают часы, а не скорость прогона.
commit_at() {
    ( export GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2"; commit_all "$1" "$3" )
}
merge_at() {
    ( export GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2"
      sandbox_git -C "$1" merge -q --no-ff --no-edit "$3" > /dev/null 2>&1 )
}

TIPREC=docs/changes/q/reviews/post-diff/r/tip.yaml

# world5tip <каталог> <откуда линия: root|rule> <дата вершины> <свести: yes|no>
# [<запись вершины>] — линия `side` пишет запись (по умолчанию без --full-index)
# и объявлена вершиной до правила. Коммит правила (2001-01-03) и граница с
# записью (2001-01-05) — РАЗНЫЕ коммиты ствола, правило — предок границы, как в
# дереве: мир, где они один коммит, не отличает гейт, судящий вершины от
# границы, от судящего их от правила (ws#822, M6). Линия ответвлена от корня
# (правила не знает) либо от коммита правила (знает его, но не границу).
# Вершина — в TIP, корень — в ROOT5.
world5tip() {
    local d="$1" b="" r=""
    commit_at "$d" "2001-01-01T00:00:00Z" root
    ROOT5="$(git -C "$d" rev-parse HEAD)"
    rec "$d" RULE.md "правило ws#818"
    commit_at "$d" "2001-01-03T00:00:00Z" rule
    r="$(git -C "$d" rev-parse HEAD)"
    rec "$d" docs/changes/p/reviews/post-diff/r/old.yaml "command: git diff aaa...bbb | sha256sum"
    commit_at "$d" "2001-01-05T00:00:00Z" boundary
    b="$(git -C "$d" rev-parse HEAD)"
    if [ "$2" = rule ]; then
        git -C "$d" checkout -q -b side "$r"
    else
        git -C "$d" checkout -q -b side "$ROOT5"
    fi
    rec "$d" "$TIPREC" "${5-command: git diff aaa...eee | sha256sum}"
    commit_at "$d" "$3" side
    TIP="$(git -C "$d" rev-parse HEAD)"
    git -C "$d" checkout -q -
    [ "$4" = yes ] && merge_at "$d" "2001-01-08T00:00:00Z" side
    const5 "$d" BOUNDARY "$b"
    const5 "$d" RULE "$r"
    tips5 "$d" "$TIP"
    anchors5 "$d"
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

# Линии, писавшие записи ДО правила и сходящиеся позже границы (ws#822, ws#824).
# Пары меняют по одному факту против c5-tip: дату вершины, её основание,
# сведение, дописанную команду, наличие записи, строку перечня.
d="$(sandbox c5-tip)"; world5tip "$d" root "2001-01-02T00:00:00Z" yes
says "$d" 0 "в истории HEAD 1, не сошлись 0, унаследовано с них 1" "запись линии до правила сведена в HEAD -> унаследована с вершины, молчит и сосчитана"

# Дата МЕЖДУ правилом и границей — единственная, на которой мерило «правило»
# отличимо от мерила «граница»: вершина, снятая после правила, записи при нём уже
# писала, хотя границы ещё не было.
d="$(sandbox c5-tip-between)"; world5tip "$d" root "2001-01-04T00:00:00Z" yes
says "$d" 1 "снята не раньше коммита правила" "вершина снята между правилом и границей -> знает правило, краснеет (мерило — правило, не граница)"

d="$(sandbox c5-tip-late)"; world5tip "$d" root "2001-01-06T00:00:00Z" yes
says "$d" 1 "снята не раньше коммита правила" "вершина снята позже правила и границы -> перечень не прощает записи при правиле, краснеет"

# Линия от коммита правила, но не от границы: вершина знает правило предком,
# хотя граница ей не предок, а дата подделана ранней.
d="$(sandbox c5-tip-knows)"; world5tip "$d" rule "2001-01-02T00:00:00Z" yes
says "$d" 1 "содержит коммит правила" "вершина содержит коммит правила, но не границу -> краснеет, её записи судятся как новые"

# Знающая вершина, которой прощать НЕЧЕГО: её запись несёт --full-index, новых
# находок нет, и код 1 обязан прийти одним знанием. Без этой пары вклад знания в
# код выхода не держит ничто: c5-tip-late и c5-tip-knows краснеют и через запись.
TIPFULL="command: git diff --full-index aaa...eee | sha256sum"
d="$(sandbox c5-tip-knows-bare)"; world5tip "$d" root "2001-01-04T00:00:00Z" yes "$TIPFULL"
says "$d" 1 "снята не раньше коммита правила" "знающая вершина без нового к прощению -> краснеет одним знанием"
says "$d" 1 "без --full-index 1 (унаследовано 1, новых 0)" "у знающей вершины без нового находок в записях 0 -> код 1 пришёл не от записи"

d="$(sandbox c5-tip-knows-bare-undeclared)"; world5tip "$d" root "2001-01-04T00:00:00Z" yes "$TIPFULL"
tips5 "$d"
says "$d" 0 "вершин линий до правила 0" "законный близнец: та же линия после правила, в перечне не объявлена -> молчит"

d="$(sandbox c5-tip-edit)"; world5tip "$d" root "2001-01-02T00:00:00Z" yes
rec "$d" "$TIPREC" "again: git diff aaa...fff | sha256sum"; commit_at "$d" "2001-01-09T00:00:00Z" edit
says "$d" 1 "без --full-index: $TIPREC" "в запись линии до правила после вершины дописана команда -> краснеет и называет путь"

d="$(sandbox c5-tip-open)"; world5tip "$d" root "2001-01-02T00:00:00Z" no
says "$d" 0 "в истории HEAD 0, не сошлись 1" "вершина объявлена, линия не сведена -> не судится, сосчитана несошедшейся"

d="$(sandbox c5-tip-gone)"; world5tip "$d" root "2001-01-02T00:00:00Z" yes
git -C "$d" rm -q "$TIPREC"; commit_at "$d" "2001-01-09T00:00:00Z" gone
says "$d" 1 "без предмета" "вершина в истории HEAD, а наследовать с неё нечего -> строка перечня без предмета, краснеет"

# Лишняя строка перечня: разрешается в клоне, но не сведена — законный транзит;
# не разрешается вовсе — без предмета с её координатой, а не вечное молчание.
LOST5="0123456789abcdef0123456789abcdef01234567"
d="$(sandbox c5-tip-lost)"; world5tip "$d" root "2001-01-02T00:00:00Z" yes
tips5 "$d" "$TIP" "$LOST5"
says "$d" 2 "$LOST5" "строка перечня не разрешается в клоне -> без предмета и называет строку, а не 'не сошлась'"

d="$(sandbox c5-tip-transit)"; world5tip "$d" root "2001-01-02T00:00:00Z" yes
other="$(GIT_AUTHOR_DATE="2001-01-02T00:00:00Z" GIT_COMMITTER_DATE="2001-01-02T00:00:00Z" \
    sandbox_git -C "$d" commit-tree -p "$ROOT5" -m other "$ROOT5^{tree}")"
git -C "$d" update-ref refs/heads/other "$other"
tips5 "$d" "$TIP" "$other"
says "$d" 0 "в истории HEAD 1, не сошлись 1" "законный близнец: лишняя строка разрешается, линия не сведена -> транзит, молчит и сосчитана"

# Строка перечня — полный sha. Имя ветки и сокращение в песочнице разрешаются в
# ту же вершину, что и c5-tip, — краснеют формой, а не содержимым.
d="$(sandbox c5-tip-name)"; world5tip "$d" root "2001-01-02T00:00:00Z" yes
tips5 "$d" side
says "$d" 1 "«side» — не полный sha" "строка перечня — имя ветки -> краснеет и называет строку"

d="$(sandbox c5-tip-abbrev)"; world5tip "$d" root "2001-01-02T00:00:00Z" yes
tips5 "$d" "${TIP:0:12}"
says "$d" 1 "«${TIP:0:12}» — не полный sha" "строка перечня — сокращённый sha -> краснеет и называет строку"

# Та же строка-имя, а прощать вершине нечего (её запись несёт --full-index):
# код 1 обязан прийти одной формой строки. Без этой пары вклад формы в код
# выхода не держит ничто — c5-tip-name краснеет и через запись вершины, ставшую
# новой. Законный близнец — c5-tip-knows-bare-undeclared.
d="$(sandbox c5-tip-name-bare)"; world5tip "$d" root "2001-01-02T00:00:00Z" yes "$TIPFULL"
tips5 "$d" side
says "$d" 1 "«side» — не полный sha" "строка-имя у вершины без нового к прощению -> краснеет одной формой"
says "$d" 1 "без --full-index 1 (унаследовано 1, новых 0)" "у строки-имени без нового находок в записях 0 -> код 1 пришёл не от записи"

# Записи ЧУЖОЙ линии до правила (corelib#54): запись снята в другом репозитории
# до правила и перенесена сюда побайтно, путь здесь новый. Признаётся она только
# по якорю — коммиту источника. Пары меняют по одному факту против c5-anchor:
# строку перечня, дату якоря, байт записи, существование и публикацию якоря,
# путь в источнике, клон источника, наличие записи и команды к прощению.
FOREC=docs/changes/f/reviews/post-diff/r/foreign.yaml
FOREPO=PRO-Robotech/src
FOREFULL="command: git diff --full-index aaa...ggg | sha256sum"

# world5src <каталог> <дата якоря> [<запись>] — ствол как у world5tip: корень,
# правило (2001-01-03), граница с записью (2001-01-05). Источник — отдельный
# репозиторий в project/src (вне индекса песочницы) с origin $FOREPO: запись
# снята в нём коммитом с датой якоря и опубликована тегом; следом — ещё коммит,
# чтобы неглубокий клон якоря не нёс. В HEAD песочницы та же запись побайтно
# в $FOREC, перечень якорей — одна строка на неё. Якорь — в ANCHOR, источник — в SRC.
world5src() {
    local d="$1" b="" r=""
    printf 'project/\n' >> "$d/.git/info/exclude"
    commit_at "$d" "2001-01-01T00:00:00Z" root
    rec "$d" RULE.md "правило ws#818"
    commit_at "$d" "2001-01-03T00:00:00Z" rule
    r="$(git -C "$d" rev-parse HEAD)"
    rec "$d" docs/changes/p/reviews/post-diff/r/old.yaml "command: git diff aaa...bbb | sha256sum"
    commit_at "$d" "2001-01-05T00:00:00Z" boundary
    b="$(git -C "$d" rev-parse HEAD)"
    SRC="$d/project/src"
    git init -q "$SRC"
    git -C "$SRC" remote add origin "https://github.com/$FOREPO.git"
    rec "$SRC" "$FOREC" "${3-command: git diff aaa...ggg | sha256sum}"
    commit_at "$SRC" "$2" record
    ANCHOR="$(git -C "$SRC" rev-parse HEAD)"
    git -C "$SRC" tag v0 "$ANCHOR"
    rec "$SRC" LATER.md "позже"
    commit_at "$SRC" "$2" later
    mkdir -p "$(dirname "$d/$FOREC")"
    git -C "$SRC" cat-file blob "$ANCHOR:$FOREC" > "$d/$FOREC"
    commit_at "$d" "2001-01-09T00:00:00Z" transfer
    const5 "$d" BOUNDARY "$b"
    const5 "$d" RULE "$r"
    tips5 "$d"
    anchors5 "$d" "$FOREC" "$FOREPO" "$ANCHOR" "$FOREC"
}

d="$(sandbox c5-anchor)"; world5src "$d" "2001-01-02T00:00:00Z"
says "$d" 0 "якорей чужих линий 1: признано 1, не судимо 0, унаследовано с них 1" "запись чужой линии с якорем до правила и тем же sha256 -> унаследована, молчит и сосчитана"

d="$(sandbox c5-anchor-env)"; world5src "$d" "2001-01-02T00:00:00Z"
mv "$SRC" "$TMP/src.env"
KACHO_HOME_SRC="$TMP/src.env" says "$d" 0 "признано 1" "клон источника назван KACHO_HOME_<ИМЯ> -> найден, запись унаследована"
rm -rf "$TMP/src.env"

d="$(sandbox c5-anchor-none)"; world5src "$d" "2001-01-02T00:00:00Z"
anchors5 "$d"
says "$d" 1 "без --full-index: $FOREC" "та же запись без якоря -> судится новой, краснеет и называет путь"

d="$(sandbox c5-anchor-other)"; world5src "$d" "2001-01-02T00:00:00Z"
rec "$d" "$NEW" "command: git diff aaa...ccc | sha256sum"; commit_all "$d" new
says "$d" 1 "без --full-index: $NEW" "якорь прощает только свою запись -> новая запись в другом пути краснеет"

# Дата МЕЖДУ правилом и границей: мерило — правило, а не граница.
d="$(sandbox c5-anchor-late)"; world5src "$d" "2001-01-04T00:00:00Z"
says "$d" 1 "снят не раньше коммита правила" "якорь на коммит после правила -> краснеет, запись судится новой"

d="$(sandbox c5-anchor-sha256)"; world5src "$d" "2001-01-02T00:00:00Z"
rec "$d" "$FOREC" "note: дописано после переноса"; commit_all "$d" edit
says "$d" 1 "sha256 записи" "запись здесь не равна записи в источнике на якоре -> краснеет"

d="$(sandbox c5-anchor-missing)"; world5src "$d" "2001-01-02T00:00:00Z"
anchors5 "$d" "$FOREC" "$FOREPO" "$LOST5" "$FOREC"
says "$d" 1 "в полном клоне источника не существует" "якорь на несуществующий коммит -> краснеет и называет якорь"

d="$(sandbox c5-anchor-unpublished)"; world5src "$d" "2001-01-02T00:00:00Z"
git -C "$SRC" tag -d v0 > /dev/null
says "$d" 1 "не опубликован" "якорь есть в клоне, но ни одна ссылка refs/remotes/ и refs/tags/ его не содержит -> краснеет"

d="$(sandbox c5-anchor-srcpath)"; world5src "$d" "2001-01-02T00:00:00Z"
anchors5 "$d" "$FOREC" "$FOREPO" "$ANCHOR" "docs/changes/f/reviews/post-diff/r/absent.yaml"
says "$d" 1 "на якоре пути" "пути записи в источнике на якоре нет -> краснеет"

d="$(sandbox c5-anchor-abbrev)"; world5src "$d" "2001-01-02T00:00:00Z"
anchors5 "$d" "$FOREC" "$FOREPO" "${ANCHOR:0:12}" "$FOREC"
says "$d" 1 "«${ANCHOR:0:12}» — не полный sha" "якорь — сокращённый sha -> краснеет и называет строку"

d="$(sandbox c5-anchor-gone)"; world5src "$d" "2001-01-02T00:00:00Z"
git -C "$d" rm -q "$FOREC"; commit_all "$d" gone
says "$d" 1 "записи с якорем нет" "строка перечня якорей без записи в HEAD -> без предмета, краснеет"

# Якорь, которому прощать НЕЧЕГО: запись несёт --full-index, код 1 обязан
# прийти одним перечнем. Законный близнец — та же запись без строки.
d="$(sandbox c5-anchor-idle)"; world5src "$d" "2001-01-02T00:00:00Z" "$FOREFULL"
says "$d" 1 "прощать нечего" "якорь у записи без команды к прощению -> строка без предмета, краснеет"
says "$d" 1 "без --full-index 1 (унаследовано 1, новых 0)" "у якоря без нового находок в записях 0 -> код 1 пришёл не от записи"

d="$(sandbox c5-anchor-idle-undeclared)"; world5src "$d" "2001-01-02T00:00:00Z" "$FOREFULL"
anchors5 "$d"
says "$d" 0 "якорей чужих линий 0" "законный близнец: та же запись с --full-index без якоря -> молчит"

# Клона источника нет, либо клон не того репозитория, либо неглубокий и якоря
# не несёт — судить якорь нечем: без предмета, а не находка и не зелёное.
d="$(sandbox c5-anchor-noclone)"; world5src "$d" "2001-01-02T00:00:00Z"
rm -rf "$SRC"
says "$d" 2 "клон $FOREPO" "клона источника нет -> без предмета, а не находка"

d="$(sandbox c5-anchor-identity)"; world5src "$d" "2001-01-02T00:00:00Z"
git -C "$SRC" remote set-url origin "https://github.com/PRO-Robotech/other.git"
says "$d" 2 "это копия PRO-Robotech/other" "клон на месте источника — другого репозитория -> отвергнут, без предмета"

d="$(sandbox c5-anchor-shallow)"; world5src "$d" "2001-01-02T00:00:00Z"
mv "$SRC" "$TMP/src.full"
git clone -q --depth 1 "file://$TMP/src.full" "$SRC" 2> /dev/null
git -C "$SRC" remote set-url origin "https://github.com/$FOREPO.git"
says "$d" 2 "неглубокий" "неглубокий клон источника без якоря -> без предмета, а не 'не существует'"
rm -rf "$TMP/src.full"

d="$(sandbox c5-norule)"; world5 "$d"
const5 "$d" RULE "$(printf '0%.0s' {1..40})"
says "$d" 2 "коммит правила" "коммит правила не разрешается в клоне -> без предмета, а не 'находок 0'"

d="$(sandbox c5-nocommit)"
says "$d" 2 "HEAD" "в песочнице нет ни одного коммита -> без предмета"

echo
echo "=== перепись инъекций набора change-graph-gate ==="
echo "утверждений: $((pass + fail)) · прошло: $pass · провалено: $fail"
[ "$fail" -eq 0 ]
