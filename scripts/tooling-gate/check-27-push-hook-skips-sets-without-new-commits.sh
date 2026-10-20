#!/usr/bin/env bash
# check-27 — хук отправки не гонит наборы, когда в отправляемых ссылках нет ни
# одного коммита, которого нет в ветках удалённого, и гонит их при любом новом
# (ws#1288).
#
# Признак: ветка заводилась на sha, уже лежащей на origin, и хук прогонял полные
# наборы над деревом, которое опубликовано и судилось (у монорепо — около 20 мин
# полного ci-local). Держатель — scripts/hooks/prepush-new-commits.sh, который
# scripts/hooks/pre-push зовёт после ветви одних удалений.
#
# ПОВЕДЕНЧЕСКАЯ, как check-25: песочница — настоящий репозиторий с голым удалённым,
# в её дереве — копии хука, стражей и предиката и прогонщик-заглушка, печатающая
# метку.
#
# ЧТО ТРЕБУЕТСЯ:
#   наборы НЕ идут (код 0, строка «новых коммитов 0 — наборы не нужны», метки нет):
#     ветка на опубликованной sha; две такие ветки в одной отправке; слияние
#     опубликованных голов, чьё дерево равно дереву одного из родителей;
#   наборы идут (код 0, метка заглушки есть):
#     ветка с одним новым коммитом; пустой коммит (новый коммит без нового
#     дерева); sha, существующая только локально; ссылка без новых рядом с
#     ссылкой с новым; догон — слияние опубликованных голов, чьё дерево
#     отличается от деревьев обоих родителей (единственный новый коммит —
#     слияние); отправка одних удалений (своя строка хука, не «новых 0»).
#
# ПРЕДПОСЫЛКА (VOID): ветка с новым коммитом гонит заглушку. Хук, не доходящий до
# наборов на ней, делает остальные пробы тождественно зелёными.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/sandbox-git-home.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/sandbox-git-home.sh"

WS="$(tooling_gate_workspace_root)"
NAME="check-27-push-hook-skips-sets-without-new-commits"
KIT=(pre-push prepush-attribution.sh attribution-rule.sh prepush-added-files.sh branch-name-rule.sh prepush-new-commits.sh)

missing=()
for f in "${KIT[@]}"; do
    [ -n "$(tooling_gate_files "$WS" "scripts/hooks/$f")" ] || missing+=("scripts/hooks/$f")
done
if [ "${#missing[@]}" -gt 0 ]; then
    tooling_gate_void "$NAME" "в дереве нет ${missing[*]} — проверять нечего"
    exit 2
fi

TMP="$(mktemp -d)"
# shellcheck disable=SC2154
trap '_rc=$?; rm -rf "$TMP" 2>/dev/null || rm -rf "$TMP" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $TMP не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT
if ! sandbox_git_home "$TMP/home"; then
    tooling_gate_void "$NAME" "корневой подписи нет — вершина песочницы не родится, судить хук не на чем"
    exit 2
fi
pgit() { sandbox_git -c core.hooksPath=/dev/null "$@"; }

ZERO=0000000000000000000000000000000000000000
MARK="stub-run-all-исполнен"
SKIP="новых коммитов 0 — наборы не нужны"
box="$TMP/box"
mkdir -p "$box/scripts/hooks" "$box/scripts/stub"
for f in "${KIT[@]}"; do cp "$WS/scripts/hooks/$f" "$box/scripts/hooks/"; done
chmod +x "$box/scripts/hooks/"*
: > "$box/scripts/hooks/prepush-added-files.allow"
printf 'основа\n' > "$box/base.txt"
printf '#!/usr/bin/env bash\necho "%s"\nexit 0\n' "$MARK" > "$box/scripts/stub/run-all.sh"
chmod +x "$box/scripts/stub/run-all.sh"
pgit -C "$box" init -q -b main
pgit -C "$box" add -A
pgit -C "$box" commit -q -m "#1 песочница check-27"
pgit init -q --bare "$box.git"
pgit -C "$box" remote add origin "$box.git"
pgit -C "$box" push -q origin main
BASE="$(pgit -C "$box" rev-parse HEAD)"

branch() { pgit -C "$box" checkout -q -f -B "$1" "${2:-$BASE}"; }
commit() { local m="$1"; shift; pgit -C "$box" add -- "$@"; pgit -C "$box" commit -q -m "$m"; }
head_sha() { pgit -C "$box" rev-parse HEAD; }
publish() { pgit -C "$box" push -q origin "$1:refs/heads/$1"; }
line() { printf 'refs/heads/%s %s refs/heads/%s %s' "$1" "$(pgit -C "$box" rev-parse "$1")" "$1" "$ZERO"; }

push() {  # <вход git> — «<код>» первой строкой и вывод хука следом
    local input="$1" out code
    out="$(
        cd "$box" || exit 111
        unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
              GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX \
              KACHO_MONOREPO KACHO_SKIP_PREPUSH
        printf '%s\n' "$input" | env HOME="$SANDBOX_GIT_HOME" bash ./scripts/hooks/pre-push origin "$box.git" 2>&1
    )" && code=0 || code=$?
    printf '%s\n%s\n' "$code" "$out"
}

findings=0 examined=0 skipped=0 ran=0
fail() { tooling_gate_fail "$NAME" "$1"; findings=$((findings + 1)); }
expect_skip() {  # <описание> <вход>
    local d="$1" res body
    examined=$((examined + 1)); skipped=$((skipped + 1))
    res="$(push "$2")"; body="$(tail -n +2 <<< "$res")"
    if [ "$(head -1 <<< "$res")" -ne 0 ]; then
        fail "$d — хук вышел $(head -1 <<< "$res") вместо 0: $(grep -m2 'ОТКАЗ' <<< "$body" | tr '\n' ' ')"
    elif grep -qF -- "$MARK" <<< "$body"; then
        fail "$d — наборы шли, а новых коммитов нет"
    elif ! grep -qF -- "$SKIP" <<< "$body"; then
        fail "$d — хук молчал о причине: нет строки «$SKIP»"
    fi
}
expect_run() {  # <описание> <вход>
    local d="$1" res body
    examined=$((examined + 1)); ran=$((ran + 1))
    res="$(push "$2")"; body="$(tail -n +2 <<< "$res")"
    if [ "$(head -1 <<< "$res")" -ne 0 ]; then
        fail "$d — хук вышел $(head -1 <<< "$res") вместо 0: $(grep -m2 'ОТКАЗ' <<< "$body" | tr '\n' ' ')"
    elif ! grep -qF -- "$MARK" <<< "$body"; then
        fail "$d — наборы НЕ шли, а новый коммит есть: непроверенное уехало бы"
    elif grep -qF -- "$SKIP" <<< "$body"; then
        fail "$d — хук объявил «$SKIP» при новом коммите"
    fi
}

# Предпосылка.
branch 1288-new; printf 'новое\n' > "$box/n.txt"; commit "#1288 новый" n.txt
res="$(push "$(line 1288-new)")"
if [ "$(head -1 <<< "$res")" -ne 0 ] || ! grep -qF -- "$MARK" <<< "$res"; then
    tooling_gate_void "$NAME" "ветка с новым коммитом не дошла до заглушки наборов (код $(head -1 <<< "$res")); остальные пробы недоказательны: $(tail -n +2 <<< "$res" | tr '\n' ' ' | head -c 400)"
    exit 2
fi

# ── Наборы не нужны ──────────────────────────────────────────────────────────
branch 1288-same
expect_skip "ветка на опубликованной sha" "$(line 1288-same)"
branch 1288-same2
expect_skip "две ветки на опубликованной sha в одной отправке" "$(line 1288-same)
$(line 1288-same2)"

# Слияние, дерево которого равно дереву родителя (вторая голова — потомок первой).
branch 1288-ahead; printf 'впереди\n' > "$box/ahead.txt"; commit "#1288 впереди" ahead.txt; publish 1288-ahead
branch 1288-ff
pgit -C "$box" merge -q --no-ff -m "#1288 слияние опубликованного" 1288-ahead > /dev/null 2>&1
expect_skip "слияние опубликованных голов, дерево равно дереву родителя" "$(line 1288-ff)"

# ── Наборы нужны ─────────────────────────────────────────────────────────────
expect_run "ветка с одним новым коммитом" "$(line 1288-new)"
branch 1288-empty; pgit -C "$box" commit -q --allow-empty -m "#1288 пустой"
expect_run "пустой коммит — новый коммит с прежним деревом" "$(line 1288-empty)"
branch 1288-local; printf 'лок\n' > "$box/l.txt"; commit "#1288 лишь локально" l.txt
expect_run "sha существует только локально" "$(line 1288-local)"
expect_run "ссылка без новых рядом со ссылкой с новым" "$(line 1288-same)
$(line 1288-new)"
expect_run "ссылка с новым рядом со ссылкой без новых" "$(line 1288-new)
$(line 1288-same)"

# Догон: две опубликованные головы с разными файлами, новый — только слияние.
branch 1288-a; printf 'a\n' > "$box/a.txt"; commit "#1288 а" a.txt; publish 1288-a
branch 1288-b; printf 'b\n' > "$box/b.txt"; commit "#1288 б" b.txt; publish 1288-b
branch 1288-catch 1288-a
pgit -C "$box" merge -q --no-ff -m "#1288 догон" 1288-b > /dev/null 2>&1
expect_run "догон: слияние опубликованных голов с деревом, отличным от обоих родителей" "$(line 1288-catch)"

# Одни удаления: своя строка хука, не «новых коммитов 0».
examined=$((examined + 1)); skipped=$((skipped + 1))
res="$(push "refs/heads/1288-gone $ZERO refs/heads/1288-gone $(pgit -C "$box" rev-parse 1288-a)")"
if [ "$(head -1 <<< "$res")" -ne 0 ] || grep -qF -- "$SKIP" <<< "$res" || ! grep -qF 'только удаление' <<< "$res"; then
    fail "отправка одних удалений: код $(head -1 <<< "$res") либо названа «новых коммитов 0» вместо своей строки"
fi

# Предиката нет рядом с хуком — наборы идут как прежде (ускорение не отнимает проверку).
mv "$box/scripts/hooks/prepush-new-commits.sh" "$TMP/pred.away"
expect_run "предиката нет рядом с хуком — наборы идут" "$(line 1288-same)"
mv "$TMP/pred.away" "$box/scripts/hooks/prepush-new-commits.sh"

tooling_gate_census "$NAME: хук и предикат осмотрены, проб по входу git $examined (без наборов $skipped, с наборами $ran)"
if [ "$findings" -gt 0 ]; then
    tooling_gate_fail "$NAME" "проб с находкой: $findings"
    exit 1
fi
tooling_gate_pass "$NAME" "наборы не идут при нуле новых коммитов (слияние с деревом родителя — не новое) и идут при любом новом: пустой коммит, локальная sha, догон с новым деревом, смесь ссылок; удаление нулём не считается"
