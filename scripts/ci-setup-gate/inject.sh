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
    printf '\t@set -e; \\\n\tcd kind && echo ok; \\\n\t# строка-комментарий с #-знаком; \\\n'
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

echo
total=$((pass + fail))
echo "инъекция ci-setup-gate: осей исполнено $total, сошлось $pass, не сошлось $fail"
if [ "$total" -eq 0 ]; then
  echo "инъекция ci-setup-gate: ОТКАЗ — не исполнено ни одной оси" >&2
  exit 1
fi
[ "$fail" -eq 0 ]
