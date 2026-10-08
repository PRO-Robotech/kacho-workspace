#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# Доказательство того, что git-guard ОТКАЗЫВАЕТ каждой запрещённой форме и
# ПРОПУСКАЕТ законного близнеца той же формы (ws#974).
#
# Каждая строка таблицы — настоящий вход PreToolUse (JSON с tool_input.command и
# cwd), поданный хуку `.claude/hooks/git-guard.sh` так же, как его зовёт харнесс.
# Читаются код И текст: отказ обязан назвать свой вид в скобках («отказ [force]»)
# и строку «Что делать вместо» — текст отказа часть свойства (`testing.md`,
# finding-text-is-part-of-property); пропуск — код 0 и ни слова: хук срабатывает
# внутри всех сабагентов, и лишний вывод на законной команде шумел бы везде.
#
# Ветку для голого `git push` страж читает из каталога команды, поэтому вход
# строится настоящими репозиториями: `onmain` (текущая ветка main) и `onlane`
# (974-x). Граница стража (BOUNDARY в guard.py) исполняется строкой [BOUND] —
# «известно, не ловится», не зелёное; пойманный пример границы — [FAIL]: перечень
# в шапке стража устарел. Поломка стража (вход не JSON, нет разборщика) обязана
# быть пропуском со словом «СЛОМАН», а не отказом всему.
#
# Сокращение опции — класс (git принимает однозначный префикс длинной опции, и
# однозначность своя у каждой подкоманды): таблица префиксов ниже на каждую
# запрещённую опцию несёт строку с минимальным однозначным префиксом (отказ) и
# строку на знак короче (близнец: git называет его ambiguous — пропуск). Перед
# судом стража каждая строка проверяет ПРЕДПОСЫЛКУ настоящим git: префикс отказа
# git принимает, префикс близнеца git отвергает (`ambiguous`/`unknown option`) —
# иначе таблица описывает не тот git, что стоит на машине. Инъекция «порог на
# знак длиннее» (копия стража с `return n + 1`) обязана замолчать хотя бы на одной
# строке отказа.
#
# Коды: 0 — все утверждения сошлись; 1 — хотя бы одно нет; 2 — вход не построен.
# Команды ниже — ВХОДЫ стража, а не исполняемый код: раскрывать их нельзя.
# shellcheck disable=SC2016
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$HOOK_DIR/git-guard.sh"
GUARD="$HOOK_DIR/git-guard/guard.py"
PARSER="$HOOK_DIR/heavy-guard/guard.py"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0; denied=0; passed=0; bound=0

if [ ! -f "$HOOK" ] || [ ! -f "$GUARD" ] || [ ! -f "$PARSER" ]; then
    echo "[VOID] git-guard: нет хука, стража или разборщика heavy-guard — доказывать нечего" >&2
    exit 2
fi
if ! git init -q -b main "$WORK/onmain" 2>/dev/null || ! git init -q -b 974-x "$WORK/onlane" 2>/dev/null; then
    echo "[VOID] git-guard: синтетические репозитории не построены (git init -b)" >&2
    exit 2
fi
mkdir -p "$WORK/onlane/sub"
# конфиги для ветви «заранее записанный файл с core.hooksPath»: прямой, через
# include и законный близнец без него
printf '[core]\n\thooksPath = /dev/null\n' > "$WORK/hp.cfg"
printf '[include]\n\tpath = hp.cfg\n' > "$WORK/inc.cfg"
printf '[user]\n\tname = probe\n' > "$WORK/clean.cfg"
# репозиторий предпосылки: в нём НАСТОЯЩИЙ git судит префиксы таблицы; удалённого
# нет, mbox и ссылок нет — команда падает после разбора опций, ничего не меняя
P="$WORK/premise"
git init -q -b 974-x "$P" 2>/dev/null || { echo "[VOID] git-guard: репозиторий предпосылки не построен" >&2; exit 2; }

assert() {
    if [ "$1" = "$2" ]; then
        echo "  [OK]   $3"; pass=$((pass + 1))
    else
        echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2
        sed 's/^/         | /' "$WORK/out" >&2
        fail=$((fail + 1))
    fi
}

# run <команда> [cwd] [инструмент] — код хука ($USE_HOOK, по умолчанию настоящий); вывод в $WORK/out
USE_HOOK="$HOOK"
run() {
    python3 -I -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[3],"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' \
        "$1" "${2:-$WORK}" "${3:-Bash}" | bash "$USE_HOOK" > "$WORK/out" 2>&1
    echo $?
}

one_line() { printf '%s' "$1" | tr '\n' ' '; }

# denies <вид> <команда> [cwd] — код 2, вид назван, строка «что делать вместо» есть
denies() {
    local rc kind instead
    rc="$(run "$2" "${3:-}")"
    kind="$(sed -n 's/^GIT-GUARD: отказ \[\([^]]*\)\].*/\1/p' "$WORK/out" | head -n 1)"
    instead="нет"; grep -q '^Что делать вместо: ' "$WORK/out" && instead="да"
    assert "2 $1 да" "$rc ${kind:-—} $instead" "отказ [$1]: $(one_line "$2")"
    denied=$((denied + 1))
}

# passes <команда> [cwd] — код 0 и ни слова
passes() {
    local rc
    rc="$(run "$1" "${2:-}")"
    assert "0 0" "$rc $(wc -c < "$WORK/out" | tr -d ' ')" "пропуск: $(one_line "$1")"
    passed=$((passed + 1))
}

M="$WORK/onmain"; L="$WORK/onlane"

echo "── запрещённые формы → отказ с видом и строкой «что делать вместо»"
denies no-verify    'git commit --no-verify -m x' "$L"
denies no-verify    'git commit -anm x' "$L"
denies no-verify    'git commit --no-veri -m x' "$L"
denies no-verify    'cd sub && timeout 60 git -C . commit -n -m x' "$L"
denies no-verify    'git push --no-verify -u origin 974-x' "$L"
denies no-verify    'git merge --no-verify origin/main' "$L"
denies no-verify    'git pull --no-verify origin 974-x' "$L"
denies no-verify    'git am --no-verify p.mbox' "$L"
denies no-verify    'git am -n p.mbox' "$L"
denies no-verify    'git am -3n p.mbox' "$L"
denies no-verify    'git rebase --no-verify main' "$L"
denies skip-prepush 'KACHO_SKIP_PREPUSH=1 git push -u origin 974-x' "$L"
denies skip-prepush 'export KACHO_SKIP_PREPUSH=1; git push' "$L"
denies force        'git push --force origin 974-x' "$L"
denies force        'git push -f origin 974-x' "$L"
denies force        'git push -uf origin 974-x' "$L"
denies force        'git push --force-with-lease origin 974-x' "$L"
denies force        'git push --force-with-lease=974-x:abc123 origin 974-x' "$L"
denies force        'git push origin +974-x' "$L"
denies force        'git push origin 974-x --force' "$L"
denies push-all     'git push --mirror origin' "$L"
denies push-all     'git push --all origin' "$L"
denies push-all     'git push --branches origin' "$L"
denies trunk        'git push origin main' "$L"
denies trunk        'git push origin HEAD:refs/heads/master' "$L"
denies trunk        'git push origin --delete main' "$L"
denies trunk        'git push origin :main' "$L"
denies trunk        'git push' "$M"
denies trunk        'git push -u origin HEAD' "$M"
denies trunk        "cd $M && git push origin @" "$L"
denies trunk        "git -C $M push" "$L"
denies trunk        "git --git-dir=$M/.git push" "$L"
denies trunk        "git --git-dir $M/.git push origin HEAD" "$L"
denies trunk        "GIT_DIR=$M/.git git push" "$L"
denies trunk        "export GIT_DIR=$M/.git; git push" "$L"
denies admin        'gh pr merge 12 --admin --merge' "$L"
denies admin        'gh pr merge 12 --merge --admin=true' "$L"
denies admin        'gh --repo PRO-Robotech/kacho pr merge 12 --admin' "$L"
denies admin        'gh -R PRO-Robotech/kacho pr merge 12 --merge --admin' "$L"
denies admin        'gh pr -R PRO-Robotech/kacho merge 12 --admin' "$L"
denies hookspath    'git -c core.hooksPath=/dev/null commit -m x' "$L"
denies hookspath    'git --config-env=core.hooksPath=HP push' "$L"
denies hookspath    'git config core.hooksPath /dev/null' "$L"
denies hookspath    'git config --global core.hooksPath /tmp/nohooks' "$L"
denies hookspath    'git config set core.hooksPath /dev/null' "$L"
denies hookspath    'git config --add core.hooksPath /dev/null' "$L"
denies hookspath    'git config --replace-all core.hooksPath /dev/null' "$L"
denies hookspath    "GIT_CONFIG_PARAMETERS=\"'core.hooksPath'='/dev/null'\" git commit -m x" "$L"
denies hookspath    'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null git commit -m x' "$L"
denies force        "bash -c 'git push --force origin 974-x'" "$L"
denies force        "bash -lc 'cd sub && git push -f origin 974-x'" "$L"
denies force        $'bash <<\'EOF\'\ngit push -f origin 974-x\nEOF' "$L"
denies force        'echo "$(git push --force origin 974-x)"' "$L"
denies force        "printf '974-x' | xargs -I{} git push --force origin {}" "$L"
denies force        'find . -maxdepth 0 -exec git push -f origin 974-x \;' "$L"
denies force        'eval "git push -f origin 974-x"' "$L"
denies no-verify    'F=--no-verify; git commit $F -m x' "$L"
denies hookspath    "GIT_CONFIG_GLOBAL=$WORK/hp.cfg git commit -m x" "$L"
denies hookspath    "GIT_CONFIG_GLOBAL=$WORK/inc.cfg git commit -m x" "$L"
denies hookspath    "export GIT_CONFIG_SYSTEM=$WORK/hp.cfg; git push" "$L"
denies hookspath    "cd $WORK && GIT_CONFIG_GLOBAL=hp.cfg git commit -m x" "$L"
denies hookspath    "git -c include.path=$WORK/hp.cfg commit -m x" "$L"
denies hookspath    "git -c includeIf.onbranch:974-x.path=$WORK/inc.cfg commit -m x" "$L"
denies hookspath    "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=include.path GIT_CONFIG_VALUE_0=$WORK/hp.cfg git commit -m x" "$L"
denies hookspath    "git config --global include.path $WORK/hp.cfg" "$L"
denies hookspath    "git config set include.path $WORK/inc.cfg" "$L"

echo "── законные близнецы → пропуск без единого слова"
passes 'git push -u origin 974-x' "$L"
passes 'git push' "$L"
passes 'git push origin HEAD' "$L"
passes 'git push --dry-run origin HEAD:refs/heads/974-x' "$L"
passes 'git push -n origin 974-x' "$L"
passes 'git push -d origin 973-old' "$L"
passes 'git push origin :973-old' "$L"
passes 'git push --no-force-with-lease origin 974-x' "$L"
passes 'git push origin main-docs' "$L"
passes 'git push origin v1.0' "$M"
passes 'git push --tags' "$M"
passes 'KACHO_SKIP_PREPUSH=0 git push -u origin 974-x' "$L"
passes 'git commit -m "не обходить --no-verify и push --force в main"' "$L"
passes 'git commit -m -n' "$L"
passes $'git commit -F - <<\'EOF\'\ngit push --force origin main запрещён (#974)\nEOF' "$L"
passes $'git commit -m "$(cat <<\'EOF\'\n#974 страж: --no-verify, KACHO_SKIP_PREPUSH=1, -c core.hooksPath\nEOF\n)"' "$L"
passes $'cat > note.md <<\'EOF\'\ngit push --force origin main\nEOF' "$L"
passes 'echo "git push --force origin main"' "$L"
passes "grep -rn -- '--no-verify' .claude/hooks" "$L"
passes "git grep -n 'core.hooksPath'" "$L"
passes 'ls # git push --force origin main' "$L"
passes 'git log --grep=--no-verify' "$L"
passes 'git merge -n origin/main' "$L"
passes 'git rebase -n main' "$L"
passes 'git pull -n origin 974-x' "$L"
passes 'git cherry-pick -n abc123' "$L"
passes 'git revert -n abc123' "$L"
passes 'git am -3 p.mbox' "$L"
passes 'git am -p1 p.mbox' "$L"
passes "git -C $L push" "$M"
passes "git --git-dir=$L/.git push" "$M"
passes "GIT_DIR=$L/.git git push" "$M"
passes 'eval "git push origin 974-x"' "$L"
passes 'git merge --no-ff origin/main' "$L"
passes 'git fetch origin main' "$M"
passes 'git pull origin main' "$L"
passes 'git -c color.ui=never commit -m y' "$L"
passes 'git config core.hooksPath' "$L"
passes 'git config --get core.hooksPath' "$L"
passes 'git config --unset core.hooksPath' "$L"
passes 'git config --unset core.hooksPath /dev/null' "$L"
passes 'git config --add core.editor vim' "$L"
passes "GIT_CONFIG_PARAMETERS=\"'color.ui'='never'\" git commit -m x" "$L"
passes 'gh pr merge 12 --merge --match-head-commit abc123' "$L"
passes 'gh pr merge 12 --squash --delete-branch' "$L"
passes 'gh pr merge 12 --merge --delete-branch' "$L"
passes 'gh -R PRO-Robotech/kacho pr merge 12 --merge' "$L"
passes 'gh --repo PRO-Robotech/kacho pr view 12' "$L"
passes 'gh pr merge 12 --merge --admin=false' "$L"
passes 'gh pr view 12 --json title' "$L"
passes 'GIT_CONFIG_GLOBAL=/dev/null git commit -m x' "$L"
passes "GIT_CONFIG_GLOBAL=$WORK/clean.cfg git commit -m x" "$L"
passes "git -c include.path=$WORK/clean.cfg commit -m x" "$L"
passes "git config include.path $WORK/clean.cfg" "$L"
passes "git config --get include.path" "$L"

echo "── cherry-pick и revert: --no-verify у них нет (предпосылка — перечень опций git)"
for sub in cherry-pick revert; do
    if git -C "$P" "$sub" --git-completion-helper-all 2>/dev/null | tr ' ' '\n' | grep -qx -- '--no-verify'; then
        echo "  [FAIL] предпосылка: у git $sub есть --no-verify ($(git --version)) — вернуть $sub в NO_VERIFY_SUBS" >&2
        fail=$((fail + 1))
    else
        echo "  [OK]   предпосылка: у git $sub нет --no-verify"; pass=$((pass + 1))
    fi
    passes "git $sub --no-verify abc123" "$L"
done

# git_says <sub> <слова…> — вердикт НАСТОЯЩЕГО git о разборе опций: refused | accepted
git_says() {
    local sub="$1"; shift
    local err
    err="$(LC_ALL=C GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
           timeout 10 git -C "$P" "$sub" "$@" 2>&1 < /dev/null | head -n 3)"
    case "$err" in
        *"ambiguous option"*|*"unknown option"*|*"unknown switch"*) echo refused ;;
        *) echo accepted ;;
    esac
}

# Таблица префиксов: вид|подкоманда|префикс|хвост|ожидание. Префикс — минимальный
# однозначный (deny) либо на знак короче (pass, близнец). У --mirror и --branches
# минимальный префикс — одна буква (`--m`, `--b`): короче только `--`, конец опций,
# поэтому близнеца нет. Строки `--no-ver` у am, `--bran`/`--br`/`--mir` — длиннее
# минимального, обязательные строки отказа задачи.
PREFIX_ROWS="
no-verify|commit|--no-veri|-m x|deny
no-verify|commit|--no-ver|-m x|pass
no-verify|push|--no-veri|origin 974-x|deny
no-verify|push|--no-ver|origin 974-x|pass
no-verify|merge|--no-verify|origin/main|deny
no-verify|merge|--no-verif|origin/main|pass
no-verify|pull|--no-verify|origin 974-x|deny
no-verify|pull|--no-verif|origin 974-x|pass
no-verify|am|--no-v|p.mbox|deny
no-verify|am|--no-|p.mbox|pass
no-verify|am|--no-ver|p.mbox|deny
no-verify|rebase|--no-veri|main|deny
no-verify|rebase|--no-ver|main|pass
force|push|--force|origin 974-x|deny
force|push|--forc|origin 974-x|pass
force|push|--force-w|origin 974-x|deny
force|push|--force-|origin 974-x|pass
push-all|push|--m|origin|deny
push-all|push|--mir|origin|deny
push-all|push|--al|origin|deny
push-all|push|--a|origin|pass
push-all|push|--b|origin|deny
push-all|push|--br|origin|deny
push-all|push|--bran|origin|deny
"
echo "── сокращения: минимальный однозначный префикс → отказ, на знак короче → пропуск"
prefix_deny=()
while IFS='|' read -r kind sub pre tail want; do
    [ -n "$kind" ] || continue
    read -ra tw <<< "$tail"
    said="$(git_says "$sub" "$pre" "${tw[@]}")"
    expect_git=accepted; [ "$want" = pass ] && expect_git=refused
    if [ "$said" != "$expect_git" ]; then
        echo "  [FAIL] предпосылка: git $sub $pre — git $said, а таблица ждёт $expect_git ($(git --version))" >&2
        fail=$((fail + 1))
    else
        pass=$((pass + 1))
    fi
    if [ "$want" = deny ]; then
        denies "$kind" "git $sub $pre $tail" "$L"
        prefix_deny+=("git $sub $pre $tail")
    else
        passes "git $sub $pre $tail" "$L"
    fi
done <<< "$PREFIX_ROWS"

echo "── gh (pflag): сокращений нет — --admi не --admin"
if command -v gh > /dev/null 2>&1; then
    # вывод сначала в переменную: gh выходит кодом 1, и под pipefail труба в grep
    # дала бы «не нашлось» при найденной строке
    gh_said="$(GH_PROMPT_DISABLED=1 timeout 10 gh pr merge 12 --admi 2>&1 < /dev/null)"
    if [[ "$gh_said" == *"unknown flag: --admi"* ]]; then
        echo "  [OK]   предпосылка: gh отвергает --admi как unknown flag"; pass=$((pass + 1))
    else
        echo "  [FAIL] предпосылка: gh принял --admi — у gh появились сокращения, страж слеп" >&2
        fail=$((fail + 1))
    fi
else
    echo "  [SKIP] предпосылка gh не проверена: gh нет в PATH (строка ниже судит только стража)"
fi
passes 'gh pr merge 12 --admi --merge' "$L"

echo "── инъекция: порог на знак длиннее обязан замолчать хотя бы на одной строке отказа"
INJ="$WORK/inj"
mkdir -p "$INJ/git-guard" "$INJ/heavy-guard"
cp "$HOOK" "$INJ/git-guard.sh"; cp "$PARSER" "$INJ/heavy-guard/guard.py"
sed 's/^\( *\)return n  # порог:/\1return n + 1  # порог:/' "$GUARD" > "$INJ/git-guard/guard.py"
if [ "$(grep -c 'return n + 1  # порог:' "$INJ/git-guard/guard.py")" != 1 ]; then
    echo "  [FAIL] инъекция не встала: строки «return n  # порог:» в guard.py нет — проба слепа" >&2
    fail=$((fail + 1))
else
    USE_HOOK="$INJ/git-guard.sh"; silent=0
    for c in "${prefix_deny[@]}"; do
        rc="$(run "$c" "$L")"
        if [ "$rc" = 0 ]; then
            echo "  [MUTE] порог+1 пропускает: $c"; silent=$((silent + 1))
        fi
    done
    USE_HOOK="$HOOK"
    assert "да" "$([ "$silent" -ge 1 ] && echo да || echo нет)" \
        "инъекция порог+1: замолчало $silent из ${#prefix_deny[@]} строк отказа (нужно ≥ 1)"
fi

echo "── граница стража (BOUNDARY в guard.py): известно, не ловится"
while IFS= read -r -d '' cls && IFS= read -r -d '' example; do
    rc="$(run "$example" "$L")"
    if [ "$rc $(wc -c < "$WORK/out" | tr -d ' ')" = "0 0" ]; then
        echo "  [BOUND] не ловится (граница: $cls): $(one_line "$example")"; bound=$((bound + 1))
    else
        echo "  [FAIL] граница «$cls» — страж поймал пример (код $rc): перечень BOUNDARY устарел: $(one_line "$example")" >&2
        fail=$((fail + 1))
    fi
done < <(python3 -I "$GUARD" --boundary)

echo "── поломка стража — громкий пропуск, а не отказ всему"
printf 'не json' | bash "$HOOK" > "$WORK/out" 2>&1; rc=$?
assert "0 да" "$rc $(grep -q 'GIT-GUARD СЛОМАН' "$WORK/out" && echo да || echo нет)" "вход не JSON → код 0 и «СЛОМАН»"
mkdir -p "$WORK/lone/git-guard"
cp "$HOOK" "$WORK/lone/git-guard.sh"; cp "$GUARD" "$WORK/lone/git-guard/guard.py"
python3 -I -c 'import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"git push --force"},"cwd":"/"}))' \
    | bash "$WORK/lone/git-guard.sh" > "$WORK/out" 2>&1; rc=$?
assert "0 да" "$rc $(grep -q 'GIT-GUARD СЛОМАН' "$WORK/out" && echo да || echo нет)" "нет разборщика heavy-guard → код 0 и «СЛОМАН»"
rc="$(run 'git push --force' "$L" Read)"
assert "0 0" "$rc $(wc -c < "$WORK/out" | tr -d ' ')" "чужой инструмент (Read) → молчание"
python3 -I -c 'import json; print(json.dumps({"tool_name":"Monitor","tool_input":{"source":"ws"}}))' \
    | bash "$HOOK" > "$WORK/out" 2>&1; rc=$?
assert "0 0" "$rc $(wc -c < "$WORK/out" | tr -d ' ')" "Monitor без команды → молчание"
rc="$(run 'git push --force origin 974-x' "$L" Monitor)"
assert "2" "$rc" "Monitor с командой судится так же, как Bash"

rows=$((denied + passed))
echo "[CENSUS] git-guard: строк таблицы $rows (отказов $denied, пропусков $passed), границ $bound, утверждений $((pass + fail)), сошлось $pass, разошлось $fail"
if [ "$rows" -lt 25 ] || [ "$denied" -eq 0 ] || [ "$passed" -eq 0 ] || [ "$bound" -eq 0 ]; then
    echo "[FAIL] git-guard — таблица сжалась: строк $rows (< 25) либо пуста одна из сторон" >&2
    exit 1
fi
[ "$fail" -eq 0 ] || { echo "[FAIL] git-guard — разошлось $fail" >&2; exit 1; }
echo "[PASS] git-guard — все $pass утверждений сошлись"
