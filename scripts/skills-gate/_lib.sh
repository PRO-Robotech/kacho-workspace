#!/usr/bin/env bash
# Shared helpers for skills-gate checks. Source-only — not directly executable.
#
# Предмет набора: утверждения, которые скилы делают САМИ О СЕБЕ и о дереве вокруг.
# Такие утверждения устаревают молча (`gate-authoring` §Читать исполняемое —
# «утверждение о дереве не есть проверка»), поэтому у каждого обязан быть
# исполняемый вопрос к git, а не абзац.

# Корень workspace. `SKILLS_GATE_ROOT` переопределяет его — этим пользуется
# ТОЛЬКО inject.sh, чтобы прогонять гейт по временному дереву с внесённым
# дефектом и не трогать рабочее (`gate-authoring` §Инъекция).
skills_gate_workspace_root() {
    if [ -n "${SKILLS_GATE_ROOT:-}" ]; then
        cd "$SKILLS_GATE_ROOT" && pwd
        return
    fi
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    cd "$script_dir/../.." && pwd
}

skills_gate_pass() { echo "[PASS] $1${2:+ — $2}"; }
skills_gate_fail() { echo "[FAIL] $1${2:+ — $2}" >&2; }
skills_gate_void() { echo "[VOID] $1${2:+ — $2}" >&2; }   # «проверять нечего» ≠ «находок 0»

# Состав дерева — из индекса git, не с диска: посторонний каталог рядом с репо
# иначе влияет на вердикт (`measurement-discipline` §Откуда читается предмет).
# `--others --exclude-standard` добавляет ЕЩЁ НЕ закоммиченный, но и не
# игнорируемый скил: иначе новый скил не проверяется ровно в тот день, когда его
# пишут, — а гейт молчит и это неотличимо от чистого дерева.
# Печатает пути SKILL.md относительно корня workspace, по одному на строку.
skills_gate_skill_files() {
    local ws="$1"
    git -C "$ws" ls-files --cached --others --exclude-standard '.claude/skills/*/SKILL.md' | sort -u
}

# Из фрагмента вида "`security.md` §Hardening п.1 | ещё текст" достаёт токен
# раздела. Ссылка живёт в свободной прозе и закрывающего разделителя не имеет,
# поэтому режем по тем, что встречаются: `|` (ячейка таблицы), `. ` (конец
# предложения), ` — ` (тире), `»`. Хвост «п.N» — указатель ВНУТРИ раздела, не
# часть имени, и снимается.
skills_gate_section_token() {
    printf '%s' "$1" \
        | sed -E 's/.*§//' \
        | sed -E 's/\|.*$//; s/\. .*$//; s/ — .*$//; s/».*$//' \
        | sed -E 's/[[:space:]]*п\.[0-9]+([[:space:]]*,[[:space:]]*п\.[0-9]+)*[[:space:]]*$//' \
        | sed -E 's/[[:space:]]+$//'
}

# Резолвится ли токен в какой-нибудь заголовок файла нормы.
#
# Два послабления, каждое — против ложного ОТРИЦАНИЯ, оба намеренные:
#  (1) пробелы снимаются С ОБЕИХ сторон: иначе «§Concurrency/lifecycle» не находит
#      заголовок «## Concurrency / lifecycle / читаемость» — расхождение на
#      форматировании, а не на существе (`measurement-discipline` §Предикат);
#  (2) резолвится ЛЮБОЙ непустой ПРЕФИКС токена по словам: у ссылки в прозе нет
#      закрывающего разделителя («§Within-service требуют атомарности»), и без
#      этого гейт краснел бы на корректных ссылках.
# Цена (2) — предикат слабее: он доказывает, что раздел с таким началом имени в
# файле ЕСТЬ, а не что назван именно он. Отрицательный контроль обязателен и
# лежит рядом (`inject.sh`): выдуманное имя не резолвится ни одним префиксом.
skills_gate_section_resolves() {
    local rulefile="$1" token="$2" needle headers
    headers="$(grep -E '^#{2,3} ' "$rulefile" | sed -E 's/^#+[[:space:]]*//' | tr -d '[:space:]')"
    while [ -n "$token" ]; do
        needle="$(printf '%s' "$token" | tr -d '[:space:]')"
        if [ -n "$needle" ] && printf '%s\n' "$headers" | grep -qF -- "$needle"; then
            return 0
        fi
        # отбросить последнее слово и повторить
        case "$token" in
            *\ *) token="${token% *}" ;;
            *)    return 1 ;;
        esac
    done
    return 1
}
