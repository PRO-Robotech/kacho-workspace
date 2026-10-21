#!/usr/bin/env bash
# check-27 — хук отправки не гонит наборы, когда каждая отправляемая вершина уже
# судилась этим хуком зелёным, и гонит их при любой непроверенной (ws#1288).
#
# Признак: ветка заводилась на sha, уже проверенную хуком, и наборы второй раз
# судили то же дерево (у монорепо — полный ci-local). Держатель —
# scripts/hooks/prepush-new-commits.sh (запись проверенного в общем каталоге git),
# который scripts/hooks/pre-push зовёт после ветви одних удалений и пополняет
# после зелёного прогона.
#
# ПОВЕДЕНЧЕСКАЯ, как check-25: песочница — настоящий репозиторий с голым удалённым
# и голым форком, в её дереве — копии хука, стражей и предиката и
# прогонщик-заглушка, печатающая метку (и красная, когда в дереве red.txt).
# «Проверено» в песочнице ставит только сам хук прогоном до заглушки.
#
# ЧТО ТРЕБУЕТСЯ:
#   наборы НЕ идут (код 0, строка «наборы не нужны», метки нет):
#     T1b новое имя на проверенной вершине; две такие ссылки в одной отправке;
#     слияние, дерево которого равно дереву проверенного родителя; проверенная
#     вершина, отправленная адресом;
#   наборы идут (метка заглушки есть, строки «не нужны» нет) — опыт check-verifier
#   ws#1288 и его близнецы:
#     коммит, не судившийся хуком; пустой коммит поверх проверенной; предок
#     проверенной (T-mid); непроверенная рядом с проверенной в обоих порядках;
#     догон с деревом, отличным от обоих проверенных родителей; слияние с деревом
#     НЕпроверенного родителя; красная вершина под новым именем (код 1 оба раза);
#     D1b черновик wip/, затем то же под обычным именем; D1env-b отправка с
#     KACHO_SKIP_PREPUSH=1, затем новое имя; D2b коммит лишь в форке, отправка в
#     origin адресом, и D2a — по имени; D3a черновик снят на сервере, отслеживание
#     осталось, и D3b — после fetch --prune; D4a тег на черновом коммите, D4b — на
#     локальном; D5 ствол переводится на черновой коммит (прежняя голова в
#     4-м поле); ствол продукта ушёл вперёд после проверки (условие вердикта —
#     ревизии стволов); отправка одних удалений — своя строка хука; предиката нет
#     рядом — наборы как прежде.
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
SKIP="наборы не нужны"
box="$TMP/box"
mkdir -p "$box/scripts/hooks" "$box/scripts/stub"
for f in "${KIT[@]}"; do cp "$WS/scripts/hooks/$f" "$box/scripts/hooks/"; done
chmod +x "$box/scripts/hooks/"*
: > "$box/scripts/hooks/prepush-added-files.allow"
printf 'основа\n' > "$box/base.txt"
printf '#!/usr/bin/env bash\necho "%s"\n[ ! -f red.txt ] || exit 1\nexit 0\n' "$MARK" > "$box/scripts/stub/run-all.sh"
chmod +x "$box/scripts/stub/run-all.sh"
mkdir -p "$box/scripts/lib"; cp "$WS/scripts/lib/product_clone.py" "$box/scripts/lib/"
pgit -C "$box" init -q -b main
pgit -C "$box" add -A
pgit -C "$box" commit -q -m "#1 песочница check-27"
pgit init -q --bare "$box.git"
pgit init -q --bare "$TMP/fork.git"
pgit -C "$box" remote add origin "$box.git"
pgit -C "$box" remote add fork "$TMP/fork.git"
pgit -C "$box" push -q origin main
BASE="$(pgit -C "$box" rev-parse HEAD)"

# Стволы продуктов — синтетические клоны с голым origin: условие вердикта хука
# (ревизии стволов) берётся из них, как из настоящих (`scripts/lib/product_clone.py`,
# `KACHO_HOME_<ИМЯ>`), и fetch идёт без сети.
for r in kacho kaname corelib; do
    pgit init -q --bare -b main "$TMP/p-$r.git"
    pgit init -q -b main "$TMP/p-$r"
    printf '%s\n' "$r" > "$TMP/p-$r/r.txt"
    pgit -C "$TMP/p-$r" add r.txt; pgit -C "$TMP/p-$r" commit -q -m "#1 ствол $r"
    pgit -C "$TMP/p-$r" remote add origin "$TMP/p-$r.git"
    pgit -C "$TMP/p-$r" push -q origin main
done
advance_trunk() {  # <репозиторий> — ствол продукта уходит вперёд на сервере
    printf 'вперёд\n' >> "$TMP/p-$1/r.txt"
    pgit -C "$TMP/p-$1" commit -q -am "#1 ствол $1 вперёд"; pgit -C "$TMP/p-$1" push -q origin main
}

n_commit=0
branch() { pgit -C "$box" checkout -q -f -B "$1" "${2:-$BASE}"; }
newc() {  # <ветка> [<от>] — ветка с одним новым коммитом (файл своего имени)
    branch "$1" "${2:-$BASE}"; n_commit=$((n_commit + 1))
    printf '%s\n' "$n_commit" > "$box/c$n_commit.txt"
    pgit -C "$box" add -- "c$n_commit.txt"; pgit -C "$box" commit -q -m "#1288 $1"
}
sha() { pgit -C "$box" rev-parse "$1"; }
publish() { pgit -C "$box" push -q "${3:-origin}" "$1:refs/heads/${2:-$1}"; }  # без хука
line() { printf 'refs/heads/%s %s refs/heads/%s %s' "$1" "$(sha "$1")" "${2:-$1}" "$ZERO"; }

push() {  # <вход git> [<первый довод хука>] [<KACHO_SKIP_PREPUSH>] — «<код>» и вывод
    local input="$1" arg="${2:-origin}" skipenv="${3:-0}" out code
    out="$(
        cd "$box" || exit 111
        unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
              GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX \
              KACHO_MONOREPO KACHO_SKIP_PREPUSH KACHO_PREPUSH_CONTEXT
        printf '%s\n' "$input" | env HOME="$SANDBOX_GIT_HOME" KACHO_SKIP_PREPUSH="$skipenv" \
            KACHO_HOME_KACHO="$TMP/p-kacho" KACHO_HOME_KANAME="$TMP/p-kaname" KACHO_HOME_CORELIB="$TMP/p-corelib" \
            bash ./scripts/hooks/pre-push "$arg" "$box.git" 2>&1
    )" && code=0 || code=$?
    printf '%s\n%s\n' "$code" "$out"
}

findings=0 examined=0 skipped=0 ran=0
fail() { tooling_gate_fail "$NAME" "$1"; findings=$((findings + 1)); }
expect_skip() {  # <описание> <вход> [<довод хука>]
    local d="$1" res body
    examined=$((examined + 1)); skipped=$((skipped + 1))
    res="$(push "$2" "${3:-origin}")"; body="$(tail -n +2 <<< "$res")"
    if [ "$(head -1 <<< "$res")" -ne 0 ]; then
        fail "$d — хук вышел $(head -1 <<< "$res") вместо 0: $(grep -m2 'ОТКАЗ' <<< "$body" | tr '\n' ' ')"
    elif grep -qF -- "$MARK" <<< "$body"; then
        fail "$d — наборы шли, а вершина уже проверена"
    elif ! grep -qF -- "$SKIP" <<< "$body"; then
        fail "$d — хук молчал о причине: нет строки «$SKIP»"
    fi
}
expect_run() {  # <описание> <вход> [<довод хука>] [<код, по умолчанию 0>]
    local d="$1" res body want="${4:-0}"
    examined=$((examined + 1)); ran=$((ran + 1))
    res="$(push "$2" "${3:-origin}")"; body="$(tail -n +2 <<< "$res")"
    if ! grep -qF -- "$MARK" <<< "$body"; then
        fail "$d — наборы НЕ шли, а вершина не проверена: непроверенное уехало бы"
    elif grep -qF -- "$SKIP" <<< "$body"; then
        fail "$d — хук объявил «$SKIP» при непроверенной вершине"
    elif [ "$(head -1 <<< "$res")" -ne "$want" ]; then
        fail "$d — хук вышел $(head -1 <<< "$res") вместо $want: $(grep -m2 'ОТКАЗ' <<< "$body" | tr '\n' ' ')"
    fi
}
silent() {  # <описание> <вход> [<довод>] [<KACHO_SKIP_PREPUSH>] — посев: код 0 и без заглушки
    local res
    res="$(push "$2" "${3:-origin}" "${4:-0}")"
    if [ "$(head -1 <<< "$res")" -ne 0 ] || grep -qF -- "$MARK" <<< "$res"; then
        tooling_gate_void "$NAME" "посев «$1» не прошёл без наборов (код $(head -1 <<< "$res")): $(tail -n +2 <<< "$res" | tr '\n' ' ' | head -c 300)"
        exit 2
    fi
}

# Предпосылка: новый коммит гонит заглушку — и хук записывает вершину проверенной.
newc 1288-new
res="$(push "$(line 1288-new)")"
if [ "$(head -1 <<< "$res")" -ne 0 ] || ! grep -qF -- "$MARK" <<< "$res"; then
    tooling_gate_void "$NAME" "ветка с новым коммитом не дошла до заглушки наборов (код $(head -1 <<< "$res")); остальные пробы недоказательны: $(tail -n +2 <<< "$res" | tr '\n' ' ' | head -c 400)"
    exit 2
fi
publish 1288-new

# ── Наборы не нужны ──────────────────────────────────────────────────────────
branch 1288-t1b 1288-new
expect_skip "T1b: новое имя на проверенной вершине" "$(line 1288-t1b)"
expect_skip "две ссылки на проверенной вершине в одной отправке" "$(line 1288-t1b)
$(line 1288-new 1288-t1c)"
expect_skip "проверенная вершина, отправленная адресом" "$(line 1288-t1b 1288-t1d)" "$box.git"

newc 1288-ahead
expect_run "коммит, не судившийся хуком" "$(line 1288-ahead)"
publish 1288-ahead
branch 1288-ff
pgit -C "$box" merge -q --no-ff -m "#1288 слияние проверенного" 1288-ahead > /dev/null 2>&1
expect_skip "слияние с деревом проверенного родителя" "$(line 1288-ff)"

# ── Наборы нужны ─────────────────────────────────────────────────────────────
branch 1288-empty 1288-new; pgit -C "$box" commit -q --allow-empty -m "#1288 пустой"
expect_run "пустой коммит поверх проверенной вершины" "$(line 1288-empty)"

newc 1288-two; newc 1288-two2 1288-two; branch 1288-two 1288-two2
expect_run "посев T-mid: две вершины одной отправкой" "$(line 1288-two)"
branch 1288-mid "1288-two2~1"
expect_run "T-mid: предок проверенной вершины" "$(line 1288-mid)"

newc 1288-mixa; newc 1288-mixb
expect_run "непроверенная перед проверенной" "$(line 1288-mixa)
$(line 1288-t1b)"
expect_run "непроверенная после проверенной" "$(line 1288-t1b)
$(line 1288-mixb)"

newc 1288-a; expect_run "посев догона: голова а" "$(line 1288-a)"; publish 1288-a
newc 1288-b; expect_run "посев догона: голова б" "$(line 1288-b)"; publish 1288-b
branch 1288-catch 1288-a
pgit -C "$box" merge -q --no-ff -m "#1288 догон" 1288-b > /dev/null 2>&1
expect_run "догон: дерево слияния отлично от обоих проверенных родителей" "$(line 1288-catch)"

newc 1288-pub; publish 1288-pub
branch 1288-ffu
pgit -C "$box" merge -q --no-ff -m "#1288 слияние непроверенного" 1288-pub > /dev/null 2>&1
expect_run "слияние с деревом НЕпроверенного родителя" "$(line 1288-ffu)"

branch 1288-red; printf 'красное\n' > "$box/red.txt"; pgit -C "$box" add red.txt; pgit -C "$box" commit -q -m "#1288 красная"
expect_run "посев: красная вершина" "$(line 1288-red)" origin 1
branch 1288-red2 1288-red
expect_run "красная вершина под новым именем — не записана проверенной" "$(line 1288-red2)" origin 1
pgit -C "$box" checkout -q -f main

newc 1288-d1b
silent "D1b: черновик" "$(line 1288-d1b wip/1288-d1b)"
publish 1288-d1b wip/1288-d1b
expect_run "D1b: черновик wip/, затем то же под обычным именем" "$(line 1288-d1b)"

newc 1288-env
silent "D1env-b: обход" "$(line 1288-env)" origin 1
publish 1288-env
branch 1288-env2 1288-env
expect_run "D1env-b: отправка с KACHO_SKIP_PREPUSH=1, затем новое имя" "$(line 1288-env2)"

newc 1288-forka; publish 1288-forka 1288-forka fork
newc 1288-forkb; publish 1288-forkb 1288-forkb fork
pgit -C "$box" fetch -q fork
expect_run "D2b: коммит лишь в форке, отправка в origin адресом" "$(line 1288-forka)" "$box.git"
expect_run "D2a: коммит лишь в форке, отправка по имени" "$(line 1288-forkb)"

newc 1288-gone; publish 1288-gone wip/1288-gone
pgit -C "$box.git" update-ref -d refs/heads/wip/1288-gone
expect_run "D3a: черновик снят на сервере, отслеживание осталось" "$(line 1288-gone)"
newc 1288-prune; publish 1288-prune wip/1288-prune
pgit -C "$box.git" update-ref -d refs/heads/wip/1288-prune
pgit -C "$box" fetch -q --prune origin
expect_run "D3b: черновик снят, после fetch --prune" "$(line 1288-prune)"

newc 1288-tagd; publish 1288-tagd wip/1288-tagd
expect_run "D4a: тег на черновом коммите" "refs/tags/t-d $(sha 1288-tagd) refs/tags/t-d $ZERO"
newc 1288-tagl
expect_run "D4b: тег на локальном коммите" "refs/tags/t-l $(sha 1288-tagl) refs/tags/t-l $ZERO"

newc 1288-d5; publish 1288-d5 wip/1288-d5
expect_run "D5: ствол переводится на черновой коммит" "refs/heads/main $(sha 1288-d5) refs/heads/main $BASE"

# Условие вердикта: ствол продукта ушёл вперёд — проверенная вчера вершина
# сегодня не проверена (близнец — T1b выше, ствол на месте).
advance_trunk kaname
branch 1288-ctx 1288-new
expect_run "ствол продукта ушёл вперёд — новое имя на проверенной вершине" "$(line 1288-ctx)"
expect_skip "ствол на месте после перепроверки — снова наборы не нужны" "$(line 1288-ctx 1288-ctx2)"

# Одни удаления: своя строка хука, не «наборы не нужны».
examined=$((examined + 1)); skipped=$((skipped + 1))
res="$(push "refs/heads/1288-gone $ZERO refs/heads/1288-gone $(sha 1288-a)")"
if [ "$(head -1 <<< "$res")" -ne 0 ] || grep -qF -- "$SKIP" <<< "$res" || ! grep -qF 'только удаление' <<< "$res"; then
    fail "отправка одних удалений: код $(head -1 <<< "$res") либо названа «$SKIP» вместо своей строки"
fi

# Предиката нет рядом с хуком — наборы идут как прежде (ускорение не отнимает проверку).
mv "$box/scripts/hooks/prepush-new-commits.sh" "$TMP/pred.away"
expect_run "предиката нет рядом с хуком — наборы идут" "$(line 1288-t1b)"
mv "$TMP/pred.away" "$box/scripts/hooks/prepush-new-commits.sh"

tooling_gate_census "$NAME: хук и предикат осмотрены, проб по входу git $examined (без наборов $skipped, с наборами $ran)"
if [ "$findings" -gt 0 ]; then
    tooling_gate_fail "$NAME" "проб с находкой: $findings"
    exit 1
fi
tooling_gate_pass "$NAME" "наборы не идут, лишь когда каждая вершина судилась этим хуком зелёным (слияние с деревом проверенного родителя — тоже); идут на черновике, обходе, форке, снятой ссылке, теге, переводе ствола, предке, пустом коммите, красной вершине, догоне и смеси ссылок"
