#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# Страж ДОБАВЛЕННЫХ ФАЙЛОВ для отправки (kacho-workspace#1189). Зовёт его
# scripts/hooks/pre-push вторым, после стража атрибуции, — до обхода
# KACHO_SKIP_PREPUSH и до пропуска черновиков. Проба —
# scripts/tooling-gate/check-25-push-refuses-binary-and-large-added-files.sh.
#
# Признак: в kacho#3284 коммит ветки нёс собранный ELF края на 39 МБ со вшитыми
# путями машины; поймало его ревью, не хук. Репозитории публичны, и файл в
# опубликованной истории не отзывается без её переписи.
#
# ПЕРЕПИСЬ — то, что уезжает: коммиты отправляемой вершины, недостижимые ни с
# одной ссылки удалённого и с прежней вершины этой ссылки, и в каждом —
# добавленные файлы (`--diff-filter=A`). Покоммитно, а не нетто-диффом базы:
# файл, добавленный и снятый следующим коммитом, в истории остаётся. Слияние
# судится `--diff-merges=remerge` — против автоматического результата, то есть
# только внесённое руками. Ссылок удалённого нет — судится вся история вершины:
# перепись становится шире, а не пустой. Признаки — из одного `git log`: режим и
# блоб (`--raw`), бинарность (`--numstat` «-»; атрибуты сняты `--attr-source`
# пустым деревом — строка `*.bin diff` в `.gitattributes` бинарь в текст не
# перекрашивает), размер — одним `git cat-file --batch-check` на вершину.
#
# Отказ называет файл: бинарный (исполняемый — режим 100755; вид — `file`) либо
# больше 1 МБ. Исключение — только строкой перечня `prepush-added-files.allow`
# рядом, с доводом; строка, под шаблон которой не подпадает ни один файл дерева
# судимой вершины, — находка: исключение истекает вместе с предметом. Перечня
# нет — исключений нет.
#
# Вход — строки git `<local_ref> <local_sha> <remote_ref> <remote_sha>` на stdin;
# $1 — имя удалённого (по умолчанию origin). Пустой вход — судится HEAD.
# ИСХОДЫ: 0 — отвергнутых нет (перепись напечатана); 1 — отвергнутые файлы либо
# негодный перечень, у каждого имя; 2 — судить не смог (вершина не сводится к
# коммиту, диапазон не прочитан): пустой обход зелёным не бывает.
set -uo pipefail

LIMIT=1048576
here="${BASH_SOURCE[0]%/*}"
[ "$here" != "${BASH_SOURCE[0]}" ] || here=.
ALLOW="$here/prepush-added-files.allow"
remote="${1:-origin}"

void() {
    echo "prepush-added-files: НЕ СУДИМО — $1. Пустой обход зелёным не бывает." >&2
    exit 2
}

targets=() prev=()
input=""
[ -t 0 ] || input="$(cat)"
if [ -n "$input" ]; then
    while read -r _lref lsha _rref rsha || [ -n "${lsha:-}" ]; do
        [ -n "${lsha:-}" ] || continue
        case "$lsha" in *[!0]*) targets+=("$lsha") ;; *) continue ;; esac
        # Прежняя вершина ссылки на удалённом — уже опубликованное.
        case "${rsha:-}" in
            *[!0]*) git cat-file -e "$rsha^{commit}" 2>/dev/null && prev+=("^$rsha") ;;
        esac
    done <<< "$input"
    if [ "${#targets[@]}" -eq 0 ]; then
        echo "prepush-added-files: только снятие ссылок — коммитов не везёт, судить нечего" >&2
        exit 0
    fi
else
    targets+=(HEAD)
    echo "prepush-added-files: вход пуст — судится HEAD" >&2
fi

# Перечень исключений: `<вид> <шаблон> <довод>`, вид — size | binary.
a_kind=() a_glob=() a_used=() a_bad=()
if [ -f "$ALLOW" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in '' | '#'*) continue ;; esac
        read -r kind glob why <<< "$line"
        case "$kind" in
            size | binary) ;;
            *) a_bad+=("«$line» — вид не size и не binary"); continue ;;
        esac
        [ -n "${why:-}" ] || { a_bad+=("«$line» — без довода"); continue; }
        a_kind+=("$kind"); a_glob+=("$glob"); a_used+=(0)
    done < "$ALLOW"
fi
allowed() {  # allowed <вид> <путь> — 0, если строка перечня снимает этот вид с пути
    local i
    for i in "${!a_glob[@]}"; do
        # shellcheck disable=SC2053  # шаблон перечня — glob намеренно
        [ "${a_kind[i]}" = "$1" ] && [[ "$2" == ${a_glob[i]} ]] && return 0
    done
    return 1
}

empty_tree="$(git mktree < /dev/null)" || void "пустое дерево для --attr-source не записано"

n_new=0 n_commits=0 n_files=0 n_excused=0 bad=() commit=""
declare -A seen=() mode=() blob=() bin=() sizes=()

# flush — судит добавленные файлы одного коммита (`commit`, `mode`, `blob`, `bin`).
flush() {
    local p sz kind what
    for p in "${!blob[@]}"; do
        [ -z "${seen[${blob[$p]} $p]:-}" ] || continue
        seen["${blob[$p]} $p"]=1
        n_files=$((n_files + 1))
        what=()
        if [ "${bin[$p]:-0}" = 1 ] && ! allowed binary "$p"; then
            kind="$(file -b - < <(git cat-file blob "${blob[$p]}") 2>/dev/null)"
            if [ "${mode[$p]}" = 100755 ]; then
                what+=("исполняемый бинарь (${kind%%,*})")
            else
                what+=("бинарный (${kind%%,*})")
            fi
        fi
        sz="${sizes[${blob[$p]}]:-0}"
        if [ "$sz" -gt "$LIMIT" ] && ! allowed size "$p"; then
            what+=("$sz Б > порога 1 МБ ($LIMIT Б)")
        fi
        if [ "${#what[@]}" -gt 0 ]; then
            bad+=("$p — ${what[*]} · коммит ${commit:0:12}")
        elif [ "${bin[$p]:-0}" = 1 ] || [ "$sz" -gt "$LIMIT" ]; then
            n_excused=$((n_excused + 1))
        fi
    done
    mode=() blob=() bin=()
}

for t in "${targets[@]}"; do
    tc="$(git rev-parse --verify -q "$t^{commit}")" || void "вершина «$t» не сводится к коммиту"
    log="$(git --attr-source="$empty_tree" -c core.quotePath=false log --no-color \
        --diff-merges=remerge --diff-filter=A --raw --no-abbrev --numstat \
        --format='@%H' "$tc" "${prev[@]}" --not --remotes="$remote" 2>&1)" ||
        void "диапазон «$tc --not --remotes=$remote» не прочитан: ${log%%$'\n'*}"
    n=$(git rev-list --count "$tc" "${prev[@]}" --not --remotes="$remote" 2>&1) ||
        void "число новых коммитов «$tc» не прочитано: $n"
    n_new=$((n_new + n))
    sizes=()
    while read -r b s; do sizes["$b"]="$s"; done < <(
        awk '/^:/ { print $4 }' <<< "$log" | git cat-file --batch-check='%(objectname) %(objectsize)')
    commit=""
    while IFS= read -r line; do
        case "$line" in
            @*) [ -z "$commit" ] || flush; commit="${line#@}"; n_commits=$((n_commits + 1)) ;;
            :*) read -r _m nm _o nb _st <<< "${line%%$'\t'*}"; p="${line#*$'\t'}"
                mode["$p"]="$nm"; blob["$p"]="$nb" ;;
            -$'\t'-$'\t'*) bin["${line#-$'\t'-$'\t'}"]=1 ;;
        esac
    done <<< "$log"
    [ -z "$commit" ] || flush
    # Исключение без предмета: под шаблон не подпадает ни один файл дерева вершины.
    if [ "${#a_glob[@]}" -gt 0 ]; then
        mapfile -t tree_files < <(git -c core.quotePath=false ls-tree -r --name-only "$tc")
        for i in "${!a_glob[@]}"; do
            for f in "${tree_files[@]}"; do
                # shellcheck disable=SC2053
                [[ "$f" == ${a_glob[i]} ]] && { a_used[i]=1; break; }
            done
        done
    fi
done
for i in "${!a_glob[@]}"; do
    [ "${a_used[i]}" = 1 ] ||
        a_bad+=("${a_kind[i]} ${a_glob[i]} — под шаблон не подпадает ни один файл судимой вершины: исключать нечего")
done

echo "prepush-added-files: вершин ${#targets[@]}, новых коммитов $n_new (с добавленными файлами $n_commits), добавленных файлов $n_files (по перечню $n_excused, отвергнуто ${#bad[@]}); строк перечня ${#a_glob[@]}" >&2
rc=0
if [ "${#a_bad[@]}" -gt 0 ]; then
    echo "prepush-added-files: ОТКАЗ — перечень исключений $ALLOW негоден:" >&2
    printf '  %s\n' "${a_bad[@]}" >&2
    rc=1
fi
if [ "${#bad[@]}" -gt 0 ]; then
    echo "prepush-added-files: ОТКАЗ — добавленные файлы, которым не место в публичной истории:" >&2
    printf '  %s\n' "${bad[@]}" >&2
    echo "  Бинарь собирать вне дерева (go build -o \"\$TMPDIR/…\"), коммитить по именам, а не git add -A." >&2
    echo "  Коммит, внёсший файл, его уже несёт: удаление следующим коммитом историю не очищает —" >&2
    echo "  соберите ветку заново от базы без файла. Законный крупный текст или бинарь — строкой" >&2
    echo "  «<size|binary> <шаблон> <довод>» в $ALLOW." >&2
    rc=1
fi
exit "$rc"
