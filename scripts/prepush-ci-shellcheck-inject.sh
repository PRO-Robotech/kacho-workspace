#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# Инъекция паритета хука отправки с шагами shellcheck конвейера (scripts/hooks/prepush-ci-shellcheck.sh,
# ws#1335): хук исполняет шаги `shellcheck …` из ci.yaml дерева тем же текстом и в том же каталоге.
#
# Синтетика (дерево в TMPDIR, ci.yaml с пином установленного shellcheck):
#   · `# shellcheck source=…` без `source-path=SCRIPTDIR` — красный с SC1091 (дефект CI ws#1345);
#     близнец с `source-path=SCRIPTDIR` — зелёный;
#   · working-directory шага соблюдён; шаг с `|| true` (справочный) не исполняется;
#   · текст с метасимволом оболочки — отказ формы, команда не исполнена;
#   · шагов shellcheck ноль, пин не равен установленному — «не выполнилось» (2), не зелёное.
# Настоящее дерево: шаги конвейера этого дерева — код 0; шаг задания hook-proofs печатается сырым
# выводом с кодом.
# Коды: 0 — всё сошлось; 1 — нет; 2 — shellcheck не установлен.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
STEP="$HERE/hooks/prepush-ci-shellcheck.sh"
W="$(mktemp -d)"
# shellcheck disable=SC2154
trap '_rc=$?; rm -rf "$W" 2>/dev/null || rm -rf "$W" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $W не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT
pass=0; fail=0
assert() {
    if [ "$1" = "$2" ]; then echo "  [OK]   $3"; pass=$((pass + 1))
    else echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; fail=$((fail + 1)); fi
}
have="$(shellcheck --version 2>/dev/null | sed -n 's/^version: //p')"
[ -n "$have" ] || { echo "[VOID] shellcheck не установлен — ничего не исполнено" >&2; exit 2; }

# tree <имя> <пин> <шаги…> — дерево с ci.yaml; шаг — «каталог|текст».
tree() {
    local t="$W/$1" pin="$2" st wd run; shift 2
    mkdir -p "$t/.github/workflows" "$t/a" "$t/lib" "$t/sub"
    { printf 'env:\n  SHELLCHECK_VERSION: "%s"\njobs:\n  j:\n    runs-on: x\n    steps:\n' "$pin"
      for st in "$@"; do
          wd="${st%%|*}"; run="${st#*|}"
          printf '      - name: s\n'
          [ "$wd" = . ] || printf '        working-directory: %s\n' "$wd"
          printf '        run: %s\n' "$run"
      done; } > "$t/.github/workflows/ci.yaml"
    printf '#!/usr/bin/env bash\nl() { :; }\n' > "$t/lib/l.sh"
    printf '#!/usr/bin/env bash\necho sub\n' > "$t/sub/s.sh"
}
src() {  # src <дерево> <есть ли source-path> — скрипт, подключающий ../lib/l.sh
    { printf '#!/usr/bin/env bash\nD="$(dirname "$0")"\n'
      [ "$2" = да ] && printf '# shellcheck source-path=SCRIPTDIR\n'
      printf '# shellcheck source=../lib/l.sh\n. "$D/../lib/l.sh"\nl\n'; } > "$W/$1/a/x.sh"
}
run() { bash "$STEP" "$W/$1" > "$W/out" 2>&1; echo $?; }
has() { grep -qF -- "$1" "$W/out" && echo да || echo нет; }

echo "── синтетика: SC1091 без source-path — красный, с ним — зелёный"
tree red "$have" ".|shellcheck -x a/x.sh"; src red нет
assert "1 да" "$(run red) $(has SC1091)" "source= без source-path=SCRIPTDIR: код 1, отказ называет SC1091"
tree green "$have" ".|shellcheck -x a/x.sh"; src green да
assert "0 да" "$(run green) $(has 'шагов shellcheck конвейера 1, провалено 0')" "близнец с source-path=SCRIPTDIR: код 0, шаг исполнен"

echo "── каталог шага, справочные шаги, форма"
tree wd "$have" "sub|shellcheck -x -- *.sh"; src wd да
assert "0 да" "$(run wd) $(has '(sub) shellcheck -x -- *.sh')" "working-directory соблюдён: шаблон *.sh раскрыт в sub/"
tree info "$have" ".|shellcheck -x a/x.sh || true" ".|shellcheck -x a/../a/x.sh"; src info нет
assert "1 да" "$(run info) $(has 'шагов shellcheck конвейера 1, провалено 1')" "шаг с «|| true» не исполняется (справочный), прочий — исполняется"
tree meta "$have" ".|shellcheck a/x.sh; touch $W/meta-ran"; src meta да
assert "1 да нет" "$(run meta) $(has 'вне формы') $([ -e "$W/meta-ran" ] && echo да || echo нет)" "метасимвол оболочки: отказ формы, команда не исполнена"

echo "── не выполнилось — не зелёное"
tree none "$have" ".|echo нет shellcheck"; src none да
assert "2 да" "$(run none) $(has 'шагов shellcheck конвейера 0')" "шагов shellcheck ноль — код 2"
tree pin "0.0.1" ".|shellcheck -x a/x.sh"; src pin да
assert "2 да" "$(run pin) $(has 'вердикт был бы не паритетен')" "пин конвейера ≠ установленному — код 2"
mkdir -p "$W/bare"
assert "2" "$(run bare)" "дерево без ci.yaml — код 2"

echo "── настоящее дерево: шаги shellcheck его ci.yaml"
rc="$(bash "$STEP" "$ROOT" > "$W/out" 2>&1; echo $?)"; sed 's/^/  | /' "$W/out"
assert "0" "$rc" "шаги shellcheck конвейера дерева $(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null) — код 0"
echo "── шаг задания hook-proofs сырым выводом (shellcheck $have, из корня)"
# shellcheck disable=SC2046,SC2035
(cd "$ROOT" && shellcheck -x scripts/hook-proofs.sh .claude/hooks/*.sh .claude/hooks/*/prove.sh); rc=$?
echo "  shellcheck -x scripts/hook-proofs.sh .claude/hooks/*.sh .claude/hooks/*/prove.sh — код $rc"
assert "0" "$rc" "шаг hook-proofs «shellcheck hook scripts (strict)» — код 0"

trees=0; for t in "$W"/*/; do trees=$((trees + 1)); done
echo "[CENSUS] prepush-ci-shellcheck-inject: осмотрено деревьев $((trees + 1)) (синтетических $trees и настоящее); утверждений $((pass + fail)), сошлось $pass, разошлось $fail"
[ "$((pass + fail))" -gt 0 ] || { echo "[VOID] утверждений ноль — проба ничего не судила" >&2; exit 2; }
[ "$fail" -eq 0 ]
