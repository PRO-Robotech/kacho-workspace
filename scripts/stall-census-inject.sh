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

# rec <файл> <минут назад> <вид: tool|done|result> [команда]
rec() {
    local f="$1" m="$2" kind="$3" cmd="${4:-go test ./...}" t
    t="$(iso "$m")"
    case "$kind" in
        tool) printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"%s"}}]}}\n' "$t" "$cmd" >> "$f" ;;
        done) printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"text","text":"готово"}]}}\n' "$t" >> "$f" ;;
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
        echo "  [OK]   $name (код $got)"; pass=$((pass + 1))
    else
        echo "  [FAIL] $name — ждали код $want${needle:+ и «$needle»}, получили $got: $(head -c 400 <<< "$out")" >&2; fail=$((fail + 1))
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
