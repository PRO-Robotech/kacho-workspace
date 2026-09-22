#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# git-rule.sh — распознаватели правила git (решение владельца 2026-09-22;
# `.claude/rules/git-issues.md` §«Git / коммиты» и §«Дерево задач, ветки,
# слияния»): первая строка `#<N> `, подпись корневого gitconfig, запрет
# атрибуции, момент вступления T0.
#
# ОДИН ИСТОЧНИК НА ЧЕТЫРЁХ ПОТРЕБИТЕЛЕЙ: `commit-msg`, `pre-push`, перепись
# диапазона перед вливанием и проверка тела PR. Две копии распознавателя
# расходятся молча: форма, добавленная в одну, во второй остаётся законной.
#
# ИМЯ С ТОЧКОЙ — НЕСУЩЕЕ: `install.sh` хуком считает только файл без точки, и
# этот в `.git/hooks` не попадает.
#
# T0 ВЫВОДИТСЯ, А НЕ ВЫПИСЫВАЕТСЯ: это время автора коммита, который завёл
# `scripts/hooks/commit-msg`. Литерал пришлось бы вписать до коммита, момент
# которого он называет. Коммиты с датой автора раньше T0 — история: подпись
# `pointpu@prorobotech.ru` и заголовок без номера у них законны (п.9 правила).
#
# Режимы, когда файл исполняется, а не подключается:
#   scan            — текст со stdin; строки атрибуции · 0 чисто · 1 найдено
#   range <a>..<b>  — сообщения ВСЕХ коммитов диапазона, включая историю до T0
#                     (п.9: ветка с атрибуцией в main не идёт) · 0 · 1 · 2
#   pr <репо> <N>   — заголовок, тело, комментарии и отзывы PR · 0 · 1 · 2
#   t0              — T0 эпохой · 0 · 2, если коммита правила в истории нет

# Атрибуция ассистента: трейлер соавторства с его именем, трейлер сеанса,
# подпись «сгенерировано» и ссылка на сеанс. Соавтор-человек — не атрибуция:
# под запрет он не подпадает (законный близнец в check-17).
GR_ATTR_RE='^[[:space:]]*co-authored-by:.*(claude|anthropic)|^[[:space:]]*claude-session:|generated with \[?claude code|claude\.ai/code'

# Первая строка: номер задачи, пробел, текст. Номер без текста — не заголовок.
GR_SUBJECT_RE='^#([0-9]+) [^[:space:]]'

GR_ZERO='0000000000000000000000000000000000000000'

# gr_root_ident — «имя <адрес>» из корневого gitconfig; код 1, если не задан.
gr_root_ident() {
    local n e
    n="$(git config --global --get user.name 2>/dev/null || true)"
    e="$(git config --global --get user.email 2>/dev/null || true)"
    [ -n "$n" ] && [ -n "$e" ] || return 1
    printf '%s <%s>' "$n" "$e"
}

# gr_local_overrides — переопределения подписи в настройках КОПИИ (по строке).
# Значение не важно: переопределение, совпавшее с корневым сегодня, разойдётся с
# ним в день смены корневого, и никто этого не увидит.
gr_local_overrides() {
    local scope k v
    for scope in --local --worktree; do
        for k in user.name user.email; do
            v="$(git config "$scope" --get "$k" 2>/dev/null || true)"
            [ -n "$v" ] && printf 'git config %s %s = %s\n' "$scope" "$k" "$v"
        done
    done
    return 0
}

# gr_t0 [ревизия] — T0 эпохой либо пусто. `tail`, а не `head`: `git log` пишет
# новое первым, а `head` под pipefail оборвал бы производителя сигналом.
gr_t0() {
    git log --diff-filter=A --format=%at "${1:-HEAD}" -- scripts/hooks/commit-msg 2>/dev/null | tail -1
}

# gr_attr_hits — строки атрибуции во входе (stdin), с номерами строк.
gr_attr_hits() {
    grep -n -i -E -- "$GR_ATTR_RE" || true
}

# gr_ident_epoch <ident> — эпоха из «имя <адрес> 1790000000 +0300».
gr_ident_epoch() {
    local x="${1% *}"
    printf '%s' "${x##* }"
}

# gr_ident_who <ident> — «имя <адрес>» без даты.
gr_ident_who() {
    local x="${1% *}"
    printf '%s' "${x% *}"
}

# gr_judge_push — судит строки pre-push со stdin («лок.ссылка лок.sha уд.ссылка
# уд.sha»). Печатает находки и перепись в stderr; код 1 при находке.
#
# Новые коммиты — достижимые из отправляемого и НЕ достижимые ни из прежней
# головы, ни из любой ссылки удалённых. Одного «прежняя..новая» мало: слияние
# `main` в ветку втянуло бы в диапазон коммиты ствола, в том числе серверные
# слияния с коммиттером хостинга, и страж обвинил бы ветку в чужой подписи.
gr_judge_push() {
    local root t0 line lsha rref rsha name refs=0 newb=0 skipped=0
    local commits=0 legacy=0 found=0 c meta at who cwho subj
    local -a range
    if ! root="$(gr_root_ident)"; then
        echo "pre-push: ОТКАЗ — корневая подпись не задана (git config --global user.name / user.email): сверять не с чем" >&2
        return 1
    fi
    t0="$(gr_t0 HEAD)"
    if [ -z "$t0" ]; then
        echo "pre-push: T0 не выведен (коммита, заведшего scripts/hooks/commit-msg, в истории HEAD нет) — судятся ВСЕ новые коммиты" >&2
        t0=0
    fi
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        read -r _ lsha rref rsha <<<"$line"
        refs=$((refs + 1))
        if [ "$lsha" = "$GR_ZERO" ]; then skipped=$((skipped + 1)); continue; fi
        case "$rref" in refs/heads/*) ;; *) skipped=$((skipped + 1)); continue ;; esac
        name="${rref#refs/heads/}"
        if [ "$rsha" = "$GR_ZERO" ]; then
            newb=$((newb + 1))
            if [ "$name" != main ] && ! [[ "$name" =~ ^[0-9]+$ ]]; then
                echo "pre-push: ОТКАЗ — новая ветка «$name» не номер задачи: имя ветки — номер задачи своего репозитория (\`^[0-9]+\$\`)" >&2
                found=$((found + 1))
            fi
            mapfile -t range < <(git rev-list "$lsha" --not --remotes 2>/dev/null)
        elif git cat-file -e "$rsha^{commit}" 2>/dev/null; then
            mapfile -t range < <(git rev-list "$lsha" --not "$rsha" --remotes 2>/dev/null)
        else
            mapfile -t range < <(git rev-list "$lsha" --not --remotes 2>/dev/null)
        fi
        for c in ${range[@]+"${range[@]}"}; do
            commits=$((commits + 1))
            meta="$(git log -1 --format='%at%x09%an <%ae>%x09%cn <%ce>%x09%s' "$c")"
            IFS=$'\t' read -r at who cwho subj <<<"$meta"
            if [ "$at" -lt "$t0" ]; then legacy=$((legacy + 1)); continue; fi
            if ! [[ "$subj" =~ $GR_SUBJECT_RE ]]; then
                echo "pre-push: ОТКАЗ — ${c:0:12} «$subj»: первая строка не начинается с «#<N> »" >&2
                found=$((found + 1))
            fi
            if [ -n "$(git log -1 --format=%B "$c" | gr_attr_hits)" ]; then
                echo "pre-push: ОТКАЗ — ${c:0:12}: в сообщении атрибуция ассистента (строки: $(git log -1 --format=%B "$c" | gr_attr_hits | cut -d: -f1 | paste -sd, -))" >&2
                found=$((found + 1))
            fi
            if [ "$who" != "$root" ] || [ "$cwho" != "$root" ]; then
                echo "pre-push: ОТКАЗ — ${c:0:12}: подпись «$who» / «$cwho», корневая — «$root»" >&2
                found=$((found + 1))
            fi
        done
    done
    echo "pre-push: правило git — ссылок $refs (новых веток $newb, не судимых $skipped), коммитов осмотрено $commits, из них история до T0 $legacy; находок $found" >&2
    [ "$found" -eq 0 ]
}

# ── исполнение режимом ─────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -uo pipefail
    mode="${1:-}"
    case "$mode" in
    scan)
        hits="$(gr_attr_hits)"
        [ -z "$hits" ] && { echo "git-rule scan: атрибуции 0"; exit 0; }
        printf 'git-rule scan: атрибуция —\n%s\n' "$hits"
        exit 1
        ;;
    range)
        [ -n "${2:-}" ] || { echo "использование: git-rule.sh range <база>..<голова>" >&2; exit 2; }
        git rev-list "$2" >/dev/null 2>&1 || { echo "git-rule range: диапазон «$2» не разрешается" >&2; exit 2; }
        mapfile -t cs < <(git rev-list "$2")
        bad=0
        for c in ${cs[@]+"${cs[@]}"}; do
            if [ -n "$(git log -1 --format=%B "$c" | gr_attr_hits)" ]; then
                echo "  ${c:0:12} $(git log -1 --format=%s "$c")"
                bad=$((bad + 1))
            fi
        done
        echo "git-rule range: коммитов осмотрено ${#cs[@]}, с атрибуцией $bad"
        [ "$bad" -eq 0 ] && exit 0
        exit 1
        ;;
    pr)
        [ -n "${2:-}" ] && [ -n "${3:-}" ] || { echo "использование: git-rule.sh pr <владелец/репо> <N>" >&2; exit 2; }
        text="$(gh pr view "$3" -R "$2" --json title,body,comments,reviews \
            --jq '.title, .body, (.comments[].body), (.reviews[].body)' 2>/dev/null)" || {
            echo "git-rule pr: PR $2#$3 не прочитан — вердикта нет" >&2; exit 2; }
        hits="$(printf '%s\n' "$text" | gr_attr_hits)"
        [ -z "$hits" ] && { echo "git-rule pr: $2#$3 — строк осмотрено $(printf '%s\n' "$text" | wc -l), атрибуции 0"; exit 0; }
        printf 'git-rule pr: %s#%s — атрибуция:\n%s\n' "$2" "$3" "$hits"
        exit 1
        ;;
    t0)
        t="$(gr_t0 HEAD)"
        [ -n "$t" ] && { echo "$t"; exit 0; }
        echo "git-rule t0: коммита, заведшего scripts/hooks/commit-msg, в истории HEAD нет" >&2
        exit 2
        ;;
    *)
        echo "использование: git-rule.sh scan | range <a>..<b> | pr <репо> <N> | t0" >&2
        exit 2
        ;;
    esac
fi
