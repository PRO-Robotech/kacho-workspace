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

    # ── род 2: ВСЕ законные формы записи списка YAML ─────────────────────────
    # Распознаватель знал одну форму («  - имя» без кавычек); на первой строке
    # иной формы он выходил из списка, и остаток списка не судился МОЛЧА. Каждая
    # форма — дефект (к настоящему списку жертвы дописан призрак) и близнец (тот же
    # настоящий список той же формой). Смешанная форма («"a"», затем «b») ловит
    # ровно отказ «первая нераспознанная строка обрывает список».
    # i15_fm_form <песочница> <форма> [призрак] — переписать skills: жертвы формой
    i15_fm_form() {
        python3 - "$1/$i15_agent" "$2" "${3:-}" <<'PY'
import re, sys
p, form, ghost = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
end = s.index("\n---", 3)
fm, rest = s[:end], s[end:]
m = re.search(r"\nskills:\n((?:[ \t]+-[^\n]*\n?)+)", fm + "\n")
assert m, "у жертвы нет блочного skills:"
names = re.findall(r"-\s+(\S+)", m.group(1)) + ([ghost] if ghost else [])
if form == "dq":
    body = "".join('  - "%s"\n' % n for n in names)
elif form == "sq":
    body = "".join("  - '%s'\n" % n for n in names)
elif form == "comment":
    body = "".join("  - %s  # зачем\n" % n for n in names)
elif form == "zero":
    body = "".join("- %s\n" % n for n in names)
elif form == "mixed":
    body = '  - "%s"\n' % names[0] + "".join("  - %s\n" % n for n in names[1:])
elif form == "flow":
    new = fm[:m.start()] + "\nskills: [" + ", ".join(names) + "]\n" + fm[m.end():]
    open(p, "w", encoding="utf-8").write(new.rstrip("\n") + rest)
    sys.exit(0)
new = fm[:m.start()] + "\nskills:\n" + body + fm[m.end():]
open(p, "w", encoding="utf-8").write(new.rstrip("\n") + rest)
PY
    }
    for _form in dq sq comment zero mixed flow; do
        d="$(sandbox "i15_fm_$_form")"
        i15_fm_form "$d" "$_form" "$i15_ghost"
        capture "$d" "$C15"
        assert_code 1 "ДЕФЕКТ: skills: формой «$_form» называет скил без каталога — краснеет"
        assert_says "«$i15_ghost»" "  ...и называет имя (форма «$_form»)"
        d="$(sandbox "i15_fm_${_form}_twin")"; b="$(sandbox_digest "$d")"
        i15_fm_form "$d" "$_form"
        assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: настоящий список формой «$_form»"
        capture "$d" "$C15"
        assert_code 0 "БЛИЗНЕЦ: настоящий список формой «$_form» — молчит"
    done
    unset -v _form

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

    # Путь от корня формой `./.claude/…`: сегмент «.» — это корень, а не чужое
    # дерево. Близнец — та же форма на существующий файл архива.
    d="$(sandbox i15_path_dot)"
    printf '\nНорма — `./.claude/rules/inj15-ghost.md` §1.\n' >> "$d/$i15_agent"
    capture "$d" "$C15"
    assert_code 1 "ДЕФЕКТ: путь от корня формой ./ на правило, которого нет — краснеет"
    assert_says ".claude/rules/inj15-ghost.md" "  ...и называет путь (форма ./)"

    d="$(sandbox i15_path_dot_twin)"; b="$(sandbox_digest "$d")"
    printf '\nДовод — `./%s` §1.\n' "$i15_arch" >> "$d/$i15_agent"
    assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: ./ на существующий файл"
    capture "$d" "$C15"
    assert_code 0 "БЛИЗНЕЦ: путь от корня формой ./ на существующий файл — молчит"

    # Цель ссылки обязана быть в КОММИТЕ: файл, который есть на диске, но не
    # отслеживается git, в клоне конвейера отсутствует. Вердикт по нему не вправе
    # зависеть от рабочего дерева — находка и здесь. Близнец — тот же файл в индексе.
    d="$(sandbox i15_untracked)"
    printf '\nНорма — `.claude/rules/inj15-untracked.md` §1.\n' >> "$d/$i15_agent"
    printf '# не в индексе\n' > "$d/.claude/rules/inj15-untracked.md"
    capture "$d" "$C15"
    assert_code 1 "ДЕФЕКТ: цель пути есть на диске, но не отслеживается git — краснеет"
    assert_says "не отслеживается" "  ...и называет причину: файла нет в коммите"

    d="$(sandbox i15_untracked_twin)"; b="$(sandbox_digest "$d")"
    printf '\nНорма — `.claude/rules/inj15-untracked.md` §1.\n' >> "$d/$i15_agent"
    printf '# в индексе\n' > "$d/.claude/rules/inj15-untracked.md"
    git -C "$d" add .claude/rules/inj15-untracked.md >/dev/null 2>&1 || true
    assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: та же цель в индексе"
    capture "$d" "$C15"
    assert_code 0 "БЛИЗНЕЦ: та же цель, отслеживаемая git, — молчит"

    # ── поддерево, которого нет целиком ──────────────────────────────────────
    # Песочница набора не несёт `.claude/hooks`, а провязка `settings.json` его
    # объявляет: упоминание каталога — неполнота копии, молчит. Необъявленное
    # отсутствующее поддерево — мёртвый адрес, находка.
    d="$(sandbox i15_subtree_twin)"; b="$(sandbox_digest "$d")"
    printf '\nИсполняемый файл верхнего уровня `.claude/hooks/` провязан.\n' >> "$d/$i15_agent"
    assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: каталог хуков, объявленный провязкой, в копии нет"
    capture "$d" "$C15"
    assert_code 0 "БЛИЗНЕЦ: поддерево, объявленное settings.json, в копии отсутствует — молчит"

    d="$(sandbox i15_subtree)"
    printf '\nСвод лежит в `.claude/inj15-rulebook/`.\n' >> "$d/$i15_agent"
    capture "$d" "$C15"
    assert_code 1 "ДЕФЕКТ: поддерево, которого провязка не объявляет и в дереве нет, — краснеет"

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

    # Та же переменная корня другими законными формами shell: закрывающая кавычка
    # до косой черты и значение по умолчанию. Обе — тот же корень.
    i15_vf_hook() { # <песочница> <форма 1|2> <имя цели> — хук, зовущий цель от корня
        case "$2" in
            1) printf '#!/usr/bin/env bash\nexec bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/%s\n' "$3" ;;
            2) printf '#!/usr/bin/env bash\nexec bash "${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/%s"\n' "$3" ;;
        esac > "$1/.claude/hooks/zz-inj15.sh"
        git -C "$1" add -A >/dev/null 2>&1 || true
    }
    for _vf in 1 2; do
        d="$(sandbox "i15_hook_vf$_vf")"; i15_hooks "$d"
        i15_vf_hook "$d" "$_vf" zz-inj15-nope.sh
        capture "$d" "$C15"
        assert_code 1 "ДЕФЕКТ: хук зовёт файл от корня-переменной (форма $_vf), файла нет — краснеет"
        assert_says ".claude/hooks/zz-inj15-nope.sh" "  ...и называет путь (форма $_vf)"
        d="$(sandbox "i15_hook_vf${_vf}_twin")"; i15_hooks "$d"; b="$(sandbox_digest "$d")"
        i15_vf_hook "$d" "$_vf" zz-inj15.sh
        assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: форма $_vf на существующий файл"
        capture "$d" "$C15"
        assert_code 0 "БЛИЗНЕЦ: корень-переменная формой $_vf и существующий файл — молчит"
    done
    unset -v _vf

    # Исключается ФАЙЛ пробы (`.claude/hooks/<хук>/prove.sh` — тот же признак, по
    # которому пробы находит `scripts/hook-proofs.sh`), а не каталог, где он лежит:
    # рядом с пробой живёт код хука, который печатает диспетчеру (класс ws#710).
    # Прежде исключался каталог целиком, и `print` мёртвого адреса в разборе хука
    # проходил с кодом 0. Жертва выводится из дерева: файл кода в каталоге с пробой.
    i15_live=""
    for _p in "$WS"/.claude/hooks/*/prove.sh; do
        [ -f "$_p" ] || continue
        for _f in "$(dirname "$_p")"/*.py; do
            [ -f "$_f" ] && { i15_live="${_f#"$WS"/}"; break 2; }
        done
    done
    unset -v _p _f
    if [ -z "$i15_live" ]; then
        echo "  [FAIL] жертва не выведена: нет кода хука (*.py) рядом с prove.sh" >&2
        fail=$((fail + 1))
    else
        d="$(sandbox i15_live_path)"; i15_hooks "$d"
        printf '\nprint("Норма: .claude/rules/inj15-ghost.md")\n' >> "$d/$i15_live"
        git -C "$d" add -A >/dev/null 2>&1 || true
        capture "$d" "$C15"
        assert_code 1 "ДЕФЕКТ: код хука рядом с пробой печатает мёртвый путь — краснеет"
        assert_says "$i15_live:" "  ...и называет файл кода хука"

        d="$(sandbox i15_live_skill)"; i15_hooks "$d"
        printf '\nprint("бери `Skill %s`")\n' "$i15_ghost" >> "$d/$i15_live"
        git -C "$d" add -A >/dev/null 2>&1 || true
        capture "$d" "$C15"
        assert_code 1 "ДЕФЕКТ: код хука рядом с пробой печатает вызов скила без каталога — краснеет"

        d="$(sandbox i15_proof_twin)"; i15_hooks "$d"; b="$(sandbox_digest "$d")"
        printf '\n# вход пробы: .claude/rules/inj15-ghost.md\n' >> "$d/$(dirname "$i15_live")/prove.sh"
        git -C "$d" add -A >/dev/null 2>&1 || true
        assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: мёртвый путь в самой пробе"
        capture "$d" "$C15"
        assert_code 0 "БЛИЗНЕЦ: мёртвый путь во входе пробы (сам prove.sh) — молчит"
        assert_says "файлов проб исключено" "  ...а перепись называет исключённые файлы числом"
    fi

    d="$(sandbox i15_proof)"; i15_hooks "$d"
    mkdir -p "$d/.claude/hooks/zz-inj15"
    printf '#!/usr/bin/env bash\n# проба\n' > "$d/.claude/hooks/zz-inj15/prove.sh"
    printf 'вход пробы: .claude/rules/inj15-ghost.md\n' > "$d/.claude/hooks/zz-inj15/fixture.md"
    git -C "$d" add -A >/dev/null 2>&1 || true
    capture "$d" "$C15"
    assert_code 1 "ДЕФЕКТ: та же строка в соседнем с пробой файле — краснеет"

    # Скил — каталог, а не один SKILL.md: `references/` читает агент, которому скил
    # загружен. Жертва — любой настоящий файл скила помимо SKILL.md; нет такого —
    # заводится в каталоге первого настоящего скила.
    d="$(sandbox i15_skill_ref)"
    i15_ref="$(cd "$d" && git ls-files .claude/skills | grep -v '/SKILL\.md$' | grep -v '^\.claude/skills/rule-' | head -1)"
    if [ -z "$i15_ref" ]; then
        _sk="$(cd "$d" && git ls-files '.claude/skills/*/SKILL.md' | grep -v '^\.claude/skills/rule-' | head -1)"
        i15_ref="$(dirname "$_sk")/references/zz-inj15.md"
        mkdir -p "$d/$(dirname "$i15_ref")"; : > "$d/$i15_ref"
        unset -v _sk
    fi
    printf '\n// Норма — .claude/rules/inj15-ghost.md\n' >> "$d/$i15_ref"
    git -C "$d" add -A >/dev/null 2>&1 || true
    capture "$d" "$C15"
    assert_code 1 "ДЕФЕКТ: файл скила помимо SKILL.md называет мёртвый путь — краснеет"
    assert_says "$i15_ref:" "  ...и называет файл скила"

    d="$(sandbox i15_skill_ref_twin)"; b="$(sandbox_digest "$d")"
    [ -f "$d/$i15_ref" ] || { mkdir -p "$d/$(dirname "$i15_ref")"; : > "$d/$i15_ref"; }
    printf '\n// Довод — %s\n' "$i15_arch" >> "$d/$i15_ref"
    git -C "$d" add -A >/dev/null 2>&1 || true
    assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: файл скила называет существующий путь"
    capture "$d" "$C15"
    assert_code 0 "БЛИЗНЕЦ: файл скила называет существующий путь — молчит"
    unset -v i15_ref

    # ── пустой обход ─────────────────────────────────────────────────────────
    d="$(sandbox i15_void)"
    rm -rf "$d/.claude/agents"
    git -C "$d" add -A >/dev/null 2>&1 || true
    capture "$d" "$C15"
    assert_code 2 "ОТКАЗ: агентов нет — VOID, а не «всё резолвится»"

    # Вторая ветвь отказа: источники есть, а судить в них нечего — ни вызова, ни
    # строки skills:, ни пути. Без этой пробы ветвь могла бы отдавать 0 (мутант
    # приёмки M10 выживал) — пустой обход читался бы как «всё резолвится».
    d="$(sandbox i15_void_empty)"
    rm -rf "$d/.claude/rules" "$d/.claude/skills" "$d/.claude/backup" "$d/CLAUDE.md"
    for _a in "$d"/.claude/agents/*.md; do
        printf -- '---\nname: %s\ndescription: заглушка\n---\n\nтело без ссылок\n' \
            "$(basename "$_a" .md)" > "$_a"
    done
    unset -v _a
    git -C "$d" add -A >/dev/null 2>&1 || true
    capture "$d" "$C15"
    assert_code 2 "ОТКАЗ: источники есть, судить в них нечего — VOID, а не «всё резолвится»"
    assert_says "ни одного вызова" "  ...и называет причину"
fi
# Перепись части — отдельной строкой: «разошлось 0» без числа исполненных здесь
# утверждений неотличимо от части, которая не исполнила ни одного.
echo "[CENSUS] inject-15: утверждений исполнено $((pass + fail - i15_before))"
if [ "$((pass + fail - i15_before))" -eq 0 ]; then
    echo "[VOID] inject-15 — ни одного утверждения: часть ничего не доказала" >&2
    fail=$((fail + 1))
fi
