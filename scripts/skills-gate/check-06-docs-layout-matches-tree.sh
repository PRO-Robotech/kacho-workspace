#!/usr/bin/env bash
# skills-gate #06 — раскладка каталогов документации ОБЪЯВЛЕНА машинно и сходится с деревом.
#
# ЧТО УТВЕРЖДАЕТ. Регламент документации (`kacho-docs-writer`) описывает, где у
# компонента продукта лежит сайт документации, страницы и инженерная часть. Эти
# имена — утверждение о ЧУЖОМ дереве: оно живёт в другом репозитории и переезжает
# там без единого конфликта здесь. Поэтому регламент обязан объявить раскладку
# машинно-сверяемым блоком, а гейт выводит те же значения из дерева продукта и
# сверяет их. Расхождение — находка с координатой.
#
# Вторым предикатом сверяется рабочий каталог КАЖДОЙ процитированной оснасткой
# команды сборки сайта (`cd <каталог> && npm …`): каталог обязан существовать в
# дереве продукта либо в воркспейсе. Команда, которую негде выполнить, — не
# рецепт, а тупик для того, кто ей поверил.
#
# ПОЧЕМУ ЭТО НЕ ДУБЛЬ ХУКА СВЕЖЕСТИ. Тот резолвит координаты в обратных кавычках и
# НАМЕРЕННО пропускает токен с подстановкой (`project/<svc>/…`) — резолвить в нём
# нечего. Ровно в такой форме раскладка и записана в нормативном регламенте, то
# есть самое читаемое утверждение о ней было вне всякого предиката. Здесь
# сверяются ИМЕНА уровней, а не отдельные пути, поэтому подстановка предикату не
# мешает.
#
# ПРЕДПОСЫЛКА ГЕЙТА (проверяется здесь же). Основание — индекс дерева продукта и
# то, что в нём есть хотя бы один сайт (признак сайта — его `docusaurus.config.ts`,
# а не выписанное имя каталога: имя как раз и переезжает). Нет дерева, нет у него
# индекса git или нет ни одного конфига — VOID, а не успех: «ноль расхождений» и
# «ноль прочитанного» обязаны различаться.
#
# ОТСУТСТВИЕ ОБЪЯВЛЕНИЯ — НАХОДКА, А НЕ VOID. Иначе гейт снимается удалением блока:
# послабление, которое отключает проверку, стоит дороже проверки.
#
# Коды выхода: 0 — объявление сошлось с деревом; 1 — расхождение; 2 — VOID.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

WS="$(skills_gate_workspace_root)"
NAME="06-docs-layout-matches-tree"
SKILL_REL=".claude/skills/kacho-docs-writer/SKILL.md"
SKILL="$WS/$SKILL_REL"
MARKER="РАСКЛАДКА-ДОКУМЕНТАЦИИ"

# Дерево продукта: рядом (`project/kacho`) либо названное явно. Переменная — та же,
# что у соседних наборов, чтобы гейт гонялся из рабочей копии, где клона продукта нет.
MONO="${KACHO_MONOREPO:-$WS/project/kacho}"

[ -d "$MONO" ] || {
    skills_gate_void "$NAME" "дерева продукта нет ($MONO) — выводить раскладку не из чего"
    exit 2
}

# Состав чужого дерева спрашивается у ЕГО индекса, а не у диска: каталог продукта
# в этом репозитории под игнором, а обход диска принёс бы собранные сайты и чужие
# черновики — объём осмотренного менялся бы от машины к машине.
mono_files="$(git -C "$MONO" ls-files 2>/dev/null)" || mono_files=""
[ -n "$mono_files" ] || {
    skills_gate_void "$NAME" "у дерева продукта ($MONO) нет индекса git — состав читать нечем"
    exit 2
}

# ── основание: что дерево говорит о себе само ────────────────────────────────────
configs="$(printf '%s\n' "$mono_files" | grep -E '(^|/)docusaurus\.config\.ts$' | sort || true)"
n_cfg="$(printf '%s\n' "$configs" | grep -c . || true)"

if [ "$n_cfg" -eq 0 ]; then
    skills_gate_void "$NAME" "в индексе дерева продукта нет ни одного docusaurus.config.ts — сверять не с чем"
    exit 2
fi

tree_sites=""       # пути каталогов сайтов относительно корня продукта
tree_site_dirs=""   # их имена
tree_pages_dirs=""  # каталоги страниц, объявленные самими конфигами
while IFS= read -r cfg; do
    [ -n "$cfg" ] || continue
    site="$(dirname "$cfg")"
    tree_sites="$tree_sites$site"$'\n'
    tree_site_dirs="$tree_site_dirs$(basename "$site")"$'\n'
    # Каталог страниц объявляет сам конфиг — ключ `path` пресета docs. Регистр
    # значим: `sidebarPath`/`routeBasePath` под `path:` не подпадают.
    pg="$(grep -oE "^[[:space:]]*path:[[:space:]]*['\"][^'\"]+['\"]" "$MONO/$cfg" 2>/dev/null | head -1 \
          | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/")"
    tree_pages_dirs="$tree_pages_dirs${pg:-docs}"$'\n'
done <<<"$configs"

tree_site_dirs="$(printf '%s' "$tree_site_dirs" | sort -u | grep . || true)"
tree_pages_dirs="$(printf '%s' "$tree_pages_dirs" | sort -u | grep . || true)"

# ── объявление регламента ────────────────────────────────────────────────────────
[ -f "$SKILL" ] || {
    skills_gate_void "$NAME" "нет $SKILL_REL — объявлять раскладку некому"
    exit 2
}

# Блок объявления: строки таблицы после маркерного комментария, до первой пустой.
declared="$(awk -v m="$MARKER" '
    index($0, m) {inside=1; next}
    inside && /^[[:space:]]*$/ {exit}
    inside && /^\|/ {print}
' "$SKILL")"

get_declared() {   # get_declared <ключ> → значение в обратных кавычках или пусто
    printf '%s\n' "$declared" \
        | awk -F'|' -v k="$1" 'index($2, k) {print $3; exit}' \
        | sed -nE 's/.*`([^`]+)`.*/\1/p'
}

d_site="$(get_declared 'каталог сайта')"
d_pages="$(get_declared 'каталог страниц')"
d_eng="$(get_declared 'каталог инженерной части')"
d_count="$(get_declared 'сайтов в дереве')"

n_rows="$(printf '%s\n' "$declared" | grep -cE '^\|.*`' || true)"

# ── второй предикат: рабочий каталог процитированной сборки ──────────────────────
tooling_files="$(git -C "$WS" ls-files --cached --others --exclude-standard \
                    '.claude/rules/*.md' '.claude/skills/*/*.md' '.claude/agents/*.md' | sort -u)"
n_files="$(printf '%s\n' "$tooling_files" | grep -c . || true)"

cites="$(cd "$WS" && printf '%s\n' "$tooling_files" | grep . \
            | xargs -r grep -nE 'cd[[:space:]]+[^[:space:]&|;]+[[:space:]]*&&[[:space:]]*npm' 2>/dev/null || true)"
n_cites="$(printf '%s\n' "$cites" | grep -c . || true)"

ws_files="$(git -C "$WS" ls-files --cached --others --exclude-standard)"

# Есть ли такой каталог — по ПРЕФИКСУ строки индекса, дословно. Сравнение через
# `index(...) == 1`, а не регулярным выражением: путь несёт точки и дефисы, и
# всякое экранирование здесь — источник тихого ложного ответа в обе стороны.
#
# Читающая сторона дочитывает вход ДО КОНЦА и не выходит на первом совпадении.
# Ранний выход закрывал бы канал под пишущим `printf`, тот получал бы SIGPIPE, и
# при `pipefail` вердикт пайплайна становился 141 — «каталога нет» для КАЖДОГО
# каталога. Дефект найден на своей же зелёной ветке: гейт краснел на верном дереве.
dir_in_index() {   # dir_in_index <список файлов> <каталог>
    [ "$2" = "." ] && return 0
    printf '%s\n' "$1" | awk -v d="$2/" 'index($0, d) == 1 {found = 1} END {exit !found}'
}

rc=0
fails=""
note() { fails="$fails  $1"$'\n'; rc=1; }

# ── сверка ───────────────────────────────────────────────────────────────────────
echo "перепись: конфигов сайтов прочитано — $n_cfg; строк объявления разобрано — $n_rows; файлов оснастки прочитано — $n_files; цитат сборки разобрано — $n_cites"

if [ "$n_rows" -eq 0 ]; then
    note "$SKILL_REL: раскладка описана, но не ОБЪЯВЛЕНА — блока «$MARKER» нет, сверять нечем"
else
    if [ -z "$d_site" ]; then
        note "$SKILL_REL: в объявлении нет строки «каталог сайта»"
    elif ! printf '%s\n' "$tree_site_dirs" | grep -qxF "$d_site"; then
        note "$SKILL_REL: объявлен каталог сайта «$d_site», дерево знает: $(printf '%s' "$tree_site_dirs" | tr '\n' ' ')"
    fi

    if [ -z "$d_pages" ]; then
        note "$SKILL_REL: в объявлении нет строки «каталог страниц»"
    elif ! printf '%s\n' "$tree_pages_dirs" | grep -qxF "$d_pages"; then
        note "$SKILL_REL: объявлен каталог страниц «$d_pages», конфиги называют: $(printf '%s' "$tree_pages_dirs" | tr '\n' ' ')"
    fi

    if [ -z "$d_eng" ]; then
        note "$SKILL_REL: в объявлении нет строки «каталог инженерной части»"
    else
        missing=""
        while IFS= read -r site; do
            [ -n "$site" ] || continue
            dir_in_index "$mono_files" "$site/$d_eng" || missing="$missing $site"
        done <<<"$(printf '%s' "$tree_sites" | grep . || true)"
        [ -z "$missing" ] || note "$SKILL_REL: объявлен каталог инженерной части «$d_eng», его нет у сайтов:$missing"
    fi

    if [ -z "$d_count" ]; then
        note "$SKILL_REL: в объявлении нет строки «сайтов в дереве»"
    elif [ "$d_count" != "$n_cfg" ]; then
        note "$SKILL_REL: объявлено сайтов «$d_count», в индексе дерева $n_cfg"
    fi
fi

while IFS= read -r cite; do
    [ -n "$cite" ] || continue
    where="${cite%%:*}"; rest="${cite#*:}"; lineno="${rest%%:*}"
    dir="$(printf '%s' "$cite" | sed -nE 's/.*cd[[:space:]]+([^[:space:]&|;]+).*/\1/p' | head -1)"
    dir="${dir%/}"
    # Путь может быть записан от воркспейса — там читатель и стоит.
    case "$dir" in
        project/kacho) dir="." ;;
        project/kacho/*) dir="${dir#project/kacho/}" ;;
    esac
    if ! dir_in_index "$mono_files" "$dir" && ! dir_in_index "$ws_files" "$dir"; then
        note "$where:$lineno: сборка процитирована из каталога «$dir» — его нет ни в индексе дерева продукта, ни в индексе воркспейса"
    fi
done <<<"$cites"

if [ "$rc" -ne 0 ]; then
    printf '%s' "$fails" >&2
    skills_gate_fail "$NAME" "объявленная раскладка документации разошлась с деревом"
    exit 1
fi

skills_gate_pass "$NAME" "раскладка сошлась: сайтов $n_cfg, каталог сайта «$d_site», страницы «$d_pages», инженерная часть «$d_eng»"
exit 0
