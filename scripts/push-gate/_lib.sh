# shellcheck shell=bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# _lib.sh — общее для проверок набора push-gate: печать исходов и ПЕСОЧНИЦА.
#
# ПРЕДМЕТ НАБОРА — механизм отправки воркспейса, судимый ПОВЕДЕНИЕМ: каждая
# проверка заводит синтетический клон с bare-«сервером» рядом, провязывает в него
# хуки ТЕМ ЖЕ установщиком, что и настоящий клон, и отправляет. Читается то, что
# вернула и напечатала отправка, и что после неё лежит на «сервере», — а не текст
# хука. Поиск строки `exit 1` в исходнике переходника доказал бы форму, а не
# отказ: хук волен вынести ветвь в функцию, и проверка покраснела бы на верном.
#
# ПЕСОЧНИЦА ГЕРМЕТИЧНА. Настройка git машины (глобальная и системная) сюда не
# доходит: `core.hooksPath` в личном `~/.gitconfig` переставил бы хуки мимо
# переходников, и проверка судила бы чужую машину. Личность коммитов — только
# внутри песочницы, адресом из зоны `.invalid`, который никуда не доставляется.
# Переменные окружения git снимаются: унаследованный от хука отправки `GIT_DIR`
# сильнее рабочего каталога и увёл бы запись в ЭТУ рабочую копию.
#
# ПРЕДМЕТ ПОДМЕНЯЕМ ради инъекции: `PUSH_GATE_SUBJECT` — корень дерева, из
# которого берутся судимые файлы (по умолчанию — этот воркспейс). `inject.sh`
# подаёт туда копию с одним внесённым дефектом и требует от проверки красного.

PG_WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PG_SUBJECT="${PUSH_GATE_SUBJECT:-$PG_WS}"

pg_census() { echo "[CENSUS] $*"; }
pg_pass()   { echo "[PASS] $*"; }
pg_fail()   { echo "[FAIL] $*" >&2; }
pg_void()   { echo "[VOID] $*" >&2; }

# pg_hermetic — окружение для всего, что проверка делает с git.
pg_hermetic() {
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
          GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX \
          GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL \
          GIT_SSH GIT_SSH_COMMAND KACHO_MONOREPO KACHO_SKIP_PREPUSH
    local v
    for v in $(compgen -e | grep '^KACHO_HOME_' || true); do unset "$v"; done
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
}

PG_OWNER_EMAIL="owner@push-gate.invalid"

# pg_sandbox <каталог> — клон «ws» на ветке `work` и bare-«сервер» «srv.git»
# рядом; в клоне — хуки предмета (`scripts/hooks/*`) и один набор-заглушка
# `scripts/stub-gate/run-all.sh` с исходом 0. Хуки провязаны установщиком
# предмета. Печатает путь клона. Ненулевой код — песочница не собралась.
pg_sandbox() {
    local box="$1" ws="$1/ws"
    mkdir -p "$box" || return 1
    git init -q --bare "$box/srv.git" || return 1
    git init -q -b work "$ws" || return 1
    git -C "$ws" config user.email "$PG_OWNER_EMAIL" || return 1
    git -C "$ws" config user.name  "push-gate owner" || return 1
    mkdir -p "$ws/scripts/hooks" "$ws/scripts/stub-gate" || return 1
    local f
    for f in "$PG_SUBJECT"/scripts/hooks/*; do
        [ -f "$f" ] || continue
        cp -p "$f" "$ws/scripts/hooks/" || return 1
    done
    [ -f "$ws/scripts/hooks/install.sh" ] || return 1
    printf '#!/usr/bin/env bash\necho "stub-gate: рассмотрено проверок 1; пройдено 1"\nexit 0\n' \
        > "$ws/scripts/stub-gate/run-all.sh"
    chmod +x "$ws/scripts/stub-gate/run-all.sh" "$ws"/scripts/hooks/* || return 1
    git -C "$ws" add -A >/dev/null || return 1
    git -C "$ws" commit -q -m "песочница push-gate" || return 1
    git -C "$ws" remote add origin "$box/srv.git" || return 1
    ( cd "$ws" && bash scripts/hooks/install.sh install >/dev/null 2>&1 ) || return 1
    printf '%s\n' "$ws"
}

# pg_remote_sha <песочница> <ветка> — sha ветки на «сервере» либо пусто.
pg_remote_sha() {
    git --git-dir="$1/srv.git" rev-parse --verify -q "refs/heads/$2" 2>/dev/null || true
}

# pg_has <вывод> <подстрока>… — все подстроки есть. Сравнением, а не трубой:
# `printf | grep -q` под `pipefail` роняет писателя SIGPIPE'ом, и найденное
# объявляется ненайденным.
pg_has() {
    local out="$1" n; shift
    for n in "$@"; do [[ "$out" == *"$n"* ]] || return 1; done
    return 0
}
