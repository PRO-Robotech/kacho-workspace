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
     '        ROLE_COMMITTER: ("owners", "signatories"),\n',
     ''),
    ("scripts/cla-gate/cla.py",
     '    "push": {\n        ROLE_AUTHOR: ("owners", "signatories", "signoff"),\n',
     '    "push": {\n        ROLE_AUTHOR: ("owners", "signatories", "waivers", "signoff"),\n'),
    ("scripts/hooks/pre-push",
     '        export "$var=$d"\n',
     '        : "$var=$d"\n'),
    ("scripts/push-verified.sh",
     'remote_line="$(git ls-remote "$remote" "refs/heads/$branch" 2>/dev/null)"\n',
     '[ "$push_rc" = 0 ] && { echo "push-verified: ПОДТВЕРЖДЕНО — по коду команды"; exit 0; }\nremote_line="$(git ls-remote "$remote" "refs/heads/$branch" 2>/dev/null)"\n'),
    ("scripts/hooks/install.sh",
     'if [ "${ka_now%%|*}" = none ]; then\n',
     'if [ "${ka_now%%|*}" != set ]; then\n'),
    ("scripts/preservation-proof.sh",
     'mapfile -t paths < <(git diff --name-only "$mb..$head" 2>/dev/null)\n',
     'mapfile -t paths < <(git show --name-only --format= "$head" 2>/dev/null | sed \'/^$/d\')\n'),
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
