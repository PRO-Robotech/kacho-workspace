#!/usr/bin/env bash
# check-29 — каждый шаг `shellcheck …` конвейера воркспейса проходит на дереве ТЕМИ ЖЕ
# командой, каталогом и версией анализатора, что в конвейере (ws#1402, паритет хука с CI).
#
# Признак: PR #1407 @9e4f3d4f0 — полный хук отправки отказов не дал, а
# задание bats-and-shellcheck краснеет на шаге «shellcheck docs-gate (strict)» (SC2016 в
# scripts/docs-gate/inject-12.sh), и шаги после него не исполняются. Корень — хук не покрывал
# цель конвейера вовсе: `scripts/hooks/pre-push` гоняет `scripts/*/run-all.sh`, а шаги
# `shellcheck -x` живут только в .github/workflows/ci.yaml (ws#1355 — открытый долг на тот же
# класс). Флаг и версия ни при чём: шага в хуке не было.
#
# ПЕРЕЧЕНЬ ВЫВОДИТСЯ, а не переписывается: шаги — из ci.yaml разбором (`yq`), каждый шаг с
# `run`, начатым словом `shellcheck`, в любом задании; каталог — его `working-directory`
# (по умолчанию корень); исполняется строка `run` как есть (`bash -c`, маски раскрывает
# оболочка, как у ранера). Версия — `env.SHELLCHECK_VERSION` того же ci.yaml; иная у
# установленного анализатора — суда нет (VOID): вердикт другой версии не вердикт конвейера.
# Хук отправки исполняет набор tooling-gate целиком, поэтому красный шаг конвейера здесь —
# отказ отправки (держит check-10: хук судит дерево вершины).
#
# ИСХОДЫ: 0 — все шаги прошли, число шагов напечатано; 1 — красный шаг: имя, команда, первые
# строки вывода; 2 — [VOID]: ci.yaml нет, шагов ноль, нет yq или shellcheck, версия не та.
# Доказательство — inject.sh рядом (проба check-29).
set -uo pipefail

# shellcheck source=scripts/tooling-gate/_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WS="$(tooling_gate_workspace_root)" || exit 2
NAME="check-29-ci-shellcheck-steps-pass-on-the-tree"
WF="$WS/.github/workflows/ci.yaml"

[ -f "$WF" ] || { tooling_gate_void "$NAME" "конвейера нет: $WF — сверять не с чем"; exit 2; }
command -v yq > /dev/null 2>&1 || { tooling_gate_void "$NAME" "нет yq — шаги конвейера не разобрать"; exit 2; }
command -v shellcheck > /dev/null 2>&1 || { tooling_gate_void "$NAME" "нет shellcheck — шаги конвейера не исполнить"; exit 2; }
pin="$(yq -r '.env.SHELLCHECK_VERSION // ""' "$WF" 2> /dev/null)"
have="$(shellcheck --version 2> /dev/null | sed -n 's/^version: //p')"
[ -n "$pin" ] || { tooling_gate_void "$NAME" "в $WF нет env.SHELLCHECK_VERSION — версия конвейера не известна"; exit 2; }
[ "$have" = "$pin" ] || { tooling_gate_void "$NAME" "shellcheck ${have:-?} при пине конвейера $pin — вердикт другой версии не вердикт конвейера"; exit 2; }

steps=()
while IFS= read -r row; do
    [ -n "$row" ] && steps+=("$row")
done < <(yq -r '.jobs[] | .steps[]? | select((.run // "") | test("^shellcheck[ \t]")) | [(.name // "—"), (.["working-directory"] // "."), (.run | sub("\n+$"; ""))] | @tsv' "$WF" 2> /dev/null)
if [ "${#steps[@]}" -eq 0 ]; then
    tooling_gate_void "$NAME" "в $WF шагов «shellcheck …» ноль — паритет судить не с чем"
    exit 2
fi

red=0 ok=0
for row in "${steps[@]}"; do
    IFS=$'\t' read -r name dir cmd <<< "$row"
    if [ ! -d "$WS/$dir" ]; then
        tooling_gate_fail "$NAME" "шаг «$name»: каталога $dir нет"
        red=$((red + 1)); continue
    fi
    if out="$(cd "$WS/$dir" && bash -c "$cmd" 2>&1)"; then
        ok=$((ok + 1))
    else
        tooling_gate_fail "$NAME" "шаг конвейера «$name» красный: ($dir) $cmd"
        printf '%s\n' "$out" | head -n 12 | sed 's/^/         /' >&2
        red=$((red + 1))
    fi
done

tooling_gate_census "$NAME: шагов shellcheck в ci.yaml ${#steps[@]}, прошло $ok, красных $red; shellcheck $have (пин $pin)"
[ "$red" -eq 0 ] || exit 1
tooling_gate_pass "$NAME" "все шаги shellcheck конвейера проходят на дереве той же версией"
