#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# stall-census-inject.sh — доказательство `scripts/stall-census.sh` ИСПОЛНЕНИЕМ
# на подложенной сессии (ws#1001): дефект → код 1 и строка, называющая предмет;
# законный близнец той же формы → 0; нечитаемое → 2, а не «чисто».
#
# Сессия собирается в mktemp: главный журнал `<id>.jsonl`, каталог `<id>/` с
# `subagents/workflows/wf_*/agent-*.jsonl`, `journal.jsonl` и состояниями
# `workflows/wf_*.json`; процессы — подложенным выводом `ps`. Время — от «сейчас»
# этого прогона, mtime файлов ставится `touch -d`.
#
# Замер скорости на живой сессии 3f44acf5 (664 каталога workflow, главный журнал
# 152 МБ): `time bash scripts/stall-census.sh --session <каталог>` — 0,13 с
# (2026-10-11); предел из задания ws#1001 — 5 с.
#
# Отсоединённые процессы (ws#1154) — пробы Д1–Д9 и их мутанты: отбор по метке окружения,
# живой близнец, законный срок, чужая сессия, переиспользованный pid, «не судимо».
#
# Серия ожиданий после остановки или возобновления (ws#1343) — пробы Р1–Р6 `reset_cases` и мутанты.
#
# Остановленный харнессом агент (ws#1033) — пробы `stop_cases` и их мутанты: уведомление
# `<task-notification>` главного журнала после последней записи агента, возобновление после
# него, снятие уведомления из очереди, чужой id в тексте, уведомление глубже хвоста 4 МиБ.
#
# Коды: 0 — все пробы сошлись; 1 — нет; 2 — нет python3: вердикта нет.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C="$HERE/stall-census.sh"
command -v python3 > /dev/null 2>&1 || { echo "stall-census-inject: VOID — нет python3" >&2; exit 2; }
[ -r "$C" ] || { echo "stall-census-inject: VOID — прибора нет: $C" >&2; exit 2; }
T="$(mktemp -d)"
# shellcheck disable=SC2154
trap '_rc=$?; rm -rf "$T" 2>/dev/null || rm -rf "$T" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $T не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT
# Своя сессия прибора берётся из окружения (ws#1131): окружение запустившего
# claude в пробы не протекает, каждая проба процессов задаёт его сама.
unset CLAUDE_PID CLAUDE_CODE_SESSION_ID STALL_PROC_ROOT
NOW="$(date +%s)"
iso() { date -u -d "@$((NOW - $1 * 60))" +%Y-%m-%dT%H:%M:%S.000Z; }
pass=0 fail=0

# rec <файл> <минут назад> <вид: tool|done|final|midthink|midtext|result|ask> [команда]
# final — итог агента (stop_reason end_turn, форма журналов Claude Code);
# midthink, midtext — промежуточная запись хода: thinking или text со
# stop_reason tool_use без вызова, вызов ещё впереди (живая форма: 1902 записи
# на 4000 журналов агентов проекта, приёмка ws#1110);
# done — ответ без вызова и без stop_reason: итог, если журнал молчит порог
# агента, иначе ход может продолжиться вызовом (ws#1130); ask — новое сообщение
# агенту (возобновление SendMessage).
rec() {
    local f="$1" m="$2" kind="$3" cmd="${4:-go test ./...}" t
    t="$(iso "$m")"
    case "$kind" in
        tool) printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"%s"}}]}}\n' "$t" "$cmd" >> "$f" ;;
        done) printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"text","text":"готово"}]}}\n' "$t" >> "$f" ;;
        final) printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"### ВОЗВРАТ"}]}}\n' "$t" >> "$f" ;;
        midthink) printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"thinking","thinking":"дальше вызов"}]}}\n' "$t" >> "$f" ;;
        midtext) printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"text","text":"проверю"}]}}\n' "$t" >> "$f" ;;
        ask) printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"продолжи"}}\n' "$t" >> "$f" ;;
        result) printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}\n' "$t" >> "$f" ;;
        intr) printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}\n' "$t" >> "$f" ;;
        intrmid) printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"см. выше: [Request interrupted by user] было вчера"}}\n' "$t" >> "$f" ;;
        intrs) printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"[Request interrupted by user for tool use]"}}\n' "$t" >> "$f" ;;
    esac
    printf '{"type":"attachment","timestamp":"%s"}\n' "$t" >> "$f"
    touch -d "@$((NOW - m * 60))" "$f"
}
# session <имя> — каталог сессии с главным журналом (последний ответ — минуту назад)
session() {
    local s="$T/$1"
    mkdir -p "$s/subagents/workflows/wf_live-1" "$s/workflows"
    rec "$s.jsonl" 1 "done"
    printf '%s' "$s"
}
ps_ok() { printf '%s\n' "100 1 90000 claude claude --x" "200 100 600 bash /bin/bash -c source /h/.claude/shell-snapshots/s.sh && eval 'go test ./...'" "300 1 99999 sshd sshd"; }
# probe <код> <имя> <строка|-> <довод…>; absent=<строка> — её в выводе быть не должно;
# stdin=<JSON> — вход хука (иначе /dev/null).
probe() {
    local want="$1" name="$2" needle="$3" got out
    shift 3
    out="$(printf '%s' "${stdin:-}" | bash "$C" "$@" 2>&1)"; got=$?
    if [ "$got" -eq "$want" ] && { [ "$needle" = - ] || grep -qF -- "$needle" <<< "$out"; } && { [ -z "${absent:-}" ] || ! grep -qF -- "$absent" <<< "$out"; }; then
        [ -n "${quiet:-}" ] || echo "  [OK]   $name (код $got)"; pass=$((pass + 1))
    else
        failed="${failed:-}; $name"
        [ -n "${quiet:-}" ] || echo "  [FAIL] $name — ждали код $want${needle:+ и «$needle»}, получили $got: $(head -c 400 <<< "$out")" >&2; fail=$((fail + 1))
    fi
}
ps_ok > "$T/ps"

echo "== агент"
s="$(session clean)"; rec "$s/subagents/workflows/wf_live-1/agent-a1.jsonl" 2 tool
probe 0 "контроль: вызов 2 мин назад — застоя нет, перепись названа" "агентов осмотрено 1" --session "$s" --ps "$T/ps"
s="$(session stall)"; rec "$s/subagents/workflows/wf_live-1/agent-a1.jsonl" 30 tool "until grep -q rc= run.log; do sleep 60; done"
probe 1 "инъекция: вызов 30 мин без результата — STALL-AGENT и последний вызов" "STALL-AGENT wf_live-1/a1" --session "$s" --ps "$T/ps"
probe 1 "  …находка называет команду" "until grep -q rc= run.log" --session "$s" --ps "$T/ps"
s="$(session waitmodel)"; rec "$s/subagents/workflows/wf_live-1/agent-a1.jsonl" 30 result
probe 1 "инъекция: результат 30 мин без ответа модели — STALL-AGENT" "STALL-AGENT" --session "$s" --ps "$T/ps"
# ws#1242 п.2: запись user «[Request interrupted …]» — подпись «прервано пользователем», вид
# прежний (`result`: тот же STALL-AGENT); близнец — обычное сообщение, прежняя подпись.
intr_cases() {
    local s
    s="$(session intr)"; rec "$s/subagents/agent-i1.jsonl" 30 intr
    absent="ответ модели на сообщение" probe 1 "прерывание блоком text — STALL-AGENT, подпись «прервано пользователем»" "STALL-AGENT agent-i1 — без нового вызова 30 мин; последний: прервано пользователем" --session "$s" --ps "$T/ps"
    s="$(session intrs)"; rec "$s/subagents/agent-i2.jsonl" 30 intrs
    probe 1 "прерывание строкой content — та же подпись" "последний: прервано пользователем" --session "$s" --ps "$T/ps"
    s="$(session intrmid)"; rec "$s/subagents/agent-i4.jsonl" 30 intrmid
    absent="прервано пользователем" probe 1 "близнец: фраза «[Request interrupted» в середине текста — прежняя подпись" "последний: ответ модели на сообщение" --session "$s" --ps "$T/ps"
    s="$(session asked)"; rec "$s/subagents/agent-i3.jsonl" 30 ask
    absent="прервано пользователем" probe 1 "близнец: обычное сообщение user — прежняя подпись, тот же вид" "STALL-AGENT agent-i3 — без нового вызова 30 мин; последний: ответ модели на сообщение" --session "$s" --ps "$T/ps"
}
intr_cases
s="$(session finished)"; rec "$s/subagents/workflows/wf_live-1/agent-a1.jsonl" 30 "done"
probe 0 "близнец: агент закончил ход 30 мин назад — не застой" - --session "$s" --ps "$T/ps"
s="$(session result)"; rec "$s/subagents/workflows/wf_live-1/agent-a1.jsonl" 30 tool
printf '{"type":"result","agentId":"a1"}\n' > "$s/subagents/workflows/wf_live-1/journal.jsonl"
probe 0 "близнец: тот же вызов, а в журнале workflow результат агента — не застой" - --session "$s" --ps "$T/ps"
s="$(session finished-wf)"; rec "$s/subagents/workflows/wf_live-1/agent-a1.jsonl" 30 tool
printf '{"runId":"wf_live-1","timestamp":"%s","status":"completed"}\n' "$(iso 30)" > "$s/workflows/wf_live-1.json"
probe 0 "близнец: workflow завершён и диспетчер ответил после — не застой" - --session "$s" --ps "$T/ps"
s="$(session top)"; mkdir -p "$s/subagents"; rec "$s/subagents/agent-t1.jsonl" 40 tool "gh run watch 1"
probe 1 "инъекция: агент верхнего уровня 40 мин в вызове — STALL-AGENT" "gh run watch 1" --session "$s" --ps "$T/ps"
s="$(session old)"; rec "$s/subagents/workflows/wf_live-1/agent-a1.jsonl" 500 tool
probe 0 "близнец: брошенный журнал старше окна 360 мин — не судится" - --session "$s" --ps "$T/ps"

echo "== опрос вместо работы (каждый вызов короче порога «нет вызова»)"
s="$(session poll)"; a="$s/subagents/workflows/wf_live-1/agent-a1.jsonl"
rec "$a" 30 tool "go build ./..."; rec "$a" 25 tool "until grep -q rc= run.log; do sleep 60; done"; rec "$a" 15 tool "gh run view 7 --json status"; rec "$a" 3 tool "tail --pid 42 -f run.log"
probe 1 "инъекция: три ожидания подряд за 25 мин — STALL-POLL и последний вызов" "STALL-POLL wf_live-1/a1" --session "$s" --ps "$T/ps"
s="$(session poll-work)"; a="$s/subagents/workflows/wf_live-1/agent-a1.jsonl"
rec "$a" 25 tool "until grep -q rc= run.log; do sleep 60; done"; rec "$a" 15 tool "gh run view 7 --json status"; rec "$a" 3 tool "go test ./internal/x/"
probe 0 "близнец: те же ожидания, но последний вызов — работа — молчит" - --session "$s" --ps "$T/ps"
s="$(session poll-young)"; a="$s/subagents/workflows/wf_live-1/agent-a1.jsonl"
rec "$a" 8 tool "until grep -q rc= run.log; do sleep 60; done"; rec "$a" 2 tool "gh pr checks 7"
probe 0 "близнец: два ожидания, первое 8 мин назад (порог 20) — молчит" - --session "$s" --ps "$T/ps"

echo "== завершённый агент не судится (ws#1110: agent-ad76971c71962c092 вернул итог, перепись звала его STALL-POLL)"
# finish_cases — пробы завершения; их же гонят мутанты ниже.
finish_cases() {
    local s a
    s="$(session fin-poll)"; a="$s/subagents/workflows/wf_live-1/agent-a1.jsonl"
    rec "$a" 30 tool "until grep -q rc= run.log; do sleep 60; done"; rec "$a" 25 tool "timeout 30 gh pr checks 1119"; rec "$a" 24 final
    probe 0 "близнец: два опроса за 30 мин, затем итог агента — молчит" "завершённых (не судятся) 1" --session "$s" --ps "$T/ps"
    probe 0 "  …завершённый 24 мин — вне счёта осмотренных" "агентов осмотрено 0" --session "$s" --ps "$T/ps"
    s="$(session fin-top)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 30 tool "until grep -q rc= run.log; do sleep 60; done"; rec "$a" 25 tool "timeout 30 gh pr checks 1119"; rec "$a" 24 final
    probe 0 "близнец: агент верхнего уровня — те же опросы и итог — молчит" "завершённых (не судятся) 1" --session "$s" --ps "$T/ps"
    probe 0 "  …и вне счёта осмотренных" "агентов осмотрено 0" --session "$s" --ps "$T/ps"
    s="$(session fin-fresh)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 30 tool "until grep -q rc= run.log; do sleep 60; done"; rec "$a" 25 tool "timeout 30 gh pr checks 1119"; rec "$a" 2 final
    probe 0 "близнец: итог 2 мин назад (порог завершённого 5) — молчит, в счёте осмотренных" "агентов осмотрено 1" --session "$s" --ps "$T/ps"
    s="$(session fin-resumed)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 50 final; rec "$a" 40 ask; rec "$a" 30 tool "until grep -q rc= run.log; do sleep 60; done"; rec "$a" 3 tool "timeout 30 gh pr checks 1119"
    probe 1 "инъекция: итог, затем возобновление и два опроса — STALL-POLL" "STALL-POLL agent-t1" --session "$s" --ps "$T/ps"
    # ws#1130: agent-a36ae50961e5c41b1 вернул итог записью без stop_reason, журнал
    # молчал 150 мин, а перепись звала его STALL-POLL со счётом минут от первого опроса.
    s="$(session fin-quiet)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 30 tool "until grep -q rc= run.log; do sleep 60; done"; rec "$a" 25 tool "timeout 30 gh pr checks 1119"; rec "$a" 24 "done"
    probe 0 "близнец: опросы, затем текст без stop_reason и журнал молчит 24 мин (порог агента 15) — итог, молчит" "завершённых (не судятся) 1" --session "$s" --ps "$T/ps"
    s="$(session fin-quiet-wf)"; a="$s/subagents/workflows/wf_live-1/agent-a1.jsonl"
    rec "$a" 30 tool "until grep -q rc= run.log; do sleep 60; done"; rec "$a" 25 tool "timeout 30 gh pr checks 1119"; rec "$a" 24 "done"
    probe 0 "близнец: то же в workflow — итог, молчит" "завершённых (не судятся) 1" --session "$s" --ps "$T/ps"
    s="$(session fin-edge-14)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 30 tool "until grep -q rc= run.log; do sleep 60; done"; rec "$a" 25 tool "timeout 30 gh pr checks 1119"; rec "$a" 14 "done"
    probe 1 "граница: текст без stop_reason, журнал молчит 14 мин (порог 15) — ход может продолжиться, STALL-POLL" "STALL-POLL agent-t1" --session "$s" --ps "$T/ps"
    s="$(session fin-edge-16)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 30 tool "until grep -q rc= run.log; do sleep 60; done"; rec "$a" 25 tool "timeout 30 gh pr checks 1119"; rec "$a" 16 "done"
    probe 0 "граница: тот же журнал молчит 16 мин — итог, молчит" "завершённых (не судятся) 1" --session "$s" --ps "$T/ps"
    s="$(session fin-open)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 30 tool "until grep -q rc= run.log; do sleep 60; done"; rec "$a" 25 tool "timeout 30 gh pr checks 1119"; rec "$a" 3 "done"
    probe 1 "инъекция: текст без stop_reason 3 мин назад после опросов — вызов может следовать, STALL-POLL" "STALL-POLL agent-t1" --session "$s" --ps "$T/ps"
    s="$(session fin-midthink)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 30 tool "until grep -q rc= run.log; do sleep 60; done"; rec "$a" 25 tool "timeout 30 gh pr checks 1119"; rec "$a" 24 midthink
    probe 1 "инъекция: thinking со stop_reason tool_use без вызова после опросов — ход не окончен, STALL-POLL" "STALL-POLL agent-t1" --session "$s" --ps "$T/ps"
    s="$(session fin-midtext)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 30 tool "until grep -q rc= run.log; do sleep 60; done"; rec "$a" 25 tool "timeout 30 gh pr checks 1119"; rec "$a" 24 midtext
    probe 1 "инъекция: text со stop_reason tool_use без вызова после опросов — ход не окончен, STALL-POLL" "STALL-POLL agent-t1" --session "$s" --ps "$T/ps"
    s="$(session fin-stuck)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 30 tool "until grep -q rc= run.log; do sleep 60; done"; rec "$a" 25 tool "timeout 30 gh pr checks 1119"
    probe 1 "инъекция: два опроса без итога, вызов не закрыт — STALL-POLL" "STALL-POLL agent-t1" --session "$s" --ps "$T/ps"
}
finish_cases
# fmutant <имя> <было> <стало> [пробы]: копия прибора с одной правкой; пробы
# (по умолчанию finish_cases) обязаны разойтись хоть в одной.
fmutant() {
    local MD="$T/fmut/scripts" p0="$pass" f0="$fail" mp mf C0="$C"
    rm -rf "$T/fmut"; mkdir -p "$MD/lib"; cp "$HERE/lib/ws-home.sh" "$MD/lib/"
    if ! python3 - "$C" "$MD/stall-census.sh" "$2" "$3" <<'MUTPY'
import sys
src, dst, was, now = sys.argv[1:5]
s = open(src).read()
if s.count(was) != 1:
    sys.exit(1)
open(dst, 'w').write(s.replace(was, now))
MUTPY
    then echo "  [FAIL] мутант «$1»: образец не найден в приборе — не лёг" >&2; fail=$((fail + 1)); return; fi
    failed=""; quiet=1; C="$MD/stall-census.sh"
    "${4:-finish_cases}"
    C="$C0"; quiet=""; mp=$((pass - p0)); mf=$((fail - f0)); pass="$p0"; fail="$f0"
    if [ "$mf" -gt 0 ]; then
        echo "  [OK]   мутант «$1» красный: разошлось $mf из $((mp + mf)): ${failed#; }"; pass=$((pass + 1))
    else
        echo "  [FAIL] мутант «$1» выжил: все $mp проб сошлись" >&2; fail=$((fail + 1))
    fi
}
fmutant "прерывание — вхождение, а не начало текста" "str(x).lstrip().startswith('[Request interrupted')" "'[Request interrupted' in str(x)" intr_cases
fmutant "прерывание — общая подпись (до ws#1242)" "        return t, 'result', 'прервано пользователем'" "        return t, 'result', 'ответ модели на сообщение'" intr_cases
fmutant "не проверять завершение" "FINAL_STOP = ('end_turn', 'stop_sequence', 'refusal')" "FINAL_STOP = ()"
fmutant "завершение — любой ответ без вызова" "('final' if fin else 'done')" "'final'"
fmutant "итог без stop_reason не узнаётся (до ws#1130)" " or (sr is None and now - os.path.getmtime(path) >= AGENT_MIN * 60)" ""
fmutant "тишина журнала не различается" "sr is None and now - os.path.getmtime(path) >= AGENT_MIN * 60" "sr is None"
fmutant "tool_use — завершение" "FINAL_STOP = ('end_turn', 'stop_sequence', 'refusal')" "FINAL_STOP = ('end_turn', 'stop_sequence', 'refusal', 'tool_use')"
fmutant "завершение — любой непустой stop_reason" "sr in FINAL_STOP or" "sr or"
fmutant "завершённый в workflow не пропускается" $'                if age_file < DONE_MIN * 60:\n                    agents_seen += 1\n                continue' $'                if age_file < DONE_MIN * 60:\n                    agents_seen += 1'
fmutant "давность не различается" $'\n            if age_file < DONE_MIN * 60:\n                agents_seen += 1\n            continue' $'\n            agents_seen += 1\n            continue'

echo "== агент, остановленный харнессом не судится (ws#1033: убитый TaskStop числился застоем, журнал кончался записью user)"
# note <главный журнал> <минут назад> <id> <статус> [операция [текст]> — терминальное
# уведомление харнесса; resume — ответ SendMessage о возобновлении (формы живого журнала).
note() { printf '{"type":"queue-operation","operation":"%s","timestamp":"%s","sessionId":"x","content":"<task-notification>\\n<task-id>%s</task-id>\\n<status>%s</status>\\n<summary>Agent stopped</summary>\\n<result>%s</result>\\n</task-notification>"}\n' "${5:-enqueue}" "$(iso "$2")" "$3" "$4" "${6:-итог}" >> "$1"; }
resume() { printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":[{"type":"tool_result","content":"{\\"success\\":true,\\"message\\":\\"Resuming agent %s\\",\\"resumedAgentId\\":\\"%s\\"}"}]}}\n' "$(iso "$2")" "$3" "$3" >> "$1"; }
# stop_cases — пробы остановки; их же гонят мутанты ниже.
stop_cases() {
    local s a st
    rm -rf "$T"/stop-*  # прогон мутанта начинает с чистых журналов: rec и note дописывают
    for st in killed completed failed stopped; do
        s="$(session stop-$st)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
        rec "$a" 60 tool; rec "$a" 40 ask
        note "$s.jsonl" 40 t1 "$st"
        absent="STALL-AGENT" probe 0 "близнец: харнесс остановил агента ($st), журнал кончается записью user — не застой" "остановленных харнессом (не судятся) 1" --session "$s" --ps "$T/ps"
    done
    s="$(session stop-result)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 60 tool; rec "$a" 40 result
    note "$s.jsonl" 40 t1 killed
    absent="STALL-AGENT" probe 0 "близнец: остановлен, журнал кончается результатом инструмента — не застой" "остановленных харнессом (не судятся) 1" --session "$s" --ps "$T/ps"
    s="$(session stop-live)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 60 tool; rec "$a" 40 ask
    probe 1 "инъекция: тот же журнал без уведомления харнесса — агент жив и стоит, STALL-AGENT" "STALL-AGENT agent-t1" --session "$s" --ps "$T/ps"
    s="$(session stop-resumed-worked)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 70 tool; rec "$a" 60 ask; rec "$a" 50 ask; rec "$a" 40 tool "go test ./..."
    note "$s.jsonl" 60 t1 killed; resume "$s.jsonl" 50 t1
    probe 1 "инъекция: остановлен, возобновлён, работал и снова стоит 40 мин — STALL-AGENT" "STALL-AGENT agent-t1" --session "$s" --ps "$T/ps"
    s="$(session stop-resumed-unseen)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 70 tool; rec "$a" 60 ask; rec "$a" 50 ask; rec "$a" 40 tool "go test ./..."
    note "$s.jsonl" 60 t1 killed
    probe 1 "инъекция: после остановки агент дописал журнал, возобновления в главном журнале нет — жив, STALL-AGENT" "STALL-AGENT agent-t1" --session "$s" --ps "$T/ps"
    s="$(session stop-resumed-silent)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 60 tool; rec "$a" 40 ask
    note "$s.jsonl" 40 t1 killed; resume "$s.jsonl" 39 t1
    probe 1 "инъекция: возобновление после остановки, журнал молчит — харнесс исполняет, STALL-AGENT" "STALL-AGENT agent-t1" --session "$s" --ps "$T/ps"
    s="$(session stop-dequeue)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 60 tool; rec "$a" 40 ask
    note "$s.jsonl" 40 t1 killed; resume "$s.jsonl" 39 t1; note "$s.jsonl" 38 t1 killed remove
    probe 1 "инъекция: снятие уведомления из очереди позже возобновления — не новая остановка, STALL-AGENT" "STALL-AGENT agent-t1" --session "$s" --ps "$T/ps"
    s="$(session stop-other)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 60 tool; rec "$a" 40 ask
    note "$s.jsonl" 40 t2 killed enqueue "итог ждёт t1"
    probe 1 "инъекция: остановлен другой агент, t1 назван лишь в тексте — STALL-AGENT" "STALL-AGENT agent-t1" --session "$s" --ps "$T/ps"
    s="$(session stop-big)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 60 tool; rec "$a" 40 ask
    note "$s.jsonl" 40 t1 killed
    local pad; pad="$(head -c 1000000 /dev/zero | tr '\0' 'x')"
    for _ in 1 2 3 4 5; do printf '{"type":"attachment","timestamp":"%s","pad":"%s"}\n' "$(iso 30)" "$pad" >> "$s.jsonl"; done
    absent="STALL-AGENT" probe 0 "близнец: уведомление глубже хвоста 4 МиБ главного журнала — окно растёт, не застой" "остановленных харнессом (не судятся) 1" --session "$s" --ps "$T/ps"
    s="$(session stop-poll)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 45 tool "until grep -q rc= run.log; do sleep 60; done"; rec "$a" 44 tool "timeout 30 gh pr checks 1119"; rec "$a" 40 ask
    probe 1 "инъекция: два опроса и тишина, уведомления нет — STALL-POLL" "STALL-POLL agent-t1" --session "$s" --ps "$T/ps"
    note "$s.jsonl" 40 t1 killed
    absent="STALL-POLL" probe 0 "близнец: те же опросы, агент остановлен харнессом — не STALL-POLL" "остановленных харнессом (не судятся) 1" --session "$s" --ps "$T/ps"
}
stop_cases
fmutant "остановка харнессом не читается" "    return n_last is not None and n_last >= t - 3 and (r_last is None or r_last < n_last)" "    return False" stop_cases
fmutant "возобновление после остановки не учитывается" "(r_last is None or r_last < n_last)" "True" stop_cases
fmutant "возобновление не разбирается" "            if resumed.search(l):" "            if False:" stop_cases
fmutant "уведомление старше записей агента принимается" " and n_last >= t - 3" "" stop_cases
fmutant "снятие из очереди — уведомление" "(r.get('type') == 'queue-operation' and r.get('operation') != 'enqueue')" "False" stop_cases

echo "== серия ожиданий считается после последней остановки или возобновления (ws#1343)"
# Живая форма 2026-10-22, wf_1995dfee-95d/aa0336b715ac9bf1c: 6 ожиданий, затем возобновление,
# прерывание и killed, снова возобновление; возобновлённый пишет в subagents/agent-<id>.jsonl,
# журнал workflow заморожен с хвостом ожиданий — хук звал его STALL-POLL на каждом ходе.
waits() { local a="$1" m; shift; for m in "$@"; do rec "$a" "$m" tool "flock -w 290 /s/ciwait/head.lock true; gh run view 7 --json status"; done; }
reset_cases() {
    local s a w
    rm -rf "$T"/rs-*
    s="$(session rs-top)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    waits "$a" 60 55 50 45 40; rec "$a" 39 ask; note "$s.jsonl" 39 t1 killed; resume "$s.jsonl" 10 t1; rec "$a" 10 ask
    absent="STALL-" probe 0 "Р1 пять ожиданий → остановка → возобновление → ни одного ожидания — молчит" "агентов осмотрено 1" --session "$s" --ps "$T/ps"
    s="$(session rs-top-again)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    waits "$a" 60 55 50 45 40; rec "$a" 39 ask; note "$s.jsonl" 39 t1 killed; resume "$s.jsonl" 35 t1; rec "$a" 35 ask
    waits "$a" 34 30 25 20 14
    probe 1 "Р2 близнец: после возобновления пять ожиданий за 34 мин — STALL-POLL" "STALL-POLL agent-t1 — ожидание вместо работы: 5 вызовов подряд за 34 мин" --session "$s" --ps "$T/ps"
    s="$(session rs-wf)"; w="$s/subagents/workflows/wf_live-1/agent-w1.jsonl"; a="$s/subagents/agent-w1.jsonl"
    waits "$w" 60 55 50 45 40; rec "$w" 39 intr; note "$s.jsonl" 39 w1 killed; resume "$s.jsonl" 38 w1
    rec "$a" 38 ask; rec "$a" 2 tool "go test ./..."
    absent="STALL-" probe 0 "Р3 агент workflow остановлен и продолжен журналом верхнего уровня — замороженный журнал не судится" "остановленных харнессом (не судятся) 1" --session "$s" --ps "$T/ps"
    s="$(session rs-wf-again)"; w="$s/subagents/workflows/wf_live-1/agent-w1.jsonl"; a="$s/subagents/agent-w1.jsonl"
    waits "$w" 60 55 50 45 40; rec "$w" 39 intr; note "$s.jsonl" 39 w1 killed; resume "$s.jsonl" 38 w1
    rec "$a" 38 ask; waits "$a" 34 30 25 20 14
    absent="STALL-POLL wf_live-1/w1" probe 1 "Р4 близнец: продолжение снова ждёт пять раз — STALL-POLL по продолжению" "STALL-POLL agent-w1 — ожидание вместо работы: 5 вызовов подряд за 34 мин" --session "$s" --ps "$T/ps"
    s="$(session rs-intr)"; w="$s/subagents/workflows/wf_live-1/agent-w1.jsonl"
    waits "$w" 60 55 50 45 40; rec "$w" 10 intr
    absent="STALL-POLL" probe 0 "Р5 запись прерывания в журнале после серии — серия кончилась" "агентов осмотрено 1" --session "$s" --ps "$T/ps"
    s="$(session rs-any)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    waits "$a" 60 55 50 45 40; rec "$a" 12 intrmid; rec "$a" 10 ask
    printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"tool_use","name":"SendMessage","input":{"to":"t1","message":"верни остаток"}}]}}\n' "$(iso 10)" >> "$s.jsonl"
    probe 1 "Р6 близнец: после серии лишь сообщение, фраза о прерывании и упоминание id в главном журнале — не сброс, STALL-POLL" "STALL-POLL agent-t1 — ожидание вместо работы: 5 вызовов подряд за 60 мин" --session "$s" --ps "$T/ps"
}
reset_cases
fmutant "сброс серии игнорируется" "        n, span, last, first = poll_run(path, last_reset(aid, first))" "        pass" reset_cases
fmutant "сброс по любой записи главного журнала, а не по остановке" "            if resumed.search(l):" "            if True:" reset_cases
fmutant "сброс по любой записи user агента, а не по прерыванию" "        if r.get('type') == 'user' and interrupted(r):" "        if r.get('type') == 'user':" reset_cases
fmutant "прерывание в журнале — не сброс" "        if r.get('type') == 'user' and interrupted(r):" "        if False:" reset_cases
fmutant "продолжение в журнале верхнего уровня не ищется" "            if moved(aid, apath):" "            if False:" reset_cases

echo "== агент прежнего процесса claude не судится (2026-10-19: после --resume хук звал застоем агентов умершего процесса)"
# restart_cases — свой claude 100 (CLAUDE_PID) со стартом etimes назад; агент писал до
# старта — исполнялся прежним процессом; близнец — тот же журнал при claude старше агента.
restart_cases() {
    local s a
    rm -rf "$T"/rst-*
    printf '%s\n' "100 1 600 claude claude --resume x" > "$T/ps-young"     # стартовал 10 мин назад
    printf '%s\n' "100 1 90000 claude claude --resume x" > "$T/ps-elder"   # стартовал 1500 мин назад
    s="$(session rst-top)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 30 tool "go test ./..."
    CLAUDE_PID=100 absent="STALL-AGENT" probe 0 "агент верхнего уровня писал 30 мин назад, claude стартовал 10 мин назад — оборван перезапуском, не застой" "оборванных перезапуском claude (не судятся) 1" --session "$s" --ps "$T/ps-young"
    CLAUDE_PID=100 probe 1 "близнец: тот же журнал, claude старше агента — STALL-AGENT" "STALL-AGENT agent-t1" --session "$s" --ps "$T/ps-elder"
    s="$(session rst-poll)"; a="$s/subagents/workflows/wf_live-1/agent-a1.jsonl"
    rec "$a" 40 tool "until grep -q rc= run.log; do sleep 60; done"; rec "$a" 30 tool "gh run view 7 --json status"; rec "$a" 12 tool "gh pr checks 7"
    CLAUDE_PID=100 absent="STALL-POLL" probe 0 "агент workflow опрашивал до старта claude — оборван перезапуском, не STALL-POLL" "оборванных перезапуском claude (не судятся) 1" --session "$s" --ps "$T/ps-young"
    CLAUDE_PID=100 probe 1 "близнец: те же опросы при живом claude старше — STALL-POLL" "STALL-POLL wf_live-1/a1" --session "$s" --ps "$T/ps-elder"
    touch -d "@$((NOW - 180))" "$a"   # журнал дописан после старта записью без разбираемого времени
    CLAUDE_PID=100 probe 1 "близнец: журнал менялся после старта claude (mtime 3 мин) — жив, STALL-POLL" "STALL-POLL wf_live-1/a1" --session "$s" --ps "$T/ps-young"
    s="$(session rst-resumed)"; mkdir -p "$s/subagents"; a="$s/subagents/agent-t1.jsonl"
    rec "$a" 60 tool; rec "$a" 5 ask
    CLAUDE_PID=100 probe 0 "возобновлённый после старта (запись 5 мин назад) — судим заново, не «оборван»" "оборванных перезапуском claude (не судятся) 0" --session "$s" --ps "$T/ps-young"
    probe 1 "близнец: свой claude не определён (нет CLAUDE_PID) — прежний суд, STALL-AGENT" "STALL-AGENT agent-t1" --session "$(printf '%s' "$T/rst-top")" --ps "$T/ps-young"
}
restart_cases
fmutant "старт своего claude не читается" "    own_start = now - procs[own_pid][1]" "    own_start = None" restart_cases
fmutant "любой агент — прежнего процесса" "if own_start is not None and last_t < own_start - 2:" "if own_start is not None:" restart_cases
fmutant "mtime журнала не учитывается (только время записи)" "max(t or 0, os.path.getmtime(apath))" "(t or 0)" restart_cases
fmutant "любой id в уведомлении" "rb'<task-id>' + re.escape(ab) + rb'</task-id>(?:" "rb'<task-id>[0-9a-z]+</task-id>(?:" stop_cases
fmutant "окно чтения не растёт" "        size = min(size * 4, total)" "        break" stop_cases
fmutant "STALL-POLL без проверки остановки" "            if harness_stopped(aid, tt):" "            if False:" stop_cases
fmutant "STALL-AGENT без проверки остановки" "            if harness_stopped(aid, t):" "            if False:" stop_cases

echo "== workflow без реакции"
s="$(session unreacted)"
: > "$s.jsonl"; rec "$s.jsonl" 60 "done"
printf '{"runId":"wf_x","workflowName":"wave-7","timestamp":"%s","status":"completed"}\n' "$(iso 30)" > "$s/workflows/wf_x.json"
probe 1 "инъекция: workflow завершён 30 мин назад, диспетчер молчит с 60 мин — UNREACTED-WF" "UNREACTED-WF wf_x «wave-7»" --session "$s" --ps "$T/ps"
s="$(session reacted)"
printf '{"runId":"wf_x","workflowName":"wave-7","timestamp":"%s","status":"completed"}\n' "$(iso 30)" > "$s/workflows/wf_x.json"
probe 0 "близнец: диспетчер ответил после завершения — молчит" - --session "$s" --ps "$T/ps"

echo "== процессы"
s="$(session procs)"
{ ps_ok; echo "201 100 7200 bash /bin/bash -c source /h/.claude/shell-snapshots/s.sh && eval 'until ! pgrep make; do sleep 30; done'"; } > "$T/ps-old"
CLAUDE_PID=100 probe 1 "инъекция: оболочка агента живёт 120 мин — STALL-PROC с командой" "STALL-PROC pid 201" --session "$s" --ps "$T/ps-old"
{ ps_ok; echo "201 100 1800 bash /bin/bash -c source /h/.claude/shell-snapshots/s.sh && eval 'make e2e'"; } > "$T/ps-young"
probe 0 "близнец: та же оболочка 30 мин — молчит" - --session "$s" --ps "$T/ps-young"
{ ps_ok; echo "202 1 7200 bash /bin/bash -c source /h/.claude/shell-snapshots/s.sh && eval 'x'"; } > "$T/ps-orphan"
probe 0 "близнец: оболочка 120 мин, но родитель не claude — не судится" - --session "$s" --ps "$T/ps-orphan"

echo "== процессы: возраст из ps, которого не может быть (ws#1149)"
# Живая форма 2026-10-17, procps-ng 4.0.4: процесс, родившийся во время работы ps,
# получает etimes=4123168608 (881 строка из 224871 при 4000 порождениях под
# 150 снимками) — хук печатал «STALL-PROC … живёт 68719476 мин».
EB="/bin/bash -c source /h/.claude/shell-snapshots/s.sh && eval"
{ echo "100 1 90000 claude claude --x"; echo "203 100 4123168608 bash $EB 'make e2e'"; } > "$T/ps-wrap"
{ echo "100 1 4123168608 claude claude --x"; echo "203 100 4123168608 bash $EB 'make e2e'"; } > "$T/ps-wrap2"
{ echo "100 1 90000 claude claude --x"; echo "203 100 -5 bash $EB 'make e2e'"; echo "204 100 x bash $EB 'make e2e'"; } > "$T/ps-junk"
{ echo "100 1 90000 claude claude --x"; echo "204 100 3601 bash $EB 'make e2e'"; } > "$T/ps-edge"
{ echo "100 1 7200 claude claude --x"; echo "204 100 7200 bash $EB 'make e2e'"; } > "$T/ps-eqpar"
{ echo "100 1 90000 claude claude --x"; echo "204 100 5000 bash $EB 'make e2e'"; } > "$T/ps-equp"
mkdir -p "$T/proc-up"; echo "5000.00 1.00" > "$T/proc-up/uptime"
ES="$s"  # сессия проб возраста: мутанты ниже гонят их, когда $s уже другая
# etimes_cases <прибор> — пробы правдоподобия возраста; их же гонят мутанты ниже.
etimes_cases() {
    local C="$1"
    CLAUDE_PID=100 absent="STALL-PROC pid 203" probe 0 "Е1 инъекция: etimes 4123168608 старше родителя-claude — не STALL-PROC" "неправдоподобного возраста 1" --session "$ES" --ps "$T/ps-wrap"
    CLAUDE_PID=100 absent="pid 203" probe 0 "  …без --verbose pid и возраст не печатаются" - --session "$ES" --ps "$T/ps-wrap"
    CLAUDE_PID=100 probe 0 "  …с --verbose — строка «не судится» с потолком" "возраст неправдоподобен — не судится: pid 203 (claude 100): 4123168608 с > родитель 90000 с" --session "$ES" --ps "$T/ps-wrap" --verbose
    CLAUDE_PID=100 STALL_PROC_ROOT="$T/proc-up" absent="STALL-PROC pid 203" probe 0 "Е2 инъекция: родитель тоже 4123168608, аптайм 5000 с — не STALL-PROC" "неправдоподобного возраста 1" --session "$ES" --ps "$T/ps-wrap2"
    CLAUDE_PID=100 absent="STALL-PROC pid 20" probe 0 "Е3 инъекция: etimes -5 и x — не судятся и сосчитаны" "неправдоподобного возраста 2" --session "$ES" --ps "$T/ps-junk"
    CLAUDE_PID=100 STALL_PROC_ROOT="$T/proc-up" probe 1 "Е4 близнец: 3601 с (порог 3600 + 1), не старше родителя и аптайма — STALL-PROC" "STALL-PROC pid 204 (claude 100) — живёт 60 мин" --session "$ES" --ps "$T/ps-edge"
    CLAUDE_PID=100 probe 1 "Е5 граница: возраст равен возрасту родителя — STALL-PROC" "STALL-PROC pid 204" --session "$ES" --ps "$T/ps-eqpar"
    CLAUDE_PID=100 STALL_PROC_ROOT="$T/proc-up" probe 1 "Е6 граница: возраст равен аптайму — STALL-PROC" "STALL-PROC pid 204" --session "$ES" --ps "$T/ps-equp"
}
etimes_cases "$C"

echo "== процессы: судится только своя сессия (ws#1131)"
# Живая форма 2026-10-17: claude 61051 «--resume 3f44acf5-…» из другого окна с
# сериями newman держал ход диспетчера сессии 9131a334 строкой STALL-PROC.
OWN=9131a334-32c0-465b-acab-ee88633ea4e4 FOR=3f44acf5-eb2b-55dd-ba20-9ef6786c26b4
SNAP="/bin/bash -c source /h/.claude/shell-snapshots/s.sh && eval"
{ echo "100 1 90000 claude claude --x"; echo "110 1 90000 claude claude --dangerously-skip-permissions --resume $FOR"
  echo "211 110 7200 bash $SNAP 'newman run x'"; echo "300 1 99999 sshd sshd"; } > "$T/ps-foreign"
{ echo "100 1 90000 claude claude --resume $OWN"; echo "110 1 90000 claude claude --resume $FOR"
  echo "201 100 7200 bash $SNAP 'make e2e'"; echo "211 110 7200 bash $SNAP 'newman run x'"
  echo "500 100 5 bash bash hook"; } > "$T/ps-both"
{ echo "100 1 90000 claude claude --x"; echo "110 1 90000 claude claude --resume $OWN --fork-session"
  echo "211 110 7200 bash $SNAP 'newman run x'"; } > "$T/ps-fork"
{ echo "100 1 90000 claude claude --x"; echo "110 1 90000 claude claude --y"
  echo "211 110 7200 bash $SNAP 'newman run x'"; } > "$T/ps-env"
# Приёмка ws#1131 (⛔): другой pid claude — не довод «чужая»: `claude -c` той же
# сессии; CLAUDE_PID, унаследованный от чужого окна.
{ echo "100 1 90000 claude claude --x"; echo "110 1 90000 claude claude -c"
  echo "211 110 7200 bash $SNAP 'make e2e'"; } > "$T/ps-cont"
{ echo "100 1 90000 claude claude --x"; echo "110 1 90000 claude claude --resume $FOR"
  echo "211 100 7200 bash $SNAP 'make e2e'"; } > "$T/ps-pidfor"
mkdir -p "$T/proc-for/211" "$T/proc-own/211"
printf 'PATH=/x\0CLAUDE_CODE_SESSION_ID=%s\0' "$FOR" > "$T/proc-for/211/environ"
printf 'PATH=/x\0CLAUDE_CODE_SESSION_ID=%s\0' "$OWN" > "$T/proc-own/211/environ"
# proc_cases <прибор> — пробы отбора своей сессии; их же гонит мутант отбора.
proc_cases() {
    local C="$1"
    CLAUDE_PID=100 CLAUDE_CODE_SESSION_ID=$OWN probe 0 "П1 инъекция: чужая сессия (--resume в родителе), оболочка 120 мин — молчит" "чужих 1" --session "$s" --ps "$T/ps-foreign"
    CLAUDE_PID=100 probe 2 "П2 другой claude при одном CLAUDE_PID, своей сессии нет — не судимо, а не «чужая»" "не судимо 1" --session "$s" --ps "$T/ps-foreign"
    CLAUDE_CODE_SESSION_ID=$OWN probe 1 "П3 своя по --resume родителя: своя 120 мин — STALL-PROC" "STALL-PROC pid 201 (claude 100)" --session "$s" --ps "$T/ps-both"
    CLAUDE_CODE_SESSION_ID=$OWN probe 1 "  …а чужая рядом не названа" "своих 1, чужих 1" --session "$s" --ps "$T/ps-both"
    probe 1 "П4 своя по предку-claude процесса (--self): STALL-PROC" "STALL-PROC pid 201 (claude 100)" --session "$s" --ps "$T/ps-both" --self 500
    probe 2 "П5 сессия не определена — отдельная строка и код 2, а не «чисто» и не суд всех" "STALL-PROC: сессия не определена" --session "$s" --ps "$T/ps-foreign"
    CLAUDE_CODE_SESSION_ID=$OWN probe 2 "П6 --fork-session: id в строке запуска — не сессия, оболочка не судима" "не судимо 1" --session "$s" --ps "$T/ps-fork"
    CLAUDE_CODE_SESSION_ID=$OWN STALL_PROC_ROOT="$T/proc-for" probe 0 "П7 чужая по окружению оболочки — молчит" "чужих 1" --session "$s" --ps "$T/ps-env"
    CLAUDE_CODE_SESSION_ID=$OWN STALL_PROC_ROOT="$T/proc-own" probe 1 "П8 своя по окружению оболочки — STALL-PROC" "STALL-PROC pid 211" --session "$s" --ps "$T/ps-env"
    CLAUDE_PID=100 CLAUDE_CODE_SESSION_ID=$OWN probe 2 "M3c второй claude -c той же сессии, окружение не прочитано — не судимо, а не «чужая»" "не судимо 1" --session "$s" --ps "$T/ps-cont"
    CLAUDE_PID=110 CLAUDE_CODE_SESSION_ID=$OWN probe 2 "M6b CLAUDE_PID на чужом claude, окружение не прочитано, свой без --resume — не судимо" "не судимо 1" --session "$s" --ps "$T/ps-pidfor"
    CLAUDE_PID=999 CLAUDE_CODE_SESSION_ID=$OWN probe 0 "П9 CLAUDE_PID не claude в снимке — не берётся, чужая молчит" "чужих 1" --session "$s" --ps "$T/ps-foreign"
}
proc_cases "$C"

echo "== процессы: отсоединённые своей сессии — по метке окружения (ws#1154)"
# Живая форма: прогон полосы `setsid env … sh -c '…' &` после выхода оболочки
# переподчинён (родитель — не claude) и прежней выборкой «прямой потомок claude»
# не осматривался вовсе. Отбор — метка окружения CLAUDE_CODE_SESSION_ID/CLAUDE_PID,
# не строка запуска: строки запуска ниже одинаковы у находки и у близнецов.
DS="$(session detached)"
DCMD="sh -c go test ./...; echo 0 > /t/r.rc"
dps() {  # dps <файл> <возраст claude 100, с> <возраст корня, с>
    { echo "100 1 $2 claude claude --x"; echo "400 1 $3 sh $DCMD"; echo "401 400 $3 go go test ./..."
      echo "300 1 99999 sshd sshd"; } > "$1"
}
denv() {  # denv <каталог proc> <сессия> <CLAUDE_PID> [KACHO_DETACHED_UNTIL]
    local d
    for d in 400 401; do
        mkdir -p "$1/$d"
        printf 'PATH=/x\0CLAUDE_CODE_SESSION_ID=%s\0CLAUDE_PID=%s\0%s' "$2" "$3" "${4:+KACHO_DETACHED_UNTIL=$4}" > "$1/$d/environ"
    done
    mkdir -p "$1/300"; printf 'PATH=/x\0' > "$1/300/environ"
}
dps "$T/ps-det" 90000 7200
dps "$T/ps-det-young" 90000 1800
dps "$T/ps-det-reuse" 600 7200
denv "$T/proc-det-dead" "$OWN" 777
denv "$T/proc-det-live" "$OWN" 100
denv "$T/proc-det-term" "$OWN" 777 "$((NOW + 3600))"
denv "$T/proc-det-expired" "$OWN" 777 "$((NOW - 60))"
denv "$T/proc-det-foreign" "$FOR" 777
mkdir -p "$T/proc-empty"
# detached_cases <прибор> — пробы отсоединённых; их же гонят мутанты ниже.
detached_cases() {
    local C="$1"
    CLAUDE_CODE_SESSION_ID=$OWN STALL_PROC_ROOT="$T/proc-det-dead" absent="pid 401" probe 1 "Д1 инъекция: отсоединённый своей сессии 120 мин, claude 777 не жив — STALL-PROC корня, потомок не назван" "STALL-PROC pid 400 (отсоединён, claude 777 не жив)" --session "$DS" --ps "$T/ps-det"
    CLAUDE_CODE_SESSION_ID=$OWN STALL_PROC_ROOT="$T/proc-det-dead" probe 1 "  …перепись называет осмотренных отсоединённых" "корней 1 — своих 1 (claude жив 0, в объявленном сроке 0)" --session "$DS" --ps "$T/ps-det"
    CLAUDE_CODE_SESSION_ID=$OWN STALL_PROC_ROOT="$T/proc-det-live" probe 0 "Д2 живой близнец: тот же процесс, claude 100 жив — молчит" "claude жив 1" --session "$DS" --ps "$T/ps-det"
    CLAUDE_CODE_SESSION_ID=$OWN STALL_PROC_ROOT="$T/proc-det-term" probe 0 "Д3 законный близнец: демон в объявленном сроке (KACHO_DETACHED_UNTIL через 60 мин) — молчит" "в объявленном сроке 1" --session "$DS" --ps "$T/ps-det"
    CLAUDE_CODE_SESSION_ID=$OWN STALL_PROC_ROOT="$T/proc-det-expired" probe 1 "Д4 инъекция: срок демона истёк минуту назад — STALL-PROC, причина названа" "срок KACHO_DETACHED_UNTIL истёк" --session "$DS" --ps "$T/ps-det"
    CLAUDE_CODE_SESSION_ID=$OWN STALL_PROC_ROOT="$T/proc-det-foreign" probe 0 "Д5 чужая сессия (как П1, П7) — молчит" "корней 1 — своих 0 (claude жив 0, в объявленном сроке 0), чужих 1" --session "$DS" --ps "$T/ps-det"
    CLAUDE_CODE_SESSION_ID=$OWN STALL_PROC_ROOT="$T/proc-det-dead" probe 0 "Д6 близнец: сирота 30 мин (порог 60) — молчит" "своих 1" --session "$DS" --ps "$T/ps-det-young"
    CLAUDE_CODE_SESSION_ID=$OWN STALL_PROC_ROOT="$T/proc-det-live" probe 1 "Д7 инъекция: pid 100 переиспользован — claude моложе процесса, владелец не жив — STALL-PROC" "STALL-PROC pid 400 (отсоединён, claude 100 не жив)" --session "$DS" --ps "$T/ps-det-reuse"
    STALL_PROC_ROOT="$T/proc-det-dead" probe 2 "Д8 своя сессия не определена, сирота старше порога — не судимо, код 2, а не «чисто»" "не судимо 1" --session "$DS" --ps "$T/ps-det"
    CLAUDE_CODE_SESSION_ID=$OWN STALL_PROC_ROOT="$T/proc-empty" probe 2 "Д9 живой снимок, окружение не прочитано ни у одного — код 2, а не «чисто»" "окружение не прочитано ни у одного" --session "$DS" --self 1
}
detached_cases "$C"

echo "== нечитаемое — не «чисто»"
probe 2 "каталога сессии нет — код 2" "VOID" --session "$T/nope" --ps "$T/ps"
s="$(session emptyps)"; : > "$T/ps-empty"
probe 2 "снимок процессов пуст — код 2" "VOID" --session "$s" --ps "$T/ps-empty"
probe 2 "неизвестный довод — код 2" "VOID" --bogus

echo "== сессия находится из любой копии (ws#1010)"
# Урок: прибор, запущенный из архива origin/main во временном каталоге, искал
# журнал по $PWD и давал VOID при живой сессии. Здесь: HOME песочницы, «основная
# копия» FWS — рабочая копия git, её журналы — под $HOME/.claude/projects/<код>;
# архив скрипта — каталог БЕЗ git.
HM="$T/home" FWS="$T/fws"
git init -q "$FWS" 2> /dev/null && mkdir -p "$FWS/tmp"
PJ="$HM/.claude/projects/$(printf '%s' "$FWS" | sed 's/[^A-Za-z0-9]/-/g')"
mkdir -p "$PJ/sid/subagents/workflows/wf_live-1" "$PJ/sid/workflows" "$T/empty-proj"
rec "$PJ/sid.jsonl" 1 "done"
rec "$PJ/sid/subagents/workflows/wf_live-1/agent-a1.jsonl" 2 tool
ARC="$T/arc"; mkdir -p "$ARC/scripts/lib"; cp "$C" "$ARC/scripts/"; cp "$HERE/lib/ws-home.sh" "$ARC/scripts/lib/"
CP="$FWS/tmp/copy"; git init -q "$CP" 2> /dev/null; mkdir -p "$CP/scripts/lib"; cp "$C" "$CP/scripts/"; cp "$HERE/lib/ws-home.sh" "$CP/scripts/lib/"
# S2: копия со СВОИМ журналом, а журнал основной копии новее — побеждает копия
# (CLAUDE_PROJECT_DIR — первый кандидат). S4: каталог проекта копии есть, а
# журнала *.jsonl в нём нет — берётся основная копия, а не VOID (побеждает первый
# кандидат С ЖУРНАЛОМ, а не первый существующий каталог). check-verifier ws#1010.
pcode() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
CP2="$FWS/tmp/copy2"; git init -q "$CP2" 2> /dev/null
PJ2="$HM/.claude/projects/$(pcode "$CP2")"; mkdir -p "$PJ2/sidcopy/subagents/workflows/wf_live-1" "$PJ2/sidcopy/workflows"
rec "$PJ2/sidcopy.jsonl" 5 "done"
CP4="$FWS/tmp/copy4"; git init -q "$CP4" 2> /dev/null
PJ4="$HM/.claude/projects/$(pcode "$CP4")"; mkdir -p "$PJ4/memory"
# probe_in <код> <имя> <строка|-> <каталог запуска> <env NAME=VAL… | -> <скрипт> <довод…>
probe_in() {
    local want="$1" name="$2" needle="$3" dir="$4" ev="$5" sc="$6" got out
    shift 6
    local envs=(); [ "$ev" = - ] || read -r -a envs <<< "$ev"
    out="$(cd "$dir" && env -u CLAUDE_PROJECT_DIR HOME="$HM" "${envs[@]}" bash "$sc" "$@" < /dev/null 2>&1)"; got=$?
    if [ "$got" -eq "$want" ] && { [ "$needle" = - ] || grep -qF -- "$needle" <<< "$out"; }; then
        [ -n "${quiet:-}" ] || echo "  [OK]   $name (код $got)"; pass=$((pass + 1))
    else
        failed="${failed:-}; $name"
        [ -n "${quiet:-}" ] || echo "  [FAIL] $name — ждали код $want${needle:+ и «$needle»}, получили $got: $(head -c 400 <<< "$out")" >&2; fail=$((fail + 1))
    fi
}
# locate_cases <скрипт в архиве> — пробы поиска сессии; их же гонят мутанты ниже.
locate_cases() {
    local A="$1"
    probe_in 0 "инъекция: архив во временном каталоге, ключ --session-dir — сессия найдена" "сессия sid;" "$ARC" - "$A" --session-dir "$PJ" --ps "$T/ps"
    probe_in 0 "  …перепись названа" "агентов осмотрено 1" "$ARC" - "$A" --session-dir "$PJ" --ps "$T/ps"
    probe_in 0 "архив во временном каталоге, CLAUDE_PROJECT_DIR — основная копия: найдена" "сессия sid;" "$ARC" "CLAUDE_PROJECT_DIR=$FWS" "$A" --ps "$T/ps"
    probe_in 0 "CLAUDE_PROJECT_DIR — копия под <ws>/tmp/ без своего журнала: основная копия выведена ws-home" "сессия sid;" "$ARC" "CLAUDE_PROJECT_DIR=$CP" "$A" --ps "$T/ps"
    probe_in 0 "S2: CLAUDE_PROJECT_DIR — копия со своим журналом, журнал основной копии новее: сессия копии" "сессия sidcopy;" "$ARC" "CLAUDE_PROJECT_DIR=$CP2" "$A" --ps "$T/ps"
    probe_in 0 "S4: каталог проекта копии есть, журнала в нём нет: сессия основной копии, не VOID" "сессия sid;" "$ARC" "CLAUDE_PROJECT_DIR=$CP4" "$A" --ps "$T/ps"
    probe_in 2 "близнец: архив без ключа и без CLAUDE_PROJECT_DIR — журнала действительно нет, VOID с перечнем опрошенных" "опрошено каталогов" "$ARC" - "$A" --ps "$T/ps"
    probe_in 2 "близнец: --session-dir на каталог без журнала — VOID" "журнала сессии проекта нет" "$ARC" - "$A" --session-dir "$T/empty-proj" --ps "$T/ps"
    probe_in 2 "--session-dir без каталога — VOID" "VOID" "$ARC" - "$A" --session-dir
}
locate_cases "$ARC/scripts/stall-census.sh"
probe_in 0 "скрипт в копии под <ws>/tmp/, запуск из временного каталога без ключа: найдена" "сессия sid;" "$ARC" - "$CP/scripts/stall-census.sh" --ps "$T/ps"

echo "== мутанты поиска сессии — каждый обязан покраснеть на пробах выше"
# mutant <имя> <было> <стало> [пробы]: правка ровно одного вхождения в копии прибора;
# пробы — функция, получающая путь копии (по умолчанию locate_cases);
# образец не найден — расхождение (мутант не лёг), а не «выжил молча».
mutant() {
    local MA="$T/mut/scripts" p0="$pass" f0="$fail" mp mf
    rm -rf "$T/mut"; mkdir -p "$MA/lib"; cp "$HERE/lib/ws-home.sh" "$MA/lib/"
    if ! python3 - "$C" "$MA/stall-census.sh" "$2" "$3" <<'MUTPY'
import sys
src, dst, was, now = sys.argv[1:5]
s = open(src).read()
if s.count(was) != 1:
    sys.exit(1)
open(dst, 'w').write(s.replace(was, now))
MUTPY
    then echo "  [FAIL] мутант «$1»: образец не найден в приборе — не лёг" >&2; fail=$((fail + 1)); return; fi
    failed=""; quiet=1
    "${4:-locate_cases}" "$MA/stall-census.sh"
    quiet=""; mp=$((pass - p0)); mf=$((fail - f0)); pass="$p0"; fail="$f0"
    if [ "$mf" -gt 0 ]; then
        echo "  [OK]   мутант «$1» красный: разошлось $mf из $((mp + mf)): ${failed#; }"; pass=$((pass + 1))
    else
        echo "  [FAIL] мутант «$1» выжил: все $mp проб сошлись" >&2; fail=$((fail + 1))
    fi
}
# shellcheck disable=SC2016  # образец — текст прибора, не раскрывается
mutant "CLAUDE_PROJECT_DIR убран из кандидатов" '[ -n "${CLAUDE_PROJECT_DIR:-}" ] && cands+=("$CLAUDE_PROJECT_DIR")' ':'
mutant "побеждает первый существующий каталог" $'        if cands:\n            break' $'        if os.path.isdir(d):\n            break'
echo "== мутант отбора своей сессии (ws#1131) — обязан покраснеть на пробах П1–П9"
mutant "старый отбор: любая оболочка под claude — своя" '    who = whose(pid, ppid)' "    who = 'own'" proc_cases
mutant "неустановленная сессия при своём claude — чужая" $'    return \'\'\n\n\nshells' $'    return \'foreign\' if own_pid else \'\'\n\n\nshells' proc_cases
echo "== мутанты правдоподобия возраста (ws#1149) — обязаны покраснеть на пробах Е1–Е6"
mutant "потолок родителя снят" '    elif parent[1] is not None and et > parent[1]:' '    elif False:' etimes_cases
mutant "потолок аптайма снят" '    elif uptime is not None and et > uptime:' '    elif False:' etimes_cases
mutant "равный родителю — неправдоподобен" 'and et > parent[1]:' 'and et >= parent[1]:' etimes_cases
mutant "равный аптайму — неправдоподобен" 'and et > uptime:' 'and et >= uptime:' etimes_cases
mutant "нечисловой возраст — ноль (до ws#1149)" 'p[2].isdigit() else None, p[3]' 'p[2].isdigit() else 0, p[3]' etimes_cases
mutant "--verbose не печатает" $'\nif verbose:' $'\nif False:' etimes_cases
mutant "поимённо и без --verbose" $'\nif verbose:' $'\nif True:' etimes_cases
echo "== мутанты отсоединённых (ws#1154) — обязаны покраснеть на пробах Д1–Д9"
mutant "выборка только прямых потомков claude" "    if e.get('CLAUDE_CODE_SESSION_ID') or e.get('CLAUDE_PID'):" "    if False:" detached_cases
mutant "живой claude не проверяется" "    alive = owner is not None and owner[2] == 'claude'" "    alive = False and owner[2] == 'claude'" detached_cases
mutant "любой claude — живой владелец" "    alive = owner is not None and owner[2] == 'claude'" "    alive = True or owner[2] == 'claude'" detached_cases
mutant "pid владельца не сверен по возрасту" " and owner[1] is not None and owner[1] >= et" "" detached_cases
mutant "объявленный срок не читается" "    if term.isdigit() and now < int(term):" "    if False:" detached_cases
mutant "срок без сверки со временем" "    if term.isdigit() and now < int(term):" "    if term.isdigit():" detached_cases
mutant "судится каждый меченый, а не корень" "        continue  # не корень: судится корень поддерева" "        pass" detached_cases
mutant "чужая сессия — своя" "        who = 'own' if sid == own_sid else 'foreign'" "        who = 'own'" detached_cases
mutant "непонятная принадлежность молчит" "            unjudged.append('pid %s (отсоединён, claude %s)' % (pid, cpid or '?'))" "            pass" detached_cases
mutant "ноль прочитанного окружения — «чисто»" "env_void = bool(live) and env_read == 0" "env_void = False" detached_cases

echo "== журнал своей сессии без transcript_path (ws#1134)"
# Один каталог проекта, два окна: у каждого свой застрявший агент, сессия N свежее;
# оболочка N 120 мин под claude «--resume N» (id — форма, которую узнаёт SID_ARG).
JS=aaaaaaaa-1111-4111-8111-000000000001 JN=bbbbbbbb-2222-4222-8222-000000000002
SD="$T/proj2"; mkdir -p "$SD/$JS/subagents" "$SD/$JN/subagents"
rec "$SD/$JS/subagents/agent-own.jsonl" 30 tool "make own-e2e"; rec "$SD/$JN/subagents/agent-nb.jsonl" 30 tool "make neighbor-e2e"
rec "$SD/$JS.jsonl" 2 "done"; rec "$SD/$JN.jsonl" 1 "done"
{ echo "100 1 90000 claude claude --x"; echo "110 1 90000 claude claude --resume $JN"
  echo "211 110 7200 bash /bin/bash -c source /h/.claude/shell-snapshots/n.sh && eval 'newman run nb'"; } > "$T/ps-jn"
# journal_cases <прибор> — выбор журнала своей сессии и его следствия; их же гонят мутанты ниже.
journal_cases() {
    local C="$1"
    CLAUDE_CODE_SESSION_ID=$JS probe 1 "инъекция: CLAUDE_CODE_SESSION_ID выбирает свою S, хотя N свежее" "сессия $JS;" --session-dir "$SD" --ps "$T/ps"
    CLAUDE_CODE_SESSION_ID=$JS absent="agent-nb" probe 1 "  …назван свой агент, агента N нет" "STALL-AGENT agent-own" --session-dir "$SD" --ps "$T/ps"
    stdin="{\"session_id\":\"$JS\"}" CLAUDE_CODE_SESSION_ID=$JN probe 1 "инъекция: session_id хука сильнее CLAUDE_CODE_SESSION_ID — журнал S" "сессия $JS;" --session-dir "$SD" --ps "$T/ps-jn"
    stdin="{\"session_id\":\"$JS\"}" CLAUDE_CODE_SESSION_ID=$JN absent="STALL-PROC pid 211" probe 1 "3a: хук S, окружение N — оболочка N чужая, не STALL-PROC (одна своя сессия на журнал и процессы)" "чужих 1" --session-dir "$SD" --ps "$T/ps-jn"
    absent="STALL-PROC pid 211" probe 1 "2b: id нет — оболочка самой свежей сессии N не судима, а не своя" "не судимо 1" --session-dir "$SD" --ps "$T/ps-jn"
    probe 1 "2a: id нет — шапка «своя сессия не определена»" "своя сессия не определена" --session-dir "$SD" --ps "$T/ps-jn"
    probe 1 "близнец: id нет — журнал самой свежей (N), без пометки о запасном" "сессия $JN;" --session-dir "$SD" --ps "$T/ps"
    CLAUDE_CODE_SESSION_ID=gone probe 1 "близнец: журнала своей сессии нет — самая свежая с пометкой, не VOID" "сессия $JN (журнала своей сессии gone нет — взята самая свежая);" --session-dir "$SD" --ps "$T/ps"
}
journal_cases "$C"
mutant "журнал своей сессии не выбирается" '    if own_j in cands:' '    if False:' journal_cases
mutant "окружение сильнее session_id хука" "own_sid = own_sid or os.environ.get('CLAUDE_CODE_SESSION_ID', '')" "own_sid = os.environ.get('CLAUDE_CODE_SESSION_ID', '') or own_sid" journal_cases
mutant "3a: STALL-PROC — второе вычисление своей сессии из окружения" $'# Свой claude (шапка, STALL-PROC); своя сессия own_sid — выше, у каталога сессии.\n' $'own_sid = os.environ.get(\'CLAUDE_CODE_SESSION_ID\', \'\')\n' journal_cases
mutant "2b: id нет — своей становится самая свежая" $'\nmain = session + \'.jsonl\'\n' $'\nown_sid = own_sid or os.path.basename(session)\nmain = session + \'.jsonl\'\n' journal_cases
mutant "2a: id нет — шапка без «не определена»" "own_sid or 'не определена'," "own_sid or os.path.basename(session)," journal_cases
mutant "запасной журнал не помечен" $'        if own_sid:\n            sess_note' $'        if False:\n            sess_note' journal_cases

echo "== разбор: не-объект, нечитаемый журнал, падение (опыт check-verifier по #1002)"
s="$(session nonobj)"; a="$s/subagents/workflows/wf_live-1/agent-a1.jsonl"
rec "$a" 20 tool "make e2e"; echo '[1,2]' >> "$a"; touch -d "@$((NOW - 20 * 60))" "$a"
probe 1 "инъекция: последняя строка агента — JSON не-объект; застой назван, а не traceback" "STALL-AGENT wf_live-1/a1" --session "$s" --ps "$T/ps"
out="$(bash "$C" --session "$s" --ps "$T/ps" 2>&1)"
if ! grep -q Traceback <<< "$out"; then echo "  [OK]   …и без Python traceback"; pass=$((pass + 1)); else echo "  [FAIL] не-объект в журнале агента роняет разбор: $(tail -1 <<< "$out")" >&2; fail=$((fail + 1)); fi
s="$(session nonobj-wf)"; rec "$s/subagents/workflows/wf_live-1/agent-a1.jsonl" 20 tool "make e2e"
echo '42' > "$s/subagents/workflows/wf_live-1/journal.jsonl"
probe 1 "инъекция: строка «42» в journal.jsonl workflow — застой назван, разбор цел" "STALL-AGENT wf_live-1/a1" --session "$s" --ps "$T/ps"
echo '[1]' > "$s/workflows/wf_live-2.json"
probe 1 "инъекция: состояние workflow — JSON не-объект — разбор цел" "STALL-AGENT wf_live-1/a1" --session "$s" --ps "$T/ps"
s="$(session garbage)"; a="$s/subagents/workflows/wf_live-1/agent-a1.jsonl"
head -c 4096 /dev/urandom | tr -d '\n{[' > "$a"; touch -d "@$((NOW - 20 * 60))" "$a"
probe 2 "инъекция: журнал агента 20 мин без единой разобранной записи — код 2, а не «чисто»" "UNREAD wf_live-1/a1" --session "$s" --ps "$T/ps"
probe 2 "  …перепись называет непрочитанное" "без единой разобранной записи 1" --session "$s" --ps "$T/ps"
touch -d "@$((NOW - 5 * 60))" "$a"
probe 0 "близнец: тот же журнал 5 мин (моложе порога агента) — не судится" "без единой разобранной записи 0" --session "$s" --ps "$T/ps"
s="$(session bigline)"; a="$s/subagents/workflows/wf_live-1/agent-a1.jsonl"
rec "$a" 30 tool "make e2e"
python3 -c 'import json,sys; print(json.dumps({"type":"user","timestamp":sys.argv[1],"message":{"role":"user","content":[{"type":"tool_result","content":"x"*200000}]}}))' "$(iso 30)" >> "$a"
touch -d "@$((NOW - 30 * 60))" "$a"
probe 1 "близнец: последняя запись длиннее хвоста 64 КиБ — прочитана, STALL-AGENT, а не UNREAD" "STALL-AGENT wf_live-1/a1" --session "$s" --ps "$T/ps"
s="$(session crash)"; rec "$s/subagents/workflows/wf_live-1/agent-a1.jsonl" 30 tool
out="$(STALL_AGENT_MIN=x bash "$C" --session "$s" --ps "$T/ps" 2>&1)"; got=$?
if [ "$got" -eq 2 ] && grep -qF "разбор упал" <<< "$out" && ! grep -q Traceback <<< "$out"; then echo "  [OK]   инъекция: падение разбора — код 2 «разбор упал», а не код 1 застоя"; pass=$((pass + 1)); else echo "  [FAIL] падение разбора — код $got: $(tail -2 <<< "$out")" >&2; fail=$((fail + 1)); fi

s="$(session hook)"; rec "$s/subagents/workflows/wf_live-1/agent-a1.jsonl" 30 tool
out="$(printf '{"transcript_path":"%s.jsonl"}' "$s" | bash "$C" --ps "$T/ps" 2>&1)"; got=$?
if [ "$got" -eq 1 ] && grep -qF "сессия hook" <<< "$out"; then echo "  [OK]   сессия из transcript_path хука (код 1)"; pass=$((pass + 1)); else echo "  [FAIL] сессия из transcript_path хука — код $got: $out" >&2; fail=$((fail + 1)); fi

echo "== хук stall-signal.sh (Stop / UserPromptSubmit главного потока)"
HOOK="$HERE/../.claude/hooks/stall-signal.sh"
# hook <код> <имя> <строка|-> <поток out|err> <сессия> <событие> [stop_hook_active]
hook() {
    local want="$1" name="$2" needle="$3" stream="$4" sess="$5" ev="$6" act="${7:-false}" got o e
    o="$(printf '{"hook_event_name":"%s","stop_hook_active":%s,"transcript_path":"%s.jsonl"}' "$ev" "$act" "$sess" \
        | CLAUDE_PROJECT_DIR="$HERE/.." STALL_CENSUS_EXTRA="--ps $T/ps" bash "$HOOK" 2> "$T/hook.err")"; got=$?
    e="$(cat "$T/hook.err")"
    local hay="$o"; [ "$stream" = err ] && hay="$e"
    if [ "$got" -eq "$want" ] && { { [ "$needle" = - ] && [ -z "$o$e" ]; } || { [ "$needle" != - ] && grep -qF -- "$needle" <<< "$hay"; }; }; then
        echo "  [OK]   $name (код $got)"; pass=$((pass + 1))
    else
        echo "  [FAIL] $name — ждали код $want и «$needle» в $stream, получили $got: out=$(head -c 300 <<< "$o") err=$(head -c 300 <<< "$e")" >&2; fail=$((fail + 1))
    fi
}
s="$(session hstall)"; rec "$s/subagents/workflows/wf_live-1/agent-a1.jsonl" 30 tool "make e2e"
hook 2 "Stop при застое — ход не кончается, перечень диспетчеру" "⏱ ЗАСТОЙ" err "$s" Stop
hook 0 "Stop повторно в том же ходе — не держит (петли нет)" - out "$s" Stop true
hook 0 "UserPromptSubmit при застое — строка в контекст" "STALL-AGENT wf_live-1/a1" out "$s" UserPromptSubmit
s="$(session hclean)"; rec "$s/subagents/workflows/wf_live-1/agent-a1.jsonl" 2 tool
hook 0 "близнец: застоя нет — Stop молчит" - out "$s" Stop
hook 0 "близнец: застоя нет — UserPromptSubmit молчит" - out "$s" UserPromptSubmit
hook 0 "сессии нет — UserPromptSubmit говорит «не проверен», а не молчит" "ЗАСТОЙ НЕ ПРОВЕРЕН" out "$T/nope" UserPromptSubmit
hook 0 "сессии нет — Stop не держит ход" - out "$T/nope" Stop
s="$(session hnonobj)"; a="$s/subagents/workflows/wf_live-1/agent-a1.jsonl"
rec "$a" 20 tool "make e2e"; echo '[1,2]' >> "$a"; touch -d "@$((NOW - 20 * 60))" "$a"
hook 2 "не-объект в журнале — Stop держит ход и НАЗЫВАЕТ агента" "STALL-AGENT wf_live-1/a1" err "$s" Stop
s="$(session hgarbage)"; a="$s/subagents/workflows/wf_live-1/agent-a1.jsonl"
head -c 4096 /dev/urandom | tr -d '\n{[' > "$a"; touch -d "@$((NOW - 20 * 60))" "$a"
hook 0 "нечитаемый журнал агента — UserPromptSubmit «не проверен»" "ЗАСТОЙ НЕ ПРОВЕРЕН (код 2)" out "$s" UserPromptSubmit
hook 0 "нечитаемый журнал агента — Stop не держит ход" - out "$s" Stop
# Прибор, упавший кодом 1 без единой строки застоя (подложенный проект).
F="$T/fakews"; mkdir -p "$F/scripts"
printf '#!/usr/bin/env bash\necho "Traceback (most recent call last):" >&2\necho "AttributeError: x" >&2\nexit 1\n' > "$F/scripts/stall-census.sh"
fhook() {
    local want="$1" name="$2" needle="$3" stream="$4" ev="$5" got o e
    o="$(printf '{"hook_event_name":"%s","stop_hook_active":false}' "$ev" | CLAUDE_PROJECT_DIR="$F" bash "$HOOK" 2> "$T/hook.err")"; got=$?
    e="$(cat "$T/hook.err")"
    local hay="$o"; [ "$stream" = err ] && hay="$e"
    if [ "$got" -eq "$want" ] && { { [ "$needle" = - ] && [ -z "$o$e" ]; } || { [ "$needle" != - ] && grep -qF -- "$needle" <<< "$hay" && ! grep -qF "TaskStop" <<< "$o$e"; }; }; then
        echo "  [OK]   $name (код $got)"; pass=$((pass + 1))
    else
        echo "  [FAIL] $name — ждали код $want и «$needle» в $stream, получили $got: out=$(head -c 300 <<< "$o") err=$(head -c 300 <<< "$e")" >&2; fail=$((fail + 1))
    fi
}
fhook 0 "инъекция: прибор упал кодом 1 без строк застоя — Stop НЕ держит ход" - out Stop
fhook 0 "инъекция: прибор упал кодом 1 без строк застоя — UserPromptSubmit «не проверен», не «ЗАСТОЙ … TaskStop»" "ЗАСТОЙ НЕ ПРОВЕРЕН (код 3)" out UserPromptSubmit
# Своя сессия — из session_id JSON хука (ws#1131); окружение пробы его не даёт.
hookp() {
    local want="$1" name="$2" needle="$3" ps="$4" got o e
    o="$(printf '{"hook_event_name":"Stop","stop_hook_active":false,"session_id":"%s","transcript_path":"%s.jsonl"}' "$OWN" "$s" \
        | CLAUDE_PROJECT_DIR="$HERE/.." STALL_CENSUS_EXTRA="--ps $ps" bash "$HOOK" 2> "$T/hook.err")"; got=$?
    e="$(cat "$T/hook.err")"
    if [ "$got" -eq "$want" ] && { { [ "$needle" = - ] && [ -z "$o$e" ]; } || { [ "$needle" != - ] && grep -qF -- "$needle" <<< "$e"; }; }; then
        echo "  [OK]   $name (код $got)"; pass=$((pass + 1))
    else
        echo "  [FAIL] $name — ждали код $want и «$needle», получили $got: out=$(head -c 300 <<< "$o") err=$(head -c 300 <<< "$e")" >&2; fail=$((fail + 1))
    fi
}
s="$(session hproc)"
{ echo "100 1 90000 claude claude --resume $OWN"; echo "110 1 90000 claude claude --resume $FOR"
  echo "211 110 7200 bash $SNAP 'newman run x'"; } > "$T/ps-hfor"
hookp 0 "Х1 Stop: чужая сессия с оболочкой 120 мин — ход не держит" - "$T/ps-hfor"
hookp 2 "Х2 Stop: своя (session_id хука) оболочка 120 мин — держит и называет" "STALL-PROC pid 201" "$T/ps-both"
{ echo "100 1 90000 claude claude --resume $OWN"; echo "201 100 4123168608 bash $SNAP 'make e2e'"; } > "$T/ps-hwrap"
hookp 0 "Х3 Stop: своя оболочка с etimes 4123168608 (ws#1149) — ход не держит, «68719476 мин» нет" - "$T/ps-hwrap"
w="$HERE/../.claude/settings.json"
if python3 - "$w" <<'PY'
import json, sys
h = json.load(open(sys.argv[1]))['hooks']
ok = all(any('stall-signal.sh' in x.get('command', '') for g in h.get(ev, []) for x in g.get('hooks', [])) for ev in ('Stop', 'UserPromptSubmit'))
sys.exit(0 if ok else 1)
PY
then echo "  [OK]   хук провязан в Stop и UserPromptSubmit settings.json"; pass=$((pass + 1))
else echo "  [FAIL] хук не провязан в Stop и UserPromptSubmit settings.json" >&2; fail=$((fail + 1)); fi

echo
echo "stall-census-inject: проб $((pass + fail)), сошлось $pass, разошлось $fail"
[ "$fail" -eq 0 ]
