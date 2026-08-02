#!/usr/bin/env bash
# Доказательство КАЖДОГО гейта набора инъекцией — В ОБЕ СТОРОНЫ.
#
# Гейт, доказанный только красной половиной, ловит форму, а не существо: первый
# ложный срабат его отключит. Поэтому у каждой инъекции дефекта здесь стоит
# ЗАКОННЫЙ БЛИЗНЕЦ той же формы, на котором гейт обязан молчать
# (`gate-authoring` §Инъекция).
#
# Работает на ВРЕМЕННОЙ копии дерева (`SKILLS_GATE_ROOT`) — рабочее не трогается.
# Копия делается из git-состояния workspace + рабочих файлов скилов и правил.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="$(cd "$SCRIPT_DIR/../.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.claude"
cp -r "$WS/.claude/skills" "$TMP/.claude/skills"
cp -r "$WS/.claude/rules"  "$TMP/.claude/rules"
# .gitignore едет вместе: без него временное дерево «отслеживает» и посторонние
# скилы, и перепись гейта 03 разойдётся с настоящей по причине, к предмету
# отношения не имеющей.
cp "$WS/.gitignore" "$TMP/.gitignore"
git -C "$TMP" init -q
git -C "$TMP" add -A >/dev/null 2>&1

CA="$TMP/.claude/skills/code-authoring/SKILL.md"
GA="$TMP/.claude/skills/gate-authoring/SKILL.md"
SS="$TMP/.claude/skills/security-surface/SKILL.md"
AT="$TMP/.claude/rules/ai-tooling.md"

pass=0
fail=0

# run <ожидаемый-код> <имя-пробы> <скрипт>
run() {
    local want="$1" label="$2" script="$3" out got
    out="$(SKILLS_GATE_ROOT="$TMP" bash "$SCRIPT_DIR/$script" 2>&1)"; got=$?
    if [ "$got" -eq "$want" ]; then
        pass=$((pass + 1)); printf '  [ok]   %-58s код %s\n' "$label" "$got"
    else
        fail=$((fail + 1)); printf '  [БЕДА] %-58s ждали %s, получили %s\n' "$label" "$want" "$got"
        printf '%s\n' "$out" | sed 's/^/         /'
    fi
    LAST_OUT="$out"
}

restore() { git -C "$TMP" checkout -- . >/dev/null 2>&1; }

echo "== гейт 01 — ссылка на норму по имени раздела =="

restore
run 0 "чистое дерево (законный близнец: все ссылки по имени)" check-01-section-refs.sh

restore
printf '\nВременная строка: норма — `security.md:361`.\n' >> "$GA"
run 1 "инъекция: ссылка номером строки" check-01-section-refs.sh
grep -q 'gate-authoring/SKILL.md' <<<"${LAST_OUT:-}" \
    && printf '  [ok]   инъекция названа координатой\n' && pass=$((pass + 1)) \
    || { printf '  [БЕДА] гейт покраснел, но координату не назвал\n'; fail=$((fail + 1)); }

restore
printf '\nВременная строка: норма — `security.md` §Hardening-инварианты п.8.\n' >> "$GA"
run 0 "законный близнец: та же ссылка по имени раздела" check-01-section-refs.sh

restore
printf '\nВременная строка: норма — `security.md` §Такого-раздела-здесь-нет.\n' >> "$GA"
run 1 "инъекция: §-имя, которое не резолвится" check-01-section-refs.sh

restore
# предпосылка гейта: корпус без ссылок на нормы вообще ⇒ VOID, не успех
find "$TMP/.claude/skills" -name SKILL.md -exec sed -i 's/\.md/·md/g' {} +
run 2 "предпосылка: ссылок на нормы нет ⇒ VOID, не успех" check-01-section-refs.sh

echo
echo "== гейт 02 — семь частей записи =="

restore
run 0 "чистое дерево (законный близнец: все записи полны)" check-02-record-parts.sh

restore
# снять предикат снятия у одной записи
perl -0pi -e 's/^> \*\*Предикат снятия:\*\*.*?\n//m' "$CA"
run 1 "инъекция: у записи снят предикат снятия" check-02-record-parts.sh
grep -q '### ' <<<"${LAST_OUT:-}" \
    && printf '  [ok]   инъекция названа записью\n' && pass=$((pass + 1)) \
    || { printf '  [БЕДА] гейт покраснел, но запись не назвал\n'; fail=$((fail + 1)); }

restore
# законный близнец: запись БЕЗ предметного содержания вне §1–§7 (в §9) гейт не трогает
printf '\n### 9.9. Служебная запись без семи частей\n\nПросто текст.\n' >> "$CA"
run 0 "законный близнец: «### N.N» вне §1–§7 не считается записью" check-02-record-parts.sh

restore
# дата без ревизии — половина части, обязана ловиться
perl -0pi -e 's/^(> \*\*Наблюдение:\*\* [0-9]{4}-[0-9]{2}-[0-9]{2}).*$/$1./m' "$CA"
run 1 "инъекция: дата есть, ревизии нет" check-02-record-parts.sh

restore
# предпосылка гейта: сменилась форма объявления разделов ⇒ VOID, не успех
sed -i 's/^## §1\./## Раздел 1./' "$CA"
run 2 "предпосылка: форма объявления разделов сменилась ⇒ VOID" check-02-record-parts.sh

echo
echo "== гейт 03 — перечень сходится с деревом =="

restore
run 0 "чистое дерево (законный близнец: перечень = дерево)" check-03-roster-matches-tree.sh

restore
perl -0pi -e 's/^- `measurement-discipline` \(workspace\).*?\n//ms' "$AT"
run 1 "инъекция: скил есть в дереве, но выпал из перечня" check-03-roster-matches-tree.sh
grep -q 'measurement-discipline' <<<"${LAST_OUT:-}" \
    && printf '  [ok]   инъекция названа именем скила\n' && pass=$((pass + 1)) \
    || { printf '  [БЕДА] гейт покраснел, но имя не назвал\n'; fail=$((fail + 1)); }

restore
perl -0pi -e 's/^(## Канонические скилы.*?\n)/$1\n- `skil-kotorogo-net` (workspace) — просроченное объявление.\n/ms' "$AT"
run 1 "инъекция: перечень называет скил, которого в дереве нет" check-03-roster-matches-tree.sh

restore
# законный близнец: строка про repo-скил `<svc>-load-testing` исключается намеренно
run 0 "законный близнец: строка repo-скила в счёт не идёт" check-03-roster-matches-tree.sh

restore
sed -i 's/^## Канонические скилы.*/## Список скилов/' "$AT"
run 2 "предпосылка: заголовок перечня сменился ⇒ VOID" check-03-roster-matches-tree.sh

echo
echo "== гейт 04 — три части записи каталога поверхностей =="

restore
run 0 "чистое дерево (законный близнец: все записи полны)" check-04-surface-record-parts.sh

restore
# снять противоядие у одной записи
perl -0pi -e 's/^\*\*Противоядие\.\*\* /ЗАМЕНЕНО: /m' "$SS"
run 1 "инъекция: у записи снято противоядие" check-04-surface-record-parts.sh
grep -q '### S' <<<"${LAST_OUT:-}" \
    && printf '  [ok]   инъекция названа записью\n' && pass=$((pass + 1)) \
    || { printf '  [БЕДА] гейт покраснел, но запись не назвал\n'; fail=$((fail + 1)); }

restore
# снять держателя у одной записи
perl -0pi -e 's/^> \*\*Держится:\*\* /> Держится: /m' "$SS"
run 1 "инъекция: у записи не сказано, чем она держится" check-04-surface-record-parts.sh

restore
# ЗАКОННЫЙ БЛИЗНЕЦ: заголовок ТОЙ ЖЕ формы, но вне каталога поверхностей.
# Без этой половины гейт ловил бы форму «### S<N>.<M>» где угодно в файле.
perl -0pi -e 's/^## §12\./### S9.9. Пример формы, не запись\n\nТекст без частей.\n\n## §12./m' "$SS"
run 0 "законный близнец: «### S<N>.<M>» вне каталога записью не считается" check-04-surface-record-parts.sh

restore
# счёт и проверка полноты обязаны читать ОДНО множество
perl -0pi -e 's/^\*\*Записей класса — [0-9]+\*\*/**Записей класса — 999**/m' "$SS"
run 1 "инъекция: объявленное число разошлось с осмотренным" check-04-surface-record-parts.sh

restore
# предпосылка гейта: сменилась форма объявления поверхностей ⇒ VOID, не успех
sed -i 's/^## S1\./## Поверхность 1./' "$SS"
run 2 "предпосылка: форма объявления поверхностей сменилась ⇒ VOID" check-04-surface-record-parts.sh

restore
echo
echo "итог инъекций: проб пройдено $pass, провалено $fail"
[ "$fail" -eq 0 ]
