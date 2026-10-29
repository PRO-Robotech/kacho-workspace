#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
# Строки команд — ВХОДЫ стража, а не код этой оболочки: `$(…)` и `$F` в них не
# раскрываются намеренно.
# shellcheck disable=SC2016
#
# prove.sh — доказательство git-guard ИНЪЕКЦИЕЙ (ws#974): страж ОТКАЗЫВАЕТ каждой
# форме обхода хуков git и ПРОПУСКАЕТ законного близнеца той же формы.
#
#   · каждая строка — настоящий вход PreToolUse (JSON с tool_input.command и cwd),
#     поданный хуку `.claude/hooks/git-guard.sh` так, как его зовёт харнесс; читаются
#     код И текст: отказ называет вид («отказ [no-verify]»), правило и строку «Что
#     делать вместо» (текст отказа — часть свойства); пропуск — код 0 и ни слова;
#   · перечни стража ВЫВОДЯТСЯ, а не переписываются: опции обхода хука и подкоманды,
#     где `-n` = `--no-verify`, — из `git <sub> -h` по всем `git --list-cmds=main`
#     (сверка с `guard.py --table` в обе стороны); имена `*_SKIP_PREPUSH` — из хуков
#     отправки деревьев (воркспейс и клоны project/*, какие есть); сокращение опции —
#     перебором каждого префикса каждой опции обхода, вердикт по которому даёт
#     НАСТОЯЩИЙ git (принял — страж обязан отказать; ambiguous/unknown — пропустить);
#   · провязка: `.claude/settings.json` зовёт канонический хук в PreToolUse под Bash
#     и Monitor;
#   · мутанты guard.py (по одной правке, таблица MUTANTS) обязаны покраснеть хотя бы
#     на одной строке — и назвать её;
#   · граница (BOUNDARY в guard.py) — [BOUND]: известно, не ловится; пойманный
#     пример — [FAIL]: перечень устарел;
#   · поломка стража — пропуск со словом «СЛОМАН», а не отказ всему.
# Коды: 0 — все утверждения сошлись; 1 — хотя бы одно нет; 2 — вход не построен.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WS="$(cd "$HOOK_DIR/../.." && pwd)"
HOOK="$HOOK_DIR/git-guard.sh"
GUARD="$HOOK_DIR/git-guard/guard.py"
PARSER="$HOOK_DIR/heavy-guard/guard.py"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0; denied=0; passed=0; bound=0; muts=0

for need in python3 git; do
    command -v "$need" > /dev/null 2>&1 || { echo "[VOID] git-guard: нет $need — доказывать нечем" >&2; exit 2; }
done
if [ ! -f "$HOOK" ] || [ ! -f "$GUARD" ] || [ ! -f "$PARSER" ]; then
    echo "[VOID] git-guard: нет хука, стража или разборщика heavy-guard — доказывать нечего" >&2
    exit 2
fi
L="$WORK/lane"; P="$WORK/premise"
if ! git init -q -b 974-x "$L" 2>/dev/null || ! git init -q -b 974-x "$P" 2>/dev/null; then
    echo "[VOID] git-guard: синтетические репозитории не построены (git init -b)" >&2
    exit 2
fi
mkdir -p "$L/sub"
# конфиги ветви «заранее записанный файл с core.hooksPath»: прямой, через include и
# законный близнец без него
printf '[core]\n\thooksPath = /dev/null\n' > "$WORK/hp.cfg"
printf '[include]\n\tpath = hp.cfg\n' > "$WORK/inc.cfg"
printf '[user]\n\tname = probe\n' > "$WORK/clean.cfg"
ROWS="$WORK/rows"; : > "$ROWS"   # ожидание, каталог, команда — через NUL: вход мутантов

assert() {
    if [ "$1" = "$2" ]; then
        echo "  [OK]   $3"; pass=$((pass + 1))
    else
        echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2
        sed 's/^/         | /' "$WORK/out" >&2
        fail=$((fail + 1))
    fi
}

USE_HOOK="$HOOK"
# run <команда> [cwd] [инструмент] — код хука на настоящем входе; вывод в $WORK/out
run() {
    python3 -I -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[3],"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' \
        "$1" "${2:-$L}" "${3:-Bash}" | bash "$USE_HOOK" > "$WORK/out" 2>&1
    echo $?
}
one_line() { printf '%s' "$1" | tr '\n' ' '; }

# denies <вид> <команда> [cwd] — код 2, вид назван, правило и «что делать вместо» есть
denies() {
    local rc kind rule instead
    rc="$(run "$2" "${3:-}")"
    kind="$(sed -n 's/^GIT-GUARD: отказ \[\([^]]*\)\].*/\1/p' "$WORK/out" | head -n 1)"
    rule="нет"; grep -qF 'Правило: .claude/rules/git-issues.md#gi-no-hook-bypass' "$WORK/out" && rule="да"
    instead="нет"; grep -q '^Что делать вместо: ' "$WORK/out" && instead="да"
    assert "2 $1 да да" "$rc ${kind:-—} $rule $instead" "отказ [$1]: $(one_line "$2")"
    printf '%s\0%s\0%s\0' "$1" "${3:-$L}" "$2" >> "$ROWS"
    denied=$((denied + 1))
}

# passes <команда> [cwd] — код 0 и ни слова
passes() {
    local rc
    rc="$(run "$1" "${2:-}")"
    assert "0 0" "$rc $(wc -c < "$WORK/out" | tr -d ' ')" "пропуск: $(one_line "$1")"
    printf '%s\0%s\0%s\0' pass "${2:-$L}" "$1" >> "$ROWS"
    passed=$((passed + 1))
}

echo "── провязка: settings.json зовёт канонический хук в PreToolUse под Bash и Monitor"
wired="$(python3 -I - "$WS" <<'PY'
import json, os, re, shlex, sys
root = sys.argv[1]
canon = os.path.realpath(os.path.join(root, ".claude/hooks/git-guard.sh"))
try:
    hooks = json.load(open(os.path.join(root, ".claude/settings.json"))).get("hooks", {})
except Exception as e:
    print("settings.json не разобран: %s" % e); sys.exit()
got = set()
for g in hooks.get("PreToolUse", []):
    for h in g.get("hooks", []):
        try:
            argv = shlex.split(h.get("command", ""))
        except ValueError:
            continue
        argv = [a for a in argv if a not in ("bash", "sh")]
        if not argv:
            continue
        p = re.sub(r"\$\{CLAUDE_PROJECT_DIR\}|\$CLAUDE_PROJECT_DIR(?![A-Za-z0-9_])", lambda m: root, argv[0])
        if os.path.realpath(p) == canon:
            got |= {t for t in ("Bash", "Monitor") if re.fullmatch(g.get("matcher") or ".*", t)}
print(" ".join(sorted(got)) or "не провязан")
PY
)"
assert "Bash Monitor" "$wired" "PreToolUse зовёт .claude/hooks/git-guard.sh под Bash и Monitor"
assert "да" "$([ -x "$HOOK" ] && echo да || echo нет)" "хук .claude/hooks/git-guard.sh исполним"

echo "── перечни стража выведены из git: опции обхода хука и подкоманды с -n = --no-verify"
: > "$WORK/derived"; scanned=0; timed=0
for sub in $(git --list-cmds=main 2>/dev/null | sort -u); do
    # gui-команды открыли бы окно; filter-branch по -h ждёт (измерено: 3 с до timeout)
    case "$sub" in gui|citool|gitk|instaweb|web--browse|difftool|mergetool|filter-branch) continue ;; esac
    help="$(env -u DISPLAY -u WAYLAND_DISPLAY LC_ALL=C GIT_PAGER=cat timeout 3 git "$sub" -h < /dev/null 2>&1)"
    [ $? = 124 ] && { timed=$((timed + 1)); continue; }
    scanned=$((scanned + 1))
    printf '%s\n' "$help" | grep -i 'hook' | grep -E '^[[:space:]]+-' | while IFS= read -r line; do
        opt="$(printf '%s\n' "$line" | grep -oE -- '--(\[no-\])?[a-z][a-z-]*' | head -n 1)"
        case "$opt" in --\[no-\]*) opt="--no-${opt#--\[no-\]}" ;; esac
        [ -n "$opt" ] && printf 'long %s %s\n' "$sub" "$opt"
        printf '%s\n' "$line" | grep -qE -- '^[[:space:]]+-n, --(\[no-\])?no-verify' && printf 'short-n %s\n' "$sub"
    done >> "$WORK/derived"
done
python3 -I - "$WORK/derived" <<'PY' > "$WORK/derived.table"
import sys
long, short = {}, set()
for ln in open(sys.argv[1]):
    w = ln.split()
    if w[0] == "long":
        long.setdefault(w[1], set()).add(w[2])
    else:
        short.add(w[1])
for sub in sorted(long):
    print("long %s %s" % (sub, " ".join(sorted(long[sub]))))
print("short-n %s" % " ".join(sorted(short)))
PY
python3 -I "$GUARD" --table > "$WORK/guard.table"
echo "  перепись: подкоманд git осмотрено $scanned, по timeout пропущено $timed ($(git --version))"
assert "да" "$([ "$scanned" -ge 100 ] && echo да || echo нет)" "осмотрено подкоманд ≥ 100 (иначе вывод перечня слеп)"
if cmp -s "$WORK/derived.table" "$WORK/guard.table"; then
    echo "  [OK]   перечни стража совпадают с выведенными из git ($(grep -c '^long' "$WORK/guard.table") подкоманд)"; pass=$((pass + 1))
else
    echo "  [FAIL] перечни стража разошлись с git (слева — git, справа — guard.py --table):" >&2
    diff "$WORK/derived.table" "$WORK/guard.table" | sed 's/^/         | /' >&2
    fail=$((fail + 1))
fi

echo "── формы случаев класса (ws#1001, приёмка 273, ws#1498, check-verifier)"
denies no-verify    'git commit --no-verify -m "wip: опыт"' "$L"
denies no-verify    "cd $L && git add note.md && git commit --no-verify -m exp" "$WORK"
denies hookspath    'git -c core.hooksPath=/dev/null commit -m "#273 приёмка"' "$L"
denies hookspath    "git -c core.hooksPath=/dev/null worktree add -q --detach $WORK/tmpcopy HEAD" "$L"

echo "── опции обхода хука → отказ [no-verify]"
denies no-verify    'git commit -n -m x'
denies no-verify    'git commit -anm x'
denies no-verify    'git commit -a -n -m x'
denies no-verify    'git commit -m x -n'
denies no-verify    'git commit --no-post-rewrite --amend -m x'
denies no-verify    'git push --no-verify -u origin 974-x'
denies no-verify    'git push --dry-run --no-verify origin 974-x'
denies no-verify    'git push origin 974-x --no-verify'
denies no-verify    'git merge --no-verify origin/main'
denies no-verify    'git pull --no-verify origin 974-x'
denies no-verify    'git am --no-verify p.mbox'
denies no-verify    'git am -n p.mbox'
denies no-verify    'git am -3n p.mbox'
denies no-verify    'git rebase --no-verify main'
denies no-verify    "git -C $L commit -n -m x" "$WORK"
denies no-verify    'cd sub && timeout 60 git -C . commit -n -m x'
denies no-verify    'F=--no-verify; git commit $F -m x'
denies no-verify    'env GIT_EDITOR=true git commit --no-verify'
denies no-verify    'sudo -u nobody git commit -n -m x'
denies no-verify    'command git commit -n -m x'
denies no-verify    '/usr/bin/git commit --no-verify -m x'
denies no-verify    "printf 'x' | xargs -I{} git commit -n -m {}"
denies no-verify    'find . -maxdepth 0 -exec git commit -n -m x \;'
denies no-verify    "bash -c 'git commit --no-verify -m x'"
denies no-verify    "bash -lc 'cd sub && git push --no-verify origin 974-x'"
denies no-verify    $'bash <<\'EOF\'\ngit commit -n -m x\nEOF'
denies no-verify    'echo "$(git commit --no-verify -m x)"'
denies no-verify    'eval "git commit -n -m x"'
denies no-verify    'git status && git commit --no-verify -m x || true'

echo "── *_SKIP_PREPUSH → отказ [skip-prepush]"
denies skip-prepush 'KACHO_SKIP_PREPUSH=1 git push -u origin 974-x'
denies skip-prepush 'KANAME_SKIP_PREPUSH=1 git push -u origin 974-x'
denies skip-prepush 'CORELIB_SKIP_PREPUSH=1 git push -u origin 974-x'
denies skip-prepush 'env KACHO_SKIP_PREPUSH=1 git push'
denies skip-prepush 'env -i KANAME_SKIP_PREPUSH=true git push'
denies skip-prepush 'export KACHO_SKIP_PREPUSH=1; git push'
denies skip-prepush 'declare -x KANAME_SKIP_PREPUSH=1 && git push'
denies skip-prepush 'KACHO_SKIP_PREPUSH=1; export KACHO_SKIP_PREPUSH; git push'
denies skip-prepush 'KACHO_SKIP_PREPUSH=1 scripts/heavy-slot.sh ci-local -- git push origin HEAD:refs/heads/974-x'
denies skip-prepush "bash -c 'KANAME_SKIP_PREPUSH=1 git push'"
# имена — из хуков отправки деревьев: каждое найденное судится
hooks_read=()
for h in "$WS/scripts/hooks/pre-push" "$WS"/project/*/scripts/hooks/pre-push; do
    [ -f "$h" ] && hooks_read+=("$h")
done
names_from=${#hooks_read[@]}
: > "$WORK/skipnames"
if [ "$names_from" -gt 0 ]; then
    grep -ohE '\$\{?[A-Z][A-Z0-9_]*_SKIP_PREPUSH' "${hooks_read[@]}" | tr -d '${' | sort -u > "$WORK/skipnames"
fi
echo "  перепись: хуков отправки прочитано $names_from, имён обхода $(wc -l < "$WORK/skipnames"): $(tr '\n' ' ' < "$WORK/skipnames")"
assert "да" "$([ -s "$WORK/skipnames" ] && echo да || echo нет)" "имена обхода выведены хотя бы из одного хука (иначе ветвь слепа)"
while IFS= read -r n; do
    denies skip-prepush "$n=1 git push origin HEAD:refs/heads/974-x"
    passes "$n=0 git push origin HEAD:refs/heads/974-x"
done < "$WORK/skipnames"

echo "── core.hooksPath в любой форме → отказ [hookspath]"
denies hookspath    'git -c core.hooksPath=.nohooks commit -m x'
denies hookspath    'git -c Core.HooksPath= commit -m x'
denies hookspath    'git -c core.hooksPath push origin 974-x'
denies hookspath    'git --config-env=core.hooksPath=HP push'
denies hookspath    'git --config-env core.hooksPath=HP commit -m x'
denies hookspath    'git config core.hooksPath /dev/null'
denies hookspath    'git config --global core.hooksPath /tmp/nohooks'
denies hookspath    'git config --local core.hooksPath .nohooks'
denies hookspath    'git config --worktree core.hooksPath .nohooks'
denies hookspath    'git config -f .git/config core.hooksPath /dev/null'
denies hookspath    'git config set core.hooksPath /dev/null'
denies hookspath    'git config set --global core.hooksPath /dev/null'
denies hookspath    'git config --add core.hooksPath /dev/null'
denies hookspath    'git config --replace-all core.hooksPath /dev/null'
denies hookspath    "GIT_CONFIG_PARAMETERS=\"'core.hooksPath'='/dev/null'\" git commit -m x"
denies hookspath    'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null git commit -m x'
denies hookspath    'export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null; git push'
denies hookspath    "GIT_CONFIG_GLOBAL=$WORK/hp.cfg git commit -m x"
denies hookspath    "GIT_CONFIG_GLOBAL=$WORK/inc.cfg git commit -m x"
denies hookspath    "export GIT_CONFIG_SYSTEM=$WORK/hp.cfg; git push"
denies hookspath    "cd $WORK && GIT_CONFIG_GLOBAL=hp.cfg git commit -m x"
denies hookspath    "git -c include.path=$WORK/hp.cfg commit -m x"
denies hookspath    "git -c includeIf.onbranch:974-x.path=$WORK/inc.cfg commit -m x"
denies hookspath    "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=include.path GIT_CONFIG_VALUE_0=$WORK/hp.cfg git commit -m x"
denies hookspath    "git config --global include.path $WORK/hp.cfg"
denies hookspath    "git config set include.path $WORK/inc.cfg"

echo "── алиас с обходом, заведённый той же строкой → отказ вида обхода"
denies no-verify    "git -c alias.ci='commit --no-verify' ci -m x"
denies no-verify    "git -c alias.ci='commit -n' ci -m x"
denies no-verify    "git config alias.ci 'commit -n'"
denies no-verify    "git config --global alias.pp 'push --no-verify'"
denies no-verify    "git -c alias.x='!git commit --no-verify' x"
denies hookspath    "git -c alias.c='-c core.hooksPath=/dev/null commit' c -m x"
denies no-verify    "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=alias.ci 'GIT_CONFIG_VALUE_0=commit -n' git ci -m x"

echo "── законные близнецы → пропуск без единого слова"
passes 'git push -n origin 974-x'
passes 'git push --dry-run origin HEAD:refs/heads/974-x'
passes 'git push -u origin 974-x'
passes 'git log -n 5 --oneline'
passes 'git log --grep=--no-verify'
passes 'git merge -n origin/main'
passes 'git pull -n origin 974-x'
passes 'git rebase -n main'
passes 'git cherry-pick -n abc123'
passes 'git revert -n abc123'
passes 'git cherry-pick --no-verify abc123'
passes 'git commit -m -n'
passes 'git commit -mn'
passes 'git commit -Cn'
passes 'git commit -m "#974 страж: --no-verify, -n, core.hooksPath, KACHO_SKIP_PREPUSH=1 запрещены"'
passes $'git commit -F - <<\'EOF\'\ngit commit --no-verify и git -c core.hooksPath=/dev/null запрещены (#974)\nEOF'
passes $'git commit -m "$(cat <<\'EOF\'\n#974 страж: --no-verify, KACHO_SKIP_PREPUSH=1, -c core.hooksPath\nEOF\n)"'
passes $'cat > note.md <<\'EOF\'\ngit commit --no-verify -m x\nKACHO_SKIP_PREPUSH=1 git push\nEOF'
passes "printf '%s\\n' 'git commit -n -m x' > notes.txt"
passes 'echo "git commit --no-verify"'
passes 'echo KACHO_SKIP_PREPUSH=1'
passes "grep -rn -- '--no-verify' .claude/hooks"
passes "grep -rn 'KANAME_SKIP_PREPUSH=1' scripts"
passes "git grep -n 'core.hooksPath'"
passes 'ls # git commit --no-verify -m x'
passes 'gh issue comment 974 --body "git commit -n и git push --no-verify запрещены"'
passes 'git am -3 p.mbox'
passes 'git am -p1 p.mbox'
passes 'git -c color.ui=never commit -m y'
passes 'git -c alias.st=status st'
passes "git config alias.ci 'commit -v'"
passes 'git config core.hooksPath'
passes 'git config --get core.hooksPath'
passes 'git config get core.hooksPath'
passes 'git config --unset core.hooksPath'
passes 'git config unset core.hooksPath'
passes 'git config --unset core.hooksPath /dev/null'
passes 'git config --add core.editor vim'
passes "GIT_CONFIG_PARAMETERS=\"'color.ui'='never'\" git commit -m x"
passes 'GIT_CONFIG_GLOBAL=/dev/null git commit -m x'
passes "GIT_CONFIG_GLOBAL=$WORK/clean.cfg git commit -m x"
passes "git -c include.path=$WORK/clean.cfg commit -m x"
passes "git config include.path $WORK/clean.cfg"
passes 'KACHO_SKIP_PREPUSH=0 git push -u origin 974-x'
passes 'KACHO_SKIP_PREPUSH= git push -u origin 974-x'
passes 'unset KACHO_SKIP_PREPUSH; git push -u origin 974-x'
passes 'KACHO_PREPUSH_GROUP=tooling git push origin HEAD:refs/heads/974-x'
passes "git worktree add -q --detach $WORK/tmpcopy HEAD"
passes 'git commit --verify -m x'
passes 'git commit --amend --no-edit'
passes 'ls -la'

# git_says <sub> <слова…> — вердикт НАСТОЯЩЕГО git о разборе опций: refused | accepted.
# Репозиторий предпосылки пуст, удалённого и файлов нет: принятая команда падает
# после разбора опций, ничего не меняя.
git_says() {
    local sub="$1"; shift
    local err
    err="$(LC_ALL=C GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
           GIT_EDITOR=true timeout 10 git -C "$P" "$sub" "$@" 2>&1 < /dev/null | head -n 3)"
    case "$err" in
        *"ambiguous option"*|*"unknown option"*|*"unknown switch"*) echo refused ;;
        *) echo accepted ;;
    esac
}

echo "── сокращения: КАЖДЫЙ префикс каждой опции обхода; принял git → отказ, отверг → пропуск"
declare -A TAIL=([commit]="-m x" [push]="origin 974-x" [merge]="origin/main" [pull]="origin 974-x"
                 [am]="p.mbox" [rebase]="main")
prefix_deny=(); prefixes=0
while read -r tag sub opts; do
    [ "$tag" = long ] || continue
    read -ra tw <<< "${TAIL[$sub]:-}"
    for target in $opts; do
        for ((n = 3; n <= ${#target}; n++)); do
            pre="${target:0:n}"
            prefixes=$((prefixes + 1))
            if [ "$(git_says "$sub" "$pre" "${tw[@]}")" = accepted ]; then
                denies no-verify "git $sub $pre ${TAIL[$sub]:-}"
                prefix_deny+=("git $sub $pre ${TAIL[$sub]:-}")
            else
                passes "git $sub $pre ${TAIL[$sub]:-}"
            fi
        done
    done
done < "$WORK/guard.table"
assert "да" "$([ "${#prefix_deny[@]}" -ge 6 ] && echo да || echo нет)" \
    "префиксов перебрано $prefixes, принятых git ${#prefix_deny[@]} (≥ 6: по одному на подкоманду)"

echo "── мутанты guard.py: каждый обязан покраснеть хотя бы на одной строке"
# имя<TAB>было<TAB>стало: правка встаёт ровно в одно место (иначе мутант слеп — FAIL)
MUTANTS="$WORK/mutants.tsv"
cat > "$MUTANTS" <<'EOF'
short-n-commit	SHORT_NO_VERIFY = {"commit", "am"}	SHORT_NO_VERIFY = {"am"}
short-n-push	SHORT_NO_VERIFY = {"commit", "am"}	SHORT_NO_VERIFY = {"commit", "am", "push"}
post-rewrite	HOOK_BYPASS = {"commit": ("--no-verify", "--no-post-rewrite"),	HOOK_BYPASS = {"commit": ("--no-verify",),
skip-class	SKIP_ENV = re.compile(r"^[A-Z][A-Z0-9_]*_SKIP_PREPUSH$")	SKIP_ENV = re.compile(r"^KACHO_SKIP_PREPUSH$")
skip-zero	bare not in ("", "0")	bare not in ("",)
hookspath-case	return key.strip().strip("'\"").lower() == "core.hookspath"	return key.strip().strip("'\"") == "core.hookspath"
value-short	                    k += 2 if j == len(a) - 1 else 1	                    k += 1
value-bundle	        if c in short_v:	        if False:
heredoc-data	                if argv and os.path.basename(argv[0]) in hg.SHELLS and hg.shell_args(argv[1:])[3]:	                if argv:
config-unset	                  "--get-colorbool", "-l", "--list", "--unset", "--unset-all", "-e", "--edit",	                  "--get-colorbool", "-l", "--list", "--unset-all", "-e", "--edit",
config-read	        if len(pos) < 2:	        if len(pos) < 1:
alias-off	        value = value.strip()	        value = ""
include-off	    return out.returncode == 0 and out.stdout.strip() != ""	    return False
env-off	            yield from self.env(env, cur, depth)	            pass
prefix-plus-one	            return n  # порог: минимальный однозначный префикс	            return n + 1  # порог
prefix-minus-one	            return n  # порог: минимальный однозначный префикс	            return n - 1  # порог
EOF
python3 -I - "$GUARD" "$PARSER" "$ROWS" "$MUTANTS" "$WORK" <<'PY' > "$WORK/mut.out"
import importlib.util, os, shutil, sys
guard, parser, rows_p, muts_p, work = sys.argv[1:]
raw = open(rows_p, encoding="utf-8").read().split("\0")[:-1]
rows = [raw[i:i + 3] for i in range(0, len(raw), 3)]


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def judge(mod, hg):
    bad = []
    for want, cwd, cmd in rows:
        try:
            hit = mod.find(cmd, cwd, hg)
            got = hit[0] if hit else "pass"
        except Exception as e:  # noqa: BLE001 — исключение мутанта тоже покраснение
            got = "исключение %s" % type(e).__name__
        if got != want:
            bad.append("%s → %s: %s" % (want, got, cmd.replace("\n", " ")[:120]))
    return bad


src = open(guard, encoding="utf-8").read()
hg = load(parser, "hg_parser")
base = judge(load(guard, "control"), hg)
print("CONTROL %d %d" % (len(rows), len(base)))
for b in base[:5]:
    print("  " + b)
d = os.path.join(work, "mut")
os.makedirs(d, exist_ok=True)
for k, line in enumerate(open(muts_p, encoding="utf-8")):
    name, old, new = line.rstrip("\n").split("\t")
    cnt = src.count(old)
    if cnt != 1:
        print("SLOT %s %d" % (name, cnt))
        continue
    p = os.path.join(d, "m%d.py" % k)
    open(p, "w", encoding="utf-8").write(src.replace(old, new))
    bad = judge(load(p, "m%d" % k), hg)
    print("MUT %s %d %s" % (name, len(bad), bad[0] if bad else "—"))
PY
read -r _ nrows nbase < <(grep '^CONTROL' "$WORK/mut.out")
assert "0" "${nbase:-нет}" "контроль: копия стража без правки сходится со всеми $nrows строками таблицы"
grep -A5 '^CONTROL' "$WORK/mut.out" | grep '^  ' | sed 's/^/       /' >&2
while read -r tag name cnt first; do
    case "$tag" in
        SLOT) echo "  [FAIL] мутант $name: правка не встала ровно в одно место (мест $cnt) — мутант слеп" >&2
              fail=$((fail + 1)) ;;
        MUT)  muts=$((muts + 1))
              if [ "$cnt" -ge 1 ]; then
                  echo "  [OK]   мутант $name покраснел: разошлось строк $cnt; первая: $first"; pass=$((pass + 1))
              else
                  echo "  [FAIL] мутант $name выжил: таблица его не видит" >&2; fail=$((fail + 1))
              fi ;;
    esac
done < "$WORK/mut.out"
assert "$(grep -c . "$MUTANTS")" "$muts" "исполнено мутантов столько же, сколько объявлено"

echo "── граница стража (BOUNDARY в guard.py): известно, не ловится"
while IFS= read -r -d '' cls && IFS= read -r -d '' example; do
    rc="$(run "$example")"
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
USE_HOOK="$WORK/lone/git-guard.sh"; rc="$(run 'git commit --no-verify -m x')"; USE_HOOK="$HOOK"
assert "0 да" "$rc $(grep -q 'GIT-GUARD СЛОМАН' "$WORK/out" && echo да || echo нет)" "нет разборщика heavy-guard → код 0 и «СЛОМАН»"
mkdir -p "$WORK/syn/git-guard" "$WORK/syn/heavy-guard"
cp "$HOOK" "$WORK/syn/git-guard.sh"; cp "$PARSER" "$WORK/syn/heavy-guard/guard.py"
printf 'def broken(:\n' > "$WORK/syn/git-guard/guard.py"
USE_HOOK="$WORK/syn/git-guard.sh"; rc="$(run 'git commit --no-verify -m x')"; USE_HOOK="$HOOK"
assert "0 да" "$rc $(grep -q 'GIT-GUARD СЛОМАН' "$WORK/out" && echo да || echo нет)" "guard.py не разбирается → код 0 и «СЛОМАН»"
rc="$(run 'git commit --no-verify -m x' "$L" Read)"
assert "0 0" "$rc $(wc -c < "$WORK/out" | tr -d ' ')" "чужой инструмент (Read) → молчание"
python3 -I -c 'import json; print(json.dumps({"tool_name":"Monitor","tool_input":{"source":"ws"}}))' \
    | bash "$HOOK" > "$WORK/out" 2>&1; rc=$?
assert "0 0" "$rc $(wc -c < "$WORK/out" | tr -d ' ')" "Monitor без команды → молчание"
rc="$(run 'git commit --no-verify -m x' "$L" Monitor)"
assert "2" "$rc" "Monitor с командой судится так же, как Bash"

rows=$((denied + passed))
echo "[CENSUS] git-guard: строк таблицы $rows (отказов $denied, пропусков $passed), мутантов $muts, границ $bound, утверждений $((pass + fail)), сошлось $pass, разошлось $fail"
if [ "$rows" -lt 100 ] || [ "$denied" -eq 0 ] || [ "$passed" -eq 0 ] || [ "$bound" -eq 0 ] || [ "$muts" -eq 0 ]; then
    echo "[FAIL] git-guard — таблица сжалась: строк $rows (< 100) либо пуста одна из сторон" >&2
    exit 1
fi
[ "$fail" -eq 0 ] || { echo "[FAIL] git-guard — разошлось $fail" >&2; exit 1; }
echo "[PASS] git-guard — все $pass утверждений сошлись"
