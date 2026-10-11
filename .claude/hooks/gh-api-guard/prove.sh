#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
# Строки команд — предмет пробы, а не код этой оболочки: `$(…)` и `$M` в них не
# раскрываются намеренно.
# shellcheck disable=SC2016
#
# prove.sh — доказательство gh-api-guard ИНЪЕКЦИЕЙ (ws#1008): хук исполняется
# настоящим входом PreToolUse (JSON на stdin, как его подаёт харнесс, с полем
# agent_type), и проба сверяет код и текст.
#
#   · НАСТОЯЩИЙ ВХОД — дословные вызовы агентов ci-watcher 2026-10-11, которыми
#     kacho#3142, kacho#3144 и kaname#703 влиты мимо посадки (журнал задачи ws#1008),
#     — отказ кодом 2 с правильным чтением merge-base в тексте;
#   · каждая запрещённая форма — отказ, класс назван;
#   · законный близнец той же формы — пропуск: код 0 и ни слова (GET, `--method GET`
#     с полями, `compare`, GraphQL-чтение, запись у git-operator вне путей вливания);
#   · граница (ГРАНИЦА шапки guard.py) — [BOUND]: известно, не ловится; пойманный
#     пример — [FAIL]: шапка устарела;
#   · мутанты guard.py (по одной правке) обязаны покраснеть;
#   · поломка стража — пропуск со словом «СЛОМАН», а не отказ всему.
# Коды: 0 — все утверждения сошлись; 1 — нет; 2 — нет python3 (вердикта нет).
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$HOOK_DIR/gh-api-guard.sh"
GUARD="$HOOK_DIR/gh-api-guard/guard.py"
command -v python3 > /dev/null 2>&1 || { echo "[VOID] gh-api-guard: нет python3" >&2; exit 2; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0; denied=0; passed=0; bound=0; muts=0
AGENT=""
assert() {
    if [ "$1" = "$2" ]; then echo "  [OK]   $3"; pass=$((pass + 1))
    else echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; fail=$((fail + 1)); fi
}
# run <команда> [хук] — код хука на настоящем входе; вывод в $WORK/out.
run() {
    python3 -c 'import json,sys; d={"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":"/tmp"}
if sys.argv[2]: d["agent_type"]=sys.argv[2]
print(json.dumps(d))' "$1" "$AGENT" > "$WORK/in.json"
    CLAUDE_PROJECT_DIR=/ws bash "${2:-$HOOK}" < "$WORK/in.json" > "$WORK/out" 2>&1
    echo $?
}
# denies <класс-текст> <команда> — отказ 2; форма названа; правильное чтение в тексте.
denies() {
    local rc named fix
    rc="$(run "$2")"
    named="нет"; grep -qF -- "$1" "$WORK/out" && named="да"
    fix="нет"; grep -qF 'gh api repos/<o>/<r>/compare/<base>...<head> --jq .merge_base_commit.sha' "$WORK/out" \
        && grep -qF 'git merge-base <base> <head>' "$WORK/out" && fix="да"
    assert "2 да да" "$rc $named $fix" "отказ${AGENT:+ [$AGENT]} ($1): $(printf '%s' "$2" | tr '\n' ' ')"
    denied=$((denied + 1))
}
passes() {
    local rc
    rc="$(run "$1")"
    assert "0 0" "$rc $(wc -c < "$WORK/out" | tr -d ' ')" "пропуск${AGENT:+ [$AGENT]}: $(printf '%s' "$1" | tr '\n' ' ')"
    passed=$((passed + 1))
}
boundary() {
    local rc
    rc="$(run "$2")"
    if [ "$rc $(wc -c < "$WORK/out" | tr -d ' ')" = "0 0" ]; then
        echo "  [BOUND] не ловится (граница: $1): $(printf '%s' "$2" | tr '\n' ' ')"; bound=$((bound + 1))
    else
        echo "  [FAIL] граница «$1» — страж поймал пример (код $rc): шапка guard.py устарела" >&2; fail=$((fail + 1))
    fi
}

# `<<` — переменной: литерал heredoc в строке данных читатели прозы приняли бы за начало тела.
LT='<<'
W='изменяющий вызов gh api'
G='gh api graphql с mutation'
M='путь вливания repos/*/merges или pulls/*/merge'
P='gh pr merge вне правила вливания'

echo "== настоящий вход: вызовы, которыми влиты kacho#3142, kacho#3144, kaname#703"
AGENT=ci-watcher
# Дословные строки — данными heredoc: кавычки и переносы в них — предмет пробы.
real() { local v; IFS= read -r -d '' v || true; printf '%s' "${v%$'\n'}"; }
R1="$(real <<'EOF'
gh api repos/PRO-Robotech/kacho/merges -X POST -f base='1266' -f head='3101' --jq '.commit.oid // .message // "no_merge"' 2>&1
EOF
)"
R2="$(real <<'EOF'
gh api repos/PRO-Robotech/kacho/merges -X POST -F base='1266' -F head='3101' --jq '.commit.oid // "merge_error"' 2>&1
EOF
)"
R3="$(real <<'EOF'
gh api repos/PRO-Robotech/kacho/merges -f base=1266 -f head=636d2f4587e4212b4f70536ac1d2e1b752082eb2 --jq '.commit.sha // "merge_base_error"' 2>&1 | head -1
EOF
)"
R4="$(real <<'EOF'
# Get merge-base of the branches
MERGE_BASE=$(gh api repos/PRO-Robotech/kaname/merges \
  -X POST \
  -f base="296" \
  -f head="685" \
  -q '.commit.sha // "error"')
echo "Merge-base: $MERGE_BASE"
EOF
)"
R5="$(real <<'EOF'
gh api -R PRO-Robotech/kaname repos/merges \
  -f base='origin/296' \
  -f head='origin/678' \
  --jq '.commit.oid' 2>/dev/null || echo "merge-base check failed"
EOF
)"
denies "$M" "$R1"
denies "$M" "$R2"
denies "$M" "$R3"
denies "$M" "$R4"
denies "$W" "$R5"

echo "== запрещённые формы — отказ (агент не git-operator)"
for AGENT in "" scout check-verifier landing-reviewer wave-reviewer; do
    denies "$W" 'gh api -X POST repos/x/y/issues/1/comments -f body=hi'
done
AGENT=scout
denies "$W" 'gh api -XPOST repos/x/y/issues/1/comments -f body=hi'
denies "$W" 'gh api --method=patch repos/x/y/issues/1 -f state=closed'
denies "$W" 'gh api --method PUT repos/x/y/issues/1/lock'
denies "$W" 'gh api -X DELETE repos/x/y/git/refs/heads/b'
denies "$W" 'gh api repos/x/y/issues/1/labels -f "labels[]=P0"'
denies "$W" 'gh api repos/x/y/issues -F title=t --raw-field body=b'
denies "$W" 'gh api repos/x/y/issues/1/labels --input f.json'
denies "$W" 'gh api repos/x/y/issues --field=title=t'
denies "$W" 'gh api -X "$M" repos/x/y/issues'
# группа коротких флагов — как pflag: каждая буква флаг (возврат check-verifier; gh 2.100.0
# под GH_DEBUG=api шлёт на этих формах POST)
denies "$M" 'gh api -iXPOST repos/x/y/merges'
denies "$M" 'gh api -iX POST repos/x/y/merges'
denies "$M" 'gh api repos/x/y/merges -if base=a -if head=b'
denies "$M" 'gh api repos/x/y/merges -F base=a -F head=b'
denies "$W" 'gh api -iXPOST repos/x/y/issues/1/comments -f body=hi'
denies "$W" 'gh api -X=POST repos/x/y/issues'
denies "$G" 'gh api graphql -f query="mutation { addLabelsToLabelable(input:{}) { clientMutationId } }"'
denies "$G" 'gh api graphql -F query=@q.graphql'
denies "$M" 'gh api repos/x/y/pulls/3/merge -X PUT -f merge_method=merge'
denies "$M" 'x=$(gh api repos/x/y/merges -X POST -f base=a -f head=b)'
denies "$M" 'bash -c "gh api -X POST repos/x/y/merges -f base=a -f head=b"'
denies "$M" 'cd /x && timeout 60 gh api repos/x/y/merges -f base=a -f head=b | jq .'
denies "$M" 'for b in 1 2; do gh api repos/x/y/merges -f base=$b -f head=h; done'
denies "$M" $'bash '"$LT"$'EOF\ngh api repos/x/y/merges -f base=a -f head=b\nEOF'
denies "$P" 'gh pr merge 7 --merge --match-head-commit abc'
denies "$P" 'gh pr merge 7 --merge'

echo "== git-operator: пути вливания и gh pr merge вне правила — отказ"
AGENT=git-operator
denies "$M" 'gh api repos/x/y/merges -X POST -f base=a -f head=b'
denies "$M" 'gh api -X PUT repos/x/y/pulls/3/merge'
denies "$M" 'gh api repos/x/y/pulls/3/merge'
denies "$P" 'gh pr merge 7 --merge'
denies "$P" 'gh pr merge 7 --merge --auto --match-head-commit abc'
denies "$P" 'gh pr merge 7 --merge --admin --match-head-commit abc'

echo "== законные близнецы той же формы — пропуск без слова"
for AGENT in "" ci-watcher; do
    passes 'gh api repos/x/pulls/1'
done
AGENT=ci-watcher
passes 'gh api repos/x/y/compare/main...b --jq .merge_base_commit.sha'
passes 'gh api --method GET search/issues -f q=repo:x/y'
passes 'gh api -X GET search/issues -f q=x --paginate'
passes 'gh api -XGET search/issues -f q=x'
passes 'gh api --method=get repos/x/y/issues -f state=open'
passes 'gh api -iX GET repos/x/y/merges'
passes 'gh api -iX GET search/issues -if q=x'
passes 'gh api -X=GET search/issues -f q=x'
passes 'gh api -i repos/x/y/pulls/1'
passes 'gh api repos/x/y/pulls/3/merge'
passes 'gh api repos/x/y/commits/abc/check-runs --jq ".check_runs[].conclusion"'
passes "gh api graphql -f query='query(\$o:String!){ repository(owner:\$o,name:\"y\"){ id } }' -F o=x"
passes 'git merge-base origin/1266 3101'
passes 'git merge-base --is-ancestor 8221edd origin/1266'
passes 'git commit -m "gh api -X POST repos/x/y/merges"'
passes 'echo "gh pr merge 7 --auto"; grep -n "repos/x/y/merges" f'
passes 'gh pr merge 7 --disable-auto'
passes 'gh pr view 7 --json state,mergeCommit'
AGENT=git-operator
passes 'gh api -X POST repos/x/y/issues/1/comments -f body=hi'
passes 'gh api -X POST repos/x/y/issues/896/sub_issues -F sub_issue_id=1'
passes 'gh api -X DELETE repos/x/y/git/refs/heads/b'
passes 'gh api graphql -f query="mutation { addLabelsToLabelable(input:{}) { clientMutationId } }"'
passes 'gh pr merge 7 --merge --match-head-commit 4e96de2b'
passes 'gh pr merge 7 --merge --match-head-commit=4e96de2b'
AGENT=""

echo "== граница (ГРАНИЦА шапки guard.py) — известно, не ловится"
boundary "вызов внутри скрипта"        'bash ./merge-base.sh'
boundary "eval: строка не разбирается" 'eval "gh api -X POST repos/x/y/merges"'
boundary "xargs: argv из входа"        'echo repos/x/y/merges | xargs gh api -X POST'
boundary "команда из переменной"       '$GH api -X POST repos/x/y/merges'
boundary "иной клиент того же API"     'curl -X POST https://api.github.com/repos/x/y/merges'

echo "== поломка стража — пропуск со словом «СЛОМАН», а не отказ"
mkdir -p "$WORK/broken/gh-api-guard"
cp "$HOOK" "$WORK/broken/gh-api-guard.sh"
printf 'raise RuntimeError("проба")\n' > "$WORK/broken/gh-api-guard/guard.py"
rc="$(run 'gh api -X POST repos/x/y/merges' "$WORK/broken/gh-api-guard.sh")"
assert "0 да" "$rc $(grep -qF 'СЛОМАН' "$WORK/out" && echo да || echo нет)" "guard.py бросает — код 0 и «СЛОМАН» (не отказ всему)"
rm -rf "$WORK/broken/gh-api-guard"
rc="$(run 'gh api -X POST repos/x/y/merges' "$WORK/broken/gh-api-guard.sh")"
assert "0 да" "$rc $(grep -qF 'СЛОМАН' "$WORK/out" && echo да || echo нет)" "guard.py нет — код 0 и «СЛОМАН»"

echo "== мутанты guard.py — обязаны покраснеть"
# mutant <имя> <было> <стало> <команда> [агент]: мутант меняет исход на настоящем входе.
mutant() {
    local d="$WORK/m$muts"
    mkdir -p "$d/gh-api-guard" "$d/no-wait-guard" "$d/heavy-guard"
    cp "$HOOK" "$d/gh-api-guard.sh"
    cp "$HOOK_DIR/no-wait-guard/guard.py" "$d/no-wait-guard/guard.py"
    cp "$HOOK_DIR/heavy-guard/guard.py" "$d/heavy-guard/guard.py"
    if ! python3 - "$GUARD" "$d/gh-api-guard/guard.py" "$2" "$3" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
if s.count(a) != 1:
    sys.exit(1)
open(dst, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
    then echo "  [FAIL] мутант «$1»: образец не найден в guard.py" >&2; fail=$((fail + 1)); muts=$((muts + 1)); return; fi
    local want got
    AGENT="${5:-}"
    want="$(run "$4")"; got="$(run "$4" "$d/gh-api-guard.sh")"
    AGENT=""
    if [ "$want" != "$got" ] && ! grep -qF 'СЛОМАН' "$WORK/out"; then
        echo "  [OK]   мутант «$1» красный: «$4» — $want → $got"; pass=$((pass + 1))
    else
        echo "  [FAIL] мутант «$1» выжил: «$4» — $want → $got" >&2; fail=$((fail + 1))
    fi
    muts=$((muts + 1))
}
mutant "тело без метода — чтение"        'or (method is None and (fields or inp))' 'or False' 'gh api repos/x/y/issues -f title=t' ci-watcher
mutant "явный GET не разрешает поля"     '    if writes and not explicit_read and agent != OPERATOR:' '    if (writes or fields) and agent != OPERATOR:' 'gh api --method GET search/issues -f q=x' ci-watcher
mutant "метод вне чтения — не запись"     '        method is not None and method not in READ)' '        False)' 'gh api -X "$M" repos/x/y/issues' ci-watcher
mutant "слитный -XPOST не разобран"      '            out.append((name, rest or None))' '            out.append((name, None))' 'gh api -XGET search/issues -f q=x' ci-watcher
mutant "распаковки группы нет"           '        j += 1' '        break' 'gh api -iXPOST repos/x/y/merges' ci-watcher
mutant "распаковки группы нет (-if)"     '        j += 1' '        break' 'gh api repos/x/y/merges -if base=a -if head=b' ci-watcher
mutant "-X=… не отделяет значение"       '        if rest.startswith("="):' '        if False:' 'gh api -X=GET search/issues -f q=x' ci-watcher
mutant "--method=… не разобран"          '            if "=" in a:' '            if False:' 'gh api --method=post repos/x/y/issues' ci-watcher
mutant "регистр метода"                  '            method = (val or "").strip().upper()' '            method = (val or "").strip()' 'gh api --method get search/issues -f q=x' ci-watcher
mutant "--input не тело"                 '        elif name == "--input":' '        elif False:' 'gh api repos/x/y/issues --input f.json' ci-watcher
mutant "git-operator пишет в merges"     '    if merge_path and (writes or agent == OPERATOR):' '    if merge_path and agent != OPERATOR and writes:' 'gh api repos/x/y/merges -X POST -f base=a -f head=b' git-operator
mutant "путь pulls/N/merge не узнан"     'merge_path = bool(MERGES.search(ep) or PR_MERGE.search(ep))' 'merge_path = bool(MERGES.search(ep))' 'gh api repos/x/y/pulls/3/merge' git-operator
mutant "запись у всех агентов"           '    if writes and not explicit_read and agent != OPERATOR:' '    if writes and not explicit_read:' 'gh api -X POST repos/x/y/issues/1/comments -f body=hi' git-operator
mutant "mutation не судится"             'bad = [f for f in fields if MUTATION.search(f) or' 'bad = [f for f in fields if' 'gh api graphql -f query="mutation { x }"' ci-watcher
mutant "GraphQL-чтение — как запись"     '        return None
    if merge_path' '        return Finding("graphql-write", shown, "x")
    if merge_path' "gh api graphql -f query='query{ viewer { login } }'" ci-watcher
mutant "pr merge у любого агента"        '    if agent != OPERATOR:
        return Finding("pr-merge"' '    if False:
        return Finding("pr-merge"' 'gh pr merge 7 --merge --match-head-commit abc' ci-watcher
mutant "pr merge без сверки головы"      '    if "--match-head-commit" not in flags:' '    if False:' 'gh pr merge 7 --merge' git-operator
mutant "--auto пропущен"                 '    if "--auto" in flags:' '    if False:' 'gh pr merge 7 --merge --auto --match-head-commit abc' git-operator
mutant "--disable-auto — вливание"       '    if "--disable-auto" in flags:
        return None' '    pass' 'gh pr merge 7 --disable-auto' ci-watcher
mutant "подстановка не судится"          '            self.text(s)' '            pass' 'x=$(gh api -X POST repos/x/y/merges)' ci-watcher
mutant "bash -c не разбирается"          '                self.text(cmd)' '                pass' 'bash -c "gh api -X POST repos/x/y/merges"' ci-watcher
mutant "heredoc в оболочку не судится"  '                    self.text(hbody)' '                    pass' $'bash '"$LT"$'EOF\ngh api -X POST repos/x/y/merges\nEOF' ci-watcher
mutant "без agent_type — git-operator"  '    w = Walker(agent_type or None)' '    w = Walker(agent_type or OPERATOR)' 'gh api -X POST repos/x/y/issues/1/comments -f body=hi'

total=$((pass + fail))
echo "[CENSUS] gh-api-guard: рассмотрено утверждений $total, сошлось $pass, разошлось $fail; отказов проверено $denied, пропусков $passed, мутантов $muts; граница (не ловится, заявлено в шапке) $bound"
if [ "$total" -eq 0 ]; then
    echo "[VOID] gh-api-guard: утверждений не исполнено ни одного — доказательства нет" >&2
    exit 2
fi
[ "$fail" -eq 0 ]
