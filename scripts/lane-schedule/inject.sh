#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# inject.sh — доказательство, что `lane-schedule.py` СПОСОБЕН отказать, способен
# отличить пустой обход от расчёта и считает известный пример ТОЧНО.
#
# Входы СИНТЕТИЧЕСКИЕ (маршрут работ реальной под-фазы меняется от захода к
# заходу, и пример с известным ответом на нём не построить). Каждая ось меняет
# ОДИН факт против законного близнеца. Пример «известный путь» посчитан руками:
#
#   9001: B2 proto-sync corelib+kacho S │ B1 docs-writer kacho S │ A1←B1,B2 M,
#         A2←A1 M, A3←A2 L, A4←A3 S (go-implementer kacho) │ D1←A4 диспетчер
#   9002: X1 go-implementer L │ X2←X1 migration-writer L │ X3←X2,Е1 docs-writer S
#   S=15 M=25 L=45, ревью 25 на пакет.
#   Цепочка A1+A2+A3 = 4 единицы (предел), A4 — отдельным пакетом: 40+120+40 = 200.
#   literal склеивает X3 с B1 (однотипные, независимые): 70+70+55+120+40 = 355.
#   guard эту склейку отвергает: путь остаётся 200.
#   B (9002 Е1 → 9001): X3 ждёт всю 9001 — 200+40 = 240.
#   Слотов 2 → 220; путь достигается с 3 слотов.
#
#   K1 guard A        → код 0, путь 200, пакетов 8, 2 слота 220, минимум 3
#   K2 цепочка        → A1+A2+A3 одним пакетом, A4 — отдельным (предел 4 единицы)
#   K3 literal A      → путь 355 (склейка удлиняет путь — то, что guard запрещает)
#   K4 guard B        → путь 240 (смысловое ребро удлиняет срок)
#   C1 цикл явных рёбер           → код 1, путь цикла назван
#   C2 цикл только раскрытием стадии → код 0 (близнец C1), снятое ребро названо
#   E1 ноль полос в разделе       → код 2, не «срок 0»
#   E2 ноль файлов                → код 2
#   E3 ведомость без строк        → код 2
#   R1 строка ведомости без носителя → код 1
#   R2 строка таблицы не той ширины  → код 1 с координатой
#   R3 B без ведомости            → код 1
#   R4 повтор id полосы           → код 1
#   R5 нет раздела «Полосы»       → код 1
# shellcheck disable=SC2016  # обратные кавычки в строках таблиц — разметка tasks.md, не подстановка
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tool="$here/lane-schedule.py"
box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT

pass=0; fail=0
ok()  { pass=$((pass + 1)); printf 'ПРОЙДЕНО %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'ПРОВАЛЕНО %s — %s\n' "$1" "$2"; }

HDR='| № | полоса | исполнитель | репозиторий · пути | зависит от | размер |
|---|---|---|---|---|---|'

# task <под-фаза> <строки таблицы…> — tasks.md в каталоге issue-<под-фаза>.
task() {
  local n=$1; shift
  mkdir -p "$box/issue-$n"
  {
    printf '# маршрут %s\n\n## 1. Внешние зависимости\n\nЕ1 — соседняя под-фаза на стенде.\n\n' "$n"
    printf '## 2. Полосы\n\n### Ярус 1 — S1\n\n%s\n' "$HDR"
    printf '%s\n' "$@"
    printf '\n## 3. Порядок по времени\n\n| шаг | полоса |\n|---|---|\n| 1 | Z9 |\n'
  } > "$box/issue-$n/tasks.md"
  echo "$box/issue-$n/tasks.md"
}

# run <метка> <ожидаемый код> <аргументы…> — вывод в $box/<метка>.out
run() {
  local label=$1 want=$2; shift 2
  python3 "$tool" "$@" > "$box/$label.out" 2>&1
  local rc=$?
  if [ "$rc" -ne "$want" ]; then
    bad "$label" "код $rc, ожидался $want; вывод: $(head -3 "$box/$label.out" | tr '\n' ' ')"
    return 1
  fi
  return 0
}

has() {  # has <метка> <подстрока> <что утверждается>
  if grep -qF -- "$2" "$box/$1.out"; then ok "$1: $3"; else bad "$1" "нет «$2» ($3)"; fi
}

t1=$(task 9001 \
  '| B2 | контракт | `proto-sync` | corelib · proto; kacho · proto | — | S |' \
  '| B1 | страница | `docs-writer` | kacho · docs | — | S |' \
  '| A1 | звено 1 | `go-implementer` | kacho · a | B1, B2 | M |' \
  '| A2 | звено 2 | `go-implementer` | kacho · a | A1 | M |' \
  '| A3 | звено 3 | `go-implementer` | kacho · a | A2 | L |' \
  '| A4 | звено 4 | `go-implementer` | kacho · a | A3 | S |' \
  '| D1 | закрыть | диспетчер | kacho-workspace · — | A4 | S |')
t2=$(task 9002 \
  '| X1 | служба | `go-implementer` | kacho · b | — | L |' \
  '| X2 | схема | `migration-writer` | kacho · m | X1 | L |' \
  '| X3 | страница | `docs-writer` | kacho · docs | X2, Е1 | S |')
printf '# под-фаза\tжетон\tцель\n9002\tЕ1\t9001\n' > "$box/sem.tsv"

# ── K: известный пример ─────────────────────────────────────────────────────
if run K1 0 "$t1" "$t2" --edges A --pack guard --slots 1,2,3; then
  has K1 'критический путь: 200 мин' 'guard A — путь 200'
  has K1 'пакетов: 8;' 'пакетов 8'
  has K1 'слотов 1: срок 420 мин' '1 слот — сумма длительностей 420'
  has K1 'слотов 2: срок 220 мин' '2 слота — 220'
  has K1 'слотов до срока = пути: 3' 'путь достигается с 3 слотов'
  has K1 'перепись: 9001' 'перепись названа по файлу'
  # K2 — предел цепочки в 4 единицы: A4 не входит в пакет A1..A3.
  if grep -qP '\t9001:A1 9001:A2 9001:A3\tgo-implementer\tkacho\t4\t120\t' "$box/K1.out" \
     && grep -qP '\t9001:A4\tgo-implementer\tkacho\t1\t40\t' "$box/K1.out"; then
    ok 'K2: цепочка A1+A2+A3 = 4 единицы, A4 отдельно'
  else
    bad K2 'пакеты цепочки не те'
  fi
fi
if run K3 0 "$t1" "$t2" --edges A --pack literal; then
  has K3 'критический путь: 355 мин' 'literal склеивает X3 с B1 и удлиняет путь до 355'
  has K3 '9001:B1 9002:X3' 'склейка названа в таблице'
fi
if run K4 0 "$t1" "$t2" --edges B --pack guard --semantic "$box/sem.tsv"; then
  has K4 'критический путь: 240 мин' 'B — смысловое ребро удлиняет путь до 240'
  has K4 'B: 9002 Е1 -> все полосы 9001 (7), носителей 1' 'ребро ведомости напечатано'
fi

# ── C: цикл ─────────────────────────────────────────────────────────────────
c1=$(task 9003 \
  '| C1 | первое | `go-implementer` | kacho · a | C2 | S |' \
  '| C2 | второе | `go-implementer` | kacho · a | C1 | S |')
if run C1 1 "$c1"; then
  has C1 'ОТКАЗ — цикл в графе полос: 9003:C1 <- 9003:C2 <- 9003:C1' 'цикл назван путём'
fi
c2=$(task 9004 \
  '| N0 | первое | `go-implementer` | kacho · a | N1 | S |' \
  '| N1 | второе | `go-implementer` | kacho · a | S1 | S |')
if run C2 0 "$c2"; then
  has C2 '9004:N1 ребро от N0 снято: раскрытие стадии замкнуло бы цикл' 'снятое ребро названо'
fi

# ── E: пустой обход ─────────────────────────────────────────────────────────
e1=$(task 9005)
if run E1 2 "$e1"; then has E1 'ПУСТОЙ ОБХОД' 'ноль полос — не расчёт'; fi
if run E2 2; then has E2 'ПУСТОЙ ОБХОД' 'ноль файлов — не расчёт'; fi
printf '# только комментарий\n' > "$box/empty.tsv"
if run E3 2 "$t1" "$t2" --edges B --semantic "$box/empty.tsv"; then
  has E3 'ПУСТОЙ ОБХОД' 'пустая ведомость — B не вырождается в A молча'
fi

# ── R: отказы входа ─────────────────────────────────────────────────────────
printf '9002\tЕ7\t9001\n' > "$box/orphan.tsv"
if run R1 1 "$t1" "$t2" --edges B --semantic "$box/orphan.tsv"; then
  has R1 'без полосы-носителя' 'строка ведомости без предмета — отказ'
fi
r2=$(task 9006 '| W1 | лишняя ячейка | `go-implementer` | kacho · a | — | S | x |')
if run R2 1 "$r2"; then has R2 "issue-9006/tasks.md:" 'координата строки названа'; fi
if run R3 1 "$t1" --edges B; then has R3 'без --semantic' 'B без ведомости — отказ'; fi
r4=$(task 9007 \
  '| Q1 | раз | `go-implementer` | kacho · a | — | S |' \
  '| Q1 | два | `go-implementer` | kacho · a | — | S |')
if run R4 1 "$r4"; then has R4 'повторяются' 'повтор id — отказ'; fi
mkdir -p "$box/issue-9008"; printf '# без раздела\n\n## 1. Прочее\n' > "$box/issue-9008/tasks.md"
if run R5 1 "$box/issue-9008/tasks.md"; then has R5 'раздела «## … Полосы» нет' 'нет раздела — отказ'; fi

printf '\nlane-schedule inject: утверждений %d; пройдено %d, провалено %d\n' \
  "$((pass + fail))" "$pass" "$fail"
if [ $((pass + fail)) -eq 0 ]; then
  echo 'ОТКАЗ — не исполнено ни одного утверждения'; exit 1
fi
[ "$fail" -eq 0 ]
