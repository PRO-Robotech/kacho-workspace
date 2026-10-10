#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# census.sh — перепись СЛЕДОВ прогона: что лежит до и что лежит после.
#
# Предмет — предикат приёмки нормы «тест не оставляет мусора» (testing.md,
# §«Прогон не оставляет следов», решение владельца 2026-10-07): «после прогона
# следов 0». Без переписи «я всё убрал» — слова автора, а не замер: уборка,
# не исполнившаяся на падении, выглядит ровно так же, как исполнившаяся.
#
#   census.sh snapshot            > before.txt   # до прогона
#   <прогон>
#   census.sh snapshot            > after.txt    # после
#   census.sh compare before.txt after.txt [--keep <префикс пути>]…
#
# Инструмент ТОЛЬКО ЧИТАЕТ: ничего не снимает и не создаёт, кроме своего вывода.
#
# ОСИ. Каждая печатается либо осмотренной (`#axis <ось> <число>`), либо
# неосмотренной (`#void <ось> <причина>`) — «ноль следов» отличим от «ноль
# прочитанного»: нет инструмента, нет доступа — это не чисто.
#   tmpdir            — верхний уровень `${TMPDIR:-/tmp}`, только записи этого uid;
#   ws-tmp            — верхний уровень `tmp/` воркспейса (копии полос);
#   worktree          — зарегистрированные worktree воркспейса и репозиториев
#                       из RESIDUE_REPOS (через двоеточие);
#   docker-container, docker-volume, docker-network — `docker … ls`;
#   kind              — `kind get clusters`;
#   kube-ns, kube-pv, kube-lb — ТОЛЬКО при RESIDUE_KUBE=1, текущий контекст
#                       kubectl (пространства имён, тома, сервисы LoadBalancer).
#                       Имя контекста и адрес кластера не печатаются: репозиторий
#                       публичный, а вывод переписи уходит в комментарии задач.
# RESIDUE_AXES=<ось,ось> сужает перепись (инъекция гоняет только tmpdir).
#
# КОДЫ compare: 0 — новых следов нет; 1 — есть, каждый назван осью и именем;
# 2 — не выполнилось: снимок не читается либо ни одной оси, осмотренной в ОБОИХ
# снимках, — сравнивать нечего, и это не зелёный.
#
# ИСКЛЮЧЕНИЕ — только артефакт отчёта для разбора красного: `--keep <префикс>`
# снимает с учёта записи путевых осей, начинающиеся с префикса, и печатает их
# отдельной строкой «оставлено как отчёт». Время жизни такого каталога называет
# норма, а не этот инструмент.
#
# ОБЩИЕ ОСИ (docker, kind, кластер, ws-tmp) делятся с соседними полосами: новый
# след там может быть чужим. Инструмент печатает имя — принадлежность читает
# человек по имени; своя ось полосы — её собственный TMPDIR.
set -uo pipefail
# Порядок и равенство строк — побайтовые. В локали со сверткой (ru_RU, en_US)
# `sort -u` склеивает «ciw-1» и «ciw1» как равные, а `comm` отказывается от
# такого порядка: перепись теряет одну запись из пары и называет следом то, что
# лежало и до прогона (измерено 2026-10-07 на этой машине, ru_RU.UTF-8).
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Воркспейс — КАНОНИЧЕСКИЙ клон, а не копия, из которой запущен инструмент: копии
# полос лежат в `tmp/` канонического, и перепись из копии иначе смотрела бы в её
# собственный пустой `tmp/`. Выводится из общего каталога git; RESIDUE_WS перекрывает.
WS="${RESIDUE_WS:-}"
if [ -z "$WS" ]; then
    _common="$(git -C "$SELF_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
        && WS="$(dirname "$_common")" \
        || WS="$(cd "$SELF_DIR/../.." && pwd)"
fi

want_axis() {
    [ -z "${RESIDUE_AXES:-}" ] && return 0
    case ",$RESIDUE_AXES," in *",$1,"*) return 0 ;; esac
    return 1
}

# emit ОСЬ КОМАНДА… — исполнить читателя оси; отказ читателя — VOID оси.
emit() {
    local axis="$1" out rc
    shift
    want_axis "$axis" || return 0
    out="$("$@" 2>/dev/null)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        printf '#void\t%s\tчитатель оси вернул код %d\n' "$axis" "$rc"
        return 0
    fi
    local n=0 line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        printf '%s\t%s\n' "$axis" "$line"
        n=$((n + 1))
    done <<<"$out"
    printf '#axis\t%s\t%d\n' "$axis" "$n"
}

void() {
    want_axis "$1" || return 0
    printf '#void\t%s\t%s\n' "$1" "$2"
}

read_tmpdir() {
    local t="${TMPDIR:-/tmp}"
    [ -d "$t" ] || return 3
    find "$t" -mindepth 1 -maxdepth 1 -user "$(id -u)" -printf "$t/%f\n" | sort
}

read_ws_tmp() {
    find "$WS/tmp" -mindepth 1 -maxdepth 1 -printf "$WS/tmp/%f\n" | sort
}

read_worktrees() {
    local r
    local -a repos=("$WS")
    if [ -n "${RESIDUE_REPOS:-}" ]; then
        IFS=: read -r -a extra <<<"$RESIDUE_REPOS"
        repos+=("${extra[@]}")
    fi
    for r in "${repos[@]}"; do
        git -C "$r" worktree list --porcelain | sed -n 's/^worktree //p' || return 1
    done | sort -u
}

has() { command -v "$1" >/dev/null 2>&1; }

snapshot() {
    if [ -d "${TMPDIR:-/tmp}" ]; then emit tmpdir read_tmpdir
    else void tmpdir "каталога ${TMPDIR:-/tmp} нет"; fi

    if [ -d "$WS/tmp" ]; then emit ws-tmp read_ws_tmp
    else void ws-tmp "каталога tmp/ в воркспейсе нет"; fi

    if has git; then emit worktree read_worktrees
    else void worktree "git нет в PATH"; fi

    if has docker && docker info >/dev/null 2>&1; then
        emit docker-container docker ps -a --format '{{.Names}} {{.Image}}'
        emit docker-volume docker volume ls -q
        emit docker-network docker network ls --format '{{.Name}}'
    else
        void docker-container "docker недоступен"
        void docker-volume "docker недоступен"
        void docker-network "docker недоступен"
    fi

    if has kind; then emit kind kind get clusters
    else void kind "kind нет в PATH"; fi

    if [ "${RESIDUE_KUBE:-0}" = "1" ] && has kubectl; then
        emit kube-ns kubectl get ns -o name
        emit kube-pv kubectl get pv -o name
        emit kube-lb kubectl get svc -A -o \
            'jsonpath={range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'
    else
        void kube-ns "RESIDUE_KUBE=1 не задан либо kubectl нет"
        void kube-pv "RESIDUE_KUBE=1 не задан либо kubectl нет"
        void kube-lb "RESIDUE_KUBE=1 не задан либо kubectl нет"
    fi
}

compare() {
    local before="$1" after="$2"
    shift 2
    local -a keep=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --keep) [ $# -ge 2 ] || { echo "compare: --keep без префикса" >&2; return 2; }
                    keep+=("$2"); shift 2 ;;
            *) echo "compare: неизвестный аргумент «$1»" >&2; return 2 ;;
        esac
    done
    local f
    for f in "$before" "$after"; do
        [ -r "$f" ] || { echo "compare: снимок «$f» не читается — сравнения не было"; return 2; }
    done

    local -a axes=()
    local a
    mapfile -t axes < <(comm -12 \
        <(awk -F'\t' '$1=="#axis"{print $2}' "$before" | sort -u) \
        <(awk -F'\t' '$1=="#axis"{print $2}' "$after" | sort -u))
    # Ось, осмотренная лишь в одном снимке, и ось VOID — не сравнены: печатаются,
    # чтобы «следов 0» не читалось шире осмотренного.
    while IFS= read -r a; do
        [ -n "$a" ] && printf 'не осмотрено: %s\n' "$a"
    done < <(
        awk -F'\t' '$1=="#void"{print $2" ("$3")"}' "$before" "$after" | sort -u
        awk -F'\t' '$1=="#axis"{print $2}' "$before" "$after" | sort | uniq -u \
            | sed 's/$/ (осмотрена лишь в одном снимке)/'
    )

    if [ "${#axes[@]}" -eq 0 ]; then
        echo "ОТКАЗ — ни одной оси, осмотренной в обоих снимках: сравнивать нечего, это не «следов 0»"
        return 2
    fi

    local found=0 kept=0 item p k
    for a in "${axes[@]}"; do
        while IFS= read -r item; do
            [ -n "$item" ] || continue
            k=0
            for p in "${keep[@]}"; do
                case "$item" in "$p"*) k=1 ;; esac
            done
            if [ "$k" -eq 1 ]; then
                printf 'оставлено как отчёт: %s %s\n' "$a" "$item"
                kept=$((kept + 1))
            else
                printf 'СЛЕД: %s %s\n' "$a" "$item"
                found=$((found + 1))
            fi
        done < <(comm -13 \
            <(awk -F'\t' -v a="$a" '$1==a{print $2}' "$before" | sort -u) \
            <(awk -F'\t' -v a="$a" '$1==a{print $2}' "$after" | sort -u))
    done
    printf 'перепись: осей сравнено %d · новых следов %d · оставлено как отчёт %d\n' \
        "${#axes[@]}" "$found" "$kept"
    [ "$found" -eq 0 ] || return 1
    return 0
}

case "${1:-}" in
    snapshot) snapshot ;;
    compare)  shift; [ $# -ge 2 ] || { echo "usage: census.sh compare BEFORE AFTER [--keep PREFIX]…" >&2; exit 2; }
              compare "$@"; exit $? ;;
    *) echo "usage: census.sh snapshot | compare BEFORE AFTER [--keep PREFIX]…" >&2; exit 2 ;;
esac
