---
title: kacho-api-gateway (сегодня — каталог gateway/ монорепо)
aliases:
  - kacho-apigw
  - kacho-api-gateway
category: repo
repo: kacho-api-gateway
service_type: edge
status: legacy
tags:
  - kacho
  - kacho-apigw
  - grpc
  - rest
  - edge
  - legacy
---

# kacho-api-gateway — сегодня это `gateway/` в монорепо

> [!warning] Предмет записки — отдельный репозиторий — существует, но разработка в нём не ведётся
> Край живёт в **`gateway/`** монорепо `PRO-Robotech/kacho`. Записка сохранена как точка
> перехода для входящих ссылок (их 3). Прежняя редакция описывала край **пятимесячной
> давности** и по существу расходилась с деревом почти в каждом пункте — расхождения
> выписаны ниже, потому что тихая правка имён превратила бы устаревшую запись в уверенно
> неверную.

## Где это сегодня

| Тогда | Сегодня |
|---|---|
| репозиторий `github.com/PRO-Robotech/kacho-api-gateway` | каталог `gateway/` монорепо |
| зависимости `kacho-proto` + `kacho-corelib` пинами | `proto/` → `pkg/` → `gateway/` в одном модуле |

## Что стоит знать про край сегодня (замер `kacho@96b2879a`)

**Три листенера, а не два.** `KACHO_API_GATEWAY_LISTEN_ADDR` (по умолчанию `:8080`),
`KACHO_API_GATEWAY_TLS_LISTEN_ADDR` (пусто ⇒ TLS не поднимается) и отдельный
`KACHO_API_GATEWAY_INTERNAL_REST_ADDR` (по умолчанию `:8081`) — **единственный**,
обёрнутый признаком internal-происхождения. Прежняя редакция знала два и объясняла
разделение совместимостью с CLI **чужого облака** — такое обоснование запрещено (запрет #2)
и, кроме того, неверно: разделение существует ради того, чтобы `Internal.*` не попадали
на внешнюю поверхность (запрет #6).

**Бэкендов семь, а не три.** В конфигурации края объявлены пары «публичный :9090 /
внутренний :9091» для `vpc`, `compute`, `iam`, `nlb`, `geo` и далее по составу сервисов —
прежний перечень `vpc/compute/iam` описывает состояние до появления geo, storage, registry
и nlb-редизайна.

**`auth_noop.go` («placeholder AAA, always allow») в дереве НЕТ.** На его месте — слой
проверок из трёх десятков файлов: проверка JWT и JWKS, привязка к mTLS, DPoP с защитой от
повтора, сессии, step-up, отзыв, per-RPC authz с кэшем вердиктов и каталогом прав,
публичный allowlist, ограничение тела запроса, идемпотентность. Утверждение «AAA — заглушка,
пропускает всё» — самое опасное из устаревших здесь: оно описывает край как незащищённый,
тогда как режим «неаутентифицированный запрос получает полный доступ» **упразднён**
(`.claude/rules/security.md`).

**Отображение gRPC-кода в HTTP-статус край НЕ переопределяет** — `runtime.NewServeMux`
собирается без своего обработчика ошибок, статус выбирает grpc-gateway. Таблица кодов —
`.claude/rules/api-conventions.md` §«gRPC-код → HTTP-статус»; здесь не дублируется.

**Маршрут `/compute/v1/regions` больше не существует** — Geography вынесена в `geo`
(эпик #82), админ-CRUD Region/Zone живёт на `InternalRegionService`/`InternalZoneService`
сервиса geo, а публичное чтение Region/Zone — задокументированное исключение из
project-scope authz (authN при этом обязателен).

**Маршрутизация `OperationService.Get` по первым трём символам id** — верна только для
legacy-формы. Действующий канон id — дефисная форма `<prefix>-<crockford-base32>`, где
prefix бывает длиннее трёх символов; классификация обеих форм аддитивна.

## Что осталось верным

- край — stateless gRPC-proxy + REST-mux поверх `grpc-gateway`, с suffix-действиями `:verb`;
- `Internal.*` регистрируются **только** на cluster-internal поверхности, не на внешней;
- `/vpc/v1/addressPools*` — админский ресурс vpc на внутреннем порту;
- снятое в KAC-266 (`:explainResolution`, `:check`, `poolSelector`, `addressPoolOverride`)
  снято и сегодня — см. [[../KAC/KAC-266]];
- за регистрацию нового публичного RPC отвечает агент `api-gateway-registrar`.

Соседний `packages.md` **удалён**: входящих ссылок ноль, а перечень пакетов края разошёлся
с деревом; per-package записки живут в категории `packages/`.

## См. также

- [[../README|vault hub]] · [[../architecture|архитектура]]
- `.claude/rules/security.md` — Internal-vs-external, authN+authZ на каждом листенере
- `.claude/rules/api-conventions.md` — REST-пути, коды ошибок, пагинация

#kacho #kacho-apigw #grpc #rest #edge #legacy
