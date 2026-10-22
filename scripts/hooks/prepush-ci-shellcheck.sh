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
# ЧТО СУДИТСЯ. Каждый шаг `run:` любого задания (однострочный и многострочный `run: |`), в котором
# есть строка-вызов `shellcheck …` — не `shellcheck --version`/`-V` (это шаг-установщик); шаг,
# где вызов несёт `|| true`, конвейер объявил справочным — он не судится. Каталог —
# `working-directory` шага либо `defaults.run.working-directory` задания, иначе корень дерева.
# Текст исполняется оболочкой (шаблоны `*.sh` раскрывает она, как bash конвейера), но лишь когда
# КАЖДАЯ строка шага — вызов shellcheck словами без метасимволов оболочки либо `set` с флагами;
# иначе шаг — отказ формы (код 1), а не молчание.
# Версия — пин `SHELLCHECK_VERSION` НА ШАГ: env шага сильнее env задания, то — верхнего (так их
# ставит GitHub Actions); иная версия либо пина нет — «не выполнилось», а не зелёное.
#
# Коды: 0 — все шаги зелёные; 1 — хотя бы один красный либо вне формы; 2 — не выполнилось
# (нет ci.yaml, разборщика YAML, shellcheck, пин не совпал либо шагов ноль). Счёт печатается всегда.
set -uo pipefail

tree="${1:-}"
[ -n "$tree" ] && [ -d "$tree" ] || { echo "prepush-ci-shellcheck: вызов — prepush-ci-shellcheck.sh <дерево>" >&2; exit 2; }
ci="$tree/.github/workflows/ci.yaml"
[ -f "$ci" ] || { echo "ci-shellcheck: [VOID] в дереве нет .github/workflows/ci.yaml — шагов конвейера нет, паритет не судится" >&2; exit 2; }

steps="$(python3 - "$ci" <<'YAMLSTEPS'
import re, sys
try:
    import yaml
except ImportError:
    print("VOID\tразборщика YAML (PyYAML) нет")
    sys.exit(0)
SAFE = re.compile(r"^shellcheck(\s[A-Za-z0-9_./*=,:\s-]+)?$")
SETL = re.compile(r"^set(\s+[-+][euxo]+)*(\s+pipefail)?$")
CALL = re.compile(r"^shellcheck(\s|$)")
INFO = re.compile(r"^shellcheck\s+(--version|-V)(\s|$)")
d = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
pin0 = (d.get("env") or {}).get("SHELLCHECK_VERSION")
for jk, j in (d.get("jobs") or {}).items():
    j = j or {}
    wd0 = ((j.get("defaults") or {}).get("run") or {}).get("working-directory") or "."
    pinj = (j.get("env") or {}).get("SHELLCHECK_VERSION", pin0)
    for st in j.get("steps") or []:
        r = st.get("run") if isinstance(st, dict) else None
        if not isinstance(r, str):
            continue
        lines = [x.strip() for x in r.splitlines() if x.strip()]
        calls = [x for x in lines if CALL.match(x) and not INFO.match(x)]
        if not calls or any("|| true" in x for x in calls):
            continue
        pin = (st.get("env") or {}).get("SHELLCHECK_VERSION", pinj)
        ok = all(SAFE.match(x) or SETL.match(x) for x in lines)
        print("STEP\t%s\t%s\t%s\t%s\t%s\t%s" % (
            "ok" if ok else "bad", jk, str(st.get("name") or "—").replace("\t", " "),
            st.get("working-directory") or wd0, "" if pin is None else pin, " ; ".join(lines).replace("\t", " ")))
YAMLSTEPS
)" || { echo "ci-shellcheck: [VOID] разбор ci.yaml не исполнился" >&2; exit 2; }
if grep -q '^VOID' <<< "$steps"; then
    echo "ci-shellcheck: [VOID] $(grep '^VOID' <<< "$steps" | cut -f2)" >&2; exit 2
fi
have="$(shellcheck --version 2>/dev/null | sed -n 's/^version: //p')"
if [ -z "$have" ]; then
    echo "ci-shellcheck: [VOID] shellcheck не найден — шаги конвейера не исполнены" >&2; exit 2
fi

n=0 bad=0 nv=0 pins=""
while IFS=$'\t' read -r kind form job name wd pin run; do
    [ "$kind" = STEP ] || continue
    n=$((n + 1)); pins="${pins:+$pins,}${pin:-—}"
    if [ "$form" != ok ]; then
        echo "ci-shellcheck: [FAIL] $job / $name — текст шага вне формы «строки shellcheck и set без метасимволов»: $run" >&2
        bad=$((bad + 1)); continue
    fi
    if [ -z "$pin" ]; then
        echo "ci-shellcheck: [VOID] $job / $name — пина SHELLCHECK_VERSION нет (шаг, задание, верх): версия CI не названа, паритет не судим" >&2
        nv=$((nv + 1)); continue
    fi
    if [ "$have" != "$pin" ]; then
        echo "ci-shellcheck: [VOID] $job / $name — shellcheck $have, а пин конвейера $pin — вердикт был бы не паритетен" >&2
        nv=$((nv + 1)); continue
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
echo "ci-shellcheck: шагов shellcheck конвейера $n, провалено $bad, не выполнено $nv (shellcheck $have, пин $(tr ',' '\n' <<< "${pins:-—}" | sort -u | paste -sd, -))" >&2
[ "$n" -gt 0 ] || { echo "ci-shellcheck: [VOID] шагов shellcheck в ci.yaml ноль — паритет не судится" >&2; exit 2; }
[ "$bad" -eq 0 ] || exit 1
[ "$nv" -eq 0 ] || exit 2
exit 0
