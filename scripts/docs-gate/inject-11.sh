#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: Apache-2.0
#
# inject-11.sh — доказательство того, что check-10-review-round-row СПОСОБЕН упасть и
# способен смолчать (ws#1273: строка круга в «Истории review» до нового отпечатка).
#
# ВХОД НАСТОЯЩИЙ. Песочница — живая приёмка дерева и её живые записи ревью прошлых кругов
# (координаты выводятся обходом `git ls-files`, первая приёмка, у которой каждый прошлый круг
# назван строкой). Запись о нынешней редакции в песочницу не кладётся: правка документа
# сделала бы её прошлой, и красное пришло бы от соседа.
#
# Оси (одна правка против законного близнеца):
#   A' живой документ и записи прошлых кругов, строки стоят → 0;
#   A  из документа снят отпечаток ОДНОЙ записи (строка круга потеряна) → 1, находка
#      одна и называет документ и запись;
#   B  запись о НЫНЕШНЕЙ редакции без строки (текущий круг) → 0, счёт текущих в переписи;
#   C' потерянная строка названа ведомостью → 0, счёт ведомости в переписи;
#   C  строка ведомости при стоящей строке круга (исключать нечего) → 1, «ничего не исключает»;
#   E  YAML без subject.sha256 рядом (состояние публикации) → 0, счётом «не записей ревью»;
#   F  запись не разбирается как YAML → 1;
#   V  записей ревью нет → 2, [VOID].
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ws_root="$(cd "$here/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/proofs.sh
. "$here/../lib/proofs.sh"
proof_own_environment
box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT
pass=0 fail=0

# ── Предмет выводится обходом: приёмка, у которой прошлые круги названы строками ──
pick="$(cd "$ws_root" && python3 - <<'PY'
import hashlib, os, re, subprocess, yaml
by = {}
for f in subprocess.run(["git", "ls-files", "docs/specs/reviews/*.yaml"], capture_output=True, text=True).stdout.split():
    p = f.split("/")
    if len(p) == 5:
        by.setdefault(p[3], []).append(f)
for stem in sorted(by):
    d = "docs/specs/%s.md" % stem
    if not os.path.isfile(d):
        continue
    raw = open(d, "rb").read(); cur = hashlib.sha256(raw).hexdigest(); txt = raw.decode("utf-8", "replace")
    past = []
    for r in by[stem]:
        y = yaml.safe_load(open(r, encoding="utf-8"))
        s = ((y or {}).get("subject") or {}).get("sha256") if isinstance(y, dict) and isinstance(y.get("subject"), dict) else None
        if isinstance(s, str) and re.match(r"^[0-9a-f]{64}$", s) and s != cur:
            past.append((r, s))
    if past and all(s in txt for _, s in past):
        print(stem); [print(r, s) for r, s in past]; break
PY
)"
stem="$(head -1 <<< "$pick")"
if [ -z "$stem" ]; then
    echo "НЕ ВЫПОЛНИЛОСЬ: в дереве нет приёмки, у которой прошлые круги названы строками, — инъекции не на чем" >&2
    exit 3
fi
mapfile -t past < <(tail -n +2 <<< "$pick")
read -r rec1 sha1 <<< "${past[0]}"
echo "предмет: docs/specs/$stem.md, прошлых кругов ${#past[@]}, снимаемая строка — $rec1"

# mk <имя> — песочница: git-репозиторий, живой документ, записи прошлых кругов, пустая ведомость.
mk() {
    local d="$box/$1" x r
    mkdir -p "$d/docs/specs/reviews/$stem" "$d/scripts/docs-gate"
    git -C "$d" init -q
    cp "$ws_root/docs/specs/$stem.md" "$d/docs/specs/"
    for x in "${past[@]}"; do read -r r _ <<< "$x"; cp "$ws_root/$r" "$d/$r"; done
    printf '# ведомость песочницы\n' > "$d/scripts/docs-gate/review-round-row-baseline.txt"
    echo "$d"
}
run() { DOCS_GATE_ROOT="$1" python3 "$here/check-10-review-round-row.py" 2>&1; }
assert() { # <ось> <код> <подстрока> <вывод> <код вывода>
    if [ "$5" = "$2" ] && grep -qF -- "$3" <<< "$4"; then echo "  ok   $1"; pass=$((pass + 1))
    else echo "  FAIL $1: код $5 (ожидался $2); искали «$3»"; printf '       | %s\n' "${4//$'\n'/$'\n'       | }"; fail=$((fail + 1)); fi
}
drop_row() { python3 -c 'import sys; p,s=sys.argv[1:]; t=open(p,encoding="utf-8").read(); open(p,"w",encoding="utf-8").write(t.replace(s,""))' "$1/docs/specs/$stem.md" "$sha1"; }

d="$(mk a2)"; out="$(run "$d")"; rc=$?
assert "A' строки прошлых кругов стоят" 0 "находок 0" "$out" "$rc"

d="$(mk a)"; drop_row "$d"; out="$(run "$d")"; rc=$?
assert "A  строка круга потеряна" 1 "строки круга нет — запись $rec1" "$out" "$rc"
assert "A  находка одна — краснеет лишь снятое" 1 "находок 1;" "$out" "$rc"

d="$(mk b)"; cur="$(sha256sum "$d/docs/specs/$stem.md" | cut -c1-64)"
printf 'reviewer_role: acceptance-reviewer\nverdict: APPROVED\nround: 9\nsubject:\n  path: docs/specs/%s.md\n  sha256: "%s"\n' "$stem" "$cur" > "$d/docs/specs/reviews/$stem/$cur.yaml"
out="$(run "$d")"; rc=$?
assert "B  текущий круг без строки — законно" 0 "текущих кругов 1" "$out" "$rc"

d="$(mk c2)"; drop_row "$d"; echo "$stem $sha1" >> "$d/scripts/docs-gate/review-round-row-baseline.txt"; out="$(run "$d")"; rc=$?
assert "C' потерянная строка в ведомости" 0 "в ведомости 1" "$out" "$rc"

d="$(mk c)"; echo "$stem $sha1" >> "$d/scripts/docs-gate/review-round-row-baseline.txt"; out="$(run "$d")"; rc=$?
assert "C  ведомость без предмета" 1 "ничего не исключает" "$out" "$rc"

d="$(mk e)"; printf 'state: published\n' > "$d/docs/specs/reviews/$stem/PUBLICATION-STATE.yaml"; out="$(run "$d")"; rc=$?
assert "E  YAML без subject.sha256 — счётом" 0 "не записей ревью 1" "$out" "$rc"

d="$(mk f)"; printf 'subject: [\n' > "$d/docs/specs/reviews/$stem/broken.yaml"; out="$(run "$d")"; rc=$?
assert "F  запись не разбирается" 1 "не разбирается как YAML" "$out" "$rc"

d="$box/v"; mkdir -p "$d/docs/specs"; git -C "$d" init -q; cp "$ws_root/docs/specs/$stem.md" "$d/docs/specs/"; out="$(run "$d")"; rc=$?
assert "V  записей нет — без предмета" 2 "[VOID]" "$out" "$rc"

echo "инъекция check-10: утверждений $((pass + fail)), пройдено $pass, провалено $fail"
[ "$fail" -eq 0 ]
