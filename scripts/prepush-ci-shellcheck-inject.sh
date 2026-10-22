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
pass=0; fail=0; void=0
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

echo "── многострочный run: и пин задания либо шага (возврат приёмки ws#1335)"
# yml <имя> <текст ci.yaml> — дерево с готовым ci.yaml; a/x.sh без дефекта, a/bad.sh — SC2086.
yml() {
    mkdir -p "$W/$1/.github/workflows" "$W/$1/a" "$W/$1/m"
    printf '%s\n' "$2" > "$W/$1/.github/workflows/ci.yaml"
    printf '#!/usr/bin/env bash\necho ok\n' > "$W/$1/a/x.sh"
    printf '#!/usr/bin/env bash\necho $1\n' > "$W/$1/m/bad.sh"
}
yml multi "env:
  SHELLCHECK_VERSION: \"$have\"
jobs:
  j:
    runs-on: x
    steps:
      - name: многострочный
        run: |
          set -e
          shellcheck -x -- m/*.sh"
assert "1 да" "$(run multi) $(has 'многострочный')" "многострочный run: со shellcheck и SC2086 в предмете — код 1, шаг назван (исполнен либо отвергнут формой), не выброшен молча"
yml multi-ok "env:
  SHELLCHECK_VERSION: \"$have\"
jobs:
  j:
    runs-on: x
    steps:
      - name: многострочный чистый
        run: |
          set -euo pipefail
          shellcheck -x -- a/*.sh"
assert "0 да" "$(run multi-ok) $(has 'шагов shellcheck конвейера 1, провалено 0')" "многострочный run: из set -e и shellcheck над чистым предметом — исполнен, код 0"
yml installer "env:
  SHELLCHECK_VERSION: \"$have\"
jobs:
  j:
    runs-on: x
    steps:
      - name: установка
        run: |
          curl -sSfL https://example.invalid/x | tar -xJf - -C /tmp
          shellcheck --version | sed -n 's/^version: /установлен /p'
      - name: строгий
        run: shellcheck -x a/x.sh"
assert "0 да" "$(run installer) $(has 'шагов shellcheck конвейера 1, провалено 0')" "близнец: шаг-установщик (shellcheck --version | sed) — не шаг проверки, молчит; строгий — 1/0"
yml jobpin "jobs:
  j:
    runs-on: x
    env:
      SHELLCHECK_VERSION: \"0.0.1\"
    steps:
      - name: строгий
        run: shellcheck -x a/x.sh"
assert "2 да" "$(run jobpin) $(has 'не паритетен')" "пин в env задания ≠ установленному — код 2 (опыт 3c)"
yml steppin "env:
  SHELLCHECK_VERSION: \"$have\"
jobs:
  j:
    runs-on: x
    steps:
      - name: строгий
        env:
          SHELLCHECK_VERSION: \"0.0.1\"
        run: shellcheck -x a/x.sh"
assert "2" "$(run steppin)" "пин в env шага ≠ установленному — код 2"
yml jobpin-ok "env:
  SHELLCHECK_VERSION: \"0.0.1\"
jobs:
  j:
    runs-on: x
    env:
      SHELLCHECK_VERSION: \"$have\"
    steps:
      - name: строгий
        run: shellcheck -x a/x.sh"
assert "0" "$(run jobpin-ok)" "близнец: пин задания (сильнее верхнего) равен установленному — код 0"
yml nopin "jobs:
  j:
    runs-on: x
    steps:
      - name: строгий
        run: shellcheck -x a/x.sh"
assert "2 да" "$(run nopin) $(has 'пина нет')" "пина нет нигде — код 2: версия CI не названа, паритет не судим"

echo "── хук отправки: провязка исхода шага (песочница по образцу tooling-gate check-08)"
# shellcheck source=lib/sandbox-git-home.sh
. "$HERE/lib/sandbox-git-home.sh"
if ! sandbox_git_home "$W/ghome"; then
    echo "  [VOID] корневой подписи нет — песочница хука не построена" >&2; void=1
else
    # hook <имя> <pre-push> <ci.yaml> — код|итоговая строка хука на HEAD песочницы.
    hook() {
        local d="$W/hk-$1" out code
        mkdir -p "$d/scripts/hooks" "$d/scripts/stub" "$d/.github/workflows" "$d/m"
        cp "$2" "$d/scripts/hooks/pre-push"
        cp "$HERE/hooks/attribution-rule.sh" "$HERE/hooks/prepush-attribution.sh" "$HERE/hooks/prepush-added-files.sh" \
           "$HERE/hooks/branch-name-rule.sh" "$STEP" "$d/scripts/hooks/" 2>/dev/null
        printf '#!/usr/bin/env bash\necho "stub: 0"\nexit 0\n' > "$d/scripts/stub/run-all.sh"; chmod +x "$d/scripts/stub/run-all.sh"
        printf '%s\n' "$3" > "$d/.github/workflows/ci.yaml"
        printf '#!/usr/bin/env bash\necho $1\n' > "$d/m/bad.sh"; printf '#!/usr/bin/env bash\necho ok\n' > "$d/m/ok.sh"
        git -C "$d" init -q; git -C "$d" add -A -f > /dev/null 2>&1
        sandbox_git -C "$d" commit -q -m fixture > /dev/null 2>&1
        out="$(cd "$d" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u KACHO_MONOREPO -u KACHO_SKIP_PREPUSH \
            bash ./scripts/hooks/pre-push < /dev/null 2>&1)"; code=$?
        printf '%s\n' "$out" > "$W/hk-$1.out"
        printf '%s|%s\n' "$code" "$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -1)"
    }
    ciy() { printf 'env:\n  SHELLCHECK_VERSION: "%s"\njobs:\n  j:\n    runs-on: x\n    steps:\n      - name: строгий\n        run: shellcheck -x %s\n' "$1" "$2"; }
    PP="$HERE/hooks/pre-push"
    h_bad="$(hook bad "$PP" "$(ciy "$have" m/bad.sh)")"
    h_ok="$(hook ok "$PP" "$(ciy "$have" m/ok.sh)")"
    h_pin="$(hook pin "$PP" "$(ciy 0.0.1 m/ok.sh)")"
    assert "1 да" "${h_bad%%|*} $(grep -qF 'ci.yaml: шаги shellcheck' "$W/hk-bad.out" && grep -qF 'ОТКАЗ' "$W/hk-bad.out" && echo да || echo нет)" "хук: дефект SC2086 в шаге конвейера — код 1, отказ называет «ci.yaml: шаги shellcheck» (H1)"
    assert "0" "${h_ok%%|*}" "хук: предмет чистый — код 0 (H2)"
    assert "0 да" "${h_pin%%|*} $(grep -qF 'без предмета 1' "$W/hk-pin.out" && echo да || echo нет)" "хук: пин не совпал — код 0, «без предмета 1» (H3)"
    assert "да" "$([ "${h_ok#*|}" != "${h_pin#*|}" ] && [ "${h_ok#*|}" != "${h_bad#*|}" ] && echo да || echo нет)" "итоговая строка чистого отлична от строк дефекта и «без предмета»"
    # Мутант H5: провязка кода 1 в failed снята — хук обязан стать зелёным на дефекте (проба его ловит).
    python3 -c '
import sys
s = open(sys.argv[1], encoding="utf-8").read()
a = """            *) failed+=(\"$rref: $g\") ;;
        esac
    else"""
if s.count(a) != 1:
    sys.exit(1)
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(a, """            *) ;;
        esac
    else"""))' "$PP" "$W/pre-push-h5" && h5="$(hook h5 "$W/pre-push-h5" "$(ciy "$have" m/bad.sh)")" || h5="не построен|"
    assert "0" "${h5%%|*}" "мутант H5 (код 1 шага не доходит до failed): хук зелёный на дефекте — утверждение H1 его ловит"
fi

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
[ "$fail" -eq 0 ] || exit 1
[ "$void" -eq 0 ] || exit 2
[ "$fail" -eq 0 ]
