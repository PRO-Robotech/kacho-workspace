#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# check-02 — хук отправки судит ОТПРАВЛЯЕМЫЙ ДИАПАЗОН против ведомости
# `contribution-ledger.yaml` ДО отправки (ws#729 пп. 1, 4, 5; ws#700).
#
# ЗАЧЕМ. Подпись коммита разъезжалась посреди сессии: адрес окружения сильнее
# настройки копии, `git config user.email` отвечал «норма», а коммит уходил
# чужим адресом. Ловил это только гейт соглашения на стороне сервера — после
# отправки, где цена — перезапись опубликованного.
#
# ЧТО ТРЕБУЕТСЯ — поведением, в песочнице с bare-«сервером»; настройка копии в
# каждой пробе ВЕРНА (владелец), подменяется только окружение коммита:
#   A  свой коммит                          → отправка проходит, объём назван;
#   B  автор подставлен окружением          → отказ: sha, адрес, роль; «сервер» не сдвинулся;
#   C  коммиттер подставлен                 → отказ, роль «коммиттер»;
#   D  соавтор в блоке трейлеров вне ведомости → отказ, роль «соавтор»;
#      близнец: то же упоминание в прозе тела → проходит;
#   E  освобождённая личность автором       → отказ (освобождение — вопрос
#      соглашения, а не подписи); она же соавтором → отказ по ключу атрибуции;
#   F  та же отправка B после записи адреса в ведомость → проходит: хук читает
#      ТУ ведомость, второго перечня нет;
#   G  чужой коммит уже на «сервере» (обход --no-verify) → свой поверх него
#      проходит: судится то, что отправка опубликует, а не вся история;
#   H  ведомости нет при поданном диапазоне → отказ «судить нечем» (fail-closed);
#   K  суждение не вынесено (исход 2: sha нет в клоне, строка не разобрана) → отказ;
#   I  снятие ссылки                        → проходит, публиковать нечего;
#   J  хук без диапазона на stdin (не из git push) → говорит «НЕ судились», а не молчит.
set -uo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
NAME="check-02-push-range-judges-identities"

[ -f "$PG_SUBJECT/scripts/hooks/pre-push" ] || { pg_void "$NAME — хука scripts/hooks/pre-push нет"; exit 2; }
[ -f "$PG_SUBJECT/scripts/cla-gate/cla.py" ] || { pg_void "$NAME — разборщика scripts/cla-gate/cla.py нет"; exit 2; }
command -v python3 >/dev/null || { pg_void "$NAME — python3 не найден"; exit 2; }

pg_hermetic
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

probes=0; failed=0
probe() {  # <да|нет> <метка> [<пояснение>]
    probes=$((probes + 1))
    if [ "$1" = да ]; then pg_pass "$NAME — $2"; else failed=$((failed + 1)); pg_fail "$NAME — $2${3:+: $3}"; fi
}

box="$TMP/box"
ws="$(pg_sandbox "$box")" || { pg_void "$NAME — песочница не собралась"; exit 2; }
SESSION="session@push-gate.invalid"
MACHINE="machine@push-gate.invalid"
# Ведомость пробы ЗАКОММИЧЕНА: отказы ниже откатывают клон `reset --hard`, и
# незакоммиченная запись пропадала бы вместе с ними — проба E проходила бы тогда
# по неверной причине (адреса нет вовсе, а не «освобождение не подписывает»).
pg_ledger "$ws" "waivers:
  - email: $MACHINE
    note: машинная личность песочницы"
git -C "$ws" add contribution-ledger.yaml && git -C "$ws" commit -q -m "ведомость пробы"

edit() { echo "$RANDOM$RANDOM" >> "$ws/f.txt"; git -C "$ws" add -A; }
push() { ( cd "$ws" && git push origin work 2>&1 ); }
published() { pg_remote_sha "$box" work; }

# ── A. свой коммит ───────────────────────────────────────────────────────────
out="$(push)"; rc=$?
probe "$( [ "$rc" = 0 ] && [ "$(published)" = "$(git -C "$ws" rev-parse HEAD)" ] && pg_has "$out" "публикуемых коммитов 2" && echo да || echo нет)" \
    "A свой коммит: отправка прошла, объём назван" "код $rc; вывод: $out"
if [ "$rc" != 0 ]; then
    pg_void "$NAME — положительная половина не прошла: отказы ниже были бы недоказательны"; exit 2
fi
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
probe "$(grep -q "$MACHINE" "$ws/contribution-ledger.yaml" && echo да || echo нет)" \
    "E предпосылка: адрес $MACHINE ЕСТЬ в ведомости (waivers) — отказ ниже о правиле, а не об отсутствии"
refused "E освобождённая личность автором отправляемого коммита: отказ" "автор" "$MACHINE"
# Прежде здесь стоял близнец «та же личность соавтором проходит». Он снят вместе
# со свойством: трейлер атрибуции — отказ ПО КЛЮЧУ, независимо от ведомости, и
# освобождение адреса его не открывает (находка приёмки E2g, gi-no-attribution-trailers).
edit; git -C "$ws" commit -q -m "E2" -m "Co-authored-by: machine <$MACHINE>"
refused "E2 освобождённая личность соавтором — отказ по КЛЮЧУ атрибуции, освобождение его не открывает" "Co-authored-by" "ключ атрибуции"

# ── F. та же ведомость ───────────────────────────────────────────────────────
edit; GIT_AUTHOR_EMAIL="$SESSION" GIT_AUTHOR_NAME=session git -C "$ws" commit -q -m "F"
pg_ledger "$ws" "signatories:
  - email: $SESSION
    note: принял соглашение — запись пробы F
waivers:
  - email: $MACHINE
    note: машинная личность песочницы"
passes "F адрес внесён в ведомость дерева — та же отправка проходит: хук читает ЕЁ"
pg_ledger "$ws" "waivers:
  - email: $MACHINE
    note: машинная личность песочницы"

# ── G. уже опубликованное не судится повторно ───────────────────────────────
edit; GIT_AUTHOR_EMAIL="$SESSION" GIT_AUTHOR_NAME=session git -C "$ws" commit -q -m "G чужой, отправлен обходом"
( cd "$ws" && git push -q --no-verify origin work 2>/dev/null )
clean="$(published)"
edit; git -C "$ws" commit -q -m "G свой поверх"
passes "G чужой коммит уже на «сервере» — свой поверх него проходит (судится публикуемое)"

# ── H. ведомости нет ─────────────────────────────────────────────────────────
edit; git -C "$ws" rm -q contribution-ledger.yaml; git -C "$ws" commit -q -m "H ревизия без ведомости"
out="$(push)"; rc=$?
probe "$( [ "$rc" != 0 ] && [ "$(published)" = "$clean" ] && pg_has "$out" "ведомости contribution-ledger.yaml в дереве нет" "ОТКАЗ" && echo да || echo нет)" \
    "H ведомости нет при поданном диапазоне: отказ «судить нечем», а не проход" "код $rc; вывод: $out"
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
    out="$( cd "$ws" && printf '%s\n' "$input" | bash scripts/hooks/pre-push origin "$box/srv.git" 2>&1 )"; rc=$?
    probe "$( [ "$rc" = 1 ] && pg_has "$out" "условие не создано" "код 2" && echo да || echo нет)" \
        "K исход 2 суждения («$input») — отказ отправки, а не проход" "код $rc; вывод: $out"
done

# ── I. снятие ссылки ─────────────────────────────────────────────────────────
( cd "$ws" && git push -q origin HEAD:refs/heads/doomed 2>/dev/null )
out="$( cd "$ws" && git push origin :refs/heads/doomed 2>&1 )"; rc=$?
probe "$( [ "$rc" = 0 ] && pg_has "$out" "снятий 1" && echo да || echo нет)" \
    "I снятие ссылки: публиковать нечего — проходит и называет снятие" "код $rc; вывод: $out"

# ── J. хук без диапазона ─────────────────────────────────────────────────────
out="$( cd "$ws" && bash scripts/hooks/pre-push origin </dev/null 2>&1 )"; rc=$?
probe "$( [ "$rc" = 0 ] && pg_has "$out" "НЕ судились" && echo да || echo нет)" \
    "J хук без диапазона на stdin: граница названа («НЕ судились»), а не молчание" "код $rc; вывод: $out"

pg_census "$NAME: песочница с bare-«сервером» 1; проб исполнено $probes, провалено $failed (A свой · B автор · C коммиттер · D соавтор/проза · E освобождённый · F та же ведомость · G опубликованное · H ведомости нет · K исход 2 · I снятие · J без диапазона)"
if [ "$failed" -gt 0 ]; then
    pg_fail "$NAME — проб с находкой: $failed"
    exit 1
fi
pg_pass "$NAME — подпись вне ведомости останавливает отправку до публикации; законные близнецы проходят"
