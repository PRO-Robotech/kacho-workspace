#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# check-04 — исход отправки берётся У СЕРВЕРА, а не у кода команды; keepalive
# транспорта — настройка клона, чужой транспорт не перебивается (ws#776).
#
# ЗАЧЕМ. Отправка отчиталась `exit code 0` при настоящем 128: соединение оборвали
# по простою длинного хука, пакет не ушёл, а ноль принадлежал посреднику. Исход
# отправки — ПОСТУСЛОВИЕ: ссылка на сервере равна отправленной sha.
#
# ЧТО ИСПОЛНЯЕТСЯ — на КАЖДОЙ отправке, поэтому быстрое:
#   · доказательство `scripts/push-verified-inject.sh` целиком: ложный ноль тремя
#     путями (команда вернула ноль без пакета · отказ транспорта · код съеден
#     посредником) краснеет и называет обе стороны, законная отправка — молчит;
#     его исход и перепись проходят сюда насквозь;
#   · keepalive установщика: в песочнице `install` выставляет клону
#     `core.sshCommand` с ServerAliveInterval, а заданный заранее чужой транспорт
#     оставляет нетронутым и называет;
#   · хук отправки называет свой код исходом ПРОВЕРОК и печатает постусловие —
#     `git ls-remote` с той sha, которую отправка подала.
set -uo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
NAME="check-04-push-verdict-comes-from-the-remote"

proof="$PG_SUBJECT/scripts/push-verified-inject.sh"
[ -f "$PG_SUBJECT/scripts/push-verified.sh" ] || { pg_void "$NAME — обёртки scripts/push-verified.sh нет"; exit 2; }
[ -f "$proof" ] || { pg_void "$NAME — доказательства scripts/push-verified-inject.sh нет"; exit 2; }
# Последняя проба отправляет через хук предмета, и хук судит диапазон разборщиком.
if [ -f "$PG_SUBJECT/scripts/cla-gate/cla.py" ]; then pg_judge_premise "$NAME" || exit 2; fi

pg_hermetic
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
probes=0; failed=0
probe() {
    probes=$((probes + 1))
    if [ "$1" = да ]; then pg_pass "$NAME — $2"; else failed=$((failed + 1)); pg_fail "$NAME — $2${3:+: $3}"; fi
}

out="$(bash "$proof" 2>&1 </dev/null)"; rc=$?
census="$(printf '%s\n' "$out" | grep -E '^\[CENSUS\]' | tail -1)"
probe "$( [ "$rc" = 0 ] && [[ "$census" == *"провалов 0"* ]] && echo да || echo нет)" \
    "постусловие: ложный ноль краснеет, законная отправка молчит — ${census#\[CENSUS\] }" \
    "код $rc; хвост: $(printf '%s\n' "$out" | tail -8)"

ws="$(pg_sandbox "$TMP/box")"; pg_sandbox_verdict "$NAME" $? || exit $?
cur="$(git -C "$ws" config --get core.sshCommand || true)"
probe "$( [[ "${cur,,}" == *serveraliveinterval=20* ]] && echo да || echo нет)" \
    "keepalive: install выставил клону core.sshCommand с ServerAliveInterval" "core.sshCommand = «$cur»"
git -C "$ws" config core.sshCommand "ssh -i /dev/null -p 2222"
out="$(cd "$ws" && bash scripts/hooks/install.sh install 2>&1)"
cur="$(git -C "$ws" config --get core.sshCommand || true)"
probe "$( [ "$cur" = "ssh -i /dev/null -p 2222" ] && pg_has "$out" "транспорт задан снаружи" && echo да || echo нет)" \
    "keepalive: чужой транспорт не перебит и назван" "core.sshCommand = «$cur»; вывод: $out"

git -C "$ws" config core.sshCommand "$(printf 'ssh -o ServerAliveInterval=20 -o ServerAliveCountMax=3')"
sha="$(git -C "$ws" rev-parse HEAD)"
git -C "$ws" remote set-url origin "$TMP/box/elsewhere.git"
git -C "$ws" config remote.origin.pushurl "$TMP/box/srv.git"
out="$(cd "$ws" && git push origin work 2>&1)"; rc=$?
probe "$( [ "$rc" = 0 ] && pg_has "$out" "код ЭТОГО хука — исход ПРОВЕРОК" "git ls-remote $TMP/box/srv.git refs/heads/work   # ожидается $sha" && echo да || echo нет)" \
    "хук отправки называет свой код своим и печатает постусловие у сервера ОТПРАВКИ (pushurl), с отправленной sha" "код $rc; вывод: $out"

pg_census "$NAME: доказательство постусловия исполнено (${census#\[CENSUS\] }), песочниц $(pg_sandboxes "$TMP"); проб $probes, провалено $failed"
if [ "$failed" -gt 0 ]; then pg_fail "$NAME — проб с находкой: $failed"; exit 1; fi
pg_pass "$NAME — вердикт отправки — постусловие сервера; keepalive — настройка клона"
