#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# inject-12.sh — доказательство того, что check-11-outward-listener-names-its-bounds СПОСОБЕН
# упасть и способен смолчать (ws#1401: приёмка, публикующая слушатель за пределы своего
# кластера, называет УЦ клиентских листов, SAN, методы и источник).
#
# ВХОД НАСТОЯЩИЙ. Песочница — синтетическая приёмка с разделом публикации в форме шапки гейта;
# каждая проба меняет ОДИН факт против полного близнеца:
#   P0  раздел полон (метки списком, цитатой и полужирным)              → 0, разделов 1;
#   P1  нет строки «УЦ клиентских листов»                                → 1, файл:строка и граница;
#   P2  значение «SAN» — заглушка «—»                                    → 1, граница SAN;
#   P3  значение «Методы» — «<перечень>»                                 → 1, граница Методы;
#   P4  строка «Источник» — ниже раздела следующего уровня (вне раздела) → 1, граница Источник;
#   P4' та же строка под подзаголовком внутри раздела                     → 0;
#   P5  приёмка без раздела публикации                                   → 0, разделов 0 (граница:
#       есть ли публикация, по тексту не вычисляется — держит acceptance-reviewer);
#   P6  названного файла нет                                             → 2, [VOID];
#   P7  дерево без приёмок                                               → 2, [VOID].
# Исходы: 0 — все пробы сошлись; 1 — нет.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/check-11-outward-listener-names-its-bounds.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/proofs.sh
. "$HERE/../lib/proofs.sh"
proof_own_environment

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

FULL='# Приёмка: межкластерный вход

## Сценарии

Дано — Когда — Тогда.

## Публикация слушателя :9091 (internal)

- УЦ клиентских листов: УЦ площадки regop-ca
> SAN: spiffe://kacho/ns/kaname/sa/gateway
- **Методы**: InternalAccess.Check, InternalAccess.Lookup
- Источник: сеть узлов кластера площадки, 10.0.0.0/16

## Что не входит

Ничего.'

doc() {  # doc <имя> <sed-правка | -> — приёмка песочницы из полного близнеца
    local f="$TMP/$1.md"
    if [ "$2" = - ]; then printf '%s\n' "$FULL" > "$f"; else printf '%s\n' "$FULL" | sed "$2" > "$f"; fi
    printf '%s' "$f"
}

expect() {  # expect <проба> <код> <файл|каталог-дерева> <образец…>
    local axis="$1" want="$2" what="$3" out got p miss=""
    shift 3
    if [ -d "$what" ]; then
        out="$(cd "$TMP" && env -u GATE_ROOT DOCS_GATE_ROOT="$what" bash "$CHECK" 2>&1)"; got=$?
    else
        out="$(cd "$TMP" && bash "$CHECK" "$what" 2>&1)"; got=$?
    fi
    for p in "$@"; do grep -qF -- "$p" <<< "$out" || miss="$miss «$p»"; done
    if [ "$got" -eq "$want" ] && [ -z "$miss" ]; then
        pass=$((pass + 1)); echo "  ok   $axis (код $got)"
    else
        fail=$((fail + 1))
        echo "  ПРОВАЛ $axis — ждали код $want, получили $got${miss:+; в выводе нет:$miss}" >&2
        printf '         %s\n' "${out//$'\n'/$'\n'         }" >&2
    fi
}

echo "== check-11: раздел публикации слушателя называет четыре границы =="
expect P0 0 "$(doc p0 -)" "разделов публикации 1, находок 0"
expect P1 1 "$(doc p1 '/^- УЦ клиентских листов:/d')" "p1.md:7" "без границы «УЦ клиентских листов»"
expect P2 1 "$(doc p2 's/^> SAN: .*/> SAN: —/')" "без границы «SAN»"
expect P3 1 "$(doc p3 's/^- \*\*Методы\*\*: .*/- **Методы**: <перечень>/')" "без границы «Методы»"
expect P4 1 "$(doc p4 '/^- Источник:/d; s/^Ничего\.$/- Источник: сеть узлов/')" "без границы «Источник»"
expect "P4'" 0 "$(doc p4t 's/^- Источник:/### Сеть\n\n- Источник:/')" "разделов публикации 1, находок 0"
expect P5 0 "$(doc p5 '/^## Публикация слушателя/,/^## Что не входит/{/^## Что не входит/!d}')" "разделов публикации 0, находок 0"
expect P6 2 "$TMP/нет-такой.md" "[VOID]"
mkdir -p "$TMP/empty" && git -C "$TMP/empty" init -q
expect P7 2 "$TMP/empty" "[VOID]" "приёмок ноль"

echo "[CENSUS] inject-12: проб $((pass + fail)), сошлось $pass, разошлось $fail"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
