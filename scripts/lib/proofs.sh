#!/usr/bin/env bash
# Части доказательства набора. Только для подключения из `scripts/<набор>/inject.sh`.
#
# ЗАЧЕМ. Вход доказательства набора — ОДИН: `inject.sh` (так его зовёт конвейер —
# `scripts/lib/run-suites.sh --proofs`, и так считает перепись
# `scripts/lib/suites.py`). Части (`inject-<N>*.sh` рядом) вход обязан исполнить
# сам: часть, которую не зовёт никто, отличается от отсутствующей только тем, что
# создаёт уверенность. Прежде один набор делал это своим циклом, другой полагался
# на то, что части выпишет конвейер поимённо, — два устройства одного правила.
#
# Перечень частей ВЫВОДИТСЯ из каталога. Ноль найденных — отказ: пустой обход здесь
# означал бы «доказано всё» ровно тогда, когда не доказано ничего.
#
# proof_parts <каталог набора>
#   исполняет каждую часть; выставляет PROOF_PARTS (сколько исполнено) и
#   PROOF_PARTS_BAD (сколько не сошлось; «не выполнилось» тоже не сошлось).
#   Возврат: 0 — все сошлись; 1 — есть несошедшаяся; 2 — частей нет.
# shellcheck disable=SC2034  # PROOF_PARTS* читает подключивший файл
proof_parts() {
    local dir="$1" p
    local -a parts=()
    PROOF_PARTS=0
    PROOF_PARTS_BAD=0
    while IFS= read -r p; do
        parts+=("$p")
    done < <(find "$dir" -maxdepth 1 -name 'inject-[0-9]*.sh' -type f | sort)
    if [ "${#parts[@]}" -eq 0 ]; then
        echo "inject: ОТКАЗ — рядом нет НИ ОДНОЙ части inject-<N>*.sh; доказывать нечем" >&2
        return 2
    fi
    for p in "${parts[@]}"; do
        echo
        echo "── $(basename "$p")"
        PROOF_PARTS=$((PROOF_PARTS + 1))
        if ! bash "$p"; then
            PROOF_PARTS_BAD=$((PROOF_PARTS_BAD + 1))
        fi
    done
    [ "$PROOF_PARTS_BAD" -eq 0 ]
}
