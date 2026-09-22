#!/usr/bin/env bash
# ЧАСТЬ инъекции набора: доказательство check-14 «у каждого потолка есть
# основание, и запас остался» — в обе стороны, на СИНТЕТИКЕ.
#
#   A     потолок подняли, ведомость не тронули                 -> 1
#   A'    подняли И ведомость, запас остался                    -> 0
#   B     запас МЕНЬШЕ медианного абзаца                        -> 1
#   B'    запас РОВНО в медианный абзац                         -> 0
#   C     строка ведомости без предмета                         -> 1
#   D     строка ведомости, которой нечего обосновывать         -> 1
#   VOID1 в check-02 нет BUDGET                                 -> 2
#   VOID2 ведомости нет                                         -> 2
#
# Файл ПОДКЛЮЧАЕТСЯ (`.`) из `inject.sh` и пользуется его оснасткой. До
# 2026-09-22 эти оси жили отдельной самостоятельной пробой, которую не звал
# никто: сверка переписи `inject.sh` называла её (тогда check-10) «ПРОВЕРКА НЕ ДОКАЗАНА»,
# и набор отдавал код 1.
#
# Мир — свой, а не `sandbox`: check-14 берёт ведомость и check-02 из СВОЕГО
# каталога (`SELF_DIR`), поэтому в мир кладётся копия проверки, и судится она.

# ── СТРАЖ ПОДКЛЮЧЕНИЯ ────────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — ЧАСТЬ инъекции, а не самостоятельная проба." >&2
    echo "       Запускать: bash scripts/rules-gate/inject.sh" >&2
    exit 2
fi
for _i14_fn in assert_code assert_says; do
    command -v "$_i14_fn" >/dev/null 2>&1 && continue
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — оснастки inject.sh нет: функция" \
         "«$_i14_fn» не определена; часть подключена не оттуда" >&2
    exit 2
done
unset -v _i14_fn

C14=check-14-ceiling-raise-carries-its-basis.sh

# i14_world <потолок> <строка ведомости или пусто> [--no-budget|--no-ledger]
# Цель — 10 абзацев по 100 Б: тело и медиана МЕРЯЮТСЯ ниже, а не выписываются.
i14_world() {
    local dir; dir="$(mktemp -d "$TMP/i14.XXXXXX")"
    mkdir -p "$dir/scripts/rules-gate"
    cp "$GATE/$C14" "$dir/scripts/rules-gate/"
    python3 -c "
import sys
open(sys.argv[1], 'w', encoding='utf-8').write('\n\n'.join('а' * 50 for _ in range(10)))" "$dir/CLAUDE.md"
    if [ "${3:-}" != "--no-budget" ]; then
        printf 'CLAUDE_REL = "CLAUDE.md"\nBUDGET = {CLAUDE_REL: %s}\n' "$1" \
            > "$dir/scripts/rules-gate/check-02-nothing-lost.sh"
    else
        printf 'CLAUDE_REL = "CLAUDE.md"\n' > "$dir/scripts/rules-gate/check-02-nothing-lost.sh"
    fi
    if [ "${3:-}" != "--no-ledger" ]; then
        { echo "# проба"; [ -n "$2" ] && echo "$2"; } > "$dir/scripts/rules-gate/ceiling-basis.txt"
    fi
    echo "$dir"
}

# shellcheck disable=SC2034  # LAST_CHECK, OUT, RC — общие переменные inject.sh, их читают assert_*
i14_capture() {   # <мир> — та же запись исхода, что у `capture`, над копией в мире
    LAST_CHECK="$C14"
    OUT="$( cd "$1" && env KACHO_WS="$1" bash "$1/scripts/rules-gate/$C14" 2>&1 )"
    RC=$?
}

d="$(i14_world 99999 "")"
I14_BODY=$(wc -c < "$d/CLAUDE.md")
I14_MED=$(python3 -c "
import sys
d = open(sys.argv[1], 'rb').read()
p = sorted(len(x) for x in d.split(b'\n\n') if x.strip())
print(p[len(p) // 2])" "$d/CLAUDE.md")
echo "  мир: тело $I14_BODY Б, медианный абзац $I14_MED Б"
i14_row() { echo "CLAUDE.md | $1 | 2026-09-21 | подъём | ${2-предмет назван} | без него невозможно"; }

d="$(i14_world $((I14_BODY + 300)) "$(i14_row $((I14_BODY + 150)))")"
i14_capture "$d"
assert_code 1 "ДЕФЕКТ: потолок подняли, ведомость не тронули — краснеет"
assert_says "ОСНОВАНИЕ ПЕРЕЖИЛО СВОЙ ПОДЪЁМ" "  ...и названа причина, а не симптом"

d="$(i14_world $((I14_BODY + 300)) "$(i14_row $((I14_BODY + 300)))")"
i14_capture "$d"
assert_code 0 "БЛИЗНЕЦ: подняли И ведомость, запас остался — молчит"

d="$(i14_world $((I14_BODY + I14_MED - 1)) "$(i14_row $((I14_BODY + I14_MED - 1)))")"
i14_capture "$d"
assert_code 1 "ДЕФЕКТ: запас на байт МЕНЬШЕ медианного абзаца — краснеет"
assert_says "ЗАПАСА НЕ ОСТАЛОСЬ" "  ...и названа причина"

d="$(i14_world $((I14_BODY + I14_MED)) "$(i14_row $((I14_BODY + I14_MED)))")"
i14_capture "$d"
assert_code 0 "БЛИЗНЕЦ: запас РОВНО в медианный абзац — молчит"

d="$(i14_world $((I14_BODY + 300)) "$(i14_row $((I14_BODY + 300)) "")")"
i14_capture "$d"
assert_code 1 "ДЕФЕКТ: подъём без названного предмета — краснеет"
assert_says "ПОДЪЁМ БЕЗ ПРЕДМЕТА" "  ...и названа причина"

d="$(i14_world $((I14_BODY + 300)) "$(i14_row $((I14_BODY + 300)))
.claude/agents/dispatcher.md | 96000 | 2026-09-18 | установка | предмет | без него")"
i14_capture "$d"
assert_code 1 "ДЕФЕКТ: основание, которому нечего обосновывать — краснеет"
assert_says "ОСНОВАНИЕ БЕЗ ПОТОЛКА" "  ...и названа причина"

d="$(i14_world $((I14_BODY + 300)) "" --no-budget)"
i14_capture "$d"
assert_code 2 "ПРЕДМЕТА НЕТ: в check-02 нет BUDGET — код 2, не зелёное"

d="$(i14_world $((I14_BODY + 300)) "" --no-ledger)"
i14_capture "$d"
assert_code 2 "ПРЕДМЕТА НЕТ: ведомости нет — код 2, не зелёное"

unset -f i14_world i14_capture i14_row
unset -v C14 I14_BODY I14_MED
