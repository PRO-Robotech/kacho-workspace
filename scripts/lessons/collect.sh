#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# collect.sh — сборщик уроков полос и диспетчера (ws#1199, новый флоу, часть 8).
# Устройство, источники, статусы и коды — шапка `lessons.py` рядом.
#
# usage:
#   collect.sh scan   [--budget С]          дописать новые уроки в ведомость
#   collect.sh status [<ключ>]               перечень «что делать» (код 1) либо 0; с ключом — один класс (ключ один, иначе 64)
#                                            и каждый его случай: ?<id> дата агент: текст ведомости целиком
#   collect.sh signal [--budget С]          scan + строка сигнала, только новое (хук)
#   collect.sh report                        классы, случаи, статусы, доля «не держит»
#   collect.sh mark <ключ> <статус> <ссылка> open|edited|mechanism|landed|verified|rejected
#   collect.sh rekey ?<id> <ключ>            ключ уроку без ключа в тексте (событие; ws#1230)
#   collect.sh --help | -h | help            эта справка, код 0 (ws#1402)
#
# Где (переопределяется окружением — швы пробы `inject.sh`):
#   LESSONS_DIR          ведомость `lessons.jsonl` и кэш разбора — `<WS>/tmp/reports`;
#   LESSONS_PROJECTS_DIR журналы Claude Code проекта — `~/.claude/projects/<код WS>`
#                        (код — путь WS, каждый знак кроме латиницы и цифр → `-`,
#                        как у `scripts/stall-census.sh`);
#   LESSONS_WAVES_DIR    каталоги волн `wave-*/` — `<WS>/tmp`;
#   LESSONS_ALIASES      синонимы классов — `aliases.tsv` рядом;
#   LESSONS_PY           ядро — `lessons.py` рядом.
# WS — корень воркспейса по `scripts/lib/ws-home.sh` (worktree и клон под tmp/
# пишут в одну ведомость).
set -uo pipefail
# Справка — шапкой этого файла, до python3 и ведомости (урок e77dd564: --help отвечал VOID).
case "${1:-}" in
    -h | --help | help) awk '/^# usage:/ { on = 1 } on && /^# WS — / { exit } on { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"; exit 0 ;;
esac
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../lib/ws-home.sh
. "$HERE/../lib/ws-home.sh"
WS="$(ws_home "$HERE")" || { echo "lessons: VOID — корень воркспейса не выведен из $HERE" >&2; exit 2; }
command -v python3 > /dev/null 2>&1 || { echo "lessons: VOID — нет python3" >&2; exit 2; }
export WS
export LESSONS_DIR="${LESSONS_DIR:-$WS/tmp/reports}"
export LESSONS_PROJECTS_DIR="${LESSONS_PROJECTS_DIR:-$HOME/.claude/projects/$(printf '%s' "$WS" | sed 's/[^A-Za-z0-9]/-/g')}"
export LESSONS_WAVES_DIR="${LESSONS_WAVES_DIR:-$WS/tmp}"
export LESSONS_ALIASES="${LESSONS_ALIASES:-$HERE/aliases.tsv}"
# Разрешённое исключение нормы «машина не для прогонов» (ws#1498; CLAUDE.md §«Локальная
# разработка»): короткий разбор ЛОКАЛЬНОЙ ведомости, а не прогон. Основание: вход — журналы
# Claude Code этой машины (LESSONS_PROJECTS_DIR), во внешний кластер они не едут —
# remote-reader.sh `secret_path` не переносит ~/.claude/* (переписка сессий), — а хук
# lessons-signal зовёт сборщик на каждом Stop с пределом в секунды: Job на ход не годится.
# Граница: ядро — чтение файлов stdlib без сети и порождений, пишет лишь LESSONS_DIR; `-I` —
# окружение PYTHON*, user site и каталог скрипта не подмешиваются; scan — под --budget.
# Держит lessons/inject.sh (форма вызова и импорты ядра); heavy-guard судит строку команды —
# прямой `python3 lessons.py` им отказан, как прежде.
exec python3 -I "${LESSONS_PY:-$HERE/lessons.py}" "$@"
