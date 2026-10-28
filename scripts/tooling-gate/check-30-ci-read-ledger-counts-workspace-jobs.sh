#!/usr/bin/env bash
# check-30 — ведомость чтения CI о стволе воркспейса знает столько проверок, сколько
# заданий производит конвейер, и разнесённое на шарды задание сводится в свой контекст.
#
# ПРИЗНАК (ws#1481, возврат check-verifier @55753ca75). Задание `bats-and-shellcheck`
# разнесено на три шарда и свод: заданий в `.github/workflows/ci.yaml` стало 15, а
# строка `PRO-Robotech/kacho-workspace main` в `scripts/ci-read-expected.tsv` осталась 12.
# ci-read.sh судит неполный набор нижней границей ведомости (CHECKS-INCOMPLETE): при 12
# записанных он молча прощал недостающие до числа заданий (`yq ".jobs | length"` по ci.yaml). Ни один набор этого не видел —
# число в ведомости и число заданий жили в разных файлах без сверки.
#
# УТВЕРЖДЕНИЯ:
#   A. строка `PRO-Robotech/kacho-workspace<TAB>main` в ведомости ровно одна, и её число
#      РАВНО числу заданий ci.yaml (единица ведомости — различное имя check-run на
#      голове; каждое задание без матрицы даёт одно имя, и пропущенное по `if:` —
#      тоже: GitHub ставит ему check-run skipped). Больше — тоже находка: ведомость
#      точным числом, не потолком (`testing.md#ledger-exact-not-ceiling`);
#   B. каждое задание `<свод>-shard-<N>` входит в `needs` задания `<свод>`, а у свода
#      `if:` содержит `always()`: шард вне needs свод не судит, а без always() красный
#      шард даёт своду skipped, и обязательный контекст проходит;
#   C. имя контекста ни одного задания (`name:`, без него — ключ) не начинается с имени
#      контекста другого задания: сверка обязательных контекстов идёт и по префиксу
#      (GitHub усекает длинные имена в защите), и шард с именем
#      «<свод> · шард N» засчитывал контекст свода, даже когда свода не было
#      (возврат check-verifier, опыт «свод снят»).
#
# ГРАНИЦА — названа, а не умолчана: задание со `strategy.matrix` даёт имя на каждое
# сочетание, и статически число не выводится — такое дерево VOID (код 2): число
# проверок матрицы этот предикат не судит. Другие процессы, кроме ci.yaml, этот
# предикат не считает: их в дереве нет; появится второй файл — VOID с его именем.
#
# Коды: 0 — сходится; 1 — находки с координатой; 2 — нет ci.yaml, ведомости,
# разборщика YAML, второй процесс либо матрица.
set -uo pipefail

name="$(basename "${BASH_SOURCE[0]}" .sh)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$here/_lib.sh"
root="$(tooling_gate_workspace_root)" || exit 2

python3 - "$root" "$name" <<'PY'
import os, subprocess, sys
root, name = sys.argv[1], sys.argv[2]
CI, LEDGER, REPO = '.github/workflows/ci.yaml', 'scripts/ci-read-expected.tsv', 'PRO-Robotech/kacho-workspace'


def void(msg):
    print('[VOID] %s — %s' % (name, msg), file=sys.stderr)
    sys.exit(2)


try:
    import yaml
except ImportError:
    void('разборщик YAML недоступен — задания ci.yaml считать нечем')
ls = subprocess.run(['git', '-C', root, 'ls-files', '--cached', '--others', '--exclude-standard', '--',
                     '.github/workflows/*'], capture_output=True, text=True)
wfs = sorted(p for p in ls.stdout.split('\n') if p.endswith(('.yml', '.yaml')))
if ls.returncode != 0 or CI not in wfs:
    void('%s в индексе нет — заданий нет' % CI)
if wfs != [CI]:
    void('процессов %d (%s): предикат считает задания одного ci.yaml' % (len(wfs), ', '.join(wfs)))
try:
    doc = yaml.safe_load(open(os.path.join(root, CI), encoding='utf-8'))
    jobs = doc['jobs']
    assert isinstance(jobs, dict) and jobs
except Exception as e:  # noqa: BLE001 — любая форма отказа разбора есть «судить нечем»
    void('%s не разобран как процесс с заданиями: %s' % (CI, str(e)[:160]))
matrix = sorted(k for k, j in jobs.items() if isinstance(j, dict) and (j.get('strategy') or {}).get('matrix'))
if matrix:
    void('задания с матрицей (%s): число имён проверок статически не выводится' % ', '.join(matrix))
try:
    rows = [(n, l.rstrip('\n').split('\t')) for n, l in enumerate(open(os.path.join(root, LEDGER), encoding='utf-8'), 1)]
except OSError as e:
    void('ведомости %s нет: %s' % (LEDGER, e))

finds = []
mine = [(n, f) for n, f in rows if not (f and f[0].startswith('#')) and len(f) >= 3 and f[0] == REPO and f[1] == 'main']
if len(mine) != 1:
    finds.append('%s: строк «%s main» %d, ждём 1' % (LEDGER, REPO, len(mine)))
else:
    n, f = mine[0]
    if f[2] != str(len(jobs)):
        finds.append('%s:%d: ведомость знает %s проверок «%s main», конвейер %s производит %d заданий — '
                     'число строки менять тем же изменением, что и состав заданий' % (LEDGER, n, f[2], REPO, CI, len(jobs)))

shards = 0
for k in sorted(jobs):
    head, sep, tail = k.rpartition('-shard-')
    if not sep or not tail.isdigit():
        continue
    shards += 1
    agg = jobs.get(head)
    if not isinstance(agg, dict):
        finds.append('%s: шард «%s» без задания-свода «%s»' % (CI, k, head))
        continue
    needs = agg.get('needs') or []
    needs = [needs] if isinstance(needs, str) else list(needs)
    if k not in needs:
        finds.append('%s: шард «%s» не входит в needs свода «%s» — свод его не судит' % (CI, k, head))
    if 'always()' not in str(agg.get('if', '')):
        finds.append('%s: у свода «%s» нет if: always() — красный шард даёт своду skipped' % (CI, head))

ctx = {k: str((j or {}).get('name') or k) for k, j in jobs.items()}
for a, ca in sorted(ctx.items()):
    for b, cb in sorted(ctx.items()):
        if a != b and cb.startswith(ca):
            finds.append('%s: имя контекста задания «%s» («%s») начинается с имени контекста «%s» — '
                         'сверка по префиксу засчитала бы одно за другое' % (CI, b, cb, ca))

print('[CENSUS] %s: заданий в %s %d, шардов %d; строк ведомости «%s main» %d, число %s'
      % (name, CI, len(jobs), shards, REPO, len(mine), mine[0][1][2] if len(mine) == 1 else '—'))
for f in finds:
    print('[FAIL] %s — %s' % (name, f), file=sys.stderr)
if finds:
    sys.exit(1)
print('[PASS] %s — ведомость о стволе воркспейса равна числу заданий, шарды сведены в свой контекст' % name)
PY
