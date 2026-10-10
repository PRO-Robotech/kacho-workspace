#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""mutants — набор `inject.sh` обязан КРАСНЕТЬ на однофактной порче каждого
решения среды и истории `run.sh` (ws#996).

Зачем: приёмка ws#996 (check-verifier, круг 1, ⛔ на 0d9c92582) нашла две порчи,
на которых `inject.sh` оставался зелёным: снятая проверка суммы архива node
(в перечне — M12: двойник curl ломал только сумму helm, а E1 искал
«SHASUMS256.txt» и «sha256sum -c» поиском по тексту) и префикс мажора node без
точки (M8: в индексе двойника не было выпуска, который префикс без точки
перепутал бы). Перечень ниже — по РЕШЕНИЮ установки, сверки среды, разбора пина
и доставки истории, у каждой порчи — проба `inject.sh`, которая её держит.
Полноты перечень не утверждает: он держит названные решения; новое решение среды
без строки здесь — та же дыра заново.

КАК: порча — точная замена фрагмента исходника копии `run.sh`. Копия кладётся
во временный каталог, `inject.sh` гонится против неё через `REMOTE_HEAVY_RUN`.
Порча УБИТА, если набор вышел кодом 1 и напечатал строку «ПРОВАЛ <проба>:» той
пробы, что названа у порчи (красное названо СВОЕЙ пробой, а не соседним случаем
и не обрывом набора).

ПРЕДПОСЫЛКИ (их отказ — код 1 харнесса, а не «порча выжила»):
  - контроль: набор против НЕиспорченной копии зелёный (код 0) — иначе
    красное порчи неотличимо от красного набора;
  - фрагмент порчи встречается в исходнике РОВНО один раз — иначе порча
    устарела вместе с правкой `run.sh` и молча перестала что-либо портить.

ИСХОДЫ: 0 — все порчи убиты; 1 — выжила хоть одна порча либо отказала
предпосылка; 2 — порч ноль (перечень пуст — проверено ничего).

Запуск: python3 scripts/remote-heavy/mutants.py [-j <параллельно>] [<id>…]
"""
import argparse
import concurrent.futures
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
RUN = os.path.join(HERE, "run.sh")
INJECT = os.path.join(HERE, "inject.sh")

# (id, проба, что портит, фрагмент, замена)
MUTANTS = [
    ("M12", "E7-badsum-node", "сумма архива node не проверяется",
     r'''| grep "  $f\$" | sha256sum -c --quiet -''',
     r'''| grep "  $f\$" >/dev/null'''),
    ("M8", "E7-minor", "префикс мажора node без точки: пин 26.1 берёт v26.11.x",
     r'''--arg m "v$HEAVY_NODE."''',
     r'''--arg m "v$HEAVY_NODE"'''),
    ("helm-sum", "E7-badsum", "сумма архива helm не проверяется",
     r'''| cut -d" " -f1)  $f" | sha256sum -c --quiet -''',
     r'''| cut -d" " -f1)  $f" >/dev/null'''),
    ("node-dl-dir", "E7-node-only", "каталог загрузки node создаётся лишь веткой helm",
     r'''mkdir -p /work/dl /work/node''',
     r'''mkdir -p /work/node'''),
    ("node-oldest", "E7", "мажор разрешается в старейший выпуск, а не в последний",
     r'''[0] // empty''',
     r'''[-1] // empty'''),
    ("node-exact", "E7-exact", "полный пин N.N.N не находит свой выпуск",
     r''' or . == (\$m | rtrimstr(\".\"))''',
     r''''''),
    ("arch", "E7-arch", "чужая архитектура проходит как amd64",
     r'''*) return 1;; esac; }''',
     r'''*) echo "$1";; esac; }'''),
    ("tools-helm-prefix", "E2-helm-prefix", "сверка helm принимает v4.2.40 за v4.2.4",
     r'''"$HEAVY_HELM"|"$HEAVY_HELM+"*)''',
     r'''"$HEAVY_HELM"*)'''),
    ("tools-node-prefix", "E2-node-prefix", "сверка node принимает v260 за 26",
     r'''"v$HEAVY_NODE"|"v$HEAVY_NODE."*)''',
     r'''"v$HEAVY_NODE"*)'''),
    ("pin-own-step", "E1", "ключ пина берётся у любого шага с uses (version setup-kubectl)",
     r'''or not str(st.get("uses", "")).startswith(u):''',
     r'''or not str(st.get("uses", "")):'''),
    ("pin-bare", "E9", "шаг без ключа пина молча значит «пина нет»",
     r'''sys.exit(4 if bare else 0)''',
     r'''sys.exit(0)'''),
    ("pin-ambiguous", "E3", "два разных пина helm не отказ",
     r'''-eq 1 ] || { say "пин $3 неоднозначен''',
     r'''-ge 1 ] || { say "пин $3 неоднозначен'''),
    ("pin-lint", "E4", "профиль lint ставит среду",
     'if [ "$PROFILE" != lint ]; then\n    HELM_PIN=',
     'if true; then\n    HELM_PIN='),
    ("pin-helm-form", "E10b", "пин helm вне формы vX.Y.Z принимается",
     r'''"$HELM_PIN" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$''',
     r'''"$HELM_PIN" =~ .'''),
    ("pin-node-form", "E10", "пин node вне формы N[.N[.N]] принимается",
     r'''"$NODE_PIN" =~ ^[0-9]+(\.[0-9]+){0,2}$''',
     r'''"$NODE_PIN" =~ .'''),
    ("env-helm", "E1", "пин helm не доходит до окружения run",
     r'''{name: "HEAVY_HELM", value: $helm}, ''',
     r''''''),
    ("env-refusal", "E6", "отказ сверки среды выдаётся кодом команды, а не 69",
     r'''if [[ "$RUN_MSG" == "remote-heavy-prep: среда: "* ]]; then''',
     r'''if false; then'''),
    ("hist-bundle", "H1", "bundle несёт лишь ствол, без веток origin и меток",
     r'''"$TMPREF" --remotes=origin --tags''',
     r'''"$TMPREF" ${MAIN_SHA:+refs/remotes/origin/main}'''),
    ("hist-fetch", "H1", "дерево pod берёт из bundle лишь ствол",
     r'''refs/remotes/*|refs/tags/*) git update-ref''',
     r'''refs/remotes/origin/main) git update-ref'''),
]


def run_inject(run_path, tmp):
    env = dict(os.environ, REMOTE_HEAVY_RUN=run_path, TMPDIR=tmp)
    p = subprocess.run(["bash", INJECT], env=env, capture_output=True, text=True, timeout=1800)
    out = p.stdout + p.stderr
    fails = [ln for ln in out.splitlines() if ln.startswith("ПРОВАЛ ")]
    tail = out.strip().splitlines()[-1] if out.strip() else ""
    return p.returncode, fails, tail


def one(src, root, m):
    mid, probe, _, frag, repl = m
    d = tempfile.mkdtemp(prefix=f"mut-{mid}-", dir=root)
    path = os.path.join(d, "run.sh")
    with open(path, "w") as f:
        f.write(src.replace(frag, repl, 1))
    rc, fails, tail = run_inject(path, d)
    shutil.rmtree(d, ignore_errors=True)
    # Убита — красным СВОЕЙ пробы: красное соседнего случая (гонки C4/C5 под
    # нагрузкой параллельных наборов) порчу не убивает.
    by_probe = any(ln.startswith(f"ПРОВАЛ {probe}:") for ln in fails)
    killed = rc == 1 and by_probe
    return mid, killed, by_probe, rc, fails, tail


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-j", type=int, default=4)
    ap.add_argument("ids", nargs="*")
    a = ap.parse_args()
    todo = [m for m in MUTANTS if not a.ids or m[0] in a.ids]
    if not todo:
        print("mutants: порч ноль — проверено ничего")
        return 2
    src = open(RUN).read()
    bad = [m[0] for m in todo if src.count(m[3]) != 1]
    if bad:
        print("mutants: ПРЕДПОСЫЛКА — фрагмент встречается не ровно один раз: " + ", ".join(bad))
        return 1
    root = tempfile.mkdtemp(prefix="remote-heavy-mutants-")
    try:
        rc, fails, tail = run_inject(RUN, root)
        print(f"контроль: код {rc} · {tail}")
        if rc != 0:
            print("mutants: ПРЕДПОСЫЛКА — набор красный без порчи")
            return 1
        survived = 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=a.j) as ex:
            res = list(ex.map(lambda m: one(src, root, m), todo))
        for m, (mid, killed, by_probe, rc, fails, tail) in zip(todo, res):
            survived += not killed
            names = sorted({ln.split(":", 1)[0][len("ПРОВАЛ "):] for ln in fails})
            print(f"{'УБИТА ' if killed else 'ВЫЖИЛА'} {mid:18} держит {m[1]}"
                  f" · код {rc} · {tail} · красные: {', '.join(names) or '—'} · {m[2]}")
        print(f"remote-heavy mutants: порч {len(todo)} · убито {len(todo) - survived} · выжило {survived}")
        return 1 if survived else 0
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
