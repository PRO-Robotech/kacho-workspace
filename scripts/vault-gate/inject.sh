#!/usr/bin/env bash
# Доказательство того, что гейт СПОСОБЕН упасть — и способен смолчать.
#
# Одного положительного контроля мало: гейт, ловящий форму, а не существо, красен
# и на законной записке, и первый же ложный срабат его отключат. Поэтому рядом с
# внесённым дефектом ставится ЗАКОННЫЙ БЛИЗНЕЦ той же формы, и от гейта требуется
# молчание (`gate-authoring` §Инъекция настоящим входом с законным близнецом).
#
# Отдельно проверяются ПРЕДПОСЫЛКИ: без монорепо и без объявленного в дереве
# запрета гейт обязан сказать VOID, а не PASS. Гейт, который на пустом месте
# печатает «чисто», — худший из возможных: он тем зеленее, чем меньше видит.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_REAL="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK="$SCRIPT_DIR/check-01-retired-mechanism-not-current.sh"

: "${KACHO_MONOREPO:?inject.sh требует KACHO_MONOREPO — предмет запрета выводится из дерева монорепо}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok=0
bad=0

# Рабочая копия дерева workspace: инъекция не трогает настоящее.
setup_tree() {
    local d="$TMP/$1"
    rm -rf "$d"
    mkdir -p "$d/obsidian/kacho/edges"
    git -C "$d" init -q
    # Записки берём из настоящего индекса — иначе гейт судил бы синтетику и
    # ничего не сказал бы о реальном дереве.
    (cd "$WS_REAL" && git ls-files 'obsidian/kacho/edges/*.md') | while read -r f; do
        install -D "$WS_REAL/$f" "$d/$f"
    done
    git -C "$d" add -A >/dev/null 2>&1
    printf '%s' "$d"
}

expect() {
    local name="$1" want="$2" got="$3" out="$4"
    if [ "$got" = "$want" ]; then
        echo "[inject OK]   $name (ожидали код $want, получили $got)"
        ok=$((ok + 1))
    else
        echo "[inject FAIL] $name (ожидали код $want, получили $got)" >&2
        printf '%s\n' "$out" | sed 's/^/    /' >&2
        bad=$((bad + 1))
    fi
}

# Контроль близнеца спрашивает про СВОЙ файл, а не про чистоту всего дерева.
# Иначе любая посторонняя находка — в том числе та, ради которой гейт и писался,
# — делает контроль красным и говорит о близнеце ровно ничего
# (`gate-authoring` §Отрицание только в паре с положительным: у отрицания должен
# быть свой референт).
expect_silent_about() {
    local name="$1" coord="$2" out="$3"
    case "$out" in
        *"$coord"*)
            echo "[inject FAIL] $name (гейт назвал $coord, а не должен был)" >&2
            bad=$((bad + 1)) ;;
        *)
            echo "[inject OK]   $name (про $coord гейт молчит)"
            ok=$((ok + 1)) ;;
    esac
}

run_on() { VAULT_GATE_ROOT="$1" bash "$CHECK" 2>&1; }

# --- (1) Внесённый дефект: ребро названо снятым механизмом, состояние текущее.
d="$(setup_tree defect)"
cat > "$d/obsidian/kacho/edges/zz-inject-defect.md" <<'EOF'
---
title: "storage → iam: AuthorizeService.ListObjects (List filtering)"
category: edge
status: active
---
# storage → iam: AuthorizeService.ListObjects
Сужение списка идёт перечислением всех видимых id.
EOF
git -C "$d" add -A >/dev/null 2>&1
out="$(run_on "$d")"; code=$?
expect "внесённый дефект пойман" 1 "$code" "$out"
case "$out" in
    *zz-inject-defect.md*) echo "[inject OK]   гейт назвал координату" ; ok=$((ok + 1)) ;;
    *) echo "[inject FAIL] гейт упал, но координату не назвал" >&2 ; bad=$((bad + 1)) ;;
esac

# --- (2) Законный близнец A: та же форма, но записка признаёт прошлое.
d="$(setup_tree twin_retired)"
cat > "$d/obsidian/kacho/edges/zz-inject-twin-a.md" <<'EOF'
---
title: "storage → iam: AuthorizeService.ListObjects (снято)"
category: edge
status: removed
---
# storage → iam: AuthorizeService.ListObjects
Механизм снят; страница сужается пакетной проверкой.
EOF
git -C "$d" add -A >/dev/null 2>&1
out="$(run_on "$d")"
expect_silent_about "законный близнец: состояние признаёт прошлое" "zz-inject-twin-a.md" "$out"

# --- (3) Законный близнец B: механизм назван в ТЕЛЕ (объяснение, почему снят),
# заголовок его не называет. Такой абзац обязан существовать, и краснеть на нём
# значит вынуждать удалять объяснение — то есть готовить возврат снятого.
d="$(setup_tree twin_body)"
cat > "$d/obsidian/kacho/edges/zz-inject-twin-b.md" <<'EOF'
---
title: "storage → iam: пакетная проверка страницы"
category: edge
status: active
---
# storage → iam: пакетная проверка страницы
Почему не ListObjects: у перечисления есть жёсткий предел и нет продолжения,
поэтому собственный ресурс тенанта выпадал за префикс. ListAllowedIDs — то же.
EOF
git -C "$d" add -A >/dev/null 2>&1
out="$(run_on "$d")"
expect_silent_about "законный близнец: механизм только в теле" "zz-inject-twin-b.md" "$out"

# --- (4) Предпосылка: монорепо недостижимо → VOID, не PASS.
d="$(setup_tree premise_norepo)"
out="$(KACHO_MONOREPO="$TMP/nonexistent" VAULT_GATE_ROOT="$d" bash "$CHECK" 2>&1)"; code=$?
expect "без монорепо — VOID, а не «чисто»" 2 "$code" "$out"

# --- (5) Предпосылка: в дереве монорепо запрет больше не объявлен → VOID.
# Подменяем монорепо пустым git-деревом: анализаторов нет, выводить не из чего.
empty="$TMP/emptyrepo"; mkdir -p "$empty"; git -C "$empty" init -q
git -C "$empty" commit -q --allow-empty -m init 2>/dev/null || true
d="$(setup_tree premise_noban)"
out="$(KACHO_MONOREPO="$empty" VAULT_GATE_ROOT="$d" bash "$CHECK" 2>&1)"; code=$?
expect "запрет в дереве исчез — VOID, а не «чисто»" 2 "$code" "$out"

echo
echo "inject: пройдено $ok, провалено $bad"
[ "$bad" -eq 0 ]
