#!/usr/bin/env bash
# inject.sh — доказательство способности check-01 упасть И СМОЛЧАТЬ (ws#1099).
#
# Стволы СИНТЕТИЧЕСКИЕ: каждая ось меняет ОДИН факт против законного близнеца.
# Близнец каждой формы достижимости молчит, та же форма без вызова Go краснит —
# так доказано, что распознаватель читает форму, а не угадывает исход:
#
#   A  `setup-go` в задании `helm` с одним `helm lint`        → находка с координатой
#   A' тот же шаг плюс `go test ./deploy/`                    → молчание
#   B  `--dir deploy -- make dev-up` → `$(MAKE)` подцели с `go build`
#      после строки-комментария и продолжений                 → молчание
#   B' та же цепочка, подцель без Go                          → находка
#   C  скрипт `bash …/s.sh` с `go vet`                        → молчание
#   C' скрипт, где `; go` лишь в тексте `echo` и в хвостовом комментарии → находка (код, не текст)
#   D  python с `subprocess.run(["go", "list"])`              → молчание
#   D' python, где `go list` лишь в строке документации        → находка
#   E  `make ${{ matrix.stack }}-up`, у одного значения цель с Go → молчание
#   E' ни у одного значения Go нет                            → находка
#   K  Go лишь в рецепте ПРЕДПОСЫЛКИ цели make                → молчание
#   K' предпосылка без Go                                     → находка
#   F  составное действие `./.github/actions/x` несёт `setup-go`, Go нет → находка
#   F' то же действие вызывает `go version`                   → молчание
#   G  ствол с находкой, рабочая копия правлена до молчания   → находка: судится ствол
#   H  клона kaname нет                                       → VOID (без предмета)
#   I  заданий с `setup-go` нет вовсе                         → VOID (предмет снят)
#   L  корень — копия полосы под `tmp/` без `project/`, клоны у канонической
#      копии (`scripts/lib/product_clone.py`)               → находка оси A, не VOID
#   L' тот же мир, у канонической копии клонов нет          → VOID
#   J  указатели вызывающего (`KACHO_HOME_*`, `KACHO_MONOREPO`) на приманку
#      не подменяют стволы мира                               → исход оси A
#   X  `exclude` снял значение матрицы, чья цель с Go         → находка
#   X' `exclude` снял другое значение                         → молчание
#   Y  `include` добавил значение с Go                        → молчание
#   Y' `include` лишь без Go; Y'' у сочетания ключа нет       → находка (перечень непуст)
#   M  `cd deploy` отдельной строкой run, там цель без Go     → находка
#   M' та же форма, цель с Go                                 → молчание
#   M2 `cd` склеенной строки рецепта (через комментарий)      → находка
#   M2' `cd` прежней строки рецепта не действует              → молчание
#   N  `go` лишь в теле here-document для `cat`               → находка
#   N' here-document, поданный `bash`                         → молчание
#   O  `; go` внутри кавычек                                  → находка
#   O' `bash -c` с тем же текстом; O'' `"$(go env …)"`        → молчание
#   P  `["go", …]` лишь в комментарии python                  → находка
#   P' тот же список в коде                                   → молчание
#   R  `Actions/Setup-Go` без Go                              → находка
#   R' `Actions/Setup-Go` и `go version`                      → молчание
#   S  Go лишь в шаге `if: false`                             → находка
#   S' условие-выражение; S'' задание `if: false` вне предмета → молчание
#   T  `node *.mjs` — находка, скрипт в перечне неразрешённого; T' прочитанный
#      скрипт без Go — находка без перечня
#   U  текст находки: число шагов run; «в Makefile не найдена» при Makefile,
#      «Makefile нет» без него
# shellcheck disable=SC2016,SC1003,SC2001  # одинарные кавычки — литералы мира (make, python), а не оболочка
set -uo pipefail

foreign() { compgen -e | command grep -E '^(KACHO_HOME_|KACHO_MONOREPO$|GIT_)'; }
for v in $(foreign); do unset "$v"; done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/proofs.sh
. "$here/../lib/proofs.sh"
proof_own_environment
box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/sandbox-git-home.sh
. "$here/../lib/sandbox-git-home.sh"
sandbox_git_home "$box/home" || { echo "инъекция ci-setup-gate: НЕ ВЫПОЛНИЛОСЬ — корневой подписи нет" >&2; exit 2; }

pass=0; fail=0
CHECK="$here/check-01-setup-go-job-calls-go.py"

# put <ствол> <путь> — содержимое со stdin.
put() { mkdir -p "$(dirname "$box/ws/project/$1/$2")"; cat > "$box/ws/project/$1/$2"; }

# seal <ствол> — коммит и ствол origin/main на нём.
seal() {
  local dir="$box/ws/project/$1"
  git -C "$dir" init -q
  git -C "$dir" add -A
  sandbox_git -C "$dir" commit -q -m inj
  git -C "$dir" update-ref refs/remotes/origin/main "$(git -C "$dir" rev-parse HEAD)"
}

# world — мир заново; kaname — законный сосед с заданием, которому Go нужен.
world() {
  rm -rf "$box/ws"
  mkdir -p "$box/ws"
  git -C "$box/ws" init -q
  put kaname .github/workflows/ci.yml <<'Y'
jobs:
  build:
    steps:
      - uses: actions/setup-go@0000000000000000000000000000000000000000
      - run: go build ./...
Y
  seal kaname
}

# job <тело шагов после setup-go> — процесс kacho с заданием helm.
job() {
  {
    printf 'jobs:\n  helm:\n'
    printf '    strategy:\n      matrix:\n        stack: [dev, prod]\n'
    printf '    steps:\n      - uses: actions/setup-go@0000000000000000000000000000000000000000\n'
    cat
  } | put kacho .github/workflows/ci.yaml
}

run() {
  local strip=() v
  for v in $(foreign); do strip+=(-u "$v"); done
  ( cd "$box" && env "${strip[@]}" CI_SETUP_GATE_ROOT="$box/ws" python3 "$CHECK" 2>&1 )
}

assert() { # <ось> <код> <подстрока> <вывод> <rc>
  local axis=$1 want=$2 needle=$3 out=$4 rc=$5
  if [[ "$rc" == "$want" ]] && grep -qF -- "$needle" <<<"$out"; then
    echo "  ok   $axis"; pass=$((pass+1))
  else
    echo "  FAIL $axis: код $rc (ожидался $want); искали «$needle»"
    sed 's/^/       | /' <<<"$out"; fail=$((fail+1))
  fi
}

FINDING="kacho:.github/workflows/ci.yaml:helm"

# ── A / A' ───────────────────────────────────────────────────────────────────
world; job <<'Y'
      - run: helm lint deploy/helm/umbrella
Y
seal kacho; out="$(run)"; rc=$?
assert "A  setup-go без Go — находка с координатой" 1 "$FINDING" "$out" "$rc"

world; job <<'Y'
      - run: helm lint deploy/helm/umbrella
      - run: go test -tags helmcharts ./deploy/ -count=1
Y
seal kacho; out="$(run)"; rc=$?
assert "A' тот же шаг плюс go test — молчание" 0 "достигают Go 2" "$out" "$rc"

# ── B / B' : make с каталогом, подцель через $(MAKE), комментарий в рецепте ──
for variant in go nogo; do
  world; job <<'Y'
      - run: .github/scripts/stand-up.sh --label "стенд" --dir deploy -- make dev-up CLUSTER_NAME="$C"
Y
  printf '#!/bin/sh\nexec "$@"\n' | put kacho .github/scripts/stand-up.sh
  if [ "$variant" = go ]; then body='	go build -o "$$work/p" ../tools/p; \'; else body='	kubectl apply -f x.yaml; \'; fi
  {
    printf 'dev-up: preflight\n'
    printf '\t@set -e; \\\n\t(cd kind && echo ok); \\\n\t# строка-комментарий с #-знаком; \\\n'
    printf '\t$(MAKE) --no-print-directory manifests STACK=dev \\\n\t  X=1\n'
    printf 'preflight:\n\t@true\n'
    printf 'manifests:\n\t@work=$$(mktemp -d); \\\n%s\n\techo готово\n' "$body"
  } | put kacho deploy/Makefile
  seal kacho; out="$(run)"; rc=$?
  if [ "$variant" = go ]; then
    assert "B  --dir + \$(MAKE) подцель с go build — молчание" 0 "достигают Go 2" "$out" "$rc"
  else
    assert "B' та же цепочка без Go — находка" 1 "$FINDING" "$out" "$rc"
  fi
done

# ── K / K' : Go лишь в ПРЕДПОСЫЛКЕ цели ───────────────────────────────────────
for variant in go nogo; do
  world; job <<'Y'
      - run: make stand
Y
  if [ "$variant" = go ]; then pre='	go build ./cmd/x'; else pre='	docker build .'; fi
  printf 'stand: images\n\tkind create cluster\nimages:\n%s\n' "$pre" | put kacho Makefile
  seal kacho; out="$(run)"; rc=$?
  if [ "$variant" = go ]; then
    assert "K  Go в предпосылке цели — молчание" 0 "достигают Go 2" "$out" "$rc"
  else
    assert "K' предпосылка без Go — находка" 1 "$FINDING" "$out" "$rc"
  fi
done

# ── C / C' : скрипт ──────────────────────────────────────────────────────────
world; job <<'Y'
      - run: bash .github/scripts/s.sh
Y
printf '#!/bin/sh\nset -e\ngo vet ./...\n' | put kacho .github/scripts/s.sh
seal kacho; out="$(run)"; rc=$?
assert "C  скрипт с go vet — молчание" 0 "достигают Go 2" "$out" "$rc"

world; job <<'Y'
      - run: bash .github/scripts/s.sh
Y
printf '#!/bin/sh\nhelm version  # затем; go test ./...\necho "шаг; go vet ./... руками"\n' | put kacho .github/scripts/s.sh
seal kacho; out="$(run)"; rc=$?
assert "C' go лишь в echo и комментарии — находка" 1 "$FINDING" "$out" "$rc"

# ── D / D' : python ──────────────────────────────────────────────────────────
world; job <<'Y'
      - run: python3 .github/scripts/a.py --self-test
Y
printf 'import subprocess\nsubprocess.run(["go", "list", "./..."], check=True)\n' | put kacho .github/scripts/a.py
seal kacho; out="$(run)"; rc=$?
assert "D  python зовёт [\"go\", …] — молчание" 0 "достигают Go 2" "$out" "$rc"

world; job <<'Y'
      - run: python3 .github/scripts/a.py --self-test
Y
printf '"""Сверяет вывод `go list` с планом."""\nimport json\nprint(json.dumps({}))\n' | put kacho .github/scripts/a.py
seal kacho; out="$(run)"; rc=$?
assert "D' go list лишь в строке документации — находка" 1 "$FINDING" "$out" "$rc"

# ── E / E' : цель из матрицы ─────────────────────────────────────────────────
for variant in go nogo; do
  world; job <<'Y'
      - run: make -C deploy ${{ matrix.stack }}-up
Y
  if [ "$variant" = go ]; then prod='	$(GO) run ./tools/seed'; else prod='	helm upgrade --install x y'; fi
  printf 'GO ?= go\ndev-up:\n\tkubectl get ns\nprod-up:\n%s\n' "$prod" | put kacho deploy/Makefile
  seal kacho; out="$(run)"; rc=$?
  if [ "$variant" = go ]; then
    assert "E  матрица: prod-up с \$(GO) — молчание" 0 "достигают Go 2" "$out" "$rc"
  else
    assert "E' матрица без Go ни в одной цели — находка" 1 "$FINDING" "$out" "$rc"
  fi
done

# ── F / F' : составное действие ──────────────────────────────────────────────
for variant in nogo go; do
  world
  {
    printf 'jobs:\n  helm:\n    steps:\n      - uses: ./.github/actions/x\n      - run: helm lint deploy\n'
  } | put kacho .github/workflows/ci.yaml
  {
    printf 'runs:\n  using: composite\n  steps:\n'
    printf '    - uses: actions/setup-go@0000000000000000000000000000000000000000\n'
    if [ "$variant" = go ]; then printf '    - run: go version\n      shell: bash\n'; fi
  } | put kacho .github/actions/x/action.yml
  seal kacho; out="$(run)"; rc=$?
  if [ "$variant" = go ]; then
    assert "F' составное действие зовёт go version — молчание" 0 "достигают Go 2" "$out" "$rc"
  else
    assert "F  setup-go внутри составного действия, Go нет — находка" 1 "$FINDING" "$out" "$rc"
  fi
done

# ── G : судится ствол, а не рабочая копия ────────────────────────────────────
world; job <<'Y'
      - run: helm lint deploy/helm/umbrella
Y
seal kacho
printf '      - run: go version\n' >> "$box/ws/project/kacho/.github/workflows/ci.yaml"
out="$(run)"; rc=$?
assert "G  правка рабочей копии ствол не подменяет" 1 "$FINDING" "$out" "$rc"

# ── H : клона kaname нет ─────────────────────────────────────────────────────
world; job <<'Y'
      - run: go build ./...
Y
seal kacho; rm -rf "$box/ws/project/kaname"
out="$(run)"; rc=$?
assert "H  клона нет — VOID" 2 "[VOID]" "$out" "$rc"

# ── I : предмета нет ─────────────────────────────────────────────────────────
world
printf 'jobs:\n  helm:\n    steps:\n      - run: helm lint deploy\n' | put kacho .github/workflows/ci.yaml
seal kacho
printf 'jobs:\n  build:\n    steps:\n      - run: echo нет\n' | put kaname .github/workflows/ci.yml
git -C "$box/ws/project/kaname" add -A; sandbox_git -C "$box/ws/project/kaname" commit -q -m inj2
git -C "$box/ws/project/kaname" update-ref refs/remotes/origin/main "$(git -C "$box/ws/project/kaname" rev-parse HEAD)"
out="$(run)"; rc=$?
assert "I  заданий с setup-go ноль — VOID" 2 "предмет снят" "$out" "$rc"

# ── J : указатели вызывающего не подменяют мир ───────────────────────────────
world; job <<'Y'
      - run: helm lint deploy/helm/umbrella
Y
seal kacho
decoy="$box/decoy"; mkdir -p "$decoy"; git -C "$decoy" init -q
out="$(KACHO_HOME_KACHO="$decoy" KACHO_HOME_KANAME="$decoy" KACHO_MONOREPO="$decoy" run)"; rc=$?
assert "J  KACHO_HOME_*/KACHO_MONOREPO вызывающего — исход оси A" 1 "$FINDING" "$out" "$rc"

# ── L / L' : копия полосы видит клоны канонической копии ────────────────────
world; job <<'Y'
      - run: helm lint deploy/helm/umbrella
Y
seal kacho
printf 'project/\ntmp/\n' > "$box/ws/.gitignore"
git -C "$box/ws" add -A && sandbox_git -C "$box/ws" commit -q -m canon
git -C "$box/ws" worktree add -q --detach "$box/ws/tmp/lane" 2>/dev/null
lane() {
  local strip=() v
  for v in $(foreign); do strip+=(-u "$v"); done
  ( cd "$box" && env "${strip[@]}" CI_SETUP_GATE_ROOT="$box/ws/tmp/lane" python3 "$CHECK" 2>&1 )
}
out="$(lane)"; rc=$?
assert "L  копия полосы — клоны канонической прочитаны, находка" 1 "$FINDING" "$out" "$rc"
mv "$box/ws/project" "$box/project-away"
out="$(lane)"; rc=$?
assert "L' у канонической клонов нет — VOID" 2 "[VOID]" "$out" "$rc"

# ── формы ложного молчания (возврат check-verifier по ws#1099) ──────────────
# Каждая форма — пара: дефект краснит, законный близнец той же формы молчит.

# refute <ось> <подстрока> <вывод> — подстроки в выводе быть НЕ должно.
refute() {
  local axis=$1 needle=$2 out=$3
  if grep -qF -- "$needle" <<<"$out"; then
    echo "  FAIL $axis: в выводе есть «$needle»"; sed 's/^/       | /' <<<"$out"; fail=$((fail+1))
  else
    echo "  ok   $axis"; pass=$((pass+1))
  fi
}

# matrix <тело strategy.matrix> <run> — задание helm со своей матрицей.
matrix() {
  {
    printf 'jobs:\n  helm:\n    strategy:\n      matrix:\n%s\n' "$1"
    printf '    steps:\n      - uses: actions/setup-go@0000000000000000000000000000000000000000\n'
    printf '      - run: %s\n' "$2"
  } | put kacho .github/workflows/ci.yaml
  printf 'dev-up:\n\tkubectl get ns\nprod-up:\n\t$(GO) run ./tools/seed\n' | put kacho deploy/Makefile
}

# ── X / X' : matrix.exclude снимает значение с Go ───────────────────────────
world; matrix '        stack: [dev, prod]
        exclude:
          - stack: prod' 'make -C deploy ${{ matrix.stack }}-up'
seal kacho; out="$(run)"; rc=$?
assert "X  exclude снял prod (цель с Go) — находка" 1 "$FINDING" "$out" "$rc"
world; matrix '        stack: [dev, prod]
        exclude:
          - stack: dev' 'make -C deploy ${{ matrix.stack }}-up'
seal kacho; out="$(run)"; rc=$?
assert "X' exclude снял dev, prod с Go остался — молчание" 0 "достигают Go 2" "$out" "$rc"

# ── Y / Y' / Y'' : matrix.include ───────────────────────────────────────────
world; matrix '        include:
          - stack: prod' 'make -C deploy ${{ matrix.stack }}-up'
seal kacho; out="$(run)"; rc=$?
assert "Y  include добавил prod (цель с Go) — молчание" 0 "достигают Go 2" "$out" "$rc"
world; matrix '        include:
          - stack: dev' 'make -C deploy ${{ matrix.stack }}-up'
seal kacho; out="$(run)"; rc=$?
assert "Y' include только dev — находка" 1 "$FINDING" "$out" "$rc"
world; matrix '        include:
          - other: x' 'make -C deploy ${{ matrix.stack }}-up'
seal kacho; out="$(run)"; rc=$?
assert "Y'' у сочетания include ключа нет — находка с непустым перечнем" 1 "у сочетания {'other': 'x'} ключа нет" "$out" "$rc"

# ── M / M' : cd отдельной строкой шага run ──────────────────────────────────
for variant in nogo go; do
  world; job <<'Y'
      - run: |
          cd deploy
          make build
Y
  printf 'build:\n\tgo build ./...\n' | put kacho Makefile
  if [ "$variant" = go ]; then r='	go vet ./...'; else r='	helm lint .'; fi
  printf 'build:\n%s\n' "$r" | put kacho deploy/Makefile
  seal kacho; out="$(run)"; rc=$?
  if [ "$variant" = go ]; then
    assert "M' cd отдельной строкой, у deploy/Makefile Go — молчание" 0 "достигают Go 2" "$out" "$rc"
  else
    assert "M  cd отдельной строкой ведёт в deploy/Makefile без Go — находка" 1 "$FINDING" "$out" "$rc"
  fi
done

# ── M2 / M2' : cd в рецепте — склеенная строка против отдельной ─────────────
for variant in joined split; do
  world; job <<'Y'
      - run: make -C deploy dev-up
Y
  if [ "$variant" = joined ]; then
    printf 'dev-up:\n\tcd kind && true; \\\n\t# комментарий; \\\n\t$(MAKE) manifests\nmanifests:\n\tgo build ./...\n' | put kacho deploy/Makefile
  else
    printf 'dev-up:\n\tcd kind && true\n\t$(MAKE) manifests\nmanifests:\n\tgo build ./...\n' | put kacho deploy/Makefile
  fi
  printf 'manifests:\n\thelm template .\n' | put kacho deploy/kind/Makefile
  seal kacho; out="$(run)"; rc=$?
  if [ "$variant" = joined ]; then
    assert "M2 cd той же строки рецепта (через комментарий) — kind/Makefile без Go, находка" 1 "$FINDING" "$out" "$rc"
  else
    assert "M2' cd прежней строки рецепта не действует — молчание" 0 "достигают Go 2" "$out" "$rc"
  fi
done

# ── N / N' : here-document ──────────────────────────────────────────────────
world; job <<'Y'
      - run: |
          cat > plan.txt <<'E'
          go test ./...
          E
Y
seal kacho; out="$(run)"; rc=$?
assert "N  go лишь в теле here-document для cat — находка" 1 "$FINDING" "$out" "$rc"
world; job <<'Y'
      - run: |
          bash <<'E'
          go test ./...
          E
Y
seal kacho; out="$(run)"; rc=$?
assert "N' here-document, поданный bash, — молчание" 0 "достигают Go 2" "$out" "$rc"

# ── O / O' / O'' : `; go` в кавычках ────────────────────────────────────────
world; job <<'Y'
      - run: helm lint "deploy; go test ./..."
Y
seal kacho; out="$(run)"; rc=$?
assert "O  ; go внутри кавычек — находка" 1 "$FINDING" "$out" "$rc"
world; job <<'Y'
      - run: bash -c "helm lint deploy; go test ./..."
Y
seal kacho; out="$(run)"; rc=$?
assert "O' bash -c с тем же текстом — молчание" 0 "достигают Go 2" "$out" "$rc"
world; job <<'Y'
      - run: echo "bin=$(go env GOPATH)/bin" >> "$GITHUB_PATH"
Y
seal kacho; out="$(run)"; rc=$?
assert "O'' подстановка \$(go …) в двойных кавычках — молчание" 0 "достигают Go 2" "$out" "$rc"

# ── P / P' : ["go", …] в комментарии python ─────────────────────────────────
for variant in comment code; do
  world; job <<'Y'
      - run: python3 .github/scripts/a.py
Y
  if [ "$variant" = comment ]; then
    printf 'import subprocess\n# subprocess.run(["go", "list"])\nprint(1)\n' | put kacho .github/scripts/a.py
  else
    printf 'import subprocess\nsubprocess.run(["go", "list"])\nprint(1)\n' | put kacho .github/scripts/a.py
  fi
  seal kacho; out="$(run)"; rc=$?
  if [ "$variant" = code ]; then
    assert "P' тот же список в коде — молчание" 0 "достигают Go 2" "$out" "$rc"
  else
    assert "P  [\"go\", …] лишь в комментарии python — находка" 1 "$FINDING" "$out" "$rc"
  fi
done

# ── R / R' : регистр в uses ─────────────────────────────────────────────────
for variant in nogo go; do
  world
  {
    printf 'jobs:\n  helm:\n    steps:\n      - uses: Actions/Setup-Go@0000000000000000000000000000000000000000\n'
    printf '      - run: helm lint deploy\n'
    if [ "$variant" = go ]; then printf '      - run: go version\n'; fi
  } | put kacho .github/workflows/ci.yaml
  seal kacho; out="$(run)"; rc=$?
  if [ "$variant" = go ]; then
    assert "R' Actions/Setup-Go и go version — молчание, задание в счёте" 0 "достигают Go 2" "$out" "$rc"
  else
    assert "R  Actions/Setup-Go без Go — находка" 1 "$FINDING" "$out" "$rc"
  fi
done

# ── S / S' / S'' : if: false ────────────────────────────────────────────────
world; job <<'Y'
      - run: helm lint deploy
      - if: false
        run: go test ./...
Y
seal kacho; out="$(run)"; rc=$?
assert "S  go лишь в шаге с if: false — находка" 1 "под if: false 1" "$out" "$rc"
world; job <<'Y'
      - run: helm lint deploy
      - if: github.event_name == 'push'
        run: go test ./...
Y
seal kacho; out="$(run)"; rc=$?
assert "S' условие-выражение исполнимо — молчание" 0 "достигают Go 2" "$out" "$rc"
world
printf 'jobs:\n  helm:\n    if: ${{ false }}\n    steps:\n      - uses: actions/setup-go@0000000000000000000000000000000000000000\n      - run: helm lint deploy\n' \
  | put kacho .github/workflows/ci.yaml
seal kacho; out="$(run)"; rc=$?
assert "S'' задание с if: false не предмет — молчание, счёт отдельно" 0 "заданий 2 (под if: false 1)" "$out" "$rc"

# ── T / T' : скрипт другого языка — в перечне неразрешённого ────────────────
world; job <<'Y'
      - run: node scripts/check.mjs
Y
printf 'import { execSync } from "node:child_process";\nexecSync("go vet ./...");\n' | put kacho scripts/check.mjs
seal kacho; out="$(run)"; rc=$?
assert "T  node .mjs — находка, скрипт назван в неразрешённом" 1 "скрипт scripts/check.mjs (язык не читается" "$out" "$rc"
world; job <<'Y'
      - run: bash scripts/check.sh
Y
printf 'helm lint .\n' | put kacho scripts/check.sh
seal kacho; out="$(run)"; rc=$?
assert "T' прочитанный скрипт без Go — находка" 1 "скриптов 1)" "$out" "$rc"
refute "T' прочитанный скрипт в неразрешённое не попадает" "неразрешено" "$out"

# ── U / U' / U'' : текст находки ────────────────────────────────────────────
world; job <<'Y'
      - run: helm lint deploy/helm/umbrella
Y
seal kacho; out="$(run)"; rc=$?
assert "U  находка называет число шагов run" 1 "шагов run осмотрено 1," "$out" "$rc"
world; job <<'Y'
      - run: make foo
Y
printf 'include rules.mk\n' | put kacho Makefile
seal kacho; out="$(run)"; rc=$?
assert "U' Makefile есть, цели нет — «в Makefile не найдена»" 1 "цель Makefile::foo (в Makefile не найдена)" "$out" "$rc"
refute "U' при существующем Makefile нет «Makefile нет»" "Makefile нет" "$out"
world; job <<'Y'
      - run: make foo
Y
seal kacho; out="$(run)"; rc=$?
assert "U'' Makefile нет — так и сказано" 1 "цель Makefile::foo (Makefile нет)" "$out" "$rc"

echo
total=$((pass + fail))
echo "инъекция ci-setup-gate: осей исполнено $total, сошлось $pass, не сошлось $fail"
if [ "$total" -eq 0 ]; then
  echo "инъекция ci-setup-gate: ОТКАЗ — не исполнено ни одной оси" >&2
  exit 1
fi
[ "$fail" -eq 0 ]
