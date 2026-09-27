#!/usr/bin/env bash
# ЧАСТЬ инъекции набора: доказательство check-15 «имя, которое тело оснастки зовёт,
# резолвится» — по каждому роду цели (вызов `Skill`, строка `skills:`, путь
# `.claude/…`) и по каждой законной форме записи, с близнецом той же формы и
# отказом на пустом обходе.
#
# Файл ПОДКЛЮЧАЕТСЯ (`.`) из `inject.sh` и пользуется его оснасткой.
#
# shellcheck disable=SC2154,SC2016
# SC2154: `pass`, `fail`, `WS` задаёт подключающий `inject.sh` — часть их только читает.
# SC2016: одинарные кавычки у тел фикстур намеренны — обратные кавычки и `$CLAUDE_PROJECT_DIR`
# обязаны доехать в файл буквально: это и есть проверяемая форма записи.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — ЧАСТЬ инъекции, а не самостоятельная проба." >&2
    echo "       Запускать: bash scripts/rules-gate/inject.sh" >&2
    exit 2
fi
for _i15_fn in sandbox capture assert_code assert_says assert_fixture_changed sandbox_digest; do
    command -v "$_i15_fn" >/dev/null 2>&1 && continue
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — оснастки inject.sh нет: функция" \
         "«$_i15_fn» не определена; часть подключена не оттуда" >&2
    exit 2
done
unset -v _i15_fn

C15=check-15-named-loads-resolve.sh
i15_before=$((pass + fail))

# Жертвы выводятся из дерева: исполнитель (не диспетчер), существующий скил-переходник
# и существующий файл архива. Синтетическое имя проверяется на синтетичность.
i15_agent=""
for _a in "$WS"/.claude/agents/*.md; do
    case "$(basename "$_a")" in dispatcher.md) continue ;; esac
    grep -q '^skills:' "$_a" && { i15_agent=".claude/agents/$(basename "$_a")"; break; }
done
i15_skill=""
for _s in "$WS"/.claude/skills/rule-*/SKILL.md; do
    [ -e "$_s" ] && { i15_skill="$(basename "$(dirname "$_s")")"; break; }
done
i15_arch=""
for _b in "$WS"/.claude/backup/*.md; do
    [ -f "$_b" ] && { i15_arch=".claude/backup/$(basename "$_b")"; break; }
done
unset -v _a _s _b
i15_ghost="rule-inj15-ghost"
if [ -z "$i15_agent" ] || [ -z "$i15_skill" ] || [ -z "$i15_arch" ] \
   || [ -e "$WS/.claude/skills/$i15_ghost" ]; then
    echo "[VOID] inject-15 — жертвы не выведены: агент «$i15_agent», скил «$i15_skill»," \
         "архив «$i15_arch»; либо синтетическое имя $i15_ghost перестало быть синтетическим" >&2
    fail=$((fail + 1))
else
    echo "жертвы: агент $i15_agent · скил $i15_skill · архив $i15_arch · призрак $i15_ghost"

    # i15_hooks <песочница> — хуки в песочницу: общий `sandbox` их не копирует.
    i15_hooks() {
        cp -a "$WS/.claude/hooks" "$1/.claude/" 2>/dev/null || mkdir -p "$1/.claude/hooks"
        git -C "$1" add -A >/dev/null 2>&1 || true
    }

    # ── род 1: вызов Skill ───────────────────────────────────────────────────
    d="$(sandbox i15_call)"
    printf '\n| условие | `Skill %s` | зачем |\n' "$i15_ghost" >> "$d/$i15_agent"
    capture "$d" "$C15"
    assert_code 1 "ДЕФЕКТ: тело зовёт скил без каталога — краснеет"
    assert_says "Skill $i15_ghost" "  ...и называет имя"
    assert_says "$i15_agent:" "  ...и называет файл со строкой"

    d="$(sandbox i15_call_bare)"
    printf '\nсработало — бери Skill %s по условию.\n' "$i15_ghost" >> "$d/$i15_agent"
    capture "$d" "$C15"
    assert_code 1 "ДЕФЕКТ: тот же вызов без code span — краснеет (форма не спасает)"

    d="$(sandbox i15_call_dangle)"
    mkdir -p "$d/.claude/skills/rule-inj15-dangle"
    ln -s ../../rules/inj15-nope.md "$d/.claude/skills/rule-inj15-dangle/SKILL.md"
    printf '\n| условие | `Skill rule-inj15-dangle` | зачем |\n' >> "$d/$i15_agent"
    git -C "$d" add -A >/dev/null 2>&1 || true
    capture "$d" "$C15"
    assert_code 1 "ДЕФЕКТ: каталог скила есть, ссылка висит — краснеет"

    d="$(sandbox i15_call_twin)"; b="$(sandbox_digest "$d")"
    printf '\n| условие | `Skill %s` | зачем |\n' "$i15_skill" >> "$d/$i15_agent"
    assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: та же строка с существующим скилом"
    capture "$d" "$C15"
    assert_code 0 "БЛИЗНЕЦ: вызов существующего скила той же формы — молчит"

    d="$(sandbox i15_call_templ)"; b="$(sandbox_digest "$d")"
    printf '\nНужное по условию — `Skill rule-<имя>`; плагин — `Skill superpowers:brainstorming`; инструмент Skill tool.\n' >> "$d/$i15_agent"
    assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: шаблон, имя плагина и проза"
    capture "$d" "$C15"
    assert_code 0 "БЛИЗНЕЦ: шаблон вызова, скил плагина и проза «Skill tool» — молчит"

    # ── род 2: skills: во frontmatter ────────────────────────────────────────
    d="$(sandbox i15_fm)"
    python3 - "$d/$i15_agent" "$i15_ghost" <<'PY'
import sys
p, name = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
assert "\nskills:\n" in s, "у жертвы нет skills:"
open(p, "w", encoding="utf-8").write(s.replace("\nskills:\n", "\nskills:\n  - %s\n" % name, 1))
PY
    capture "$d" "$C15"
    assert_code 1 "ДЕФЕКТ: skills: называет скил без каталога — краснеет"
    assert_says "skills: «$i15_ghost»" "  ...и называет строку frontmatter"

    d="$(sandbox i15_fm_twin)"; b="$(sandbox_digest "$d")"
    python3 - "$d/$i15_agent" "$i15_skill" <<'PY'
import sys
p, name = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(s.replace("\nskills:\n", "\nskills:\n  - %s\n" % name, 1))
PY
    assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: skills: называет существующий скил"
    capture "$d" "$C15"
    assert_code 0 "БЛИЗНЕЦ: строка skills: с существующим скилом — молчит"

    # ── род 3: путь .claude/… ────────────────────────────────────────────────
    d="$(sandbox i15_path)"
    printf '\nНорма — `.claude/rules/inj15-ghost.md` §1.\n' >> "$d/$i15_agent"
    capture "$d" "$C15"
    assert_code 1 "ДЕФЕКТ: тело называет путь правила, которого нет — краснеет"
    assert_says ".claude/rules/inj15-ghost.md" "  ...и называет путь"

    d="$(sandbox i15_path_twin)"; b="$(sandbox_digest "$d")"
    printf '\nДовод — `%s` §1; личное — `~/.claude/settings.json`; чужое — `project/kacho/.claude/x.md`;\nмаска — `.claude/skills/rule-*/SKILL.md`; машина — `.claude/settings.local.json`.\n' \
        "$i15_arch" >> "$d/$i15_agent"
    assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: архив, личный, чужой, маска, игнорируемый"
    capture "$d" "$C15"
    assert_code 0 "БЛИЗНЕЦ: путь в архив, чужое дерево, маска и игнорируемый файл — молчит"

    # ── хуки: печатаемый адрес и корень переменной ───────────────────────────
    d="$(sandbox i15_hook)"; i15_hooks "$d"
    printf '#!/usr/bin/env bash\necho "Норма: .claude/rules/inj15-ghost.md"\n' > "$d/.claude/hooks/zz-inj15.sh"
    git -C "$d" add -A >/dev/null 2>&1 || true
    capture "$d" "$C15"
    assert_code 1 "ДЕФЕКТ: живой хук печатает путь, которого нет — краснеет"

    d="$(sandbox i15_hook_var)"; i15_hooks "$d"
    printf '#!/usr/bin/env bash\nexec bash "$CLAUDE_PROJECT_DIR/.claude/hooks/zz-inj15-nope.sh"\n' > "$d/.claude/hooks/zz-inj15.sh"
    git -C "$d" add -A >/dev/null 2>&1 || true
    capture "$d" "$C15"
    assert_code 1 "ДЕФЕКТ: хук зовёт файл от корня-переменной, файла нет — краснеет"

    d="$(sandbox i15_hook_var_twin)"; i15_hooks "$d"; b="$(sandbox_digest "$d")"
    printf '#!/usr/bin/env bash\nexec bash "$CLAUDE_PROJECT_DIR/.claude/hooks/zz-inj15.sh"\n' > "$d/.claude/hooks/zz-inj15.sh"
    git -C "$d" add -A >/dev/null 2>&1 || true
    assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: тот же вызов существующего файла"
    capture "$d" "$C15"
    assert_code 0 "БЛИЗНЕЦ: корень-переменная и существующий файл — молчит"

    # Каталог с `prove.sh` несёт фикстуры проб: мёртвый путь там законен. Та же
    # строка в каталоге БЕЗ пробы — находка: исключение выводится признаком, не именем.
    d="$(sandbox i15_proof_twin)"; i15_hooks "$d"; b="$(sandbox_digest "$d")"
    mkdir -p "$d/.claude/hooks/zz-inj15"
    printf '#!/usr/bin/env bash\n# проба\n' > "$d/.claude/hooks/zz-inj15/prove.sh"
    printf 'вход пробы: .claude/rules/inj15-ghost.md\n' > "$d/.claude/hooks/zz-inj15/fixture.md"
    git -C "$d" add -A >/dev/null 2>&1 || true
    assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: фикстура в каталоге пробы"
    capture "$d" "$C15"
    assert_code 0 "БЛИЗНЕЦ: мёртвый путь во входе пробы (каталог с prove.sh) — молчит"

    d="$(sandbox i15_proof)"; i15_hooks "$d"
    mkdir -p "$d/.claude/hooks/zz-inj15"
    printf 'вход пробы: .claude/rules/inj15-ghost.md\n' > "$d/.claude/hooks/zz-inj15/fixture.md"
    git -C "$d" add -A >/dev/null 2>&1 || true
    capture "$d" "$C15"
    assert_code 1 "ДЕФЕКТ: та же строка в каталоге БЕЗ пробы — краснеет"

    # ── пустой обход ─────────────────────────────────────────────────────────
    d="$(sandbox i15_void)"
    rm -rf "$d/.claude/agents"
    git -C "$d" add -A >/dev/null 2>&1 || true
    capture "$d" "$C15"
    assert_code 2 "ОТКАЗ: агентов нет — VOID, а не «всё резолвится»"
fi
# Перепись части — отдельной строкой: «разошлось 0» без числа исполненных здесь
# утверждений неотличимо от части, которая не исполнила ни одного.
echo "[CENSUS] inject-15: утверждений исполнено $((pass + fail - i15_before))"
if [ "$((pass + fail - i15_before))" -eq 0 ]; then
    echo "[VOID] inject-15 — ни одного утверждения: часть ничего не доказала" >&2
    fail=$((fail + 1))
fi
