#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# lane-tier-inject.sh — доказательство того, что `scripts/lane-tier.sh` СПОСОБЕН
# поднять уровень полосы по каждому признаку и отказать в занижении, а не только
# объявляет это в шапке.
#
# Каждый признак подаётся настоящим входом (перечень путей; для режима git —
# настоящий репозиторий во временном каталоге), рядом — законный близнец той же
# формы, который уровня не поднимает: путь `author.go` рядом с `auth/`, ссылка на
# переменную рядом с литералом секрета, проба authz рядом с кодом authz. Пустой
# вход — не R0, а «уровня нет». Вывод `--json` сверяется с текстовым: шаги
# уровня — одна запись, и два вида вывода обязаны её повторить.
# Коды: 0 — все утверждения сошлись; 1 — хотя бы одно нет; 2 — корневой подписи нет,
# посев режима git не построить.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$HERE/lane-tier.sh"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
pass=0 fail=0

assert() {
    if [ "$1" = "$2" ]; then echo "  [OK]   $3"; pass=$((pass + 1))
    else echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; fail=$((fail + 1)); fi
}
# tier_of <файл путей> [аргументы…] — «код уровень» из текстового вывода.
run() { bash "$T" "$@" > "$W/out" 2> "$W/err"; echo $?; }
field() { sed -n "s/^$1: //p" "$W/out" | head -1; }
paths() { printf '%s\n' "$@" > "$W/p"; }

echo "== уровень по путям"
paths docs/x.md .claude/agents/a.md scripts/g/check.sh tests/newman/cases/a.py services/vpc/internal/net_test.go
assert "0 R0 none" "$(run --paths-file "$W/p") $(field tier) $(field review)" "R0: документы, оснастка, пробы — без рецензентов"
paths docs/x.md services/vpc/internal/apps/net/usecase.go
assert "0 R1 wave" "$(run --paths-file "$W/p") $(field tier) $(field review)" "R1: обычный код — один рецензент на собранную волну"
assert "implementer-tdd,lane-precheck,ci,wave-reviewer" "$(field steps)" "R1: шаги — TDD, предпроверка полосы, CI, рецензент волны"
paths services/vpc/internal/migrations/0042_add.sql
assert "0 R2 db-architect-reviewer yes" "$(run --paths-file "$W/p") $(field tier) $(field roles) $(field acceptance)" "R2: миграция → роль данных и приёмка (ban01, TestNewMigrationCitesAnApprovedAcceptance)"
case "$(field steps)" in "acceptance(<=2),"*) a=да ;; *) a=нет ;; esac
assert "да" "$a" "R2 с миграцией: шаг приёмки первым"
paths services/vpc/internal/repo/queries/network.sql
assert "0 R2 db-architect-reviewer no" "$(run --paths-file "$W/p") $(field tier) $(field roles) $(field acceptance)" "близнец: SQL вне каталога миграций — роль данных, приёмки нет"
paths services/vpc/internal/migrations/0043_backfill.go
assert "0 R2 yes" "$(run --paths-file "$W/p") $(field tier) $(field acceptance)" "R2: Go-миграция (признак каталога migrations/ сам по себе)"
paths proto/kacho/cloud/vpc/v1/network.proto
assert "0 R2 proto-api-reviewer yes" "$(run --paths-file "$W/p") $(field tier) $(field roles) $(field acceptance)" "R2: proto → контракт и приёмка"
case "$(field steps)" in "acceptance(<=2),"*) a=да ;; *) a=нет ;; esac
assert "да" "$a" "R2 с контрактом: шаг приёмки первым и с пределом двух кругов"
# Каждый признак контракта — отдельным путём, который несёт ТОЛЬКО его.
paths services/vpc/api/network.proto
assert "0 R2 yes" "$(run --paths-file "$W/p") $(field tier) $(field acceptance)" "*.proto вне каталога proto/ → контракт"
paths proto/buf.yaml
assert "0 R2 yes" "$(run --paths-file "$W/p") $(field tier) $(field acceptance)" "каталог proto/ без *.proto → контракт"
paths services/vpc/internal/openapi/spec.yaml
assert "0 R2 yes" "$(run --paths-file "$W/p") $(field tier) $(field acceptance)" "openapi в пути → контракт"
paths services/vpc/swagger.json
assert "0 R2 yes" "$(run --paths-file "$W/p") $(field tier) $(field acceptance)" "swagger в пути → контракт"
paths services/vpc/internal/apps/protocol.go
assert "0 R1" "$(run --paths-file "$W/p") $(field tier)" "близнец: protocol.go — не proto/ и не *.proto — R1"
paths gateway/internal/routes/vpc.go
assert "0 R2 no" "$(run --paths-file "$W/p") $(field tier) $(field acceptance)" "R2: публичный край без proto — без приёмки"

echo "== согласованность, посадка и секрет по пути: каждый признак отдельно"
for x in outbox/relay.go subscription/feed.go reconcile/loop.go; do
    paths "services/vpc/internal/$x"
    assert "0 R2 system-design-reviewer" "$(run --paths-file "$W/p") $(field tier) $(field roles)" "$x → согласованность"
done
paths services/vpc/internal/apps/outboxed_notes.go
assert "0 R1" "$(run --paths-file "$W/p") $(field tier)" "близнец: outbox не началом сегмента с границей — R1"
paths services/vpc/internal/tls/config.go
assert "0 R2 security-auditor" "$(run --paths-file "$W/p") $(field tier) $(field roles)" "сегмент tls/ → посадка"
paths pkg/certs/load.go
assert "0 R2 security-auditor" "$(run --paths-file "$W/p") $(field tier) $(field roles)" "сегмент certs/ → посадка"
paths pkg/secretstore/store.go
assert "0 R2 security-auditor" "$(run --paths-file "$W/p") $(field tier) $(field roles)" "secret в пути → посадка"
paths pkg/certainty/score.go
assert "0 R1" "$(run --paths-file "$W/p") $(field tier)" "близнец: certainty — не сегмент cert — R1"

echo "== вход и права: признак и близнец"
paths services/iam/internal/authz/check.go
assert "0 R2 security-auditor" "$(run --paths-file "$W/p") $(field tier) $(field roles)" "сегмент authz/ → R2, роль безопасности"
paths services/vpc/internal/apps/author.go
assert "0 R1" "$(run --paths-file "$W/p") $(field tier)" "близнец: author.go не сегмент auth — R1"
# Формы дерева kacho, где слово стоит НЕ отдельным сегментом (check-verifier ws#933, п. 2).
for x in services/compute/internal/authzfilter/filter.go services/nlb/internal/apps/tg/tg_authz.go \
         services/storage/internal/shared/objectauthz.go cmd/kacho-registry/tokenverifier.go \
         services/registry/internal/config/tokenissuers.go services/iam/internal/apps/rbacsync.go \
         services/iam/internal/oauthclient/c.go services/vpc/internal/iam_client.go \
         pkg/listnarrow/narrowiam/client.go ui-future/host/src/remotes/IamRemote.tsx \
         services/vpc/internal/apps/authmw.go services/vpc/internal/apps/authorizer.go; do
    paths "$x"
    assert "0 R2 security-auditor" "$(run --paths-file "$W/p") $(field tier) $(field roles)" "$x → вход и права"
done
paths services/vpc/internal/apps/diameter.go
assert "0 R1" "$(run --paths-file "$W/p") $(field tier)" "близнец: diameter.go — iam не началом сегмента — R1"
paths services/iam/internal/authz/check_test.go
assert "0 R0" "$(run --paths-file "$W/p") $(field tier)" "проба authz — R0 (тесты — решение владельца)"
paths internal/registry/store.go
assert "0 R2" "$(run --repo kaname --paths-file "$W/p") $(field tier)" "Go-путь kaname — R2 (продукт управления доступом)"
assert "0 R1" "$(run --repo kacho --paths-file "$W/p") $(field tier)" "близнец: тот же путь в kacho — R1"
paths deploy/helm/vpc/values-prod.yaml
assert "0 R2 security-auditor" "$(run --paths-file "$W/p") $(field tier) $(field roles)" "values чарта — R2, посадка"

echo "== секрет по содержимому — и в пути R0"
# Литералы собираются из частей во время прогона: в диффе этой пробы их нет, и
# полоса оснастки не поднимается до R2 собственными фикстурами (шапка lane-tier).
paths docs/howto.md
val="S3cr3t""Value99"
# shellcheck disable=SC2016  # обратные кавычки — форма литерала Go, сам вход пробы
for key_form in 'password: "%s"' 'PASSWORD="%s"' 'DB_PASSWORD: "%s"' 'apiToken = "%s"' 'clientSecret: "%s"' \
                'password: %s' 'KACHO_DB_PASSWORD=%s' 'api_key := `%s`' '"secret": "%s",' 'secretKey: "%s"' 'TOKEN_VALUE=%s'; do
    # shellcheck disable=SC2059  # формат — сам вход пробы
    printf "$key_form\n" "$val" > "$W/a"
    assert "0 R2" "$(run --paths-file "$W/p" --added-file "$W/a") $(field tier)" "литерал секрета «$key_form» → R2"
done
# Значения со спецсимволами (check-verifier ws#933 A-r2, п.1) — тоже из частей.
# shellcheck disable=SC2016  # `$def` — знаки значения пробы, а не подстановка
for pair in 'password := "%s"|p@ss''w0rd!Xy' 'DB_PASSWORD=%s|Qw3r''ty!@#2024' 'clientSecret: "%s"|abc$def''%ghi^jkl' \
            'token: %s|t0k&en''*value~1' 'API_KEY="%s"|k3y:wi''th:colons'; do
    # shellcheck disable=SC2059  # формат — сам вход пробы
    printf "${pair%%|*}\n" "${pair#*|}" > "$W/a"
    assert "0 R2" "$(run --paths-file "$W/p" --added-file "$W/a") $(field tier)" "литерал со спецсимволами «${pair%%|*}» → R2"
done
# shellcheck disable=SC2016  # литералы «$X» — сам вход пробы
printf 'password: "$DB_PASSWORD"\nDB_PASSWORD=$FROM_VAULT_VALUE\nclientSecret: secretFromConfig(cfg)\n' > "$W/a"
assert "0 R0" "$(run --paths-file "$W/p" --added-file "$W/a") $(field tier)" "близнец: \$X в кавычках и голым, вызов функции — R0"
# shellcheck disable=SC2016  # литерал «${DB_PASSWORD}» — сам вход пробы
printf 'password: "${DB_PASSWORD}"\ntoken = os.Getenv("X")\npassword: ${DB_PASSWORD}\ntoken := req.Token\napiKey = apiKeyFromEnvironment\nToken: tokenFromHeader,\n' > "$W/a"
assert "0 R0" "$(run --paths-file "$W/p" --added-file "$W/a") $(field tier)" "близнец: ссылка на переменную и выражение кода — R0"
printf -- '-----BEGIN RSA %s KEY-----\n' PRIVATE > "$W/a"
assert "0 R2" "$(run --paths-file "$W/p" --added-file "$W/a") $(field tier)" "закрытый ключ в добавленных строках → R2"

echo "== роли не больше трёх, по словарю"
paths services/iam/internal/authz/a.go services/vpc/internal/migrations/1.sql proto/x/v1/a.proto services/vpc/internal/outbox/o.go
run --paths-file "$W/p" > /dev/null
assert "security-auditor,db-architect-reviewer,proto-api-reviewer" "$(field roles)" "четыре признака → три роли в порядке словаря"

echo "== объявленный уровень: повысить можно, понизить нельзя"
paths services/vpc/internal/apps/net/usecase.go
assert "1" "$(run --declared R0 --paths-file "$W/p")" "объявлен R0 при вычисленном R1 → находка"
assert "да" "$(grep -q 'REASON TIER-UNDERSTATED объявлен R0, вычислен R1' "$W/err" && echo да || echo нет)" "причина названа кодом и обоими уровнями"
assert "0 R2 R1" "$(run --declared R2 --paths-file "$W/p") $(field tier) $(field computed)" "близнец: объявлен R2 — уровень повышен, вычисленный виден"
assert "2" "$(run --declared R9 --paths-file "$W/p")" "объявление вне словаря — вердикта нет"

echo "== пустой вход — не R0"
: > "$W/p"
assert "2" "$(run --paths-file "$W/p")" "путей ноль → код 2"
assert "2" "$(run --paths-file "$W")" "каталог вместо файла → код 2"

echo "== режим git: настоящий репозиторий"
R="$W/repo"
# shellcheck source=lib/sandbox-git-home.sh
. "$HERE/lib/sandbox-git-home.sh"
sandbox_git_home "$W/home" || exit 2
git() { sandbox_git "$@"; }
git init -q -b main "$R"
echo a > "$R/README.md"; git -C "$R" add . && git -C "$R" commit -qm base
git -C "$R" checkout -qb lane
mkdir -p "$R/services/vpc/internal/migrations"; echo 'ALTER TABLE x ADD c int NOT NULL;' > "$R/services/vpc/internal/migrations/0002.sql"
git -C "$R" add . && git -C "$R" commit -qm lane
assert "0 R2" "$(run "$R" main lane) $(field tier)" "дифф с миграцией → R2"
git -C "$R" checkout -q main && git -C "$R" checkout -qb docs && echo b >> "$R/README.md" && git -C "$R" commit -qam d
assert "0 R0" "$(run "$R" main docs) $(field tier)" "близнец: дифф документа → R0"
assert "2" "$(run "$R" main нет-такой)" "ревизия не разрешается → код 2"

echo "== json повторяет текстовый вывод"
paths services/vpc/internal/migrations/1.sql proto/x/v1/a.proto
run --paths-file "$W/p" > /dev/null; txt="$(field tier) $(field steps) $(field roles)"
bash "$T" --json --paths-file "$W/p" 2> /dev/null | tail -1 > "$W/j"
js="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["tier"], ",".join(d["steps"]), ",".join(d["roles"]))' "$W/j" 2>&1)"
assert "$txt" "$js" "уровень, шаги и роли в json те же, что в тексте"

echo
echo "lane-tier-inject: утверждений $((pass + fail)); сошлось $pass, разошлось $fail"
[ "$fail" -eq 0 ]
