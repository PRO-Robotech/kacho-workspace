#!/usr/bin/env bash
# skills-gate #01 — ссылка на норму даётся ИМЕНЕМ РАЗДЕЛА, а не номером строки.
#
# ЧТО УТВЕРЖДАЕТ. Ни один `.claude/skills/*/SKILL.md` не ссылается на файл правил
# номером строки (`<файл>.md:<число>` / `<файл>.md:<число>-<число>`).
#
# ПОЧЕМУ. Номер строки — координата, которая устаревает от ЛЮБОГО коммита выше по
# файлу, молча и без конфликта. Один коммит в `security.md` (+12 строк) увёл часть
# таких ссылок внутрь ЧУЖИХ разделов: текст скила продолжал утверждать «норма вот
# здесь», указывая на другое правило. Имя раздела переживает вставку строк и
# ломается только вместе с самим разделом — то есть заметно.
#
# ПРЕДПОСЫЛКА ГЕЙТА (проверяется здесь же). Запрет осмыслен, только пока в корпусе
# ЕСТЬ ссылки на нормы вообще. Если их ноль — «находок 0» означает «нечего
# проверять», и это ДРУГОЙ исход (VOID), а не успех.
#
# ПОЛОЖИТЕЛЬНАЯ ПОЛОВИНА. Гейт не только запрещает номерную форму, но и
# ПРОВЕРЯЕТ разрешённую: каждое `§<Имя>` при ссылке на `.claude/rules/<f>.md`
# обязано резолвиться в заголовок этого файла. Без этой половины запрет зеленел бы
# на дереве, где все ссылки просто исчезли.
#
# Коды выхода: 0 — осмотрено N, находок 0; 1 — находки; 2 — VOID (нечего проверять).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

WS="$(skills_gate_workspace_root)"
NAME="01-section-refs"
SELF="scripts/skills-gate/check-01-section-refs.sh"

# Номерная форма ссылки. Собирается из кусков, чтобы исходник гейта не содержал
# собственного искомого литерала: иначе гейт, наведённый на scripts/, найдёт сам
# себя и перепись завысится (`gate-authoring` §Читать исполняемое).
NUMBERED='[A-Za-z0-9_-]+[.]md:[0-9]+(-[0-9]+)?'
# Ссылка по имени раздела: `<файл>.md` … §Имя.
# Между именем файла и § не должно быть обратной кавычки — иначе выражение
# перепрыгивает ЧЕРЕЗ соседнее имя файла и приписывает раздел не тому (реальный
# ложный срабат на строке «`00-kacho-core.md` ban #10; `data-integrity.md` §…»).
NAMED='`[A-Za-z0-9_-]+[.]md`[^§`]{0,40}§'

mapfile -t files < <(skills_gate_skill_files "$WS")

if [ ${#files[@]} -eq 0 ]; then
    skills_gate_void "$NAME" "в индексе git нет ни одного .claude/skills/*/SKILL.md"
    exit 2
fi

findings=0
named_refs=0
numbered_refs=0
unresolved=0
report=""

for rel in "${files[@]}"; do
    f="$WS/$rel"
    [ -f "$f" ] || continue

    # --- отрицательная половина: номерная форма запрещена ---
    while IFS=: read -r lineno hit; do
        [ -n "${hit:-}" ] || continue
        numbered_refs=$((numbered_refs + 1))
        findings=$((findings + 1))
        report+="  $rel:$lineno  ссылка номером строки: $hit"$'\n'
    done < <(grep -nEo "$NUMBERED" "$f" || true)

    # --- положительная половина: §Имя обязано резолвиться в заголовок нормы ---
    # Читается ФАЙЛ ЦЕЛИКОМ с нормализованными переводами строк: ссылка часто
    # перенесена («…(`security.md`\n §Hardening п.7…»), и построчный разбор её
    # не видит вовсе — то есть молчание гейта было бы неотличимо от чистоты.
    while IFS= read -r ref; do
        [ -n "${ref:-}" ] || continue
        named_refs=$((named_refs + 1))
        rulefile="$(printf '%s' "$ref" | sed -E 's/^`([A-Za-z0-9_-]+[.]md)`.*/\1/')"
        [ -f "$WS/.claude/rules/$rulefile" ] || continue
        section="$(skills_gate_section_token "$ref")"
        # Пустая §-ссылка («см. §») смысла не несёт и резолвиться не может.
        if [ -z "$section" ]; then
            unresolved=$((unresolved + 1))
            findings=$((findings + 1))
            report+="  $rel  пустая §-ссылка на $rulefile"$'\n'
            continue
        fi
        if ! skills_gate_section_resolves "$WS/.claude/rules/$rulefile" "$section"; then
            unresolved=$((unresolved + 1))
            findings=$((findings + 1))
            report+="  $rel  §$section не резолвится ни в один заголовок $rulefile"$'\n'
        fi
    done < <(tr '\n' ' ' < "$f" | tr -s ' ' | grep -oE "$NAMED[^,;)(\`]*" || true)
done

# Самопроверка: гейт обязан не находить сам себя (он единственный файл, где
# номерная форма живёт легально — в этом комментарии её нет, но проверка дешева).
if printf '%s' "$report" | grep -qF "$SELF"; then
    skills_gate_fail "$NAME" "гейт нашёл сам себя — перепись завышена, предикат негоден"
    exit 1
fi

# Предпосылка: корпус вообще содержит ссылки на нормы.
if [ "$named_refs" -eq 0 ] && [ "$numbered_refs" -eq 0 ]; then
    skills_gate_void "$NAME" "прочитано ${#files[@]} SKILL.md, ссылок на нормы 0 — проверять нечего, это НЕ успех"
    exit 2
fi

echo "перепись: прочитано SKILL.md — ${#files[@]}; ссылок по имени раздела — $named_refs; ссылок номером строки — $numbered_refs"

if [ "$findings" -gt 0 ]; then
    printf '%s' "$report" >&2
    skills_gate_fail "$NAME" "находок $findings (номерных $numbered_refs, нерезолвящихся §-имён $unresolved)"
    exit 1
fi

skills_gate_pass "$NAME" "осмотрено ${#files[@]} файлов, $named_refs ссылок по имени раздела, все резолвятся; номерных 0"
exit 0
