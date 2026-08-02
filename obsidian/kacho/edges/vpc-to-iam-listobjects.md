---
title: "vpc → iam: сужение страницы списка пакетной проверкой"
aliases:
  - vpc listobjects
  - vpc fga listobjects
  - vpc batchcheck
category: edge
caller_repo: kacho-vpc
callee_repo: kacho-iam
sync_async: sync
protocol: gRPC
status: active
related_tickets:
  - "[[KAC-127]]"
  - "[[rbac-rules-model-2026-subphase-D-consumer-vpc]]"
tags:
  - edge
  - kacho-vpc
  - cross-service
  - authz
  - fga
---

# vpc → iam: сужение страницы списка пакетной проверкой

> [!info] Имя файла — координата, а не описание
> Файл называется `…-listobjects`, потому что на него ссылаются десятки записок, а
> ссылка обязана пережить смену механизма. Само ребро перечислением больше не
> пользуется: имя стабильно, заголовок говорит правду. То же правило, что ban #15
> для ресурсов — адресуемся по неизменной координате, а не по мутабельной метке.

**Caller**: `kacho-vpc` — 21 списочный метод в 8 ресурсах (`network`, `subnet`,
`security_group`, `route_table`, `address`, `gateway`, `network_interface`,
`address_pool`), плюс 1 на внутреннем слушателе. Из них 2 объявлены
cluster-scoped (`addresspool.List`, `addresspool.ListAddresses`) — админский
ресурс, не тенантский.
**Callee**: `kacho-iam` `AuthorizeService.BatchCheck` ([[../rpc/iam-authorize-service]]).
**Protocol**: gRPC, sync, per-request.
**Реализация**: `services/vpc/internal/authzfilter/` (порт `UseCasePort`,
`FilterVisibleIDs`); провязка — в композиционном корне.

## Механика

Use-case читает **страницу** строк из своей БД курсором и спрашивает iam, какие
id **этой страницы** видимы вызывающему: батчами ≤100 (контрактный предел
`BatchCheck`). Предикат видимости — `viewer ∪ v_list`: сначала батч на `viewer`,
затем `v_list` для тех, кому `viewer` отказал.

- **Стоимость пропорциональна СТРАНИЦЕ**, а не популяции типа.
- **read == enforce**: видимый набор равен Check-allow набору.
- **`Get` по id в этот порт не заходит вовсе** — единичное чтение авторизуется
  прямым per-object Check в интерсепторе, как `Update`/`Delete`.
- **Неопознанный вызывающий отсекается безусловно**, а не «когда фильтр
  подключён»: за scope-filtered `List` нет per-RPC Check, на который можно
  откатиться.
- **Ошибка резолва — fail-closed** (`UNAVAILABLE`), не пустая и не полная страница.
- **Формат страницы судится ДО прав**: `page_token`/`page_size` валидируются
  раньше, чем short-circuit по пустому гранту.

## Почему не перечисление (механизм снят)

Прежде фильтр спрашивал «перечисли ВСЕ объекты типа, которые субъекту можно», и
сужал SQL до полученного набора. У перечисления в хранилище прав **жёсткий
серверный предел и нет продолжения**: ответ — произвольный префикс, а предел
общий на тип для всего кластера, а не на тенанта. Следствие было не отказом, а
**молчаливой потерей видимости**: строка есть, грант есть, `Update`/`Delete`
работают (они задают прямой per-object вопрос), а `List` ресурс не показывает.
Просьба о большем лимите предела не поднимает — это обрезка уже усечённого ответа.

Лечится не поднятием предела (он внешний и всё равно конечен), а **формой
вопроса**. Ослабления авторизации нет: предикат тот же, запрос другой.

Имена `ListObjects`/`ListAllowedIDs` **запрещены анализатором сужения** в дереве
каждого сервиса-потребителя — запрет исполняем, а не записан абзацем.

## History

- **2026-08-02** — ребро переведено с перечисления на пакетную проверку страницы;
  записка приведена к дереву `a373c599`. Прежняя редакция описывала перечисление
  как активный механизм и приводила под него бюджет SLO.
- Sub-phase D-consumer — первая посадка per-object фильтрации (перечислением).

## See also

[[compute-to-iam-listobjects]] [[nlb-to-iam-listobjects]] [[api-gateway-to-iam-authorize]]
[[iam-to-openfga-check]] [[../rpc/iam-authorize-service]] [[../packages/corelib-authz-listobjects]]
[[../KAC/KAC-127]]

#edge #kacho-vpc #cross-service #authz #fga
