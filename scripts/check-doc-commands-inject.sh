#!/usr/bin/env bash
# Доказательство ИНЪЕКЦИЕЙ для `check-doc-commands.py` — в обе стороны и с третьим
# исходом.
#
# Гейт, чью работоспособность не доказали, отчитывается одинаково и когда всё
# хорошо, и когда он сломан: «цитат не нашлось» печатается тем же успехом, что и
# «все цитаты исполнимы». Поэтому спрашивается всё три:
#   (+) цитата цели, которой в Makefile нет → КРАСНЫЙ и НАЗЫВАЕТ координату;
#   (−) законная цитата той же формы (та же строка, живая цель) → МОЛЧИТ;
#   (∅) документов без единой цитаты → VOID (код 2), а не успех;
#   (∅∅) дерева продукта нет вовсе → VOID (код 2) со строкой [VOID], а не код
#        находки (ws#463): «условие не создано» — не находка о документах;
#   (≡) дерево продукта названо `KACHO_MONOREPO` — тем же порядком, что у
#        наборов (`scripts/docs-gate/_lib.py`, функция `monorepo`): второго
#        способа найти дерево продукта в одном репозитории нет.
#
# Дерево пробы строится ВОКРУГ СКРИПТА: без переопределения корня он выводит его
# из расположения (общий резолвер наборов `scripts/lib/gate_root.py`, ws#816),
# поэтому копия скрипта в `<врем>/scripts/` смотрит на `<врем>/docs` и
# `<врем>/project/kacho`. Переопределения корня (`DOCS_GATE_ROOT`, `GATE_ROOT`) —
# контракт наборов, а не ручка этой пробы: здесь они сняты, а то, что гейт как
# проверка набора их читает, доказывает `scripts/docs-gate/inject-09.sh`.
#
# Запуск: bash scripts/check-doc-commands-inject.sh   (код 0 — все три сошлись)
#
# shellcheck disable=SC2016
# Одинарные кавычки в телах проб — НАМЕРЕННЫЕ и снимать их нельзя: тело пробы
# состоит из цитаты в обратных кавычках, а в двойных кавычках оболочка исполнила
# бы её как подстановку команды. Цитата ушла бы в гейт уже без команды, и проба
# осталась бы зелёной, ничего не проверив.
set -uo pipefail

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$WS/scripts/check-doc-commands.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0

# Основание пробы — настоящий Makefile с настоящей целью: выдуманное основание
# доказывало бы лишь, что скрипт совпадает сам с собой.
# Резолвер дерева продукта — общий с наборами (`scripts/docs-gate/_lib.py`), и
# копия гейта берёт его рядом с собой, как в настоящем дереве.
mkdir -p "$TMP/scripts/docs-gate" "$TMP/scripts/lib" "$TMP/docs"
cp "$GATE" "$TMP/scripts/"
cp "$WS/scripts/docs-gate/_lib.py" "$TMP/scripts/docs-gate/"
cp "$WS/scripts/lib/gate_root.py" "$TMP/scripts/lib/"

run_gate() { env -u KACHO_MONOREPO -u DOCS_GATE_ROOT -u GATE_ROOT python3 "$TMP/scripts/$(basename "$GATE")" 2>&1; }

echo "== check-doc-commands: инъекция =="

# (∅∅) дерева продукта нет — «условие не создано», код 2 и [VOID], а не 1
printf 'Поднять стенд — `make -C deploy dev-up`.\n' > "$TMP/docs/legit.md"
out="$(run_gate)"; rc=$?
if [ "$rc" -eq 2 ] && grep -qF '[VOID]' <<<"$out"; then
  echo "  ✔ (∅∅) дерева продукта нет — VOID (код 2), а не код находки"; PASS=$((PASS+1))
else
  echo "  ✘ (∅∅) без дерева продукта код $rc — «не создано условие» пришло кодом находки либо без [VOID]"; FAIL=$((FAIL+1))
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# (≡) дерево продукта названо KACHO_MONOREPO и лежит вне корня — находится
alt="$TMP/elsewhere/kacho"
mkdir -p "$alt/deploy"; git -C "$alt" init -q
printf 'dev-up:\n\t@true\n' > "$alt/deploy/Makefile"
out="$(env -u DOCS_GATE_ROOT -u GATE_ROOT KACHO_MONOREPO="$alt" python3 "$TMP/scripts/$(basename "$GATE")" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qE 'all 1 make citations' <<<"$out"; then
  echo "  ✔ (≡) KACHO_MONOREPO читается тем же порядком, что у наборов"; PASS=$((PASS+1))
else
  echo "  ✘ (≡) KACHO_MONOREPO не прочитан (код $rc)"; FAIL=$((FAIL+1))
  printf '%s\n' "$out" | sed 's/^/      /'
fi
rm -f "$TMP/docs/legit.md"

# Основание остальных проб — клон на обычном месте `project/kacho`. `.git` —
# признак клона у общего резолвера: каталог без него деревом продукта не считается.
mkdir -p "$TMP/project/kacho/deploy"; git -C "$TMP/project/kacho" init -q
printf 'dev-up:\n\t@true\n' > "$TMP/project/kacho/deploy/Makefile"

# (∅) предмета нет — VOID, а не «чисто»
out="$(run_gate)"; rc=$?
if [ "$rc" -eq 2 ] && grep -qF 'VOID' <<<"$out"; then
  echo "  ✔ (∅) ноль цитат — VOID (код 2), а не успех"; PASS=$((PASS+1))
else
  echo "  ✘ (∅) ноль цитат прочитался как успех (код $rc) — гейт без предмета неотличим от чистого"; FAIL=$((FAIL+1))
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# (−) законная цитата той же формы
printf 'Поднять стенд — `make -C deploy dev-up`.\n' > "$TMP/docs/legit.md"
out="$(run_gate)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qE 'all 1 make citations' <<<"$out"; then
  echo "  ✔ (−) законная цитата той же формы — молчит, и число цитат названо"; PASS=$((PASS+1))
else
  echo "  ✘ (−) ЛОЖНЫЙ СРАБАТ на законной цитате (код $rc)"; FAIL=$((FAIL+1))
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# (+) цитата цели, которой нет — на ОДНОЙ строке с законной, чтобы различал не
# файл, а сама цель
printf 'Поднять стенд — `make -C deploy dev-up`; полнота — `make -C deploy no-such-target`.\n' \
  > "$TMP/docs/broken.md"
out="$(run_gate)"; rc=$?
if [ "$rc" -eq 1 ] && grep -qF 'no-such-target' <<<"$out" && grep -qE 'docs/broken\.md:1' <<<"$out"; then
  echo "  ✔ (+) цитата несуществующей цели — краснеет и называет координату"; PASS=$((PASS+1))
else
  echo "  ✘ (+) цитата несуществующей цели прошла (код $rc)"; FAIL=$((FAIL+1))
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# Перепись обязана печататься и на красном прогоне — иначе разбор упавшего гейта
# начинается с вопроса «а он вообще что-нибудь прочитал».
if grep -qE 'census: документов прочитано [0-9]+, цитат make рассмотрено [0-9]+' <<<"$out"; then
  echo "  ✔ перепись напечатана и на красном прогоне"; PASS=$((PASS+1))
else
  echo "  ✘ на красном прогоне нет переписи — объём осмотренного неизвестен"; FAIL=$((FAIL+1))
fi

echo "══ инъекций: $((PASS+FAIL)) · сошлось: $PASS · разошлось: $FAIL ══"
[ "$FAIL" -eq 0 ]
