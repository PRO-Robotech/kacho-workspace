#!/usr/bin/env bash
# check-11 — перепись каскада читает ОБА отношения дочерних и не выдаёт пустой
# уровень за «открытых ноль».
#
# ЧТО ЗАПРЕЩАЕТ ЭТА ПРОВЕРКА. `scripts/cascade-census.sh` — предикат каскада
# закрытия (`.claude/rules/git-issues.md#gi-close-cascade`): у закрытой волны
# открытых дочерних ноль. Прежний предикат читал одно отношение из двух —
# sub-issue — и печатал только открытые номера, поэтому волна без привязанных
# дочерних давала пустой вывод, то есть зелёное, а перечень задач в теле не
# читался вовсе (возврат wave-reviewer к ws#845: тело kacho#2794 перечисляет
# #2724, #2709 и #2714, чей родитель по sub-issue — #2795).
#
# ПРОВЕРКА ПОВЕДЕНЧЕСКАЯ, по образцу check-09. Настоящему инструменту
# подкладывается подставной `gh` с записанными ответами трекера, и читаются код
# и напечатанное. Искать в исходнике `sub_issues` и `body` значило бы ловить
# форму: читать тело автор волен чем угодно.
#
# ПОДДЕЛКА СТРУКТУРНО НЕ СПОСОБНА ДАТЬ ЗЕЛЁНОЕ. Подставной `gh` не решает
# ничего: он отдаёт фикстуру, а выражение `--jq` исполняет над ней настоящий
# `jq` — то самое, что написал инструмент. Страницы после первой он отдаёт
# только под `--paginate`, как хостинг. Незнакомый вызов и отсутствующая
# фикстура — код 99, а не пустой ответ: пустой ушёл бы в ветку «дочерних нет».
# Обе стороны заглушки доказываются до того, как ей верят.
#
# ВХОД — НАСТОЯЩИЙ. Проба расхождения несёт дословно пункты перечня из тела
# kacho#2794 (замер 2026-09-26), с упоминаниями PR вливания дальше по строке;
# проба формы тела — перевод строки `\r\n`, каким тело приходит после правки в
# браузере.
#
# КАЖДАЯ ПРОБА СВЕРЯЕТ КОД И ТЕКСТ: код 1 дают и расхождение, и закрытый
# уровень с открытыми, и проба, читающая только код, зеленела бы на чужой
# ветке.
#
# Предпосылка (исход VOID): в дереве есть инструмент, есть `jq` и `perl`,
# подставной `gh` доказал обе свои стороны.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WS="$(tooling_gate_workspace_root)"
NAME="check-11-cascade-census-reads-both-relations"
TOOL_REL="scripts/cascade-census.sh"

if [ -z "$(tooling_gate_files "$WS" "$TOOL_REL")" ]; then
    tooling_gate_void "$NAME" "$TOOL_REL в дереве нет — проверять нечего"
    exit 2
fi
for bin in jq perl; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        tooling_gate_void "$NAME" "$bin не найден — инструмент не запустить, вердикта не будет"
        exit 2
    fi
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── ПОДСТАВНОЙ ТРЕКЕР ────────────────────────────────────────────────────────
STUB="$TMP/stub"; mkdir -p "$STUB"
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
# Подставной gh: отдаёт записанный ответ и НИЧЕГО не решает.
set -u
[ "${1:-}" = api ] || { echo "gh-stub: незнакомый вызов: $*" >&2; exit 99; }
shift
paginate=0; expr=""; path=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --paginate) paginate=1 ;;
        --jq) expr="${2:?}"; shift ;;
        -*) echo "gh-stub: незнакомый ключ: $1" >&2; exit 99 ;;
        *) [ -z "$path" ] || { echo "gh-stub: лишний аргумент: $1" >&2; exit 99; }
           path="$1" ;;
    esac
    shift
done
f="${CC_FIXTURE:?}/$path"
if [ -e "$f.unavailable" ]; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
[ -e "$f.json" ] || { echo "gh-stub: нет фикстуры: $path" >&2; exit 99; }
pages=("$f.json")
if [ "$paginate" = 1 ]; then
    for p in "$f".p[2-9].json; do [ -e "$p" ] && pages+=("$p"); done
fi
for p in "${pages[@]}"; do
    if [ -n "$expr" ]; then jq -r "$expr" "$p" || exit 1; else cat "$p"; fi
done
STUBEOF
chmod +x "$STUB/gh"

# ── ФИКСТУРЫ ─────────────────────────────────────────────────────────────────
R="PRO-Robotech/kacho"

mkcase() { local d="$TMP/case-$1"; mkdir -p "$d"; printf '%s' "$d"; }

# mk_issue <каталог> <репо> <номер> <состояние> <тело>
mk_issue() {
    local d="$1/repos/$2/issues"; mkdir -p "$d"
    jq -n --argjson n "$3" --arg s "$4" --arg b "$5" --arg r "$2" \
        '{number:$n, state:$s, title:"проба", body:$b,
          repository_url:("https://api.github.com/repos/" + $r)}' > "$d/$3.json"
}

# mk_sub <каталог> <репо> <номер> <страница: 1|2…> [<репо>:<номер>:<состояние>…]
mk_sub() {
    local d="$1/repos/$2/issues/$3" page="$4" f; shift 4
    mkdir -p "$d"
    if [ "$page" = 1 ]; then f="$d/sub_issues.json"; else f="$d/sub_issues.p$page.json"; fi
    if [ "$#" -eq 0 ]; then echo '[]' > "$f"; return; fi
    printf '%s\n' "$@" | jq -R 'split(":") |
        {number:(.[1]|tonumber), state:.[2],
         repository_url:("https://api.github.com/repos/" + .[0])}' | jq -s . > "$f"
}

# A — отношения совпадают, тело с `\r\n`, уровень закрыт, дочерние закрыты.
A="$(mkcase A)"
mk_issue "$A" "$R" 100 closed $'## Задачи волны\r\n\r\n- [x] #1 — сделано\r\n- [x] #2 — сделано\r\n'
mk_sub "$A" "$R" 100 1 "$R:1:closed" "$R:2:closed"

# B — расхождение на настоящем входе: пункты тела kacho#2794 дословно.
B="$(mkcase B)"
mk_issue "$B" "$R" 2794 closed "$(cat <<'BODY'
## Задачи волны

- [x] #2788 — закрыта вливанием #2787
- [ ] #2724 — открыта: тело #2787 относит её к задачам, которые закрываются своим предикатом, а не этим запросом
- [x] #2716 — стек посадки `own` посажен #2722 (`f445aaaa`). Закрыта 2026-09-21 опровержением посылки, остаток передан #2724. Привязана 2026-09-22
- [ ] #2709 — код посажен #2722, метка `status:landed-awaiting-stand`. Закрывается тем же замером подъёма стенда `own`, что и #2724. Привязана 2026-09-22
- [ ] #2714 — то же, что #2709. Привязана 2026-09-22
BODY
)"
mk_sub "$B" "$R" 2794 1 "$R:2788:closed" "$R:2716:closed"
for n in 2724 2709 2714; do mk_issue "$B" "$R" "$n" closed "дочерний #2795"; done

# C — перечня в теле нет; пример перечня в блоке кода и упоминание в прозе
# дочерними не считаются. Сверяется одно отношение, и это сказано.
C="$(mkcase C)"
mk_issue "$C" "$R" 2795 closed "$(cat <<'BODY'
Задачи волны — это её sub-issue, в теле они не перечисляются, см. #9.

```md
- [ ] #5 — так выглядел бы перечень
```
BODY
)"
mk_sub "$C" "$R" 2795 1 "$R:3:closed" "$R:4:closed"

# D — уровень закрыт, а дочерний открыт.
D="$(mkcase D)"
mk_issue "$D" "$R" 200 closed $'- [x] #1\n- [ ] #2\n'
mk_sub "$D" "$R" 200 1 "$R:1:closed" "$R:2:open"

# E — дочерних ноль в обоих отношениях.
E="$(mkcase E)"
mk_issue "$E" "$R" 300 closed "Волна без задач."
mk_sub "$E" "$R" 300 1

# F — дочерний привязан sub-issue, но в перечне тела его нет.
F="$(mkcase F)"
mk_issue "$F" "$R" 400 open $'- [ ] #1\n- [ ] #2\n'
mk_sub "$F" "$R" 400 1 "$R:1:open" "$R:2:open" "$R:3:open"

# G — задача не читается.
G="$(mkcase G)"
mkdir -p "$G/repos/$R/issues"; : > "$G/repos/$R/issues/500.unavailable"

# H — все три законные формы ссылки, маркеры `*` и `+`, два пункта без ссылки
# первой (во втором ссылка есть, но дальше по строке — это упоминание),
# дочерний другого репозитория; уровень открыт с открытым дочерним — законно.
H="$(mkcase H)"
mk_issue "$H" "$R" 600 open $'* [ ] #1 — идёт\n+ [x] https://github.com/PRO-Robotech/corelib/issues/7\n- [x] PRO-Robotech/kaname#8 — сделано\n- [ ] написать записку\n- [ ] проверить #9 после вливания\n'
mk_sub "$H" "$R" 600 1 "$R:1:open" "PRO-Robotech/corelib:7:closed" "PRO-Robotech/kaname:8:closed"

# I — sub-issue на двух страницах.
I="$(mkcase I)"
mk_issue "$I" "$R" 700 closed $'- [x] #1\n- [x] #2\n- [x] #3\n'
mk_sub "$I" "$R" 700 1 "$R:1:closed" "$R:2:closed"
mk_sub "$I" "$R" 700 2 "$R:3:closed"

# K — ответ о задаче не разбирается.
K="$(mkcase K)"
mkdir -p "$K/repos/$R/issues"
printf '<html><head><title>502</title></head></html>\n' > "$K/repos/$R/issues/800.json"

# ── ПРЕДПОСЫЛКА: ЗАГЛУШКА ДОКАЗАНА В ОБЕ СТОРОНЫ ─────────────────────────────
stub_pages="$(PATH="$STUB:$PATH" CC_FIXTURE="$I" gh api --paginate "repos/$R/issues/700/sub_issues" --jq '.[].number' 2>/dev/null | tr '\n' ' ' || true)"
if [ "$stub_pages" != "1 2 3 " ]; then
    tooling_gate_void "$NAME" "подставной gh не отдал страницы фикстуры (получено '$stub_pages') — пробы на нём недоказательны"
    exit 2
fi
PATH="$STUB:$PATH" CC_FIXTURE="$I" gh api "repos/$R/issues/999" >/dev/null 2>&1 && stub_rc=0 || stub_rc=$?
if [ "$stub_rc" -ne 99 ]; then
    tooling_gate_void "$NAME" "подставной gh на вызове без фикстуры вернул $stub_rc вместо 99 — он способен молча подыграть"
    exit 2
fi

# ── ПРОБЫ ────────────────────────────────────────────────────────────────────
probes=0
findings=0

# probe <каталог> <номер> <ожидаемый-код> <имя-пробы> <обязательная-подстрока>...
probe() {
    local dir="$1" num="$2" want="$3" title="$4"; shift 4
    local out rc needle
    probes=$((probes + 1))
    out="$(PATH="$STUB:$PATH" CC_FIXTURE="$dir" bash "$WS/$TOOL_REL" "$R" "$num" 2>&1)" && rc=0 || rc=$?
    if [ "$rc" -ne "$want" ]; then
        tooling_gate_fail "$NAME" "$title — ждали код $want, получили $rc"
        printf '%s\n' "$out" | sed 's/^/      /' >&2
        findings=$((findings + 1))
        return
    fi
    for needle in "$@"; do
        if ! printf '%s\n' "$out" | grep -qF -- "$needle"; then
            tooling_gate_fail "$NAME" "$title — код $rc верен, но в выводе нет «$needle»"
            printf '%s\n' "$out" | sed 's/^/      /' >&2
            findings=$((findings + 1))
            return
        fi
    done
    tooling_gate_pass "$NAME" "$title (код $rc)"
}

probe "$A" 100 0 "отношения совпадают, тело с \\r\\n — вердикт с total" \
    "sub-issue:  total 2" "тело:       total 2" "ИТОГ: дочерних 2"

probe "$B" 2794 1 "перечень тела шире sub-issue (kacho#2794) — находка, лишние названы" \
    "только в теле (нет в sub-issue): $R#2709 $R#2714 $R#2724" "расходятся"

probe "$C" 2795 0 "перечня в теле нет — сверяется одно отношение, и это сказано" \
    "перечня дочерних нет" "sub-issue:  total 2" "ИТОГ: дочерних 2"

probe "$D" 200 1 "уровень закрыт, дочерний открыт — находка, открытый назван" \
    "открытые:   $R#2" "уровень закрыт"

probe "$E" 300 2 "дочерних ноль в обоих отношениях — вердикта нет, а не «открытых ноль»" \
    "дочерних ноль" "вердикта НЕТ"

probe "$F" 400 1 "sub-issue шире перечня тела — находка, лишний назван" \
    "только в sub-issue (нет в теле): $R#3" "расходятся"

probe "$G" 500 2 "задача не читается — вердикта нет, а не находка" \
    "не читается"

probe "$H" 600 0 "три формы ссылки, три маркера, пункт без ссылки — все опознаны" \
    "тело:       total 3" "без ссылки 2" "открытые:   $R#1"

probe "$I" 700 0 "sub-issue на двух страницах — прочитаны обе" \
    "sub-issue:  total 3" "ИТОГ: дочерних 3"

probe "$K" 800 2 "ответ о задаче не разбирается — вердикта нет" \
    "не разбирается"

tooling_gate_census "$NAME: проб исполнено $probes над $TOOL_REL; исходов покрыто три (0 — 4 пробы, 1 — 3 пробы, 2 — 3 пробы)"

if [ "$findings" -gt 0 ]; then
    tooling_gate_fail "$NAME" "проб с находкой: $findings из $probes"
    exit 1
fi

tooling_gate_pass "$NAME" "перепись каскада читает оба отношения, печатает total, расхождение — находка, пустой уровень — не зелёное"
