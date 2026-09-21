#!/usr/bin/env bash
# ПРИБОР: монотонна ли проверка набора ПО ДОПИСЫВАНИЮ. НЕ гейт — вердикта о дереве
# он не выносит; код 0 значит «замер исполнен», код 2 — «замерять оказалось не на чем».
#
# ЧТО МЕРЯЕТСЯ И ЗАЧЕМ. Предикат, построенный на ПРИСУТСТВИИ подстроки, монотонен
# по дописыванию: если подстрока есть в тексте T, она есть и в T + X при любом X.
# Такой предикат ловит УДАЛЕНИЕ нормы и слеп к её ОСЛАБЛЕНИЮ — потому что всякое
# ослабление есть добавление текста: оговорку, исключение, «кроме случаев», новый
# пункт дописывают, не трогая ни одной старой буквы. Проверка, которую невозможно
# уронить дописыванием, стережёт ровно противоположный класс тому, ради которого
# нормы обычно и сторожат.
#
# ЕДИНИЦА ЗАМЕРА ОБЪЯВЛЕНА, ИНАЧЕ ЧИСЛО НЕ ЧИТАЕТСЯ. Ослабляющая вставка — это
# добавление текста в ПРЕДМЕТ ПРОВЕРКИ, не трогающее ни одной существующей
# подстроки: новая строка, новая запись, новый файл, дописанный в конец элемент
# списка. Проверка зовётся НЕМОНОТОННОЙ, если такая вставка существует и роняет
# её; зовётся монотонной, если не существует.
#
# АСИММЕТРИЯ ДОКАЗАТЕЛЬСТВА НАЗВАНА ВСЛУХ. «Немонотонна» доказывается ОДНИМ
# опытом — вот вставка, вот красное. «Монотонна» — утверждение обо ВСЕХ мыслимых
# вставках, и одним опытом не доказывается: прибор его не выносит, а печатает
# «вставки, роняющей проверку, НЕ НАЙДЕНО» вместе с тем, какую пробовал. Выдавать
# ненайденное за несуществующее — ровно та подмена, против которой прибор заведён.
#
# ПЕРЕЧЕНЬ ПРОВЕРОК ВЫВОДИТСЯ ГЛОБОМ ИЗ ДЕРЕВА, А НЕ ВЫПИСАН. Проверка без
# объявленной пробы попадает в строку «НЕ ИЗМЕРЕНО» и считается отдельно: замер,
# умолчавший о неизмеренном, читался бы как полный. Пустой глоб — отказ (код 2),
# а не молчаливый ноль.
#
# ПРОБЫ ИДУТ НА ВРЕМЕННОЙ КОПИИ. Рабочее дерево не правится ни одной пробой.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Песочница — та же пятёрка, что у inject.sh: связка «правило → скилл-ссылка →
# `skills:` агента → база диспетчера → настройки». Урезанная копия отвечала бы
# беспредметностью там, где нужен вердикт.
sandbox() {
    local dir="$TMP/s.$1"
    rm -rf "$dir"; mkdir -p "$dir/.claude"
    cp "$WS/CLAUDE.md" "$dir/"
    cp -a "$WS/.claude/rules" "$dir/.claude/"
    cp -a "$WS/.claude/agents" "$dir/.claude/" 2> /dev/null || true
    cp -a "$WS/.claude/skills" "$dir/.claude/" 2> /dev/null || true
    cp -a "$WS/.claude/settings.json" "$dir/.claude/" 2> /dev/null || true
    cp -a "$WS/.claude/backup" "$dir/.claude/" 2> /dev/null || true
    cp "$WS/.gitignore" "$dir/" 2> /dev/null || true
    git -C "$dir" init -q > /dev/null 2>&1
    git -C "$dir" add -A > /dev/null 2>&1
    echo "$dir"
}

# ОТПЕЧАТОК ПЕСОЧНИЦЫ — страж вакуумной пробы. Проба, ничего не изменившая,
# оставляет проверку зелёной, и замер объявил бы её монотонной по свойству самой
# пробы, а не проверки. Берётся по содержимому и типу записи, не по mtime.
digest() {   # <каталог песочницы>
    (
        cd "$1" 2> /dev/null || exit 0
        find . -path ./.git -prune -o -print0 2> /dev/null \
        | LC_ALL=C sort -z \
        | while IFS= read -r -d '' e; do
              if [ -L "$e" ]; then printf 'l %s -> %s\n' "$e" "$(readlink "$e")"
              elif [ -f "$e" ]; then printf 'f %s %s\n' "$e" "$(md5sum < "$e" | cut -d' ' -f1)"
              else printf 'd %s\n' "$e"; fi
          done
    ) | md5sum | cut -d' ' -f1
}

run_check() {   # <каталог> <имя проверки> -> код в RC
    ( cd "$1" && env RULES_GATE_ROOT="$1" bash "$HERE/$2" ) > /dev/null 2>&1
    RC=$?
}

# Жертвы выводятся из дерева, а не выписываются.
victim_rule=""
for _f in "$WS"/.claude/rules/*.md; do
    [ -f "$_f" ] || continue
    case "$(basename "$_f")" in MANIFEST*) continue ;; esac
    victim_rule="$(basename "$_f")"; break
done
unset -v _f
victim_agent=""
for _a in "$WS"/.claude/agents/*.md; do
    [ -f "$_a" ] || continue
    case "$(basename "$_a")" in dispatcher.md) continue ;; esac
    victim_agent="$(basename "$_a")"; break
done
unset -v _a
if [ -z "$victim_rule" ] || [ -z "$victim_agent" ]; then
    echo "[VOID] замер монотонности — в дереве нет правила либо исполнителя: пробы ставить не на чем" >&2
    exit 2
fi

# ── ПРОБЫ: по одной на проверку, каждая — ЧИСТОЕ ДОПИСЫВАНИЕ ────────────────
#
# Имя функции выводится из имени файла проверки: `check-04-…sh` → `probe_04`.
# Связь по номеру, а не по списку: список разошёлся бы с глобом молча.

# shellcheck disable=SC2329  # зовётся косвенно: имя выводится из имени проверки («check-01-…» → probe_01), прямого вызова нет by construction
probe_01() {   # состав: дописана строка таблицы о правиле, которого нет
    # shellcheck disable=SC2016  # обратные кавычки — разметка markdown фикстуры, не подстановка
    printf '| `probe-monotone-nesushchestvuyushchee.md` | проба | проба | `tooling-maintainer` |\n' \
        >> "$1/.claude/rules/MANIFEST.md"
}

# shellcheck disable=SC2329  # зовётся косвенно: имя выводится из имени проверки («check-02-…» → probe_02), прямого вызова нет by construction
probe_02() {   # автозагрузка: дописана строка-импорт правила в CLAUDE.md
    printf '\n@.claude/rules/%s\n' "$victim_rule" >> "$1/CLAUDE.md"
}

# shellcheck disable=SC2329  # зовётся косвенно: имя выводится из имени проверки («check-03-…» → probe_03), прямого вызова нет by construction
probe_03() {   # полнота строки: дописана строка таблицы с пустыми ячейками
    # shellcheck disable=SC2016  # обратные кавычки — разметка markdown фикстуры, не подстановка
    printf '| `probe-monotone-pustaya.md` |  |  |  |\n' >> "$1/.claude/rules/MANIFEST.md"
}

# shellcheck disable=SC2329  # зовётся косвенно: имя выводится из имени проверки («check-04-…» → probe_04), прямого вызова нет by construction
probe_04() {   # привязка: агенту дописано правило, которого манифест ему не закреплял
    python3 - "$1" "$victim_agent" <<'P4'
import os
import re
import sys

root, agent = sys.argv[1], sys.argv[2]
path = os.path.join(root, ".claude/agents", agent)
lines = open(path, encoding="utf-8").read().split("\n")

# ГРАНИЦЫ FRONTMATTER БЕРУТСЯ ЯВНО, А НЕ РЕГУЛЯРКОЙ ПО СПИСКУ. Первая редакция
# пробы искала список как `(?:\s*-\s*\S+\s*\n)+` — `\s` съел перевод строки,
# закрывающее `---` разобралось как ещё один пункт, и вставка легла в ТЕЛО
# агента. check-04 молчал совершенно законно: его предмет — объявление
# `skills:`, а не проза. Замер тогда вышел «монотонна» — и это было свойство
# вакуумной пробы, а не проверки.
assert lines[0] == "---", "у агента нет frontmatter — проба беспредметна"
close = lines.index("---", 1)
items = [i for i in range(1, close) if re.match(r"^[ \t]+-[ \t]+\S+[ \t]*$", lines[i])]
assert items, "во frontmatter агента нет ни одного пункта списка skills:"

mine = {lines[i].strip().lstrip("-").strip() for i in items}
free = sorted(
    d for d in os.listdir(os.path.join(root, ".claude/skills"))
    if d.startswith("rule-") and d not in mine
)
assert free, "агенту закреплены все правила — дописывать нечего"

lines.insert(items[-1] + 1, "  - " + free[0])
open(path, "w", encoding="utf-8").write("\n".join(lines))

# ПОСТУСЛОВИЕ ПРОБА ПРОВЕРЯЕТ САМА: вставка обязана лежать ВНУТРИ frontmatter.
# Проба, не изменившая ПРЕДМЕТ проверки, даёт зелёное, которое читается как
# «проверка монотонна», — худший исход замера из возможных.
after = open(path, encoding="utf-8").read().split("\n")
close2 = after.index("---", 1)
assert any(free[0] in after[i] for i in range(1, close2)), \
    "вставка легла вне frontmatter — проба вакуумна, замер по check-04 недействителен"
P4
}

# shellcheck disable=SC2329  # зовётся косвенно: имя выводится из имени проверки («check-05-…» → probe_05), прямого вызова нет by construction
probe_05() {   # маршрутизация: дописан файл исполнителя, которого база не знает
    cat > "$1/.claude/agents/probe-monotone.md" <<'AGENT'
---
name: probe-monotone
description: исполнитель, дописанный пробой монотонности
disallowedTools: Agent
---

Тело пробы.
AGENT
}

# shellcheck disable=SC2329  # зовётся косвенно: имя выводится из имени проверки («check-06-…» → probe_06), прямого вызова нет by construction
probe_06() {   # форма корпуса: дописана строка-норма без поля `red:`
    printf '\nprobe-monotone · послабление, дописанное пробой · вниманием\n' \
        >> "$1/.claude/rules/$victim_rule"
}

# shellcheck disable=SC2329  # зовётся косвенно: имя выводится из имени проверки («check-07-…» → probe_07), прямого вызова нет by construction
probe_07() {   # адрес: дописана ссылка в раздел, которого нет
    # shellcheck disable=SC2016  # обратные кавычки — разметка markdown фикстуры, не подстановка
    printf '\nprobe-monotone · см. `ai-tooling.md` §«раздела такого нет, проба монотонности» · вниманием · red: признак\n' \
        >> "$1/.claude/rules/$victim_rule"
}

# shellcheck disable=SC2329  # зовётся косвенно: имя выводится из имени проверки («check-08-…» → probe_08), прямого вызова нет by construction
probe_08() {   # frontmatter: дописан файл правила без frontmatter
    printf 'Файл правил, дописанный пробой монотонности, без frontmatter.\n' \
        > "$1/.claude/rules/probe-monotone.md"
}

# shellcheck disable=SC2329  # зовётся косвенно: имя выводится из имени проверки («check-09-…» → probe_09), прямого вызова нет by construction
probe_09() {   # настройки: дописан ключ, называющий обход подтверждений
    python3 - "$1" <<'PY'
import json
import os
import sys

p = os.path.join(sys.argv[1], ".claude/settings.json")
d = json.load(open(p, encoding="utf-8"))
d["probeMonotone"] = "bypassPermissions"
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
}

# shellcheck disable=SC2329  # зовётся косвенно: имя выводится из имени проверки («check-10-…» → probe_10), прямого вызова нет by construction
probe_10() {   # отпечаток нормы: в охраняемый раздел базы дописана оговорка
    python3 - "$1" <<'PY'
import os
import re
import sys

p = os.path.join(sys.argv[1], ".claude/agents/dispatcher.md")
lines = open(p, encoding="utf-8").read().split("\n")
start = next(i for i, l in enumerate(lines)
             if re.match(r"^##\s+\d+\.\s+Когда спрашивать владельца\s*$", l))
end = next((j for j in range(start + 1, len(lines)) if re.match(r"^##\s", lines[j])),
           len(lines))
last = max(i for i in range(start, end) if lines[i].startswith("- "))
lines.insert(last + 1, "- Перечень выше — ориентир, а не закрытый список.")
open(p, "w", encoding="utf-8").write("\n".join(lines))
PY
}

# shellcheck disable=SC2329  # зовётся косвенно: имя выводится из имени проверки («check-11-…» → probe_11), прямого вызова нет by construction
probe_11() {   # адрес там, где написан: дописан вызов скила-привязки, которого в дереве нет
    # ИМЯ СОБИРАЕТСЯ ИЗ ЧАСТЕЙ, А НЕ ПИШЕТСЯ ЦЕЛИКОМ, И ЭТО НЕСУЩЕЕ.
    # `scripts/**` входит в ОБЛАСТЬ самой проверки, а прибор в ней и лежит.
    # Написанный здесь целиком вызов `Skill rule-<имя>` был бы для неё РАБОЧИМ
    # АДРЕСОМ, ведущим в пустоту, — прибор краснил бы набор собственным текстом
    # фикстуры. Ровно этим до сих пор красит дерево probe_08 (координата
    # фикстуры `probe-monotone.md`, чинится соседней полосой).
    printf '\n%s %s%s — вход пробы монотонности, цели в дереве нет.\n' \
        'Skill' 'rule-' 'probe-monotone-nesushchestvuyushchiy' >> "$1/CLAUDE.md"
}

# ВЕДОМОСТЬ ДОЛГА ДЛЯ check-11 БЕРЁТСЯ ИЗ САМОЙ ПЕСОЧНИЦЫ — И ЭТО РЕШЕНИЕ, А НЕ
# УДОБСТВО. У проверки два входа: дерево (`RULES_GATE_ROOT`) и объявленный долг
# (`RULES_GATE_RULE_ADDRESS_BASELINE`). Песочница прибора — не всё дерево: она
# несёт `.claude/**` и `CLAUDE.md`, а объявленной областью проверки заявлены ещё
# и `scripts/**`. Настоящая ведомость поэтому описывает БОЛЬШЕ, чем песочница
# содержит: замер 2026-09-22 — в песочнице 314 вхождений по 22 именам при
# объявленных 315 по 22, одно живёт вне копии. Сегодня это не красит контроль
# только потому, что проверка требует у записи РОВНО ноль вхождений, а не
# «меньше объявленного»; в день, когда последнее вхождение какого-нибудь имени
# уедет в `scripts/**`, контроль стал бы красным и прибор ответил бы «ЗАМЕР
# НЕГОДЕН» по причине, к монотонности отношения не имеющей.
#
# ВТОРОЙ ЗАКОННЫЙ ИСХОД — «песочница берёт и `scripts/`» — ИЗМЕРЕН И ОТВЕРГНУТ:
# копия со `scripts/` даёт на нетронутом дереве 316 висячих по 23 именам против
# объявленных 315 по 22 («НОВАЯ ПОЛОМКА: путь-правила probe-monotone.md»), то
# есть контроль краснеет сразу и замер по этой проверке не выносится вовсе.
# Починка того адреса — предмет соседней полосы, и ждать её, чтобы измерить
# монотонность, значило бы не измерить её.
#
# ЧТО ЭТО МЕНЯЕТ В СМЫСЛЕ ЗАМЕРА. Вопрос прибора — «роняет ли проверку чистое
# ДОПИСЫВАНИЕ», а не «сошёлся ли сегодня долг дерева». Ведомость, снятая с той
# же песочницы, делает контроль зелёным ПО ПОСТРОЕНИЮ, и красное после пробы
# приходит ровно от дописанного имени, которого нет ни в дереве, ни в ведомости.
# Шов объявлен самой проверкой и тем же швом пользуется `inject.sh` (ось C).
RULE_ADDRESS_REFS="$HERE/rule-address-refs.py"
if [ -f "$RULE_ADDRESS_REFS" ]; then
    _seam_dir="$(sandbox seam)"
    if python3 "$RULE_ADDRESS_REFS" --root "$_seam_dir" --emit-baseline \
            > "$TMP/rule-address-baseline.sandbox.txt" 2> /dev/null; then
        export RULES_GATE_RULE_ADDRESS_BASELINE="$TMP/rule-address-baseline.sandbox.txt"
    fi
    unset -v _seam_dir
fi

# СТРОКА ТАБЛИЦЫ ВЫРАВНИВАЕТСЯ ПО СИМВОЛАМ, А НЕ ПО БАЙТАМ. `printf %-10s`
# считает байты, а «нет» в UTF-8 весит шесть, — колонки разъезжались, и таблицу,
# ради которой прибор и заведён, становилось трудно читать.
row() {   # <гейт> <вердикт> <чем проверил>
    local a="$1" b="$2" c="$3" pa="" pb="" i
    for (( i = ${#a}; i < 48; i++ )); do pa="$pa "; done
    for (( i = ${#b}; i < 11; i++ )); do pb="$pb "; done
    printf '%s%s | %s%s | %s\n' "$a" "$pa" "$b" "$pb" "$c"
}

# ── ЗАМЕР ────────────────────────────────────────────────────────────────────
checks=0; mono=0; nonmono=0; unmeasured=0; broken=0
row "гейт" "монотонен" "чем проверил"
printf -- '---\n'
for c in "$HERE"/check-*; do
    [ -f "$c" ] || continue
    checks=$((checks + 1))
    name="$(basename "$c")"
    num="$(printf '%s' "$name" | sed -n 's/^check-\([0-9][0-9]*\)-.*/\1/p')"
    fn="probe_$num"

    if ! command -v "$fn" > /dev/null 2>&1; then
        unmeasured=$((unmeasured + 1))
        row "$name" "НЕ ИЗМЕРЕНО" \
            "пробы дописывания для неё не объявлено — замер по ней НЕ вынесен"
        continue
    fi

    # Контроль: на нетронутой копии проверка обязана молчать, иначе красное после
    # пробы пришло бы не от пробы.
    d="$(sandbox "ctl$num")"
    run_check "$d" "$name"
    if [ "$RC" != 0 ]; then
        broken=$((broken + 1))
        row "$name" "ЗАМЕР НЕГОДЕН" \
            "на нетронутой копии код $RC — вердикт после пробы был бы не о пробе"
        continue
    fi

    d="$(sandbox "prb$num")"
    before="$(digest "$d")"
    if ! "$fn" "$d" > /dev/null 2>&1; then
        unmeasured=$((unmeasured + 1))
        row "$name" "НЕ ИЗМЕРЕНО" \
            "проба не исполнилась (предпосылка не создалась) — замер НЕ вынесен"
        continue
    fi
    if [ "$(digest "$d")" = "$before" ]; then
        unmeasured=$((unmeasured + 1))
        row "$name" "НЕ ИЗМЕРЕНО" \
            "проба ВАКУУМНА — песочница не изменилась; зелёное относилось бы к нетронутой копии"
        continue
    fi
    run_check "$d" "$name"
    if [ "$RC" = 0 ]; then
        mono=$((mono + 1))
        row "$name" "ДА" \
            "дописывание ($fn) оставило код 0 — вставка, роняющая её, НЕ НАЙДЕНА"
    else
        nonmono=$((nonmono + 1))
        row "$name" "нет" \
            "дописывание ($fn) дало код $RC"
    fi
done

echo
if [ "$checks" -eq 0 ]; then
    echo "[VOID] замер монотонности — проверок в $HERE не найдено: мерить нечего" >&2
    exit 2
fi
echo "[CENSUS] замер монотонности по дописыванию: проверок набора $checks;" \
     "немонотонных $nonmono; монотонных (вставка не найдена) $mono;" \
     "НЕ ИЗМЕРЕНО $unmeasured; замер негоден $broken."
echo "         «Монотонна» здесь значит «роняющей вставки НЕ НАЙДЕНО пробой $0»," \
     "а не «её не существует»: универсальное утверждение одним опытом не доказывается."
exit 0
