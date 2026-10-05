#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# plan-precheck-inject.sh — доказательство того, что `scripts/plan-precheck.sh`
# СПОСОБЕН остановить раздачу по каждой причине, а законный близнец той же
# формы проходит.
#
# ВХОД — настоящий: два репозитория git во временном каталоге (`kacho` и
# `kaname`, у каждого `go.mod` с пином corelib — форма строки взята из стволов
# 2026-10-06: `github.com/PRO-Robotech/corelib v1.10.0`), полоса режима git —
# настоящий коммит. Каждая инъекция меняет ОДИН факт против близнеца и обязана
# дать код 1 (2 — для «судить не смог») и строку своей причины; близнец — код 0
# и ни одной строки REASON. Шаги уровня сверяются с прямым вызовом
# `lane-tier.sh`: проверка плана их повторяет, а не выписывает.
# Коды: 0 — все утверждения сошлись; 1 — хотя бы одно нет; 2 — корневой подписи
# нет, посев не построить.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/plan-precheck.sh"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
pass=0 fail=0
assert() {
    if [ "$1" = "$2" ]; then echo "  [OK]   $3"; pass=$((pass + 1))
    else echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; sed 's/^/         /' "$W/out" >&2; fail=$((fail + 1)); fi
}
run() { bash "$P" "$W/plan.json" "$@" > "$W/out" 2>&1; echo $?; }
# reasons — коды причин через запятую, по порядку вывода; «-» — причин нет.
reasons() { awk -F'\t' '$1 == "REASON" { printf "%s%s", s, $2; s = "," } END { if (s == "") printf "-" }' "$W/out"; }
has() { grep -q -- "$1" "$W/out" && echo да || echo нет; }

# shellcheck source=lib/sandbox-git-home.sh
. "$HERE/lib/sandbox-git-home.sh"
sandbox_git_home "$W/home" || exit 2
git() { sandbox_git "$@"; }
mk() { # mk <репо> <версия corelib>
    git init -q -b main "$W/$1"
    printf 'module github.com/PRO-Robotech/%s\n\ngo 1.25\n\nrequire (\n\tgithub.com/PRO-Robotech/corelib %s\n)\n' "$1" "$2" > "$W/$1/go.mod"
    git -C "$W/$1" add . && git -C "$W/$1" commit -qm base
}
mk kacho v1.11.0
mk kaname v1.11.0
KC="$W/kacho" KN="$W/kaname"
# plan <jq-выражение над близнецом> — план в $W/plan.json.
plan() {
    jq -n --arg kc "$KC" --arg kn "$KN" '
      {wave: "9",
       targets: {kacho: {dir: $kc, rev: "main"}, kaname: {dir: $kn, rev: "main"}},
       lanes: [
         {key: "A", repo: "kacho", dir: $kc, base: "main", paths: ["services/vpc/internal/apps/net/usecase.go"]},
         {key: "B", repo: "kacho", dir: $kc, base: "main", paths: ["services/vpc/internal/apps/net/usecase.go", "docs/x.md"], deps: ["A"]},
         {key: "C", repo: "kaname", dir: $kn, base: "main", paths: ["docs/k.md"]}
       ]}' | jq "$1" > "$W/plan.json"
}

echo "== близнец"
plan '.'
assert "0 -" "$(run) $(reasons)" "план без причин — код 0"
assert "0" "$(run --json 2> /dev/null > /dev/null; echo $?)" "--json — тот же код"
bash "$P" "$W/plan.json" --json 2> /dev/null > "$W/j"
assert "A,C|B R1 R0" "$(jq -r '[.layers[] | join(",")] | join("|")' "$W/j") $(jq -r '.lanes[] | select(.key=="A") | .tier' "$W/j") $(jq -r '.lanes[] | select(.key=="C") | .tier' "$W/j")" "слои: A и C параллельно, B после A; уровни из lane-tier"
printf 'services/vpc/internal/apps/net/usecase.go\n' > "$W/pa"
direct="$(bash "$HERE/lane-tier.sh" --json --repo kacho --paths-file "$W/pa" 2> /dev/null | tail -1 | jq -r '.steps | join(",")')"
assert "$direct" "$(jq -r '.lanes[] | select(.key=="A") | .steps | join(",")' "$W/j")" "шаги полосы — те же, что у lane-tier (один дом)"

echo "== объём, ключи, зависимости"
plan 'del(.lanes[2].paths)'
assert "1 LANE-NO-SCOPE" "$(run) $(reasons)" "полоса без paths и head — задание неполно"
plan '.lanes[2].key = "A"'
assert "1 LANE-KEY" "$(run) $(reasons)" "ключ повторён"
plan '.lanes[2].deps = ["Z"]'
assert "1 DEP-UNKNOWN" "$(run) $(reasons)" "зависимость от несуществующей полосы"
plan '.lanes[0].deps = ["B"]'
assert "1 DEP-CYCLE" "$(run) $(reasons)" "A↔B — кольцо"

echo "== пересечения путей"
plan 'del(.lanes[1].deps)'
assert "1 LANES-OVERLAP да" "$(run) $(reasons) $(has 'A и B (kacho) трогают services/vpc/internal/apps/net/usecase.go')" "общий файл без порядка — в параллель нельзя"
plan 'del(.lanes[1].deps) | .lanes[1].paths = ["services/vpc/internal/apps/"]'
assert "1 LANES-OVERLAP" "$(run) $(reasons)" "файл внутри объявленного каталога соседа (каталог у второй полосы)"
plan 'del(.lanes[1].deps) | .lanes[0].paths = ["services/vpc/internal/apps/"]'
assert "1 LANES-OVERLAP" "$(run) $(reasons)" "то же, каталог у первой полосы — сторона пары не важна"
plan 'del(.lanes[1].deps) | .lanes[1].paths = ["services/vpc/internal/apps/net/usecase_extra.go"]'
assert "0 -" "$(run) $(reasons)" "близнец: соседний файл с общим префиксом имени — не пересечение"
plan '.lanes[2].paths = ["services/vpc/internal/apps/net/usecase.go"]'
assert "0 -" "$(run) $(reasons)" "близнец: тот же путь в другом репозитории — не пересечение"

echo "== уровень: понизить объявлением нельзя"
plan '.lanes[0].paths = ["services/vpc/internal/migrations/0042.sql"] | .lanes[0].declared = "R1"'
assert "1 TIER-UNDERSTATED" "$(run) $(reasons)" "миграция объявлена R1"
plan '.lanes[0].declared = "R2"'
bash "$P" "$W/plan.json" --json 2> /dev/null > "$W/j"
assert "0 R2 R1" "$(jq -r '.code' "$W/j") $(jq -r '.lanes[0].tier' "$W/j") $(jq -r '.lanes[0].computed' "$W/j")" "близнец: повысить объявлением можно"

echo "== corelib на целевых головах"
printf 'module github.com/PRO-Robotech/kaname\n\nrequire github.com/PRO-Robotech/corelib v1.10.0\n' > "$KN/go.mod"
git -C "$KN" commit -qam old
plan '.'
assert "1 CORELIB-SKEW да" "$(run) $(reasons) $(has 'kaname на corelib v1.10.0')" "kaname отстаёт, полосы перепина нет"
bash "$P" "$W/plan.json" --json 2> /dev/null > "$W/j"
assert "kaname v1.10.0 v1.11.0" "$(jq -r '.autoRepin[0] | "\(.repo) \(.from) \(.to)"' "$W/j")" "autoRepin называет репозиторий и обе версии"
plan '.lanes += [{key: "R", repo: "kaname", dir: .lanes[2].dir, base: "main", paths: ["go.mod", "go.sum"], repin: "corelib"}] | .lanes[2].deps = ["R"]'
assert "0 -" "$(run) $(reasons)" "близнец: полоса перепина есть и C от неё зависит"
plan '.lanes += [{key: "R", repo: "kaname", dir: .lanes[2].dir, base: "main", paths: ["go.mod", "go.sum"], repin: "corelib"}]'
assert "1 CORELIB-SKEW" "$(run) $(reasons)" "полоса перепина есть, но C от неё не зависит"
plan 'del(.targets.kaname)'
assert "2 да" "$(run) $(has 'TARGET-MISSING')" "целевой головы нет — судить не смог, код 2"
printf 'module github.com/PRO-Robotech/kaname\n\nrequire github.com/PRO-Robotech/corelib v1.11.0\n' > "$KN/go.mod"
git -C "$KN" commit -qam repin

echo "== режим git: полоса уже писала"
git -C "$KC" checkout -qb lane
mkdir -p "$KC/services/vpc/internal/migrations" && echo 'SELECT 1;' > "$KC/services/vpc/internal/migrations/0001.sql"
git -C "$KC" add . && git -C "$KC" commit -qm lane
plan '.lanes[0] = {key: "A", repo: "kacho", dir: .lanes[0].dir, base: "main", head: "lane"}'
bash "$P" "$W/plan.json" --json 2> /dev/null > "$W/j"
assert "R2 true" "$(jq -r '.lanes[] | select(.key=="A") | .tier' "$W/j") $(jq -r '.lanes[] | select(.key=="A") | .acceptance' "$W/j")" "уровень по диффу base...head — миграция R2 с приёмкой"
plan '.lanes[0] = {key: "A", repo: "kacho", dir: .lanes[0].dir, base: "main", head: "нет-такой"}'
assert "2" "$(run)" "голова не разрешается — код 2"

echo "== план не разбирается — не «годен»"
echo '{' > "$W/plan.json"
assert "2" "$(run)" "битый JSON — код 2"
echo '{"lanes": []}' > "$W/plan.json"
assert "2" "$(run)" "ноль полос — код 2"

echo
echo "plan-precheck-inject: утверждений $((pass + fail)); сошлось $pass, разошлось $fail"
[ $((pass + fail)) -gt 0 ] || exit 2
[ "$fail" -eq 0 ]
