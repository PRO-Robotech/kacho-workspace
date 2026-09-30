#!/usr/bin/env bash
# check-10 — хук отправки отвергает СОЗДАНИЕ ветки с именем не по форме
# `<N>-<суффикс>` и пропускает законные имена (`git-issues.md` §«Имя ветки»).
#
# Решение владельца 2026-09-30: «Таски именуй по номеру плюс постфикс от себя
# задачи которую делают что бы придерживаться гит флоу». Держатель формы —
# `scripts/hooks/pre-push`; эта проверка держит ХУК: без неё предикат имени
# в хуке можно ослабить до «всё законно», и отправка продолжит проходить молча.
#
# ПОВЕДЕНЧЕСКАЯ, А НЕ ТЕКСТОВАЯ — по той же причине, что `check-08`: копия хука
# кладётся в песочницу рядом с одним зелёным прогонщиком, на вход ей подаются
# строки `<local_ref> <local_sha> <remote_ref> <remote_sha>` — ровно то, что
# даёт git, — и читается код выхода и напечатанное. Текст отказа не
# закрепляется: требуется только, чтобы отказ НАЗЫВАЛ отвергнутое имя.
#
# ЧТО ТРЕБУЕТСЯ (исход и, где важно, напечатанное):
#   законные создания: 884-flow-acceleration, 2914-notify, 2915-c8-feed-put,
#     main, wip/x, тег                                  → 0;
#   незаконные создания: issue-880, epic-2914-notify, 77, 2914-Notify,
#     ntf/c8, суффикс в 41 символ                       → 1, имя названо,
#     и прогонщик наборов НЕ запускался (отказ до десяти минут проверок);
#   законное рядом с незаконным                         → 1 (антимаска);
#   удаление ветки прежней формы                        → 0 (снимать обязаны);
#   дописывание уже существующей ветки прежней формы    → 0 (самоистекающее
#     послабление: новых таких ссылок хук не допускает);
#   переходное условие релиза (владелец 2026-09-30, gi-branch-bare-number-release):
#     дописывание существующей на удалённом «26»        → 0,
#     создание новой «27»                               → 1, имя названо.
#
# ПРЕДПОСЫЛКА (исход VOID): хук есть в дереве и отвечает НУЛЁМ на законном
# имени. Хук, красный и на нём, к остальным пробам непригоден: отказ на
# незаконных именах прошёл бы на нём тождественно и не доказал бы ничего.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WS="$(tooling_gate_workspace_root)"
NAME="check-10-push-refuses-unlawful-branch-name"
HOOK="scripts/hooks/pre-push"

mapfile -t HOOKS < <(tooling_gate_files "$WS" "$HOOK")
if [ "${#HOOKS[@]}" -eq 0 ]; then
    tooling_gate_void "$NAME" "хука $HOOK в дереве нет — проверять нечего"
    exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ZERO=0000000000000000000000000000000000000000
SHA=1111111111111111111111111111111111111111
MARK="stub-run-all-исполнен"

# box — песочница с копией хука и одним зелёным прогонщиком, печатающим метку.
box="$(mktemp -d "$TMP/b.XXXXXX")"
mkdir -p "$box/scripts/hooks" "$box/scripts/stub"
cp "$WS/$HOOK" "$box/scripts/hooks/pre-push"
printf '#!/usr/bin/env bash\necho "%s"\nexit 0\n' "$MARK" > "$box/scripts/stub/run-all.sh"
git -C "$box" init -q
git -C "$box" add -A -f >/dev/null 2>&1

# push <вход git> — печатает «<код>» первой строкой и вывод хука следом.
push() {
    local out code
    out="$(
        cd "$box" || exit 111
        unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
              GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX \
              KACHO_MONOREPO KACHO_SKIP_PREPUSH
        printf '%s\n' "$1" | bash ./scripts/hooks/pre-push origin 2>&1
    )"; code=$?
    printf '%s\n%s\n' "$code" "$out"
}

create() { printf 'refs/heads/%s %s refs/heads/%s %s' "$1" "$SHA" "$1" "$ZERO"; }

findings=0
examined=0
lawful=0
unlawful=0
fail() { tooling_gate_fail "$NAME" "$1"; findings=$((findings + 1)); }

# Предпосылка.
res="$(push "$(create 884-flow-acceleration)")"
if [ "$(head -1 <<< "$res")" -ne 0 ]; then
    tooling_gate_void "$NAME" "$HOOK — на законном имени 884-flow-acceleration вернул $(head -1 <<< "$res"); остальные пробы на нём недоказательны"
    exit 2
fi

expect_pass() {  # <описание> <вход>
    local res
    examined=$((examined + 1)); lawful=$((lawful + 1))
    res="$(push "$2")"
    [ "$(head -1 <<< "$res")" -eq 0 ] \
        || fail "$1 — отвергнуто (код $(head -1 <<< "$res")), а форма законна"
}

expect_refuse() {  # <имя-которое-обязан-назвать> <описание> <вход>
    local res body
    examined=$((examined + 1)); unlawful=$((unlawful + 1))
    res="$(push "$3")"; body="$(tail -n +2 <<< "$res")"
    if [ "$(head -1 <<< "$res")" -ne 1 ]; then
        fail "$2 — хук вышел $(head -1 <<< "$res") вместо 1: ветка незаконной формы уехала бы"
    elif ! grep -qF -- "$1" <<< "$body"; then
        fail "$2 — отказ не называет отвергнутое имя «$1»"
    elif grep -qF -- "$MARK" <<< "$body"; then
        fail "$2 — отказ пришёл ПОСЛЕ прогона наборов, а не до него"
    fi
}

for n in 884-flow-acceleration 2914-notify 2915-c8-feed-put main wip/x \
         "2914-$(printf 'a%.0s' $(seq 40))"; do
    expect_pass "создание «$n»" "$(create "$n")"
done
expect_pass "тег не судится" "refs/tags/v1 $SHA refs/tags/v1 $ZERO"
expect_pass "удаление ветки прежней формы issue-880" \
    "(delete) $ZERO refs/heads/issue-880 $SHA"
expect_pass "дописывание существующей ветки прежней формы issue-880" \
    "refs/heads/issue-880 $SHA refs/heads/issue-880 2222222222222222222222222222222222222222"

for n in issue-880 epic-2914-notify 77 2914-Notify ntf/c8 2914_notify \
         "2914-$(printf 'a%.0s' $(seq 41))"; do
    expect_refuse "$n" "создание «$n»" "$(create "$n")"
done
# Переходное условие релиза: голый номер, уже существующий на удалённом,
# дописывается; новый голый номер — отказ. Отправка релиза не останавливается.
expect_pass "дописывание существующей на удалённом ветки релиза «26»" \
    "refs/heads/26 $SHA refs/heads/26 2222222222222222222222222222222222222222"
expect_refuse 27 "создание новой ветки с голым номером «27»" "$(create 27)"
expect_refuse issue-880 "законное рядом с незаконным (антимаска)" \
    "$(create 2914-notify)
$(create issue-880)"

tooling_gate_census "$NAME: хуков осмотрено ${#HOOKS[@]}, проб по входу git $examined (законных $lawful, незаконных $unlawful)"

if [ "$findings" -gt 0 ]; then
    tooling_gate_fail "$NAME" "проб с находкой: $findings"
    exit 1
fi

tooling_gate_pass "$NAME" "хук отвергает создание ветки не по форме «<N>-<суффикс>» до прогона наборов и называет имя; законные имена, удаление и дописывание прежних (в т.ч. голого номера релиза) проходят"
