#!/usr/bin/env bash
# ЧАСТЬ инъекции набора: доказательство check-11 «корпус не предписывает вливание
# схлопыванием или перебазированием» — команда со способом, которого нет, в базе
# диспетчера, в форме задания шаблона волны и в правиле; законные близнецы той же
# формы: способ слиянием, слово без команды (красная колонка), стратегия
# `git merge -s`, отменённая норма в архиве; отказ по отсутствию предмета.
#
# Файл ПОДКЛЮЧАЕТСЯ (`.`) из `inject.sh` и пользуется его оснасткой.

# ── СТРАЖ ПОДКЛЮЧЕНИЯ ────────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — ЧАСТЬ инъекции, а не самостоятельная проба." >&2
    echo "       Она подключается из scripts/rules-gate/inject.sh и пользуется его оснасткой;" >&2
    echo "       самостоятельно писала бы в рабочее дерево. Запускать:" >&2
    echo "       bash scripts/rules-gate/inject.sh" >&2
    exit 2
fi
for _i11_fn in sandbox capture assert_code assert_says assert_fixture_changed sandbox_digest; do
    command -v "$_i11_fn" >/dev/null 2>&1 && continue
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — оснастки inject.sh нет: функция" \
         "«$_i11_fn» не определена; часть подключена не оттуда" >&2
    exit 2
done
unset -v _i11_fn

C11=check-11-merge-method-is-merge-commit.sh
D11=".claude/agents/dispatcher.md"
W11=".claude/workflows/wave.js"
R11=".claude/rules/git-issues.md"

# Обратные кавычки во вносимых строках — разметка markdown, а не подстановка;
# отвод SC2016 стоит адресно у каждой такой фикстуры.

# ── ДЕФЕКТ: база диспетчера предписывает `--squash` (форма ws#994) ───────────
d="$(sandbox i11_disp)"
# shellcheck disable=SC2016  # обратные кавычки — разметка вносимого markdown
printf '\n- Вливание в `main` — только `gh pr merge <N> --squash --delete-branch`.\n' >> "$d/$D11"
capture "$d" "$C11"
assert_code 1 "ДЕФЕКТ: база диспетчера предписывает gh pr merge --squash — краснеет"
assert_says "ВЛИВАНИЕ НЕ СЛИЯНИЕМ" "  ...и вердикт назван своим именем"
assert_says "$D11:" "  ...и названа строка, где норма живёт"
assert_says "--squash" "  ...и назван ключ"

# ── ДЕФЕКТ: форма задания шаблона волны предписывает rebase ──────────────────
d="$(sandbox i11_wave)"
printf '\n// посадка полосы: gh pr merge --rebase --delete-branch\n' >> "$d/$W11"
capture "$d" "$C11"
assert_code 1 "ДЕФЕКТ: шаблон волны предписывает gh pr merge --rebase — краснеет"
assert_says "$W11:" "  ...и названа строка шаблона"

# ── ДЕФЕКТ: правило предписывает `git merge --squash` ────────────────────────
d="$(sandbox i11_gitsq)"
# shellcheck disable=SC2016  # обратные кавычки — разметка вносимого markdown
printf '\nПеренос в ствол — `git merge --squash <ветка>`.\n' >> "$d/$R11"
capture "$d" "$C11"
assert_code 1 "ДЕФЕКТ: правило предписывает git merge --squash — краснеет"
assert_says "git merge --squash" "  ...и названа форма команды"

# ── БЛИЗНЕЦ: та же строка базы, способ — слиянием ────────────────────────────
d="$(sandbox i11_twin_merge)"; b="$(sandbox_digest "$d")"
# shellcheck disable=SC2016  # обратные кавычки — разметка вносимого markdown
printf '\n- Вливание в `main` — только `gh pr merge <N> --merge --match-head-commit`.\n' >> "$d/$D11"
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: команда вливания со способом слиянием"
capture "$d" "$C11"
assert_code 0 "БЛИЗНЕЦ: gh pr merge --merge — молчит"

# ── БЛИЗНЕЦ: слово без команды — красная колонка запрета ────────────────────
d="$(sandbox i11_twin_word)"; b="$(sandbox_digest "$d")"
# shellcheck disable=SC2016  # обратные кавычки — разметка вносимого markdown
printf '\ninj11-merge-word · вливание коммитом слияния (`gh pr merge --merge`) · сервер · red: способ из памяти; `--squash`\n' >> "$d/$R11"
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: --squash назван в красной колонке, вне команды"
capture "$d" "$C11"
assert_code 0 "БЛИЗНЕЦ: ключ вне код-спана команды — молчит"

# ── БЛИЗНЕЦ: `git merge -s` — стратегия, а не схлопывание ────────────────────
d="$(sandbox i11_twin_strategy)"; b="$(sandbox_digest "$d")"
# shellcheck disable=SC2016  # обратные кавычки — разметка вносимого markdown
printf '\nДогнать ствол — `git merge -s ours origin/main`.\n' >> "$d/$R11"
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: git merge со стратегией -s"
capture "$d" "$C11"
assert_code 0 "БЛИЗНЕЦ: git merge -s ours — молчит"

# ── БЛИЗНЕЦ: та же отменённая норма в АРХИВЕ ─────────────────────────────────
d="$(sandbox i11_twin_backup)"; b="$(sandbox_digest "$d")"
mkdir -p "$d/.claude/backup"
# shellcheck disable=SC2016  # обратные кавычки — разметка вносимого markdown
printf '\n### Снято (решение 2026-08-20, отменено 2026-09-22): `gh pr merge <N> --squash`\n' >> "$d/.claude/backup/git-issues.md"
git -C "$d" add -A >/dev/null 2>&1
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: отменённая норма дописана в архив"
capture "$d" "$C11"
assert_code 0 "БЛИЗНЕЦ: архив снятых редакций вне области — молчит"

# ── ось VOID: области корпуса нет — ОТКАЗ, а не «находок 0» ──────────────────
d="$TMP/s.i11_void"; rm -rf "$d"; mkdir -p "$d"; git -C "$d" init -q >/dev/null 2>&1
capture "$d" "$C11"
assert_code 2 "ДЕФЕКТ: области корпуса нет — ОТКАЗ по предмету, не зелёный вердикт"
assert_says "[VOID]" "  ...и отказ объявлен строкой [VOID]"

# Перепись части: сколько утверждений набора исполнено к её концу (накопительно —
# счётчики общие с inject.sh). Ноль здесь значил бы, что часть не исполнила ничего.
# shellcheck disable=SC2154  # счётчики pass/fail заводит inject.sh, часть подключается из него
echo "[CENSUS] часть inject-11-merge-method-is-merge-commit.sh: утверждений набора к концу части $((pass + fail)), разошлось $fail"
