#!/usr/bin/env bash
# Доказательство того, что check-06 (учётные данные в хранилище) СПОСОБЕН упасть и
# СПОСОБЕН смолчать — на копии настоящего хранилища.
#
# Контроли:
#   1. закрытый ключ PEM в замороженном архиве (`KAC/`) → код 1: предмет — ВСЁ
#      хранилище, заморозка утечку не отменяет; названа координата;
#   2. токен GitHub в уроке → код 1;
#   3. учётный литерал (`password: …` буквы и цифры) в процедуре → код 1, и
#      значение в выводе НЕ напечатано (вывод гейта сам публичен в журнале CI);
#   4. законные близнецы той же формы: имя ресурса без цифр, заглушки `<…>`,
#      `{{…}}`, `${…}` → молчание;
#   5. хранилище пусто → код 2 (VOID), не 0.
# Образцы собираются конкатенацией: в тексте этого файла литерала нет, и сканер
# отправки на нём не срабатывает.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_REAL="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK="$SCRIPT_DIR/check-06-no-secret-in-vault.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok=0
bad=0

setup_tree() {
    local d="$TMP/$1"
    rm -rf "$d"; mkdir -p "$d"; git -C "$d" init -q
    (cd "$WS_REAL" && git ls-files --cached --others --exclude-standard 'obsidian/kacho/*') | while read -r f; do
        install -D "$WS_REAL/$f" "$d/$f"
    done
    git -C "$d" add -A >/dev/null 2>&1
    printf '%s' "$d"
}

run_on() { VAULT_GATE_ROOT="$1" bash "$CHECK" 2>&1; }

expect_code() {
    local name="$1" want="$2" got="$3" out="$4"
    if [ "$got" = "$want" ]; then echo "[inject OK]   $name (ожидали код $want, получили $got)"; ok=$((ok + 1))
    else echo "[inject FAIL] $name (ожидали код $want, получили $got)" >&2; printf '%s\n' "$out" | sed 's/^/    /' >&2; bad=$((bad + 1)); fi
}
expect_names() {
    local name="$1" needle="$2" out="$3"
    case "$out" in *"$needle"*) echo "[inject OK]   $name (гейт назвал $needle)"; ok=$((ok + 1)) ;;
        *) echo "[inject FAIL] $name (гейт не назвал $needle)" >&2; bad=$((bad + 1)) ;; esac
}
expect_silent_about() {
    local name="$1" needle="$2" out="$3"
    case "$out" in *"$needle"*) echo "[inject FAIL] $name (в выводе есть $needle, а не должно)" >&2; bad=$((bad + 1)) ;;
        *) echo "[inject OK]   $name (про $needle гейт молчит)"; ok=$((ok + 1)) ;; esac
}

pem="-----BEGIN ""RSA PRIVATE KEY-----"
ghtok="gh""p_$(printf 'Ab1%.0s' {1..12})"
pwlit="Kacho""Stand2026x"

# --- (1) PEM в замороженном архиве.
d="$(setup_tree pem)"
printf '\n%s\nMIIB\n' "$pem" >> "$d/obsidian/kacho/KAC/KAC-127.md"
git -C "$d" add -A >/dev/null 2>&1
out="$(run_on "$d")"; code=$?
expect_code "закрытый ключ в архиве пойман" 1 "$code" "$out"
expect_names "гейт назвал координату в архиве" "KAC/KAC-127.md" "$out"

# --- (2) Токен GitHub в уроке.
d="$(setup_tree gh)"
printf -- '---\ntitle: "инъекция"\ncategory: lesson\n---\n# инъекция\nтокен %s\n' "$ghtok" \
    > "$d/obsidian/kacho/lessons/zz-inject-gh.md"
git -C "$d" add -A >/dev/null 2>&1
out="$(run_on "$d")"; code=$?
expect_code "токен GitHub пойман" 1 "$code" "$out"
expect_names "гейт назвал форму" "токен GitHub" "$out"

# --- (3) Учётный литерал в процедуре; значение не печатается.
d="$(setup_tree pw)"
# shellcheck disable=SC2016  # обратные кавычки — разметка вносимого markdown, не подстановка.
printf -- '---\ntitle: "инъекция"\ncategory: runbook\n---\n# инъекция\n`password: %s`\n' "$pwlit" \
    > "$d/obsidian/kacho/runbooks/zz-inject-pw.md"
git -C "$d" add -A >/dev/null 2>&1
out="$(run_on "$d")"; code=$?
expect_code "учётный литерал пойман" 1 "$code" "$out"
expect_names "гейт назвал координату" "runbooks/zz-inject-pw.md" "$out"
expect_silent_about "значение в выводе не напечатано" "$pwlit" "$out"

# --- (4) Законные близнецы той же формы.
d="$(setup_tree twins)"
# shellcheck disable=SC2016  # `${…}` и обратные кавычки — ТЕКСТ близнеца-заглушки, не подстановка.
printf -- '---\ntitle: "инъекция"\ncategory: runbook\n---\n# инъекция\n%s\n%s\n%s\n%s\n' \
    '`existingSecret: kacho-db-credentials`' '`password: <пароль-стенда-2026>`' \
    '`token: {{token2026abcdef}}`' '`apiKey=${KACHO_API_KEY_2026}`' \
    > "$d/obsidian/kacho/runbooks/zz-inject-twins.md"
git -C "$d" add -A >/dev/null 2>&1
out="$(run_on "$d")"; code=$?
expect_code "законные близнецы: имя без цифр и заглушки молчат" 0 "$code" "$out"
expect_silent_about "гейт про близнецов молчит" "zz-inject-twins.md" "$out"

# --- (5) Хранилище пусто → VOID.
d="$TMP/void"; rm -rf "$d"; mkdir -p "$d"; git -C "$d" init -q
out="$(run_on "$d")"; code=$?
expect_code "пустое хранилище даёт VOID, а не PASS" 2 "$code" "$out"

echo
echo "inject-06: контролей пройдено $ok, провалено $bad"
[ "$bad" -eq 0 ]
