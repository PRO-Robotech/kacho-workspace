#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# Доказательство того, что heavy-guard ОТКАЗЫВАЕТ тяжёлой команде без слота и
# ПРОПУСКАЕТ законного близнеца той же формы.
#
# Контракт стража — напоминание против случайных форм, а не барьер: предел держит
# cgroup (слот, потолок сессии). Поэтому доказательство двустороннее: пойманные
# формы — зелёные утверждения, а граница стража (BOUNDARY в guard.py) исполняется
# строкой [BOUND] — «известно, не ловится», не зелёное. Пример границы, который
# страж вдруг поймал, — [FAIL]: перечень в шапке стража устарел.
#
# Страж молчалив по замыслу: пропуск — пустой вывод и код 0. Сломанный страж
# выглядит так же, поэтому каждая форма записи тяжёлой команды подаётся ему
# настоящим входом PreToolUse, и читается код И текст: отказ обязан назвать класс
# и готовую строку «heavy-slot.sh <класс> -- <команда>» — текст отказа часть
# свойства (`testing.md`, finding-text-is-part-of-property).
#
# Тяжесть make-цели и скрипта страж выводит из дерева: на синтетическом дереве
# (цепочка предпосылок, `$(MAKE) -C`, переменные, `-n`, скрипт в скрипте, цикл по
# шаблону) и на дереве продукта — формами, которые опыт ws#832 провёл мимо
# словаря. Страж make не зовёт: рецепты синтетики пишут метку, и её отсутствие
# после всех проб — утверждение. Перепись дерева продукта печатается: сколько
# скриптов и целей осмотрено и сколько из них тяжёлых (ноль — отказ разбора).
#
# Сверки в обе стороны:
#   · классы стража = классам слота (`heavy-slot.sh --classes`), и порядок стража —
#     по убыванию бюджета слота: из нескольких найденных он берёт первый;
#   · каждая запись SCRIPTS есть в дереве продукта — запись без предмета молча
#     перестала бы что-либо ловить.
# Нет дерева продукта (${KACHO_MONOREPO:-<корень>/project/kacho}) — его части «не
# выполнились».
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

pass=0; fail=0; void=0; denied=0; passed=0; bound=0
TOOL=Bash; HOOKENV=()  # инструмент входа и окружение самого стража

assert() {
    if [ "$1" = "$2" ]; then
        echo "  [OK]   $3"; pass=$((pass + 1))
    else
        echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; fail=$((fail + 1))
    fi
}

# run <команда> [cwd] — код стража; вывод в $WORK/out. GOFLAGS и MAKEFLAGS
# прогона сняты: страж читает их из своего окружения, а оно — HOOKENV.
run() {
    python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[3],"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' \
        "$1" "${2:-$WORK}" "$TOOL" | env -u GOFLAGS -u MAKEFLAGS "${HOOKENV[@]}" CLAUDE_PROJECT_DIR=/ws bash "$HOOK" > "$WORK/out" 2>&1
    echo $?
}

# denies <класс> <команда> [cwd] — отказ, класс назван, строка с обёрткой готова.
denies() {
    local rc cls fix
    rc="$(run "$2" "${3:-}")"
    cls="$(sed -n 's/.*класс «\([^»]*\)».*/\1/p' "$WORK/out" | head -n 1)"
    fix="нет"; grep -qF -- "/ws/scripts/heavy-slot.sh $1 -- " "$WORK/out" && fix="да"
    assert "2 $1 да" "$rc $cls $fix" "отказ «$1»: $(printf '%s' "$2" | tr '\n' ' ')"
    denied=$((denied + 1))
}

# knob <ручка> <команда> — отказ вызову слота с ручкой; ручка названа, строки
# «как запустить» без неё.
knob() {
    local rc named fixed
    rc="$(run "$2")"
    named="нет"; grep -qF -- "ручку «$1" "$WORK/out" && named="да"
    fixed="$(sed -n '/Как запустить правильно/{n;p}' "$WORK/out")"
    case "$fixed" in *"${1%%=*}"*|'') fixed="нет" ;; *) fixed="да" ;; esac
    assert "2 да да" "$rc $named $fixed" "отказ ручке «$1»: $2"
    denied=$((denied + 1))
}

# boundary <класс формы> <команда> — граница: страж её пропускает, и это не зелёное.
boundary() {
    local rc
    rc="$(run "$2")"
    if [ "$rc $(wc -c < "$WORK/out" | tr -d ' ')" = "0 0" ]; then
        echo "  [BOUND] не ловится (граница: $1): $(printf '%s' "$2" | tr '\n' ' ')"; bound=$((bound + 1))
    else
        echo "  [FAIL] граница «$1» — страж поймал пример (код $rc): перечень BOUNDARY устарел: $(printf '%s' "$2" | tr '\n' ' ')" >&2
        fail=$((fail + 1))
    fi
}

# passes <команда> [cwd] — пропуск: код 0 и ни слова.
passes() {
    local rc
    rc="$(run "$1" "${2:-}")"
    assert "0 0" "$rc $(wc -c < "$WORK/out" | tr -d ' ')" "пропуск: $(printf '%s' "$1" | tr '\n' ' ')"
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

echo "── формы, которые опыт ws#832 провёл мимо стража, и их близнецы"
denies go-race     'bash -lc "go test -race ./..."'
denies go-race     'bash -ec "go test -race ./..."'
denies go-race     'sh -xc "go test -race ./..."'
denies go-race     'bash -euo pipefail -c "go test -race ./..."'
passes             'bash -lc "go test ./..."'
passes             'bash -o pipefail -c "go vet ./..."'
denies go-race     'export GOFLAGS=-race; go test ./...'
passes             'export GOFLAGS=-count=1; go test ./...'
denies go-race     'go test -race=1 ./...'
denies go-race     'go test -race=TRUE ./...'
passes             'go test -race=false ./...'
denies go-race     'R=-race; go test $R ./...'
passes             'R=-v; go test $R ./...'
denies docker      'D=docker; $D run alpine'
passes             'D=docker; $D ps'
denies go-race     'find . -name x -exec go test -race {} \;'
passes             'find . -name x -exec go vet {} \;'
denies go-race     "bash <<'EOF'
go test -race ./...
EOF"
passes             "bash <<'EOF'
go vet ./...
EOF"

echo "── круг 3: строка дочерней оболочке из переменных строки, экспорт, \$@"
denies go-race     'C="go test -race ./..."; bash -c "$C"'
passes             'C="go test ./..."; bash -c "$C"'
passes             'C="go test -race ./..."; bash -c $C'
denies go-race     "C='go test -race ./...'; sh -c \"\$C\""
passes             "C='go vet ./...'; sh -c \"\$C\""
denies go-race     "export FLAGS=-race; bash -c 'go test \$FLAGS ./...'"
passes             "FLAGS=-race; bash -c 'go test \$FLAGS ./...'"
denies go-race     "FLAGS=-race bash -c 'go test \$FLAGS ./...'"
denies go-race     "R=-race; export R; bash -c 'go test \$R ./...'"
denies go-race     "set -a; FLAGS=-race; bash -c 'go test \$FLAGS ./...'"
denies go-race     'X=go; bash -c "$X test -race ./..."'
passes             'X=go; bash -c "$X test ./..."'
denies go-race     'F="-race ./..."; bash -c "go test $F"'
passes             'F="-v ./..."; bash -c "go test $F"'
denies go-race     "R=-race; eval 'go test \$R ./...'"
passes             "R=-v; eval 'go test \$R ./...'"
denies go-race     "bash -c '\"\$@\"' _ go test -race ./..."
passes             "bash -c '\"\$@\"' _ go test ./..."
denies go-race     "sh -c 'exec go test \$1 ./...' sh -race"
passes             "sh -c 'exec go test \$1 ./...' sh -v"
HOOKENV=(GOFLAGS=-race)
denies go-race     'go test ./...'
HOOKENV=()

echo "── круг 3: опции обёрток, go -C, go run/build -race"
denies go-race     '/usr/bin/time -v go test -race ./...'
passes             '/usr/bin/time -v go test ./...'
denies go-race     '/usr/bin/time -o /tmp/t -f %M go test -race ./...'
denies go-race     'time -p go test -race ./...'
passes             'time -p go vet ./...'
denies go-race     'command -p go test -race ./...'
passes             'command -v go test -race ./...'
denies go-race     'exec -a x go test -race ./...'
denies go-race     'env -S "go test -race ./..."'
denies go-race     'go -C services/vpc test -race ./...'
passes             'go -C services/vpc test ./...'
denies go-race     'go run -race ./cmd/x'
passes             'go run ./cmd/x'
denies go-race     'go build -race -o x .'
passes             'go build -o x .'

echo "── незнакомые обёртки; строка оболочке у watch, script, parallel, flock"
denies go-race     'strace -f go test -race ./...'
passes             'strace -f go vet ./...'
passes             'echo go test -race ./...'
passes             'chmod +x scripts/ci-local.sh'
denies go-race     'systemd-run --user --scope -p MemoryMax=16G go test -race ./...'
passes             'systemd-run --user --scope -p MemoryMax=16G go vet ./...'
denies go-race     "watch -n 5 'go test -race ./...'"
passes             'watch -n 5 docker ps'
denies go-race     "script -qc 'go test -race ./...' /dev/null"
passes             "script -qc 'go vet ./...' /dev/null"
denies go-race     "parallel -j2 'go test -race {}' ::: ./a ./b"
passes             "parallel -j2 'go vet {}' ::: ./a ./b"
denies go-race     'parallel go test -race ::: ./a'
denies go-race     "flock /tmp/l -c 'go test -race ./...'"
passes             "flock /tmp/l -c 'go vet ./...'"
denies go-race     'flock -w 5 /tmp/l go test -race ./...'
denies lint        'gosec ./...'
passes             'gosec -version'
denies go-race     'docker exec box go test -race ./...'
passes             'docker exec box go test ./...'
denies docker      'docker buildx bake'
passes             'docker buildx ls'

echo "── круг 4: головы с флагами до подкоманды, make lint|test|ci по имени"
denies stand       'helm -n ns upgrade --install a ./c'
denies stand       'helm --kube-context kind-x upgrade -i a ./c'
passes             'helm -n ns list'
passes             'helm -n ns template a ./c'
denies stand       'kind -q create cluster'
denies stand       'kind --verbosity 3 create cluster --name x'
passes             'kind -q get clusters'
denies go-race     'env -S"go test -race ./..."'
denies go-race     "env -S'go test -race ./...'"
denies go-race     'env --split-string="go test -race ./..."'
denies go-race     'env -iS "go test -race ./..."'
passes             'env -S"go vet ./..."'
denies newman      'newman --verbose run c.json'
mkdir -p "$WORK/nomk"
denies lint        'make lint' "$WORK/nomk"
denies go-race     'make test' "$WORK/nomk"
denies ci-local    'make ci' "$WORK/nomk"
denies go-race     'make -C "$d" test'
passes             'make -n lint' "$WORK/nomk"
passes             'make help' "$WORK/nomk"

echo "── граница стража (BOUNDARY): известно, не ловится — не зелёное"
nb=0
while IFS= read -r -d '' what && IFS= read -r -d '' example; do
    nb=$((nb + 1)); boundary "$what" "$example"
done < <(python3 "$GUARD" --boundary < /dev/null)
assert "да" "$([ "$nb" -gt 0 ] && echo да || echo нет)" "перечень BOUNDARY прочитан: примеров $nb (ноль — разбор ослеп)"

echo "── Monitor исполняет command той же оболочкой: страж стоит и на нём"
TOOL=Monitor
denies go-race     'go test -race ./...'
passes             'tail -f run.log | grep --line-buffered ERROR'
TOOL=Bash
out="$(printf '{"tool_name":"Monitor","tool_input":{"ws":{"url":"wss://x"},"description":"d","timeout_ms":1000}}' | bash "$HOOK" 2>&1; echo "rc=$?")"
assert "rc=0" "$out" "Monitor с источником ws, без команды — пропуск молча"
wired="$(python3 -c '
import json, re, sys
ms = [e.get("matcher", "") for e in json.load(open(sys.argv[1])).get("hooks", {}).get("PreToolUse", [])
      if any("heavy-guard.sh" in h.get("command", "") for h in e.get("hooks", []))]
print(" ".join(t for t in ("Bash", "Monitor") if any(re.fullmatch(m, t) for m in ms)) or "нет")
' "$ROOT/.claude/settings.json")"
assert "Bash Monitor" "$wired" "settings.json: heavy-guard провязан на PreToolUse и для Bash, и для Monitor"

echo "── законный близнец той же формы → пропуск молча"
passes 'go test ./...'
passes 'go test -run Race ./...'
passes 'go vet ./...'
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

echo "── ручки слота в строке команды: над настоящей памятью ни одной"
knob   HEAVY_SLOT_LIMIT_GIB=200 'HEAVY_SLOT_LIMIT_GIB=200 /ws/scripts/heavy-slot.sh go-race -- go test -race ./...'
knob   HEAVY_SLOT_DIR=/tmp/x    'HEAVY_SLOT_DIR=/tmp/x bash scripts/heavy-slot.sh docker -- true'
knob   HEAVY_SLOT_MEMINFO=/tmp/m 'env HEAVY_SLOT_MEMINFO=/tmp/m heavy-slot.sh docker -- true'
knob   HEAVY_SLOT_BUDGET_MIB=1  'export HEAVY_SLOT_BUDGET_MIB=1; timeout 9 heavy-slot.sh docker -- true'
knob   HEAVY_SLOT_LIMITER=watch 'bash -c "HEAVY_SLOT_LIMITER=watch heavy-slot.sh docker -- true"'
knob   HEAVY_SLOT_WAIT_S=60     'HEAVY_SLOT_WAIT_S=60 HEAVY_SLOT_POLL_S=5 /ws/scripts/heavy-slot.sh go-race -- go test -race ./...'
knob   HEAVY_SLOT_LIMIT_GIB=1   'HEAVY_SLOT_LIMIT_GIB=1 HEAVY_SLOT_WAIT_S=99999 /ws/scripts/heavy-slot.sh docker -- true'
knob   HEAVY_SLOT_LIMIT_GIB=40  'HEAVY_SLOT_LIMIT_GIB=40 /ws/scripts/heavy-slot.sh docker -- true'
passes 'FOO=1 /ws/scripts/heavy-slot.sh docker -- true'

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

echo "── make и скрипт: тяжесть выводится из дерева, make не исполняется"
M="$WORK/mk"; MARK="$WORK/mark"
mkdir -p "$M/sub" "$M/sh"
cat > "$M/Makefile" <<EOF
GO ?= go
STAND = kind create cluster
include sub/vars.mk
.PHONY: t dep help heavydry lightdry loop plain
t: dep
	@echo building; touch $MARK
dep:
	\$(MAKE) -C sub unit
help:
	@echo "go test -race ./..."; touch $MARK
heavydry:
	touch $MARK; \$(MAKE) -C sub unit; \$(STAND)
lightdry:
	touch $MARK; \$(MAKE) -C sub unit
loop:
	@for s in sh/h*.sh; do bash "\$\$s" || exit 1; done
lightloop:
	@for s in sh/l*.sh; do bash "\$\$s" || exit 1; done
plain:
	touch $MARK; go test ./...
EOF
printf 'RACE := -race\n' > "$M/sub/vars.mk"
printf 'include vars.mk\nunit:\n\ttouch %s; go test $(RACE) ./...\n' "$MARK" > "$M/sub/Makefile"
printf '#!/usr/bin/env bash\nkind create cluster --name x\n' > "$M/sh/heavy.sh"
printf '#!/usr/bin/env bash\necho "kind create cluster"\n' > "$M/sh/light.sh"
printf '#!/usr/bin/env bash\n./inner.sh\n' > "$M/sh/outer.sh"
printf '#!/usr/bin/env bash\nnewman run c.json\n' > "$M/sh/inner.sh"
printf '#!/usr/bin/env python3\nimport os; os.system("true")\n# kind create cluster\n' > "$M/sh/tool"
printf '#!/usr/bin/env bash\ngo test ./...\n' > "$M/sh/unit.sh"
chmod +x "$M/sh/"*
denies go-race 'make t' "$M"
denies go-race 'make -C sub unit' "$M"
denies go-race 'make -C mk dep' "$WORK"
passes         'make help' "$M"
denies stand   'make -n heavydry' "$M"
passes         'make -n lightdry' "$M"
passes         'make -n t' "$M"
denies stand   'make loop' "$M"
passes         'make lightloop' "$M"
denies stand   'bash sh/heavy.sh' "$M"
denies stand   './sh/heavy.sh' "$M"
denies stand   'source sh/heavy.sh' "$M"
denies newman  'bash sh/outer.sh' "$M"
passes         'bash sh/light.sh' "$M"
passes         './sh/tool' "$M"
denies stand   'for s in sh/h*.sh; do bash "$s"; done' "$M"
passes         'for s in sh/l*.sh; do bash "$s"; done' "$M"
denies go-race 'export GOFLAGS=-race; bash sh/unit.sh' "$M"
passes         'export GOFLAGS=-count=1; bash sh/unit.sh' "$M"
denies go-race 'export GOFLAGS=-race; make plain' "$M"
denies go-race 'make plain GOFLAGS=-race' "$M"
passes         'make plain' "$M"
assert "нет" "$([ -e "$MARK" ] && echo да || echo нет)" "страж не исполнял ни одного рецепта (метки нет)"

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

echo "── классы стража = классам слота, порядок стража — по убыванию бюджета слота"
g="$(python3 "$GUARD" --classes < /dev/null)"
s="$(bash "$SLOT" --classes | awk 'NR > 1 && $0 !~ /^ / { print $1 }')"
assert "$(sort <<< "$s")" "$(sort <<< "$g")" "классы стража и слота совпадают ($(printf '%s\n' "$g" | wc -l) шт.)"
order="$(bash "$SLOT" --classes | awk 'NR > 1 && $0 !~ /^ / { v = $2; if ($3 == "ГиБ") v *= 1024; print $1, v }' |
    awk 'NR == FNR { b[$1] = $2; next } { if (NR > FNR && prev != "" && b[$1] > b[prev]) bad = bad " " prev "<" $1; prev = $1 } END { print bad == "" ? "да" : bad }' - <(printf '%s\n' "$g"))"
assert "да" "$order" "порядок RANK стража не нарушает убывания бюджетов слота"

echo "── дерево продукта: формы ws#832 и перепись"
if [ -f "$PRODUCT/Makefile" ] && [ -f "$PRODUCT/deploy/Makefile" ]; then
    denies go-race     'make test-unit' "$PRODUCT"
    denies integration 'make test-integration SVC=vpc' "$PRODUCT"
    denies stand       'make -C deploy dev-up' "$PRODUCT"
    denies stand       'make -C deploy e2e-test' "$PRODUCT"
    denies newman      'make -C deploy e2e-newman SVC=vpc' "$PRODUCT"
    denies docker      'make -C services/vpc docker' "$PRODUCT"
    denies docker      'make -C deploy build-services' "$PRODUCT"
    denies docker      'make -C deploy build-ui' "$PRODUCT"
    denies stand       'make -C deploy stack-up STACK=dev' "$PRODUCT"
    denies stand       'bash deploy/kind/create-cluster.sh' "$PRODUCT"
    denies newman      'bash services/vpc/tests/newman/scripts/run.sh' "$PRODUCT"
    denies docker      'bash deploy/tests/conformance/oidc/run-oidc-conformance.sh' "$PRODUCT"
    denies newman      'bash deploy/scripts/newman-parallel.sh vpc' "$PRODUCT"
    denies newman      './deploy/scripts/newman-e2e.sh vpc' "$PRODUCT"
    passes             'make help' "$PRODUCT"
    passes             'make -n test-unit' "$PRODUCT"
    passes             'make -C deploy dev-down' "$PRODUCT"
    passes             'make -C deploy logs-svc SVC=vpc' "$PRODUCT"
    while IFS= read -r sc; do
        have="$(git -C "$PRODUCT" ls-files | grep -c "/$sc\$\|^$sc\$")"
        assert "да" "$([ "$have" -gt 0 ] && echo да || echo нет)" "запись SCRIPTS «$sc» есть в дереве продукта"
    done < <(python3 "$GUARD" --scripts < /dev/null)
    census="$(cd "$PRODUCT" && python3 - "$GUARD" <<'PY'
import os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(sys.argv[1]))
import guard
files = subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True).stdout.split()
sh = [f for f in files if f.endswith(".sh")]
hs = sum(1 for f in sh if guard.best(guard.classes_in("bash " + f, os.getcwd(), guard.Ctx())))
mt = hm = 0
for mf in (f for f in files if os.path.basename(f) == "Makefile"):
    d = os.path.dirname(mf) or "."
    with open(mf, encoding="utf-8", errors="replace") as fh:
        targets = sorted({m.group(1) for m in re.finditer(r"^([A-Za-z0-9_-][A-Za-z0-9_.-]*)\s*:(?!=)", fh.read(), re.M)})
    for t in targets:
        mt += 1
        hm += bool(guard.best(guard.classes_in("make -C %s %s" % (d, t), os.getcwd(), guard.Ctx())))
print(len(sh), hs, mt, hm)
PY
)"
    read -r nsh hsh nmt hmt <<< "$census"
    echo "  [CENSUS] продукт: скриптов .sh осмотрено ${nsh:-?}, тяжёлых ${hsh:-?}; make-целей осмотрено ${nmt:-?}, тяжёлых ${hmt:-?}"
    assert "да" "$([ "${hsh:-0}" -gt 0 ] && [ "${hmt:-0}" -gt 0 ] && echo да || echo нет)" "перепись нашла тяжёлые скрипты и цели (ноль — разбор ослеп)"
else
    echo "  [VOID] нет дерева продукта $PRODUCT — его формы и перепись не выполнялись" >&2
    void=$((void + 1))
fi

echo "[CENSUS] heavy-guard: утверждений $((pass + fail)), сошлось $pass, разошлось $fail; отказов проверено $denied, пропусков $passed; граница (не ловится, заявлено в BOUNDARY) $bound; не построено частей $void"
[ "$fail" -eq 0 ] || exit 1
[ "$void" -eq 0 ] || exit 2
exit 0
