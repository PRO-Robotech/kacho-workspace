---
title: api-gateway public cmux vs internal-rest
category: edge
caller_repo: kacho-api-gateway
callee_repo: kacho-vpc
sync_async: sync
protocol: REST
status: stable
tags: [edge, kacho-api-gateway, kacho-vpc, internal, handler]
---

# api-gateway: публичный cmux vs internal-rest — куда идут Internal*-пути

Как на самом деле разложены REST-поверхности gateway и почему тесты обязаны это учитывать.

## Два листенера

| листенер | порт | что отдаёт |
|---|---|---|
| публичный cmux | `:8080` (Service `cmux`) | публичные RPC. **Internal\*-REST → 404 by design** (ban #6) |
| `internal-rest` | `:8081` (Service `internal-rest`) | Internal\*-REST (admin-UI, port-forward, cluster-tooling) |

Ingress **обязан** таргетить только публичный. Оба обслуживают ОДИН `restHandler`
(`restmux.NewMux`) — разделение делает `HasInternalSuffix`-роутер прокси, а не отдельные муксы.

Internal-ресурсы vpc: **`AddressPool`** (`/vpc/v1/addressPools*`, включая
`/vpc/v1/networks/{id}/addressPoolBinding` — объявлен в `internal_address_pool_service.proto`),
`InternalNetwork`. Внимание на формулировку доки mux.go: «обслуживаются internal-портом vpc
backend (9091)» — это про **backend**, а не про то, что REST-путь публичный.

## Гоча: порядок authz → routing (ловушка ложно-зелёного теста)

На ПУБЛИЧНОМ порту запрос к Internal\*-пути даёт **разный** ответ в зависимости от субъекта:

- **не-админ** → `403 permission denied` — authz-middleware отвергает **ДО** маршрутизации
  (по permission-catalog, по имени метода), 404-роутер не достигается;
- **ANON** → `401`;
- **админ** (`system_admin`) → authz проходит → упирается в **404** internal-suffix-роутера.

Отсюда два следствия для newman:

1. **Админские Internal-операции обязаны идти на `{{internalBaseUrl}}`** (:18081). На
   `{{baseUrl}}` они получают 404 — и тест ловит не баг продукта, а свою неверную посылку
   («expected 404 to deeply equal 200»).
2. **`authz-deny` на `{{baseUrl}}` — КОРРЕКТЕН и трогать его нельзя.** Он проверяет ровно
   то, что публичный порт отказывает не-админам (403/401 от middleware). Его
   `addresspool-admin-only` ждёт DENY у всех 6 субъектов — ни одного ALLOW, поэтому до
   404-ветки он не доходит и зелен по ПРАВИЛЬНОЙ причине.

Т.е. один и тот же путь на одном порту легитимно тестируется двумя наборами с разными
ожиданиями. Не «унифицировать», не разобравшись.

## Как это выражено в наборах

- **iam**: `_internal_url_override(path)` в `iam-internal-only-check.py` — подменяет
  `pm.request.url` на `internalBaseUrl+path`, при пустой переменной скипает шаг.
- **vpc**: флаг `Step.internal=True` в `scripts/gen.py` → генератор подставляет
  `{{internalBaseUrl}}` вместо `{{baseUrl}}`. Помечены 89 шагов `internal-pool` + 6 `address`
  + setup-хелпер `_pool_seed_item` (он сеял пул через публичный URL и молча получал 404,
  роняя все зависящие кейсы). `authz-deny` — намеренно НЕ помечен.
- Харнесс (`deploy/scripts/newman-e2e.sh`) форвардит оба порта и передаёт `baseUrl` +
  `internalBaseUrl`.

История: до 2026-07-16 vpc-набор про `internalBaseUrl` не знал вообще (в отличие от iam) →
`internal-pool` падал 48/63. Пробел был pre-existing, вскрыт при переезде в [[kacho-monorepo]].

## Гоча харнесса: одиночный прогон ≠ полный

`internal-pool` давал **78/0** при `COLLECTION=internal-pool`, но **62/56** в полном наборе.
Причина не в тестах: `newman-e2e.sh` в одиночной ветке передаёт `--env-var internalBaseUrl=…`
напрямую, а полная ветка идёт через `scripts/run.sh`, который **значения из окружения НЕ
читает** — он берёт их только из env-файла, а всё неизвестное в argv пробрасывает в newman
(массив `EXTRA`). Поэтому `INTERNAL_BASE_URL=… ./scripts/run.sh` молча ничего не давал:
`{{internalBaseUrl}}` оставался пустым и запрос уходил на литерал —
`getaddrinfo ENOTFOUND {{internalbaseurl}}`, а следом сыпался каскад неразрешённых
`{{lifeId}}`/`{{addrIdIdm}}` («invalid resource id '{{…}}'» → 400 вместо 404).

Вывод: переменные в полный набор передавать **через argv** (`--env-var k=v` → попадает в
`EXTRA`), а не через env. И проверять фикс ИМЕННО полным прогоном — одиночный зелёный ничего
не доказывает.

Связано: [[kacho-monorepo]], `security.md` §Internal-vs-external (ban #6).

#edge #kacho-api-gateway #kacho-vpc #internal #handler
