#!/usr/bin/env bash
# Общие помощники набора adapter-gate. Только для подключения, не исполняется.
#
# Предмет набора: производное оснастки для других агентских сред. Оно
# отслеживаемое, а значит может разойтись со своим источником молча — правкой
# производного, правкой входа без регенерации либо недетерминизмом генератора.
# Каждое из трёх состояний выглядит как исправное дерево.

adapter_gate_pass() { echo "[PASS] $1${2:+ — $2}"; }
adapter_gate_fail() { echo "[FAIL] $1${2:+ — $2}" >&2; }
adapter_gate_void() { echo "[VOID] $1${2:+ — $2}" >&2; }   # «сверять не с чем» ≠ «находок 0»

# Прогоняет один предикат и переводит его исход в вердикт проверки.
#
# Вердикт берётся из КОДА ВОЗВРАТА предиката, а не из вида его печати: та же
# строка «CENSUS …» выходит и на чистом дереве, и рядом с находками, поэтому
# чтение вывода глазами дало бы зелёное на красном.
adapter_gate_run() {
    local name="$1" predicate="$2" title="$3"
    local dir out rc
    dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    out="$(python3 "$dir/probe.py" "$predicate" 2>&1)"; rc=$?

    local census
    census="$(printf '%s\n' "$out" | sed -n 's/^CENSUS //p')"
    printf '%s\n' "$out" | grep -v '^CENSUS ' | grep -v '^VOID ' || true

    case "$rc" in
        0) adapter_gate_pass "$name" "$title; осмотрено ${census:-0}, находок 0"; return 0 ;;
        2) adapter_gate_void "$name" "$(printf '%s\n' "$out" | sed -n 's/^VOID //p')"; return 2 ;;
        *) adapter_gate_fail "$name" "$title; осмотрено ${census:-0} — есть находки"; return 1 ;;
    esac
}
