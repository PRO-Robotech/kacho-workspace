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
# Возврат check-verifier к ws#930: мутанты, которые прежние пробы пропускали зелёными
# или красили соседним отказом. Самопробы судят отказ по коду И по причине, поэтому
# каждый из них краснеет своей пробой, а не чужой:
#   M8  approval-event: отпечаток документа не сверяется      → check-03
#   M9  approval-event: повтор события не запрещён            → check-03
#   M10 close-wave: перечитывание после действий слепо         → check-02
#   M11 pr-body: закрытая задача с доказательством — Closes    → check-01
#   M12 approval-event: документ записи не сверяется с названным → check-03
#   M13 vault-trails: код генератора указателя проглочен       → check-04
#   M14 approval-event: правка, задевшая другие поля, принята   → check-03
#   M15 approval-event: значение ответа трекера без кавычек     → check-03
#   M16 approval-event: тип отпечатка в записи не судится       → check-03
#   M17 approval-event: правка записи не проверена до публикации → check-03
#   M18 общий распознаватель DoD: маркер посреди прозы засчитан
#       (`scripts/lib/dod_proof.jq` — один на ритуалы, merge-readiness и cascade-census) → check-01
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
    cp "$ws/scripts/lib/sandbox-git-home.sh" "$ws/scripts/lib/gate_root.py" "$ws/scripts/lib/dod_proof.jq" \
        "$d/scripts/lib/" || return 2
    printf '%s' "$d/scripts/rituals"
}

# mutate <файл> <якорь> <замена> — ровно одно вхождение якоря, иначе отказ.
mutate() {
    python3 - "$1" "$2" "$3" <<'PY'
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

# inject <метка> <самопроба> <якорь> <замена> [<файл относительно копии scripts/rituals>]
inject() {
    local label="$1" check="$2" d out rc
    d="$(copy "m$((ok + bad))")" || { expect "$label: копия" 1 2 ""; return; }
    if ! mutate "$d/${5:-rituals.py}" "$3" "$4"; then
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
inject "M8 approval-event: отпечаток не сверяется" check-03-approval-event.py \
    '    if got != want:' \
    '    if False:'
inject "M9 approval-event: повтор не запрещён" check-03-approval-event.py \
    'if ev.get("status") == "performed" or ev.get("published") is True:' \
    'if False:'
inject "M10 close-wave: перечитывание слепо" check-02-close-wave.py \
    'still = [c for c in after if c.get("state") == "open"]' \
    'still = []'
inject "M11 pr-body: закрытая с доказательством — Closes" check-01-pr-body.py \
    '        if it.get("state") != "open":' \
    '        if False:'
inject "M12 approval-event: документ записи не сверяется" check-03-approval-event.py \
    'if subj.get("path") and subj["path"] != doc:' \
    'if False:'
inject "M13 vault-trails: код генератора проглочен" check-04-vault-trails.py \
    'if gen.returncode != 0:' \
    'if False:'
inject "M14 approval-event: задевшая другие поля правка принята" check-03-approval-event.py \
    'if drop(check) != drop(rec):' \
    'if False:'
inject "M15 approval-event: значение ответа трекера без кавычек" check-03-approval-event.py \
    '"  api_url: %s" % q(posted.get("url") or ""),' \
    '"  api_url: %s" % (posted.get("url") or ""),'
inject "M16 approval-event: тип отпечатка не судится" check-03-approval-event.py \
    'if not isinstance(want, str) or not SHA256_RE.match(want):' \
    'if False:'
inject "M17 approval-event: правка не проверена до публикации" check-03-approval-event.py \
    '        raise Refused("%s — событие не публикуется" % e)' \
    '        pass'
inject "M18 dod_proof.jq: маркер посреди прозы засчитан" check-01-pr-body.py \
    '(^|\n)DoD-proof' \
    'DoD-proof' \
    ../lib/dod_proof.jq

echo
echo "rituals/inject: доказательств $((ok + bad)), прошло $ok, провалено $bad"
[ "$bad" -eq 0 ]
