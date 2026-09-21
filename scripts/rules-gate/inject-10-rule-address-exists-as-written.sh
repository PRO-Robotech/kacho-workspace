#!/usr/bin/env bash
# shellcheck disable=SC2016
#   Вносимые строки — markdown: обратные кавычки в них разметка, а не подстановка
#   команды. Одинарные кавычки здесь намеренны на весь файл, как и в inject.sh.
# ЧАСТЬ инъекции набора: доказательство check-10 «адрес правила и скила-привязки
# резолвится там, где написан» по трём осям находки и трём законным близнецам.
#
# Оси находки различны по СУЩЕСТВУ, а не по букве: новая поломка (имени нет в
# объявленном долге), рост долга (имя есть, вхождений стало больше) и зажившая
# запись (в долге числится, в дереве не осталось). Третья — самоистечение: база
# не вправе пережить свой предмет, иначе гейт зеленеет на записи, которой нечего
# исключать.
#
# Файл ПОДКЛЮЧАЕТСЯ (`.`) из `inject.sh` и пользуется его оснасткой.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — ЧАСТЬ инъекции, а не самостоятельная проба." >&2
    echo "       Запускать: bash scripts/rules-gate/inject.sh" >&2
    exit 2
fi
for _i10_fn in sandbox capture assert_code assert_fixture_changed sandbox_digest; do
    command -v "$_i10_fn" >/dev/null 2>&1 && continue
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — оснастки inject.sh нет: функция" \
         "«$_i10_fn» не определена" >&2
    exit 2
done
unset -v _i10_fn
if [ -z "${GATE:-}" ] || [ ! -d "$GATE" ] || [ -z "${TMP:-}" ] || [ ! -d "$TMP" ]; then
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — \$GATE либо \$TMP не определён" >&2
    exit 2
fi

C10=check-10-rule-address-exists-as-written.sh
BL10="$GATE/rule-address-baseline.txt"

# ЖЕРТВА И ЗАКОННАЯ ЦЕЛЬ ВЫВОДЯТСЯ ИЗ ДЕРЕВА, а не выписываются именем: имя в
# коде рассыпалось бы вместе с раскладкой, а предмет осей от него не зависит.
V10=""
while IFS= read -r _v; do
    [ -f "$_v" ] || continue
    V10=".claude/agents/$(basename "$_v")"; break
done < <(printf '%s\n' "$WS"/.claude/agents/*.md | LC_ALL=C sort)
unset -v _v
LIVE_RULE=""; LIVE_SKILL=""
while IFS= read -r _r; do
    [ -f "$_r" ] || continue
    LIVE_RULE="$(basename "$_r")"
    [ -e "$WS/.claude/skills/rule-${LIVE_RULE%.md}/SKILL.md" ] || { LIVE_RULE=""; continue; }
    LIVE_SKILL="rule-${LIVE_RULE%.md}"; break
done < <(printf '%s\n' "$WS"/.claude/rules/*.md | LC_ALL=C sort)
unset -v _r
if [ -z "$V10" ] || [ -z "$LIVE_SKILL" ]; then
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — в дереве нет агента либо нет правила" \
         "с парным скилом-ссылкой: ни дефект вписать некуда, ни законную цель взять" >&2
    exit 2
fi
# Имя из объявленного долга берётся ИЗ САМОЙ БАЗЫ: выписанное здесь разошлось бы
# с ней молча ровно в тот день, когда долг сократят.
DEBT_SKILL="$(awk '$2=="Skill"{print $3; exit}' "$BL10")"
if [ -z "$DEBT_SKILL" ]; then
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — в объявленном долге нет ни одной" \
         "записи формы Skill: ось «долг вырос» беспредметна" >&2
    exit 2
fi

# ── ось A: НОВАЯ ПОЛОМКА — имени нет в объявленном долге ─────────────────────
d="$(sandbox i10_new)"
printf '\n| правишь что-нибудь | `Skill rule-takogo-skila-net-v-dereve` | § |\n' >> "$d/$V10"
capture "$d" "$C10"
assert_code 1 "ДЕФЕКТ: вызов скила, которого в дереве нет и в долге не объявлено — краснеет"

# ── ось A2: та же поломка ДРУГОЙ ЗАКОННОЙ ФОРМОЙ — путь к файлу правила ──────
# Распознаватель, знающий лишь одну форму записи адреса, молчит на остальных, и
# это слепая зона, а не успех.
d="$(sandbox i10_new_path)"
printf '\nНорма — `.claude/rules/takogo-pravila-net-v-dereve.md` §«Раздел».\n' >> "$d/$V10"
capture "$d" "$C10"
assert_code 1 "ДЕФЕКТ: путь к правилу, которого нет — краснеет той же осью"

# ── ось B: ДОЛГ ВЫРОС — имя объявлено, вхождений стало больше ────────────────
d="$(sandbox i10_grew)"
printf '\n| ещё одно условие | `Skill %s` | § |\n' "$DEBT_SKILL" >> "$d/$V10"
capture "$d" "$C10"
assert_code 1 "ДЕФЕКТ: объявленный долг вырос на одно вхождение — краснеет"

# ── ось C: ЗАЖИВШАЯ ЗАПИСЬ — в долге числится, в дереве не осталось ──────────
# Подменная база — законный шов проверки: настоящую база сокращает отдельная
# полоса, и ждать её, чтобы доказать самоистечение, значило бы не доказать его.
d="$(sandbox i10_healed)"
cp "$BL10" "$TMP/bl10.healed.txt"
printf '1 Skill rule-etogo-imeni-v-dereve-net\n' >> "$TMP/bl10.healed.txt"
capture "$d" "$C10" RULES_GATE_RULE_ADDRESS_BASELINE="$TMP/bl10.healed.txt"
assert_code 1 "ДЕФЕКТ: запись долга, которой нечего исключать — краснеет и требует убрать её"

# ── БЛИЗНЕЦ 1: те же две формы, но цель в дереве ЕСТЬ ────────────────────────
d="$(sandbox i10_twin_live)"; b="$(sandbox_digest "$d")"
printf '\n| правишь что-нибудь | `Skill %s` | § |\nНорма — `.claude/rules/%s` §«Раздел».\n' \
    "$LIVE_SKILL" "$LIVE_RULE" >> "$d/$V10"
assert_fixture_changed "$d" "$b" "близнец: ссылка на существующие скил и правило"
capture "$d" "$C10"
assert_code 0 "БЛИЗНЕЦ: те же формы на СУЩЕСТВУЮЩУЮ цель — молчит"

# ── БЛИЗНЕЦ 2: тот же висячий адрес В АРХИВЕ ────────────────────────────────
# Архив называет координаты, верные на момент снятия, и живым предписанием не
# является. Гейт, краснеющий и здесь, требовал бы чинить историю.
d="$(sandbox i10_twin_archive)"; b="$(sandbox_digest "$d")"
printf '\n`Skill rule-takogo-skila-net-v-dereve` — координата на момент снятия.\n' \
    >> "$d/.claude/backup/README.md"
assert_fixture_changed "$d" "$b" "близнец: тот же висячий адрес в архиве"
capture "$d" "$C10"
assert_code 0 "БЛИЗНЕЦ: висячий адрес в объявленном архиве — молчит"

# ── ось D: РОЛЬ ПРОИЗВОДИТЕЛЯ ВЫВЕДЕНА, А НЕ ВЫПИСАНА ИМЕНЕМ ─────────────────
#
# До 2026-09-21 производители фикстур исключались закрытым списком `inject*` и
# `prove.sh`. Список — не свойство роли: полоса завела производителя той же роли
# под третьим именем, и гейт покраснел на координате, правилом не являющейся.
# Две фикстуры ниже отличаются РОВНО ОДНИМ ФАКТОМ — создающий акт стоит в
# исполняемой строке либо в комментарии, — и потому красное одной приходит
# только от этого факта, а не от соседнего.
I10_PRODUCER=".claude/hooks/zz-proba-roli-proizvoditelya.sh"
I10_ADDR=".claude/rules/probe-roli-net-v-dereve.md"

# ДЕФЕКТ: создающий акт только ПРОЦИТИРОВАН в комментарии — файл производителем
# не является, и висячий адрес в его исполняемой строке обязан краснеть.
d="$(sandbox i10_role_prose)"
mkdir -p "$d/$(dirname "$I10_PRODUCER")"
{   printf '#!/usr/bin/env bash\n'
    printf '# производитель делает так: mkdir -p "$d/.claude/rules"\n'
    printf 'echo "норма — %s"\n' "$I10_ADDR"
} > "$d/$I10_PRODUCER"
capture "$d" "$C10"
assert_code 1 "ДЕФЕКТ: создающий акт в КОММЕНТАРИИ роли не даёт — висячий адрес краснеет"

# БЛИЗНЕЦ 3: тот же адрес в файле, который дерево `.claude/` ДЕЙСТВИТЕЛЬНО
# создаёт, и имя у файла произвольное — ни `inject*`, ни `prove.sh`. Молчание
# здесь и есть доказательство, что признак выводится из действия, а не из имени:
# следующий производитель под четвёртым именем красного не получит.
d="$(sandbox i10_role_code)"
mkdir -p "$d/$(dirname "$I10_PRODUCER")"
b="$(sandbox_digest "$d")"
{   printf '#!/usr/bin/env bash\n'
    printf 'd="$(mktemp -d)"\n'
    printf 'mkdir -p "$d/.claude/rules"\n'
    printf 'echo "норма — %s"\n' "$I10_ADDR"
} > "$d/$I10_PRODUCER"
assert_fixture_changed "$d" "$b" "близнец: производитель под произвольным именем"
capture "$d" "$C10"
assert_code 0 "БЛИЗНЕЦ: файл СОЗДАЁТ дерево .claude/ — координата в нём вход, а не адрес; имя роли не решает"

# ── ПРЕДПОСЫЛКА: файлов оснастки нет — VOID, а не успех ─────────────────────
d="$(sandbox i10_void)"
rm -rf "$d/.claude" "$d/CLAUDE.md"
capture "$d" "$C10"
assert_code 2 "ПРЕДПОСЫЛКА: файлов оснастки нет — VOID, а не успех"
