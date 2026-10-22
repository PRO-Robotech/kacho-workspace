#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# prepush-ci-shellcheck.sh <дерево> — шаги shellcheck конвейера дерева, исполненные хуком отправки
# тем же текстом и в том же каталоге (паритет хука с CI, ws#1335).
#
# ПОЧЕМУ. Хук отправки гонит наборы scripts/*/run-all.sh, а шаги shellcheck конвейера
# (`.github/workflows/ci.yaml`: задания bats-and-shellcheck и hook-proofs) в наборы не входят:
# полный хук «12 наборов, 0 отказов» пропустил SC1091 в .claude/hooks/heavy-guard/prove.sh,
# и CI ws#1345 покраснел дважды подряд (прогоны 39791282976, 39797096014). Перечень шагов
# ВЫВОДИТСЯ из ci.yaml дерева, а не выписывается: шаг, заведённый в конвейере, хук исполнит
# той же отправкой.
#
# ЧТО СУДИТСЯ. Каждый шаг `run:` любого задания, чей текст — одна строка `shellcheck …` без
# `|| true` (такие шаги конвейер объявил справочными); каталог — `working-directory` шага либо
# `defaults.run.working-directory` задания, иначе корень дерева. Текст исполняется оболочкой
# (шаблоны `*.sh` раскрывает она, как bash конвейера), но лишь в форме «shellcheck и слова без
# метасимволов оболочки» — иное в хуке не исполняется и называется отказом разбора.
# Версия — пин конвейера `env.SHELLCHECK_VERSION`: иная версия даёт не тот вердикт, и это
# «не выполнилось», а не зелёное.
#
# Коды: 0 — все шаги зелёные; 1 — хотя бы один красный либо шаг вне формы; 2 — не выполнилось
# (нет ci.yaml, разборщика YAML, shellcheck пина либо шагов ноль). Счёт печатается всегда.
set -uo pipefail

tree="${1:-}"
[ -n "$tree" ] && [ -d "$tree" ] || { echo "prepush-ci-shellcheck: вызов — prepush-ci-shellcheck.sh <дерево>" >&2; exit 2; }
ci="$tree/.github/workflows/ci.yaml"
[ -f "$ci" ] || { echo "ci-shellcheck: [VOID] в дереве нет .github/workflows/ci.yaml — шагов конвейера нет, паритет не судится" >&2; exit 2; }

steps="$(python3 - "$ci" <<'PY'
import sys
try:
    import yaml
except ImportError:
    print("VOID\tразборщика YAML (PyYAML) нет")
    sys.exit(0)
d = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
print("PIN\t%s" % ((d.get("env") or {}).get("SHELLCHECK_VERSION") or ""))
for jk, j in (d.get("jobs") or {}).items():
    wd0 = (((j or {}).get("defaults") or {}).get("run") or {}).get("working-directory") or "."
    for st in (j or {}).get("steps") or []:
        r = st.get("run") if isinstance(st, dict) else None
        if not isinstance(r, str):
            continue
        t = r.strip()
        if not (t == "shellcheck" or t.startswith("shellcheck ")) or "\n" in t or "|| true" in t:
            continue
        print("STEP\t%s\t%s\t%s\t%s" % (jk, st.get("name") or "—", st.get("working-directory") or wd0, t))
PY
)" || { echo "ci-shellcheck: [VOID] разбор ci.yaml не исполнился" >&2; exit 2; }
if grep -q '^VOID' <<< "$steps"; then
    echo "ci-shellcheck: [VOID] $(grep '^VOID' <<< "$steps" | cut -f2)" >&2; exit 2
fi
pin="$(sed -n 's/^PIN\t//p' <<< "$steps")"
have="$(shellcheck --version 2>/dev/null | sed -n 's/^version: //p')"
if [ -z "$have" ]; then
    echo "ci-shellcheck: [VOID] shellcheck не найден — шаги конвейера не исполнены" >&2; exit 2
fi
if [ -n "$pin" ] && [ "$have" != "$pin" ]; then
    echo "ci-shellcheck: [VOID] shellcheck $have, а пин конвейера $pin — вердикт был бы не паритетен" >&2; exit 2
fi

n=0 bad=0
while IFS=$'\t' read -r kind job name wd run; do
    [ "$kind" = STEP ] || continue
    n=$((n + 1))
    if ! [[ "$run" =~ ^shellcheck[[:space:]][A-Za-z0-9_./*=,:[:space:]-]+$ ]]; then
        echo "ci-shellcheck: [FAIL] $job / $name — текст шага вне формы «shellcheck и слова без метасимволов»: $run" >&2
        bad=$((bad + 1)); continue
    fi
    out="$(cd "$tree/$wd" 2>/dev/null && bash -c "$run" 2>&1)"; rc=$?
    if [ "$rc" = 0 ]; then
        echo "ci-shellcheck: [PASS] $job / $name — ($wd) $run" >&2
    else
        echo "ci-shellcheck: [FAIL] $job / $name — ($wd) $run — код $rc" >&2
        printf '%s\n' "$out" | sed 's/^/    /' >&2
        bad=$((bad + 1))
    fi
done <<< "$steps"
echo "ci-shellcheck: шагов shellcheck конвейера $n, провалено $bad (shellcheck $have, пин ${pin:-—})" >&2
[ "$n" -gt 0 ] || { echo "ci-shellcheck: [VOID] шагов shellcheck в ci.yaml ноль — паритет не судится" >&2; exit 2; }
[ "$bad" -eq 0 ]
