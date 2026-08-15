#!/usr/bin/env bash
# Shared helpers for vault-gate checks. Source-only — not directly executable.
#
# Предмет набора: утверждения, которые записки хранилища знаний делают О ДЕРЕВЕ
# соседнего монорепо. Такие утверждения устаревают молча и в одну сторону: код
# уезжает, записка остаётся, и следующий читатель проектирует по механизму,
# которого в дереве уже нет. Абзац «сверяйтесь с кодом» этого не ловит — ловит
# исполняемый вопрос к дереву (`gate-authoring` §Исход вместо объявления).

# Корень workspace. `VAULT_GATE_ROOT` переопределяет его — этим пользуется ТОЛЬКО
# inject.sh, чтобы прогнать гейт по временному дереву с внесённым дефектом и не
# трогать рабочее (`gate-authoring` §Инъекция).
vault_gate_workspace_root() {
    if [ -n "${VAULT_GATE_ROOT:-}" ]; then
        cd "$VAULT_GATE_ROOT" && pwd
        return
    fi
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    cd "$script_dir/../.." && pwd
}

# Монорепо. `project/` лежит под gitignore и в свежем клоне/worktree его нет
# вовсе — поэтому его ОТСУТСТВИЕ обязано давать VOID, а не PASS: «нечего
# проверять» и «проверено, чисто» — разные исходы (`gate-authoring` §Гейт
# заявляет предпосылку). `KACHO_MONOREPO` указывает на него явно.
vault_gate_monorepo() {
    if [ -n "${KACHO_MONOREPO:-}" ]; then
        [ -d "$KACHO_MONOREPO/.git" ] || [ -f "$KACHO_MONOREPO/.git" ] || return 1
        cd "$KACHO_MONOREPO" && pwd
        return
    fi
    local ws="$1"
    [ -d "$ws/project/kacho" ] || return 1
    cd "$ws/project/kacho" && pwd
}

vault_gate_pass() { echo "[PASS] $1${2:+ — $2}"; }
vault_gate_fail() { echo "[FAIL] $1${2:+ — $2}" >&2; }
vault_gate_void() { echo "[VOID] $1${2:+ — $2}" >&2; }   # «проверять нечего» ≠ «находок 0»

# Имена механизмов, запрещённых ПОТРЕБИТЕЛЮ, — ВЫВОДЯТСЯ из дерева, а не
# выписываются здесь руками. Рукописный список расходится с деревом молча и ровно
# в ту сторону, в которую гейт перестаёт ловить: механизм переименовали — запись
# осталась, находок ноль (`measurement-discipline` §Перечни производны от
# предмета). Источник — анализаторы сужения списков каждого сервиса: они и есть
# то место, где запрет объявлен исполняемо.
#
# Печатает по одному имени на строку; пусто — предпосылки нет, вызывающий обязан
# ответить VOID, а не PASS.
vault_gate_banned_consumer_mechanisms() {
    local repo="$1"
    git -C "$repo" grep -hoE '"(ListAllowedIDs|ListObjects)"' -- \
        'services/*/tools/auditlistfilter/*.go' 2>/dev/null \
        | tr -d '"' | sort -u
}

# Сколько файлов дерева объявляют этот запрет. Ноль означает, что предмет запрета
# исчез (анализаторы перестроены/переименованы) — тогда гейт судит по списку,
# которого дерево больше не подтверждает, и обязан сказать VOID.
vault_gate_ban_declaring_files() {
    local repo="$1"
    git -C "$repo" grep -lE '"(ListAllowedIDs|ListObjects)"' -- \
        'services/*/tools/auditlistfilter/*.go' 2>/dev/null | sort -u
}

# Записки-рёбра — из индекса git, не с диска: посторонний файл рядом иначе влияет
# на вердикт (`measurement-discipline` §Откуда читается предмет). `--others
# --exclude-standard` добавляет ещё не закоммиченную записку: иначе новая записка
# не проверяется ровно в тот день, когда её пишут.
vault_gate_edge_files() {
    local ws="$1"
    git -C "$ws" ls-files --cached --others --exclude-standard 'obsidian/kacho/edges/*.md' | sort -u
}

# Заголовок записки: frontmatter `title:` либо первый `# `-заголовок. Предмет —
# именно ЗАГОЛОВОК, а не тело: тело вправе — и обязано — объяснять, почему
# механизм снят, и такой абзац находкой не является (`gate-authoring` §Законный
# близнец).
vault_gate_note_title() {
    local f="$1" t
    t="$(sed -nE 's/^title:[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/p' "$f" | head -1)"
    [ -n "$t" ] || t="$(sed -nE 's/^#[[:space:]]+(.*)$/\1/p' "$f" | head -1)"
    printf '%s' "$t"
}

# Объявленное состояние записки. Пусто — состояние не объявлено вовсе.
vault_gate_note_status() {
    sed -nE 's/^status:[[:space:]]*"?([A-Za-z-]+)"?[[:space:]]*$/\1/p' "$1" | head -1
}

# Состояния, которыми записка признаёт, что описывает ПРОШЛОЕ. Словарь взят из
# того, что в хранилище уже используется, — новых синонимов гейт не вводит
# (`vault.md` §Запреты: канонические теги только из obsidian/kacho/CLAUDE.md).
vault_gate_status_is_retired() {
    case "$1" in
        removed|deprecated|superseded) return 0 ;;
        *) return 1 ;;
    esac
}
