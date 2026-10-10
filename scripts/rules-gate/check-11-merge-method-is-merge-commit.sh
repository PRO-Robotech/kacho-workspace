#!/usr/bin/env bash
# check-11 — КОРПУС НЕ ПРЕДПИСЫВАЕТ ВЛИВАНИЕ СХЛОПЫВАНИЕМ ИЛИ ПЕРЕБАЗИРОВАНИЕМ.
#
# Предмет: способ вливания — коммит слияния; сквоша и rebase опубликованного нет
# (решение владельца 2026-09-22, подтверждено 2026-10-06; `git-issues.md`
# запись `gi-merge-method`). Хостинг это держит сам: `allow_squash_merge=false`,
# и `gh pr merge --squash` отклоняется сервером (2026-10-10: запрос отклонён при
# `--squash`, влит `--merge`). Но корпус, говорящий исполнителю «только
# `--squash`», стоит исполнителю круга: команда падает, полоса разбирается,
# почему, и ровно этим путём `dispatcher.md` §7 и §12 держали отменённую норму
# после решения о её отмене (ws#994).
#
# ЧТО СУДИТСЯ — ФОРМА КОМАНДЫ, А НЕ СЛОВО. Находка — строка, где команда
# вливания несёт способ схлопывания или перебазирования:
#   * `gh pr merge … --squash | -s | --rebase | -r`;
#   * `git merge … --squash`.
# У `git merge` ключ `-s` — СТРАТЕГИЯ (`-s ours`), а не схлопывание, и он законен.
# Слово «squash» вне команды — законный близнец: красная колонка правила
# («red: … `--squash`»), запрет в форме задания («нельзя … squash»), пересказ
# истории. Судить слово значило бы краснеть на самом запрете.
#
# Область — `scripts/rules-gate/corpus_scope.py` (одна на check-11 и check-12);
# архив `.claude/backup/` вне её намеренно — там отменённая норма лежит с датой.
#
# Вердикт — в КОДЕ ВЫХОДА: 0 молчит, 1 находка, 2 без предмета (`[VOID]`).
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(python3 "$SELF_DIR/../lib/gate_root.py" RULES_GATE_ROOT "${BASH_SOURCE[0]}")" || exit 2
cd "$root" 2>/dev/null || {
    echo "[VOID] check-11-merge-method-is-merge-commit — корень «$root» не открывается; обходить нечего" >&2
    exit 2
}

python3 - "$root" "$SELF_DIR" <<'PY'
import re, sys
root, here = sys.argv[1], sys.argv[2]
sys.path.insert(0, here)
import corpus_scope

rels = corpus_scope.files(root)
if rels is None:
    print("[VOID] check-11-merge-method-is-merge-commit — корень %s не git-репозиторий: "
          "область выводится из индекса, а его нет" % root)
    sys.exit(2)
if not rels:
    print("[VOID] check-11-merge-method-is-merge-commit — область корпуса пуста "
          "(CLAUDE.md, .claude/**, scripts/*precheck*.sh, scripts/merge-readiness.sh): "
          "судить нечего, и это не «находок 0»")
    sys.exit(2)

# Граница токена: пробел, обратная кавычка, кавычка, начало/конец строки.
B = r"(?:^|(?<=[\s`'\"(]))"
E = r"(?=$|[\s`'\")])"
GH = re.compile(r"\bgh\s+pr\s+merge\b(?P<tail>[^\n]*)")
GH_BAD = re.compile(B + r"(--squash|-s|--rebase|-r)" + E)
GIT = re.compile(r"\bgit\s+merge\b(?P<tail>[^\n]*)")
GIT_BAD = re.compile(B + r"(--squash)" + E)

n_lines = n_cmd = 0
finds = []
for rel in rels:
    for i, line in enumerate(corpus_scope.lines(root, rel), 1):
        n_lines += 1
        for rx, bad, name in ((GH, GH_BAD, "gh pr merge"), (GIT, GIT_BAD, "git merge")):
            for m in rx.finditer(line):
                n_cmd += 1
                # Хвост команды — до конца код-спана, если команда в нём стоит:
                # ключ за пределами спана командой не является.
                tail = m.group("tail")
                tick = tail.find("`")
                if tick >= 0:
                    tail = tail[:tick]
                hit = bad.search(tail)
                if hit:
                    finds.append((rel, i, name, hit.group(1)))

for rel, i, name, key in finds:
    print("КРАСНОЕ ВЛИВАНИЕ НЕ СЛИЯНИЕМ %s:%d — `%s %s` предписывает способ, которого "
          "нет: вливание — коммитом слияния (`--merge`), сквоша и rebase опубликованного "
          "нет (решение владельца 2026-09-22; хостинг отклоняет squash)" % (rel, i, name, key))
print("корень %s; осмотрено: файлов %d, строк %d, команд вливания %d; находок %d"
      % (root, len(rels), n_lines, n_cmd, len(finds)))
sys.exit(1 if finds else 0)
PY
