---
title: RouteTable
aliases:
  - RouteTable (vpc)
  - vpc RouteTable
category: resource
domain: vpc
id_prefix: rtb
owner_table: kacho_vpc.route_tables
owner_db: kacho_vpc
project_level: true
status: stable
verified_against: "ствол redesign/integration, сверено 2026-08-05"
related_rpc:
  - "[[rpc/vpc-routetable-service]]"
related_packages:
  - "[[packages/vpc-apps-kacho-api-routetable]]"
tags:
  - resource
  - kacho-vpc
  - routetable
---

# RouteTable

**Домен**: vpc · **владелец**: сервис `kacho-vpc` (`services/vpc/`)
**ID prefix**: `rtb` (`ids.PrefixRouteTable`) — **не** `enp`
**Owner table**: `kacho_vpc.route_tables`
**Scope**: project; сеть — через `network_id`

**Контракт**: `proto/kacho/cloud/vpc/v1/route_table.proto`
**Схема**: `services/vpc/internal/migrations/0001_initial.sql` + 0017, 0019

## Поля (`message RouteTable`)

| Поле | Тип | Заметка |
|---|---|---|
| `id` | string | `rtb<17>` |
| `project_id` | string | ссылка → **iam** `Project` |
| `created_at` | Timestamp | |
| `name`, `description`, `labels` | | |
| `network_id` | string | FK → `networks(id)` (без CASCADE) |
| `static_routes` | repeated `StaticRoute` | колонка `static_routes jsonb DEFAULT '[]'` |

`StaticRoute`: `oneof destination { destination_prefix }`,
`oneof next_hop { next_hop_address | gateway_id }`, `labels`.
Обе группы — `oneof`, то есть назначение и следующий переход выражаются ровно одним
способом каждый; «и адрес, и шлюз» непредставимо by construction.

## Выбор RouteTable для подсети — ОДИН механизм, а не два

Сегодня цепочка такая: `Network.Create` безусловно провижнит системную таблицу маршрутов
и пишет её id в `networks.default_route_table_id` (миграция 0017), а `Subnet.Create`
подставляет этот id в `subnets.route_table_id`. Тенант может переопределить через
`Subnet.Update`.

> [!note] История: два конкурирующих триггера сняты (0017 → 0019)
> В baseline жили **два** DB-триггера выбора: `subnet_auto_pick_rt` (BEFORE INSERT ON
> subnets — «самая ранняя RT сети») и парный `rt_auto_assoc_subnets` (AFTER INSERT ON
> route_tables — «усыновить все подсети сети с `route_table_id IS NULL»`). 0017 снял
> первый, 0019 — второй.
>
> Второй сохраняли как «безобидный backstop», и разбор в самой миграции показывает, почему
> это было неверно: на всех путях после VPC-1 он строго no-op (подсети без RT просто не
> рождаются), а единственный достижимый путь, где он **срабатывал**, — деградация:
> `RouteTable.Delete` по `ON DELETE SET NULL` обнуляет и привязку подсетей, и
> `networks.default_route_table_id`, после чего следующий `RouteTable.Create` молча
> переклеивал бы осиротевшие подсети на себя при пустом объявленном дефолте сети. Ровно тот
> класс, который правила запрещают: два механизма об одном предмете, из которых верен один.

## FK-контракт

- `route_tables.network_id → networks(id)` — без CASCADE
- `subnets.route_table_id → route_tables(id) ON DELETE SET NULL` — удаление таблицы
  обнуляет привязку подсетей (и дефолт сети, см. выше)

## Мутации маршрутов — ЗАМЕНА НАБОРА через общий `Update`

Поэлементных глаголов у маршрутов **нет**: набор правится маской `static_routes` у общего
`Update` и приходит **итогом целиком**. Причина — у `StaticRoute` нет собственной
идентичности, адресовать элемент нечем; это решение, а не упущение
(PRO-Robotech/kacho#499, коммит `7675925f`).

> [!warning] Здесь стояло обратное — три отдельных глагола и «через `Update` набор не
> меняется». На дереве этого нет (перемерено `origin/main` @ `007e3e99`, 2026-08-18)
> `RouteTableService` несёт ровно шесть RPC — `Get`, `List`, `Create`, `Update`, `Delete`,
> `ListOperations`; ни `AddRoutes`, ни `RemoveRoutes`, ни `UpdateRoute` в контракте нет.
> Зеркально: `static_routes` **стоит** в наборе изменяемых полей маски
> (`services/vpc/internal/apps/kacho/api/routetable/update.go`), то есть общий `Update`
> набор маршрутов как раз и меняет.
>
> Записка утверждала ровно противоположное действительности по обоим пунктам сразу и
> отправляла читателя за глаголами, которых нет. Осадок снятия ещё виден в дереве: три
> осиротевших сообщения запроса (`AddRouteTableRoutesRequest` и соседние) на `main`
> остались и снимаются PR PRO-Robotech/kacho#598 (открыт), а комментарий переписи гейта
> края всё ещё называет kebab-case пути этих глаголов.

## Gotcha

- **Замена набора теряет параллельную правку, и рычага у вызывающего нет.** Два
  вызывающих, правящих разные маршруты с общего снимка, оба получают успех, и один
  маршрут исчезает. Внутри транзакции строка берётся под блокировку, но защищено этим
  только слияние **внутри** транзакции, а не основание, на котором вызывающий построил
  свой набор. Поля `resource_version` контракт таблицы маршрутов **не несёт** — предъявить
  версию нечем, и потерю нельзя ни предотвратить, ни заметить. Предмет —
  PRO-Robotech/kacho#584, трейл [[../KAC/issue-584]]; радиус класса по дереву — **два**
  поля, второе `Role.rules` ([[iam-role]], там рычаг есть, но необязателен).
- `static_routes[].gateway_id` — within-service ссылка на [[vpc-gateway]] в той же БД;
  валидируется на мутации.
- `RouteTableService.Move` не существует ([[KAC-266]]).

## См. также

[[vpc-network]] · [[vpc-subnet]] · [[vpc-gateway]] · [[../rpc/vpc-routetable-service]]

#resource #vpc #routetable
