#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# inject.sh — доказательство того, что проверки набора push-gate СПОСОБНЫ упасть
# и способны смолчать.
#
# Вход — НАСТОЯЩИЕ файлы предмета из этого дерева, скопированные во временный
# корень; дефект вносится ОДНОЙ заменой строки в одном файле и возвращает ровно
# то поведение, ради которого проверка писалась (переходник v1 с успехом без
# адресата, хук без суждения по диапазону и т.д.). Проверка зовётся с
# `PUSH_GATE_SUBJECT=<корень>` и обязана выйти 1. Законный близнец — та же копия
# без замены — обязан выйти 0: проверка, красная и на исправном, не доказывает
# ничего.
#
# Замена, не нашедшая своей строки, — ПРОВАЛ инъекции, а не пропуск: иначе
# переписанный предмет молча превратил бы пробу в прогон исправного дерева.
#
# Три исхода: 0 — все мутанты убиты, все близнецы молчат; 1 — нет; 2 — предмета
# нет (набор пуст, файла предмета нет).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Файлы предмета, которые проверки набора читают. Перечень — ПРЕДМЕТ, а не
# выбор: проверка берёт из `PUSH_GATE_SUBJECT` ровно их, и недостающий файл
# в копии дал бы беспредметный прогон вместо инъекции.
SUBJECT_FILES=(
    scripts/hooks/install.sh
    scripts/hooks/pre-push
    scripts/cla-gate/cla.py
    scripts/push-verified.sh
    scripts/push-verified-inject.sh
    scripts/preservation-proof.sh
    scripts/preservation-proof-inject.sh
)

copy_subject() {  # <корень>
    local f
    for f in "${SUBJECT_FILES[@]}"; do
        [ -e "$WS/$f" ] || { echo "[VOID] inject — файла предмета $f в дереве нет" >&2; return 2; }
        mkdir -p "$1/$(dirname "$f")"
        cp -p "$WS/$f" "$1/$f"
    done
}

# МУТАНТЫ: <проверка>|<файл>|<что роняет — одной фразой>, а замена — в python
# ниже по номеру. Строка-источник цитируется ДОСЛОВНО из предмета.
mutant_descr=(
    "check-01-hook-stub-refuses-without-target|scripts/hooks/install.sh|переходник без адресата снова выходит УСПЕХОМ (v1)"
    "check-01-hook-stub-refuses-without-target|scripts/hooks/install.sh|check снова называет наш переходник без адресата «посторонним»"
    "check-02-push-range-judges-identities|scripts/hooks/pre-push|хук не зовёт суждение по диапазону — подпись не судится"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|суждение отправки не судит коммиттера"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|освобождённая личность подписывает отправляемый коммит"
    "check-03-neighbour-homes-are-derived|scripts/hooks/pre-push|выведенный дом не передаётся наборам — копия снова без предмета"
    "check-04-push-verdict-comes-from-the-remote|scripts/push-verified.sh|вердикт отправки снова берётся из кода команды"
    "check-04-push-verdict-comes-from-the-remote|scripts/hooks/install.sh|установщик перебивает чужой транспорт своим keepalive"
    "check-05-preservation-denominator-is-the-lane|scripts/preservation-proof.sh|знаменатель снова — файлы головного коммита"
    "check-02-push-range-judges-identities|scripts/hooks/pre-push|исход 2 суждения («судить нечем») пропускает отправку (M1)"
    "check-04-push-verdict-comes-from-the-remote|scripts/push-verified.sh|постусловие снова спрашивает url, а не pushurl"
    "check-05-preservation-denominator-is-the-lane|scripts/preservation-proof.sh|переименование снова склеивает пути знаменателя"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|ключ атрибуции снова судится только по адресу"
    "check-02-push-range-judges-identities|scripts/hooks/pre-push|разборщика нет — отправка проходит, «судить нечем» стало проходом (MP1)"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|опубликованное снова пополнено ссылками отслеживания, а не только сервером отправки"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|опубликованное на сервере отправки не вычитается — отправка по URL судит всю историю"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|ведомость снова из рабочего дерева, а не из ствола"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|коммиттер-сервер из committers снова не покрыт при отправке"
    "check-02-push-range-judges-identities|scripts/hooks/pre-push|строки отправки снова читаются с пределом по времени и при вызове от git"
    "check-05-preservation-denominator-is-the-lane|scripts/preservation-proof.sh|двоичное и подмодуль снова не сверяются объектом"
    "check-05-preservation-denominator-is-the-lane|scripts/preservation-proof.sh|режим, сменённый полосой, снова не сверяется"
    "check-05-preservation-denominator-is-the-lane|scripts/preservation-proof.sh|снятая строка снова булева: снятие одного из повторов невидимо"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|ведомость снова читается ДО вычитания опубликованного — тег на опубликованное отказывает (круг 2, N1)"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|ведомость снова из ОТПРАВЛЯЕМОЙ ревизии, а не из ствола — изменение само себя допускает (круг 3)"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|флаг первой посадки снова без сужения owners до user.email копии"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|ревизия без ведомости снова проходит под флагом первой посадки"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|объект аннотированного тега снова не судится (круг 3)"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|ствол без ведомости снова не «условие не создано», а проход без флага"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|лечение первой посадки снова печатает повторную отправку без флага"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|лечение ключа снова не снимает ключ — напечатанная команда не исполняет обещанного"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|отправка отказывает своей личности — положительная половина не должна стать «без предмета» (круг 1, находка 5)"
    "check-01-hook-stub-refuses-without-target|scripts/hooks/pre-push|хук отказывает каждой судимой отправке — положительная половина не должна стать «без предмета» (круг 1, находка 5)"
    "check-01-hook-stub-refuses-without-target|scripts/hooks/install.sh|установщик предмета отказывает после провязки — сборка песочницы не должна стать «без предмета»"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|лечение ключа переподписывает коммиты диапазона личностью копии (круг 1, находка 1)"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|лечение ключа снимает и строку соавтора вне ведомости — его вклад скрыт (круг 1, находка 1)"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|лечение печатает перепись и для находки личности (круг 1, находка 1)"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|команда переписи снова печатается при опубликованном в диапазоне (круг 1, находка 3)"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|лечение тега снова не снимает ключ из сообщения (круг 1, находка 4)"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|лечение тега пересоздаёт тег личностью копии (круг 1, находка 1)"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|автора тега снова покрывают committers (круг 1, находка 2)"
    "check-02-push-range-judges-identities|scripts/cla-gate/cla.py|автора тега снова покрывают waivers (круг 1, находка 2)"
)

apply_mutant() {  # <номер> <корень> — 0 применено, 1 строка не найдена
    python3 - "$1" "$2" <<'PY'
import sys
n, root = int(sys.argv[1]), sys.argv[2]
M = [
    ("scripts/hooks/install.sh",
     '        echo "  Обход только явный, и он называется в отчёте: $bypass"\n    } >&2\n    exit 1\n',
     '        echo "  Обход только явный, и он называется в отчёте: $bypass"\n    } >&2\n    exit 0\n'),
    ("scripts/hooks/install.sh",
     '    if [ -n "$v" ]; then\n        orphans+=("$b (v$v)")\n',
     '    if false; then\n        orphans+=("$b (v$v)")\n'),
    ("scripts/hooks/pre-push",
     'if [ "${#push_lines[@]}" -gt 0 ]; then\n    judge=',
     'if false; then\n    judge='),
    ("scripts/cla-gate/cla.py",
     '        ROLE_COMMITTER: ("owners", "signatories", "committers"),\n',
     ''),
    ("scripts/cla-gate/cla.py",
     '    "push": {\n        ROLE_AUTHOR: ("owners", "signatories"),\n',
     '    "push": {\n        ROLE_AUTHOR: ("owners", "signatories", "waivers"),\n'),
    ("scripts/hooks/pre-push",
     '        export "$var=$d"\n',
     '        : "$var=$d"\n'),
    ("scripts/push-verified.sh",
     'mapfile -t push_urls < <(git remote get-url --push --all "$remote" 2>/dev/null)\n',
     '[ "$push_rc" = 0 ] && { echo "push-verified: ПОДТВЕРЖДЕНО — по коду команды"; exit 0; }\nmapfile -t push_urls < <(git remote get-url --push --all "$remote" 2>/dev/null)\n'),
    ("scripts/hooks/install.sh",
     'if [ "${ka_now%%|*}" = none ]; then\n',
     'if [ "${ka_now%%|*}" != set ]; then\n'),
    ("scripts/preservation-proof.sh",
     'mapfile -d \'\' -t paths < <(gdiff -z --name-only "$mb..$head" 2>/dev/null)\n',
     'mapfile -d \'\' -t paths < <(git diff-tree -z --no-commit-id --name-only -r --no-renames --root "$head" 2>/dev/null)\n'),
    ("scripts/hooks/pre-push",
     '    if [ "$judged" -ne 0 ]; then\n',
     '    if [ "$judged" -eq 1 ]; then\n'),
    ("scripts/push-verified.sh",
     'mapfile -t push_urls < <(git remote get-url --push --all "$remote" 2>/dev/null)\n',
     'push_urls=()\n'),
    ("scripts/preservation-proof.sh",
     'gdiff() { git -c color.ui=never diff --no-color --no-ext-diff --no-textconv --no-renames "$@"; }\n',
     'gdiff() { git -c color.ui=never diff --no-color --no-ext-diff --no-textconv "$@"; }\n'),
    ("scripts/cla-gate/cla.py",
     '        if mode != "history":\n            for m in ATTRIBUTION_RE.finditer(r.body):\n',
     '        if False:\n            for m in ATTRIBUTION_RE.finditer(r.body):\n'),
    ("scripts/hooks/pre-push",
     '        echo "  Обход только явный: git push --no-verify" >&2\n        exit 1\n',
     '        echo "  Обход только явный: git push --no-verify" >&2\n        exit 0\n'),
    ("scripts/cla-gate/cla.py",
     '    return sorted(advertised), (head_name or "HEAD", head_sha)\n',
     '    return sorted(advertised | set(git(root, "for-each-ref", "--format=%(objectname)", "refs/remotes/").stdout.split())), (head_name or "HEAD", head_sha)\n'),
    ("scripts/cla-gate/cla.py",
     '        published = set(present(root, advertised))\n',
     '        published = set()\n'),
    ("scripts/cla-gate/cla.py",
     '        led = load_ledger_at(root, tsha, rel)\n',
     '        led = load_ledger(root, rel)\n'),
    ("scripts/cla-gate/cla.py",
     '        ROLE_COMMITTER: ("owners", "signatories", "committers"),\n',
     '        ROLE_COMMITTER: ("owners", "signatories"),\n'),
    ("scripts/hooks/pre-push",
     '    if [ $# -ge 2 ]; then\n',
     '    if false; then\n'),
    ("scripts/preservation-proof.sh",
     '        if [ "$lm" = 160000 ] || [ -n "${binary[$p]:-}" ]; then\n',
     '        if false; then\n'),
    ("scripts/preservation-proof.sh",
     '    if [ "$mm" != "$lm" ]; then\n',
     '    if false; then\n'),
    ("scripts/preservation-proof.sh",
     '                        if (c[2, l] > cap) printf "R\\t%d\\t%d\\t%s\\n", c[2, l], cap, l\n',
     '                        if (c[2, l] > 0 && c[1, l] == 0) printf "R\\t%d\\t%d\\t%s\\n", c[2, l], cap, l\n'),
    ("scripts/cla-gate/cla.py",
     '            if not fresh and not tags:\n                idle += 1\n',
     '            if False:\n                idle += 1\n'),
    ("scripts/cla-gate/cla.py",
     '        led = load_ledger_at(root, tsha, rel)\n',
     '        led = load_ledger_at(root, items[0]["commit"], rel)\n'),
    ("scripts/cla-gate/cla.py",
     '    n["owners"] = {em: e for em, e in led["owners"].items() if own and em == own}\n',
     '    n["owners"] = dict(led["owners"])\n'),
    ("scripts/cla-gate/cla.py",
     '                bad = True\n',
     '                bad = False\n'),
    ("scripts/cla-gate/cla.py",
     '            tags = [t for t in chain if t not in adv]\n',
     '            tags = []\n'),
    ("scripts/cla-gate/cla.py",
     '        if not first:\n            print(head, file=sys.stderr)\n',
     '        if False:\n            print(head, file=sys.stderr)\n'),
    ("scripts/cla-gate/cla.py",
     '        print_cures(root, items, neg, auth, trunk if tblob is not None else None, strip)\n',
     '        print_cures(root, items, neg, auth, trunk, strip)\n'),
    ("scripts/cla-gate/cla.py",
     '                arms = " ".join("%s) sed -E %s ;;" % (',
     '                arms = " ".join("%s) cat %.0s;;" % ('),
    ("scripts/cla-gate/cla.py",
     '    "push": {\n        ROLE_AUTHOR: ("owners", "signatories"),\n',
     '    "push": {\n        ROLE_AUTHOR: ("signatories",),\n'),
    ("scripts/hooks/pre-push",
     '    if [ "$judged" -ne 0 ]; then\n',
     '    if true; then\n'),
    ("scripts/hooks/install.sh",
     'wired=${#installed[@]}\n',
     'exit 1\n'),
    ("scripts/cla-gate/cla.py",
     'git filter-branch -f --msg-filter %s',
     "git filter-branch -f --env-filter 'export GIT_AUTHOR_NAME=$(git config user.name) GIT_AUTHOR_EMAIL=$(git config user.email) GIT_COMMITTER_NAME=$(git config user.name) GIT_COMMITTER_EMAIL=$(git config user.email)' --msg-filter %s"),
    ("scripts/cla-gate/cla.py",
     '    return "/^(claude-session[[:space:]]*:%s)/Id" % coauthor\n',
     '    return "/^(claude-session|co-authored-by)[[:space:]]*:/Id"\n'),
    ("scripts/cla-gate/cla.py",
     '            if strippable_keys(r.body, cov):\n',
     '            if True:\n'),
    ("scripts/cla-gate/cla.py",
     '            if set(span) - set(it["fresh"]):\n',
     '            if False:\n'),
    ("scripts/cla-gate/cla.py",
     '"sed -E %s | GIT_COMMITTER_NAME=%s',
     '"cat %.0s| GIT_COMMITTER_NAME=%s'),
    ("scripts/cla-gate/cla.py",
     'GIT_COMMITTER_NAME=%s GIT_COMMITTER_EMAIL=%s GIT_COMMITTER_DATE=%s "\n                  "git tag',
     'GIT_COMMITTER_NAME%.0s%.0s%.0s= "\n                  "git tag'),
    ("scripts/cla-gate/cla.py",
     '        ROLE_TAGGER: ("owners", "signatories"),\n',
     '        ROLE_TAGGER: ("owners", "signatories", "committers"),\n'),
    ("scripts/cla-gate/cla.py",
     '        ROLE_TAGGER: ("owners", "signatories"),\n',
     '        ROLE_TAGGER: ("owners", "signatories", "waivers"),\n'),
]
path, old, new = M[n]
p = root + "/" + path
s = open(p, encoding="utf-8").read()
if s.count(old) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
}

probes=0; failed=0
checks_seen=()

# ── близнецы: каждая проверка на нетронутой копии молчит ─────────────────────
mapfile -t CHECKS < <(cd "$HERE" && ls check-*.sh 2>/dev/null)
if [ "${#CHECKS[@]}" -eq 0 ]; then
    echo "[VOID] inject — в наборе нет ни одной проверки" >&2
    exit 2
fi
twin="$TMP/twin"
copy_subject "$twin" || exit 2
for c in "${CHECKS[@]}"; do
    probes=$((probes + 1))
    out="$(PUSH_GATE_SUBJECT="$twin" bash "$HERE/$c" 2>&1 </dev/null)"; rc=$?
    if [ "$rc" = 0 ]; then
        echo "[PASS] близнец ${c%.sh}: исправная копия предмета — молчит (код 0)"
    else
        failed=$((failed + 1))
        echo "[FAIL] близнец ${c%.sh}: исправная копия дала код $rc — проверка красна и на исправном" >&2
        printf '%s\n' "$out" | tail -5 | sed 's/^/    | /' >&2
    fi
done

# ── мутанты: каждый обязан быть убит своей проверкой ─────────────────────────
for i in "${!mutant_descr[@]}"; do
    IFS='|' read -r check file what <<<"${mutant_descr[$i]}"
    checks_seen+=("$check")
    probes=$((probes + 1))
    root="$TMP/m$i"
    copy_subject "$root" || exit 2
    if ! apply_mutant "$i" "$root"; then
        failed=$((failed + 1))
        echo "[FAIL] мутант $i ($check): строка-источник в $file не найдена ровно один раз — предмет переписан, инъекция не применилась" >&2
        continue
    fi
    out="$(PUSH_GATE_SUBJECT="$root" bash "$HERE/$check.sh" 2>&1 </dev/null)"; rc=$?
    if [ "$rc" = 1 ]; then
        echo "[PASS] мутант $i убит: $what → $check выходит 1"
    else
        failed=$((failed + 1))
        echo "[FAIL] мутант $i ВЫЖИЛ: $what → $check выходит $rc вместо 1" >&2
        printf '%s\n' "$out" | tail -5 | sed 's/^/    | /' >&2
    fi
done

# У каждой проверки набора есть хотя бы один мутант: проверка без инъекции
# неотличима от проверки, которая упасть не умеет.
for c in "${CHECKS[@]}"; do
    probes=$((probes + 1))
    has=0
    for s in "${checks_seen[@]+"${checks_seen[@]}"}"; do [ "$s.sh" = "$c" ] && has=1; done
    if [ "$has" = 1 ]; then
        echo "[PASS] у ${c%.sh} есть мутант"
    else
        failed=$((failed + 1))
        echo "[FAIL] у ${c%.sh} нет ни одного мутанта — способность упасть не доказана" >&2
    fi
done

echo "[CENSUS] push-gate inject: проверок ${#CHECKS[@]}, мутантов ${#mutant_descr[@]}, проб $probes, провалено $failed"
if [ "$failed" -gt 0 ]; then
    echo "[FAIL] push-gate inject — провалов $failed" >&2
    exit 1
fi
echo "[PASS] push-gate inject — каждая проверка краснеет на своём дефекте и молчит на исправном"
