#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# prove.sh — доказательство return-guard ИНЪЕКЦИЕЙ (ws#1030): хук исполняется
# настоящим входом SubagentStop (JSON на stdin той формы, что харнесс подал в опыте
# 2026-10-12, Claude Code 2.1.295), и проба сверяет исход и текст.
#
#   · отказ: дословные последние сообщения четырёх полос сессии 2026-10-12 («Waiting
#     for events.» и др.), блок без статуса, статус вне словаря, блок не последний,
#     пустое сообщение — JSON decision=block, причина названа, правило несёт
#     «Monitor» и статус «идёт»;
#   · законный близнец — пропуск без слова: блок со статусом «готово» и «идёт»,
#     агент шаблона волны (путь /subagents/workflows/, поля сообщения нет), встроенный
#     агент без определения, событие Stop главного потока;
#   · второе завершение подряд (stop_hook_active) — пропуск, но systemMessage
#     «недействителен»: отказ по кругу без предела не заводится;
#   · поломка — код 0 и «СЛОМАН» (guard.py бросает, его нет, нет поля сообщения у
#     исполнителя, нет каталога определений);
#   · мутанты guard.py (по одной правке) обязаны изменить исход на настоящем входе.
# Коды: 0 — все утверждения сошлись; 1 — нет; 2 — нет python3 (вердикта нет).
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$HOOK_DIR/../.." && pwd)"
HOOK="$HOOK_DIR/return-guard.sh"
GUARD="$HOOK_DIR/return-guard/guard.py"
command -v python3 > /dev/null 2>&1 || { echo "[VOID] return-guard: нет python3" >&2; exit 2; }
[ -f "$ROOT/.claude/agents/qa-test-engineer.md" ] || { echo "[VOID] return-guard: нет определения qa-test-engineer в $ROOT" >&2; exit 2; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0; denied=0; passed=0; muts=0
assert() {
    if [ "$1" = "$2" ]; then echo "  [OK]   $3"; pass=$((pass + 1))
    else echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; fail=$((fail + 1)); fi
}
# ev <agent_type> <сообщение|__NONE__> [путь стенограммы] [stop_hook_active] [событие]
ev() {
    python3 -c '
import json, sys
kind, msg, path, active, name = sys.argv[1:6]
d = {"session_id": "s", "transcript_path": "/x/s.jsonl", "cwd": "/tmp", "permission_mode": "default",
     "agent_id": "a1", "agent_type": kind, "hook_event_name": name, "stop_hook_active": active == "1",
     "agent_transcript_path": path, "background_tasks": [], "session_crons": []}
if msg != "__NONE__":
    d["last_assistant_message"] = msg
if name == "Stop":
    for k in ("agent_id", "agent_transcript_path"):
        d.pop(k)
    if not kind:
        d.pop("agent_type")
print(json.dumps(d, ensure_ascii=False))' "$1" "$2" "${3:-/x/s/subagents/agent-a1.jsonl}" "${4:-0}" "${5:-SubagentStop}" > "$WORK/in.json"
}
# run <hook> [корень] — исход по выводу: block | pass | invalid (systemMessage без СЛОМАН) | broken | other
run() {
    local rc
    CLAUDE_PROJECT_DIR="${2:-$ROOT}" bash "$1" < "$WORK/in.json" > "$WORK/out" 2> "$WORK/err"; rc=$?
    python3 - "$WORK/out" "$rc" <<'PY'
import json, sys
s, rc = open(sys.argv[1], encoding='utf-8').read().strip(), sys.argv[2]
if rc != '0':
    print('rc' + rc); sys.exit()
if not s:
    print('pass'); sys.exit()
try:
    d = json.loads(s)
except Exception:
    print('other'); sys.exit()
if d.get('decision') == 'block':
    print('block')
elif 'СЛОМАН' in d.get('systemMessage', ''):
    print('broken')
elif 'недействителен' in d.get('systemMessage', ''):
    print('invalid')
else:
    print('other')
PY
}
reason_has() { python3 -c 'import json,sys; print("да" if sys.argv[2] in json.load(open(sys.argv[1])).get("reason","") else "нет")' "$WORK/out" "$1" 2>/dev/null || echo нет; }
# denies <агент> <ожидаемая причина> <сообщение>
denies() {
    ev "$1" "$3"
    local got; got="$(run "$HOOK")"
    assert "block да да да" "$got $(reason_has "$2") $(reason_has 'Monitor') $(reason_has 'статусом «идёт»')" "отказ ($2): $(printf '%s' "$3" | tr '\n' ' ' | head -c 80)"
    denied=$((denied + 1))
}
passes() {
    local got; got="$(run "$HOOK" "${2:-$ROOT}")"
    assert "pass" "$got" "пропуск без слова: $1"
    passed=$((passed + 1))
}

NOHEAD='нет строки «### ВОЗВРАТ»'
NOST='нет строки «- статус: …»'
BADST='вне словаря контракта'
NOTLAST='блок не последний'
OK_DONE=$'Сделано.\n\n### ВОЗВРАТ\n- статус: готово\n- вердикт: —\n- исход проверок: зелёных 3 · красных 0 · не выполнилось 0'
OK_RUN=$'Прогон отсоединён.\n\n### ВОЗВРАТ\n- статус: идёт\n- факты: pid 4242, журнал /ws/tmp/r.log, срок 12:40'

echo "== отказ: последние сообщения полос сессии 2026-10-12 и родственные формы"
denies tooling-maintainer "$NOHEAD" 'Waiting for events.'
denies tooling-maintainer "$NOHEAD" "I'll wait for the monitor notification."
denies qa-test-engineer   "$NOHEAD" 'Waiting for run 2 to finish (monitor armed on the run log).'
denies qa-test-engineer   "$NOHEAD" 'Waiting for the Monitor event…'
denies go-implementer     "$NOHEAD" ''
denies go-implementer     "$NOHEAD" 'Верну ВОЗВРАТ, когда придёт событие.'
denies go-implementer     "$NOST"   $'### ВОЗВРАТ\n- вердикт: —'
denies go-implementer     "$NOHEAD" $'Верну ВОЗВРАТ позже.\n- статус: готово'
denies go-implementer     "$BADST"  $'### ВОЗВРАТ\n- статус: жду монитор'
denies go-implementer     "$NOTLAST" $'### ВОЗВРАТ\n- статус: готово\n\n## Дальше\nЖду событие Monitor.'

echo "== законные близнецы — пропуск без слова"
ev go-implementer "$OK_DONE";                                  passes 'блок со статусом «готово»'
ev qa-test-engineer "$OK_RUN";                                 passes 'блок со статусом «идёт» (pid, журнал, срок)'
ev tooling-maintainer $'Работа.\n### ВОЗВРАТ\n- статус: блокер\n- факты: —'; passes 'блок со статусом «блокер»'
ev git-operator __NONE__ /x/s/subagents/workflows/wf_1/agent-a1.jsonl; passes 'агент шаблона волны: поля схемы, сообщения нет'
ev git-operator 'Waiting.' /x/s/subagents/workflows/wf_1/agent-a1.jsonl; passes 'агент шаблона волны с текстом — судит шаблон'
ev general-purpose 'Waiting for events.';                      passes 'встроенный агент без определения в .claude/agents/'
ev dispatcher 'Waiting for events.';                           passes 'dispatcher — главный поток, не сабагент'
ev '../agents/qa-test-engineer' 'Waiting.';                    passes 'тип агента вне формы имени — не путь к определению'
ev '' 'Waiting for events.' '' 0 Stop;                         passes 'событие Stop главного потока'
ev qa-test-engineer 'Waiting for events.' '' 0 Stop;           passes 'Stop сессии `claude --agent qa-test-engineer`: главный поток говорит с человеком'

echo "== второе завершение подряд — пропуск с громким «недействителен», не отказ по кругу"
ev qa-test-engineer 'Waiting for events.' /x/s/subagents/agent-a1.jsonl 1
assert invalid "$(run "$HOOK")" "stop_hook_active без блока — пропуск, итог назван недействительным"
ev qa-test-engineer "$OK_DONE" /x/s/subagents/agent-a1.jsonl 1
assert pass "$(run "$HOOK")" "stop_hook_active с блоком — пропуск без слова"

echo "== поломка — код 0 и «СЛОМАН», а не отказ"
ev qa-test-engineer __NONE__
assert broken "$(run "$HOOK")" "у исполнителя нет поля last_assistant_message"
mkdir -p "$WORK/empty"
ev qa-test-engineer 'Waiting.'
assert broken "$(run "$HOOK" "$WORK/empty")" "нет каталога .claude/agents в корне"
mkdir -p "$WORK/broken/return-guard"
cp "$HOOK" "$WORK/broken/return-guard.sh"
printf 'raise RuntimeError("проба")\n' > "$WORK/broken/return-guard/guard.py"
assert broken "$(run "$WORK/broken/return-guard.sh")" "guard.py бросает"
rm -rf "$WORK/broken/return-guard"
assert broken "$(run "$WORK/broken/return-guard.sh")" "guard.py нет"
printf 'not json' > "$WORK/in.json"
assert broken "$(run "$HOOK")" "вход не JSON"

echo "== мутанты guard.py — обязаны изменить исход"
# mutant <имя> <было> <стало> — затем ev; исход мутанта обязан отличаться от исходного.
mutant() {
    local d="$WORK/m$muts"
    mkdir -p "$d/return-guard"
    cp "$HOOK" "$d/return-guard.sh"
    if ! python3 - "$GUARD" "$d/return-guard/guard.py" "$2" "$3" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
if s.count(a) != 1:
    sys.exit(1)
open(dst, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
    then echo "  [FAIL] мутант «$1»: образец не найден в guard.py" >&2; fail=$((fail + 1)); muts=$((muts + 1)); return; fi
    local want got
    want="$(run "$HOOK")"; got="$(run "$d/return-guard.sh")"
    if [ "$want" != "$got" ]; then echo "  [OK]   мутант «$1» красный: $want → $got"; pass=$((pass + 1))
    else echo "  [FAIL] мутант «$1» выжил: $want → $got" >&2; fail=$((fail + 1)); fi
    muts=$((muts + 1))
}
ev qa-test-engineer "$OK_RUN"
mutant "«идёт» вне словаря"          "STATUSES = ('готово', 'идёт', " "STATUSES = ('готово', "
ev qa-test-engineer 'Waiting for events.'
mutant "отказ не выдаётся"           "    out({'decision': 'block'," "    sys.exit(0)
    out({'decision': 'block',"
ev go-implementer $'Верну ВОЗВРАТ позже.\n- статус: готово'
mutant "заголовок ВОЗВРАТ — любое слово" "HEAD = re.compile(r'^\s*###\s+ВОЗВРАТ\s*\$')" "HEAD = re.compile(r'.*ВОЗВРАТ')"
ev go-implementer $'### ВОЗВРАТ\n- статус: готово\n\n## Дальше\nЖду событие Monitor.'
mutant "блок не обязан быть последним" "    if any(HEADING.match(l) for l in tail):" "    if False:"
ev go-implementer $'### ВОЗВРАТ\n- вердикт: —'
mutant "строка статуса не обязательна" "    if not st:
        return" "    if not st:
        return None
        return"
ev go-implementer $'### ВОЗВРАТ\n- статус: жду монитор'
mutant "статус не сверяется со словарём" "    if st[0] not in STATUSES:" "    if False:"
ev git-operator __NONE__ /x/s/subagents/workflows/wf_1/agent-a1.jsonl
mutant "шаблон волны судится"        "    if WORKFLOW_PATH in (ev.get('agent_transcript_path') or ''):" "    if False:"
ev general-purpose 'Waiting for events.'
mutant "встроенный агент судится"     "            or not os.path.isfile(os.path.join(adir, kind + '.md')):" "            or False:"
ev qa-test-engineer 'Waiting for events.' /x/s/subagents/agent-a1.jsonl 1
mutant "отказ по кругу"               "    if ev.get('stop_hook_active'):" "    if False:"
ev qa-test-engineer 'Waiting for events.' '' 0 Stop
mutant "Stop главного потока судится" "    if ev.get('hook_event_name') != 'SubagentStop':" "    if False:"

echo "[CENSUS] return-guard: утверждений $((pass + fail)), сошлось $pass, разошлось $fail; отказов проверено $denied, пропусков $passed, мутантов $muts"
# Ноль утверждений — не «все сошлись», а «ничего не проверено».
[ $((pass + fail)) -gt 0 ] || { echo "[VOID] return-guard: утверждений ноль — проверять оказалось нечего" >&2; exit 2; }
[ "$fail" -eq 0 ]
