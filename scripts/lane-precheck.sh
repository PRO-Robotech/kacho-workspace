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
#        lane-precheck.sh --premise <файл предусловий>
#
# РЕЖИМ ПРЕДУСЛОВИЙ (ws#1071, база диспетчера §3) — ДО раздачи задания: задание с
# ложным предусловием не уходит. Строка файла — одно предусловие закрытого словаря
# (`#` и пустые строки — не предусловия):
#   task <владелец/репо>#<N>                      номер задачи полосы: N — ^[0-9]+$ (иначе ложно:
#                                                 урок 2026-10-16 — в шаблон подставился текст
#                                                 отказа, полоса ушла без N), задача есть и не PR;
#   pr <владелец/репо>#<N> <MERGED|OPEN|CLOSED>   состояние PR (GET pulls/<N>);
#   branch <владелец/репо> <ветка>                ветка на origin (GET branches/<ветка>);
#   head <владелец/репо> <ветка> <sha40>          голова ветки на origin равна sha целиком (GET branches/
#                                                 <ветка> .commit.sha; ws#1191: полоса стенда ушла
#                                                 раньше, чем голова ветки доехала до origin);
#   proof <владелец/репо>#<N>                     у задачи есть `DoD-proof @<sha>`;
#   verdict <файл записи роли> <accept|return>    `verdict.value` записи: ✅ / ⛔.
# Ложное — `REASON PREMISE-FALSE …`, код 1. Не судимо (трекер не ответил, строка вне
# словаря, файла нет) — VOID, код 2; ноль предусловий — тоже код 2: пустой файл не
# «все верны».
#
# ЧТО СУДИТ (каждый пункт — своя причина, строкой `REASON <КОД> <текст>`):
#   HEAD-NOT-ON-ORIGIN  ветки нет на origin (`git ls-remote`, а не память);
#   HEAD-DIVERGED       голова на origin ≠ голове ветки в копии: ревью судило бы
#                       не то, что отправлено;
#   BASE-NOT-ANCESTOR   база не предок головы: полоса ответвлена не от того;
#   UNCOMMITTED         в копии есть правка или новый файл вне коммита
#                       (`git status --porcelain`, неотслеживаемые — тоже);
#   MAIN-COPY           копия вне `<WS>/tmp/` (ws#923: отправка из основной копии
#                       исполняет устаревший хук);
#   GOMOD-ABOVE         над корнем копии (в любом каталоге-предке) лежит чужой
#                       `go.mod`: копия положена внутрь вложенного дерева, и
#                       тесты, ищущие корень модуля подъёмом, берут его (ws#1010:
#                       копии полос kaname под `tmp/wave7/ws-main/tmp/` приняли
#                       `ws-main/go.mod` за корень — хук отправки упал на 12 пробах
#                       по вине среды). Свой `go.mod` копии — не предмет;
#   ISSUES-NONE         задач полосы ноль: доказательство судить не о чем;
#   DOD-PROOF-MISSING   у задачи нет комментария `DoD-proof @<sha>` (форма —
#                       `CLAUDE.md`; распознаватель — общий `lib/dod_proof.jq`, тот
#                       же у merge-readiness и `cascade-census.sh --proof`),
#                       чей sha — голова полосы или коммит из база..голова:
#                       доказательство чужой или прежней ревизии — не доказательство;
#   HOOK-LOG-MISSING    журнала отправки нет;
#   HOOK-HEAD-MISMATCH  журнал отправки — не о текущей голове;
#   HOOK-RC             отправка вышла не нулём;
#   HOOK-BYPASSED       хук пропущен обходом (`*_SKIP_PREPUSH=1`) либо черновиком;
#   HOOK-NOT-GREEN      в журнале нет строки ЗЕЛЁНОГО итога хука этого
#                       репозитория (строка «без предмета» воркспейса — не зелёная);
#   STATIC-RED          отправка отказана: ПО СТРОКЕ на каждую красную единицу итога
#                       хука (ws#1110 — весь список разом, а не первый): воркспейс —
#                       блок «Красные наборы:», kacho — «   красное: …», kaname —
#                       «красные : …», corelib — «КРАСНОЕ: <имя> (код N)». kacho и
#                       kaname склеивают имена ПРОБЕЛОМ (`${fails[*]}`), а имя шага
#                       пробелы содержит: строка режется не по пробелу, а на столько
#                       имён словаря, сколько отказов в итоге хука (`отказов K` ·
#                       `красных K`), и разрез обязан быть ЕДИНСТВЕННЫМ. Словарь —
#                       заголовки шагов журнала (`== <имя>` · `── <имя>: `) и, у kacho,
#                       литералы `fails+=("…")` и `local name="…"` файла
#                       `scripts/ci-local.sh` ГОЛОВЫ (`git show <голова>:…`);
#   STATIC-REFUSAL      единиц нет — каждая строка «pre-push ОТКАЗ…» хука;
#   STATIC-UNPARSED     нет ни того, ни другого, либо строка «красное» не режется на
#                       K имён словаря однозначно: список не извлечён — не «отказов 0».
#
# ЖУРНАЛ ОТПРАВКИ — форма, которую пишет исполнитель (передача через файлы,
# `<WS>/tmp/wave-<N>/reports/<полоса>/push.log`, вне дерева копии):
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
# выведенный `scripts/lib/ws-home.sh` (worktree и клон под `tmp/` — один корень).
#
# Коды: 0 — причин ноль и всё судимое осуждено; 1 — хотя бы одна причина;
# 2 — причин ноль, но часть не судима (VOID: ветка не читается, трекер не
# ответил, хук репозитория вне словаря, DOD-LIB — распознавателя
# `lib/dod_proof.jq` нет либо ответ трекера им не разобран). Перепись печатается всегда.
# Держит `scripts/lane-precheck-inject.sh`.
set -uo pipefail

usage() {
    echo "usage: lane-precheck.sh <каталог копии> <ветка> <база> [--issue <владелец/репо>#<N>]… [--hook-log <файл>] | --premise <файл>" >&2
    exit 2
}

issues=() hook_log="" premise="" pos=()
while [ $# -gt 0 ]; do
    case "$1" in
        --issue) [ $# -ge 2 ] || usage; issues+=("$2"); shift 2 ;;
        --hook-log) [ $# -ge 2 ] || usage; hook_log="$2"; shift 2 ;;
        --premise) [ $# -ge 2 ] || usage; premise="$2"; shift 2 ;;
        -h | --help) usage ;;
        *) pos+=("$1"); shift ;;
    esac
done
GH="${LANE_PRECHECK_GH:-gh}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# dod_revs — ревизии строк-доказательств DoD из JSON комментариев на stdin (страницы
# подряд), по строке. Распознаватель — общий `lib/dod_proof.jq` (ws#1140): своя копия
# выражения здесь разошлась с merge-readiness молча. Код 2 — распознавателя нет либо
# ответ не разобран: судить нечем.
dod_revs() {
    [ -r "$HERE/lib/dod_proof.jq" ] || return 2
    jq -L "$HERE/lib" -r -s 'include "dod_proof"; add // [] | .[] | (.body // "") | dod_proof_revisions[]' 2> /dev/null || return 2
}

# ── режим предусловий ───────────────────────────────────────────────────
# ghget <путь> <jq> — GET трекера; код 0 — ответ в stdout, 3 — 404 (предмета нет), 1 — не ответил.
ghget() {
    local out err
    err="$(mktemp)"
    if out="$($GH api "$1" --jq "$2" 2> "$err")"; then rm -f "$err"; printf '%s' "$out"; return 0; fi
    if grep -q 'HTTP 404' "$err"; then rm -f "$err"; return 3; fi
    rm -f "$err"; return 1
}
if [ -n "$premise" ]; then
    [ "${#pos[@]}" -eq 0 ] || usage
    [ -r "$premise" ] || { echo "lane-precheck: файла предусловий $premise нет; вердикта нет" >&2; exit 2; }
    reasons=() voids=() n=0
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in '' | '#'*) continue ;; esac
        n=$((n + 1))
        read -r kind a b _ <<< "$line"
        case "$kind" in
            task)
                r="${line#task }"; r="${r%%#*}" num="${line#*#}"
                if [ "$r" = "$line" ] || [ "$num" = "$line" ] || ! [[ "$r" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then voids+=("PREMISE-FORM $line"); continue; fi
                if ! [[ "$num" =~ ^[0-9]+$ ]]; then reasons+=("PREMISE-FALSE $line: номер задачи «$num» не ^[0-9]+$ — полоса не раздаётся"); continue; fi
                got="$(ghget "repos/$r/issues/$num" 'if .pull_request then "PR" else "ISSUE" end')"; rc=$?
                if [ "$rc" = 3 ]; then reasons+=("PREMISE-FALSE $line: задачи нет")
                elif [ "$rc" != 0 ]; then voids+=("GH-UNREADABLE $line")
                elif [ "$got" != ISSUE ]; then reasons+=("PREMISE-FALSE $line: это PR, а не задача"); fi ;;
            pr)
                r="${a%%#*}" num="${a##*#}"
                if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$r" = "$a" ] || ! [[ "$b" =~ ^(MERGED|OPEN|CLOSED)$ ]]; then voids+=("PREMISE-FORM $line"); continue; fi
                got="$(ghget "repos/$r/pulls/$num" 'if .merged then "MERGED" elif .state == "open" then "OPEN" else "CLOSED" end')"; rc=$?
                if [ "$rc" = 3 ]; then reasons+=("PREMISE-FALSE $line: PR нет")
                elif [ "$rc" != 0 ]; then voids+=("GH-UNREADABLE $line")
                elif [ "$got" != "$b" ]; then reasons+=("PREMISE-FALSE $line: состояние $got"); fi ;;
            branch)
                if [ -z "$a" ] || ! [[ "$b" =~ ^[A-Za-z0-9._/-]+$ ]]; then voids+=("PREMISE-FORM $line"); continue; fi
                ghget "repos/$a/branches/$b" .name > /dev/null; rc=$?
                if [ "$rc" = 3 ]; then reasons+=("PREMISE-FALSE $line: ветки на origin нет")
                elif [ "$rc" != 0 ]; then voids+=("GH-UNREADABLE $line"); fi ;;
            head)
                read -r _ _ _ want _ <<< "$line"
                # Ветка — знаки пути GET (`#`, `?`, пробел обрезали бы путь до чужой ветки).
                if [ -z "$a" ] || ! [[ "$b" =~ ^[A-Za-z0-9._/-]+$ ]] || ! [[ "${want:-}" =~ ^[0-9a-f]{40}$ ]]; then voids+=("PREMISE-FORM $line"); continue; fi
                got="$(ghget "repos/$a/branches/$b" .commit.sha)"; rc=$?
                if [ "$rc" = 3 ]; then reasons+=("PREMISE-FALSE $line: ветки $b на origin нет — ожидалась голова $want")
                elif [ "$rc" != 0 ]; then voids+=("GH-UNREADABLE $line")
                elif [ "$got" != "$want" ]; then reasons+=("PREMISE-FALSE $line: голова $b на origin ${got:-пуста}, ожидалась $want"); fi ;;
            proof)
                r="${a%%#*}" num="${a##*#}"
                if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$r" = "$a" ]; then voids+=("PREMISE-FORM $line"); continue; fi
                got="$(ghget "repos/$r/issues/$num/comments" '.')"; rc=$?
                if [ "$rc" != 0 ]; then voids+=("GH-UNREADABLE $line"); continue; fi
                if ! got="$(printf '%s' "$got" | dod_revs)"; then voids+=("DOD-LIB $line: распознаватель $HERE/lib/dod_proof.jq не судил"); continue; fi
                if [ -z "$got" ]; then reasons+=("PREMISE-FALSE $line: комментария «DoD-proof @<sha>» нет"); fi ;;
            verdict)
                if ! [ -r "$a" ] || ! [[ "$b" =~ ^(accept|return)$ ]]; then voids+=("PREMISE-FORM $line"); continue; fi
                v="$(sed -n '/^verdict:/,/^[^ ]/{s/^  value: *//p}' "$a" | head -1)"
                case "$v" in *✅*) got="accept" ;; *⛔*) got="return" ;; *) got="" ;; esac
                if [ -z "$got" ]; then voids+=("VERDICT-UNREADABLE $line")
                elif [ "$got" != "$b" ]; then reasons+=("PREMISE-FALSE $line: вердикт $got"); fi ;;
            *) voids+=("PREMISE-FORM $line") ;;
        esac
    done < "$premise"
    echo "lane-precheck --premise: файл $premise; предусловий $n; ложных ${#reasons[@]}, не судимо ${#voids[@]}"
    for x in "${reasons[@]+"${reasons[@]}"}"; do echo "REASON $x"; done
    for x in "${voids[@]+"${voids[@]}"}"; do echo "VOID $x"; done
    [ "${#reasons[@]}" -eq 0 ] || exit 1
    [ "${#voids[@]}" -eq 0 ] && [ "$n" -gt 0 ] || exit 2
    exit 0
fi

[ "${#pos[@]}" -eq 3 ] || usage
dir="${pos[0]}" branch="${pos[1]}" base="${pos[2]}"

reasons=() voids=()
reason() { reasons+=("$1 $2"); }
void() { voids+=("$1 $2"); }

if [ -n "${LANE_PRECHECK_WS:-}" ]; then
    WS="$(cd "$LANE_PRECHECK_WS" 2> /dev/null && pwd -P)" || WS="$LANE_PRECHECK_WS"
else
    # shellcheck source=lib/ws-home.sh
    . "$HERE/lib/ws-home.sh"
    WS="$(ws_home "$HERE")" || WS=""
fi

top="$(git -C "$dir" rev-parse --show-toplevel 2> /dev/null)" || top=""
if [ -z "$top" ]; then
    echo "lane-precheck: копия $dir — не рабочая копия git; вердикта нет" >&2
    exit 2
fi
top="$(cd "$top" && pwd -P)"

head="$(git -C "$top" rev-parse --verify --quiet "refs/heads/$branch^{commit}" 2> /dev/null)" || head=""
[ -n "$head" ] || void BRANCH-UNKNOWN "ветки $branch в копии нет"

# ── незакоммиченное в копии ─────────────────────────────────────────────
# Правка или новый файл, не попавшие в коммит, ревью не увидит, а исполнитель
# сочтёт сданными: класс «незакоммичено» замера 2026-10-06. Неотслеживаемые
# файлы считаются тоже — новый файл, забытый в `git add`, и есть этот класс;
# игнорируемые (`.gitignore`) не считаются.
if ! dirty="$(git -C "$top" status --porcelain --untracked-files=all 2> /dev/null)"; then
    void STATUS-UNREADABLE "состояние копии $top не читается"
elif [ -n "$dirty" ]; then
    n_dirty="$(printf '%s\n' "$dirty" | grep -c .)"
    reason UNCOMMITTED "в копии $n_dirty путей вне коммита: $(printf '%s\n' "$dirty" | head -5 | tr '\n' ';' | sed 's/;$//')"
fi

# ── копия ─────────────────────────────────────────────────────────────────
if [ -z "$WS" ]; then
    void WS-UNKNOWN "корень воркспейса не выведен — дом копий судить не с чем"
else
    case "$top/" in
        "$WS/tmp/"?*) ;;
        *) reason MAIN-COPY "копия $top вне $WS/tmp/ (ws#923)" ;;
    esac
fi

# ── чужой go.mod над копией ────────────────────────────────────────────
# Подъём от родителя корня копии до `/`: каждый найденный `go.mod` — находка.
# Свой `go.mod` копии (в её корне) не судится — это её модуль.
n_up=0 above=()
a="$(dirname "$top")"
while :; do
    n_up=$((n_up + 1))
    [ -f "$a/go.mod" ] && above+=("$a/go.mod")
    [ "$a" = / ] && break
    a="$(dirname "$a")"
done
if [ "${#above[@]}" -gt 0 ]; then
    reason GOMOD-ABOVE "над копией $top чужой go.mod: ${above[*]} — копия внутри вложенного дерева; место копий полос — <корень воркспейса>/tmp/wave-<N>/ (ws#1010)"
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
    if ! raw="$($GH api --paginate "repos/$r/issues/$n/comments" 2> /dev/null)"; then
        void GH-UNREADABLE "комментарии $r#$n не прочитаны"
        continue
    fi
    if ! shas="$(printf '%s' "$raw" | dod_revs)"; then
        void DOD-LIB "$r#$n: распознаватель $HERE/lib/dod_proof.jq не судил"
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
    # Статика — ВЕСЬ список отказов хука разом (ws#1110, владелец 2026-10-16: перепись,
    # потом массово): по строке STATIC-RED на красную единицу из формы итога хука
    # репозитория; единиц нет — строки отказа самого хука (STATIC-REFUSAL); нет и их —
    # STATIC-UNPARSED: список не извлечён, это не «отказов 0».
    if [ "$logged_rc" != 0 ] && [ "$hook" != "зелёный" ]; then
        mapfile -t units < <(awk -v r="$repo" '
            r == "kacho-workspace" && /^ОТКАЗ: отправка остановлена\. Красные наборы:$/ { inl = 1; next }
            inl && /^  [^ ]/ { sub(/^  /, ""); print; next }
            { inl = 0 }
            r == "corelib" && /^КРАСНОЕ: .* \(код [0-9]+\)$/ { sub(/^КРАСНОЕ: /, ""); sub(/ \(код [0-9]+\)$/, ""); print }
        ' "$hook_log" | awk '!seen[$0]++')
        n_static=0
        for u in "${units[@]+"${units[@]}"}"; do reason STATIC-RED "$repo: $u"; n_static=$((n_static + 1)); done
        # kacho и kaname: строка имён, склеенных пробелом, — разрезом по словарю (шапка).
        if { [ "$repo" = kacho ] || [ "$repo" = kaname ]; } && command -v python3 > /dev/null 2>&1; then
            vocab_src="$(mktemp)" || vocab_src=/dev/null
            [ "$repo" != kacho ] || [ -z "$head" ] || git -C "$top" show "$head:scripts/ci-local.sh" > "$vocab_src" 2> /dev/null || : > "$vocab_src"
            while IFS=$'\t' read -r kind u; do
                case "$kind" in
                    RED) reason STATIC-RED "$repo: $u" ;;
                    UNPARSED) reason STATIC-UNPARSED "$repo: $u" ;;
                    *) continue ;;
                esac
                n_static=$((n_static + 1))
            done < <(python3 - "$repo" "$hook_log" "$vocab_src" <<'PY'
import re, sys
repo, log, src = sys.argv[1:4]
lines = open(log, encoding='utf-8', errors='replace').read().splitlines()
if repo == 'kacho':
    hdr, red = re.compile(r'^== (.+?)\s*$'), re.compile(r'^   красное: (.*)$')
    tot = re.compile(r'^== итог: проверок исполнено \d+, отказов (\d+), ')
    s = open(src, encoding='utf-8', errors='replace').read()
    vocab = set(re.findall(r'fails\+=\("([^"$`\\]+)"\)', s)) | set(re.findall(r'local name="([^"$`\\]+)"', s))
else:
    hdr, red = re.compile(r'^── (.+?): '), re.compile(r'^красные +: (.*)$')
    tot = re.compile(r'^групп ИСПОЛНЕНО +: \d+ +\(зелёных \d+ · красных (\d+)\)')
    vocab = set()
for l in lines:
    m = hdr.match(l)
    if m and not re.match(r'(итог:|pre-push)', m.group(1)):
        vocab.add(m.group(1))
k, seen = None, set()
for l in lines:
    m = tot.match(l)
    if m:
        k = int(m.group(1))
        continue
    m = red.match(l)
    if not m:
        continue
    toks = m.group(1).strip().split(' ')
    n = len(toks)
    # ways[i][c] — число разрезов toks[i:] ровно на c имён словаря (до 2: важна лишь единственность)
    ways = [[0] * (n + 2) for _ in range(n + 1)]
    ways[n][0] = 1
    for i in range(n - 1, -1, -1):
        for j in range(i + 1, n + 1):
            if ' '.join(toks[i:j]) in vocab:
                for c in range(1, n + 1):
                    ways[i][c] = min(2, ways[i][c] + ways[j][c - 1])
    if k is None or k > n or ways[0][k] != 1:
        print('UNPARSED\tстрока «%s» не режется однозначно на %s имён словаря хука (разрезов %s; имён в словаре %d)'
              % (l.strip(), 'K=?' if k is None else k, '?' if k is None or k > n else ways[0][k], len(vocab)))
        continue
    i, c = 0, k
    while c:
        for j in range(i + 1, n + 1):
            u = ' '.join(toks[i:j])
            if u in vocab and ways[j][c - 1]:
                break
        if u not in seen:
            seen.add(u)
            print('RED\t' + u)
        i, c = j, c - 1
PY
)
            [ "$vocab_src" = /dev/null ] || rm -f "$vocab_src"
        fi
        if [ "$n_static" -eq 0 ]; then
            while IFS= read -r l; do reason STATIC-REFUSAL "$l"; n_static=$((n_static + 1)); done \
                < <(grep -E '^pre-push:? ОТКАЗ' "$hook_log" | awk '!seen[$0]++')
        fi
        [ "$n_static" -gt 0 ] || reason STATIC-UNPARSED "хук вышел кодом ${logged_rc:-?}, а список отказов из журнала не извлечён — читать журнал целиком, не «отказов 0»"
        hook="красный, статических отказов $n_static"
    fi
fi

echo "lane-precheck: копия $top; предков осмотрено на go.mod $n_up; ветка $branch @${head:0:12}; origin @${remote_head:0:12}; база ${base_sha:0:12}; задач $n_issues, с доказательством $n_proven; хук $hook; причин ${#reasons[@]}, не судимо ${#voids[@]}"
for x in "${reasons[@]+"${reasons[@]}"}"; do echo "REASON $x"; done
for x in "${voids[@]+"${voids[@]}"}"; do echo "VOID $x"; done
[ "${#reasons[@]}" -eq 0 ] || exit 1
[ "${#voids[@]}" -eq 0 ] || exit 2
exit 0
