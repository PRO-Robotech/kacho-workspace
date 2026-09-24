#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# Доказательство того, что heavy-guard ОТКАЗЫВАЕТ тяжёлой команде без слота и
# ПРОПУСКАЕТ законного близнеца той же формы.
#
# Страж молчалив по замыслу: пропуск — пустой вывод и код 0. Сломанный страж
# выглядит так же, поэтому каждая форма записи тяжёлой команды подаётся ему
# настоящим входом PreToolUse, и читается код И текст: отказ обязан назвать класс
# и готовую строку «heavy-slot.sh <класс> -- <команда>» — текст отказа часть
# свойства (`testing.md`, finding-text-is-part-of-property).
#
# Сверки в обе стороны:
#   · словарь классов стража = классам слота (`heavy-slot.sh --classes`): класс,
#     которого слот не знает, дал бы исполнителю строку, падающую кодом 64;
#   · каждая make-цель словаря есть в дереве продукта — запись без предмета
#     (цель переименовали) молча перестала бы что-либо ловить. Нет дерева продукта
#     (${KACHO_MONOREPO:-<корень>/project/kacho}) — эта часть «не выполнилась».
#
# Коды: 0 — все утверждения сошлись; 1 — хотя бы одно нет; 2 — сошлось всё
# исполненное, но часть не построена (нет дерева продукта).
# Команды ниже — ВХОДЫ стража, а не исполняемый код: раскрывать их нельзя.
# shellcheck disable=SC2016
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$HOOK_DIR/../.." && pwd)"
HOOK="$HOOK_DIR/heavy-guard.sh"
GUARD="$HOOK_DIR/heavy-guard/guard.py"
SLOT="$ROOT/scripts/heavy-slot.sh"
PRODUCT="${KACHO_MONOREPO:-$ROOT/project/kacho}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0; void=0; denied=0; passed=0

assert() {
    if [ "$1" = "$2" ]; then
        echo "  [OK]   $3"; pass=$((pass + 1))
    else
        echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; fail=$((fail + 1))
    fi
}

# run <команда> [cwd] — код стража; вывод в $WORK/out.
run() {
    python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' \
        "$1" "${2:-$WORK}" | CLAUDE_PROJECT_DIR=/ws bash "$HOOK" > "$WORK/out" 2>&1
    echo $?
}

# denies <класс> <команда> [cwd] — отказ, класс назван, строка с обёрткой готова.
denies() {
    local rc cls fix
    rc="$(run "$2" "${3:-}")"
    cls="$(sed -n 's/.*класс «\([^»]*\)».*/\1/p' "$WORK/out" | head -n 1)"
    fix="нет"; grep -qF -- "/ws/scripts/heavy-slot.sh $1 -- " "$WORK/out" && fix="да"
    assert "2 $1 да" "$rc $cls $fix" "отказ «$1»: $2"
    denied=$((denied + 1))
}

# passes <команда> [cwd] — пропуск: код 0 и ни слова.
passes() {
    local rc
    rc="$(run "$1" "${2:-}")"
    assert "0 0" "$rc $(wc -c < "$WORK/out" | tr -d ' ')" "пропуск: $1"
    passed=$((passed + 1))
}

if [ ! -f "$HOOK" ] || [ ! -f "$GUARD" ] || [ ! -f "$SLOT" ]; then
    echo "[VOID] heavy-guard: нет хука, стража или слота — доказывать нечего" >&2
    exit 2
fi

echo "── формы записи тяжёлой команды → отказ с классом и готовой строкой"
denies go-race     'go test -race ./...'
denies go-race     'go test -count=1 -race=true ./services/vpc/...'
denies go-race     'GOFLAGS=-race go test ./x'
denies integration 'go test -tags=integration ./...'
denies integration 'go test -tags "a integration" ./...'
denies go-race     'cd /x && timeout 900 go test -race ./... 2>&1 | tee run.log'
denies go-race     'bash -c "go test -race ./..."'
denies go-race     'echo a | xargs -n1 go test -race'
denies go-race     'for p in a b; do go test -race $p; done'
denies go-race     'echo "$(go test -race ./...)"'
denies go-race     'make test-unit'
denies integration 'make test-integration SVC=vpc'
denies stand       'make -C deploy dev-up'
denies newman      'make e2e-newman SVC=vpc'
denies ci-local    'bash scripts/ci-local.sh go'
denies ci-local    './scripts/ci-local.sh'
denies lint        'golangci-lint run ./...'
denies lint        'govulncheck ./...'
denies go-race     'docker run --rm golang:1.26.8 go test -race ./...'
denies integration "docker run --rm -v /var/run/docker.sock:/var/run/docker.sock golang:1.26.8 sh -c 'go test -race ./...'"
denies docker      'docker run --rm alpine true'
denies docker      'docker build -t x .'
denies docker      'docker compose up -d'
denies stand       'kind create cluster --name x'
denies stand       'helm upgrade --install a ./c'
denies newman      'newman run c.json'
denies newman      'npx -y newman run c.json'

echo "── законный близнец той же формы → пропуск молча"
passes 'go test ./...'
passes 'go test -run Race ./...'
passes 'go vet ./...'
passes 'make -n test-unit'
passes 'make help'
passes 'docker ps'
passes 'docker compose logs'
passes 'kind get clusters'
passes 'helm template a ./c'
passes 'newman --version'
passes 'echo "go test -race ./..."'
passes 'git commit -m "go test -race; docker run x"'
passes "grep -rn 'docker run' docs/"
passes '# go test -race ./...'
passes "cat > f.sh <<'EOF'
go test -race ./...
docker run x
EOF"
passes "git commit -m \"\$(cat <<'EOF'
go test -race и docker run
EOF
)\""
passes '/ws/scripts/heavy-slot.sh go-race -- go test -race ./...'
passes 'bash scripts/heavy-slot.sh docker -- docker run --rm alpine true'

echo "── git push: тяжёл там, где pre-push клона зовёт ci-local (признак — дерево)"
mkdir -p "$WORK/prod/.git" "$WORK/prod/scripts/hooks" "$WORK/ws/.git" "$WORK/ws/scripts/hooks"
: > "$WORK/prod/scripts/ci-local.sh"
echo 'bash "$subject_root/scripts/ci-local.sh" $groups' > "$WORK/prod/scripts/hooks/pre-push"
echo 'bash scripts/rules-gate/run-all.sh' > "$WORK/ws/scripts/hooks/pre-push"
denies ci-local 'git push origin x' "$WORK/prod"
denies ci-local "git -C $WORK/prod push"
passes 'git push origin x' "$WORK/ws"
passes "cd $WORK/prod && git push --no-verify"
: > "$WORK/ws/scripts/ci-local.sh"
passes 'git push origin x' "$WORK/ws"

echo "── не Bash и поломка стража"
out="$(printf '{"tool_name":"Edit","tool_input":{"file_path":"x"}}' | bash "$HOOK" 2>&1; echo "rc=$?")"
assert "rc=0" "$out" "вызов не Bash — пропуск молча"
out="$(echo 'not json' | bash "$HOOK" 2>/dev/null)"; rc=$?
said="нет"; printf '%s' "$out" | grep -qF 'СЛОМАН' && said="да"
assert "0 да" "$rc $said" "вход не JSON — пропуск со словом «СЛОМАН», а не молча"
mkdir -p "$WORK/lone"; cp "$HOOK" "$WORK/lone/"
out="$(echo '{}' | bash "$WORK/lone/heavy-guard.sh")"; rc=$?
said="нет"; printf '%s' "$out" | grep -qF 'СЛОМАН' && said="да"
assert "0 да" "$rc $said" "нет guard.py — пропуск со словом «СЛОМАН»"
out="$(echo '{}' | env PATH=/nonexistent /bin/bash "$HOOK")"; rc=$?
said="нет"; printf '%s' "$out" | grep -qF 'python3' && said="да"
assert "0 да" "$rc $said" "нет python3 — пропуск, причина названа"

echo "── словарь классов стража = классам слота, в обе стороны"
g="$(python3 "$GUARD" --classes | sort)"
s="$(bash "$SLOT" --classes | awk 'NR > 1 && $0 !~ /^ / { print $1 }' | sort)"
assert "$s" "$g" "классы стража и слота совпадают ($(printf '%s\n' "$g" | wc -l) шт.)"

echo "── каждая make-цель словаря есть в дереве продукта"
if [ -f "$PRODUCT/Makefile" ] && [ -f "$PRODUCT/deploy/Makefile" ]; then
    n=0
    while IFS= read -r t; do
        n=$((n + 1))
        have="нет"; grep -qE "^$t:" "$PRODUCT/Makefile" "$PRODUCT/deploy/Makefile" && have="да"
        assert "да" "$have" "make-цель «$t» есть в $PRODUCT"
    done < <(python3 "$GUARD" --make-targets)
    assert "да" "$([ "$n" -gt 0 ] && echo да || echo нет)" "словарь make-целей непуст ($n)"
else
    echo "  [VOID] нет дерева продукта $PRODUCT — сверка make-целей не выполнялась" >&2
    void=$((void + 1))
fi

echo "[CENSUS] heavy-guard: утверждений $((pass + fail)), сошлось $pass, разошлось $fail; отказов проверено $denied, пропусков $passed; не построено частей $void"
[ "$fail" -eq 0 ] || exit 1
[ "$void" -eq 0 ] || exit 2
exit 0
