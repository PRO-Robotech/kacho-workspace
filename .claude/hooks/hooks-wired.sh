#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# hooks-wired.sh — непровязанная рабочая копия видна БЕЗ ЗАПУСКА КОМАНДЫ.
#
# # Предмет
#
# Правило «перед отправкой ветки — обязательный локальный прогон» объявлено
# держащимся хуком, а не вниманием. Проверить это можно было только позвав
# `install.sh check` — то есть узнать, что защиты нет, мог лишь тот, кто и так
# о ней помнил. Цена измерена: за одну сессию конвейер девятнадцать раз стал
# первым читателем кода, три прогона упали на том, что локальный прогон нашёл
# бы за секунды, а очередь ранеров дошла до 32 прогонов.
#
# Провязка и заметность — РАЗНЫЕ вещи, и вторая важнее. Провязку чинят один раз;
# она разваливается снова при свежем клоне, при переезде каталога, при
# выставленном `core.hooksPath`, ведущем в никуда, — и каждый раз молча.
#
# # Форма
#
# Хук исполняется на КАЖДОМ обращении к сессии (`UserPromptSubmit`) и молчит,
# пока всё в порядке. Молчание выбрано намеренно: строка, печатающаяся всегда,
# перестаёт читаться на третий день, и заметность превращается в шум.
#
# Отсюда обязанность, которую молчание накладывает: хук ОБЯЗАН заговорить, когда
# ему нечего осмотреть. «Ноль находок» и «ноль прочитанного» здесь дают один и
# тот же пустой вывод, поэтому второе названо отдельной строкой.
#
# Сессию не роняет НИКОГДА (выход 0 при любом исходе): это указатель, а не гейт.
# Гейт — сам `pre-push`, и он отказывает в отправке.
set -uo pipefail

ws="${CLAUDE_PROJECT_DIR:-}"
[ -n "$ws" ] || ws="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

marker="kacho-hook-stub v1"
findings=()
examined=0

# check_clone <корень> <как называть в отчёте>
check_clone() {
    local root="$1" name="$2"
    [ -d "$root" ] || return 0

    local common
    common="$(git -C "$root" rev-parse --git-common-dir 2>/dev/null)" || return 0
    case "$common" in /*) ;; *) common="$root/$common" ;; esac
    examined=$((examined + 1))

    # Настройка, уводящая git от `.git/hooks`, — отдельный вид поломки: она
    # выглядит настроенной и при этом отключает ВСЁ, что там лежит.
    local cfg
    cfg="$(git -C "$root" config --get core.hooksPath 2>/dev/null || true)"
    if [ -n "$cfg" ]; then
        local abs="$cfg"
        case "$abs" in /*) ;; *) abs="$root/$abs" ;; esac
        if [ ! -d "$abs" ]; then
            findings+=("$name: core.hooksPath ведёт в НЕСУЩЕСТВУЮЩИЙ «$cfg» — хуков нет ни одного")
            return 0
        fi
    fi

    # Отслеживаемые хуки — то же множество, что увидит свежий клон.
    local tracked=()
    while IFS= read -r rel; do
        local base="${rel##*/}"
        case "$base" in *.*) continue ;; esac
        tracked+=("$base")
    done < <(git -C "$root" ls-files scripts/hooks 2>/dev/null)

    if [ "${#tracked[@]}" -eq 0 ]; then
        findings+=("$name: в scripts/hooks нет НИ ОДНОГО отслеживаемого хука — отправка не проверяется")
        return 0
    fi

    local h target
    for h in "${tracked[@]}"; do
        target="$common/hooks/$h"
        if [ ! -e "$target" ]; then
            findings+=("$name: хук «$h» НЕ провязан — отправка идёт без локального прогона")
        elif ! grep -qF "$marker" "$target" 2>/dev/null; then
            findings+=("$name: «$h» в .git/hooks — посторонний файл, наш прогон им не исполняется")
        elif [ ! -x "$target" ]; then
            findings+=("$name: «$h» провязан, но НЕ исполняемый — git его пропустит молча")
        elif [ ! -x "$root/scripts/hooks/$h" ]; then
            findings+=("$name: «$h» провязан в пустоту — scripts/hooks/$h не исполняемый или отсутствует")
        fi
    done
}

check_clone "$ws" "воркспейс"
check_clone "$ws/project/kacho" "монорепо"

if [ "$examined" -eq 0 ]; then
    echo "ХУКИ: не осмотрено НИ ОДНОЙ рабочей копии — этот указатель сейчас ничего не значит." >&2
    echo "     Ни \$CLAUDE_PROJECT_DIR, ни каталог рядом с ним репозиторием не оказались." >&2
    exit 0
fi

if [ "${#findings[@]}" -gt 0 ]; then
    echo "ХУКИ НЕ ПРОВЯЗАНЫ — отправка ветки НЕ проверяется локально:" >&2
    printf '  · %s\n' "${findings[@]}" >&2
    echo "  Починить: bash <корень>/scripts/hooks/install.sh install" >&2
    echo "  (в монорепо есть и цель: make install-hooks)" >&2
fi

exit 0
