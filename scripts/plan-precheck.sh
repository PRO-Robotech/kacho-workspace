#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# plan-precheck.sh — проверка плана волны ДО раздачи: то, что прежде держал
# текст диспетчера и что стоило возвратов не из-за кода (замер 2026-10-06:
# неверная посылка 74, неполное задание 7; линия kacho#1266 — полоса, начатая
# на corelib, которого у соседнего репозитория ещё нет, и две полосы на одном
# файле в параллель).
#
# ОСНОВАНИЕ. Решение владельца 2026-10-06 — процесс по уровням риска, условия
# плана — скриптом; предложение стрима нотификации, принятое владельцем, п.3:
# «одинаков ли corelib у kacho и kaname на целевых головах (иначе полоса
# перепина первой автоматически); граф зависимостей полос (зависимые — не в
# параллель)». Уровень полосы — НЕ здесь: его считает `scripts/lane-tier.sh`
# (единственный дом «уровень → шаги»), эта проверка его зовёт и повторяет вывод.
#
# usage: plan-precheck.sh <план.json> [--json]
#
# ПЛАН — объект:
#   {"wave": "<N>",
#    "targets": {"kacho": {"dir": "<клон>", "rev": "<ревизия>"},
#                "kaname": {"dir": "<клон>", "rev": "<ревизия>"}},
#    "lanes": [{"key": "A", "repo": "kacho", "dir": "<клон>", "base": "<ревизия>",
#               "head": "<ревизия>"?, "paths": ["<путь>", "<каталог>/"]?,
#               "deps": ["B"]?, "declared": "R0|R1|R2"?, "repin": "corelib"?}]}
# Объём полосы — `paths` (план до кода; каталог — с `/` на конце) либо дифф
# `base...head` (полоса уже писала). `targets` — головы, на которые полосы
# лягут (ветка волны или эпика); обязательны, когда в плане есть полоса kacho
# или kaname.
#
# ЧТО СУДИТ (строка `REASON<TAB><код><TAB><текст>` на причину):
#   LANE-NO-SCOPE     у полосы нет ни `paths`, ни `head`: уровень и пересечения
#                     судить не о чем — задание неполно (класс «неполное
#                     задание»);
#   LANE-KEY          ключ пуст или повторён;
#   DEP-UNKNOWN       зависимость названа ключом, которого в плане нет;
#   DEP-CYCLE         зависимости замкнуты в кольцо;
#   LANES-OVERLAP     две полосы одного репозитория трогают один путь (или путь
#                     внутри объявленного каталога), а порядка между ними нет:
#                     в параллель такие не идут — либо зависимость, либо одна
#                     полоса;
#   TIER-UNDERSTATED  объявленный уровень ниже вычисленного `lane-tier.sh`;
#   CORELIB-SKEW      пин corelib на целевых головах kacho и kaname разный, а
#                     полосы перепина (`"repin": "corelib"`) в отстающем
#                     репозитории нет либо его прочие полосы от неё не зависят.
#                     В выводе `--json` — `autoRepin`: шаблон волны
#                     (`.claude/workflows/wave.js`) заводит такую полосу первой
#                     сам и зовёт проверку заново.
#
# ВЫВОД. Перепись и причины — строками; с `--json` в stdout один объект
# {code, lanes:[{key, repo, tier, computed, steps, roles, acceptance, review,
# layer}], layers:[[ключи]], autoRepin:[{repo, from, to}], reasons:[{code,
# text}], voids:[…]}, перепись — в stderr. `layer` — номер слоя: полосы одного
# слоя идут параллельно, слой N+1 — после всех своих зависимостей.
#
# Коды: 0 — причин нет; 1 — причины есть; 2 — судить не смог (план не
# разбирается, ревизия не разрешается, lane-tier не дал уровня, нет целевой
# головы для corelib). Код 2 — не «план годен».
# Держит `scripts/plan-precheck-inject.sh`.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
[ $# -ge 1 ] || { echo "usage: plan-precheck.sh <план.json> [--json]" >&2; exit 2; }
command -v python3 > /dev/null 2>&1 || { echo "plan-precheck: VOID — нет python3" >&2; exit 2; }
exec python3 - "$HERE/lane-tier.sh" "$@" <<'PY'
import json, os, re, subprocess, sys, tempfile

tier_tool, args = sys.argv[1], sys.argv[2:]
as_json = "--json" in args
args = [a for a in args if a != "--json"]
if len(args) != 1:
    print("usage: plan-precheck.sh <план.json> [--json]", file=sys.stderr)
    sys.exit(2)

reasons, voids, census = [], [], []
out = sys.stderr if as_json else sys.stdout


def reason(code, text):
    reasons.append({"code": code, "text": " ".join(str(text).split())})


def void(code, text):
    voids.append({"code": code, "text": " ".join(str(text).split())})


def finish(lanes_out=(), layers=(), auto=()):
    code = 1 if reasons else (2 if voids else 0)
    for c in census:
        print(f"CENSUS\t{c}", file=out)
    for r in reasons:
        print(f"REASON\t{r['code']}\t{r['text']}", file=out)
    for v in voids:
        print(f"VOID\t{v['code']}\t{v['text']}", file=out)
    print(f"VERDICT\t{['plan-ok', 'stop', 'void'][code]}\tпричин {len(reasons)}, не судимо {len(voids)}", file=out)
    if as_json:
        print(json.dumps({"code": code, "lanes": list(lanes_out), "layers": list(layers),
                          "autoRepin": list(auto), "reasons": reasons, "voids": voids}, ensure_ascii=False))
    sys.exit(code)


try:
    plan = json.load(open(args[0], encoding="utf-8"))
except Exception as e:  # noqa: BLE001 — любой отказ разбора одинаково «плана нет»
    void("PLAN-MALFORMED", f"план {args[0]} не разбирается: {e}")
    finish()
lanes = plan.get("lanes") if isinstance(plan, dict) else None
if not isinstance(lanes, list) or not lanes or not all(isinstance(l, dict) for l in lanes):
    void("PLAN-MALFORMED", "в плане нет непустого массива lanes из объектов: ноль полос — не «план годен»")
    finish()


def git(d, *a):
    p = subprocess.run(["git", "-C", d, *a], capture_output=True, text=True)
    return p.returncode, p.stdout


# ── ключи и зависимости ─────────────────────────────────────────────────
keys = [str(l.get("key") or "") for l in lanes]
for k in sorted(set(keys)):
    if not k:
        reason("LANE-KEY", "у полосы пустой ключ")
    elif keys.count(k) > 1:
        reason("LANE-KEY", f"ключ {k} повторён {keys.count(k)} раз")
by = {str(l.get("key")): l for l in lanes if l.get("key")}
deps = {}
for l in lanes:
    k = str(l.get("key") or "")
    ds = l.get("deps") or []
    if not isinstance(ds, list):
        reason("DEP-UNKNOWN", f"{k}: deps не массив")
        ds = []
    deps[k] = []
    for d in ds:
        if str(d) not in by:
            reason("DEP-UNKNOWN", f"{k} зависит от {d}, а такой полосы в плане нет")
        else:
            deps[k].append(str(d))

# слои (Кан); кольцо — остаток
layer, left = {}, set(by)
n = 0
while left:
    ready = sorted(k for k in left if all(d in layer for d in deps.get(k, [])))
    if not ready:
        reason("DEP-CYCLE", f"зависимости замкнуты: {', '.join(sorted(left))}")
        break
    for k in ready:
        layer[k] = n
    left -= set(ready)
    n += 1
layers = [sorted(k for k in layer if layer[k] == i) for i in range(n)]


def ancestors(k, seen=None):
    seen = set() if seen is None else seen
    for d in deps.get(k, []):
        if d not in seen:
            seen.add(d)
            ancestors(d, seen)
    return seen


# ── объём и уровень каждой полосы ───────────────────────────────────────
scope, lanes_out = {}, []
for l in lanes:
    k = str(l.get("key") or "")
    repo = str(l.get("repo") or "")
    paths = l.get("paths")
    tier_args = ["bash", tier_tool, "--json"]
    if l.get("declared"):
        tier_args += ["--declared", str(l["declared"])]
    if repo:
        tier_args += ["--repo", repo]
    tmp = None
    if isinstance(paths, list) and paths:
        tmp = tempfile.NamedTemporaryFile("w", delete=False, suffix=".paths", encoding="utf-8")
        tmp.write("\n".join(str(p) for p in paths) + "\n")
        tmp.close()
        tier_args += ["--paths-file", tmp.name]
        scope[k] = [str(p) for p in paths]
    elif l.get("head"):
        d, b, h = str(l.get("dir") or ""), str(l.get("base") or ""), str(l["head"])
        rc, names = git(d, "diff", "--name-only", f"{b}...{h}")
        if rc != 0:
            void("REV-UNKNOWN", f"{k}: дифф {b}...{h} в «{d}» не читается")
            continue
        scope[k] = [p for p in names.splitlines() if p]
        tier_args += [d, b, h]
    else:
        reason("LANE-NO-SCOPE", f"{k}: нет ни paths, ни head — уровень и пересечения судить не о чем")
        continue
    p = subprocess.run(tier_args, capture_output=True, text=True)
    if tmp:
        os.unlink(tmp.name)
    last = (p.stdout.strip().splitlines() or [""])[-1]
    try:
        t = json.loads(last)
    except ValueError:
        void("TIER-VOID", f"{k}: lane-tier код {p.returncode}, уровня нет: {p.stderr.strip()[:200]}")
        continue
    if p.returncode == 1 and t.get("understated"):
        reason("TIER-UNDERSTATED", f"{k}: {t['understated']} — понизить уровень объявлением нельзя")
    elif p.returncode not in (0, 1):
        void("TIER-VOID", f"{k}: lane-tier код {p.returncode}")
        continue
    lanes_out.append({"key": k, "repo": repo, "tier": t["tier"], "computed": t["computed"],
                      "steps": t["steps"], "roles": t["roles"], "acceptance": t["acceptance"],
                      "review": t["review"], "layer": layer.get(k)})

# ── пересечения путей без порядка ───────────────────────────────────────
def touch(a, b):
    return a == b or (a.endswith("/") and b.startswith(a)) or (b.endswith("/") and a.startswith(b))


ks = sorted(scope)
pairs = 0
for i, a in enumerate(ks):
    for b in ks[i + 1:]:
        if str(by[a].get("repo")) != str(by[b].get("repo")):
            continue
        pairs += 1
        if a in ancestors(b) or b in ancestors(a):
            continue
        common = sorted({x if len(x) <= len(y) else y for x in scope[a] for y in scope[b] if touch(x, y)})
        if common:
            reason("LANES-OVERLAP", f"{a} и {b} ({by[a].get('repo')}) трогают {', '.join(common[:5])} без порядка между ними")

# ── corelib на целевых головах ──────────────────────────────────────────
PIN = re.compile(r"^\s*(?:require\s+)?github\.com/PRO-Robotech/corelib\s+(v\S+)", re.M)


def ver_key(v):
    m = re.match(r"v(\d+)\.(\d+)\.(\d+)(.*)", v)
    return (int(m[1]), int(m[2]), int(m[3]), m[4]) if m else (0, 0, 0, v)


auto = []
repos = {str(l.get("repo")) for l in lanes} & {"kacho", "kaname"}
if repos:
    targets = plan.get("targets") or {}
    pins = {}
    for r in ("kacho", "kaname"):
        tg = targets.get(r) if isinstance(targets, dict) else None
        if not isinstance(tg, dict) or not tg.get("dir") or not tg.get("rev"):
            void("TARGET-MISSING", f"целевой головы {r} нет (targets.{r}.dir/rev): corelib не с чем сверить")
            continue
        rc, gomod = git(str(tg["dir"]), "show", f"{tg['rev']}:go.mod")
        m = PIN.search(gomod) if rc == 0 else None
        if not m:
            void("TARGET-PIN", f"{r}@{tg['rev']}: go.mod не читается либо пина corelib в нём нет")
            continue
        pins[r] = m[1]
    if len(pins) == 2:
        census.append(f"corelib: kacho {pins['kacho']}, kaname {pins['kaname']}")
        if pins["kacho"] != pins["kaname"]:
            hi = max(pins.values(), key=ver_key)
            for r, v in sorted(pins.items()):
                if v == hi:
                    continue
                own = [str(l.get("key")) for l in lanes if str(l.get("repo")) == r]
                rep = [k for k in own if by[k].get("repin") == "corelib"]
                others = [k for k in own if k not in rep]
                ok = bool(rep) and all(set(rep) & ancestors(k) for k in others)
                if not ok:
                    auto.append({"repo": r, "from": v, "to": hi})
                    reason("CORELIB-SKEW", f"{r} на corelib {v}, соседний репозиторий — {hi}: полоса перепина corelib в {r} — первой, прочие полосы {r} — от неё")
else:
    census.append("corelib: полос kacho и kaname нет — не судился")

census.insert(0, f"план {args[0]}: полос {len(lanes)}, слоёв {len(layers)}, пар одного репозитория {pairs}, уровней вычислено {len(lanes_out)}")
for lo in lanes_out:
    census.append(f"полоса {lo['key']} ({lo['repo']}): {lo['tier']} слой {lo['layer']} шаги {','.join(lo['steps'])}")
finish(lanes_out, layers, auto)
PY
