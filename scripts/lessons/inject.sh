#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# inject.sh — доказательство сборщика уроков `collect.sh` и хука `lessons-signal.sh`
# ИСПОЛНЕНИЕМ на подложенных журналах (ws#1199). Настоящие журналы и ведомость проба не
# видит и не трогает: всё — во временном каталоге, пути — переменными LESSONS_*.
#
# Пробы (контроль — каждая сходится):
#   сбор        — урок из журнала агента, итога workflow, главного потока (строка «урок
#                 диспетчера:», упоминание в прозе — не урок), lessons.md и errors.md волны;
#                 «—» — не урок; берётся ПОСЛЕДНИЙ блок ВОЗВРАТ сообщения;
#   B1 формы    — итог-объект по формам переписи журналов 2026-10-18: блок ВОЗВРАТ в поле
#                 ret, note (сжатый в строку «· урок:»), notes[] на глубине, блок без заголовка
#                 после поля контракта; близнецы молчат: «урок:» в прозе поля без блока и без
#                 поля контракта, «урок: —»;
#   B2 весь файл — ранний ВОЗВРАТ дозапущенного агента за 300 КиБ до конца журнала собран;
#                 близнец: «### ВОЗВРАТ» в сообщении пользователя (задание) — не урок;
#   B3 случай   — одна строка у двух РАЗНЫХ агентов — два случая (нужен механизм); близнецы:
#                 итог workflow ↔ lessons.md той же волны и полосы — один, повтор одного агента
#                 (два блока одной строкой) — один, пересказчик (задание называет журнал
#                 автора) при том же тексте у автора — не случай;
#   ключ, идемпотентность, порог 2, статусы — как прежде;
#   rekey       — `rekey ?<id> <ключ>`: урок без ключа в тексте уходит из UNKEYED в класс ключа
#                 (ws#1230); ключ события проходит ту же `canon` (синонимы — пересчётом: строка
#                 aliases.tsv, дописанная ПОСЛЕ события, сводит и его); из двух событий одному
#                 уроку действует последнее; близнецы — отказ с текстом и без события в ведомости:
#                 урок с ключом в тексте, нет урока, префикс id у двух уроков, ключ с «·»,
#                 начатый «?», пустой; событие на урок с ключом в тексте ключ не меняет;
#   бюджет      — при --budget 0 сбор читает кусок за вызов и откладывает остальное, догоном
#                 доходит до того же числа уроков;
#   B4 хук      — неверный регэксп синонима: сборщик код 3 с координатой, хук «НЕ СОБРАНЫ»;
#                 исключение — код 3; сборщик код 1 без строки, код 3, таймаут (проба времени:
#                 хук возвращается ≤ 3 с при сборщике на 6 с), нет сборщика — «НЕ СОБРАНЫ»;
#   хук конца хода — есть что делать: код 2; тот же перечень второй раз — молчит, через сутки —
#                 снова; та же причина сбоя — раз в сутки; stop_hook_active — молчит; делать
#                 нечего — код 0 без вывода.
# Затем мутанты — каждый обязан покраснеть хотя бы одной пробой (перечень — в конце файла).
# Мутант, чей фрагмент не найден, — отказ пробы (порча, которая не легла, ничего не доказывает).
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
def agent(aid, *texts, task='задание'):
    with open(os.path.join(S, 'agent-%s.jsonl' % aid), 'w') as f:
        f.write(json.dumps({'type': 'user', 'timestamp': iso(now - 4000), 'message': {'role': 'user', 'content': task}}, ensure_ascii=False) + '\n')
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
# B3: одна строка у двух разных агентов — два случая; повтор одного агента — один
agent('a7', ret('одинаковый-урок · два агента'))
agent('a8', ret('одинаковый-урок · два агента'))
agent('a11', ret('повтор-агента · дозапуск'), ret('повтор-агента · дозапуск'))
# пересказчик: задание называет журнал другого агента — его урок при том же тексте у автора не случай
RELAY = 'Прочитай файл %s/subagents/workflows/wf_1/journal.jsonl и верни дословно блок «### ВОЗВРАТ»' % P
agent('a12', ret('имя ветки kaname · задание'), task=RELAY)
agent('a13', ret('пересказ-без-автора · сирота'), task=RELAY)
# B2: ранний ВОЗВРАТ дозапущенного агента — за 300 КиБ до конца журнала
with open(os.path.join(S, 'agent-a10.jsonl'), 'w') as f:
    f.write(json.dumps({'type': 'user', 'timestamp': iso(now - 4000), 'message': {'role': 'user', 'content': 'задание: в конце ### ВОЗВРАТ\n- урок: чужой-из-задания · не урок'}}, ensure_ascii=False) + '\n')
    f.write(asst(ret('ранний-возврат · начало журнала'), now - 3900) + '\n')
    for i in range(300):
        f.write(json.dumps({'type': 'user', 'timestamp': iso(now - 3800), 'message': {'role': 'user', 'content': 'x' * 1024}}) + '\n')
    f.write(asst(ret('поздний-возврат · хвост журнала'), now - 3700) + '\n')
W1 = os.path.join(S, 'workflows', 'wf_1')
with open(os.path.join(W1, 'agent-w1.jsonl'), 'w') as f:  # задание полосы L2 волны 9 (wave.js)
    f.write(json.dumps({'type': 'user', 'message': {'role': 'user', 'content': 'Полоса L2 … её же допиши `>> /ws/tmp/wave-9/reports/lessons.md` с префиксом «L2 · »; урока нет — «—»'}}, ensure_ascii=False) + '\n')
def res(aid, r):
    return json.dumps({'type': 'result', 'key': 'v2:' + aid, 'agentId': aid, 'result': r}, ensure_ascii=False) + '\n'
with open(os.path.join(W1, 'journal.jsonl'), 'w') as f:
    f.write(json.dumps({'type': 'launched'}) + '\n')
    f.write(json.dumps({'type': 'started', 'key': 'v2:w1', 'agentId': 'w1', 'label': 'impl:L2', 'phase': 'Полосы'}) + '\n')
    f.write(res('w1', {'status': 'done', 'lesson': 'head-moved · lane-precheck'}))
    f.write(res('w2', ret('имя ветки kaname · задание')))
    f.write(res('w3', {'status': 'done', 'lesson': '—'}))
    # B1: формы объекта-итога из переписи журналов
    f.write(res('w4', {'verdict': 'accept', 'blocking': [], 'ret': ret('поле-ret · итог объектом')}))
    f.write(res('w5', {'head': 'x', 'ok': True, 'note': 'ВОЗВРАТ: готово · вопросы владельцу: — · урок: поле-note · сжатый возврат'}))
    f.write(res('w6', {'summary': 's', 'notes': ['n1', 'итог\n### ВОЗВРАТ\n- статус: готово\n- урок: поле-notes · глубина']}))
    f.write(res('w7', {'ideas': [{'mechanism': 'проза\n- затронуто в vault: —\n- урок: без-заголовка · поле контракта'}]}))
    f.write(res('w8', {'ideas': [{'mechanism': 'проза поля; урок: близнец-прозы · не урок'}], 'summary': '### ВОЗВРАТ\n- урок: —'}))
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
    local py="$1" hook="$2" D fails=0 out rc n1 n2 t0 el now
    D="$(mktemp -d "$T/run.XXXX")"
    now="$(date +%s)"
    ok() { echo "  [OK]   $1"; }
    no() { echo "  [FAIL] $1" >&2; fails=$((fails + 1)); }
    chk() { if [ "$1" = "$2" ]; then ok "$3"; else no "$3 — ожидалось «$1», получено «$2»"; fi; }
    has() { if grep -qF -- "$1" <<< "$out"; then ok "$2"; else no "$2 — нет «$1»"; fi; }
    hasnt() { if grep -qF -- "$1" <<< "$out"; then no "$2 — есть «$1»"; else ok "$2"; fi; }
    lid() { python3 -c 'import json,sys
for l in open(sys.argv[1]):
    r = json.loads(l)
    if r.get("raw") == sys.argv[2]: print(r["id"])' "$1/led/lessons.jsonl" "$2"; }
    L() { LESSONS_PY="$py" LESSONS_DIR="$1/led" LESSONS_PROJECTS_DIR="$1/proj" LESSONS_WAVES_DIR="$1/waves" \
        LESSONS_ALIASES="$1/aliases.tsv" LESSONS_SINCE=2000-01-01 bash "$HERE/collect.sh" "${@:2}" 2>&1; }
    H() { local d="$1" inp="${2:-}"; [ -n "$inp" ] || inp='{}'; printf '%s' "$inp" | LESSONS_COLLECT="${HC:-$HERE/collect.sh}" LESSONS_PY="$py" LESSONS_DIR="$d/led" \
        LESSONS_PROJECTS_DIR="$d/proj" LESSONS_WAVES_DIR="$d/waves" LESSONS_ALIASES="$d/aliases.tsv" \
        LESSONS_SINCE=2000-01-01 LESSONS_NOW="${HN:-$now}" CLAUDE_PROJECT_DIR="$WSR" bash "$hook" 2>&1; }

    mkfix "$D/w" work
    out="$(L "$D/w" scan)"; rc=$?
    chk 0 "$rc" "сбор: код 0"
    has 'новых уроков 21' "сбор: 21 урок — агенты 11 (a3 «—», a6 без «урок:» — не уроки; a10 — два), workflow 6 (w3, w8 — не уроки), диспетчер 1, lessons.md 2, errors.md 1"
    out="$(L "$D/w" report)"
    has '  2  open                      код-77' "ключ: синоним свёл «Код 77» и «код 77» в код-77"
    has '  2  open                      имя-ветки' "ключ: итог workflow и lessons.md волны — один класс имя-ветки"
    has '  1  open                      head-moved' "B3 близнец: итог workflow ↔ lessons.md той же волны и полосы — один случай"
    has '  2  open                      одинаковый-урок' "B3: одна строка у двух РАЗНЫХ агентов — два случая"
    has '  1  open                      повтор-агента' "B3 близнец: два блока одной строкой у одного агента — один случай"
    has '  2  open                      имя-ветки' "B3 близнец: пересказчик итога w2 (задание называет журнал автора) — не третий случай"
    has '  1  open                      пересказ-без-автора' "пересказчик без автора в ведомости — случай"
    has 'поле-ret' "B1: блок ВОЗВРАТ в поле ret объекта-итога собран"
    has 'поле-note' "B1: ВОЗВРАТ, сжатый в строку поля note («· урок:»), собран"
    has 'поле-notes' "B1: блок ВОЗВРАТ в notes[] на глубине собран"
    has 'без-заголовка' "B1: блок без заголовка — от поля контракта — собран"
    hasnt 'близнец-прозы' "B1 близнец: «урок:» в прозе поля без блока — не урок"
    has 'ранний-возврат' "B2: ранний ВОЗВРАТ за 300 КиБ до конца журнала собран"
    has 'поздний-возврат' "B2: поздний ВОЗВРАТ собран"
    hasnt 'чужой-из-задания' "B2 близнец: ВОЗВРАТ в сообщении пользователя — не урок"
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
    has 'NEED-MECHANISM одинаковый-урок — случаев 2' "B3: два агента одной строкой — механизм просит"
    hasnt 'NEED-MECHANISM head-moved' "один случай — механизма не просит"
    hasnt 'NEED-MECHANISM повтор-агента' "B3 близнец: повтор одного агента механизма не просит"
    has 'UNKEYED' "урок без места — в перечне UNKEYED"
    out="$(L "$D/w" mark код-77 mechanism просто-слова)"; rc=$?
    chk 1 "$rc" "mechanism без #N — отказ"
    L "$D/w" mark код-77 mechanism ws#1 > /dev/null
    out="$(L "$D/w" status)"
    hasnt 'NEED-MECHANISM код-77' "после mechanism класс механизма не просит"
    L "$D/w" mark код-77 landed ws#2 > /dev/null
    late_case "$D/w"
    L "$D/w" scan > /dev/null
    out="$(L "$D/w" status --now "$((now + 120))")"
    has 'MECHANISM-FAILS код-77' "повтор после landed — «механизм не держит»"
    out="$(L "$D/w" status --now "$((now + 2 * 86400))")"
    has 'STALE head-moved' "открытый класс старше суток — STALE"

    # Часы хука — после «старше суток»: перечень от времени больше не меняется.
    local h0=$((now + 2 * 86400))
    out="$(HN=$h0 H "$D/w")"; rc=$?
    chk 2 "$rc" "хук: есть что делать — код 2 (ход продлён)"
    has '📚 УРОКИ: новых' "хук: строка сигнала"
    out="$(HN=$h0 H "$D/w")"; rc=$?
    chk "0 " "$rc $out" "хук: тот же перечень второй раз — молчит"
    out="$(HN=$((h0 + 86000)) H "$D/w")"; rc=$?
    chk "0 " "$rc $out" "хук: тот же перечень до истечения суток — молчит"
    out="$(HN=$((h0 + 86401)) H "$D/w")"; rc=$?
    chk 2 "$rc" "хук: тот же перечень через сутки — снова код 2"
    out="$(H "$D/w" '{"stop_hook_active": true}')"; rc=$?
    chk "0 " "$rc $out" "хук: stop_hook_active — молчит"

    # Бюджет: кусок за вызов, остальное — догоном; итог тот же.
    mkfix "$D/b" work
    out="$(LESSONS_CHUNK=65536 L "$D/b" scan --budget 0)"
    if grep -qE 'отложено бюджетом [1-9]' <<< "$out"; then ok "бюджет 0: отложено > 0 (сбор ограничен бюджетом)"; else no "бюджет 0: ничего не отложено — бюджет не ограничивает сбор: $out"; fi
    if grep -qE 'новых уроков ([1-9]|1[0-9]|20),' <<< "$out"; then ok "бюджет 0: кусок за вызов прочитан — догон не стоит, но и не всё"; else no "бюджет 0: прочитано ноль либо всё: $out"; fi
    out="$(LESSONS_CHUNK=65536 L "$D/b" scan --budget 5)"
    has 'в ведомости 21' "догон: те же 21 урок"

    # rekey (ws#1230): урок без «·» получает ключ событием ведомости; урок с «·» — нет.
    mkfix "$D/r" work
    L "$D/r" scan > /dev/null
    local uid kid
    uid="$(lid "$D/r" 'без места вообще')"
    kid="$(lid "$D/r" 'второй-блок · берётся')"
    out="$(L "$D/r" rekey "?${uid:0:8}" ключ-пробы)"; rc=$?
    chk 0 "$rc" "rekey: урок без «·» — код 0"
    out="$(L "$D/r" report)"
    has '  1  open                      ключ-пробы' "rekey: урок без «·» считается в классе ключа"
    has 'без ключа 0' "rekey: урок ушёл из UNKEYED"
    out="$(L "$D/r" mark ключ-пробы edited ws#1)"; rc=$?
    chk 0 "$rc" "rekey: класс ключа виден mark"
    out="$(L "$D/r" rekey "?${kid:0:8}" чужой-ключ)"; rc=$?
    chk 1 "$rc" "rekey близнец: урок с «·» — отказ"
    has 'ключ из текста «второй-блок»; rekey — только уроку без ключа в тексте' "rekey близнец: отказ уроку с «·» называет его ключ"
    out="$(L "$D/r" rekey '?ffffffff' ключ-пробы)"; rc=$?
    chk 1 "$rc" "rekey: нет урока с таким id — отказ"
    has 'уроков с id ffffffff…: 0, нужен ровно один' "rekey: отказ «нет урока» называет число"
    printf '{"t": "rekey", "id": "%s", "key": "чужой-ключ", "ts": 0}\n' "$kid" >> "$D/r/led/lessons.jsonl"
    out="$(L "$D/r" report)"
    has '  1  open                      второй-блок' "rekey близнец: событие на урок с «·» ключ из текста не меняет"
    hasnt 'чужой-ключ' "rekey близнец: ключ события к уроку с «·» не применён"

    # rekey: ключ события — через ту же canon (синонимы, пересчёт), последнее событие выигрывает,
    # отказы — с текстом и без события в ведомости.
    mkfix "$D/q" work
    L "$D/q" scan > /dev/null
    python3 - "$D/q/led/lessons.jsonl" "$now" <<'PY'
import json, sys
p, now = sys.argv[1], float(sys.argv[2])
with open(p, 'a', encoding='utf-8') as f:
    for n in (1, 2):  # два урока без места с общим префиксом id «abcd»
        f.write(json.dumps({'t': 'lesson', 'id': 'abcd%04d' % n + '0' * 32, 'sid': 'S9', 'agent': 'z%d' % n,
                            'src': 'agent', 'ts': now - 3600, 'key': None, 'raw': 'синтетика без места %d' % n},
                           ensure_ascii=False) + '\n')
PY
    n1="$(grep -c '"t": "rekey"' "$D/q/led/lessons.jsonl")"
    out="$(L "$D/q" rekey '?abcd' ключ-пробы)"; rc=$?
    chk 1 "$rc" "rekey близнец: префикс id у двух уроков — отказ"
    has 'уроков с id abcd…: 2, нужен ровно один' "rekey близнец: отказ называет неоднозначность числом"
    out="$(L "$D/q" rekey '?abcd0002' 'а · б')"; rc=$?
    chk 1 "$rc" "rekey близнец: ключ с «·» — отказ"
    has 'ключ «а · б» несёт «·»' "rekey близнец: отказ называет «·»"
    out="$(L "$D/q" rekey '?abcd0002' '?abc')"; rc=$?
    chk 1 "$rc" "rekey близнец: ключ, начатый «?», — отказ"
    has 'ключ «?abc» начат «?»' "rekey близнец: отказ называет «?»"
    out="$(L "$D/q" rekey '?abcd0002' '«» .')"; rc=$?
    chk 1 "$rc" "rekey близнец: ключ, пустой после нормализации, — отказ"
    has 'ключ ««» .» пуст после нормализации' "rekey близнец: отказ называет пустоту"
    n2="$(grep -c '"t": "rekey"' "$D/q/led/lessons.jsonl")"
    chk "$n1" "$n2" "rekey близнецы: отказ событие в ведомость не дописал"
    uid="$(lid "$D/q" 'без места вообще')"
    out="$(L "$D/q" rekey "?${uid:0:8}" первый-ключ)"; rc=$?
    chk 0 "$rc" "rekey: первое событие уроку — код 0"
    out="$(L "$D/q" rekey "?${uid:0:8}" '«Код 77» в цепочке')"; rc=$?
    chk 0 "$rc" "rekey: второе событие тому же уроку — код 0"
    has "?${uid:0:8} → код-77" "rekey: ключ события прошёл синонимы при записи — класс код-77"
    out="$(L "$D/q" report)"
    has '  3  open                      код-77' "rekey: ключ «Код 77 в цепочке» сведён синонимом с уроками из текста — 3 случая"
    hasnt 'код 77 в цепочке' "rekey: ключ события в обход синонимов классом не стал"
    hasnt 'первый-ключ' "rekey: из двух событий одному уроку действует последнее"
    out="$(L "$D/q" status)"
    has 'NEED-MECHANISM код-77 — случаев 3' "rekey: случай под ключом события виден порогу"
    out="$(L "$D/q" rekey '?abcd0001' новый-класс)"; rc=$?
    chk 0 "$rc" "rekey: однозначный префикс — код 0"
    printf 'новый-класс\tкод-77\n' >> "$D/q/aliases.tsv"
    out="$(L "$D/q" report)"
    has '  4  open                      код-77' "rekey: строка синонимов, дописанная после события, сводит и его (пересчёт)"

    # B4: сбой сборщика отличим от «делать нечего».
    mkfix "$D/a" work
    printf '(\tсломан\n' > "$D/a/aliases.tsv"
    out="$(L "$D/a" scan)"; rc=$?
    chk 3 "$rc" "B4: неверный регэксп синонима — код 3"
    has 'aliases.tsv:1 — регэксп синонима не разобран' "B4: отказ называет координату синонима"
    out="$(H "$D/a")"; rc=$?
    chk 2 "$rc" "B4: хук при неверном синониме — код 2"
    has '📚 УРОКИ НЕ СОБРАНЫ: код 3' "B4: хук при неверном синониме — «НЕ СОБРАНЫ: код 3»"
    out="$(H "$D/a")"; rc=$?
    chk "0 " "$rc $out" "B4: та же причина сбоя второй раз за сутки — молчит"
    out="$(HN=$((now + 86401)) H "$D/a")"; rc=$?
    chk 2 "$rc" "B4: та же причина сбоя через сутки — снова код 2"
    mkfix "$D/x" work
    : > "$D/x/led"
    out="$(L "$D/x" scan)"; rc=$?
    chk 3 "$rc" "B4: исключение сборщика (ведомость — не каталог) — код 3, не 1"
    printf '#!/usr/bin/env bash\necho boom >&2\nexit 1\n' > "$D/s1.sh"
    printf '#!/usr/bin/env bash\necho "lessons: VOID — x" >&2\nexit 3\n' > "$D/s3.sh"
    printf '#!/usr/bin/env bash\nsleep 6\nexit 0\n' > "$D/sl.sh"
    out="$(HC="$D/s1.sh" H "$D/w")"; rc=$?
    chk 2 "$rc" "B4: сборщик код 1 без строки сигнала — хук код 2"
    has 'НЕ СОБРАНЫ: код 1 без строки сигнала: boom' "B4: код 1 без строки — «НЕ СОБРАНЫ» с причиной"
    out="$(HC="$D/s3.sh" H "$D/w")"; rc=$?
    has 'НЕ СОБРАНЫ: код 3: lessons: VOID — x' "B4: сборщик код 3 — «НЕ СОБРАНЫ» с причиной"
    t0="$(date +%s%N)"
    out="$(HC="$D/sl.sh" LESSONS_TIMEOUT=1 H "$D/w")"; rc=$?
    el=$((($(date +%s%N) - t0) / 1000000))
    chk 2 "$rc" "B4: таймаут сборщика — хук код 2"
    has 'НЕ СОБРАНЫ: таймаут 1 с' "B4: таймаут сборщика — «НЕ СОБРАНЫ: таймаут»"
    if [ "$el" -le 3000 ]; then ok "проба времени: хук вернулся за ${el} мс ≤ 3000 при сборщике на 6 с"; else no "проба времени: хук держал ${el} мс > 3000"; fi
    out="$(HC="$D/нет.sh" H "$D/w")"; rc=$?
    has 'НЕ СОБРАНЫ: нет сборщика' "B4: нет сборщика — «НЕ СОБРАНЫ»"

    mkfix "$D/i" idle
    out="$(H "$D/i")"; rc=$?
    chk "0 " "$rc $out" "хук: делать нечего (один свежий урок) — код 0 без вывода"
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
mutant() {  # mutant <имя> <файл: py|hook> <фрагмент> <замена> [<фрагмент> <замена> …]
    local name="$1" which="$2" py="$HERE/lessons.py" hook="$WSR/.claude/hooks/lessons-signal.sh" m
    m="$T/mut-$name"
    mkdir -p "$m"
    cp "$py" "$m/lessons.py"; cp "$hook" "$m/hook.sh"
    local tgt="$m/lessons.py"; [ "$which" = hook ] && tgt="$m/hook.sh"
    if ! python3 - "$tgt" "${@:3}" <<'PY'
import sys
p, pairs = sys.argv[1], sys.argv[2:]
s = open(p, encoding='utf-8').read()
for a, b in zip(pairs[::2], pairs[1::2]):
    if a not in s:
        sys.exit(1)
    s = s.replace(a, b, 1)
open(p, 'w', encoding='utf-8').write(s)
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
mutant repeat-after-landed-blind py '            if late:' '            if False:'
mutant first-return-block py "i = text.rfind('### ВОЗВРАТ')" "i = text.find('### ВОЗВРАТ')"
mutant void-as-zero py '        if not ok and not store.lessons:' '        if False:'
mutant dispatcher-prose py "DISP_RE = re.compile(r'^\\s*[-*]?\\s*урок диспетчера:" "DISP_RE = re.compile(r'урок диспетчера:"
# B1 — итог-объект: только поле lesson; без «· урок:»; без поля контракта; урок без блока
mutant b1-lesson-field-only py "else lessons_in(res, [])" "else ([res.get('lesson')] if isinstance(res, dict) and res.get('lesson') not in (None, '—') else [])"
mutant b1-no-inline py "RET_RE = re.compile(r'(?:^\\s*[-*]?|[;·])" "RET_RE = re.compile(r'(?:^\\s*[-*]?)"
mutant b1-no-field-anchor py '        m = FIELD_RE.search(text)' '        m = None'
mutant b1-no-block-needed py '        m = FIELD_RE.search(text)
        if not m:
            return None
        i = m.start()' '        i = 0'
# B2 — первый осмотр хвостом 256 КиБ
mutant b2-tail-first py 'isinstance(st, int) and 0 <= st <= size else 0' 'isinstance(st, int) and 0 <= st <= size else max(0, size - (1 << 18))'
# B3 — сведение по тексту между агентами; пара workflow ↔ lessons.md не сведена
mutant b3-text-dedup py "            rh = r['id']" "            rh = (k, sha(re.sub(r'\\s+', ' ', r.get('raw', '')).strip()))"
mutant b3-relay-counted py " or (r.get('relay') and flat(r) in authored):" ":"
mutant b3-pair-off py "        if r.get('wave') and r.get('lane'):" "        if False:"
# rekey (ws#1230) — событие не учтено; событие перекрывает ключ из текста; отказ близнецу снят
mutant rekey-ignored py '        if k is None and rekeys:' '        if False:'
mutant rekey-overrides-text py '        if k is None and rekeys:
            k = canon(rekeys.get(r['"'"'id'"'"']), aliases)' '        if rekeys and r['"'"'id'"'"'] in rekeys:
            k = canon(rekeys[r['"'"'id'"'"']], aliases)'
# ключ события в обход canon; canon лишь при записи (новая строка синонимов не сводит прежний);
# неоднозначный префикс берёт первый урок; первое событие выигрывает; ключ не проверен
mutant rekey-key-bypasses-canon py "            k = canon(rekeys.get(r['id']), aliases)" "            k = rekeys.get(r['id'])"
mutant rekey-canon-at-write-only py "            k = canon(rekeys.get(r['id']), aliases)" "            k = rekeys.get(r['id'])" \
    "        store.rekey(r['id'], key, now)" "        store.rekey(r['id'], canon(key, aliases), now)"
mutant rekey-ambiguous-takes-first py '        if len(hit) != 1:' '        if len(hit) < 1:'
mutant rekey-first-event-wins py "self.rekeys[r['id']] = r['key']  # последнее событие выигрывает" "self.rekeys.setdefault(r['id'], r['key'])"
mutant rekey-key-unchecked py '        if why:
            print' '        if not key:
            print'
mutant rekey-keyed-accepted py "        if r.get('src') == 'wave-errors' or key_of(r.get('raw', ''), aliases) is not None:" "        if False:"
# B4 — бюджет, догон, исключения сборщика, ветви хука
mutant b4-budget-1e9 py "deadline = time.time() + float(opts['--budget'])" "deadline = time.time() + 1e9"
mutant b4-no-progress py "if census['progress'] and time.time() > deadline:" "if time.time() > deadline:"
mutant b4-alias-uncaught py '        except re.error as e:' '        except KeyError as e:'
mutant b4-crash-code-1 py "        die('сбой сборщика: %s: %s' % (type(e).__name__, str(e)[:200]), 3)" "        raise"
# shellcheck disable=SC2016  # фрагменты кода хука — литералом, без подстановки
{
mutant hook-prints-on-empty hook '    0) exit 0 ;;' '    0) ;;'
mutant hook-code1-silent hook '*) void "код 1 без строки сигнала${why:+: $why}" ;;' '*) exit 0 ;;'
mutant hook-other-silent hook '    *) void "код $rc${why:+: $why}" ;;' '    *) exit 0 ;;'
mutant hook-timeout-silent hook '    124 | 137) void "таймаут ${lim} с" ;;' '    124 | 137) exit 0 ;;'
mutant hook-no-timeout hook 'timeout -k 2 "$lim" bash "$collect"' 'bash "$collect"'
mutant hook-missing-silent hook '[ -r "$collect" ] || void "нет сборщика $collect"' '[ -r "$collect" ] || exit 0'
mutant hook-void-unthrottled hook '        exit 0
    fi
    mkdir -p' '        :
    fi
    mkdir -p'
mutant hook-stop-active-ignored hook "*'\"stop_hook_active\":true'* | *'\"stop_hook_active\": true'*) exit 0 ;;" "*'\"stop_hook_active\":never'*) exit 0 ;;"
}
# (6) хук конца хода: перечень не чаще раза в сутки — и не реже
mutant signal-unthrottled py "    if last.get('sig') == sig and now - float(last.get('ts') or 0) < DAY:" "    if False:"
mutant signal-throttle-forever py "now - float(last.get('ts') or 0) < DAY:" "now - float(last.get('ts') or 0) < 1e12:"

echo "lessons-inject: контроль — расхождений $ctl; мутантов покраснело $mok, прошло контроль либо не легло $mfail"
[ "$ctl" = 0 ] && [ "$mfail" = 0 ] && [ "$mok" -gt 0 ] || exit 1
exit 0
