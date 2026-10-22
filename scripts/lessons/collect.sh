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
exec python3 "${LESSONS_PY:-$HERE/lessons.py}" "$@"
