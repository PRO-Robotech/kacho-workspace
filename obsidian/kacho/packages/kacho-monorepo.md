---
title: kacho — монорепа
category: packages
repo: kacho
layer: root
status: stable
tags: [packages, polyrepo, dependencies, architecture, go, proto]
---

# kacho — монорепа (замещает polyrepo)

`github.com/PRO-Robotech/kacho` — **один Go-модуль** на всю платформу. Создана
2026-07-15/16. Старые `kacho-*` репозитории **не тронуты** и остаются архивом; история
в монорепу не переносилась (осознанное решение).

## Раскладка

```
proto/     .proto-исходники + buf.yaml  ← ЕДИНСТВЕННЫЙ дом .proto
pkg/api/   сгенерённые стабы (buf generate → сюда; РУКАМИ НЕ ПРАВИТЬ)
pkg/*      shared-фундамент: ids db grpcsrv grpcclient authz operations outbox …
services/  iam vpc compute geo nlb storage registry
gateway/   api-gateway
deploy/    helm/стенд/e2e
```

`proto` и `corelib` **слиты** в фундамент: в одном модуле разделение на «proto-модуль»
и «corelib-модуль» — формальность, но именно она порождала цепочку PR
proto→corelib→сервисы→gateway. Кросс-доменная фича теперь = **один атомарный PR**.

## Что монорепа вскрыла сразу (polyrepo это прятал)

Все четыре — скрытый рассинхрон версий, невозможный в едином модуле:

1. **Ни один сервис не реализовывал `operations.OwnedOperationRepo.ListOwned`** — все
   запинены на старый corelib. geo/nlb — ошибка сборки, registry — **паника** через
   `AsOwned`. → [[kacho-corelib-operations]]
2. **H-BF/corlib**: сервисы жили на `v1.2.31-dev`, `go mod tidy` разрешил `v0.0.12`
   (corelib его не требовал) → `WithKeepAlive undefined`.
3. **Локальный `kacho-proto` отставал на 2 коммита** от origin/main: код iam использует
   `name`/`labels` (#319), которых в чекауте не было → 12 ошибок сборки.
4. **licensehdr-гейт** был захардкожен на путь `proto/gen/` и при переезде протух
   МОЛЧА. Исправлен на детект по маркеру `// Code generated … DO NOT EDIT.`

## Гочи (дорого стоили — не повторять)

**Генерённое НЕЛЬЗЯ патчить текстом.** `sed` по import-путям внутри `.pb.go` бьёт
`rawDesc` (сериализованный FileDescriptorProto с длино-префиксными полями): замена
подстроки другой длины ломает дескриптор. **`go build` и `go vet` при этом ЗЕЛЁНЫЕ** —
ловится только рантайм-паникой `slice bounds out of range` при init-регистрации.
Меняешь пути → правь `.proto` + `buf generate`. CI-гейт `generate-diff` это стережёт.

**Вставка хедеров через `.tmp` убивает +x.** `printf … > "$f.tmp" && mv` создаёт файл с
umask-правами 644 → бит исполнения теряется (пострадали 27 скриптов; в CI/чистом клоне
они бы не запустились). Плюс у `.py` хедер встал ПЕРЕД shebang'ом — файл как
исполняемый мёртв. Хедер вставляй ПОСЛЕ shebang'а и сохраняй режим.

**dev-стенд мог уехать на прод.** kind-кластер существовал, контекста в kubeconfig не
было, `dev-up` шёл `; \`-цепочкой → упавший `use-context` не прерывал цель, и стенд
поехал на текущий контекст (прод). Спасла случайность. Введён `guard-kind-context`
(аварийный стоп, если контекст не `kind-*`) — сработал дважды. См. [[fe3455-production-deploy]].

**Bootstrap с нуля не проверялся.** Фаза 1 `dev-up` глушит mtls, чтобы Certificate не
рендерились до CRD cert-manager (он сабчарт того же umbrella). Список `--set` покрывал
5 из 6 — `kacho-geo` забыли. Не всплывало, потому что kind-кластер переиспользовали и
CRD уже стояли. Гейт `check-mtls-off-complete` сверяет список с `values.dev.yaml`.

## Гейты репо-гигиены (`internal/repohygiene/`)

Живут в КОРНЕ, а не внутри сервиса (licensehdr раньше сидел в `services/compute` —
рудимент polyrepo). Каждый ловит класс, невидимый компилятору/линтеру:

- **`license_test.go`** — SPDX-хедер + LICENSE. Исключение генерённого — по маркеру
  `// Code generated … DO NOT EDIT.`, а НЕ по пути (прежний хардкод `proto/gen/` протух молча).
- **`execbit_test.go`** — shebang ⇒ mode 100755 в ИНДЕКСЕ git (не на диске: в CI работает
  индекс, и расхождение диск-vs-индекс — форма бага «у меня работало»); shebang обязан быть
  ПЕРВОЙ строкой.
- **`newmanvars_test.go`** — каждая `{{var}}` коллекции имеет источник. Postman не ругается
  на неразрешённую переменную, а подставляет ЛИТЕРАЛОМ → падение выглядит багом продукта
  (`invalid resource id '{{lifeId}}'`, `ENOTFOUND {{internalbaseurl}}`). `knownGaps` требует
  ссылку на тикет (`TestKnownGapsAreTracked`), иначе карта разрастётся молча.

## Детерминизм: local == CI по построению

`tools/tools.go` (build-tag `tools`) пинит protoc-плагины через go.mod → CI ставит их БЕЗ
`@latest` и получает версию из go.mod. buf 1.69.0, golangci-lint v2.12.2, **helm v3.17.0**
запинены явно. `govulncheck` ОСТАЁТСЯ на `@latest` осознанно — ему нужна свежая база CVE.
Причина: разъезд версий заставляет гейт `generate-diff` мигать «фантомным диффом» при
нетронутых `.proto` — а незапиненный helm вообще притащил **Helm 4** и гейт «зеленел»,
проверяя чарты не той версией, что на проде. Подробности — [[kacho-ci-determinism]].

## CI

Один корневой `.github/workflows/` (GitHub читает только корень — 18 приехавших с
сервисами `.github/` были мертвы, удалены): build·vet·gofmt·test-race, buf
lint/breaking/**generate-diff**, golangci-lint, govulncheck, helm lint,
check-mtls-off-complete. `docker-build` (8 образов, context = корень) и `e2e-newman`
(kind-стенд с нуля) — на **self-hosted beget-runner**; раскладка и замеры —
[[kacho-ci-runners]].

**unit и integration РАЗДЕЛЕНЫ.** `build-test` гоняет `go test ./... -race -short` (59с,
202 пакета); отдельная джоба `integration` — testcontainers-Postgres с `-p 1`
(сериализация: под -race + Docker-contention параллельные пакеты голодают друг у друга
ресурсы и CAS/EXCLUDE-кейсы флакают). Без `-short` unit-джоба затягивала testcontainers на
КАЖДОМ из 202 пакетов → `panic: test timed out after 15m0s`, 23 минуты красного CI.
Дизайн был правильным в polyrepo (kacho-vpc/nlb) и потерян при переезде.

Пакеты для integration отбираются `go list`, а НЕ шелл-глобом: `./services/*/internal/repo/...`
не работает (bash глобит слово целиком, `...` — не каталог → паттерн уходит в go test
литералом, джоба краснеет за 18с не запустив ни одного теста).

## fe3455

С 2026-07-16 кластер держит ЕДИНЫЙ образ одного коммита монорепы для всех 7 сервисов
(`prorobotech/kacho-*:main-<sha>`) вместо 7 разных сборок из 7 репо. Рассинхрон версий,
который вскрыла миграция, на кластере теперь структурно невозможен. См. [[fe3455-production-deploy]].

> [!warning] values.*-ory.yaml несёт креды (hydra.config.dsn)
> В kacho-deploy он был gitignored; при переезде правило НЕ поехало, и в монорепе файл не
> игнорировался — любой `git add -A` закоммитил бы секреты в ПУБЛИЧНЫЙ репозиторий.
> Закрыто `**/values.*-ory.yaml` в .gitignore; в историю не попадал (проверено).

Связано: [[registry-dataplane-public-tls]], [[fe3455-production-deploy]].

#packages #polyrepo #dependencies #architecture #go #proto
