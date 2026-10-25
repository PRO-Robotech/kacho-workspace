#!/usr/bin/env bash
# skills-gate #09 — хук отправки гонит доказательство (`scripts/<набор>/inject.sh`) набора, чью
# пробу, проверку или общую часть отправка правит, и сломанное доказательство останавливает
# отправку (ws#1402).
#
# ПРИЗНАК. PR #1407 @ed86c4228: хук зелёный, конвейер красный — «run-suites — доказательство
# не сошлось: docs-gate»: правка inject-12.sh потеряла пробел, и пробы P9, P10 падали под
# `set -u`. Хук гонил лишь `scripts/*/run-all.sh`, доказательства наборов — только конвейер.
#
# ПОВЕДЕНЧЕСКАЯ, как tooling-gate check-27: песочница — репозиторий с голым удалённым, на
# который опубликован `main` (ссылка origin/main есть), в дереве — копии хука и его стражей и
# набор-заглушка `scripts/stub/` (run-all.sh зелёный; inject.sh печатает метку и выходит кодом
# по файлу `red.txt`). Вход хука — настоящая строка git отправки.
#
# ЧТО ТРЕБУЕТСЯ:
#   правка scripts/stub/inject.sh, доказательство красное — код 1, оно исполнялось и названо
#     среди красных;
#   правка scripts/stub/check-01.sh — доказательство исполнялось (зелёное — код 0);
#   близнец: правка вне набора — доказательство НЕ исполнялось, код 0.
# ИСХОДЫ: 0 — всё требуемое сошлось; 1 — нет; 2 — [VOID]: хука или стража в дереве нет, посев
# не прошёл. Перепись — числом проб.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
# shellcheck source=../lib/sandbox-git-home.sh
source "$SCRIPT_DIR/../lib/sandbox-git-home.sh"

NAME="09-push-hook-runs-touched-proofs"
WS="$(skills_gate_workspace_root)" || { skills_gate_void "$NAME" "корень судимого дерева не выведен"; exit 2; }
KIT=(pre-push prepush-attribution.sh attribution-rule.sh prepush-added-files.sh branch-name-rule.sh prepush-new-commits.sh)
for f in "${KIT[@]}"; do
    [ -f "$WS/scripts/hooks/$f" ] || { skills_gate_void "$NAME" "в дереве нет scripts/hooks/$f — проверять нечего"; exit 2; }
done
[ -f "$WS/scripts/lib/product_clone.py" ] || { skills_gate_void "$NAME" "в дереве нет scripts/lib/product_clone.py"; exit 2; }

TMP="$(mktemp -d)"
# shellcheck disable=SC2154  # _rc присваивает сама ловушка первой командой
trap '_rc=$?; rm -rf "$TMP" 2>/dev/null || rm -rf "$TMP" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $TMP не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT
sandbox_git_home "$TMP/home" || { skills_gate_void "$NAME" "корневой подписи нет — вершина песочницы не родится"; exit 2; }
pgit() { sandbox_git -c core.hooksPath=/dev/null "$@"; }

ZERO=0000000000000000000000000000000000000000
MARK="stub-inject-исполнен"
box="$TMP/box"
mkdir -p "$box/scripts/hooks" "$box/scripts/stub" "$box/scripts/lib"
for f in "${KIT[@]}"; do cp "$WS/scripts/hooks/$f" "$box/scripts/hooks/"; done
chmod +x "$box/scripts/hooks/"*
: > "$box/scripts/hooks/prepush-added-files.allow"
cp "$WS/scripts/lib/product_clone.py" "$box/scripts/lib/"
printf 'основа\n' > "$box/base.txt"
printf '#!/usr/bin/env bash\nexit 0\n' > "$box/scripts/stub/run-all.sh"
printf '#!/usr/bin/env bash\necho "%s"\n[ ! -f red.txt ] || exit 1\nexit 0\n' "$MARK" > "$box/scripts/stub/inject.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$box/scripts/stub/check-01.sh"
chmod +x "$box/scripts/stub/"*.sh
pgit -C "$box" init -q -b main
pgit -C "$box" add -A
pgit -C "$box" commit -q -m "#1402 песочница check-09"
pgit init -q --bare "$box.git"
pgit -C "$box" remote add origin "$box.git"
pgit -C "$box" push -q origin main
pgit -C "$box" fetch -q origin
pgit -C "$box" rev-parse -q --verify refs/remotes/origin/main > /dev/null \
    || { skills_gate_void "$NAME" "посев: origin/main в песочнице не появился"; exit 2; }
for r in kacho kaname corelib; do
    pgit init -q --bare -b main "$TMP/p-$r.git"; pgit init -q -b main "$TMP/p-$r"
    printf '%s\n' "$r" > "$TMP/p-$r/r.txt"; pgit -C "$TMP/p-$r" add r.txt; pgit -C "$TMP/p-$r" commit -q -m "#1 ствол $r"
    pgit -C "$TMP/p-$r" remote add origin "$TMP/p-$r.git"; pgit -C "$TMP/p-$r" push -q origin main
done

newc() {  # <ветка> <файл> [<строка>] — ветка от main с правкой файла
    pgit -C "$box" checkout -q -f -B "$1" main
    printf '%s\n' "${3:-правка}" >> "$box/$2"
    pgit -C "$box" add -A; pgit -C "$box" commit -q -m "#1402 $1"
}
push() {  # <ветка> — «<код>» и вывод хука на настоящем входе отправки
    local out code sha
    sha="$(pgit -C "$box" rev-parse "$1")"
    out="$(
        cd "$box" || exit 111
        unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
              GIT_COMMON_DIR GIT_PREFIX KACHO_MONOREPO KACHO_SKIP_PREPUSH KACHO_PREPUSH_CONTEXT
        printf 'refs/heads/%s %s refs/heads/%s %s\n' "$1" "$sha" "$1" "$ZERO" \
            | env HOME="$SANDBOX_GIT_HOME" KACHO_SKIP_PREPUSH=0 \
                KACHO_HOME_KACHO="$TMP/p-kacho" KACHO_HOME_KANAME="$TMP/p-kaname" KACHO_HOME_CORELIB="$TMP/p-corelib" \
                bash ./scripts/hooks/pre-push origin "$box.git" 2>&1
    )" && code=0 || code=$?
    printf '%s\n%s\n' "$code" "$out"
}

probes=0 findings=0
judge() {  # <описание> <ветка> <ожидаемый код> <исполнялось: да|нет>
    local res body code ran=нет
    probes=$((probes + 1))
    res="$(push "$2")"; code="$(head -1 <<< "$res")"; body="$(tail -n +2 <<< "$res")"
    grep -qF -- "$MARK" <<< "$body" && ran=да
    if [ "$code" != "$3" ] || [ "$ran" != "$4" ]; then
        skills_gate_fail "$NAME" "$1 — ждали код $3 и исполнение доказательства «$4», получили код $code и «$ran»: $(grep -m2 -E 'ОТКАЗ|scripts/stub' <<< "$body" | tr '\n' ' ' | head -c 300)"
        findings=$((findings + 1))
    elif [ "$3" = 1 ] && ! grep -qF -- "scripts/stub/inject.sh" <<< "$body"; then
        skills_gate_fail "$NAME" "$1 — отказ без имени доказательства среди красных"
        findings=$((findings + 1))
    fi
}

newc 1402-red scripts/stub/inject.sh '# правка пробы'
printf 'красное\n' > "$box/red.txt"; pgit -C "$box" add red.txt; pgit -C "$box" commit -q -m "#1402 красное доказательство"
judge "правка inject.sh набора, доказательство красное — отказ отправки" 1402-red 1 да
newc 1402-check scripts/stub/check-01.sh '# правка проверки'
judge "правка check-* набора — доказательство исполнялось, зелёное" 1402-check 0 да
newc 1402-outside base.txt 'вне набора'
judge "близнец: правка вне набора — доказательство не исполнялось" 1402-outside 0 нет

echo "[CENSUS] $NAME: проб $probes, находок $findings"
[ "$findings" -eq 0 ] || exit 1
skills_gate_pass "$NAME" "хук отправки гонит доказательство тронутого набора, и красное доказательство останавливает отправку"
