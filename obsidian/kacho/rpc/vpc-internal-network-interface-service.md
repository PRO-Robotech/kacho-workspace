---
title: InternalNetworkInterfaceService (vpc)
aliases:
  - InternalNetworkInterfaceService (vpc)
  - Internal NIS
proto_file: proto/kacho/cloud/vpc/v1/network_interface_service.proto
category: rpc
backend: kacho-vpc
backend_port: 9091
visibility: internal
domain: vpc
status: stable
related_resource: "[[resources/vpc-networkinterface]]"
methods_count: 3
async_methods: 0
tags:
  - rpc
  - kacho-vpc
  - internal
  - stable
---

# InternalNetworkInterfaceService (vpc) — :9091

Координация привязки NIC↔Instance на стороне владельца. Инициатор — compute; vpc
валидирует **свои** строки и **никогда не зовёт compute обратно** (ацикличность).

| Метод | Тип | Авторизация |
|---|---|---|
| `Attach` | sync | `editor` @ `vpc_network_interface:<id>` (per-RPC Check) |
| `Detach` | sync | `editor` @ `vpc_network_interface:<id>` (per-RPC Check) |
| `ListByInstance` | sync | **на уровне данных**, per-object (см. ниже) |

`Attach` — атомарный CAS на `used_by_id` с проверкой когерентности размещения
(зона NIC = зона инстанса; REGIONAL/anycast-подсеть из зональной полосы исключена
by construction). Контракт-тексты отказов — в `services/nicinternal/service.go`.

## ListByInstance — почему авторизация не per-RPC

Единого объекта, про который можно спросить заранее, у него нет: инстансы называет
**вызывающий**, а ответ касается интерфейсов, у каждого из которых свой владелец.

Прежде метод спрашивал `viewer` на singleton `cluster` — отношение **глобального
справочника** (регионы, зоны, типы дисков), которое бутстрап намеренно открывает
`user:*`. То есть проверка пропускала **любого аутентифицированного субъекта**, хотя
ответ метода справочными данными не является. Самодельный админ-гейт перед листенером
этого не ловил: он классифицировал по **уровню** отношения, а не по предмету ответа.
Класс — [[../../../.claude/rules/security.md|отношение, выполнимое
подстановкой, не сужает ничего]].

Сейчас: страница читается курсором из своей БД, затем модель спрашивается про
идентификаторы **этой** страницы (`viewer ∪ v_list` на `vpc_network_interface:<id>`,
батчами). Метод помечен `ScopeFiltered` в `check.PermissionMap` и попадает в
`ScopeFilteredRPCs()`, поэтому production boot-guard отказывается стартовать без
работающего фильтра. Пустой субъект отсекается **безусловно** (не «когда фильтр
подключён» — за этим RPC нет per-RPC Check, на который можно откатиться); ошибка
фильтра — fail-closed.

Тот же дефект и то же лечение — у парного внутреннего метода блочного хранения,
перечисляющего привязки томов.

> [!note] История записи
> До 2026-07-28 эта заметка объявляла сервис удалённым (`methods_count: 0`,
> tombstone «удалён в KAC-36/79/80»). Сервис всё это время был жив и обслуживал
> три метода — заметка описывала отменённый замысел internal-проекции
> data-plane, а не то, что было в коде.

## See also

[[vpc-networkinterface-service]] [[../resources/vpc-networkinterface]]

#rpc #kacho-vpc #internal #stable
