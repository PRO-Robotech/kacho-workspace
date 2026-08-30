#!/usr/bin/env bash
# Доказательство того, что check-05 СПОСОБЕН упасть и СПОСОБЕН смолчать, — и что
# посадка слияния действительно снимает конфликт, а не объявляет его снятым.
#
# Утверждений два рода, и оба обязательны:
#   · про ГЕЙТ — краснеет на снятой посадке, на именованном (требующем установки)
#     драйвере, на осиротевшей половине и на маркере, оставшемся в прозе; молчит
#     на целом дереве; отвечает VOID там, где предпосылки нет;
#   · про МЕХАНИЗМ — настоящий генератор, настоящее хранилище, две ветки от одной
#     базы и по записке в каждой. БЕЗ `.gitattributes` слияние падает конфликтом
#     (это и есть замер «до», исполняемый навсегда, а не запомненный), С ним —
#     проходит. Рядом законный близнец: две линии, правящие ОДИН абзац ПРОЗЫ,
#     обязаны конфликтовать по-прежнему — иначе посадка выхолостила бы то
#     расхождение, которое осмысленно и должно достаться автору.
#
# Окружение git снимается: `git push` запускает хуки с выставленным `GIT_DIR`, и
# его наследует всё, что они запускают. Проба, заводящая свой репозиторий, начала
# бы писать в РАБОЧУЮ копию — индекс схлопывается, а падают потом проверки, ни к
# чему не причастные (`multi-agent-flow.md` §НЕПРИКОСНОВЕННОСТЬ ЧУЖОГО СОСТОЯНИЯ).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_REAL="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK="$SCRIPT_DIR/check-05-index-split-holds.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ok=0; bad=0

# Рабочая копия дерева: инъекция не трогает настоящее. Берём хранилище, генератор,
# сам набор проверок и посадку слияния — то есть ровно предмет.
setup_tree() {
    local d="$TMP/$1"
    rm -rf "$d"; mkdir -p "$d"
    git -C "$d" init -q
    git -C "$d" config user.email inject@example.invalid
    git -C "$d" config user.name  inject
    (cd "$WS_REAL" && git ls-files --cached --others --exclude-standard \
        'obsidian/kacho/*' 'scripts/vault-index/*' 'scripts/vault-gate/*' '.gitattributes') \
        | while read -r f; do install -D "$WS_REAL/$f" "$d/$f"; done
    git -C "$d" add -A >/dev/null 2>&1
    git -C "$d" commit -qm base >/dev/null 2>&1
    printf '%s' "$d"
}

expect_code() {
    local name="$1" want="$2" got="$3" out="$4"
    if [ "$got" = "$want" ]; then
        echo "[inject OK]   $name (ожидали код $want, получили $got)"; ok=$((ok + 1))
    else
        echo "[inject FAIL] $name (ожидали код $want, получили $got)" >&2
        printf '%s\n' "$out" | sed 's/^/    /' >&2; bad=$((bad + 1))
    fi
}

# Находка обязана НАЗЫВАТЬ КООРДИНАТУ: гейт, краснеющий без имени файла, снимут
# как непонятный (`gate-authoring` §Исход вместо объявления).
expect_names() {
    local name="$1" coord="$2" out="$3"
    if printf '%s' "$out" | grep -qF "$coord"; then
        echo "[inject OK]   $name (находка названа: $coord)"; ok=$((ok + 1))
    else
        echo "[inject FAIL] $name (в выводе нет координаты $coord)" >&2
        printf '%s\n' "$out" | sed 's/^/    /' >&2; bad=$((bad + 1))
    fi
}

run_on() { VAULT_GATE_ROOT="$1" bash "$CHECK" 2>&1; }

# ── Часть I: гейт ────────────────────────────────────────────────────────────

d="$(setup_tree whole)"
out="$(run_on "$d")"; expect_code "законный близнец: целое дерево — молчит" 0 "$?" "$out"

# Снимать посадку надо И ИЗ ИНДЕКСА: `git check-attr` при отсутствии файла в
# рабочей копии читает его из индекса. Это ровно то свойство, ради которого
# посадка и выбрана — её везёт закоммиченное дерево, а не рабочая копия, — но
# инъекция, удалившая файл только с диска, ничего бы не сняла и «доказала» бы
# несуществующую способность гейта.
d="$(setup_tree noattr)"
rm -f "$d/.gitattributes"
git -C "$d" rm -q --cached .gitattributes >/dev/null 2>&1
out="$(run_on "$d")"; code=$?
expect_code "посадка слияния снята — поймано" 1 "$code" "$out"
expect_names "снятая посадка названа координатой" "obsidian/kacho/INDEX-notes.md" "$out"

# Ловушка именованного драйвера: атрибут есть, выглядит настоящим, но держится
# `git config` в каждом клоне — в клоне без него git молча вернётся к обычному
# слиянию. Гейт обязан отличать это от встроенной посадки.
d="$(setup_tree nameddriver)"
echo 'obsidian/kacho/INDEX-notes.md merge=vaultindex' > "$d/.gitattributes"
git -C "$d" config merge.vaultindex.driver true
out="$(run_on "$d")"; code=$?
expect_code "именованный драйвер (держится установкой) — пойман" 1 "$code" "$out"
expect_names "именованный драйвер назван по имени" "vaultindex" "$out"

# Ловушка ИСТОЧНИКА: посадка объявлена, `check-attr` отвечает «union», драйвер
# встроенный — и всё-таки её везёт не дерево, а файл ЭТОГО клона. У всякого, кто
# клонирует, посадки нет вовсе. Замер 2026-08-30: до пятого утверждения гейт на
# этом дереве печатал «находок 0».
d="$(setup_tree infoattrs)"
rm -f "$d/.gitattributes"; git -C "$d" rm -q --cached .gitattributes >/dev/null 2>&1
git -C "$d" commit -qm "посадка снята из дерева" >/dev/null 2>&1
mkdir -p "$d/.git/info"
echo 'obsidian/kacho/INDEX-notes.md merge=union' > "$d/.git/info/attributes"
out="$(run_on "$d")"; code=$?
expect_code "посадку везёт .git/info/attributes, а не дерево — поймано" 1 "$code" "$out"
expect_names "источник назван оператору" ".git/info/attributes" "$out"
expect_names "источниковая находка названа координатой" "obsidian/kacho/INDEX-notes.md" "$out"

# Тот же класс вторым источником: `core.attributesFile`. Проверка, ключующаяся на
# ОДНО имя файла, прошла бы здесь мимо — а посадка так же принадлежит клону.
d="$(setup_tree attrfile)"
rm -f "$d/.gitattributes"; git -C "$d" rm -q --cached .gitattributes >/dev/null 2>&1
git -C "$d" commit -qm "посадка снята из дерева" >/dev/null 2>&1
echo 'obsidian/kacho/INDEX-notes.md merge=union' > "$d/clone-attrs"
git -C "$d" config core.attributesFile "$d/clone-attrs"
out="$(run_on "$d")"; expect_code "посадку везёт core.attributesFile — поймано" 1 "$?" "$out"

# Законный близнец ИСТОЧНИКА: файл клона есть, но он лишь ПОВТОРЯЕТ объявленное
# деревом. Свежий клон получит ту же посадку — находки нет. Без этого контроля
# пятое утверждение ловило бы наличие `.git/info/attributes`, а не расхождение
# источников, и краснело бы на клоне, где кто-то продублировал посадку себе.
d="$(setup_tree infoattrs_same)"
mkdir -p "$d/.git/info"
echo 'obsidian/kacho/INDEX-notes.md merge=union' > "$d/.git/info/attributes"
out="$(run_on "$d")"; expect_code "законный близнец: файл клона повторяет дерево — молчит" 0 "$?" "$out"

d="$(setup_tree orphan)"
python3 - "$d" <<'PY'
import re, sys
p = sys.argv[1] + "/obsidian/kacho/INDEX.md"
t = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(re.sub(r"\[\[INDEX-notes(\|[^\]]*)?\]\]", "перечень", t))
PY
out="$(run_on "$d")"; expect_code "проза перестала ссылаться на машинную половину — поймано" 1 "$?" "$out"

d="$(setup_tree markerback)"
printf '\n<!-- GENERATED:vault-index BEGIN — правится генератором, руками не трогать -->\n' \
    >> "$d/obsidian/kacho/INDEX.md"
out="$(run_on "$d")"; expect_code "маркер генератора вернулся в прозу — поймано" 1 "$?" "$out"

# Предпосылки: «проверять нечего» ≠ «проверено, чисто».
nogit="$TMP/nogit"; mkdir -p "$nogit/obsidian/kacho"
out="$(run_on "$nogit")"; expect_code "не git-дерево — VOID, а не PASS" 2 "$?" "$out"

emptyvault="$TMP/emptyvault"; mkdir -p "$emptyvault"; git -C "$emptyvault" init -q
out="$(run_on "$emptyvault")"; expect_code "хранилища нет вовсе — VOID, а не PASS" 2 "$?" "$out"

# ── Часть II: механизм — настоящее слияние настоящих веток ───────────────────
#
# Записки кладутся в ОДНУ категорию намеренно: именно эта форма и падала
# конфликтом. Записки в разных категориях конфликта не давали и без посадки — и
# оставляли указатель молча неверным, что ловит уже check-04.
two_lines_merge() { # $1=каталог дерева → печатает код возврата слияния
    local d="$1" base
    base="$(git -C "$d" rev-parse HEAD)"
    local n
    for n in a b; do
        git -C "$d" checkout -q -B "line$n" "$base"
        printf -- '---\ntitle: "синтетика: zz-inject-%s"\ncategory: lesson\nstatus: stable\n---\n# zz-inject-%s\n' \
            "$n" "$n" > "$d/obsidian/kacho/lessons/zz-inject-$n.md"
        git -C "$d" add -A >/dev/null 2>&1
        ( cd "$d" && VAULT_GATE_ROOT="$d" python3 scripts/vault-index/generate.py >/dev/null )
        git -C "$d" add -A >/dev/null 2>&1
        git -C "$d" commit -qm "записка zz-inject-$n" >/dev/null 2>&1
    done
    git -C "$d" checkout -q linea
    git -C "$d" merge --no-edit lineb >/dev/null 2>&1
    printf '%s' "$?"
}

d="$(setup_tree merge_without_attr)"
rm -f "$d/.gitattributes"; git -C "$d" rm -q --cached .gitattributes >/dev/null 2>&1
git -C "$d" commit -qm "посадка снята" >/dev/null 2>&1
code="$(two_lines_merge "$d")"
if [ "$code" != "0" ]; then
    echo "[inject OK]   БЕЗ посадки две параллельные записки конфликтуют (код merge $code) — замер «до» воспроизведён"
    ok=$((ok + 1))
else
    echo "[inject FAIL] БЕЗ посадки слияние прошло — значит проба уже не воспроизводит предмет" >&2
    bad=$((bad + 1))
fi

d="$(setup_tree merge_with_attr)"
code="$(two_lines_merge "$d")"
if [ "$code" = "0" ]; then
    echo "[inject OK]   С посадкой две параллельные записки сливаются БЕЗ ручного разрешения"
    ok=$((ok + 1))
else
    echo "[inject FAIL] С посадкой слияние всё ещё требует человека (код merge $code)" >&2
    git -C "$d" diff --name-only --diff-filter=U | sed 's/^/    конфликт: /' >&2
    bad=$((bad + 1))
fi

# Законный близнец механизма: расхождение в ПРОЗЕ обязано остаться конфликтом.
# Без этого контроля посадку было бы не отличить от «слить как угодно, лишь бы
# молча» — а это ровно та потеря, которой разделение и должно было избежать.
d="$(setup_tree merge_prose)"
base="$(git -C "$d" rev-parse HEAD)"
for n in a b; do
    git -C "$d" checkout -q -B "prose$n" "$base"
    python3 - "$d" "$n" <<'PY'
import sys
p = sys.argv[1] + "/obsidian/kacho/INDEX.md"
t = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(
    t.replace("# INDEX — что вообще есть в хранилище",
              "# INDEX — что вообще есть в хранилище (редакция %s)" % sys.argv[2], 1))
PY
    git -C "$d" commit -qam "проза $n" >/dev/null 2>&1
done
git -C "$d" checkout -q prosea
git -C "$d" merge --no-edit proseb >/dev/null 2>&1; code=$?
if [ "$code" != "0" ]; then
    echo "[inject OK]   законный близнец: расхождение в ПРОЗЕ по-прежнему спрашивает автора (код merge $code)"
    ok=$((ok + 1))
else
    echo "[inject FAIL] расхождение в прозе слилось молча — посадка задела человеческий текст" >&2
    bad=$((bad + 1))
fi

echo
echo "inject-05: контролей пройдено $ok, провалено $bad"
[ "$bad" -eq 0 ]
