#!/usr/bin/env bash
# shellcheck disable=SC2016
#   Тела документов песочницы — markdown с цитатой в обратных кавычках; в двойных
#   кавычках оболочка исполнила бы её как подстановку команды.
# check-17 — ХУК ОТПРАВКИ СУДИТ ВЕТКУ ГЕЙТОМ ЦИТАТ `make` С ТРЕМЯ ЕГО ИСХОДАМИ (ws#816).
#
# ПРЕДМЕТ. Гейт цитат (`scripts/check-doc-commands.py`) не исполнял никто, кто
# судит ветку: конвейер поднимается только руками, а хук выводит перечень из
# `scripts/*/run-all.sh`, и гейт ни в один набор не входил. Цитата неисполнимой
# команды доезжала до ветки волны. Здесь спрашивается ПОВЕДЕНИЕ хука, а не текст:
# песочница — свой клон с копией хука, общей библиотеки наборов, набора-носителя
# гейта и самого гейта, и настоящий `git push` в голый удалённый.
#
# ЧТО ТРЕБУЕТСЯ:
#   цитата `make e2e-test` (цели в корневом Makefile нет, она в `deploy/`)
#       → отправка остановлена, вывод называет файл и строку, на удалённом пусто;
#   близнец — та же копия с `make -C deploy e2e-test`
#       → отправка прошла, гейт исполнен и зелен, без предмета 0;
#   копия без дерева продукта
#       → отправка прошла, набор-носитель назван «без предмета», гейт ответил `[VOID]`.
#
# НОСИТЕЛЬ ВЫВОДИТСЯ ИЗ ДЕРЕВА, А НЕ ВЫПИСЫВАЕТСЯ: проверка набора, чей исполняемый
# текст ЗОВЁТ гейт интерпретатором (`python3 … check-doc-commands.py`), — не та,
# что лишь называет его имя. Носителя нет — НАХОДКА: хук гейта не исполнит, и это
# ровно дефект предмета. Носитель копируется со своим `run-all.sh` и помощниками
# набора, но без соседних проверок: их предпосылки к предмету не относятся.
#
# САМА СЕБЕ НОСИТЕЛЕМ ПРОВЕРКА НЕ БЫВАЕТ, и это несущее: она называет гейт по имени,
# и признак «имя в исполняемом тексте» выбрал бы её — тогда хук песочницы гонял бы
# её же набор, она строила бы песочницу снова, и отправки вкладывались бы без конца
# (измерено при сведении ws-816 — процессы снимались руками). Поэтому носитель —
# только ВЫЗОВ гейта, эта проверка исключена по имени файла, а вызов изнутри своей
# песочницы опознаётся меткой окружения и отвечает [VOID], не строя новой.
#
# ПРЕДПОСЫЛКА (VOID, код 2): хук и гейт есть в дереве, корневая подпись есть,
# песочница строится.
set -uo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/sandbox-git-home.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/sandbox-git-home.sh"

WS="$(tooling_gate_workspace_root)" || exit 2
NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
if [ -n "${KACHO_QUOTE_HOOK_PROBE:-}" ]; then
    tooling_gate_void "$NAME" "вызвана изнутри своей же песочницы (KACHO_QUOTE_HOOK_PROBE=$KACHO_QUOTE_HOOK_PROBE) — вложенной песочницы не строю"
    exit 2
fi
GATE="scripts/check-doc-commands.py"
HOOK="scripts/hooks/pre-push"

for f in "$HOOK" "$GATE"; do
    if [ -z "$(tooling_gate_files "$WS" "$f")" ]; then
        tooling_gate_void "$NAME" "$f в дереве $WS нет — судить хук гейтом цитат нечем"
        tooling_gate_census "$NAME: хук и гейт в дереве — не оба, проб 0"
        exit 2
    fi
done

# Носитель — проверка набора верхнего уровня, исполняемый текст которой зовёт гейт.
carrier=""
while IFS= read -r rel; do
    case "$rel" in scripts/*/check-*) ;; *) continue ;; esac
    [ "${rel##*/}" = "${BASH_SOURCE[0]##*/}" ] && continue
    [ "$(printf '%s' "$rel" | tr -cd '/' | wc -c)" -eq 2 ] || continue
    if grep -qE -- 'python3[^#]*check-doc-commands\.py' <<<"$(grep -v '^[[:space:]]*#' -- "$WS/$rel" 2>/dev/null)"; then
        carrier="$rel"
        break
    fi
done < <(tooling_gate_files "$WS" 'scripts/*/check-*')
if [ -z "$carrier" ]; then
    tooling_gate_fail "$NAME" "гейт $GATE не входит ни в один набор scripts/*/run-all.sh: хук отправки его не исполнит, цитата неисполнимой команды уедет"
    tooling_gate_census "$NAME: проверок наборов, зовущих гейт цитат, 0; проб 0"
    exit 1
fi
suite_dir="${carrier%/*}"

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX KACHO_SKIP_PREPUSH KACHO_MONOREPO \
      GATE_ROOT DOCS_GATE_ROOT KACHO_HOME_KACHO KACHO_HOME_KANAME KACHO_HOME_CORELIB

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if ! sandbox_git_home "$TMP/home" 2> "$TMP/home.err"; then
    tooling_gate_void "$NAME" "$(tr '\n' ' ' < "$TMP/home.err")"
    exit 2
fi

probes=0; findings=0
okp() { probes=$((probes + 1)); }
badp() { probes=$((probes + 1)); findings=$((findings + 1)); tooling_gate_fail "$NAME" "$1"; }

# build <копия> <тело документа> [без-продукта] — клон воркспейса-песочницы,
# провязанный штатной командой, с голым удалённым.
# Копируется ОТСЛЕЖИВАЕМОЕ (индекс судимого дерева), а не диск: байткод и чужие
# файлы рядом в песочницу не едут.
KIT=()
while IFS= read -r rel; do
    case "$rel" in
        scripts/hooks/* | scripts/lib/* | "$GATE" | "$carrier") KIT+=("$rel") ;;
        "$suite_dir"/check-*) ;;
        "$suite_dir"/*) [ "${rel#"$suite_dir"/}" = "${rel##*/}" ] && KIT+=("$rel") ;;
    esac
done < <(tooling_gate_files "$WS" 'scripts/*')
build() {
    local F="$1" rel
    mkdir -p "$F/docs"
    for rel in "${KIT[@]}"; do
        mkdir -p "$F/${rel%/*}" && cp -p "$WS/$rel" "$F/$rel" || return 1
    done
    printf 'project/\ntmp/\n__pycache__/\n' > "$F/.gitignore"
    printf '%s\n' "$2" > "$F/docs/guide.md"
    if [ "${3:-}" != без-продукта ]; then
        mkdir -p "$F/project/kacho/deploy"
        printf 'lint:\n\t@true\n' > "$F/project/kacho/Makefile"
        printf 'e2e-test:\n\t@true\n' > "$F/project/kacho/deploy/Makefile"
        sandbox_run git -C "$F/project/kacho" init -q || return 1
    fi
    sandbox_run git -C "$F" init -q -b main &&
        sandbox_run git -C "$F" add -A &&
        sandbox_run git -C "$F" commit -q --no-verify -m '#1 песочница' &&
        sandbox_run git init -q --bare "$F.git" &&
        sandbox_run git -C "$F" remote add origin "$F.git" &&
        ( cd "$F" && sandbox_run bash scripts/hooks/install.sh install >/dev/null 2>&1 ) &&
        [ -x "$F/.git/hooks/pre-push" ]
}

# push <копия> — настоящий `git push` ветки в голый удалённый; код и вывод — в rc/out.
# Имя отправляемой ветки — законной формы `<N>-<суффикс>` (`git-issues.md`
# §«Имя ветки»): хук судит имя ДО наборов (`check-18`), и создание ветки с голым
# номером получало бы отказ по имени, а не по цитате — близнецы краснели бы не по
# своему предмету, а дефект краснел бы и без гейта цитат.
BRANCH="816-quote-gate"
push() {
    out="$(cd "$1" && KACHO_QUOTE_HOOK_PROBE="$NAME" sandbox_run git push origin "HEAD:refs/heads/$BRANCH" 2>&1 < /dev/null)"; rc=$?
    remote="$(sandbox_run git -C "$1" ls-remote origin "refs/heads/$BRANCH" | cut -f1)"
    head="$(sandbox_run git -C "$1" rev-parse HEAD)"
}
has() { [[ "$out" == *"$1"* ]]; }
expect_lines() { # <имя> <образец…> — каждого образца в выводе нет → находка
    local name="$1" p miss=""
    shift
    for p in "$@"; do has "$p" || miss="$miss «$p»"; done
    printf '%s' "$miss"
}

F1="$TMP/defect"
if ! build "$F1" 'Сквозной прогон — `make e2e-test`.'; then
    tooling_gate_void "$NAME" "песочница не собрана (копия хука, наборов и гейта, коммит, провязка)"
    exit 2
fi
push "$F1"
miss="$(expect_lines x "docs/guide.md:1" "e2e-test" "ОТКАЗ")"
if [ "$rc" -ne 0 ] && [ -z "$remote" ] && [ -z "$miss" ]; then okp
else badp "цитата make e2e-test: код отправки $rc, на удалённом «${remote:-—}», нет в выводе:${miss:- —} — хук не остановил неисполнимую цитату"; fi

F2="$TMP/twin"
build "$F2" 'Сквозной прогон — `make -C deploy e2e-test`.' || { tooling_gate_void "$NAME" "песочница близнеца не собрана"; exit 2; }
push "$F2"
miss="$(expect_lines x "all 1 make citations" "$suite_dir/run-all.sh" "провалено 0, без предмета 0")"
if [ "$rc" -eq 0 ] && [ "$remote" = "$head" ] && [ -z "$miss" ]; then okp
else badp "близнец make -C deploy e2e-test: код отправки $rc, на удалённом «${remote:-—}», нет в выводе:${miss:- —} — гейт не исполнен либо краснеет на исполнимой цитате"; fi

F3="$TMP/no-product"
build "$F3" 'Сквозной прогон — `make -C deploy e2e-test`.' без-продукта || { tooling_gate_void "$NAME" "песочница без дерева продукта не собрана"; exit 2; }
push "$F3"
miss="$(expect_lines x "[VOID] check-doc-commands" "БЕЗ ПРЕДМЕТА" "$suite_dir/run-all.sh" "без предмета 1")"
if [ "$rc" -eq 0 ] && [ "$remote" = "$head" ] && [ -z "$miss" ]; then okp
else badp "копия без дерева продукта: код отправки $rc, на удалённом «${remote:-—}», нет в выводе:${miss:- —} — «не выполнилось» остановило отправку либо подано зелёным"; fi

tooling_gate_census "$NAME: носитель гейта $carrier; файлов песочницы ${#KIT[@]}; проб $probes (неисполнимая цитата, близнец, без дерева продукта), находок $findings"
if [ "$findings" -gt 0 ]; then
    tooling_gate_fail "$NAME" "хук судит ветку гейтом цитат не по трём исходам: находок $findings"
    exit 1
fi
tooling_gate_pass "$NAME" "хук останавливает неисполнимую цитату, пропускает исполнимую и называет отсутствие дерева продукта «без предмета»"
