#!/usr/bin/env bash
# skills-gate #08 — шаги `shellcheck …` конвейера воркспейса проходят на дереве так, как их
# исполняет ранер: той же строкой, в том же каталоге, с тем же окружением и версией (ws#1402).
#
# ПРИЗНАК. PR #1407 @9e4f3d4f0: хук отправки зелёный, задание bats-and-shellcheck красное на
# «shellcheck docs-gate (strict)» (SC2016). Хук гоняет лишь `scripts/*/run-all.sh`, а
# шаги анализатора жили только в .github/workflows/ci.yaml — цель конвейера хук не покрывал вовсе.
# Набор skills-gate хук исполняет целиком: красный здесь — отказ отправки. В конвейере набор
# идёт в задании skills-gate (запас по времени — у него; у tooling-gate его нет).
#
# ПЕРЕЧЕНЬ ВЫВОДИТСЯ: ci.yaml разбирается в JSON (`yq -o=json`), шаги — `jq` (без построчного
# `@tsv`: многострочный `run: |` и кавычки внутри строки доходят до исполнения целыми). Шаг
# судится, если `run` (без ведущих пробелов) начат словом `shellcheck`; исполняется ВСЯ строка
# `run` файлом через `bash -e` (так её исполняет ранер), в каталоге: `working-directory` шага,
# иначе `defaults.run.working-directory` задания, иначе workflow, иначе корень. Окружение —
# `env` workflow, поверх `env` задания, поверх `env` шага (SHELLCHECK_OPTS и прочее). Шаг с
# `continue-on-error: true` при красном задание не роняет — печатается строкой, не находка.
#
# ГРАНИЦА (названа, не судится): шаг, где `shellcheck` стоит не первым словом (`$SC …`,
# `cd x && shellcheck …`); значение `env` или каталог с выражением `${{ … }}` — такой шаг
# объявляется «не судим» строкой переписи, вердикта о нём нет; `if:` шага не вычисляется.
#
# ВЕРСИЯ — `env.SHELLCHECK_VERSION` того же ci.yaml; иная у установленного анализатора — VOID:
# вердикт другой версии не вердикт конвейера. VOID хук отправки НЕ останавливает (третья
# категория, scripts/hooks/pre-push, ws#458); в отправке слотом `ci-local` анализатор — пина
# дерева (scripts/remote-heavy/run.sh), и там исход судим.
#
# ИСХОДЫ: 0 — судимые шаги прошли, число напечатано; 1 — красный шаг (не continue-on-error):
# имя, каталог, команда, первые строки вывода; 2 — [VOID]: ci.yaml нет, судимых шагов ноль,
# нет yq, jq или shellcheck, версия не та. Доказательство — inject.sh рядом.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

NAME="08-ci-shellcheck-steps"
WS="$(skills_gate_workspace_root)" || { skills_gate_void "$NAME" "корень судимого дерева не выведен"; exit 2; }
WF="$WS/.github/workflows/ci.yaml"

[ -f "$WF" ] || { skills_gate_void "$NAME" "конвейера нет: $WF — сверять не с чем"; exit 2; }
for t in yq jq shellcheck; do
    command -v "$t" > /dev/null 2>&1 || { skills_gate_void "$NAME" "нет $t — шаги конвейера не разобрать и не исполнить"; exit 2; }
done
TMP="$(mktemp -d)"
# shellcheck disable=SC2154  # _rc присваивает сама ловушка первой командой
trap '_rc=$?; rm -rf "$TMP" 2>/dev/null || rm -rf "$TMP" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $TMP не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT
yq -o=json '.' "$WF" > "$TMP/wf.json" 2> "$TMP/yq.err" || { skills_gate_void "$NAME" "ci.yaml не разобран: $(head -c 200 "$TMP/yq.err")"; exit 2; }
pin="$(jq -r '.env.SHELLCHECK_VERSION // ""' "$TMP/wf.json")"
have="$(shellcheck --version 2> /dev/null | sed -n 's/^version: //p')"
[ -n "$pin" ] || { skills_gate_void "$NAME" "в ci.yaml нет env.SHELLCHECK_VERSION — версия конвейера не известна"; exit 2; }
[ "$have" = "$pin" ] || { skills_gate_void "$NAME" "shellcheck ${have:-?} при пине конвейера $pin — вердикт другой версии не вердикт конвейера"; exit 2; }

# Шаг — объект JSON строкой: имя, каталог, run, слитое окружение, continue-on-error.
jq -c '
  (.env // {}) as $wenv | (.defaults.run["working-directory"] // ".") as $wdir
  | (.jobs // {}) | to_entries[] | .key as $job | .value as $j
  | ($j.defaults.run["working-directory"] // $wdir) as $jdir
  | ($j.steps // [])[]
  | select((.run // "") | test("^\\s*shellcheck(\\s|$)"))
  | {job: $job, name: (.name // "—"), dir: (.["working-directory"] // $jdir), run: .run,
     env: ($wenv + ($j.env // {}) + (.env // {})), coe: ((.["continue-on-error"] // false) == true)}
' "$TMP/wf.json" > "$TMP/steps.jsonl" 2> "$TMP/jq.err" || { skills_gate_void "$NAME" "шаги не выведены: $(head -c 200 "$TMP/jq.err")"; exit 2; }

n=0 ok=0 red=0 coe=0 unjudged=0
while IFS= read -r step; do
    n=$((n + 1))
    name="$(jq -r .name <<< "$step")"; dir="$(jq -r .dir <<< "$step")"
    if jq -e '[.dir, (.env | to_entries[] | .value | tostring)] | any(test("\\$\\{\\{"))' <<< "$step" > /dev/null; then
        echo "  не судим: шаг «$name» — выражение \${{ … }} в каталоге или env"; unjudged=$((unjudged + 1)); continue
    fi
    if [ ! -d "$WS/$dir" ]; then
        skills_gate_fail "$NAME" "шаг «$name»: каталога $dir нет"; red=$((red + 1)); continue
    fi
    jq -r .run <<< "$step" > "$TMP/step.sh"
    mapfile -t envs < <(jq -r '.env | to_entries[] | "\(.key)=\(.value | tostring)"' <<< "$step")
    if out="$(cd "$WS/$dir" && env "${envs[@]}" bash -e "$TMP/step.sh" 2>&1)"; then
        ok=$((ok + 1))
    elif jq -e .coe <<< "$step" > /dev/null; then
        echo "  красный при continue-on-error: шаг «$name» — задание он не роняет"; coe=$((coe + 1))
    else
        skills_gate_fail "$NAME" "шаг конвейера «$name» красный ($dir): $(head -n1 "$TMP/step.sh")"
        printf '%s\n' "$out" | head -n 12 | sed 's/^/         /' >&2
        red=$((red + 1))
    fi
done < "$TMP/steps.jsonl"

echo "[CENSUS] $NAME: шагов shellcheck в ci.yaml $n, прошло $ok, красных $red, красных при continue-on-error $coe, не судимо $unjudged; shellcheck $have (пин $pin)"
if [ $((n - unjudged)) -le 0 ]; then
    skills_gate_void "$NAME" "судимых шагов «shellcheck …» ноль — паритет судить не с чем"; exit 2
fi
[ "$red" -eq 0 ] || exit 1
skills_gate_pass "$NAME" "шаги shellcheck конвейера проходят на дереве так, как их исполняет ранер"
