#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# check-11 — приёмка, публикующая слушатель за пределы своего кластера, называет его
# границы — УЦ, SAN, методы, источник (ws#1401).
#
# ПРИЗНАК. Класс урока «межкластерная публикация внутреннего слушателя» повторился дважды
# за 2026-10-24 (`collect.sh status 'межкластерная публикация внутреннего слушателя'`):
# приёмка дошла до выбора адреса публикации, не назвав УЦ клиентских листов, перечень SAN
# и методов (`00-kacho-core.md#ban18-q-security`: расширение поверхности не названо).
#
# ФОРМА. Публикацию автор приёмки объявляет разделом с заголовком «Публикация слушателя …»
# (любого уровня; по разделу на слушатель), в котором строки с метками:
#   - УЦ клиентских листов: <какому УЦ слушатель доверяет>
#   - SAN: <закрытый перечень SAN по каждому УЦ>
#   - Методы: <закрытый перечень методов, доступных через публикацию>
#   - Источник: <откуда принимаются соединения>
# Метка — в начале строки после маркера списка, цитаты либо полужирного; значение —
# непустое и не заглушка («—», «-», «TBD», «?», «…», «<…>»).
#
# ГРАНИЦА (держится вниманием, не этим гейтом): ЕСТЬ ли публикация, по тексту приёмки не
# вычисляется — слово «LoadBalancer» в корпусе — имя ресурса продукта (перепись 2026-10-24:
# 200 приёмок, фраз «за пределы кластера», «межкластерн», «вне кластера» — 0). Раздел
# объявляет автор — пункт самопроверки `acceptance-author`; публикация без раздела — ⛔
# `acceptance-reviewer`. Гейт судит ПОЛНОТУ объявленного раздела.
#
# ВХОД. Без доводов — приёмки дерева (`docs/specs/*-acceptance.md`,
# `docs/changes/*/acceptance*.md`, индекс git); с доводами — названные файлы (приёмка
# чужого репозитория судится той же командой: `bash <этот файл> <путь>`).
#
# ИСХОДЫ: 0 — каждый раздел полон, объём прочитанного напечатан; 1 — находка: файл, строка
# заголовка, недостающая граница; 2 — [VOID]: приёмок ноль либо названного файла нет.
# Доказательство — `inject-12.sh` рядом.
set -uo pipefail
NAME="check-11-outward-listener-names-its-bounds"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

files=(); root=""
if [ "$#" -gt 0 ]; then
    for f in "$@"; do
        [ -f "$f" ] || { echo "[VOID] $NAME — файла нет: $f" >&2; exit 2; }
        files+=("$f")
    done
else
    root="$(python3 "$SELF_DIR/../lib/gate_root.py" DOCS_GATE_ROOT "${BASH_SOURCE[0]}")" || exit 2
    while IFS= read -r p; do
        [ -n "$p" ] && files+=("$root/$p")
    done < <(git -C "$root" ls-files --cached --others --exclude-standard -- \
        'docs/specs/*-acceptance.md' 'docs/changes/*/acceptance*.md' | LC_ALL=C sort -u)
fi
if [ "${#files[@]}" -eq 0 ]; then
    echo "[VOID] $NAME — приёмок ноль: судить нечего, это не «находок ноль»" >&2
    exit 2
fi

# Один проход awk по файлу: строка «B <строка заголовка>» на раздел и «M <строка> <граница>»
# на недостающую границу.
judge() {
    awk '
    function flush(   i) {
        if (!open) return
        print "B " hl
        for (i = 1; i <= 4; i++) if (!(lab[i] in got)) print "M " hl " " lab[i]
        open = 0; delete got
    }
    BEGIN { lab[1] = "УЦ клиентских листов"; lab[2] = "SAN"; lab[3] = "Методы"; lab[4] = "Источник" }
    /^#+[ \t]/ {
        lvl = index($0, " ") - 1; t = index($0, "\t") - 1
        if (t > 0 && (lvl < 0 || t < lvl)) lvl = t
        if (open && lvl <= olvl) flush()
        rest = substr($0, lvl + 2); gsub(/^[ \t*_]+/, "", rest)
        if (rest ~ /^Публикация слушателя/) { open = 1; olvl = lvl; hl = NR }
        next
    }
    open {
        s = $0; gsub(/[*_]/, "", s); sub(/^[ \t>]*([-+][ \t]+)?/, "", s)
        for (i = 1; i <= 4; i++) {
            if (index(s, lab[i]) != 1) continue
            v = substr(s, length(lab[i]) + 1)
            if (v !~ /^[ \t]*:/) continue
            sub(/^[ \t]*:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
            if (v == "" || v ~ /^(—|-|–|TBD|\?|…|\.\.\.)$/ || v ~ /^<.*>$/) continue
            got[lab[i]] = 1
        }
    }
    END { flush() }' "$1"
}

blocks=0; findings=0
for f in "${files[@]}"; do
    while IFS= read -r line; do
        case "$line" in
            "B "*) blocks=$((blocks + 1)) ;;
            "M "*)
                rest="${line#M }"; ln="${rest%% *}"; what="${rest#* }"
                findings=$((findings + 1))
                rel="$f"; [ -z "$root" ] || rel="${f#"$root/"}"
                echo "[FAIL] $NAME — $rel:$ln: раздел «Публикация слушателя» без границы «$what» (ws#1401; ban18-q-security)" >&2 ;;
        esac
    done < <(judge "$f")
done
echo "[CENSUS] $NAME: приёмок ${#files[@]}, разделов публикации $blocks, находок $findings"
[ "$findings" -eq 0 ] || exit 1
echo "[PASS] $NAME — каждый раздел публикации называет УЦ клиентских листов, SAN, методы и источник"
