#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# check-02 — хук отправки судит ОТПРАВЛЯЕМЫЙ ДИАПАЗОН против ведомости
# `contribution-ledger.yaml` СТВОЛА сервера отправки ДО отправки (ws#729 пп. 1, 4, 5;
# ws#700).
#
# ЗАЧЕМ. Подпись коммита разъезжалась посреди сессии: адрес окружения сильнее
# настройки копии, `git config user.email` отвечал «норма», а коммит уходил
# чужим адресом. Ловил это только гейт соглашения на стороне сервера — после
# отправки, где цена — перезапись опубликованного.
#
# ПОЛНОМОЧИЯ БЕРУТСЯ ИЗ СТВОЛА, А НЕ ИЗ ПРОВЕРЯЕМОГО ИЗМЕНЕНИЯ (решение по роду
# круга 3): судит ведомость ветки, на которую указывает HEAD сервера отправки. Запись
# о личности в отправляемой ревизии круг допущенных не расширяет — она садится в
# ствол отдельной посадкой. Посадка в песочнице — `land`: ствол «сервера» сдвигается
# без суждения, как это делает сервер.
#
# ЧТО ТРЕБУЕТСЯ — поведением, в песочнице с bare-«сервером»; настройка копии в
# каждой пробе ВЕРНА (владелец), подменяется только окружение коммита:
#   A  свой коммит                          → отправка проходит, объём и ствол названы;
#      не прошла на собранной песочнице — НАХОДКА (исход 1), а не «без предмета»;
#   B  автор подставлен окружением          → отказ: sha, адрес, роль; «сервер» не сдвинулся;
#   C  коммиттер подставлен                 → отказ, роль «коммиттер»;
#   D  соавтор в блоке трейлеров вне ведомости → отказ, роль «соавтор»;
#      близнец: то же упоминание в прозе тела → проходит;
#   E  освобождённая СТВОЛОМ личность автором → отказ (освобождение — вопрос
#      соглашения, а не подписи); она же соавтором → отказ по ключу атрибуции;
#   F' запись адреса в ведомости НЕ закоммичена → отказ;
#   F  запись адреса в ведомости ОТПРАВЛЯЕМОЙ ревизии → отказ: ведомость изменения не
#      действует, лечение — «ведомость вашего адреса должна сначала сесть в ствол»;
#      близнец — та же запись СНАЧАЛА села в ствол → та же отправка проходит;
#   W  две редакции ведомости, ранняя ШИРЕ (прежний адрес — в owners, чужой — в
#      signatories), ствол несёт позднюю: ветка от ранней с коммитом адреса «только
#      история» либо чужого → отказ; КАЖДАЯ напечатанная команда лечения исполняется
#      ДОСЛОВНО, включая повторную отправку через настоящий хук, → отправка проходит,
#      и на «сервере» нет ни одного коммита запретного адреса; близнец — свой коммит
#      на той же ветке → проходит, отличие ведомости ветки названо;
#   T  аннотированный тег: автор тега чужой → отказ, тега на «сервере» нет; ключ
#      атрибуции в сообщении тега → отказ; близнец — свой тег → проходит;
#   G  чужой коммит уже на «сервере» (обход --no-verify) → свой поверх него
#      проходит: судится то, что отправка опубликует, а не вся история;
#   H  ревизия без ведомости судится стволом → своя проходит; ствол без ведомости →
#      отказ «условие не создано» с флагом первой посадки; напечатанная отправка с
#      флагом исполняется дословно → ревизия, несущая ведомость, проходит в узкой форме,
#      чужой коммит в ней — отказ; сервер, не назвавший HEAD, → отказ;
#   M  разборщика нет в рабочем дереве → отказ «судить нечем» (fail-closed);
#   K  суждение не вынесено (исход 2: sha нет в клоне, строка не разобрана) → отказ;
#   L  опубликованное — то, что лежит на сервере ОТПРАВКИ: ссылка отслеживания,
#      пережившая снятие ветки на сервере, чужой коммит не вычитает → отказ;
#      близнец — тот же коммит на сервере под другой ссылкой → проходит;
#   P  pushurl ведёт на другой сервер: коммит, известный лишь серверу выборки,
#      судится → отказ; близнец — он же на сервере отправки → проходит;
#   Q  посадка сервером (коммиттер noreply@github.com) уже на «сервере»: новая ветка
#      по URL проходит; зеркало, чей ствол записи `committers` не несёт, → отказ, и
#      та же запись в ведомости ветки его не снимает; запись села в ствол зеркала →
#      проходит; та же личность автором → отказ;
#   R  ссылка, не публикующая ни одного коммита (тег на опубликованное), — проходит,
#      даже если в дереве её ревизии ведомости нет либо та негодна по нынешнему разбору;
#   S  пустое зеркало (ствола нет): отказ «условие не создано»; напечатанная отправка
#      с флагом дословно — ревизия без ведомости → отказ, ревизия с ведомостью, всё
#      своё → проходит;
#   N  строки отправки пришли с задержкой, вызов с URL (как зовёт git) → судятся;
#   I  снятие ссылки                        → проходит, публиковать нечего;
#   J  хук без диапазона на stdin (не из git push) → говорит «НЕ судились», а не молчит.
set -uo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
NAME="check-02-push-range-judges-identities"

[ -f "$PG_SUBJECT/scripts/hooks/pre-push" ] || { pg_void "$NAME — хука scripts/hooks/pre-push нет"; exit 2; }
[ -f "$PG_SUBJECT/scripts/cla-gate/cla.py" ] || { pg_void "$NAME — разборщика scripts/cla-gate/cla.py нет"; exit 2; }
pg_judge_premise "$NAME" || exit 2

pg_hermetic
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

probes=0; failed=0
probe() {  # <да|нет> <метка> [<пояснение>]
    probes=$((probes + 1))
    if [ "$1" = да ]; then pg_pass "$NAME — $2"; else failed=$((failed + 1)); pg_fail "$NAME — $2${3:+: $3}"; fi
}

box="$TMP/box"
ws="$(pg_sandbox "$box")"; pg_sandbox_verdict "$NAME" $? || exit $?
srv="$box/srv.git"
SESSION="session@push-gate.invalid"
MACHINE="machine@push-gate.invalid"
OLD="old@push-gate.invalid"
STRANGER="stranger@push-gate.invalid"
WAIVE="waivers:
  - email: $MACHINE
    note: машинная личность песочницы"
# Ведомость пробы ЗАКОММИЧЕНА: отказы ниже откатывают клон `reset --hard`, и
# незакоммиченная запись пропадала бы вместе с ними.
pg_ledger "$ws" "$WAIVE"
git -C "$ws" add contribution-ledger.yaml && git -C "$ws" commit -q -m "ведомость пробы"
q_base="$(git -C "$ws" rev-parse HEAD)"   # чистая история для проб Q и S: ни одного чужого коммита

edit() { echo "$RANDOM$RANDOM" >> "$ws/f.txt"; git -C "$ws" add -A; }
push() { ( cd "$ws" && git push origin work 2>&1 ); }
published() { pg_remote_sha "$box" work; }
# land <ревизия> [<сервер>] — посадка в ствол «сервера» БЕЗ суждения: шаг сервера, а
# не отправка разработчика.
land() {
    ( cd "$ws" && git push -q --no-verify "${2:-$srv}" "$1:refs/heads/main" 2>/dev/null ) && return 0
    # Находка объявляется первой: посадка ломается каскадом, когда проба выше уже
    # покраснела (отправка, которой полагался отказ, сдвинула «сервер»).
    if [ "$failed" -gt 0 ]; then
        pg_fail "$NAME — посадка $1 в ствол не удалась после $failed провалов выше: остальные пробы не исполнялись"
        exit 1
    fi
    pg_void "$NAME — посадка $1 в ствол «сервера» не удалась: пробы ниже судили бы не тот ствол"
    exit 2
}
trunk_ledger() { git --git-dir="${1:-$srv}" show main:contribution-ledger.yaml 2>/dev/null; }
# idents <сервер> <ref> <^исключение> — адреса авторов и коммиттеров диапазона на «сервере».
idents() { git --git-dir="$1" log --format='%ae%n%ce' "$2" "$3" 2>/dev/null | sort -u; }
# cures <вывод> — исполнимые строки лечения («лечение$ <команда>»).
cures() { printf '%s\n' "$1" | sed -n 's/^  лечение\$ //p'; }
# cure_verbatim <вывод> — исполняет в клоне ДОСЛОВНО каждую напечатанную команду
# лечения, включая повторную отправку (через настоящий хук); печатает вывод
# последней команды, код — её код. Ни одной команды — код 3.
cure_verbatim() {
    local cmd out="" rc=3
    while IFS= read -r cmd; do
        [ -n "$cmd" ] || continue
        out="$( cd "$ws" && bash -c "$cmd" 2>&1 )"; rc=$?
    done < <(cures "$1")
    printf '%s\n' "$out"
    return "$rc"
}

# ── A. свой коммит ───────────────────────────────────────────────────────────
#
# Положительная половина, не прошедшая на собранной песочнице, — НАХОДКА о
# предмете, а не «условие не создано»: окружение (python3, разборщик YAML,
# песочница) проверено выше, и отказ законной отправке выносит сам предмет — хук
# или суждение. Прежде здесь стоял исход 2, и набор писал «провалено 0, без
# предмета 1», а хук отправки пропускал его как беспредметный (находка приёмки
# круга 1: мутант «автор допустим только из signatories» выживал с кодом 2).
out="$(push)"; rc=$?
probe "$( [ "$rc" = 0 ] && [ "$(published)" = "$(git -C "$ws" rev-parse HEAD)" ] && pg_has "$out" "публикуемых коммитов 1" "ствол main@" && echo да || echo нет)" \
    "A свой коммит: отправка прошла, объём и судящий ствол названы" "код $rc; вывод: $out"
if [ "$failed" -gt 0 ]; then
    pg_fail "$NAME — положительная половина не прошла: предмет отказывает законной отправке; отказы ниже не исполнялись — они были бы недоказательны"
    exit 1
fi
land "$q_base"
clean="$(published)"

refused() {  # <метка> <роль> <адрес> — отправка HEAD обязана быть остановлена
    local sha out rc
    sha="$(git -C "$ws" rev-parse HEAD)"
    out="$(push)"; rc=$?
    probe "$( [ "$rc" != 0 ] && [ "$(published)" = "$clean" ] && pg_has "$out" "${sha:0:12}" "$2" "$3" && echo да || echo нет)" \
        "$1" "код $rc, на «сервере» $(published); вывод: $out"
    git -C "$ws" reset -q --hard "$clean"
}
passes() {  # <метка>
    local out rc
    out="$(push)"; rc=$?
    probe "$( [ "$rc" = 0 ] && [ "$(published)" = "$(git -C "$ws" rev-parse HEAD)" ] && echo да || echo нет)" \
        "$1" "код $rc; вывод: $out"
    clean="$(published)"
}

# ── B. автор подставлен окружением ───────────────────────────────────────────
edit; GIT_AUTHOR_EMAIL="$SESSION" GIT_AUTHOR_NAME=session git -C "$ws" commit -q -m "B"
refused "B автор подставлен окружением: отказ до отправки, названы sha и адрес" "автор" "$SESSION"

# ── C. коммиттер подставлен ──────────────────────────────────────────────────
edit; GIT_COMMITTER_EMAIL="$SESSION" GIT_COMMITTER_NAME=session git -C "$ws" commit -q -m "C"
refused "C коммиттер подставлен: отказ" "коммиттер" "$SESSION"

# ── D. соавтор ───────────────────────────────────────────────────────────────
edit; git -C "$ws" commit -q -m "D" -m "Co-authored-by: Mallory <mallory@push-gate.invalid>"
refused "D соавтор в блоке трейлеров вне ведомости: отказ" "соавтор" "mallory@push-gate.invalid"
edit; git -C "$ws" commit -q -m "D близнец" -m "Правило запрещает строку Co-authored-by: Mallory <mallory@push-gate.invalid> в конце сообщения." -m "Это проза, а не блок трейлеров."
passes "D близнец: то же упоминание в прозе тела — проходит"

# ── E. освобождённая личность ────────────────────────────────────────────────
edit; GIT_AUTHOR_EMAIL="$MACHINE" GIT_AUTHOR_NAME=machine git -C "$ws" commit -q -m "E"
probe "$(trunk_ledger | grep -q "$MACHINE" && echo да || echo нет)" \
    "E предпосылка: адрес $MACHINE ЕСТЬ в ведомости СТВОЛА (waivers) — отказ ниже о правиле, а не об отсутствии"
refused "E освобождённая личность автором отправляемого коммита: отказ" "автор" "$MACHINE"
edit; git -C "$ws" commit -q -m "E2" -m "Co-authored-by: machine <$MACHINE>"
refused "E2 освобождённая личность соавтором — отказ по КЛЮЧУ атрибуции, освобождение его не открывает" "Co-authored-by" "ключ атрибуции"

# ── F. запись адреса — в ведомости ВЕТКИ и в ведомости СТВОЛА ──────────────────
sign_session="signatories:
  - email: $SESSION
    note: принял соглашение — запись пробы F
$WAIVE"
edit; GIT_AUTHOR_EMAIL="$SESSION" GIT_AUTHOR_NAME=session git -C "$ws" commit -q -m "F'"
pg_ledger "$ws" "$sign_session"
refused "F' запись в ведомости НЕ закоммичена — отказ: незакоммиченное состояние отправку не открывает" "автор" "$SESSION"
edit; GIT_AUTHOR_EMAIL="$SESSION" GIT_AUTHOR_NAME=session git -C "$ws" commit -q -m "F"
f_sha="$(git -C "$ws" rev-parse HEAD)"
pg_ledger "$ws" "$sign_session"
git -C "$ws" add contribution-ledger.yaml && git -C "$ws" commit -q -m "F: запись в ведомость ветки"
out="$(push)"; rc=$?
probe "$( [ "$rc" != 0 ] && [ "$(published)" = "$clean" ] && pg_has "$out" "${f_sha:0:12}" "$SESSION" "НЕ действует" "сначала сесть в ствол" && echo да || echo нет)" \
    "F адрес внесён в ведомость ОТПРАВЛЯЕМОЙ ревизии — отказ: изменение круг допущенных не расширяет, лечение — посадка записи в ствол" "код $rc; вывод: $out"
git -C "$ws" reset -q --hard "$clean"
pg_ledger "$ws" "$sign_session"
git -C "$ws" add contribution-ledger.yaml && git -C "$ws" commit -q -m "F: запись сначала — в ствол"
land HEAD
edit; GIT_AUTHOR_EMAIL="$SESSION" GIT_AUTHOR_NAME=session git -C "$ws" commit -q -m "F после посадки записи"
passes "F близнец: та же запись СНАЧАЛА села в ствол — та же отправка проходит"
pg_ledger "$ws" "$WAIVE"
git -C "$ws" add contribution-ledger.yaml && git -C "$ws" commit -q -m "F: запись снята"
passes "F: снятие записи — свой коммит проходит"
land "$clean"

# ── W. две редакции ведомости, ранняя шире; лечение — дословно ────────────────
#
# Находка приёмки круга 3: лечение из отказа переносило в ветку самую раннюю и
# самую широкую редакцию ведомости, и после него коммит адреса «только история»
# уходил на сервер с кодом 0. Здесь каждая напечатанная команда исполняется
# дословно, повторная отправка — через настоящий хук.
git -C "$ws" checkout -q -b w-line "$clean"
pg_ledger "$ws" "  - email: $OLD
    note: ранняя редакция — прежний адрес ещё свой
signatories:
  - email: $STRANGER
    note: ранняя редакция — принял соглашение
$WAIVE"
git -C "$ws" add -A && git -C "$ws" commit -q -m "ведомость: ранняя, широкая"
w_wide="$(git -C "$ws" rev-parse HEAD)"
land "$w_wide"
pg_ledger "$ws" "history_floor:
  commit: $q_base
  note: граница поздней редакции
history_only:
  - email: $OLD
    note: поздняя редакция — прежний адрес только в истории
$WAIVE"
git -C "$ws" add -A && git -C "$ws" commit -q -m "ведомость: поздняя, узкая"
w_narrow="$(git -C "$ws" rev-parse HEAD)"
land "$w_narrow"
probe "$( git --git-dir="$srv" show "$w_wide:contribution-ledger.yaml" | grep -q "$OLD" && ! trunk_ledger | sed -n '/^owners:/,/^[a-z]/p' | grep -q "$OLD" && echo да || echo нет)" \
    "W предпосылка: редакций ведомости в стволе две, ранняя шире ($OLD в её owners), ствол несёт позднюю"
w_try() {  # <ветка> <адрес> <ожидаемая причина> — отказ, лечение дословно, запретного нет
    local b="$1" who="$2" why="$3" out rc cured crc
    git -C "$ws" checkout -q -b "$b" "$w_wide"
    edit; GIT_AUTHOR_EMAIL="$who" GIT_AUTHOR_NAME=x GIT_COMMITTER_EMAIL="$who" GIT_COMMITTER_NAME=x git -C "$ws" commit -q -m "$b: коммит $who"
    out="$( cd "$ws" && git push origin "$b" 2>&1 )"; rc=$?
    probe "$( [ "$rc" != 0 ] && [ -z "$(pg_remote_sha "$box" "$b")" ] && pg_has "$out" "$who" "$why" "ствол main@" && [[ "$out" != *"cherry-pick"* ]] && echo да || echo нет)" \
        "W $b: ветка от ранней широкой редакции, коммит $who — отказ ведомостью ствола, лечение без переноса редакций" "код $rc; вывод: $out"
    cured="$(cure_verbatim "$out")"; crc=$?
    probe "$( [ "$crc" = 0 ] && [ "$(pg_remote_sha "$box" "$b")" = "$(git -C "$ws" rev-parse "$b")" ] && echo да || echo нет)" \
        "W $b: напечатанные команды лечения исполнены ДОСЛОВНО, повторная отправка через хук прошла" "код $crc; напечатано: $(cures "$out"); вывод: $cured"
    probe "$( idents "$srv" "refs/heads/$b" "^$w_narrow" | grep -qx "$who" && echo нет || echo да)" \
        "W $b: после лечения на «сервере» нет ни одного коммита $who" "адреса: $(idents "$srv" "refs/heads/$b" "^$w_narrow" | tr '\n' ' ')"
    git -C "$ws" checkout -q work
}
w_try w-old "$OLD" "вперёд запрет"
w_try w-stranger "$STRANGER" "личности нет в ведомости"
git -C "$ws" checkout -q -b w-own "$w_wide"
edit; git -C "$ws" commit -q -m "w-own: свой коммит"
out="$( cd "$ws" && git push origin w-own 2>&1 )"; rc=$?
probe "$( [ "$rc" = 0 ] && pg_has "$out" "НЕ действует" && echo да || echo нет)" \
    "W близнец: свой коммит на ветке от ранней редакции — проходит, ведомость ветки названа недействующей" "код $rc; вывод: $out"
# Ствол возвращается к ведомости пробы НОВОЙ посадкой поверх поздней редакции, а не
# перемоткой: сервер ствол назад не двигает.
git -C "$ws" checkout -q w-line
pg_ledger "$ws" "$WAIVE"
git -C "$ws" add -A && git -C "$ws" commit -q -m "ведомость пробы — снова в стволе"
land HEAD
probe "$( [ "$(git --git-dir="$srv" rev-parse main)" = "$(git -C "$ws" rev-parse HEAD)" ] && echo да || echo нет)" \
    "W: ствол возвращён к ведомости пробы посадкой (main = $(git -C "$ws" rev-parse --short HEAD))"
git -C "$ws" checkout -q work

# ── T. аннотированный тег судится, как коммит ─────────────────────────────────
t_push() {  # <тег> — настоящая отправка тега; печатает вывод, код — её код
    ( cd "$ws" && git push origin "refs/tags/$1" 2>&1 )
}
GIT_COMMITTER_EMAIL="$SESSION" GIT_COMMITTER_NAME=session git -C "$ws" tag -a tg-foreign -m "выпуск" "$clean"
out="$(t_push tg-foreign)"; rc=$?
probe "$( [ "$rc" != 0 ] && pg_has "$out" "автор тега" "$SESSION" && ! git --git-dir="$srv" rev-parse -q --verify refs/tags/tg-foreign >/dev/null && echo да || echo нет)" \
    "T аннотированный тег на опубликованный коммит, автор тега подставлен — отказ, тега на «сервере» нет" "код $rc; вывод: $out"
git -C "$ws" tag -a tg-attr -m "выпуск" -m "Co-authored-by: Claude <noreply@anthropic.com>" "$clean"
out="$(t_push tg-attr)"; rc=$?
probe "$( [ "$rc" != 0 ] && pg_has "$out" "ключ атрибуции" "Co-authored-by" && echo да || echo нет)" \
    "T ключ атрибуции в сообщении тега — отказ" "код $rc; вывод: $out"
git -C "$ws" tag -a tg-own -m "выпуск" "$clean"
out="$(t_push tg-own)"; rc=$?
probe "$( [ "$rc" = 0 ] && pg_has "$out" "объектов тегов 1" && git --git-dir="$srv" rev-parse -q --verify refs/tags/tg-own >/dev/null && echo да || echo нет)" \
    "T близнец: свой аннотированный тег — судим и проходит" "код $rc; вывод: $out"

# ── G. уже опубликованное не судится повторно ───────────────────────────────
edit; GIT_AUTHOR_EMAIL="$SESSION" GIT_AUTHOR_NAME=session git -C "$ws" commit -q -m "G чужой, отправлен обходом"
( cd "$ws" && git push -q --no-verify origin work 2>/dev/null )
clean="$(published)"
edit; git -C "$ws" commit -q -m "G свой поверх"
passes "G чужой коммит уже на «сервере» — свой поверх него проходит (судится публикуемое)"

# ── H. ведомости нет: в ревизии — судит ствол; в стволе — первая посадка ────────
edit; git -C "$ws" rm -q contribution-ledger.yaml; git -C "$ws" commit -q -m "H ревизия без ведомости"
out="$( cd "$ws" && git push origin HEAD:refs/heads/h-side 2>&1 )"; rc=$?
probe "$( [ "$rc" = 0 ] && pg_has "$out" "публикуемых коммитов 1" "ствол main@" && echo да || echo нет)" \
    "H ревизия БЕЗ ведомости судится ведомостью ствола — свой коммит проходит" "код $rc; вывод: $out"
h_bare="$(git -C "$ws" rev-parse HEAD)"
git -C "$ws" reset -q --hard "$clean"
( cd "$ws" && git push -q --no-verify origin "$h_bare:refs/heads/bare-trunk" 2>/dev/null )
git --git-dir="$srv" symbolic-ref HEAD refs/heads/bare-trunk
out="$( cd "$ws" && git push origin "$clean:refs/tags/h-tag" 2>&1 )"; rc=$?
probe "$( [ "$rc" = 0 ] && pg_has "$out" "публикуемых коммитов 0" && echo да || echo нет)" \
    "H тег на опубликованное при стволе без ведомости — публиковать нечего: проходит без флага" "код $rc; вывод: $out"
edit; git -C "$ws" commit -q -m "H свой при стволе без ведомости"
out="$(push)"; rc=$?
probe "$( [ "$rc" != 0 ] && [ "$(published)" = "$clean" ] && pg_has "$out" "условие не создано" "KACHO_CLA_FIRST_LANDING=1 git push" && echo да || echo нет)" \
    "H ствол без ведомости — отказ «условие не создано», флаг первой посадки назван, «сервер» не сдвинулся" "код $rc; вывод: $out"
cured="$(cure_verbatim "$out")"; crc=$?
probe "$( [ "$crc" = 0 ] && [ "$(published)" = "$(git -C "$ws" rev-parse HEAD)" ] && pg_has "$cured" "узкой форме" && echo да || echo нет)" \
    "H напечатанная отправка с флагом исполнена ДОСЛОВНО — ревизия несёт ведомость, всё своё: проходит в узкой форме" "код $crc; вывод: $cured"
clean="$(published)"
edit; GIT_AUTHOR_EMAIL="$SESSION" GIT_AUTHOR_NAME=session git -C "$ws" commit -q -m "H чужой при стволе без ведомости"
out="$(push)"; rc=$?
cured="$(cure_verbatim "$out")"; crc=$?
probe "$( [ "$crc" != 0 ] && [ "$(published)" = "$clean" ] && pg_has "$cured" "$SESSION" "узкой форме" "личности нет в ведомости" && echo да || echo нет)" \
    "H флаг дословно, чужой коммит — узкая форма его не допускает, «сервер» не сдвинулся" "код $crc; вывод: $cured"
cured2="$(cure_verbatim "$cured")"; crc=$?
probe "$( [ "$crc" = 0 ] && [ "$(published)" = "$(git -C "$ws" rev-parse HEAD)" ] && ! idents "$srv" refs/heads/work "^$clean" | grep -qx "$SESSION" && echo да || echo нет)" \
    "H лечение отказа в узкой форме дословно: переподпись и отправка С ФЛАГОМ проходят, $SESSION на «сервере» нет" "код $crc; напечатано: $(cures "$cured"); вывод: $cured2"
clean="$(published)"
git -C "$ws" reset -q --hard "$clean"
pg_ledger "$ws" "  - email: $SESSION
    note: своя личность, объявленная самой ревизией первой посадки
$WAIVE"
git -C "$ws" add -A && git -C "$ws" commit -q -m "H ведомость ревизии: SESSION в owners"
edit; GIT_AUTHOR_EMAIL="$SESSION" GIT_AUTHOR_NAME=session git -C "$ws" commit -q -m "H SESSION по записи ревизии"
out="$( cd "$ws" && KACHO_CLA_FIRST_LANDING=1 git push origin work 2>&1 )"; rc=$?
probe "$( [ "$rc" != 0 ] && [ "$(published)" = "$clean" ] && pg_has "$out" "$SESSION" "узкую форму" && echo да || echo нет)" \
    "H флаг: owners ревизии шире user.email копии — чужой адрес из owners не допущен" "код $rc; вывод: $out"
git -C "$ws" reset -q --hard "$clean"
git --git-dir="$srv" symbolic-ref HEAD refs/heads/nope
edit; git -C "$ws" commit -q -m "H свой при висящем HEAD"
out="$(push)"; rc=$?
probe "$( [ "$rc" != 0 ] && [ "$(published)" = "$clean" ] && pg_has "$out" "ствола не называет" && echo да || echo нет)" \
    "H сервер не называет HEAD — ствола нет: отказ, а не проход" "код $rc; вывод: $out"
git -C "$ws" reset -q --hard "$clean"
git --git-dir="$srv" symbolic-ref HEAD refs/heads/main

# ── M. разборщика нет — отказ «судить нечем», а не проход ────────────────────
edit; git -C "$ws" rm -q scripts/cla-gate/cla.py; git -C "$ws" commit -q -m "M ревизия без разборщика"
out="$(push)"; rc=$?
probe "$( [ "$rc" != 0 ] && [ "$(published)" = "$clean" ] && pg_has "$out" "судить нечем" "scripts/cla-gate/cla.py" && echo да || echo нет)" \
    "M разборщика нет в рабочем дереве при поданном диапазоне: отказ «судить нечем», «сервер» не сдвинулся" "код $rc; вывод: $out"
git -C "$ws" reset -q --hard "$clean"

# ── K. суждение вынесено быть не может (исход 2) — отказ, а не проход ─────────
#
# Исход 2 разборщика — «условие не создано»: строка отправки не разобрана либо
# git не ответил. Хук вызывается так, как его зовёт git: `$1` — remote, `$2` —
# URL, строки — на stdin. Отказ обязан прийти ИМЕННО от суждения («код 2»):
# проба, покрасневшая от наборов, не доказала бы fail-closed.
z=0000000000000000000000000000000000000000
ghost=1111111111111111111111111111111111111111
for input in "refs/heads/work $ghost refs/heads/work $z" "строка из трёх полей"; do
    out="$( cd "$ws" && printf '%s\n' "$input" | bash scripts/hooks/pre-push origin "$srv" 2>&1 )"; rc=$?
    probe "$( [ "$rc" = 1 ] && pg_has "$out" "условие не создано" "код 2" && echo да || echo нет)" \
        "K исход 2 суждения («$input») — отказ отправки, а не проход" "код $rc; вывод: $out"
done

# ── L. опубликованное — на сервере ОТПРАВКИ, а не в ссылках отслеживания ──────
#
# Ссылка отслеживания — память клона о сервере ВЫБОРКИ, и она бывает устаревшей:
# ветку на сервере сняли, объект собран сборщиком, а `refs/remotes/origin/*` всё
# ещё его называет. Вычитать ею — объявить опубликованным то, чего на сервере нет.
foreign_on() {  # <ссылка на сервере> — чужой коммит, отправленный туда обходом; печатает sha
    edit; GIT_AUTHOR_EMAIL="$SESSION" GIT_AUTHOR_NAME=session git -C "$ws" commit -q -m "чужой → $1"
    ( cd "$ws" && git push -q --no-verify origin "HEAD:refs/heads/$1" 2>/dev/null && git fetch -q origin 2>/dev/null )
    git -C "$ws" rev-parse HEAD
}
judged_foreign() {  # <метка> <sha чужого> <отправка…> — отказ, чужой назван, «сервер» work не сдвинулся
    local label="$1" x="$2" out rc; shift 2
    out="$( cd "$ws" && "$@" 2>&1 )"; rc=$?
    probe "$( [ "$rc" != 0 ] && [ "$(published)" = "$clean" ] && pg_has "$out" "${x:0:12}" "$SESSION" && echo да || echo нет)" \
        "$label" "код $rc; вывод: $out"
}
x="$(foreign_on stale)"
git --git-dir="$srv" update-ref -d refs/heads/stale
git --git-dir="$srv" reflog expire --expire=now --all 2>/dev/null
git --git-dir="$srv" gc -q --prune=now 2>/dev/null
edit; git -C "$ws" commit -q -m "L свой поверх чужого"
probe "$( git -C "$ws" rev-parse -q --verify refs/remotes/origin/stale >/dev/null && ! git --git-dir="$srv" cat-file -e "$x" 2>/dev/null && echo да || echo нет)" \
    "L предпосылка: ссылка отслеживания называет чужой коммит, а на «сервере» его нет"
judged_foreign "L ссылка отслеживания устарела — чужой коммит судится: отказ, назван" "$x" git push origin work
git -C "$ws" reset -q --hard "$clean"
x="$(foreign_on live)"
edit; git -C "$ws" commit -q -m "L близнец: свой поверх чужого"
passes "L близнец: чужой коммит лежит на «сервере» под другой ссылкой — не судится повторно"

# ── P. pushurl: сервер отправки — не сервер выборки ─────────────────────────
srv_b="$box/srvB.git"
git init -q --bare -b main "$srv_b"
( cd "$ws" && git push -q --no-verify "$srv_b" "$clean:refs/heads/main" "$clean:refs/heads/work" 2>/dev/null )
x="$(foreign_on fetch-only)"
edit; git -C "$ws" commit -q -m "P свой поверх"
git -C "$ws" config remote.origin.pushurl "$srv_b"
out="$( cd "$ws" && git push origin work 2>&1 )"; rc=$?
probe "$( [ "$rc" != 0 ] && pg_has "$out" "${x:0:12}" "$SESSION" && ! git --git-dir="$srv_b" cat-file -e "$x" 2>/dev/null && echo да || echo нет)" \
    "P pushurl на другой сервер: коммит, известный лишь серверу выборки, судится — отказ, на сервер отправки не попал" "код $rc; вывод: $out"
( cd "$ws" && git push -q --no-verify "$srv_b" "$x:refs/heads/seed" 2>/dev/null )
out="$( cd "$ws" && git push origin work 2>&1 )"; rc=$?
probe "$( [ "$rc" = 0 ] && [ "$(git --git-dir="$srv_b" rev-parse -q --verify refs/heads/work)" = "$(git -C "$ws" rev-parse HEAD)" ] && echo да || echo нет)" \
    "P близнец: тот же коммит уже на сервере отправки — проходит" "код $rc; вывод: $out"
git -C "$ws" config --unset remote.origin.pushurl
( cd "$ws" && git push -q --no-verify origin work 2>/dev/null )
clean="$(published)"

# ── Q. посадка сервером: коммиттер noreply@github.com ────────────────────────
#
# Схлопывание и слияние на стороне GitHub подписывает коммиттером сервер (ws#700:
# «находкой НЕ является»). Посадка уже на «сервере» — отправка новой ветки по URL
# её не судит. Зеркало, чей ствол посадку ещё не несёт, публикует её заново, и
# решает ведомость СТВОЛА ЗЕРКАЛА: запись `committers` в ведомости ветки её не
# заменяет. Ветка пробы — от чистой истории (`q_base`).
git -C "$ws" checkout -q -b q "$q_base"
edit; GIT_COMMITTER_NAME=GitHub GIT_COMMITTER_EMAIL=noreply@github.com git -C "$ws" commit -q -m "Q посадка (коммиттер — сервер)"
landing="$(git -C "$ws" rev-parse HEAD)"
( cd "$ws" && git push -q --no-verify origin q 2>/dev/null )
edit; git -C "$ws" commit -q -m "Q свой поверх посадки"
out="$( cd "$ws" && git push "$srv" HEAD:refs/heads/feat-url 2>&1 )"; rc=$?
probe "$( [ "$rc" = 0 ] && pg_has "$out" "публикуемых коммитов 1" && [ "$(git --git-dir="$srv" rev-parse -q --verify refs/heads/feat-url)" = "$(git -C "$ws" rev-parse HEAD)" ] && echo да || echo нет)" \
    "Q отправка новой ветки по URL: посадка уже на «сервере» — не судится, публикуемых 1" "код $rc; вывод: $out"
mirror="$box/mirror.git"
git init -q --bare -b main "$mirror"
land "$q_base" "$mirror"
out="$( cd "$ws" && git push "$mirror" q 2>&1 )"; rc=$?
probe "$( [ "$rc" != 0 ] && pg_has "$out" "${landing:0:12}" "коммиттер" "noreply@github.com" && [ -z "$(git --git-dir="$mirror" rev-parse -q --verify refs/heads/q)" ] && echo да || echo нет)" \
    "Q зеркало, чей ствол не несёт committers: посадка с коммиттером-сервером названа, отказ, ветки на зеркале нет" "код $rc; вывод: $out"
CMT="$WAIVE
committers:
  - email: noreply@github.com
    note: сервер подписывает коммиттером посадку (ws#700)"
pg_ledger "$ws" "$CMT"
git -C "$ws" add contribution-ledger.yaml && git -C "$ws" commit -q -m "Q: committers в ведомости ветки"
out="$( cd "$ws" && git push "$mirror" q 2>&1 )"; rc=$?
probe "$( [ "$rc" != 0 ] && pg_has "$out" "${landing:0:12}" "noreply@github.com" "НЕ действует" && [ -z "$(git --git-dir="$mirror" rev-parse -q --verify refs/heads/q)" ] && echo да || echo нет)" \
    "Q' запись committers в ведомости ВЕТКИ ствол зеркала не расширяет — отказ" "код $rc; вывод: $out"
q_cm_blob="$(git -C "$ws" rev-parse HEAD:contribution-ledger.yaml)"
git -C "$ws" checkout -q -b qc "$q_base"
pg_ledger "$ws" "$CMT"
git -C "$ws" add contribution-ledger.yaml && git -C "$ws" commit -q -m "Q: committers — посадка в ствол зеркала"
land HEAD "$mirror"
git -C "$ws" checkout -q q
out="$( cd "$ws" && git push "$mirror" q 2>&1 )"; rc=$?
probe "$( [ "$rc" = 0 ] && [ "$(git --git-dir="$mirror" rev-parse -q --verify refs/heads/q)" = "$(git -C "$ws" rev-parse HEAD)" ] && [ "$(git --git-dir="$mirror" rev-parse main:contribution-ledger.yaml)" = "$q_cm_blob" ] && echo да || echo нет)" \
    "Q запись committers СНАЧАЛА села в ствол зеркала — посадка покрыта, отправка проходит" "код $rc; вывод: $out"
q_clean="$(git -C "$ws" rev-parse HEAD)"
edit; GIT_AUTHOR_NAME=GitHub GIT_AUTHOR_EMAIL=noreply@github.com git -C "$ws" commit -q -m "Q сервер автором"
q_sha="$(git -C "$ws" rev-parse HEAD)"
out="$( cd "$ws" && git push "$mirror" q 2>&1 )"; rc=$?
probe "$( [ "$rc" != 0 ] && pg_has "$out" "${q_sha:0:12}" "автор" "noreply@github.com" "раздел committers" && [ "$(git --git-dir="$mirror" rev-parse -q --verify refs/heads/q)" = "$q_clean" ] && echo да || echo нет)" \
    "Q личность из committers АВТОРОМ отправляемого коммита — отказ: вклад она не подписывает" "код $rc; вывод: $out"
git -C "$ws" checkout -q work
git -C "$ws" reset -q --hard "$clean"

# ── R. ссылка, не публикующая ни одного коммита, ведомости не требует ─────────
#
# Находка приёмки круга 2 (N1): ведомость читалась ДО вычитания опубликованного.
# Тег на коммит, который уже лежит на «сервере», отказывал, если в дереве этого
# коммита ведомости нет либо она негодна по нынешнему разбору. Опубликованный коммит
# не переписывается, поэтому отказ был вечным и обходился только флагом.
git -C "$ws" checkout -q -b r-side "$clean"
edit; git -C "$ws" rm -q contribution-ledger.yaml; git -C "$ws" commit -q -m "R ревизия без ведомости"
r_bare="$(git -C "$ws" rev-parse HEAD)"
edit; printf 'scope: [.]\nowners:\n  - email: %s\n    note: n\nretired_section: []\n' "$PG_OWNER_EMAIL" > "$ws/contribution-ledger.yaml"
git -C "$ws" add -A; git -C "$ws" commit -q -m "R ведомость прежней формы"
r_bad="$(git -C "$ws" rev-parse HEAD)"
( cd "$ws" && git push -q --no-verify origin r-side 2>/dev/null )
git -C "$ws" checkout -q work
tag_passes() {  # <метка> <sha> <тег> — тег на опубликованное: проходит, тег на «сервере»
    local out rc
    out="$( cd "$ws" && git push origin "$2:refs/tags/$3" 2>&1 )"; rc=$?
    probe "$( [ "$rc" = 0 ] && [ "$(git --git-dir="$srv" rev-parse -q --verify "refs/tags/$3")" = "$2" ] && pg_has "$out" "публикуемых коммитов 0" && echo да || echo нет)" \
        "$1" "код $rc; вывод: $out"
}
tag_passes "R тег на опубликованную ревизию БЕЗ ведомости — публиковать нечего: проходит, тег на «сервере»" "$r_bare" r0
tag_passes "R' тег на опубликованную ревизию с ведомостью, негодной по нынешнему разбору, — проходит" "$r_bad" r1
tag_passes "R близнец: тег на опубликованную ревизию с ведомостью — проходит" "$clean" r2

# ── S. ПУСТОЕ зеркало: ствола нет — первая посадка ────────────────────────────
#
# Полномочий нет: отказ «условие не создано» с флагом. Напечатанная отправка с
# флагом исполняется дословно: ревизия без ведомости её не вводит — отказ; ревизия с
# ведомостью, где всё своё, проходит в узкой форме. Ветка — от чистой истории.
git -C "$ws" checkout -q -b s-side "$q_base"
edit; git -C "$ws" rm -q contribution-ledger.yaml; git -C "$ws" commit -q -m "S ревизия без ведомости"
s_bare="$(git -C "$ws" rev-parse HEAD)"
edit; git -C "$ws" checkout -q "$q_base" -- contribution-ledger.yaml; git -C "$ws" add -A; git -C "$ws" commit -q -m "S ведомость возвращена"
s_led="$(git -C "$ws" rev-parse HEAD)"
git -C "$ws" checkout -q work
mirror_s="$box/mirror-s.git"
git init -q --bare -b main "$mirror_s"
out="$( cd "$ws" && git push "$mirror_s" "$s_bare:refs/heads/hist" 2>&1 )"; rc=$?
probe "$( [ "$rc" != 0 ] && pg_has "$out" "условие не создано" "ствола не называет" "KACHO_CLA_FIRST_LANDING=1 git push" && [ -z "$(git --git-dir="$mirror_s" for-each-ref)" ] && echo да || echo нет)" \
    "S ревизия без ведомости в пустое зеркало — условие не создано, флаг назван, зеркало пусто" "код $rc; вывод: $out"
cured="$(cure_verbatim "$out")"; crc=$?
probe "$( [ "$crc" != 0 ] && pg_has "$cured" "лишь ревизию, которая сама вводит ведомость" && [ -z "$(git --git-dir="$mirror_s" for-each-ref)" ] && echo да || echo нет)" \
    "S флаг дословно на ревизии БЕЗ ведомости — отказ: флаг допускает лишь ревизию, вводящую её" "код $crc; вывод: $cured"
out="$( cd "$ws" && git push "$mirror_s" "$s_led:refs/heads/main" 2>&1 )"; rc=$?
cured="$(cure_verbatim "$out")"; crc=$?
probe "$( [ "$rc" != 0 ] && [ "$crc" = 0 ] && [ "$(git --git-dir="$mirror_s" rev-parse -q --verify refs/heads/main)" = "$s_led" ] && pg_has "$cured" "узкой форме" && echo да || echo нет)" \
    "S ревизия с ведомостью, всё своё: отказ без флага, напечатанная отправка с флагом дословно — проходит в узкой форме" "код $rc/$crc; вывод: $cured"

# ── N. строки отправки с задержкой: вызов как у git (с URL) их дожидается ─────
edit; GIT_AUTHOR_EMAIL="$SESSION" GIT_AUTHOR_NAME=session git -C "$ws" commit -q -m "N"
sha="$(git -C "$ws" rev-parse HEAD)"
out="$( cd "$ws" && { sleep 3; printf 'refs/heads/work %s refs/heads/work %s\n' "$sha" "$clean"; } | KACHO_SKIP_PREPUSH=1 bash scripts/hooks/pre-push origin "$srv" 2>&1 )"; rc=$?
probe "$( [ "$rc" = 1 ] && pg_has "$out" "${sha:0:12}" "$SESSION" && echo да || echo нет)" \
    "N строка отправки пришла через 3 с при вызове с URL — судится (отказ), а не «НЕ судились»" "код $rc; вывод: $out"
git -C "$ws" reset -q --hard "$clean"

# ── I. снятие ссылки ─────────────────────────────────────────────────────────
( cd "$ws" && git push -q origin HEAD:refs/heads/doomed 2>/dev/null )
out="$( cd "$ws" && git push origin :refs/heads/doomed 2>&1 )"; rc=$?
probe "$( [ "$rc" = 0 ] && pg_has "$out" "снятий 1" && echo да || echo нет)" \
    "I снятие ссылки: публиковать нечего — проходит и называет снятие" "код $rc; вывод: $out"

# ── J. хук без диапазона ─────────────────────────────────────────────────────
out="$( cd "$ws" && bash scripts/hooks/pre-push origin </dev/null 2>&1 )"; rc=$?
probe "$( [ "$rc" = 0 ] && pg_has "$out" "НЕ судились" && echo да || echo нет)" \
    "J хук без диапазона на stdin: граница названа («НЕ судились»), а не молчание" "код $rc; вывод: $out"

pg_census "$NAME: песочниц с bare-«сервером» $(pg_sandboxes "$TMP"); проб исполнено $probes, провалено $failed (A свой · B автор · C коммиттер · D соавтор/проза · E освобождённый · F/F' ведомость ветки против ствола · W две редакции, лечение дословно · T аннотированный тег · G опубликованное · H ведомости нет в ревизии и в стволе · M разборщика нет · K исход 2 · L ссылка отслеживания · P pushurl · Q посадка сервером · R публиковать нечего · S пустое зеркало · N задержка stdin · I снятие · J без диапазона)"
if [ "$failed" -gt 0 ]; then
    pg_fail "$NAME — проб с находкой: $failed"
    exit 1
fi
pg_pass "$NAME — подпись вне ведомости ствола останавливает отправку до публикации; лечение исполнимо дословно; законные близнецы проходят"
