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
# Коды: 0 — все пробы сошлись; 1 — нет; 2 — нет python3: вердикта нет.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C="$HERE/stall-census.sh"
command -v python3 > /dev/null 2>&1 || { echo "stall-census-inject: VOID — нет python3" >&2; exit 2; }
[ -r "$C" ] || { echo "stall-census-inject: VOID — прибора нет: $C" >&2; exit 2; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
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
# probe <код> <имя> <строка|-> <довод…>
probe() {
    local want="$1" name="$2" needle="$3" got out
    shift 3
    out="$(bash "$C" "$@" < /dev/null 2>&1)"; got=$?
    if [ "$got" -eq "$want" ] && { [ "$needle" = - ] || grep -qF -- "$needle" <<< "$out"; }; then
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
# fmutant <имя> <было> <стало>: копия прибора с одной правкой; пробы
# finish_cases обязаны разойтись хоть в одной.
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
    finish_cases
    C="$C0"; quiet=""; mp=$((pass - p0)); mf=$((fail - f0)); pass="$p0"; fail="$f0"
    if [ "$mf" -gt 0 ]; then
        echo "  [OK]   мутант «$1» красный: разошлось $mf из $((mp + mf)): ${failed#; }"; pass=$((pass + 1))
    else
        echo "  [FAIL] мутант «$1» выжил: все $mp проб сошлись" >&2; fail=$((fail + 1))
    fi
}
fmutant "не проверять завершение" "FINAL_STOP = ('end_turn', 'stop_sequence', 'refusal')" "FINAL_STOP = ()"
fmutant "завершение — любой ответ без вызова" "('final' if fin else 'done')" "'final'"
fmutant "итог без stop_reason не узнаётся (до ws#1130)" " or (sr is None and now - os.path.getmtime(path) >= AGENT_MIN * 60)" ""
fmutant "тишина журнала не различается" "sr is None and now - os.path.getmtime(path) >= AGENT_MIN * 60" "sr is None"
fmutant "tool_use — завершение" "FINAL_STOP = ('end_turn', 'stop_sequence', 'refusal')" "FINAL_STOP = ('end_turn', 'stop_sequence', 'refusal', 'tool_use')"
fmutant "завершение — любой непустой stop_reason" "sr in FINAL_STOP or" "sr or"
fmutant "завершённый в workflow не пропускается" $'                if age_file < DONE_MIN * 60:\n                    agents_seen += 1\n                continue' $'                if age_file < DONE_MIN * 60:\n                    agents_seen += 1'
fmutant "давность не различается" $'\n            if age_file < DONE_MIN * 60:\n                agents_seen += 1\n            continue' $'\n            agents_seen += 1\n            continue'

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
probe 1 "инъекция: оболочка агента живёт 120 мин — STALL-PROC с командой" "STALL-PROC pid 201" --session "$s" --ps "$T/ps-old"
{ ps_ok; echo "201 100 1800 bash /bin/bash -c source /h/.claude/shell-snapshots/s.sh && eval 'make e2e'"; } > "$T/ps-young"
probe 0 "близнец: та же оболочка 30 мин — молчит" - --session "$s" --ps "$T/ps-young"
{ ps_ok; echo "202 1 7200 bash /bin/bash -c source /h/.claude/shell-snapshots/s.sh && eval 'x'"; } > "$T/ps-orphan"
probe 0 "близнец: оболочка 120 мин, но родитель не claude — не судится" - --session "$s" --ps "$T/ps-orphan"

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
# mutant <имя> <было> <стало>: правка ровно одного вхождения в копии прибора;
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
    locate_cases "$MA/stall-census.sh"
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
