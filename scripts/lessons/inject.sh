#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# inject.sh — доказательство сборщика уроков `collect.sh` и хука `lessons-signal.sh`
# ИСПОЛНЕНИЕМ на подложенных журналах (ws#1199). Настоящие журналы и ведомость проба не
# видит и не трогает: всё — во временном каталоге, пути — переменными LESSONS_*.
#
# Пробы (контроль — каждая сходится):
#   сбор        — урок из журнала агента, итога workflow (строкой и полем lesson), главного
#                 потока (строка «урок диспетчера:», упоминание в прозе — не урок), lessons.md
#                 и errors.md волны; «—» — не урок; берётся ПОСЛЕДНИЙ блок ВОЗВРАТ;
#   ключ        — синоним сводит два имени в один класс; урок диспетчера и счётчика волны —
#                 под «оркестровка:»; урок без места — UNKEYED, в классы не идёт;
#   идемпотентность — второй сбор не дописывает ни строки;
#   порог 2     — класс с двумя случаями «нужен механизм», с одним — нет; та же строка из двух
#                 источников — один случай;
#   статусы     — mechanism без #N отвергнут; после mechanism класс не просит механизма;
#                 случай позже landed — «механизм не держит»; открытый старше суток — STALE;
#   хук         — есть что делать: код 2 и строка «📚 УРОКИ», тот же перечень второй раз —
#                 молчит, stop_hook_active — молчит; делать нечего — молчит; журналов нет —
#                 scan код 2, хук — «НЕ СОБРАНЫ».
# Затем мутанты — каждый обязан покраснеть хотя бы одной пробой: урок без ключа принят,
# дубль не схлопнут, порог 3 вместо 2, хук печатает на пустом, повтор после landed не виден,
# взят первый блок ВОЗВРАТ, «журналов нет» выдано за «уроков 0». Мутант, чей фрагмент не
# найден, — отказ пробы (порча, которая не легла, ничего не доказывает).
#
# Коды: 0 — контроль сошёлся и все мутанты покраснели; 1 — нет; 2 — нет python3.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WSR="$(cd "$HERE/../.." && pwd -P)"
command -v python3 > /dev/null 2>&1 || { echo "lessons-inject: VOID — нет python3" >&2; exit 2; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# ── Подложенные журналы ─────────────────────────────────────────────────────
mkfix() {  # mkfix <каталог> <вид: work|idle|empty>
    python3 - "$1" "$2" <<'PY'
import json, os, sys, time
root, kind = sys.argv[1], sys.argv[2]
P, W = os.path.join(root, 'proj'), os.path.join(root, 'waves')
os.makedirs(P, exist_ok=True)
os.makedirs(W, exist_ok=True)
if kind == 'empty':
    sys.exit(0)
now = time.time()
def iso(t):
    return time.strftime('%Y-%m-%dT%H:%M:%S.000Z', time.gmtime(t))
def asst(text, t):
    return json.dumps({'type': 'assistant', 'timestamp': iso(t),
                       'message': {'role': 'assistant', 'stop_reason': 'end_turn',
                                   'content': [{'type': 'text', 'text': text}]}}, ensure_ascii=False)
def ret(lesson):
    return 'итог\n\n### ВОЗВРАТ\n- статус: готово\n- нужен следующий: —\n- урок: %s\n' % lesson
S = os.path.join(P, 'S1', 'subagents')
os.makedirs(os.path.join(S, 'workflows', 'wf_1'), exist_ok=True)
def agent(aid, *texts):
    with open(os.path.join(S, 'agent-%s.jsonl' % aid), 'w') as f:
        f.write(json.dumps({'type': 'user', 'timestamp': iso(now - 4000), 'message': {'role': 'user', 'content': 'задание'}}) + '\n')
        for t in texts:
            f.write(asst(t, now - 3600) + '\n')
if kind == 'idle':
    agent('i1', ret('одиночный класс · место правки'))
    sys.exit(0)
agent('a1', ret('Код 77 в цепочке · heavy-slot'))
agent('a2', ret('«код 77» при отправке · задание полосе'))
agent('a3', ret('—'))
agent('a4', ret('без места вообще'))
agent('a5', '### ВОЗВРАТ\n- урок: первый-блок · не берётся\n\nдоводка\n\n' + ret('второй-блок · берётся'))
# последний блок без строки «урок:» — урока нет, прежний блок не подставляется
agent('a6', '### ВОЗВРАТ\n- урок: прежний-блок · не берётся\n\nдоводка\n\n### ВОЗВРАТ\n- статус: готово\n')
with open(os.path.join(S, 'workflows', 'wf_1', 'journal.jsonl'), 'w') as f:
    f.write(json.dumps({'type': 'launched'}) + '\n')
    f.write(json.dumps({'type': 'result', 'agentId': 'w1', 'result': {'status': 'done', 'lesson': 'head-moved · lane-precheck'}}, ensure_ascii=False) + '\n')
    f.write(json.dumps({'type': 'result', 'agentId': 'w2', 'result': ret('имя ветки kaname · задание')}, ensure_ascii=False) + '\n')
    f.write(json.dumps({'type': 'result', 'agentId': 'w3', 'result': {'status': 'done', 'lesson': '—'}}, ensure_ascii=False) + '\n')
with open(os.path.join(P, 'S1.jsonl'), 'w') as f:
    f.write(asst('ход\n\nурок диспетчера: конвейер не остановлен блокером · база §7\n', now - 3000) + '\n')
    f.write(asst('пишу строки «урок диспетчера: x · y» в ответах', now - 2900) + '\n')
os.makedirs(os.path.join(W, 'wave-9', 'reports'), exist_ok=True)
with open(os.path.join(W, 'wave-9', 'reports', 'lessons.md'), 'w') as f:
    f.write('L1 · имя ветки не по правилу · шаблон задания\n')
    f.write('L2 · head-moved · lane-precheck\n')  # та же строка, что итог w1: один случай
with open(os.path.join(W, 'wave-9', 'errors.md'), 'w') as f:
    f.write('# Ошибки оркестровки волны 9\n\n| когда (UTC) | полоса | шаг | класс | часы | заметка |\n|---|---|---|---|---|---|\n')
    f.write('| %s | L1 | implement | false-fail | 0.5 | повтор на той же голове |\n' % time.strftime('%Y-%m-%dT%H:%MZ', time.gmtime(now - 3000)))
with open(os.path.join(root, 'aliases.tsv'), 'w') as f:
    f.write('# проба\n\\b77\\b\tкод-77\nимя ветки\tимя-ветки\n')
PY
}
late_case() {  # случай класса код-77 ПОСЛЕ влитого механизма
    python3 - "$1" <<'PY'
import json, os, sys, time
p = os.path.join(sys.argv[1], 'proj', 'S1', 'subagents', 'agent-a9.jsonl')
t = time.strftime('%Y-%m-%dT%H:%M:%S.000Z', time.gmtime(time.time() + 60))
with open(p, 'w') as f:
    f.write(json.dumps({'type': 'assistant', 'timestamp': t, 'message': {'role': 'assistant', 'stop_reason': 'end_turn',
        'content': [{'type': 'text', 'text': '### ВОЗВРАТ\n- урок: код 77 снова · цепочка\n'}]}}, ensure_ascii=False) + '\n')
PY
}

# ── Набор проб: suite <ядро> <хук> — печатает [OK]/[FAIL], возвращает число расхождений ─
suite() {
    local py="$1" hook="$2" D fails=0 out rc n1 n2
    D="$(mktemp -d "$T/run.XXXX")"
    ok() { echo "  [OK]   $1"; }
    no() { echo "  [FAIL] $1" >&2; fails=$((fails + 1)); }
    chk() { if [ "$1" = "$2" ]; then ok "$3"; else no "$3 — ожидалось «$1», получено «$2»"; fi; }
    has() { if grep -qF -- "$1" <<< "$out"; then ok "$2"; else no "$2 — нет «$1»"; fi; }
    hasnt() { if grep -qF -- "$1" <<< "$out"; then no "$2 — есть «$1»"; else ok "$2"; fi; }
    L() { LESSONS_PY="$py" LESSONS_DIR="$1/led" LESSONS_PROJECTS_DIR="$1/proj" LESSONS_WAVES_DIR="$1/waves" \
        LESSONS_ALIASES="$1/aliases.tsv" LESSONS_SINCE=2000-01-01 bash "$HERE/collect.sh" "${@:2}" 2>&1; }
    H() { local d="$1" inp="${2:-}"; [ -n "$inp" ] || inp='{}'; printf '%s' "$inp" | LESSONS_COLLECT="$HERE/collect.sh" LESSONS_PY="$py" LESSONS_DIR="$d/led" \
        LESSONS_PROJECTS_DIR="$d/proj" LESSONS_WAVES_DIR="$d/waves" LESSONS_ALIASES="$d/aliases.tsv" \
        LESSONS_SINCE=2000-01-01 CLAUDE_PROJECT_DIR="$WSR" bash "$hook" 2>&1; }

    mkfix "$D/w" work
    out="$(L "$D/w" scan)"; rc=$?
    chk 0 "$rc" "сбор: код 0"
    has 'новых уроков 10' "сбор: 10 уроков — агенты 4 (a3 «—» не урок), workflow 2 (w3 «—» не урок), диспетчер 1 (проза — не урок), lessons.md 2, errors.md 1"
    out="$(L "$D/w" report)"
    has '  2  open                      код-77' "ключ: синоним свёл «Код 77» и «код 77» в код-77"
    has '  2  open                      имя-ветки' "ключ: итог workflow и lessons.md волны — один класс имя-ветки"
    has '  1  open                      head-moved' "одна строка из двух источников — один случай"
    has 'оркестровка:конвейер не остановлен блокером' "урок диспетчера — под оркестровка:"
    has 'оркестровка:false-fail' "строка счётчика волны — под оркестровка:"
    has 'второй-блок' "взят последний блок ВОЗВРАТ"
    hasnt 'первый-блок' "первый блок ВОЗВРАТ не взят"
    hasnt 'прежний-блок' "последний блок без «урок:» — прежний блок не подставлен"
    hasnt '  x' "упоминание «урок диспетчера:» в прозе — не урок"
    has 'без ключа 1' "урок без места — без ключа, в классы не идёт"
    n1="$(wc -l < "$D/w/led/lessons.jsonl")"
    out="$(L "$D/w" scan)"
    n2="$(wc -l < "$D/w/led/lessons.jsonl")"
    has 'новых уроков 0' "идемпотентность: второй сбор — 0 новых"
    chk "$n1" "$n2" "идемпотентность: строк ведомости столько же"
    rm -f "$D/w/led/lessons-scan.json"
    out="$(L "$D/w" scan)"
    has 'новых уроков 0' "идемпотентность: без кэша смещений — 0 новых (ключ id)"
    out="$(L "$D/w" status)"; rc=$?
    chk 1 "$rc" "статус: есть что делать — код 1"
    has 'NEED-MECHANISM код-77 — случаев 2' "порог 2: код-77 просит механизм"
    has 'NEED-MECHANISM имя-ветки — случаев 2' "порог 2: имя-ветки просит механизм"
    hasnt 'NEED-MECHANISM head-moved' "один случай — механизма не просит"
    has 'UNKEYED' "урок без места — в перечне UNKEYED"
    out="$(L "$D/w" mark код-77 mechanism просто-слова)"; rc=$?
    chk 1 "$rc" "mechanism без #N — отказ"
    L "$D/w" mark код-77 mechanism ws#1 > /dev/null
    out="$(L "$D/w" status)"
    hasnt 'NEED-MECHANISM код-77' "после mechanism класс механизма не просит"
    L "$D/w" mark код-77 landed ws#2 > /dev/null
    late_case "$D/w"
    L "$D/w" scan > /dev/null
    out="$(L "$D/w" status --now "$(($(date +%s) + 120))")"
    has 'MECHANISM-FAILS код-77' "повтор после landed — «механизм не держит»"
    out="$(L "$D/w" status --now "$(($(date +%s) + 2 * 86400))")"
    has 'STALE head-moved' "открытый класс старше суток — STALE"

    out="$(H "$D/w")"; rc=$?
    chk 2 "$rc" "хук: есть что делать — код 2 (ход не кончается)"
    has '📚 УРОКИ: новых' "хук: строка сигнала"
    out="$(H "$D/w")"; rc=$?
    chk "0 " "$rc $out" "хук: тот же перечень второй раз — молчит"
    out="$(H "$D/w" '{"stop_hook_active": true}')"; rc=$?
    chk "0 " "$rc $out" "хук: stop_hook_active — молчит"

    mkfix "$D/i" idle
    out="$(H "$D/i")"; rc=$?
    chk "0 " "$rc $out" "хук: делать нечего (один свежий урок) — молчит"
    out="$(L "$D/i" status)"; rc=$?
    chk 0 "$rc" "статус: делать нечего — код 0"

    mkfix "$D/e" empty
    out="$(L "$D/e" scan)"; rc=$?
    chk 2 "$rc" "журналов нет: scan код 2, а не «уроков 0»"
    out="$(H "$D/e")"; rc=$?
    chk 2 "$rc" "хук: журналов нет — код 2"
    has 'НЕ СОБРАНЫ' "хук: журналов нет — «НЕ СОБРАНЫ»"
    return "$fails"
}

echo "== контроль"
suite "$HERE/lessons.py" "$WSR/.claude/hooks/lessons-signal.sh"
ctl=$?
[ "$ctl" = 0 ] || echo "контроль: расхождений $ctl" >&2

# ── Мутанты ────────────────────────────────────────────────────────────────
mutant() {  # mutant <имя> <файл: py|hook> <фрагмент> <замена>
    local name="$1" which="$2" py="$HERE/lessons.py" hook="$WSR/.claude/hooks/lessons-signal.sh" m
    m="$T/mut-$name"
    mkdir -p "$m"
    cp "$py" "$m/lessons.py"; cp "$hook" "$m/hook.sh"
    local tgt="$m/lessons.py"; [ "$which" = hook ] && tgt="$m/hook.sh"
    if ! python3 - "$tgt" "$3" "$4" <<'PY'
import sys
p, a, b = sys.argv[1:4]
s = open(p, encoding='utf-8').read()
if a not in s:
    sys.exit(1)
open(p, 'w', encoding='utf-8').write(s.replace(a, b, 1))
PY
    then
        echo "  [FAIL] мутант $name: фрагмент не найден — порча не легла" >&2
        mfail=$((mfail + 1)); return
    fi
    suite "$m/lessons.py" "$m/hook.sh" > "$m/out" 2>&1
    local r=$?
    if [ "$r" -gt 0 ]; then echo "  [OK]   мутант $name покраснел (расхождений $r)"; mok=$((mok + 1))
    else echo "  [FAIL] мутант $name прошёл контроль — проба слепа к нему" >&2; mfail=$((mfail + 1)); fi
}
echo "== мутанты"
mok=0 mfail=0
mutant unkeyed-accepted py '        if not m:
            return None' '        if not m:
            return norm(raw)'
mutant dedup-off py '        if lid in self.ids:
            return False' '        if False:
            return False'
mutant threshold-3 py 'THRESHOLD = 2' 'THRESHOLD = 3'
# shellcheck disable=SC2016  # фрагмент кода хука — литералом, без подстановки
mutant hook-prints-on-empty hook '[ "$rc" = 1 ] && [ -n "$out" ] || exit 0' 'true'
mutant repeat-after-landed-blind py '            if late:' '            if False:'
mutant first-return-block py "i = text.rfind('### ВОЗВРАТ')" "i = text.find('### ВОЗВРАТ')"
mutant void-as-zero py '        if not ok and not store.lessons:' '        if False:'
mutant dispatcher-prose py "DISP_RE = re.compile(r'^\\s*[-*]?\\s*урок диспетчера:" "DISP_RE = re.compile(r'урок диспетчера:"

echo "lessons-inject: контроль — расхождений $ctl; мутантов покраснело $mok, прошло контроль либо не легло $mfail"
[ "$ctl" = 0 ] && [ "$mfail" = 0 ] && [ "$mok" -gt 0 ] || exit 1
exit 0
