#!/usr/bin/env bash
# Признак дельты для хуков на bash. Только для `source`.
#
# Механизма здесь НЕТ — он один, в `signal.py`, и эта оболочка его ЗОВЁТ. Второй
# реализации того же признака в дереве не заводится: две копии решения расходятся,
# и расходятся молча (`ai-tooling.md` §«Оснастка: экземпляр»).
#
# `signal_stdin` вызывается ПЕРВОЙ строкой хука: событие `UserPromptSubmit` подаёт
# JSON на stdin, и `session_id` из него — ключ, по которому «уже сказано» относится
# к ЭТОЙ сессии, а не к прошлой. Читать stdin позже нельзя: его успевает забрать
# что-то ещё.
#
# Фолбэк без python3 — ПОЛНАЯ печать, а не молчание: сигнал, замолчавший из-за
# отсутствия интерпретатора, неотличим от «находок нет».

signal_stdin() {
    SIGNAL_PAYLOAD=""
    [ -t 0 ] && return 0          # человек запустил руками — ждать stdin нечего
    SIGNAL_PAYLOAD="$(cat 2>/dev/null || true)"
    SIGNAL_SESSION="$(printf '%s' "$SIGNAL_PAYLOAD" |
        sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    export SIGNAL_SESSION
}

# signal_emit <id> <агент-адресат> <машинный предикат снятия> <ревизия> ; тело на stdin
signal_emit() {
    local id="$1" addressee="$2" clear_when="$3" sha="${4:-}" lib py
    lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/signal.py"
    py="$(command -v python3 || true)"
    if [ -z "$py" ] || [ ! -f "$lib" ]; then
        cat
        echo "[сигнал \`$id\`] признак дельты НЕ применён: нет $( [ -z "$py" ] && echo python3 || echo "$lib" )."
        echo "   Печатается полностью КАЖДЫЙ ход, пока это так. → tooling-maintainer."
        echo "   Предикат снятия предмета: $clear_when · адресат: $addressee"
        return 0
    fi
    "$py" "$lib" --id "$id" --addressee "$addressee" --clear-when "$clear_when" \
        --session "${SIGNAL_SESSION:-}" --sha "$sha"
}

# Короткая ревизия воркспейса — её называет строка повтора, чтобы «без изменений»
# было привязано к состоянию дерева, а не только ко времени.
signal_sha() {
    git -C "${1:-.}" rev-parse --short HEAD 2>/dev/null || echo "ревизия не читается"
}
