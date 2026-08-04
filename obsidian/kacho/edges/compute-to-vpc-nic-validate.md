---
title: "compute → vpc: NIC attach/detach + subnet placement (живое ребро)"
aliases:
  - compute to vpc NIC validate
  - compute nic attach
category: edge
caller_repo: kacho-compute
callee_repo: kacho-vpc
sync_async: sync
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[KAC/KAC-94]]"
  - "[[KAC/KAC-266]]"
tags:
  - edge
  - cross-service
  - kacho-compute
  - kacho-vpc
  - ni
---

> [!warning] Записка объявляла ребро РАЗОРВАННЫМ — оно живое (сверено с деревом 2026-08-05)
> Прежняя редакция говорила: «compute больше не создаёт и не привязывает NIC», статус
> `deprecated`, а всё описание — «historical для archeology». В дереве продукта
> (`96b2879a`, вровень со стволом `redesign/integration` 50e5e624) привязка **есть и
> исполняется**: `services/compute/internal/clients/vpc_nic_client.go` держит
> `Attach`/`Detach`/`ListByInstance` поверх `vpc.v1.InternalNetworkInterfaceService`,
> use-case — `internal/apps/kacho/api/instance/instance_nic.go`.
>
> Это самый дорогой вид расхождения из тех, что тут бывают: по мёртвой записке о живом
> ребре проектируют так, будто ребра нет, — и заводят второе. Верно в прежней редакции
> осталось одно: **старый** способ привязки (авто-создание NIC внутри `Instance.Create`
> и публичные `AttachToInstance`/`DetachFromInstance`) снят и не вернулся; сегодняшняя
> привязка — **отдельные RPC compute** поверх **внутреннего** сервиса vpc.

# compute → vpc: NIC attach/detach + резолв placement подсети

**Вызывающий**: `kacho-compute`
— `internal/clients/vpc_nic_client.go` (`ports.NicClient`) поверх
`vpc.v1.InternalNetworkInterfaceService` (**:9091**, internal-only);
— `internal/clients/vpc_subnet_client.go` (`ports.SubnetRegistry`) поверх публичного
`vpc.v1.SubnetService.Get` (**:9090**).
**Вызываемый**: `kacho-vpc` — владелец NIC и подсети.
**Транспорт**: gRPC service→service, mTLS; **два разных listener'а одного пира**.
**Синхронность**: вызовы синхронные, но идут **внутри Operation-worker'а** мутации
compute — снаружи ответ по-прежнему асинхронный (`Operation`).

## Что именно ходит по ребру

| RPC vpc | Кто зовёт в compute | Зачем |
|---|---|---|
| `InternalNetworkInterfaceService.Attach` | `InstanceService.AttachNetworkInterface` | привязать существующий NIC к инстансу (слот `index`; `index==0` → vpc выбирает первый свободный) |
| `InternalNetworkInterfaceService.Detach` | `InstanceService.DetachNetworkInterface` | снять привязку по `nic_id` **или** по номеру слота (oneof; обе ветки эквивалентны) |
| `InternalNetworkInterfaceService.ListByInstance` | `Instance.Get`/`List`, а также резолв слота при detach-by-index | read-only **зеркало** привязок + источник истины для «какой NIC в слоте N» |
| `SubnetService.Get` | request-path `Instance.Create` | placement-проекция подсети (`placement_type` → `zone_id` либо `region_id`) для зональной когерентности |

**Владелец привязки — vpc, и compute не держит своего attach-состояния.** Мутация — один
атомарный CAS по `used_by_id` на строке NIC у владельца, вместе с проверкой зональной
когерентности (REGIONAL/anycast-подсеть из зональной проверки исключена by construction).
compute форвардит **самоописывающийся** payload (`instance_id`, `instance_name`,
`instance_zone_id`, `project_id`, `index`) — поэтому **vpc не зовёт compute обратно**, и
ацикличность держится без дополнительных соглашений (проверено: ноль импортов
`computev1` в `services/vpc`).

## Что происходит при отказе

Формат отказа задан **белым списком** (`mapNicErr`, `instance_nic.go`) — не «пробросить всё
как есть»:

| Исход | Что видит вызывающий compute | Почему так |
|---|---|---|
| привязка удалась | `Operation.done`, ресурс с обновлённым зеркалом | — |
| NIC занят / зоны не совпали / состояние не то | код и текст vpc **дословно** (`FAILED_PRECONDITION`, `INVALID_ARGUMENT`, `NOT_FOUND`, `ALREADY_EXISTS`, `PERMISSION_DENIED`) | это контракт владельца, а не транспортный шум |
| vpc недоступен / дедлайн исчерпан | `UNAVAILABLE "network interface service unavailable"` | fail-closed на мутации, без утечки деталей соединения |
| vpc ответил `INTERNAL`/`UNKNOWN` | фиксированный `INTERNAL "internal error"` | не-сентинельный `Internal` пира может нести драйверные/DB-подробности |
| клиент NIC не сконфигурирован (`nil`) | `UNAVAILABLE "network interface service unavailable"` | «ребро не провязано» отвечает как «пир недоступен», а не молча пропускает мутацию |
| детач слота, в котором никого нет | `done`, no-op | идемпотентность детача — часть контракта |

**Срок годности вызова принадлежит вызову**: per-call 5 с на каждый NIC-RPC
(`defaultNicCallTimeout`) и 3 с на `SubnetService.Get` — иначе «пир жив, но не отвечает»
парковал бы worker-слот до op-timeout. Транзиентные обрывы сглаживает
`retry.OnUnavailable`; личность вызывающего проброшена (`auth.PropagateOutgoing`), поэтому
authz-гейт vpc видит **реального** инициатора, а не служебную учётку compute.

**Чтение подсети идёт под личностью вызывающего.** Подсеть, которую тенант не видит,
отвечает ему тем же, чем ответила бы несуществующая, — consumer не превращается в оракул
чужого placement'а.

**Зеркало деградирует мягко и молча — это осознано.** `Instance.Get`/`List` дополняют ответ
привязками из vpc; недоступность vpc или ошибка чтения **опускают** зеркало, а не роняют
чтение (`applyNicMirror`). То есть на чтении `UNAVAILABLE` со стороны vpc не наблюдаем —
наблюдаем инстанс без списка интерфейсов. При отладке «куда делись NIC в ответе» смотреть
надо на это ребро, а не на данные compute.

## История

- **KAC-94** — ребро заведено: compute сам создавал и привязывал NIC внутри `Instance.Create`.
- **KAC-52** — привязка защищена single-statement CAS (снята гонка второго писателя).
- **KAC-266** — прежняя форма **снята**: авто-создание NIC на `Instance.Create` убрано,
  публичные `NetworkInterfaceService.AttachToInstance`/`DetachFromInstance` удалены с
  контракта. `network_interface_specs` в `CreateInstanceRequest` перестал что-либо менять.
- **редизайн compute (COMP-\*)** — привязка вернулась **в другой форме**: отдельные RPC
  compute (`Instance.AttachNetworkInterface`/`DetachNetworkInterface`) поверх **внутреннего**
  `InternalNetworkInterfaceService` (`Attach`/`Detach`/`ListByInstance`) — то есть поверхность
  привязки стала явной и внутренней, а не побочным эффектом создания машины.
- **placement-когерентность на request-path** — `SubnetService.Get` заведён ради проверки
  «зона подсети каждого интерфейса = зона инстанса»; без резолва у владельца эта проверка
  ничем не обеспечена (`data-integrity.md` §Placement-coherence).
- **SEC-M** — транспорт обоих conn'ов переведён на клиентский mTLS; контракт RPC не менялся.

## Смежное

[[../rpc/vpc-networkinterface-service]] [[../rpc/vpc-internal-address-service]]
[[../resources/vpc-networkinterface]] [[compute-to-storage-volume-resolve]]
[[compute-to-geo-zone-validate]] [[../KAC/KAC-266]]

#edge #cross-service #kacho-compute #kacho-vpc #ni
