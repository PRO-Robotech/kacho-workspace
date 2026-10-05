#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# lane-precheck.sh — предпроверка полосы ДО ревью и сборки: условия, которые
# раньше проверял текст диспетчера и которые за 2026-10-04…06 стоили возвратов
# не из-за кода (замер 2026-10-06: класс «механика исполнителя» 43 возврата —
# незакоммичено или не отправлено, преждевременный Closes, устаревший отпечаток;
# класс «ложный провал или повтор на той же голове» 172).
#
# ОСНОВАНИЕ. Решение владельца 2026-10-06 — процесс по уровням риска, ритуалы и
# обязательные условия — механически, скриптами. Шаги уровня берутся из
# `scripts/lane-tier.sh`; эта предпроверка — шаг `lane-precheck` КАЖДОГО уровня.
#
# usage: lane-precheck.sh <каталог копии> <ветка> <база> [--issue <владелец/репо>#<N>]…
#                          [--hook-log <файл>]
#
# ЧТО СУДИТ (каждый пункт — своя причина, строкой `REASON <КОД> <текст>`):
#   HEAD-NOT-ON-ORIGIN  ветки нет на origin (`git ls-remote`, а не память);
#   HEAD-DIVERGED       голова на origin ≠ голове ветки в копии: ревью судило бы
#                       не то, что отправлено;
#   BASE-NOT-ANCESTOR   база не предок головы: полоса ответвлена не от того;
#   MAIN-COPY           копия вне `<WS>/tmp/` (ws#923: отправка из основной копии
#                       исполняет устаревший хук);
#   ISSUES-NONE         задач полосы ноль: доказательство судить не о чем;
#   DOD-PROOF-MISSING   у задачи нет комментария `DoD-proof @<sha>` (форма —
#                       `CLAUDE.md`, та же, что судит `cascade-census.sh --proof`),
#                       чей sha — голова полосы или коммит из база..голова:
#                       доказательство чужой или прежней ревизии — не доказательство;
#   HOOK-LOG-MISSING    журнала отправки нет;
#   HOOK-HEAD-MISMATCH  журнал отправки — не о текущей голове;
#   HOOK-RC             отправка вышла не нулём;
#   HOOK-BYPASSED       хук пропущен обходом (`*_SKIP_PREPUSH=1`) либо черновиком;
#   HOOK-NOT-GREEN      в журнале нет строки ЗЕЛЁНОГО итога хука этого
#                       репозитория (строка «без предмета» воркспейса — не зелёная).
#
# ЖУРНАЛ ОТПРАВКИ — форма, которую пишет исполнитель (передача через файлы,
# `<WS>/tmp/wave-<N>/<полоса>/push.log`):
#     { echo "lane-push head=$(git rev-parse HEAD)"; git push origin HEAD:refs/heads/<ветка> 2>&1; echo "lane-push rc=$?"; } > push.log
# Голова и код — строки обёртки, итог хука — его собственная строка. Строки
# зелёного итога (закрытый словарь, по репозиторию из адреса origin):
#     kacho-workspace  «pre-push: локальные проверки воркспейса зелёные»
#     kacho            «== pre-push: локальные проверки зелёные (не выполненных нет)»
#     kaname           «pre-push: зелёное — исполнено N из M групп, отказов 0.»
#     corelib          «pre-push (corelib): исполнено N из N, красных 0»
# ГРАНИЦА (названо, не ловится): журнал, написанный руками без отправки, этой
# проверкой не отличим от настоящего; сверка головы с origin сужает подлог до
# «отправлено, но хук не исполнялся», а это ловит HOOK-NOT-GREEN.
#
# ТРЕКЕР — через `LANE_PRECHECK_GH` (по умолчанию `gh`): инъекция подставляет
# обёртку без сети. Дом копий — `LANE_PRECHECK_WS` либо корень воркспейса,
# выведенный из общего каталога git этого скрипта.
#
# Коды: 0 — причин ноль и всё судимое осуждено; 1 — хотя бы одна причина;
# 2 — причин ноль, но часть не судима (VOID: ветка не читается, трекер не
# ответил, хук репозитория вне словаря). Перепись печатается всегда.
# Держит `scripts/lane-precheck-inject.sh`.
set -uo pipefail

usage() {
    echo "usage: lane-precheck.sh <каталог копии> <ветка> <база> [--issue <владелец/репо>#<N>]… [--hook-log <файл>]" >&2
    exit 2
}

issues=() hook_log="" pos=()
while [ $# -gt 0 ]; do
    case "$1" in
        --issue) [ $# -ge 2 ] || usage; issues+=("$2"); shift 2 ;;
        --hook-log) [ $# -ge 2 ] || usage; hook_log="$2"; shift 2 ;;
        -h | --help) usage ;;
        *) pos+=("$1"); shift ;;
    esac
done
[ "${#pos[@]}" -eq 3 ] || usage
dir="${pos[0]}" branch="${pos[1]}" base="${pos[2]}"
GH="${LANE_PRECHECK_GH:-gh}"

reasons=() voids=()
reason() { reasons+=("$1 $2"); }
void() { voids+=("$1 $2"); }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -n "${LANE_PRECHECK_WS:-}" ]; then
    WS="$(cd "$LANE_PRECHECK_WS" 2> /dev/null && pwd -P)" || WS="$LANE_PRECHECK_WS"
else
    common="$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2> /dev/null)" || common=""
    WS="${common%/.git}"
fi

top="$(git -C "$dir" rev-parse --show-toplevel 2> /dev/null)" || top=""
if [ -z "$top" ]; then
    echo "lane-precheck: копия $dir — не рабочая копия git; вердикта нет" >&2
    exit 2
fi
top="$(cd "$top" && pwd -P)"

head="$(git -C "$top" rev-parse --verify --quiet "refs/heads/$branch^{commit}" 2> /dev/null)" || head=""
[ -n "$head" ] || void BRANCH-UNKNOWN "ветки $branch в копии нет"

# ── копия ─────────────────────────────────────────────────────────────────
if [ -z "$WS" ]; then
    void WS-UNKNOWN "корень воркспейса не выведен — дом копий судить не с чем"
else
    case "$top/" in
        "$WS/tmp/"?*) ;;
        *) reason MAIN-COPY "копия $top вне $WS/tmp/ (ws#923)" ;;
    esac
fi

# ── голова на origin и база ─────────────────────────────────────────────
remote_head=""
if ls_out="$(git -C "$top" ls-remote origin "refs/heads/$branch" 2> /dev/null)"; then
    remote_head="$(printf '%s\n' "$ls_out" | awk -v r="refs/heads/$branch" '$2 == r { print $1; exit }')"
    if [ -z "$remote_head" ]; then
        reason HEAD-NOT-ON-ORIGIN "ветки $branch на origin нет"
    elif [ -n "$head" ] && [ "$remote_head" != "$head" ]; then
        reason HEAD-DIVERGED "origin ${remote_head:0:12} ≠ копия ${head:0:12}"
    fi
else
    void ORIGIN-UNREADABLE "origin копии $top не ответил на ls-remote"
fi

base_sha="$(git -C "$top" rev-parse --verify --quiet "$base^{commit}" 2> /dev/null)" || base_sha=""
if [ -z "$base_sha" ]; then
    void BASE-UNKNOWN "база $base в копии не разрешается"
elif [ -n "$head" ] && ! git -C "$top" merge-base --is-ancestor "$base_sha" "$head"; then
    reason BASE-NOT-ANCESTOR "база ${base_sha:0:12} не предок головы ${head:0:12}"
fi

# in_lane <sha> — sha равен голове либо лежит в база..голова.
in_lane() {
    local s full
    s="$1"
    full="$(git -C "$top" rev-parse --verify --quiet "$s^{commit}" 2> /dev/null)" || return 1
    [ "$full" = "$head" ] && return 0
    [ -n "$base_sha" ] || return 1
    git -C "$top" merge-base --is-ancestor "$full" "$head" || return 1
    ! git -C "$top" merge-base --is-ancestor "$full" "$base_sha"
}

# ── доказательства DoD ──────────────────────────────────────────────────
n_issues="${#issues[@]}" n_proven=0
if [ "$n_issues" -eq 0 ]; then
    reason ISSUES-NONE "задач полосы ноль (--issue): доказательство DoD судить не о чем"
fi
for it in "${issues[@]+"${issues[@]}"}"; do
    r="${it%%#*}" n="${it##*#}"
    if [ "$r" = "$it" ] || ! [[ "$n" =~ ^[0-9]+$ ]]; then
        void ISSUE-FORM "задача «$it» не в форме <владелец/репо>#<N>"
        continue
    fi
    if ! shas="$($GH api --paginate "repos/$r/issues/$n/comments" \
            --jq '.[] | (.body // "") | capture("(^|\n)DoD-proof @(?<s>[0-9a-f]{7,40})"; "g") | .s' 2> /dev/null)"; then
        void GH-UNREADABLE "комментарии $r#$n не прочитаны"
        continue
    fi
    ok=0
    if [ -n "$head" ]; then
        while IFS= read -r s; do
            [ -n "$s" ] || continue
            if in_lane "$s"; then ok=1; break; fi
        done <<< "$shas"
    fi
    if [ "$ok" = 1 ]; then
        n_proven=$((n_proven + 1))
    elif [ -z "$shas" ]; then
        reason DOD-PROOF-MISSING "$r#$n: комментария «DoD-proof @<sha>» нет"
    else
        reason DOD-PROOF-MISSING "$r#$n: DoD-proof есть, но ни один sha не голова полосы и не коммит база..голова ($(printf '%s' "$shas" | tr '\n' ' '))"
    fi
done

# ── хук отправки на голове ─────────────────────────────────────────────
url="$(git -C "$top" remote get-url origin 2> /dev/null || true)"
repo="${url##*/}"; repo="${repo%.git}"
case "$repo" in
    kacho-workspace) green_re='^pre-push: локальные проверки воркспейса зелёные' ;;
    kacho) green_re='^== pre-push: локальные проверки зелёные \(не выполненных нет\)' ;;
    kaname) green_re='^pre-push: зелёное — исполнено [0-9]+ из [0-9]+ групп, отказов 0\.' ;;
    corelib) green_re='^pre-push \(corelib\): исполнено ([0-9]+) из \1, красных 0' ;;
    *) green_re="" ;;
esac
hook="не судился"
if [ -z "$hook_log" ] || ! [ -f "$hook_log" ]; then
    reason HOOK-LOG-MISSING "журнала отправки нет (--hook-log ${hook_log:-не передан})"
else
    logged_head="$(sed -n 's/^lane-push head=\([0-9a-f]\{40\}\)$/\1/p' "$hook_log" | tail -1)"
    logged_rc="$(sed -n 's/^lane-push rc=\([0-9]\{1,3\}\)$/\1/p' "$hook_log" | tail -1)"
    if [ -z "$logged_head" ] || { [ -n "$head" ] && [ "$logged_head" != "$head" ]; }; then
        lh="${logged_head:0:12}"
        reason HOOK-HEAD-MISMATCH "журнал о голове ${lh:-«нет строки lane-push head=»}, голова ${head:0:12}"
    fi
    if [ "$logged_rc" != 0 ]; then
        reason HOOK-RC "отправка вышла кодом ${logged_rc:-нет строки lane-push rc=}"
    fi
    if grep -qE '_SKIP_PREPUSH=1 —|проверки пропущены|пропущен по [A-Z_]*SKIP|объявлена черновиком|уезжают только черновики' "$hook_log"; then
        reason HOOK-BYPASSED "хук пропущен обходом или черновиком"
    fi
    if [ -z "$green_re" ]; then
        void HOOK-KIND-UNKNOWN "строки зелёного итога для репозитория «${repo:-?}» в словаре нет"
    elif ! grep -qE -- "$green_re" "$hook_log"; then
        reason HOOK-NOT-GREEN "нет строки зелёного итога хука $repo"
    else
        hook="зелёный"
    fi
fi

echo "lane-precheck: копия $top; ветка $branch @${head:0:12}; origin @${remote_head:0:12}; база ${base_sha:0:12}; задач $n_issues, с доказательством $n_proven; хук $hook; причин ${#reasons[@]}, не судимо ${#voids[@]}"
for x in "${reasons[@]+"${reasons[@]}"}"; do echo "REASON $x"; done
for x in "${voids[@]+"${voids[@]}"}"; do echo "VOID $x"; done
[ "${#reasons[@]}" -eq 0 ] || exit 1
[ "${#voids[@]}" -eq 0 ] || exit 2
exit 0
