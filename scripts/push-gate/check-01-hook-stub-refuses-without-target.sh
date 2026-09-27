#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# check-01 — переходник хука, не нашедший адресата, ОТКАЗЫВАЕТ; `check`
# различает «переходник есть» и «адресат исполним» (ws#751, ws#729 пп. 2–3).
#
# ЗАЧЕМ. Переходник прежней редакции без адресата печатал «проверок НЕ БЫЛО» и
# выходил нулём: отправка проходила за три секунды при нуле проверок, а провязка
# выглядела исполненной — файл на месте, права стоят, строка печатается. В этом
# клоне так жил переходник `commit-msg`: скрипта, к которому он вёл, нет ни в
# стволе, ни в ветке, и `check` называл его «посторонним хуком» с кодом 0.
#
# ЧТО ТРЕБУЕТСЯ — поведением, в песочнице с bare-«сервером»:
#   A  адресат есть         → отправка проходит, «сервер» несёт sha, вывод
#                             называет число исполненных наборов и ГРАНИЦУ зелёного;
#   B  адресата нет          → отправка НЕ проходит, «сервер» не сдвинулся, отказ
#                             называет «условие не создано» и обход `--no-verify`;
#   C  тот же случай + явный `--no-verify` → проходит (обход один и явный);
#   D  `check` на клоне с переходником без адресата → отказ, а не «провязано»;
#   E  адресат не исполним   → `check` отказывает и называет оба состояния;
#   F  переходник v1 (успех без адресата) → `check` отказывает, `install` чинит;
#   G  наш переходник под именем без хука в дереве → `check` отказывает,
#                             `install` снимает; чужой хук — не тронут;
#   H  `core.hooksPath` выставлен → `install` отказывает (git пропустил бы
#                             ревизию без хука молча).
# Отрицания B, D–H стоят в паре с положительной A в ТОЙ ЖЕ песочнице: отказ,
# пришедший оттого, что отправка не работает вовсе, пробу A не пройдёт.
set -uo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
NAME="check-01-hook-stub-refuses-without-target"

[ -f "$PG_SUBJECT/scripts/hooks/install.sh" ] || {
    pg_void "$NAME — установщика scripts/hooks/install.sh в дереве нет, судить нечего"; exit 2; }
command -v git >/dev/null || { pg_void "$NAME — git не найден"; exit 2; }

pg_hermetic
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

probes=0; failed=0
probe() {  # <ожидалось: да|нет> <метка> [<пояснение>]
    probes=$((probes + 1))
    if [ "$1" = да ]; then pg_pass "$NAME — $2"; else failed=$((failed + 1)); pg_fail "$NAME — $2${3:+: $3}"; fi
}
is() { [ "$1" = "$2" ] && echo да || echo нет; }

ws="$(pg_sandbox "$TMP/box")" || { pg_void "$NAME — песочница не собралась (git, личность, установщик)"; exit 2; }

# ── A. адресат есть — положительная половина пары ────────────────────────────
sha="$(git -C "$ws" rev-parse HEAD)"
out="$(cd "$ws" && git push -q origin work 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(pg_remote_sha "$TMP/box" work)" = "$sha" ] && ok=да || ok=нет
probe "$ok" "A адресат есть: отправка прошла, «сервер» несёт $sha" "код $rc; вывод: $out"
if [ "$ok" != да ]; then
    pg_void "$NAME — положительная половина не прошла: остальные пробы на этой песочнице недоказательны"
    exit 2
fi
pg_has "$out" "исполнено наборов 1" && ok=да || ok=нет
probe "$ok" "A зелёное называет число исполненных наборов" "вывод: $out"
pg_has "$out" "НЕ проверялось" && ok=да || ok=нет
probe "$ok" "A зелёное несёт объявленную границу — что НЕ проверялось" "вывод: $out"

# ── B. адресата нет — ревизия без хука ───────────────────────────────────────
git -C "$ws" rm -q scripts/hooks/pre-push
git -C "$ws" commit -q -m "ревизия без адресата"
new="$(git -C "$ws" rev-parse HEAD)"
out="$(cd "$ws" && git push -q origin work 2>&1)"; rc=$?
probe "$( [ "$rc" != 0 ] && [ "$(pg_remote_sha "$TMP/box" work)" = "$sha" ] && echo да || echo нет)" \
    "B адресата нет: отправка остановлена, «сервер» остался на $sha" "код $rc, на сервере $(pg_remote_sha "$TMP/box" work)"
pg_has "$out" "условие не создано" "git push --no-verify" && ok=да || ok=нет
probe "$ok" "B отказ называет причину «условие не создано» и явный обход" "вывод: $out"

# ── C. явный обход ───────────────────────────────────────────────────────────
out="$(cd "$ws" && git push -q --no-verify origin work 2>&1)"; rc=$?
probe "$( [ "$rc" = 0 ] && [ "$(pg_remote_sha "$TMP/box" work)" = "$new" ] && echo да || echo нет)" \
    "C --no-verify: обход явный и проходит" "код $rc; вывод: $out"

# ── D. check на клоне с переходником без адресата ───────────────────────────
out="$(cd "$ws" && bash "$PG_SUBJECT/scripts/hooks/install.sh" check 2>&1)"; rc=$?
probe "$( [ "$rc" = 1 ] && pg_has "$out" "pre-push" "без адресата" && echo да || echo нет)" \
    "D check: переходник без адресата — отказ, а не «провязано»" "код $rc; вывод: $out"

# Возвращаем адресата: дальше — состояния провязки на ИСПРАВНОЙ ревизии.
git -C "$ws" checkout -q "$sha" -- scripts/hooks/pre-push
git -C "$ws" commit -q -m "адресат возвращён"
( cd "$ws" && bash scripts/hooks/install.sh install >/dev/null 2>&1 )
out="$(cd "$ws" && bash scripts/hooks/install.sh check 2>&1)"; rc=$?
probe "$(is "$rc" 0)" "D близнец: адресат возвращён — check зелёный" "код $rc; вывод: $out"
probe "$( pg_has "$out" "переходник v2 есть" "адресат исполним" && echo да || echo нет)" \
    "D близнец: check печатает ОБА состояния" "вывод: $out"

# ── E. адресат есть, но не исполним ─────────────────────────────────────────
chmod -x "$ws/scripts/hooks/pre-push"
out="$(cd "$ws" && bash scripts/hooks/install.sh check 2>&1)"; rc=$?
probe "$( [ "$rc" = 1 ] && pg_has "$out" "адресат НЕ исполним" && echo да || echo нет)" \
    "E адресат не исполним: check отказывает и называет состояние" "код $rc; вывод: $out"
out="$(cd "$ws" && git push -q origin HEAD:e-branch 2>&1)"; rc=$?
probe "$( [ "$rc" != 0 ] && [ -z "$(pg_remote_sha "$TMP/box" e-branch)" ] && echo да || echo нет)" \
    "E адресат не исполним: отправка остановлена" "код $rc; вывод: $out"
chmod +x "$ws/scripts/hooks/pre-push"

# ── F. переходник прежней редакции ──────────────────────────────────────────
hooks_dir="$(cd "$ws" && git rev-parse --git-common-dir)/hooks"
case "$hooks_dir" in /*) ;; *) hooks_dir="$ws/$hooks_dir" ;; esac
cat > "$hooks_dir/pre-push" <<'V1'
#!/usr/bin/env bash
# kacho-hook-stub v1
top="$(git rev-parse --show-toplevel 2>/dev/null)" || top="$PWD"
real="$top/scripts/hooks/pre-push"
if [ ! -x "$real" ]; then echo "pre-push: нет $real — проверок НЕ БЫЛО" >&2; exit 0; fi
exec "$real" "$@"
V1
chmod +x "$hooks_dir/pre-push"
out="$(cd "$ws" && bash scripts/hooks/install.sh check 2>&1)"; rc=$?
probe "$( [ "$rc" = 1 ] && pg_has "$out" "v1" && echo да || echo нет)" \
    "F переходник v1: check отказывает и называет редакцию" "код $rc; вывод: $out"
( cd "$ws" && bash scripts/hooks/install.sh install >/dev/null 2>&1 )
probe "$( grep -q 'kacho-hook-stub v2' "$hooks_dir/pre-push" && echo да || echo нет)" \
    "F install заменил v1 на v2"

# ── G. наш переходник без хука в дереве; чужой хук рядом ─────────────────────
sed 's/pre-push/commit-msg/g' "$hooks_dir/pre-push" > "$hooks_dir/commit-msg"
chmod +x "$hooks_dir/commit-msg"
printf '#!/bin/sh\n# свой хук человека, маркера нет\nexit 0\n' > "$hooks_dir/post-commit"
chmod +x "$hooks_dir/post-commit"
out="$(cd "$ws" && bash scripts/hooks/install.sh check 2>&1)"; rc=$?
probe "$( [ "$rc" = 1 ] && pg_has "$out" "commit-msg" "без адресата" && echo да || echo нет)" \
    "G наш переходник без хука в дереве: check отказывает и называет его" "код $rc; вывод: $out"
probe "$( pg_has "$out" "посторонних хуков оставлено нетронутыми: post-commit" && echo да || echo нет)" \
    "G чужой хук назван посторонним, а наш — нет" "вывод: $out"
out="$(cd "$ws" && bash scripts/hooks/install.sh install 2>&1)"; rc=$?
probe "$( [ "$rc" = 0 ] && [ ! -e "$hooks_dir/commit-msg" ] && [ -x "$hooks_dir/post-commit" ] && echo да || echo нет)" \
    "G install снял наш переходник без адресата и не тронул чужой хук" "код $rc; вывод: $out"
out="$(cd "$ws" && bash scripts/hooks/install.sh check 2>&1)"; rc=$?
probe "$(is "$rc" 0)" "G близнец: после провязки check зелёный" "код $rc; вывод: $out"

# ── H. core.hooksPath ────────────────────────────────────────────────────────
git -C "$ws" config core.hooksPath scripts/hooks
out="$(cd "$ws" && bash scripts/hooks/install.sh install 2>&1)"; rc=$?
probe "$( [ "$rc" = 1 ] && pg_has "$out" "core.hooksPath" && echo да || echo нет)" \
    "H core.hooksPath: провязка отказывает с названной причиной" "код $rc; вывод: $out"
git -C "$ws" config --unset core.hooksPath

pg_census "$NAME: песочниц с bare-«сервером» $(pg_sandboxes "$TMP"); проб исполнено $probes, провалено $failed (A адресат есть · B нет · C --no-verify · D check · E не исполним · F v1 · G без хука в дереве · H core.hooksPath)"
if [ "$failed" -gt 0 ]; then
    pg_fail "$NAME — проб с находкой: $failed"
    exit 1
fi
pg_pass "$NAME — переходник без адресата отказывает, обход явный, check различает оба состояния"
