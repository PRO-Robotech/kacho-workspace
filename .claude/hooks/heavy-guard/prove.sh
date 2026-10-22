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
#     перестала бы что-либо ловить;
#   · класс suite (ws#1291): каждый набор `scripts/lib/suites.py` (прогонщик и
#     доказательство) и каждый шаг ci.yaml с именем набора или пробы — suite.
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
        "$1" "${2:-$WORK}" "$TOOL" | env -u GOFLAGS -u MAKEFLAGS "${HOOKENV[@]}" CLAUDE_PROJECT_DIR=/ws bash "${HOOK_RUN:-$HOOK}" > "$WORK/out" 2>&1
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
passes             'bash -lc "go vet ./..."'
passes             'bash -o pipefail -c "go vet ./..."'
denies go-race     'export GOFLAGS=-race; go test ./...'
passes             'export GOFLAGS=-count=1; go vet ./...'
denies go-race     'go test -race=1 ./...'
denies go-race     'go test -race=TRUE ./...'
denies go-unit     'go test -race=false ./...'  # любой go test — внешний кластер (ws#1301)
denies go-race     'R=-race; go test $R ./...'
passes             'R=-v; go vet $R ./...'
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
passes             'C="go vet ./..."; bash -c "$C"'
passes             'C="go test -race ./..."; bash -c $C'
denies go-race     "C='go test -race ./...'; sh -c \"\$C\""
passes             "C='go vet ./...'; sh -c \"\$C\""
denies go-race     "export FLAGS=-race; bash -c 'go test \$FLAGS ./...'"
denies go-unit     "FLAGS=-race; bash -c 'go test \$FLAGS ./...'"  # любой go test (ws#1301)
denies go-race     "FLAGS=-race bash -c 'go test \$FLAGS ./...'"
denies go-race     "R=-race; export R; bash -c 'go test \$R ./...'"
denies go-race     "set -a; FLAGS=-race; bash -c 'go test \$FLAGS ./...'"
denies go-race     'X=go; bash -c "$X test -race ./..."'
passes             'X=go; bash -c "$X vet ./..."'
denies go-race     'F="-race ./..."; bash -c "go test $F"'
passes             'F="-v ./..."; bash -c "go vet $F"'
denies go-race     "R=-race; eval 'go test \$R ./...'"
passes             "R=-v; eval 'go vet \$R ./...'"
denies go-race     "bash -c '\"\$@\"' _ go test -race ./..."
passes             "bash -c '\"\$@\"' _ go vet ./..."
denies go-race     "sh -c 'exec go test \$1 ./...' sh -race"
passes             "sh -c 'exec go vet \$1 ./...' sh -v"
HOOKENV=(GOFLAGS=-race)
denies go-race     'go test ./...'
HOOKENV=()

echo "── круг 3: опции обёрток, go -C, go run/build -race"
denies go-race     '/usr/bin/time -v go test -race ./...'
passes             '/usr/bin/time -v go vet ./...'
denies go-race     '/usr/bin/time -o /tmp/t -f %M go test -race ./...'
denies go-race     'time -p go test -race ./...'
passes             'time -p go vet ./...'
denies go-race     'command -p go test -race ./...'
passes             'command -v go test -race ./...'
denies go-race     'exec -a x go test -race ./...'
denies go-race     'env -S "go test -race ./..."'
denies go-race     'go -C services/vpc test -race ./...'
passes             'go -C services/vpc vet ./...'
denies go-race     'go run -race ./cmd/x'
passes             'go run ./cmd/x'
denies go-race     'go build -race -o x .'
denies go-unit     'go build -o x .'  # сборка — внешний кластер (ws#1301)

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
passes             'docker exec box go vet ./...'
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

echo "── машина владельца — не для прогонов (ws#1301): любая сборка и тест — отказ, git и правка файла — пропуск"
denies go-unit     'go test ./...'
denies go-unit     'cd services/vpc && go test -run TestX ./internal/...'
denies go-unit     'go build ./...'
denies go-unit     'make test-unit'
denies go-unit     'make e2e-smoke-test'
denies suite       'pytest -q tools/'
denies suite       'python3 -m pytest tools/'
denies stand       'npx playwright test'
denies stand       'npm run test:e2e'
denies ci-local    'npm test'
denies ci-local    'npm ci --prefix ui-future'
denies ci-local    'npm run typecheck'
denies ci-local    'npx vitest run'
passes             'git status'
passes             'git diff --stat origin/main...HEAD'
passes             'gh issue view 1301'
passes             "sed -i 's/a/b/' f.txt"
passes             'gofmt -l .'
passes             'go version'
passes             'go list ./...'
passes             'npm --version'
passes             'npm run dev'
passes             'make generate'
passes             'python3 -c "print(1)"'
passes             'playwright --version'

echo "── законный близнец той же формы → пропуск молча"
passes 'go vet ./...'
passes 'go vet -run Race ./...'
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

echo "── синтаксическая проверка — не исполнение (ws#1247): noexec — пропуск, близнецы — прежний отказ"
# Каждая форма судится ДВАЖДЫ: стражем (на месте @H@ — `go test -race ./...`) и настоящей
# оболочкой (на месте @H@ — запись метки): отказ обязан быть формой, которая ИСПОЛНЯЕТ
# тело, пропуск — формой, которая его НЕ исполняет. Так причина отказа («тяжёлая
# команда») подтверждена исполнением, а не догадкой стража. Оболочка оракула — без
# управляющего терминала (setsid) и с HOME прогона: интерактивная (`-i`) читает ~/.bashrc
# и берёт терминал, а вердикт не должен зависеть от машины.
NX="$WORK/nx"; NXO="$WORK/nxo"; NXS=(); command -v setsid > /dev/null && NXS=(setsid -w)
mkdir -p "$NX/scripts" "$NX/tmp" "$NXO/scripts" "$NXO/tmp"
printf 'go test -race ./...\n' > "$NX/heavy.sh"; : > "$NX/scripts/ci-local.sh"
printf 'bash scripts/ci-local.sh go\n' > "$NX/tmp/land-3261.sh"
printf 'touch "%s/ran"\n' "$NXO" | tee "$NXO/heavy.sh" "$NXO/scripts/ci-local.sh" > "$NXO/tmp/land-3261.sh"
chmod +x "$NX/scripts/ci-local.sh" "$NXO/scripts/ci-local.sh"
# nx_ran <форма> — исполнила ли настоящая оболочка тело формы: да | нет
nx_ran() {
    rm -f "$NXO/ran"
    (cd "$NXO" && HOME="$NXO" timeout 20 "${NXS[@]}" bash -c "${1//@H@/touch $NXO/ran}") > /dev/null 2>&1 < /dev/null
    if [ -e "$NXO/ran" ]; then echo да; else echo нет; fi
}
# nx <пропуск|класс> <форма> — страж и настоящая оболочка над одной формой
nx() {
    local o="${2//@H@/touch $NXO/ran}"
    if [ "$1" = пропуск ]; then passes "${2//@H@/go test -race ./...}" "$NX"; else denies "$1" "${2//@H@/go test -race ./...}" "$NX"; fi
    assert "$([ "$1" = пропуск ] && echo нет || echo да)" "$(nx_ran "$2")" "оболочка: тело $([ "$1" = пропуск ] && echo НЕ )исполнено — $(printf '%s' "$o" | tr '\n' ' ')"
}
# nx_cons <класс> <форма> — отказ КОНСЕРВАТИВЕН: страж не полагается на поведение версии
# оболочки, которое man называет иначе; исход оракула печатается, но не утверждается
nx_cons() {
    denies "$1" "${2//@H@/go test -race ./...}" "$NX"
    echo "         оракул здесь: тело исполнено — $(nx_ran "$2"); отказ консервативен"
}
nx go-race   'bash heavy.sh'
nx пропуск   'bash -n heavy.sh'
nx пропуск   'sh -n heavy.sh'
nx пропуск   'bash -nx heavy.sh'
nx пропуск   'bash -xn heavy.sh'
nx пропуск   'bash -n -x heavy.sh'
nx пропуск   'bash -o noexec heavy.sh'
nx пропуск   'bash -n scripts/ci-local.sh'
nx пропуск   'bash -n -c "@H@"'
nx пропуск   'bash -nc "@H@"'
nx пропуск   "bash -c 'set -n; @H@'"
nx пропуск   "sh -c 'set -n; @H@'"
nx пропуск   "bash -c 'set -e; set -o noexec; @H@'"
nx пропуск   "bash -n <<'EOF'
@H@
EOF"
nx пропуск   "bash -c 'set -n
@H@'"
echo "   близнецы «почти совпадение» — прежний отказ"
nx go-race   'bash heavy.sh -n'
nx ci-local  './scripts/ci-local.sh -n'
nx go-race   'bash -n +n heavy.sh'
nx go-race   'bash -o noexec +o noexec heavy.sh'
nx go-race   "bash -c '@H@; set -n'"
nx go-race   "bash -c 'set -n | cat; @H@'"
nx go-race   "bash -c 'set -n & @H@'"
nx go-race   "bash -c '(set -n); @H@'"
nx go-race   "bash -c 'set -- -n; @H@'"
nx go-race   "bash -c 'set +n; @H@'"
nx go-race   'bash -n heavy.sh; bash heavy.sh'
nx go-race   "bash <<'EOF'
set -x
@H@
EOF"
echo "   интерактивная оболочка (-i в любой связке) noexec не соблюдает — отказ"
nx go-race   "bash -ic 'set -n; @H@'"
nx go-race   "bash -xi -c 'set -n; @H@'"
nx go-race   "bash -i -c 'set -o noexec; @H@'"
nx go-race   "bash -ic 'set -e; set -o noexec; @H@'"
nx go-race   "bash -i <<'EOF'
set -n
@H@
EOF"
nx go-race   "bash -is <<'EOF'
set -o noexec
@H@
EOF"
echo "   -n флагом при -i: bash 5.3 соблюдает, man bash — «игнорируется интерактивной»"
nx_cons go-race "bash -ni -c '@H@'"
nx_cons go-race 'bash -n -i heavy.sh'
nx_cons go-race "bash -i -n <<'EOF'
@H@
EOF"
nx_cons go-race "bash -i +i -c 'set -n; @H@'"
echo "   близнецы без -i — пропуск (значение опции с буквой i — не -i)"
nx пропуск   "bash -x -c 'set -n; @H@'"
nx пропуск   "bash -o pipefail -c 'set -n; @H@'"
nx пропуск   "bash <<'EOF'
set -n
@H@
EOF"
echo "   живые формы исполнителей (журналы сессий, 2026-10)"
nx ci-local  "/bin/bash -c '. tmp/land-3261.sh' ; echo syn=\$?"
nx пропуск   "/bin/bash -c 'set -n; . tmp/land-3261.sh' ; echo syn=\$?"
nx пропуск   'bash -n tmp/land-3261.sh; echo rc=$?'
nx пропуск   'for f in heavy.sh tmp/land-3261.sh; do bash -n "$f" || echo "SYNTAX $f"; done'
# Мутанты: порча стража по одному решению — каждую обязан поймать свой случай выше.
# Порча — точная замена фрагмента копии guard.py (фрагмент ровно один, иначе мутант
# устарел и не построен); убита, если страж с порчей вышел не тем кодом, что без неё.
nx_mut() {
    local id="$1" form="$2" want="$3" md="$WORK/mut-$1" rc
    mkdir -p "$md/heavy-guard"; cp "$HOOK" "$md/heavy-guard.sh"
    if ! python3 -c '
import sys
s = open(sys.argv[1], encoding="utf-8").read()
if s.count(sys.argv[3]) != 1:
    sys.exit(1)
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))' "$GUARD" "$md/heavy-guard/guard.py" "$4" "$5"; then
        assert "построен" "не построен" "мутант $id: фрагмент порчи в guard.py не единствен"; return
    fi
    rc="$(HOOK_RUN="$md/heavy-guard.sh" run "${form//@H@/go test -race ./...}" "$NX")"
    assert "убит" "$([ "$rc" != "$want" ] && echo убит || echo выжил)" "мутант $id ($(printf '%s' "$form" | tr '\n' ' ')): с порчей код $rc, без неё $want"
}
nx_mut n-past-script 'bash heavy.sh -n' 2 \
    $'            k += 1 + j\n            continue\n        break\n    return on' \
    $'            k += 1 + j\n            continue\n        k += 1\n    return on'
nx_mut plus-ignored 'bash -n +n heavy.sh' 2 \
    $'                if ch == "n":\n                    on = a[0] == "-"' \
    $'                if ch == "n":\n                    on = True'
nx_mut set-anywhere "bash -c '@H@; set -n'" 2 'm = SET_HEAD.match(t)' 'm = SET_HEAD.search(t)'
nx_mut set-pipe "bash -c 'set -n | cat; @H@'" 2 '(;|&&|\|\||\n|$)")' '(;|&&|\|\||\||&|\n|$)")'
nx_mut cluster-exact 'bash -nx heavy.sh' 0 '                if ch == "n":' '                if ch == "n" and a in ("-n", "+n"):'
nx_mut heredoc-blind "bash -n <<'EOF'
@H@
EOF" 0 '                if shell_interactive(argv[1:]) or not (shell_noexec(argv[1:]) or set_noexec_first(body)):' '                if True:'
nx_mut interactive-ignored "bash -ic 'set -n; @H@'" 2 \
    $'        if a[0] == "-" and "i" in a[1:]:\n            return True' \
    $'        if False:\n            return True'
nx_mut interactive-argv "bash -i -c 'set -o noexec; @H@'" 2 \
    '        noexec = not shell_interactive(args)' '        noexec = True'
nx_mut interactive-heredoc "bash -i <<'EOF'
set -n
@H@
EOF" 2 'if shell_interactive(argv[1:]) or not (' 'if not ('
nx_mut interactive-flag-n "bash -ni -c '@H@'" 2 \
    '        if noexec and shell_noexec(args):' '        if shell_noexec(args):'

echo "── git push: тяжёл там, где git исполнит хук отправки (признак — scripts/push-hook.sh, ws#1335)"
# Настоящие репозитории git: признак спрашивает git (общий каталог, core.hooksPath, корень дерева).
# Клон без хука — лёгкая отправка (решение диспетчера 2026-10-22, вариант б); у каждого вида хука
# — отказ и законный близнец, отличный одним фактом.
gx() { git -c init.defaultBranch=main -c commit.gpgsign=false -c user.name=p -c user.email=p@p.invalid "$@" >/dev/null 2>&1; }
for r in none tree inst noexec hpath; do gx init -q "$WORK/push-$r"; git -C "$WORK/push-$r" config --unset core.hooksPath 2>/dev/null; done
PN="$WORK/push-none"
mkdir -p "$WORK/push-tree/scripts/hooks"; echo 'echo хук без наборов' > "$WORK/push-tree/scripts/hooks/pre-push"
printf '#!/bin/sh\nexit 0\n' > "$WORK/push-inst/.git/hooks/pre-push"; chmod +x "$WORK/push-inst/.git/hooks/pre-push"
printf '#!/bin/sh\nexit 0\n' > "$WORK/push-noexec/.git/hooks/pre-push"; chmod -x "$WORK/push-noexec/.git/hooks/pre-push"
mkdir -p "$WORK/hookdir"; printf '#!/bin/sh\nexit 0\n' > "$WORK/hookdir/pre-push"; chmod +x "$WORK/hookdir/pre-push"
git -C "$WORK/push-hpath" config core.hooksPath "$WORK/hookdir"
gx -C "$PN" commit -q --allow-empty -m x; gx -C "$PN" worktree add -q "$WORK/push-none-wt"
gx -C "$WORK/push-inst" commit -q --allow-empty -m x; gx -C "$WORK/push-inst" worktree add -q "$WORK/push-inst-wt"
mkdir -p "$WORK/push-plain"
assert "1" "$(cd "$PN" && bash "$ROOT/scripts/push-hook.sh" >/dev/null; echo $?)" "предпосылка: в синтетическом клоне без хука push-hook.sh отвечает «нет хука» (только образцы git init)"
passes 'git push origin HEAD:refs/heads/x' "$PN"
passes "cd $PN && git push origin HEAD"
passes "git -C $PN push origin HEAD"
passes "git -C $WORK/push-none-wt push origin HEAD"
passes "git -c user.name=x push origin HEAD" "$PN"
passes 'git push origin HEAD' "$WORK/push-noexec"
passes "git --git-dir=$PN/.git push origin HEAD" "$WORK/push-inst"
passes "git --git-dir $PN/.git --work-tree $PN push origin HEAD" "$WORK/push-inst"
passes 'git push origin HEAD' "$WORK/push-plain"
denies ci-local 'git push origin HEAD:refs/heads/x' "$WORK/push-tree"
denies ci-local 'git push origin HEAD' "$WORK/push-inst"
denies ci-local "git -C $WORK/push-inst-wt push origin HEAD"
denies ci-local 'git push origin HEAD' "$WORK/push-hpath"
denies ci-local "git -c core.hooksPath=$WORK/hookdir push origin HEAD" "$PN"
denies ci-local "git -c Core.HooksPath=$WORK/hookdir push origin HEAD" "$PN"
denies ci-local "git --git-dir=$WORK/push-inst/.git push origin HEAD" "$PN"
denies ci-local "git -C $WORK/push-inst push" "$PN"
passes "cd $WORK/push-inst && git push --no-verify"
passes 'git -C "$X" push origin x' "$WORK/push-inst"
# Признака нет (scripts/push-hook.sh снят) — отправка тяжела: молча лёгкой она не становится.
md="$WORK/mut-nohook"; mkdir -p "$md/.claude/hooks/heavy-guard"; cp "$HOOK" "$md/.claude/hooks/heavy-guard.sh"; cp "$GUARD" "$md/.claude/hooks/heavy-guard/guard.py"
assert "2" "$(HOOK_RUN="$md/.claude/hooks/heavy-guard.sh" run 'git push origin HEAD' "$PN")" "без scripts/push-hook.sh отправка клона без хука — отказ ci-local (признак не судим — не «лёгкая»)"
# Мутанты признака: снятая ветвь — её отказ становится пропуском (каждая ветвь читается).
ph_mut() {
    local id="$1" cwd="$2" form="$3" md="$WORK/mut-ph-$1" rc
    mkdir -p "$md/.claude/hooks/heavy-guard" "$md/scripts"; cp "$HOOK" "$md/.claude/hooks/heavy-guard.sh"; cp "$GUARD" "$md/.claude/hooks/heavy-guard/guard.py"
    if ! python3 -c '
import sys
s = open(sys.argv[1], encoding="utf-8").read()
if s.count(sys.argv[3]) != 1:
    sys.exit(1)
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))' "$ROOT/scripts/push-hook.sh" "$md/scripts/push-hook.sh" "$4" "$5"; then
        assert "построен" "не построен" "мутант признака $id: фрагмент порчи в push-hook.sh не единствен"; return
    fi
    rc="$(HOOK_RUN="$md/.claude/hooks/heavy-guard.sh" run "$form" "$cwd")"
    assert "убит" "$([ "$rc" != 2 ] && echo убит || echo выжил)" "мутант признака $id ($form): с порчей код $rc, без неё 2"
}
ph_mut hookspath "$WORK/push-hpath" 'git push origin HEAD' '[ -n "$hp" ] || hp="$hp_cli"
if [ -n "$hp" ]; then' '[ -n "$hp" ] || hp="$hp_cli"
if false; then'
ph_mut hookspath-cli "$PN" "git -c core.hooksPath=$WORK/hookdir push origin HEAD" '[ -n "$hp" ] || hp="$hp_cli"' ':'
ph_mut installed "$WORK/push-inst" 'git push origin HEAD' 'if [ -x "$gd/hooks/pre-push" ]' 'if false'
ph_mut tree "$WORK/push-tree" 'git push origin HEAD' 'if [ -n "$top" ] && [ -e "$top/scripts/hooks/pre-push" ]; then' 'if false; then'
ph_mut git-dir "$PN" "git --git-dir=$WORK/push-inst/.git push origin HEAD" '--git-dir=*|--work-tree=*) opts+=("$1"); shift ;;' '--git-dir=*|--work-tree=*) shift ;;'

echo "── наборы и пробы воркспейса — класс suite: голый запуск отказан, слот и чтение — пропуск (ws#1291)"
# Синтетический воркспейс: корень с scripts/heavy-slot.sh, набор с прогонщиком, доказательством
# и проверкой, мутанты, отдельная проба и проба хука. Близнец места — то же дерево без
# scripts/heavy-slot.sh (клон продукта): имя то же, класса нет.
SX="$WORK/sx"; PX="$WORK/px"
for d in "$SX" "$PX"; do
    mkdir -p "$d/.git" "$d/scripts/tg-gate" "$d/scripts/ls" "$d/.claude/hooks/h"
    for f in scripts/tg-gate/run-all.sh scripts/tg-gate/inject.sh scripts/tg-gate/inject-2-x.sh \
             scripts/tg-gate/check-01-x.sh scripts/ls/mutants.py scripts/ls/explore-mutants.py \
             scripts/x-inject.sh .claude/hooks/h/prove.sh; do echo 'true' > "$d/$f"; done
done
: > "$SX/scripts/heavy-slot.sh"
denies suite 'bash scripts/tg-gate/run-all.sh' "$SX"
denies suite './scripts/tg-gate/run-all.sh' "$SX"
denies suite 'bash scripts/tg-gate/inject.sh' "$SX"
denies suite 'bash scripts/tg-gate/inject-2-x.sh' "$SX"
denies suite 'timeout 600 bash scripts/tg-gate/inject.sh > inj.log 2>&1; echo rc=$?' "$SX"
denies suite 'cd scripts/tg-gate && bash inject.sh' "$SX"
denies suite "bash $SX/scripts/x-inject.sh" "$WORK"
denies suite 'python3 scripts/ls/mutants.py' "$SX"
denies suite 'python3 -u -W ignore scripts/ls/mutants.py -j 4' "$SX"
denies suite 'python3 scripts/ls/explore-mutants.py' "$SX"
denies suite 'bash .claude/hooks/h/prove.sh' "$SX"
echo 'go test -race ./...' > "$SX/scripts/tg-gate/run-all.sh"
denies go-race 'bash scripts/tg-gate/run-all.sh' "$SX"
echo 'true' > "$SX/scripts/tg-gate/run-all.sh"
passes 'bash scripts/tg-gate/check-01-x.sh' "$SX"
passes 'cat scripts/tg-gate/run-all.sh' "$SX"
passes 'bash -n scripts/tg-gate/inject.sh' "$SX"
passes 'python3 -m py_compile scripts/ls/mutants.py' "$SX"
passes 'python3 -c "print(1)" scripts/ls/mutants.py' "$SX"
passes 'grep -n run-all.sh scripts/tg-gate/inject.sh' "$SX"
passes "/ws/scripts/heavy-slot.sh suite -- bash scripts/tg-gate/inject.sh" "$SX"
passes "bash /ws/scripts/heavy-slot.sh suite -- python3 scripts/ls/mutants.py" "$SX"
passes 'bash scripts/tg-gate/run-all.sh' "$PX"
passes 'python3 scripts/ls/mutants.py' "$PX"
# Мутанты: порча по одному решению — каждую обязан поймать свой случай выше; место вызова — $6
# (по умолчанию $SX): порчу признака воркспейса ловит лишь близнец места $PX.
sx_mut() {
    local id="$1" form="$2" want="$3" at="${6:-$SX}" md="$WORK/smut-$1" rc
    mkdir -p "$md/heavy-guard"; cp "$HOOK" "$md/heavy-guard.sh"
    if ! python3 -c '
import sys
s = open(sys.argv[1], encoding="utf-8").read()
if s.count(sys.argv[3]) != 1:
    sys.exit(1)
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))' "$GUARD" "$md/heavy-guard/guard.py" "$4" "$5"; then
        assert "построен" "не построен" "мутант $id: фрагмент порчи в guard.py не единствен"; return
    fi
    rc="$(HOOK_RUN="$md/heavy-guard.sh" run "$form" "$at")"
    assert "убит" "$([ "$rc" != "$want" ] && echo убит || echo выжил)" "мутант $id ($form в ${at##*/}): с порчей код $rc, без неё $want"
}
sx_mut python-blind 'python3 scripts/ls/mutants.py' 2 \
    'return "suite" if script and suite_member(resolve(script, cwd, alt)) else None' 'return None'
sx_mut no-marker 'bash scripts/tg-gate/run-all.sh' 0 \
    'if top and os.path.isfile(os.path.join(top, "scripts", "heavy-slot.sh")):' 'if top:' "$PX"
sx_mut shell-blind 'bash scripts/tg-gate/inject.sh' 2 \
    'return best(got | ({"suite"} if suite_member(resolve(script, cwd, alt)) else set()))' 'return best(got)'
sx_mut path-blind './scripts/tg-gate/run-all.sh' 2 \
    'c = best(got | ({"suite"} if suite_member(resolve(argv[0], cwd, alt)) else set()))' 'c = best(got)'
# Перепись дерева воркспейса этой копии: каждый набор suites.py (прогонщик и доказательство) и
# каждый шаг конвейера ci.yaml, чьё имя — набор или проба, страж обязан назвать suite. Шаги без
# такого имени печатаются поимённо — «не набор» названо, а не умолчано.
if [ -f "$ROOT/scripts/lib/suites.py" ] && [ -f "$ROOT/.github/workflows/ci.yaml" ]; then
    ns=0; nok=0
    while IFS= read -r s; do
        [ -n "$s" ] || continue
        for f in run-all.sh inject.sh; do
            [ -f "$ROOT/scripts/$s/$f" ] || continue
            ns=$((ns + 1)); c="$(python3 "$GUARD" --classify "bash scripts/$s/$f" "$ROOT" < /dev/null)"
            [ "$c" = suite ] && nok=$((nok + 1)) || echo "  [FAIL] набор suites.py: scripts/$s/$f — класс «$c», ждали suite" >&2
        done
    done < <(python3 "$ROOT/scripts/lib/suites.py" suites "$ROOT")
    assert "да" "$([ "$ns" -gt 0 ] && [ "$ns" = "$nok" ] && echo да || echo нет)" "наборы suites.py: файлов $ns, класс suite у $nok (ноль — перепись ослепла)"
    nc=0; ncs=0; other=()
    while IFS= read -r f; do
        [ -f "$ROOT/$f" ] || continue
        nc=$((nc + 1)); c="$(python3 "$GUARD" --classify "bash $f" "$ROOT" < /dev/null)"
        # класс тяжелее suite — скрипт сам собирает или тестирует (ws#1301: remote-heavy/inject.sh
        # зовёт go build) — назван, не пропущен; пропуск — класс «-»
        if [ "$c" = suite ]; then ncs=$((ncs + 1)); elif [ "$c" = - ]; then other+=("$f"); else echo "  [INFO] шаг ci.yaml $f — класс «$c» тяжелее suite: скрипт сам собирает или тестирует"; fi
    done < <(grep -E '^[[:space:]]+run:' "$ROOT/.github/workflows/ci.yaml" | grep -oE '(^|[ =])scripts/[A-Za-z0-9_./-]+\.(sh|py)' | sed 's/^[ =]//' | sort -u)
    bad="$(printf '%s\n' "${other[@]}" | grep -E '(run-all|inject|prove|mutants|run-suites|hook-proofs)[^/]*$' || true)"
    assert "" "$bad" "шаги ci.yaml с именем набора или пробы — все тяжёлые, ни один не пропущен (шагов $nc, suite $ncs)"
    echo "  [CENSUS] ci.yaml: шагов-скриптов $nc, suite $ncs; не набор: ${other[*]:-—}"
    assert "да" "$([ "$ncs" -gt 0 ] && echo да || echo нет)" "перепись ci.yaml нашла наборы (ноль — разбор ослеп)"
else
    echo "  [VOID] нет scripts/lib/suites.py или .github/workflows/ci.yaml в $ROOT — перепись наборов не выполнялась" >&2
    void=$((void + 1))
fi

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
printf '#!/usr/bin/env bash\ndocker run --rm alpine true\n' > "$M/sh/box.sh"
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
denies docker  'bash sh/box.sh' "$M"
passes         'bash sh/light.sh' "$M"
passes         './sh/tool' "$M"
denies stand   'for s in sh/h*.sh; do bash "$s"; done' "$M"
passes         'for s in sh/l*.sh; do bash "$s"; done' "$M"
denies go-race 'export GOFLAGS=-race; bash sh/unit.sh' "$M"
denies go-unit 'export GOFLAGS=-count=1; bash sh/unit.sh' "$M"  # любой go test (ws#1301)
denies go-race 'export GOFLAGS=-race; make plain' "$M"
denies go-race 'make plain GOFLAGS=-race' "$M"
denies go-unit 'make plain' "$M"  # любой go test (ws#1301)
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
    denies newman      'bash deploy/scripts/newman-parallel.sh vpc' "$PRODUCT"
    denies newman      './deploy/scripts/newman-e2e.sh vpc' "$PRODUCT"
    # Предпосылка: скрипт, названный пробой продукта, есть в его дереве. Снятый
    # скрипт страж молча пропускает — без этой строки находка говорит «получено 0»,
    # а не «предмета нет» (так было при снятии прогона соответствия OIDC).
    subjects="$(sed -n "s/^    denies [a-z-]* *'\(bash \|\.\/\)\([^ ']*\.sh\).*\"\$PRODUCT\"\$/\2/p" "${BASH_SOURCE[0]}")"
    assert "да" "$([ -n "$subjects" ] && echo да || echo нет)" "скриптов-предметов продукта найдено $(printf '%s' "$subjects" | grep -c .) (ноль — разбор ослеп)"
    while IFS= read -r sc; do
        [ -n "$sc" ] || continue
        have="$(git -C "$PRODUCT" ls-files --error-unmatch -- "$sc" >/dev/null 2>&1 && echo да || echo нет)"
        assert "да" "$have" "скрипт-предмет «$sc» есть в дереве продукта (нет — снять утверждение вместе с ним)"
    done <<< "$subjects"
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
