#!/usr/bin/env bash
# shellcheck disable=SC2016
#   Тела агентов в мирах — markdown; бэктики в них разметка, а не подстановка команды,
#   поэтому одинарные кавычки намеренны на весь файл (как в inject.sh).
# ДОКАЗЫВАЕТ: check-14-agent-load-targets-resolve.sh (зовётся из inject.sh; строку читает его перепись доказанности)
# Инъекция для check-14
#
# ЗАМЕЧАНИЕ О САМОЙ ПРОБЕ: первый прогон провалил пять осей из девяти не из-за
# гейта, а из-за СВОЕГО экранирования — `\`` внутри одинарных кавычек попадает
# в файл вместе с обратным слешем, и образец `Skill <имя>` не совпадает. Красное
# пришло от пробы, а не от предмета; починено здесь, гейт не тронут. — в обе стороны, на СИНТЕТИКЕ.
#
#   A    `Skill <имя>` без каталога скила                       -> 1
#   A'   тот же вызов, каталог есть                             -> 0
#   B    `Read .claude/backup/<файл>` без файла                 -> 1
#   B'   тот же путь, файл есть                                 -> 0
#   C    предзагрузка `skills:` без каталога                    -> 1
#   C'   предзагрузка ИМЕНЕМ С ЗАГЛАВНЫМИ (rule-MANIFEST)       -> 0
#   D    скил, которого не зовёт никто                          -> 1
#   D'   тот же скил, названный ГОЛЫМ именем в кавычках         -> 0
#   VOID тел агентов ноль                                       -> 2
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SELF_DIR/check-14-agent-load-targets-resolve.sh"
PASS=0; FAIL=0

sandbox() { local d; d="$(mktemp -d "${TMPDIR:-/tmp}/probe-c14-XXXXXX")"
  mkdir -p "$d/.claude/agents" "$d/.claude/skills" "$d/.claude/backup" "$d/scripts/tooling-gate"
  cp "$CHECK" "$d/scripts/tooling-gate/"; echo "$d"; }
skill() { mkdir -p "$1/.claude/skills/$2"; echo "# $2" > "$1/.claude/skills/$2/SKILL.md"; }
agent() { # <dir> <имя> <строка skills: или пусто> <тело>
  { echo "---"; echo "name: $2"; echo "skills:"; [ -n "$3" ] && echo "  - $3";
    echo "---"; echo; echo "$4"; } > "$1/.claude/agents/$2.md"; }
run() { KACHO_WS="$1" bash "$1/scripts/tooling-gate/check-14-agent-load-targets-resolve.sh" >/dev/null 2>&1; echo $?; }
assert() { if [ "$1" = "$2" ]; then echo "  ✔ $3 (код $2)"; PASS=$((PASS+1)); else echo "  ✘ $3 — ждали $1, получили $2"; FAIL=$((FAIL+1)); fi; }

echo "инъекция check-14-agent-load-targets-resolve:"

d="$(sandbox)"; skill "$d" alpha; agent "$d" a alpha 'Грузи `Skill beta` по триггеру.'
assert 1 "$(run "$d")" 'ДЕФЕКТ: вызов Skill beta без каталога скила'; rm -rf "$d"

d="$(sandbox)"; skill "$d" alpha; skill "$d" beta; agent "$d" a alpha 'Грузи `Skill beta` по триггеру.'
assert 0 "$(run "$d")" "БЛИЗНЕЦ: тот же вызов, каталог есть — молчит"; rm -rf "$d"

d="$(sandbox)"; skill "$d" alpha; agent "$d" a alpha 'Читай `Read .claude/backup/gone.md` (АРХИВ).'
assert 1 "$(run "$d")" "ДЕФЕКТ: чтение архива без файла"; rm -rf "$d"

d="$(sandbox)"; skill "$d" alpha; echo x > "$d/.claude/backup/gone.md"
agent "$d" a alpha 'Читай `Read .claude/backup/gone.md` (АРХИВ).'
assert 0 "$(run "$d")" "БЛИЗНЕЦ: тот же путь, файл есть — молчит"; rm -rf "$d"

d="$(sandbox)"; skill "$d" alpha; agent "$d" a rule-Ghost 'Тело.'
assert 1 "$(run "$d")" "ДЕФЕКТ: предзагрузка без каталога"; rm -rf "$d"

d="$(sandbox)"; skill "$d" alpha; skill "$d" rule-MANIFEST; agent "$d" a rule-MANIFEST 'Тело зовёт `Skill alpha`.'
assert 0 "$(run "$d")" "БЛИЗНЕЦ: предзагрузка ИМЕНЕМ С ЗАГЛАВНЫМИ — молчит"; rm -rf "$d"

d="$(sandbox)"; skill "$d" alpha; skill "$d" lonely; agent "$d" a alpha 'Тело без упоминаний.'
assert 1 "$(run "$d")" "ДЕФЕКТ: скил, которого не зовёт никто"; rm -rf "$d"

d="$(sandbox)"; skill "$d" alpha; skill "$d" lonely; agent "$d" a alpha 'Смотри скил `lonely` по месту.'
assert 0 "$(run "$d")" "БЛИЗНЕЦ: тот же скил назван ГОЛЫМ именем — молчит"; rm -rf "$d"

d="$(sandbox)"; skill "$d" alpha
assert 2 "$(run "$d")" "ПРЕДМЕТА НЕТ: тел агентов ноль — код 2, не зелёное"; rm -rf "$d"

# ── ось E: ЗАГЛАВНЫЕ В ФОРМЕ ВЫЗОВА ────────────────────────────────────────
# Прежняя редакция допускала заглавные только в предзагрузке, и `Skill rule-MANIFEST`
# стоял вне наблюдения: ни красного, ни зелёного.
d="$(sandbox)"; skill "$d" alpha; agent "$d" a alpha 'Грузи `Skill rule-MANIFEST` по триггеру.'
assert 1 "$(run "$d")" 'ДЕФЕКТ: вызов С ЗАГЛАВНЫМИ без каталога — виден'; rm -rf "$d"

d="$(sandbox)"; skill "$d" alpha; skill "$d" rule-MANIFEST
agent "$d" a alpha 'Грузи `Skill rule-MANIFEST` по триггеру.'
assert 0 "$(run "$d")" 'БЛИЗНЕЦ: тот же вызов, каталог есть — молчит'; rm -rf "$d"

echo "инъекция: пройдено $PASS, провалено $FAIL"
[ "$FAIL" -eq 0 ]
