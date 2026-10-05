#!/usr/bin/env bash
# ЕДИНЫЙ ВХОД доказательств набора rituals: самопробы СПОСОБНЫ упасть (ws#930).
#
# Каждая инъекция — мутант НАСТОЯЩЕГО rituals.py в копии каталога, ровно в одном
# месте (`mutate` требует, чтобы якорь встретился один раз: иначе мутант молча не
# применился бы, и зелёное контроля читалось бы как доказательство). От самопробы
# своего ритуала требуется код 1. Контроль — та же копия без мутации — обязан дать 0
# по всем четырём: иначе красное мутанта пришло бы от соседа, а не от предмета.
#
#   M1 pr-body: Closes без доказательства        → check-01 красная
#   M2 pr-body: предикат атрибуции ослеп          → check-01 красная
#   M3 close-wave: остаток закрыт без доказательства → check-02 красная
#   M4 approval-event: событие без правки блока   → check-03 красная
#   M5 approval-event: публикация до проверки записываемости → check-03 красная
#   M6 vault-trails: состояние закрытой задачи не done → check-04 красная
#   M7 vault-trails: исход vault-gate проглочен   → check-04 красная
#
# Хранилище для check-04 берётся из HEAD настоящего воркспейса (`RITUALS_WS`):
# копия несёт только код ритуалов и их общие зависимости.
# Коды: 0 — все доказательства прошли; 1 — хоть одно нет; 2 — копию не завести.
# shellcheck source-path=SCRIPTDIR
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ws="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)" || { echo "[VOID] rituals/inject — не завёлся каталог" >&2; exit 2; }
trap 'rm -rf "$tmp"' EXIT

# Унаследованный указатель корня (`GATE_ROOT`, `*_GATE_ROOT`) сильнее расположения
# копии: самопроба мутанта судила бы не мутанта. Снимается до первой пробы.
# shellcheck source=../lib/proofs.sh
. "$ws/scripts/lib/proofs.sh"
proof_own_environment

ok=0
bad=0

copy() {
    local d="$tmp/$1"
    mkdir -p "$d/scripts/hooks" "$d/scripts/lib" || return 2
    cp -r "$here" "$d/scripts/rituals" || return 2
    cp "$ws/scripts/hooks/attribution-rule.sh" "$d/scripts/hooks/" || return 2
    cp "$ws/scripts/lib/sandbox-git-home.sh" "$ws/scripts/lib/gate_root.py" "$d/scripts/lib/" || return 2
    printf '%s' "$d/scripts/rituals"
}

# mutate <каталог> <якорь> <замена> — ровно одно вхождение якоря, иначе отказ.
mutate() {
    python3 - "$1/rituals.py" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
n = text.count(old)
if n != 1:
    print("якорь мутанта встречен %d раз(а), а не один: %r" % (n, old), file=sys.stderr)
    sys.exit(2)
open(path, "w", encoding="utf-8").write(text.replace(old, new))
PY
}

run_check() {
    (cd "$tmp" && RITUALS_WS="$ws" python3 "$1/$2" 2>&1)
}

expect() {
    local label="$1" want="$2" got="$3" out="$4"
    if [ "$got" = "$want" ]; then
        echo "[inject OK]   $label (ожидали код $want, получили $got)"
        ok=$((ok + 1))
    else
        echo "[inject FAIL] $label (ожидали код $want, получили $got)" >&2
        printf '%s\n' "$out" | tail -n 15 | sed 's/^/    /' >&2
        bad=$((bad + 1))
    fi
}

# контроль: копия без мутации зелена по всем самопробам
d="$(copy control)" || { echo "[VOID] rituals/inject — копия не заведена" >&2; exit 2; }
for c in check-01-pr-body.py check-02-close-wave.py check-03-approval-event.py check-04-vault-trails.py; do
    out="$(run_check "$d" "$c")"; rc=$?
    expect "контроль $c" 0 "$rc" "$out"
done

# inject <метка> <самопроба> <якорь> <замена>
inject() {
    local label="$1" check="$2" d out rc
    d="$(copy "m$((ok + bad))")" || { expect "$label: копия" 1 2 ""; return; }
    if ! mutate "$d" "$3" "$4"; then
        expect "$label: мутант не применён" 1 2 ""
        return
    fi
    out="$(run_check "$d" "$check")"; rc=$?
    expect "$label" 1 "$rc" "$out"
}

inject "M1 pr-body: Closes без доказательства" check-01-pr-body.py \
    '        proof = dod_proof(repo, n)
        if proof:' \
    '        proof = dod_proof(repo, n) or ("(нет)", "0000000")
        if proof:'
inject "M2 pr-body: атрибуция не видна" check-01-pr-body.py \
    'return p.stdout.strip() or "(пустая строка)"' \
    'return None'
inject "M3 close-wave: остаток закрыт без доказательства" check-02-close-wave.py \
    '(to_close if proof else remainder).append((c, proof))' \
    'to_close.append((c, proof or ("(нет)", "0000000")))'
inject "M4 approval-event: событие без правки блока" check-03-approval-event.py \
    '            fh.write(after)' \
    '            fh.write(before)'
inject "M5 approval-event: публикация до проверки записываемости" check-03-approval-event.py \
    'if not os.access(rec_path, os.W_OK):' \
    'if False:'
inject "M6 vault-trails: закрытая задача не done" check-04-vault-trails.py \
    'status = "wontfix" if it.get("state_reason") == "not_planned" else "done"' \
    'status = "test"'
inject "M7 vault-trails: исход vault-gate проглочен" check-04-vault-trails.py \
    'return gate.returncode if gate.returncode in (OK, REFUSED, UNMET) else REFUSED' \
    'return OK if gate.returncode == REFUSED else gate.returncode'

echo
echo "rituals/inject: доказательств $((ok + bad)), прошло $ok, провалено $bad"
[ "$bad" -eq 0 ]
