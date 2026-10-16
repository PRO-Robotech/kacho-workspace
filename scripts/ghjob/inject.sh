#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# inject.sh — доказательство того, что ghjob.py СПОСОБЕН дать шагу задания среду
# python конвейера и способен её не дать, а не только объявляет это в шапке.
#
# Настоящий вход — форма задания `stand` kaname (ws#1110): подъём красный, шаг с
# `pip install` после него пропущен, шаг `if: always()` импортирует пакет. Пакет —
# свой колёсный архив, pip идёт без индекса (PIP_NO_INDEX, PIP_FIND_LINKS): исход
# не зависит от сети. Случаи:
#   P1  шаг always() видит пакет, который ставит пропущенный шаг задания → success;
#       перепись «итог: шагов 3, исполнено 2, упало 1, пропущено 1», код 1
#   P1m порча: venv без пакетов задания → тот же шаг failure (P1 способен упасть)
#   P2  законный близнец: у задания pip нет → пакет НЕ поставлен (лишнего нет),
#       строка «pip-пакетов у задания нет»
#   P3  вывод пакетов формами текста: --quiet, -q, -r, ==, перенос строки, флаг со
#       значением, подстановка «$X» → «?», хвост «|| rc=$?»
#   P4  пакета нет нигде → код 4 «не выполнилось», шагов не исполнено
#   P5  токен площадки в текст шага не подставлен, а в окружении шага есть
#   P6  `if: false` — шагов не исполнено → код 3
#   P7  пакет системного python (yaml), который ни один шаг не ставит, — виден шагу,
#       как apt-пакет образа ранера (посев kaname — cryptography); порча P7m — venv
#       без пакетов системы → failure
#   P8  env уровня workflow доходит до шага (ws#1115: пин shellcheck воркспейса брал
#       версию оттуда и без неё тянул релиз «v» — 404); близнец — env задания сильнее
#       env workflow; порча P8m — env workflow снят → failure; P8m2 — уровни
#       переставлены → близнец failure
#   P9  предел шага вне CI — ×GHJOB_TIMEOUT_SCALE, по умолчанию ×3 (ws#1110). Настоящий
#       вход — шаг 11 задания stand-ceremony kaname («условие создано — люди и их
#       предъявители своей церемонией службы», timeout-minutes 5): в CI 90 с, вне CI
#       подом во внешнем кластере ≥ 305 с — оборван. Минуты сжаты в 100 раз при той же
#       форме: предел 0,03 мин (1,8 с), шаг 3 с — длиннее предела ×1, короче ×3.
#       P9   вне CI без переменной → success, строка «предел шагов ×3 (вне CI…)»;
#       P9s  GHJOB_TIMEOUT_SCALE=1 — без множителя шаг обрывается: failure, rc 124;
#       P9c  законный близнец: ранер CI (GITHUB_ACTIONS=true) — предел workflow не
#            тронут, шаг обрывается на 1,8 с: failure, «×1 = 2 с»;
#       P9v  GHJOB_TIMEOUT_SCALE не число либо 0 → код 64, шагов не исполнено;
#       P9m  порча: множитель не доходит до предела → P9 failure (P9 способен упасть);
#       P9m2 порча: ранер не опознан → близнец P9c success (P9c способен упасть).
# Коды: 0 — все сошлись; 1 — хотя бы одно нет; 2 — предпосылки нет (python3 с
# yaml, venv либо pip) — не выполнилось.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GHJOB="$HERE/ghjob.py"
W="$(mktemp -d)" || { echo "inject: каталог не создан" >&2; exit 2; }
trap 'rm -rf -- "$W"' EXIT
pass=0; fail=0
ok() { echo "  [OK]   $1"; pass=$((pass + 1)); }
bad() { echo "  [FAIL] $1" >&2; [ -n "${2:-}" ] && sed 's/^/      /' "$2" >&2; fail=$((fail + 1)); }
check() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 — ожидалось «$1», получено «$2»" "${4:-}"; fi; }

python3 -c 'import yaml' 2>/dev/null || { echo "inject: нет python3 с yaml — не выполнилось" >&2; exit 2; }

# Колёсный архив пакета пробы — руками, без setuptools и сети.
mkdir -p "$W/wh"
python3 - "$W/wh" <<'PY' || { echo "inject: колёсный архив не построен — не выполнилось" >&2; exit 2; }
import base64, hashlib, sys, zipfile
d = sys.argv[1]
files = {
    "ghjobprobe.py": "VALUE = 1\n",
    "ghjobprobe-1.0.dist-info/METADATA": "Metadata-Version: 2.1\nName: ghjobprobe\nVersion: 1.0\n",
    "ghjobprobe-1.0.dist-info/WHEEL": "Wheel-Version: 1.0\nGenerator: inject\nRoot-Is-Purelib: true\nTag: py3-none-any\n",
}
rec = []
with zipfile.ZipFile(f"{d}/ghjobprobe-1.0-py3-none-any.whl", "w") as z:
    for n, c in files.items():
        z.writestr(n, c)
        h = base64.urlsafe_b64encode(hashlib.sha256(c.encode()).digest()).rstrip(b"=").decode()
        rec.append(f"{n},sha256={h},{len(c.encode())}")
    rec.append("ghjobprobe-1.0.dist-info/RECORD,,")
    z.writestr("ghjobprobe-1.0.dist-info/RECORD", "\n".join(rec) + "\n")
PY
export PIP_NO_INDEX=1 PIP_FIND_LINKS="$W/wh" PIP_DISABLE_PIP_VERSION_CHECK=1
# Двойник gh: токен площадки — опознаваемая строка.
mkdir -p "$W/bin"
# shellcheck disable=SC2016  # текст двойника, а не раскрытие
printf '#!/bin/sh\n[ "$1 $2" = "auth token" ] && echo SENTINEL-gh-token && exit 0\nexit 1\n' > "$W/bin/gh"
chmod +x "$W/bin/gh"
export PATH="$W/bin:$PATH"

# Подпись песочницы — из её корневого gitconfig (scripts/lib/sandbox-git-home.sh, check-16).
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/sandbox-git-home.sh
. "$HERE/../lib/sandbox-git-home.sh"
sandbox_git_home "$W/ghome" || { echo "inject: корневой подписи нет — копия пробы не построена, не выполнилось" >&2; exit 2; }
CO="$W/co"; git init -q "$CO"; git -C "$CO" remote add origin https://github.com/PRO-Robotech/probe.git
sandbox_git -C "$CO" commit -q --allow-empty -m probe \
    || { echo "inject: копия пробы не построена — не выполнилось" >&2; exit 2; }
cat > "$W/wf.yml" <<'YML'
env:
  GHJOB_WF: from-workflow
jobs:
  stand:
    steps:
      - name: подъём стенда
        run: exit 1
      - name: инструменты прогона
        run: python3 -m pip install --quiet ghjobprobe || rc=$?
      - name: долг
        if: always()
        run: python3 -c 'import ghjobprobe'
  bare:
    steps:
      - run: exit 1
      - if: always()
        run: python3 -c 'import ghjobprobe'
  forms:
    steps:
      - run: |
          pip install --quiet pytest pyyaml
          python3 -m pip install -q -r req/a.txt x==1 \
            --index-url https://example.invalid y
          pip3 install "$PKG"
          python3 -m pip install --quiet z || rc=$?
  missing:
    steps:
      - run: pip install ghjobnosuchpackage
      - run: "true"
  token:
    steps:
      - run: |
          echo "${{ github.token }}" > /dev/null
          test "${#GITHUB_TOKEN}" = 17 && test "${GITHUB_TOKEN%-token}" = SENTINEL-gh
  sysyaml:
    steps:
      - run: python3 -c 'import yaml'
  never:
    steps:
      - if: false
        run: "true"
  wfenv:
    steps:
      - run: test "$GHJOB_WF" = from-workflow
  wfenv-job:
    env:
      GHJOB_WF: from-job
    steps:
      - run: test "$GHJOB_WF" = from-job
  stand-ceremony:
    steps:
      - name: условие создано — люди и их предъявители своей церемонией службы
        timeout-minutes: 0.03
        run: sleep 3
YML
step_outcome() { python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(" ".join(s["outcome"] for s in r["steps"]))' "$1" 2>/dev/null || echo нет; }

# run_ghjob <имя> <ghjob> <задание> [K=V…] — код в RC, вывод в $W/<имя>.out, каталог $W/<имя>
# GHJOB_WF вызывающего снят: P8 судит env из workflow пробы, а не унаследованное.
# GHJOB_TIMEOUT_SCALE и GITHUB_ACTIONS сняты: случай — «вне CI», и на ранере тоже;
# ранер и множитель случай задаёт сам хвостом K=V (P9).
run_ghjob() {
    local n="$1" g="$2" j="$3"; shift 3
    env -u GHJOB_WF -u GHJOB_TIMEOUT_SCALE -u GITHUB_ACTIONS "$@" python3 "$g" "$W/wf.yml" "$j" "$CO" "$W/$n" > "$W/$n.out" 2>&1; RC=$?
}

echo "── среда python задания: пакеты пропущенного шага — в venv сразу (ws#1110)"
run_ghjob p1 "$GHJOB" stand
check "1 failure skipped success" "$RC $(step_outcome "$W/p1/result.json")" "P1: шаг always() видит пакет пропущенного шага задания" "$W/p1.out"
check да "$(grep -q 'итог: шагов 3, исполнено 2, упало 1, пропущено 1' "$W/p1.out" && echo да || echo нет)" "P1: перепись шагов напечатана" "$W/p1.out"
check да "$(grep -q 'пакеты задания: ghjobprobe' "$W/p1.out" && echo да || echo нет)" "P1: пакеты задания названы" "$W/p1.out"
# Порча: venv без пакетов задания — проба обязана покраснеть.
frag='    pkgs, reqs, unknown = pip_packages(job)'
if [ "$(grep -cxF -- "$frag" "$GHJOB")" = 1 ]; then
    sed "s/^    pkgs, reqs, unknown = pip_packages(job)\$/    pkgs, reqs, unknown = [], [], []/" "$GHJOB" > "$W/ghjob-mut.py"
    run_ghjob p1m "$W/ghjob-mut.py" stand
    check "1 failure skipped failure" "$RC $(step_outcome "$W/p1m/result.json")" "P1m порча: без пакетов задания шаг always() падает — P1 способен упасть" "$W/p1m.out"
else
    bad "P1m: фрагмент порчи встречается не ровно один раз — порча устарела"
fi
run_ghjob p2 "$GHJOB" bare
check "1 failure failure" "$RC $(step_outcome "$W/p2/result.json")" "P2 близнец: у задания pip нет — пакет не поставлен" "$W/p2.out"
check да "$(grep -q 'pip-пакетов у задания нет' "$W/p2.out" && echo да || echo нет)" "P2: «пакетов нет» названо отдельной строкой" "$W/p2.out"

echo "── вывод пакетов из текста шагов"
got="$(python3 "$GHJOB" --pip "$W/wf.yml" forms | tr '\n' ' ')"
check "pytest pyyaml x==1 y z -r req/a.txt ? " "$got" "P3: формы pip install выведены, подстановка — «?»"

echo "── отказы — не вердикт"
run_ghjob p4 "$GHJOB" missing
check "4 нет" "$RC $([ -e "$W/p4/result.json" ] && echo да || echo нет)" "P4: пакет не ставится — код 4, шагов не исполнено" "$W/p4.out"
check да "$(grep -q 'не поставлены' "$W/p4.out" && echo да || echo нет)" "P4: причина названа" "$W/p4.out"
run_ghjob p5 "$GHJOB" token
check "0 success" "$RC $(step_outcome "$W/p5/result.json")" "P5: токен в окружении шага" "$W/p5.out"
# shellcheck disable=SC2016  # ищется буквальная ссылка на переменную
check "нет да" "$(grep -qF SENTINEL-gh-token "$W/p5/step-00.sh" && echo да || echo нет) $(grep -qF '${GITHUB_TOKEN}' "$W/p5/step-00.sh" && echo да || echo нет)" "P5: токен в текст шага на диске не подставлен"
run_ghjob p6 "$GHJOB" never
check 3 "$RC" "P6: if: false — шагов не исполнено, код 3" "$W/p6.out"

echo "── пакеты системного python видны шагу, как пакеты образа ранера"
run_ghjob p7 "$GHJOB" sysyaml
check "0 success" "$RC $(step_outcome "$W/p7/result.json")" "P7: yaml системы виден шагу без pip" "$W/p7.out"
frag="SYS_SITE = '--system-site-packages'"
if [ "$(grep -cxF -- "$frag" "$GHJOB")" = 1 ]; then
    sed "s/^SYS_SITE = '--system-site-packages'\$/SYS_SITE = ''/" "$GHJOB" > "$W/ghjob-mut7.py"
    run_ghjob p7m "$W/ghjob-mut7.py" sysyaml
    check "1 failure" "$RC $(step_outcome "$W/p7m/result.json")" "P7m порча: venv без пакетов системы — шаг падает, P7 способен упасть" "$W/p7m.out"
else
    bad "P7m: фрагмент порчи встречается не ровно один раз — порча устарела"
fi

echo "── env уровнями ранера: workflow, поверх — задания (ws#1115)"
run_ghjob p8 "$GHJOB" wfenv
check "0 success" "$RC $(step_outcome "$W/p8/result.json")" "P8: env workflow виден шагу" "$W/p8.out"
run_ghjob p8j "$GHJOB" wfenv-job
check "0 success" "$RC $(step_outcome "$W/p8j/result.json")" "P8 близнец: env задания сильнее env workflow" "$W/p8j.out"
frag='    env.update(env_of(WF))'
if [ "$(grep -cxF -- "$frag" "$GHJOB")" = 1 ] && [ "$(grep -cxF -- '    env.update(env_of(J))' "$GHJOB")" = 1 ]; then
    grep -vxF -- "$frag" "$GHJOB" > "$W/ghjob-mut8.py"
    run_ghjob p8m "$W/ghjob-mut8.py" wfenv
    check "1 failure" "$RC $(step_outcome "$W/p8m/result.json")" "P8m порча: env workflow снят — шаг падает, P8 способен упасть" "$W/p8m.out"
    # Уровни переставлены: workflow поверх задания.
    awk -v f="$frag" '$0 == f { next } { print } $0 == "    env.update(env_of(J))" { print f }' "$GHJOB" > "$W/ghjob-mut8b.py"
    run_ghjob p8m2 "$W/ghjob-mut8b.py" wfenv-job
    check "1 failure" "$RC $(step_outcome "$W/p8m2/result.json")" "P8m2 порча: workflow поверх задания — близнец падает, порядок уровней держится" "$W/p8m2.out"
else
    bad "P8m: фрагменты порчи встречаются не ровно один раз — порча устарела"
fi

echo "── предел шага вне CI — ×3 по умолчанию, в CI — предел workflow (ws#1110)"
yes_if() { grep -qF -- "$1" "$2" && echo да || echo нет; }
run_ghjob p9 "$GHJOB" stand-ceremony
check "0 success" "$RC $(step_outcome "$W/p9/result.json")" "P9: вне CI шаг длиннее предела ×1 проходит под ×3" "$W/p9.out"
check да "$(yes_if 'предел шагов ×3 (вне CI, по умолчанию)' "$W/p9.out")" "P9: множитель и источник напечатаны" "$W/p9.out"
run_ghjob p9s "$GHJOB" stand-ceremony GHJOB_TIMEOUT_SCALE=1
check "1 failure" "$RC $(step_outcome "$W/p9s/result.json")" "P9s: без множителя (×1) шаг обрывается" "$W/p9s.out"
check да "$(yes_if 'rc=124' "$W/p9s.out")" "P9s: обрыв — код 124 шага" "$W/p9s.out"
run_ghjob p9c "$GHJOB" stand-ceremony GITHUB_ACTIONS=true
check "1 failure" "$RC $(step_outcome "$W/p9c/result.json")" "P9c близнец: на ранере CI предел workflow не тронут — шаг обрывается" "$W/p9c.out"
check "да да" "$(yes_if 'предел шагов ×1 (ранер CI' "$W/p9c.out") $(yes_if 'timeout-minutes=0.03 ×1 = 2 с' "$W/p9c/step-00.log")" "P9c: ×1 и предел workflow названы" "$W/p9c.out"
run_ghjob p9v "$GHJOB" stand-ceremony GHJOB_TIMEOUT_SCALE=abc
check "64 нет" "$RC $([ -e "$W/p9v/result.json" ] && echo да || echo нет)" "P9v: множитель не число — 64, шагов не исполнено" "$W/p9v.out"
run_ghjob p9z "$GHJOB" stand-ceremony GHJOB_TIMEOUT_SCALE=0
check "64 нет" "$RC $([ -e "$W/p9z/result.json" ] && echo да || echo нет)" "P9v: множитель 0 — 64, шагов не исполнено" "$W/p9z.out"
frag='                limit = tmo * 60 * scale if tmo else None'
if [ "$(grep -cxF -- "$frag" "$GHJOB")" = 1 ]; then
    sed 's/^                limit = tmo \* 60 \* scale if tmo else None$/                limit = tmo * 60 if tmo else None/' "$GHJOB" > "$W/ghjob-mut9.py"
    run_ghjob p9m "$W/ghjob-mut9.py" stand-ceremony
    check "1 failure" "$RC $(step_outcome "$W/p9m/result.json")" "P9m порча: множитель не доходит до предела — P9 способен упасть" "$W/p9m.out"
else
    bad "P9m: фрагмент порчи встречается не ровно один раз — порча устарела"
fi
frag="    if environ.get('GITHUB_ACTIONS') == 'true':"
if [ "$(grep -cxF -- "$frag" "$GHJOB")" = 1 ]; then
    sed "s/^    if environ.get('GITHUB_ACTIONS') == 'true':\$/    if False:/" "$GHJOB" > "$W/ghjob-mut9b.py"
    run_ghjob p9m2 "$W/ghjob-mut9b.py" stand-ceremony GITHUB_ACTIONS=true
    check "0 success" "$RC $(step_outcome "$W/p9m2/result.json")" "P9m2 порча: ранер не опознан — близнец проходит, P9c способен упасть" "$W/p9m2.out"
else
    bad "P9m2: фрагмент порчи встречается не ровно один раз — порча устарела"
fi

echo "[CENSUS] ghjob: утверждений $((pass + fail)), сошлось $pass, разошлось $fail"
[ "$fail" -eq 0 ]
