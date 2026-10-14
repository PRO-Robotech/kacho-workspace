#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# trunk-future.sh — наборы воркспейса, судящие СТВОЛЫ продуктов, на БУДУЩЕМ
# состоянии: ствол названного продукта = голова запроса, который садится.
#
#   bash scripts/trunk-future.sh <продукт>=<ревизия> [...] [-- <команда> …]
#
# ЗАЧЕМ (ws#1078, урок L2 посадки 2026-10-14): `foundation-candidates` судит
# `origin/main` клонов продуктов и покраснел ПОСЛЕ вливания kaname#714 (дубль
# фикстуры, 23 файла): до вливания будущего ствола он не видел, а
# предпосадочная перепись его не звала. Все три набора задания
# `product-trunk-gates` (`foundation-candidates`, `comment-language-gate`,
# `crossrepo-gate`) берут клон из `KACHO_HOME_<ПРОДУКТ>` и ствол — из его
# `origin/main`; поэтому будущее состояние подставляется, не трогая наборы:
# на каждый названный продукт — общий (`--shared`, без копии объектов и без
# рабочего дерева) клон его клона во временном каталоге, `origin/main` клона
# переставлен на ревизию, `KACHO_HOME_<ПРОДУКТ>` указывает на него. Клон
# разработчика не меняется. Неназванные продукты судятся своими клонами.
#
# Команда по умолчанию — задание конвейера:
#   bash scripts/lib/run-suites.sh --void-is-failure --job product-trunk-gates
#
# КОДЫ: код команды проходит как есть (0 — наборы зелёные на будущем стволе,
# 1 — находка); 2 — будущего состояния НЕТ (ни одной пары, чужое имя продукта,
# клона нет, ревизии в клоне нет — `git -C <клон> fetch origin <ветка запроса>`),
# и это не зелёное. Доказательство — scripts/trunk-future-inject.sh.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="${WS:-$(cd "$here/.." && pwd)}"

void() { echo "trunk-future: [VOID] $1 — будущего состояния нет, это не зелёное" >&2; exit 2; }

pairs=() cmd=()
while [ $# -gt 0 ]; do
    case "$1" in
        --) shift; cmd=("$@"); break ;;
        *=*) pairs+=("$1"); shift ;;
        *) void "аргумент «$1» не форма <продукт>=<ревизия>" ;;
    esac
done
[ ${#pairs[@]} -gt 0 ] || void "ни одной пары <продукт>=<ревизия>"
[ ${#cmd[@]} -gt 0 ] || cmd=(bash "$WS/scripts/lib/run-suites.sh" --void-is-failure --job product-trunk-gates)

tmp="$(mktemp -d "${TMPDIR:-/tmp}/trunk-future.XXXXXX")" || void "временный каталог не заведён"
trap 'rm -rf "$tmp"' EXIT

for p in "${pairs[@]}"; do
    name="${p%%=*}" rev="${p#*=}"
    case "$name" in kacho|kaname|corelib) ;; *) void "продукт «$name» не из kacho, kaname, corelib" ;; esac
    var="KACHO_HOME_${name^^}"
    src="${!var:-$WS/project/$name}"
    [ -e "$src/.git" ] || void "$name: клона нет ($src)"
    full="$(git -C "$src" rev-parse --verify --quiet "$rev^{commit}")" \
        || void "$name: ревизии «$rev» в клоне $src нет — git -C $src fetch origin <ветка запроса>"
    git clone -q --shared --no-checkout "$src" "$tmp/$name" 2>/dev/null || void "$name: общий клон $src не заведён"
    git -C "$tmp/$name" update-ref refs/remotes/origin/main "$full"
    export "$var=$tmp/$name"
    echo "trunk-future: $name — origin/main = $full (клон $src не тронут)"
done

"${cmd[@]}"; rc=$?
echo "trunk-future: наборы на будущем стволе (${pairs[*]}) — код $rc"
exit "$rc"
