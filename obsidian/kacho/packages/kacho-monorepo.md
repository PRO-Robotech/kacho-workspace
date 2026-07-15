---
tags: [kacho/package, kacho/monorepo]
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

## CI

Один корневой `.github/workflows/` (GitHub читает только корень — 18 приехавших с
сервисами `.github/` были мертвы, удалены): build·vet·gofmt·test-race, buf
lint/breaking/**generate-diff**, golangci-lint, govulncheck, helm lint,
check-mtls-off-complete. `docker-build` — матрица на 8 образов, context = корень.

Связано: [[registry-dataplane-public-tls]], [[fe3455-production-deploy]].
