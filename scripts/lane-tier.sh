#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# lane-tier.sh — уровень риска полосы (R0 / R1 / R2) по признакам её дельты и
# шаги, которые этот уровень обязан пройти.
#
# ОСНОВАНИЕ. Решение владельца 2026-10-06 («Да, по уровням (Recommended)»):
# R0 (документы, тесты, оснастка, уровни журнала) — исполнитель + проверка
# скриптом + CI, без агентов-рецензентов; R1 (обычный код) — TDD + один
# рецензент на собранную волну, а не на полосу; R2 (безопасность, вход и права,
# данные и миграции, публичный контракт) — полный набор; приёмка — только при
# изменении публичного контракта. Дословно — `.claude/backup/flow-acceleration.md`.
#
# ЕДИНСТВЕННЫЙ ДОМ СООТВЕТСТВИЯ «уровень → шаги». Шаблон волны и проверка плана
# берут шаги ОТСЮДА (строки `steps:`, `roles:`, `acceptance:` либо `--json`), а
# не выписывают их у себя: второе изложение разошлось бы с этим молча.
#
# ВХОД. Либо `<каталог репозитория> <база> <голова>` — пути берутся из
# `git diff --name-only база...голова`, добавленные строки — из того же диффа;
# либо `--paths-file <файл>` (путь на строку) и необязательный
# `--added-file <файл>` (добавленные строки). Имя репозитория для признаков
# продукта — `--repo <имя>` или базовое имя адреса `origin`.
#
# ПРИЗНАКИ (по каждому пути, уровень полосы — наибольший):
#   R0  путь документа, пробы или оснастки: `*.md`, `docs/`, `obsidian/`,
#       `.claude/`, `scripts/`, `.github/`, `tests/`, `testdata/`, `*_test.go`,
#       `*.test.ts(x)`, `*.spec.ts(x)`, `e2e/`;
#   R2  (если путь не R0) миграции и SQL (`migrations/`, `*.sql`) → роль
#       `db-architect-reviewer`; контракт (`*.proto`, `proto/`, `openapi`,
#       `swagger`) → `proto-api-reviewer` и приёмка; публичный край (`gateway/`)
#       → `proto-api-reviewer`; вход и права (сегмент пути authz, authn, auth,
#       iam, listauthz, permission(s), rbac, policy/policies, jwks, oidc,
#       token(s), session(s), credential(s), identity; любой Go-путь репозитория
#       `kaname` — продукта управления доступом) → `security-auditor`; секреты и
#       посадка (`secret`, `*.pem`, `*.key`, `*.crt`, `tls`, `cert`, values-файлы
#       чартов) → `security-auditor`; согласованность (`outbox`, `subscription`,
#       `reconcile`) → `system-design-reviewer`;
#   R2  по СОДЕРЖИМОМУ — для любого пути, включая R0: добавленная строка несёт
#       закрытый ключ (`BEGIN … PRIVATE KEY`) или присваивание секрета литералом
#       (password|passwd|secret|api_key|token = 8+ символов) → `security-auditor`;
#   R1  прочее.
# Ролей не больше трёх (`git-issues.md#gi-asm-one-round`), в порядке выше.
#
# ОБЪЯВЛЕННЫЙ УРОВЕНЬ (`--declared Rn`) может ПОВЫСИТЬ вычисленный, но не
# понизить: объявление ниже вычисленного — находка TIER-UNDERSTATED.
#
# ГРАНИЦА (не ловится, названо): правка одного лишь уровня журнала в коде по
# пути не отличима от правки кода — такая полоса получает R1, то есть строже
# решения владельца, а не мягче; признак по содержимому видит только литералы
# названных форм, секрет, собранный из частей, он не увидит.
#
# ВЫВОД — строками `ключ: значение` (перепись первой), с `--json` — объектом.
# Коды: 0 — уровень вычислен; 1 — находка (TIER-UNDERSTATED); 2 — уровня нет:
# путей ноль, дифф не читается, вход не разобран.
# Держит `scripts/lane-tier-inject.sh`.
set -uo pipefail

usage() {
    echo "usage: lane-tier.sh [--declared R0|R1|R2] [--repo <имя>] [--json] (<каталог> <база> <голова> | --paths-file <файл> [--added-file <файл>])" >&2
    exit 2
}

declared="" repo="" json=0 paths_file="" added_file=""
pos=()
while [ $# -gt 0 ]; do
    case "$1" in
        --declared) [ $# -ge 2 ] || usage; declared="$2"; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; repo="$2"; shift 2 ;;
        --json) json=1; shift ;;
        --paths-file) [ $# -ge 2 ] || usage; paths_file="$2"; shift 2 ;;
        --added-file) [ $# -ge 2 ] || usage; added_file="$2"; shift 2 ;;
        -h | --help) usage ;;
        *) pos+=("$1"); shift ;;
    esac
done
case "$declared" in "" | R0 | R1 | R2) ;; *)
    echo "lane-tier: VOID — объявленный уровень «$declared» вне словаря R0|R1|R2" >&2; exit 2 ;;
esac

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

if [ -n "$paths_file" ]; then
    [ "${#pos[@]}" -eq 0 ] || usage
    { [ -f "$paths_file" ] && [ -r "$paths_file" ]; } || { echo "lane-tier: VOID — файл путей не читается: $paths_file" >&2; exit 2; }
    grep -v '^[[:space:]]*$' "$paths_file" > "$W/paths" || true
    if [ -n "$added_file" ]; then
        { [ -f "$added_file" ] && [ -r "$added_file" ]; } || { echo "lane-tier: VOID — файл строк не читается: $added_file" >&2; exit 2; }
        cp "$added_file" "$W/added"
    else
        : > "$W/added"
    fi
else
    [ "${#pos[@]}" -eq 3 ] || usage
    dir="${pos[0]}" base="${pos[1]}" head="${pos[2]}"
    if ! git -C "$dir" diff --name-only "$base...$head" > "$W/paths" 2> "$W/err"; then
        echo "lane-tier: VOID — дифф $base...$head в $dir не читается: $(head -c 300 "$W/err")" >&2
        exit 2
    fi
    if ! git -C "$dir" diff --no-color -U0 "$base...$head" > "$W/diff" 2> "$W/err"; then
        echo "lane-tier: VOID — содержимое диффа не читается: $(head -c 300 "$W/err")" >&2
        exit 2
    fi
    grep -E '^\+' "$W/diff" | grep -vE '^\+\+\+ ' | cut -c2- > "$W/added" || true
    if [ -z "$repo" ]; then
        url="$(git -C "$dir" remote get-url origin 2> /dev/null || true)"
        repo="${url##*/}"; repo="${repo%.git}"
    fi
fi

n_paths="$(wc -l < "$W/paths" | tr -d ' ')"
n_added="$(wc -l < "$W/added" | tr -d ' ')"
if [ "$n_paths" -eq 0 ]; then
    echo "lane-tier: осмотрено путей 0; добавленных строк $n_added"
    echo "lane-tier: VOID — путей ноль: уровня нет (ноль целей — отказ, а не R0)" >&2
    exit 2
fi

# Классификация путей — одним awk: путь → «уровень<TAB>роль<TAB>признак<TAB>путь».
LC_ALL=C awk -v repo="$repo" '
function seg(p, re) { return (("/" p "/") ~ ("/(" re ")(/|[._-])")) }
{
    p = $0; low = tolower(p)
    if (low ~ /\.md$/ || low ~ /^(docs|obsidian|\.claude|scripts|\.github)\// ||
        low ~ /(^|\/)(tests?|testdata|e2e)\// || low ~ /_test\.go$/ ||
        low ~ /\.(test|spec)\.tsx?$/) { print "R0\t-\tдокумент, проба или оснастка\t" p; next }
    if (low ~ /(^|\/)migrations\// || low ~ /\.sql$/) { print "R2\tdb-architect-reviewer\tданные и миграции\t" p; next }
    if (low ~ /\.proto$/ || low ~ /(^|\/)proto\// || low ~ /openapi/ || low ~ /swagger/) {
        print "R2\tproto-api-reviewer\tпубличный контракт\t" p; next }
    if (low ~ /^gateway\//) { print "R2\tproto-api-reviewer\tпубличный край\t" p; next }
    if (seg(low, "authz|authn|auth|iam|listauthz|permissions?|rbac|polic(y|ies)|jwks|oidc|tokens?|sessions?|credentials?|identity")) {
        print "R2\tsecurity-auditor\tвход и права\t" p; next }
    if (repo == "kaname" && low ~ /\.go$/) { print "R2\tsecurity-auditor\tвход и права (продукт управления доступом)\t" p; next }
    if (low ~ /secret/ || low ~ /\.(pem|key|crt)$/ || seg(low, "tls|certs?") ||
        low ~ /(^|\/)deploy\/helm\/.*values[^\/]*\.ya?ml$/) {
        print "R2\tsecurity-auditor\tсекреты и посадка\t" p; next }
    if (seg(low, "outbox|subscription|subscriptionjournal|reconcile")) {
        print "R2\tsystem-design-reviewer\tсогласованность\t" p; next }
    print "R1\t-\tкод\t" p
}' "$W/paths" > "$W/class"

# Признак по содержимому — для любого пути.
secret_hits="$(LC_ALL=C grep -cE -- '-----BEGIN [A-Z ]*PRIVATE KEY-----|(password|passwd|secret|api[_-]?key|token)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9/+_=-]{8,}' "$W/added" || true)"

r0="$(grep -c '^R0' "$W/class" || true)"
r1="$(grep -c '^R1' "$W/class" || true)"
r2="$(grep -c '^R2' "$W/class" || true)"
r2_paths="$r2"
[ "${secret_hits:-0}" -gt 0 ] && r2=$((r2 + 1)) && printf 'R2\tsecurity-auditor\tсекрет в добавленных строках (%s)\t-\n' "$secret_hits" >> "$W/class"

tier=R0
[ "$r1" -gt 0 ] && tier=R1
[ "$r2" -gt 0 ] && tier=R2
computed="$tier"

rank() { echo "${1#R}"; }
rc=0
understated=""
if [ -n "$declared" ]; then
    if [ "$(rank "$declared")" -lt "$(rank "$computed")" ]; then
        understated="объявлен $declared, вычислен $computed"
        rc=1
    elif [ "$(rank "$declared")" -gt "$(rank "$computed")" ]; then
        tier="$declared"
    fi
fi

# Роли R2: порядок словаря, без повторов, не больше трёх.
roles=""
if [ "$tier" = R2 ]; then
    for r in security-auditor db-architect-reviewer proto-api-reviewer system-design-reviewer; do
        if grep -q "^R2"$'\t'"$r"$'\t' "$W/class"; then
            n_roles="$(printf '%s' "$roles" | tr ',' '\n' | grep -c . || true)"
            [ "$n_roles" -lt 3 ] && roles="${roles:+$roles,}$r"
        fi
    done
    # Повышенный объявлением или R2 только по коду: роль кода — go-style-reviewer.
    [ -n "$roles" ] || roles="go-style-reviewer"
fi
acceptance=no
grep -q $'^R2\tproto-api-reviewer\tпубличный контракт\t' "$W/class" && acceptance=yes

# Соответствие «уровень → шаги» — единственное в дереве.
case "$tier" in
    R0) steps="implementer,lane-precheck,ci"; review="none" ;;
    R1) steps="implementer-tdd,lane-precheck,ci,wave-reviewer"; review="wave" ;;
    R2) steps="surface-census,implementer-tdd,lane-precheck,roles,wave-reviewer,ci,landing-reviewer"; review="roles+wave" ;;
esac
[ "$acceptance" = yes ] && steps="acceptance(<=2),$steps"
mechanical_model="haiku"

echo "lane-tier: осмотрено путей $n_paths (R0 $r0 · R1 $r1 · R2 $r2_paths); добавленных строк $n_added; признаков секрета $secret_hits; репозиторий ${repo:--}"
if [ "$json" = 1 ]; then
    python3 - "$tier" "$computed" "${declared:-}" "$acceptance" "$roles" "$steps" "$review" "$mechanical_model" "$W/class" "$understated" <<'PY'
import json, sys
tier, computed, declared, acc, roles, steps, review, model, cls, under = sys.argv[1:11]
reasons = []
with open(cls, encoding='utf-8') as fh:
    for line in fh:
        t, role, sign, path = line.rstrip('\n').split('\t')
        reasons.append({'tier': t, 'role': None if role == '-' else role, 'sign': sign, 'path': None if path == '-' else path})
print(json.dumps({'tier': tier, 'computed': computed, 'declared': declared or None,
                  'acceptance': acc == 'yes', 'roles': [r for r in roles.split(',') if r],
                  'steps': steps.split(','), 'review': review, 'mechanicalModel': model,
                  'understated': under or None, 'reasons': reasons}, ensure_ascii=False))
PY
else
    echo "tier: $tier"
    echo "computed: $computed"
    echo "acceptance: $acceptance"
    echo "roles: ${roles:--}"
    echo "review: $review"
    echo "steps: $steps"
    echo "mechanical-model: $mechanical_model"
    awk -F'\t' '$1 != "R0" || NR <= 3 { printf "reason: %s %s %s\n", $1, $3, $4 }' "$W/class" | head -40
fi
if [ -n "$understated" ]; then
    echo "REASON TIER-UNDERSTATED $understated: понизить уровень объявлением нельзя" >&2
fi
exit "$rc"
