#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# ДОКАЗАТЕЛЬСТВО ИНЪЕКЦИЕЙ для `.claude/hooks/hooks-wiring-notice.sh`.
#
# Хук молчит, когда всё провязано. Молчание — законный исход и одновременно самый
# опасный: оно неотличимо от «хук не исполнялся», «клонов не нашлось», «признак
# разошёлся с деревом». Поэтому способность говорить доказывается ЗДЕСЬ, на
# синтетическом дереве, и проверяется в ОБЕ стороны:
#
#   1. непровязанный клон  → хук ГОВОРИТ и НАЗЫВАЕТ координату;
#   2. провязанный клон    → хук МОЛЧИТ (законный близнец той же формы);
#   3. клон без механизма  → хук МОЛЧИТ (нет предмета — нет вопроса);
#   4. ни одного клона     → хук ГОВОРИТ «осмотрено 0» (перепись, а не тишина);
#   5. смешанный случай    → назван ИМЕННО непровязанный, а не оба.
#
# Без пункта 2 проверка ловила бы форму, а не существо: хук, кричащий всегда,
# прошёл бы пункт 1 и был бы снят первым же читателем как шумный.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks-wiring-notice.sh"
[ -f "$HOOK" ] || { echo "[FAIL] нет самого хука: $HOOK" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0
ran=0

# Синтетический клон. `wired=1` — провязанный: его `install.sh check` выходит нулём.
#
# `.git` создаётся ВСЕГДА — вложенный клон опознаётся именно по нему, и фикстура
# без него не является клоном. Первая редакция этого доказательства так и упала:
# случай «воркспейс без механизма, вложенный продукт провязан» дал «осмотрено 0»,
# потому что вложенный каталог клоном не выглядел. Фикстура обязана быть НЕ
# снисходительнее продукта — здесь она была строже и обвиняла исправный хук.
make_clone() { # make_clone <путь> <wired 0|1>
    local dir="$1" wired="$2"
    mkdir -p "$dir/scripts/hooks" "$dir/.git"
    cat > "$dir/scripts/hooks/install.sh" <<EOF
#!/usr/bin/env bash
exit $(( wired == 1 ? 0 : 1 ))
EOF
    chmod +x "$dir/scripts/hooks/install.sh"
}

# Клон, у которого механизма нет вовсе.
make_bare_clone() { mkdir -p "$1"; }

run_case() { # run_case <имя> <корень> <ожидание: talks|silent> [<подстрока>]
    local name="$1" root="$2" expect="$3" needle="${4:-}"
    ran=$((ran + 1))
    local err
    err="$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" 2>&1 >/dev/null)"
    case "$expect" in
    talks)
        if [ -z "$err" ]; then
            echo "[FAIL] $name — хук ПРОМОЛЧАЛ там, где обязан был сказать" >&2
            fails=$((fails + 1)); return
        fi
        if [ -n "$needle" ] && ! printf '%s' "$err" | grep -qF "$needle"; then
            echo "[FAIL] $name — сказал, но не назвал «$needle»:" >&2
            printf '%s\n' "$err" | sed 's/^/       /' >&2
            fails=$((fails + 1)); return
        fi
        ;;
    silent)
        if [ -n "$err" ]; then
            echo "[FAIL] $name — хук ЗАГОВОРИЛ там, где обязан был молчать:" >&2
            printf '%s\n' "$err" | sed 's/^/       /' >&2
            fails=$((fails + 1)); return
        fi
        ;;
    esac
    echo "   ok: $name"
}

# ── 1. непровязанный воркспейс → говорит и называет его путь ────────────────
W1="$TMP/unwired"; make_clone "$W1" 0
run_case "непровязанный клон → отказ назван" "$W1" talks "$W1"

# ── 2. провязанный воркспейс → молчит (ЗАКОННЫЙ БЛИЗНЕЦ) ────────────────────
W2="$TMP/wired"; make_clone "$W2" 1
run_case "провязанный клон → тишина" "$W2" silent

# ── 3. клон без механизма → молчит (нет предмета) ───────────────────────────
W3="$TMP/bare"; make_bare_clone "$W3"; make_clone "$W3/project/kacho" 1
run_case "воркспейс без своего install.sh → тишина" "$W3" silent

# ── 4. ни одного клона с механизмом → перепись, а не тишина ─────────────────
W4="$TMP/empty"; make_bare_clone "$W4"
run_case "ноль осмотренных → сказано вслух" "$W4" talks "осмотрено клонов 0"

# ── 5. смешанный: воркспейс провязан, вложенный продукт — нет ───────────────
W5="$TMP/mixed"; make_clone "$W5" 1; make_clone "$W5/project/kacho" 0

run_case "вложенный продукт непровязан → назван именно он" "$W5" talks "$W5/project/kacho"
# и при этом сам воркспейс виновным НЕ назван
if CLAUDE_PROJECT_DIR="$W5" bash "$HOOK" 2>&1 >/dev/null | grep -qE "^  • $W5\$"; then
    echo "[FAIL] смешанный случай — провязанный воркспейс назван виновным" >&2
    fails=$((fails + 1))
else
    echo "   ok: провязанный воркспейс в перечне отсутствует"
fi
ran=$((ran + 1))

echo "[CENSUS] hooks-wiring-notice: проб исполнено $ran, разошлось $fails"
[ "$fails" -eq 0 ] || { echo "[FAIL] hooks-wiring-notice — доказательство разошлось" >&2; exit 1; }
echo "[PASS] hooks-wiring-notice — говорит на дефекте, молчит на законном близнеце"
