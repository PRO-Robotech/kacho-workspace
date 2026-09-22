#!/usr/bin/env bash
# check-09 — ОТСЛЕЖИВАЕМЫЕ НАСТРОЙКИ НЕ НЕСУТ ОБХОДА ПОДТВЕРЖДЕНИЙ.
#
# Предмет: `.claude/settings.json` едет в репозиторий, и блок `permissions` с
# `defaultMode: bypassPermissions` — выбор про ОДНУ машину, принятый за каждого,
# кто сделает клон. Место такого выбора — `.claude/settings.local.json`, который
# git игнорирует (норма `ai-tooling.md` §«Оснастка: экземпляр, счёт правил и
# доставка до агента», запись `at-settings-without-permissions`).
#
# ПОЧЕМУ ГЕЙТ, А НЕ АБЗАЦ. Держателем нормы стояло «вниманием», и норма
# нарушилась: на 2026-09-20 ствол нёс `"permissions": {"defaultMode":
# "bypassPermissions"}` — опись сама помечала запись «КАНДИДАТ НА ГЕЙТ». Разрыв не
# проявляется ничем: дифф безобиден, прогон зелен, а свежий клон получает режим
# без подтверждений.
#
# ЧИТАЕТСЯ ДЕРЕВО, А НЕ `HEAD`. Предикат нормы (`git show HEAD:… | grep -c`)
# выносит вердикт ПОСЛЕ коммита; дерево судится ДО, и хук отправки ловит правку
# раньше, чем она уедет. Вердикт — в КОДЕ ВЫХОДА: 0 молчит, 1 находка, 2 отказ.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

S=".claude/settings.json"
L=".claude/settings.local.json"

if [ ! -f "$S" ]; then
  printf 'ОТКАЗ — нет %s: предмет отсутствует, судить обход подтверждений не в чем\n' "$S"
  exit 2
fi
if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$S" 2> /dev/null; then
  printf 'ОТКАЗ — %s не разбирается как JSON: вердикт был бы о форме, не о предмете\n' "$S"
  exit 2
fi

rc=0

# ── ось A: блок permissions в отслеживаемых настройках ───────────────────────
if python3 -c 'import json,sys; sys.exit(0 if "permissions" in json.load(open(sys.argv[1])) else 1)' "$S"; then
  printf 'КРАСНОЕ %s несёт блок permissions — его место в %s (git игнорирует)\n' "$S" "$L"
  rc=1
fi

# ── ось B: обход назван где угодно в файле, не только в своём блоке ──────────
if grep -q 'bypassPermissions' "$S"; then
  printf 'КРАСНОЕ %s называет bypassPermissions — обход принят за каждого, кто сделает клон\n' "$S"
  rc=1
fi

# ── ось C: локальные настройки существуют и НЕ игнорируются ──────────────────
# Дом выбора назван нормой; дом, который git отслеживает, домом не является.
if [ -f "$L" ] && ! git check-ignore -q "$L"; then
  printf 'КРАСНОЕ %s существует и НЕ игнорируется git — локальный выбор уедет в репозиторий\n' "$L"
  rc=1
fi

printf 'осмотрено: %s (ключей %s); локальные настройки %s\n' "$S" \
  "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$S")" \
  "$([ -f "$L" ] && echo 'есть, игнорируются' || echo 'нет')"
exit "$rc"
