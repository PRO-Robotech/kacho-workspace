#!/usr/bin/env bash
# ЧАСТЬ инъекции набора: доказательство check-12 «алгоритм подписи, названный
# корпусом, — тот, которым подписывают профили посадки». Дерево продукта —
# СИНТЕТИЧЕСКОЕ (крохотный репозиторий со стволом `origin/main`), чтобы каждая
# ось меняла ровно один факт: либо строку корпуса, либо алгоритм профиля. Живой
# клон продукта здесь не годится: проба доказывала бы свойство до дня, когда
# посадка сменит алгоритм, и молча перестала бы что-либо утверждать.
#
# Оси: корпус называет алгоритм, которого профили не объявляют (дефект корпуса);
# профиль сменил алгоритм, корпус остался прежним (дефект — корпус отстал от
# посадки); законные близнецы — алгоритм в красной колонке, «forged HS256»,
# строка без якоря подписи, утверждение с алгоритмом профиля; отказы — профиль не
# объявляет алгоритм, дерева продукта нет.
#
# Файл ПОДКЛЮЧАЕТСЯ (`.`) из `inject.sh` и пользуется его оснасткой.

# ── СТРАЖ ПОДКЛЮЧЕНИЯ ────────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — ЧАСТЬ инъекции, а не самостоятельная проба." >&2
    echo "       Она подключается из scripts/rules-gate/inject.sh и пользуется его оснасткой;" >&2
    echo "       самостоятельно писала бы в рабочее дерево. Запускать:" >&2
    echo "       bash scripts/rules-gate/inject.sh" >&2
    exit 2
fi
for _i12_fn in sandbox capture assert_code assert_says assert_fixture_changed sandbox_digest; do
    command -v "$_i12_fn" >/dev/null 2>&1 && continue
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — оснастки inject.sh нет: функция" \
         "«$_i12_fn» не определена; часть подключена не оттуда" >&2
    exit 2
done
unset -v _i12_fn

# shellcheck source-path=SCRIPTDIR source=../lib/sandbox-git-home.sh
. "$WS/scripts/lib/sandbox-git-home.sh"
sandbox_git_home "$TMP/i12-home" || {
    echo "[VOID] inject-12 — подпись песочницы не заведена: синтетический продукт не закоммитить" >&2
    exit 2
}

C12=check-12-signing-algorithm-matches-deploy.sh
S12=".claude/rules/security.md"

# i12_product <имя> <алгоритм|-> — синтетический продукт: один профиль посадки,
# ствол `origin/main`. «-» — профиль без `tokenSigning.algorithm`.
i12_product() {
    local p="$TMP/p.$1" alg="$2"
    rm -rf "$p"; mkdir -p "$p/deploy/helm/umbrella"
    if [ "$alg" = "-" ]; then
        printf 'kaname:\n  config:\n    authn:\n      tokenSigning:\n        enabled: true\n' \
            > "$p/deploy/helm/umbrella/values.prod.yaml"
    else
        printf 'kaname:\n  config:\n    authn:\n      tokenSigning:\n        enabled: true\n        algorithm: %s\n' \
            "$alg" > "$p/deploy/helm/umbrella/values.prod.yaml"
    fi
    sandbox_git -C "$p" init -q >/dev/null 2>&1
    sandbox_git -C "$p" add -A >/dev/null 2>&1
    sandbox_git -C "$p" commit -qm "профиль посадки" >/dev/null 2>&1
    sandbox_git -C "$p" update-ref refs/remotes/origin/main HEAD >/dev/null 2>&1
    echo "$p"
}

P_ES="$(i12_product es ES256)"
P_RS="$(i12_product rs RS256)"
P_NONE="$(i12_product none -)"

# ── КОНТРОЛЬ ЧАСТИ: нетронутый корпус против профиля ES256 молчит ────────────
d="$(sandbox i12_clean)"
capture "$d" "$C12" KACHO_MONOREPO="$P_ES"
assert_code 0 "БЛИЗНЕЦ: нетронутый корпус, профиль подписывает ES256 — молчит"

# ── ДЕФЕКТ корпуса: утверждение называет RS256 при профиле ES256 ─────────────
d="$(sandbox i12_rs)"
printf '\ninj12-posture · боевая посадка: authMode=production + mTLS + sslmode=require + RS256 · гейт · red: HS256\n' >> "$d/$S12"
capture "$d" "$C12" KACHO_MONOREPO="$P_ES"
assert_code 1 "ДЕФЕКТ: кортеж посадки называет RS256, профиль подписывает ES256 — краснеет"
assert_says "ПОДПИСЬ НЕ ТА" "  ...и вердикт назван своим именем"
assert_says "$S12:" "  ...и названа строка корпуса"
assert_says "называет RS256" "  ...и назван алгоритм корпуса"
assert_says "ES256 — values.prod.yaml" "  ...и назван алгоритм посадки с профилем"

# ── ДЕФЕКТ корпуса через выпуск токена, без слова «подпись» ─────────────────
d="$(sandbox i12_issue)"
printf '\ninj12-e2e · авторизоваться RS256 через выпуск службы доступа · гейт · red: заглушка\n' >> "$d/$S12"
capture "$d" "$C12" KACHO_MONOREPO="$P_ES"
assert_code 1 "ДЕФЕКТ: «авторизоваться RS256 через выпуск» — краснеет"

# ── ДЕФЕКТ посадки: профиль сменил алгоритм, корпус отстал ───────────────────
d="$(sandbox i12_moved)"
capture "$d" "$C12" KACHO_MONOREPO="$P_RS"
assert_code 1 "ДЕФЕКТ: профиль подписывает RS256, корпус называет прежний — краснеет"
assert_says "RS256 — values.prod.yaml" "  ...и назван новый алгоритм посадки"

# ── БЛИЗНЕЦ: алгоритм только в красной колонке ───────────────────────────────
d="$(sandbox i12_twin_red)"; b="$(sandbox_digest "$d")"
printf '\ninj12-red · подпись токена асимметричная · гейт · red: HS256-заглушка на поднятом кластере\n' >> "$d/$S12"
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: HS256 назван в красной колонке"
capture "$d" "$C12" KACHO_MONOREPO="$P_ES"
assert_code 0 "БЛИЗНЕЦ: алгоритм нарушения в red: — молчит"

# ── БЛИЗНЕЦ: подделка — утверждение об отказе, а не о подписи ────────────────
d="$(sandbox i12_twin_forged)"; b="$(sandbox_digest "$d")"
printf '\ninj12-forged · на крае токен forged HS256 ⇒ 401 · гейт · red: 200\n' >> "$d/$S12"
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: forged HS256 в строке с якорем «токен»"
capture "$d" "$C12" KACHO_MONOREPO="$P_ES"
assert_code 0 "БЛИЗНЕЦ: forged HS256 ⇒ 401 — молчит"

# ── БЛИЗНЕЦ: имя алгоритма без якоря подписи ─────────────────────────────────
d="$(sandbox i12_twin_noanchor)"; b="$(sandbox_digest "$d")"
printf '\nРазборщик ключа знает кривые P-256 (RS256 не кривая).\n' >> "$d/$S12"
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: RS256 в строке без якоря"
capture "$d" "$C12" KACHO_MONOREPO="$P_ES"
assert_code 0 "БЛИЗНЕЦ: алгоритм вне утверждения о подписи — молчит"

# ── БЛИЗНЕЦ: та же строка дефекта, алгоритм посадки ──────────────────────────
d="$(sandbox i12_twin_es)"; b="$(sandbox_digest "$d")"
printf '\ninj12-posture · боевая посадка: authMode=production + mTLS + sslmode=require + ES256 · гейт · red: HS256\n' >> "$d/$S12"
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: кортеж посадки называет ES256"
capture "$d" "$C12" KACHO_MONOREPO="$P_ES"
assert_code 0 "БЛИЗНЕЦ: кортеж с алгоритмом профиля — молчит"

# ── ось VOID: профиль не объявляет алгоритм ──────────────────────────────────
d="$(sandbox i12_void_alg)"
capture "$d" "$C12" KACHO_MONOREPO="$P_NONE"
assert_code 2 "ДЕФЕКТ: профиль без tokenSigning.algorithm — ОТКАЗ, не зелёный"
assert_says "[VOID]" "  ...и отказ объявлен строкой [VOID]"

# ── ось VOID: дерева продукта нет ────────────────────────────────────────────
d="$(sandbox i12_void_mono)"
capture "$d" "$C12" KACHO_MONOREPO="$TMP/p.absent"
assert_code 2 "ДЕФЕКТ: дерева продукта нет — ОТКАЗ, не зелёный"

# Перепись части: сколько утверждений набора исполнено к её концу (накопительно —
# счётчики общие с inject.sh). Ноль здесь значил бы, что часть не исполнила ничего.
# shellcheck disable=SC2154  # счётчики pass/fail заводит inject.sh, часть подключается из него
echo "[CENSUS] часть inject-12-signing-algorithm-matches-deploy.sh: утверждений набора к концу части $((pass + fail)), разошлось $fail"
