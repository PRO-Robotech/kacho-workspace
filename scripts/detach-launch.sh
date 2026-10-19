# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
# shellcheck shell=bash disable=SC2034  # DETACH_MODE, DETACH_WARN — итог для подключившего
#
# detach-launch.sh — отсоединённый запуск ВНЕ scope сессии; подключается source'ом
# (scripts/detach.sh, scripts/autoland/autoland.sh). Исполняемым не бывает.
#
# ЗАЧЕМ. `setsid` даёт новый сеанс, но не новую cgroup: ребёнок остаётся в scope
# терминала сессии (vte-spawn-*.scope, у `session-memcap.sh --launch` — свой scope) и
# умирает вместе с ним. Замер 2026-10-19 (systemd 259): снят `systemctl --user stop`
# родительский scope — setsid-ребёнок убит, служба `systemd-run --user` из того же scope
# жива. Снимают scope: остановка терминала, OOM-убийство под OOMPolicy=stop (у
# vte-spawn-*.scope — stop, `session-memcap.sh`), выбор oomd. Перезагрузку машины не
# переживает НИЧТО: её status различает по времени загрузки (detach_gone_reason).
#
# detach_launch <имя юнита> <журнал> -- <команда…>
#   · systemd --user отвечает — служба `systemd-run --user --collect --unit=<имя>`:
#     каталог вызова (--same-dir), доводы дословно (--expand-environment=no), umask вызова, OOMPolicy=continue (OOM-убийство
#     одного процесса не снимает всю службу, обёртка успевает записать исход);
#     окружение вызова — целиком, `--setenv=<ИМЯ>` без значения (systemd берёт его из
#     окружения вызова: в argv и в `ps` — только имена; замер — перевод строки и ESC в
#     значении доходят дословно). Метки окружения (CLAUDE_CODE_SESSION_ID, CLAUDE_PID,
#     KACHO_DETACHED_UNTIL) доходят до службы — перепись застоя её видит;
#   · иначе — прежний путь `setsid` с ГРОМКИМ предупреждением в stderr: шаг живёт в scope
#     сессии и её перезапуск не переживёт. KACHO_DETACH_NO_SYSTEMD=1 — этот путь
#     нарочно (режим проб: близнец без службы).
#   Ввод/вывод — в журнал (дописывается) обёрткой `bash -c 'exec >>…'` на ОБОИХ путях;
#   pid сохраняется через exec: pid, записанный командой, — pid процесса шага.
#   Итог — в переменных: DETACH_MODE (unit | setsid), DETACH_WARN (текст или пусто).
#   Код 0 — запущено; 69 — не запущено ни одним путём (нет setsid).
#
# ГРАНИЦА: служба — вне потолка памяти scope сессии (session-memcap): тяжёлое, как и
# прежде, идёт слотом `heavy-slot.sh` (свой scope и предел); служба снимается
# `systemctl --user stop <юнит>` и, как прежде, сигналом по pid.
detach_launch() {
    local unit="$1" log="$2" why="" kv n out
    local -a envs=()
    shift 2
    [ "${1:-}" = -- ] && shift
    DETACH_MODE=""; DETACH_WARN=""
    # shellcheck disable=SC2016
    local wrap='exec >> "$0" 2>&1 < /dev/null; exec "$@"'
    if [ "${KACHO_DETACH_NO_SYSTEMD:-}" = 1 ]; then
        why="KACHO_DETACH_NO_SYSTEMD=1"
    elif ! command -v systemd-run > /dev/null 2>&1; then
        why="нет systemd-run"
    elif ! out="$(systemctl --user show-environment 2>&1 > /dev/null)"; then
        why="systemd --user не отвечает (${out:0:120})"
    else
        while IFS= read -r -d '' kv; do
            n="${kv%%=*}"
            [[ "$n" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && envs+=("--setenv=$n")
        done < <(env -0)
        # --expand-environment=no: иначе systemd раскрывает `$$` и `$ИМЯ` в доводах ExecStart
        # (замер: `echo $$` писал в .pid «$»), и текст команды исполнялся бы не тот.
        if out="$(systemd-run --user --quiet --collect --unit="$unit" --same-dir --expand-environment=no \
                -p UMask="$(umask)" -p OOMPolicy=continue "${envs[@]}" \
                -- bash -c "$wrap" "$log" "$@" 2>&1 < /dev/null)"; then
            DETACH_MODE=unit; return 0
        fi
        # Отказ вызова при уже поднятой службе (таймаут шины) — второй запуск был бы дублем.
        case "$(systemctl --user is-active "$unit" 2>/dev/null)" in
            active|activating|reloading) DETACH_MODE=unit; return 0 ;;
        esac
        why="systemd-run отказал (${out:0:160})"
    fi
    command -v setsid > /dev/null 2>&1 || { DETACH_WARN="$why; нет и setsid — не запущено"; return 69; }
    DETACH_WARN="ПРЕДУПРЕЖДЕНИЕ: $why — запущено setsid в scope сессии: НЕ переживёт перезапуск сессии (снятие scope, OOM-стоп scope, oomd)"
    printf '%s\n' "$DETACH_WARN" >&2
    setsid bash -c "$wrap" "$log" "$@" < /dev/null > /dev/null 2>&1 &
    DETACH_MODE=setsid
    return 0
}

# detach_gone_reason <файл .pid> <файл .unit> — почему процесса шага нет: перезагрузка
# машины (файл шага старше загрузки — btime из /proc/stat; судит и шаги, запущенные до
# этой правки), служба снята (её состояние systemd), либо процесс setsid-пути убит.
detach_gone_reason() {
    local bt mt u st
    bt="$(awk '$1 == "btime" { print $2 }' /proc/stat 2> /dev/null)"
    mt="$(stat -c %Y "$1" 2> /dev/null)"
    if [[ "$bt" =~ ^[0-9]+$ ]] && [[ "$mt" =~ ^[0-9]+$ ]] && [ "$mt" -lt "$bt" ]; then
        printf 'машина перезагружена после старта (шаг %s, загрузка %s)' \
            "$(date -u -d "@$mt" +%FT%TZ)" "$(date -u -d "@$bt" +%FT%TZ)"; return
    fi
    u="$(cat "$2" 2> /dev/null)"
    if [ -n "$u" ]; then
        st="$(systemctl --user show -p ActiveState -p Result --value "$u" 2> /dev/null | paste -sd/)"
        case "$st" in
            ''|inactive/success) printf 'служба %s снята без исхода' "$u" ;;
            *) printf 'служба %s — %s' "$u" "$st" ;;
        esac
        return
    fi
    printf 'процесс setsid-пути убит или снят вместе со scope сессии'
}
