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
#   F  та же отправка B, адрес записан в ведомость ОТПРАВЛЯЕМОЙ ревизии → проходит:
#      хук читает ТУ ведомость, второго перечня нет;
#   F' та же запись, но НЕ закоммичена → отказ: незакоммиченное состояние рабочего
#      дерева отправку не открывает (обход один — --no-verify);
#   G  чужой коммит уже на «сервере» (обход --no-verify) → свой поверх него
#      проходит: судится то, что отправка опубликует, а не вся история;
#   H  ведомости нет при поданном диапазоне → отказ «судить нечем» (fail-closed);
#   M  разборщика нет в рабочем дереве → отказ «судить нечем» (fail-closed);
#   K  суждение не вынесено (исход 2: sha нет в клоне, строка не разобрана) → отказ;
#   L  опубликованное — то, что лежит на сервере ОТПРАВКИ: ссылка отслеживания,
#      пережившая снятие ветки на сервере, чужой коммит не вычитает → отказ;
#      близнец — тот же коммит на сервере под другой ссылкой → проходит;
#   P  pushurl ведёт на другой сервер: коммит, известный лишь серверу выборки,
#      судится → отказ; близнец — он же на сервере отправки → проходит;
#   Q  посадка сервером (коммиттер noreply@github.com) уже на «сервере»: новая ветка
#      по URL проходит (вычитается опубликованное на нём); отправка в пустое
#      зеркало проходит, когда ведомость ревизии объявляет эту личность в
#      `committers`, и отказывает без записи; та же личность автором — отказ;
#   N  строки отправки пришли с задержкой, вызов с URL (как зовёт git) → судятся;
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
q_base="$(git -C "$ws" rev-parse HEAD)"   # чистая история для пробы Q: ни одного чужого коммита

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

# ── F. та же ведомость — ЗАКОММИЧЕННАЯ в отправляемой ревизии ─────────────────
#
# Отправляемый диапазон несёт запись о личности сам: судит ведомость ревизии,
# которую отправка публикует. Незакоммиченная правка рабочего дерева (F') —
# неявный обход помимо объявленного `--no-verify`, и отправку она не открывает.
sign_session="signatories:
  - email: $SESSION
    note: принял соглашение — запись пробы F
waivers:
  - email: $MACHINE
    note: машинная личность песочницы"
edit; GIT_AUTHOR_EMAIL="$SESSION" GIT_AUTHOR_NAME=session git -C "$ws" commit -q -m "F'"
pg_ledger "$ws" "$sign_session"
refused "F' запись в ведомости НЕ закоммичена — отказ: незакоммиченное состояние отправку не открывает" "автор" "$SESSION"
edit; GIT_AUTHOR_EMAIL="$SESSION" GIT_AUTHOR_NAME=session git -C "$ws" commit -q -m "F"
pg_ledger "$ws" "$sign_session"
git -C "$ws" add contribution-ledger.yaml && git -C "$ws" commit -q -m "F: запись в ведомость"
passes "F адрес внесён в ведомость отправляемой ревизии — та же отправка проходит: хук читает ЕЁ"
pg_ledger "$ws" "waivers:
  - email: $MACHINE
    note: машинная личность песочницы"
git -C "$ws" add contribution-ledger.yaml && git -C "$ws" commit -q -m "F: запись снята"

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
    out="$( cd "$ws" && printf '%s\n' "$input" | bash scripts/hooks/pre-push origin "$box/srv.git" 2>&1 )"; rc=$?
    probe "$( [ "$rc" = 1 ] && pg_has "$out" "условие не создано" "код 2" && echo да || echo нет)" \
        "K исход 2 суждения («$input») — отказ отправки, а не проход" "код $rc; вывод: $out"
done

# ── L. опубликованное — на сервере ОТПРАВКИ, а не в ссылках отслеживания ──────
#
# Ссылка отслеживания — память клона о сервере ВЫБОРКИ, и она бывает устаревшей:
# ветку на сервере сняли, объект собран сборщиком, а `refs/remotes/origin/*` всё
# ещё его называет. Вычитать ею — объявить опубликованным то, чего на сервере нет.
srv="$box/srv.git"
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
git init -q --bare "$srv_b"
( cd "$ws" && git push -q --no-verify "$srv_b" "$clean:refs/heads/work" 2>/dev/null )
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
# её не судит; отправка в пустое зеркало публикует её заново, и тогда решает
# ведомость ревизии: `committers` — личности, допустимые ТОЛЬКО коммиттером.
# Ветка пробы — от чистой истории: в `work` к этому месту лежат чужие коммиты,
# отправленные обходом (G, L, P), и зеркало законно отказало бы на них.
git -C "$ws" checkout -q -b q "$q_base"
edit; GIT_COMMITTER_NAME=GitHub GIT_COMMITTER_EMAIL=noreply@github.com git -C "$ws" commit -q -m "Q посадка (коммиттер — сервер)"
landing="$(git -C "$ws" rev-parse HEAD)"
( cd "$ws" && git push -q --no-verify origin q 2>/dev/null )
edit; git -C "$ws" commit -q -m "Q свой поверх посадки"
out="$( cd "$ws" && git push "$srv" HEAD:refs/heads/feat-url 2>&1 )"; rc=$?
probe "$( [ "$rc" = 0 ] && pg_has "$out" "публикуемых коммитов 1" && [ "$(git --git-dir="$srv" rev-parse -q --verify refs/heads/feat-url)" = "$(git -C "$ws" rev-parse HEAD)" ] && echo да || echo нет)" \
    "Q отправка новой ветки по URL: посадка уже на «сервере» — не судится, публикуемых 1" "код $rc; вывод: $out"
git init -q --bare "$box/mirror.git"
out="$( cd "$ws" && git push "$box/mirror.git" q 2>&1 )"; rc=$?
probe "$( [ "$rc" != 0 ] && pg_has "$out" "${landing:0:12}" "коммиттер" "noreply@github.com" && [ -z "$(git --git-dir="$box/mirror.git" rev-parse -q --verify refs/heads/q)" ] && echo да || echo нет)" \
    "Q близнец-отказ: зеркало без записи committers — посадка с коммиттером-сервером названа, зеркало пусто" "код $rc; вывод: $out"
pg_ledger "$ws" "waivers:
  - email: $MACHINE
    note: машинная личность песочницы
committers:
  - email: noreply@github.com
    note: сервер подписывает коммиттером посадку (ws#700)"
git -C "$ws" add contribution-ledger.yaml && git -C "$ws" commit -q -m "Q: committers в ведомости"
out="$( cd "$ws" && git push "$box/mirror.git" q 2>&1 )"; rc=$?
probe "$( [ "$rc" = 0 ] && [ "$(git --git-dir="$box/mirror.git" rev-parse -q --verify refs/heads/q)" = "$(git -C "$ws" rev-parse HEAD)" ] && echo да || echo нет)" \
    "Q отправка в пустое зеркало: посадка покрыта записью committers ревизии — проходит" "код $rc; вывод: $out"
q_clean="$(git -C "$ws" rev-parse HEAD)"
edit; GIT_AUTHOR_NAME=GitHub GIT_AUTHOR_EMAIL=noreply@github.com git -C "$ws" commit -q -m "Q сервер автором"
q_sha="$(git -C "$ws" rev-parse HEAD)"
out="$( cd "$ws" && git push "$box/mirror.git" q 2>&1 )"; rc=$?
probe "$( [ "$rc" != 0 ] && pg_has "$out" "${q_sha:0:12}" "автор" "noreply@github.com" "раздел committers" && [ "$(git --git-dir="$box/mirror.git" rev-parse -q --verify refs/heads/q)" = "$q_clean" ] && echo да || echo нет)" \
    "Q личность из committers АВТОРОМ отправляемого коммита — отказ: вклад она не подписывает" "код $rc; вывод: $out"
git -C "$ws" checkout -q work
git -C "$ws" reset -q --hard "$clean"

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

pg_census "$NAME: песочниц с bare-«сервером» $(pg_sandboxes "$TMP"); проб исполнено $probes, провалено $failed (A свой · B автор · C коммиттер · D соавтор/проза · E освобождённый · F/F' ведомость ревизии · G опубликованное · H ведомости нет · M разборщика нет · K исход 2 · L ссылка отслеживания · P pushurl · Q посадка сервером · N задержка stdin · I снятие · J без диапазона)"
if [ "$failed" -gt 0 ]; then
    pg_fail "$NAME — проб с находкой: $failed"
    exit 1
fi
pg_pass "$NAME — подпись вне ведомости останавливает отправку до публикации; законные близнецы проходят"
