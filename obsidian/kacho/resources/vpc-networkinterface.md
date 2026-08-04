---
title: NetworkInterface
aliases:
  - NetworkInterface (vpc)
  - NIC
  - vpc NetworkInterface
category: resource
domain: vpc
id_prefix: nic
owner_table: kacho_vpc.network_interfaces
owner_db: kacho_vpc
project_level: true
status: stable
verified_against: "ствол redesign/integration, сверено 2026-08-05"
related_rpc:
  - "[[rpc/vpc-networkinterface-service]]"
  - "[[rpc/vpc-internal-network-interface-service]]"
related_packages:
  - "[[packages/vpc-apps-kacho-api-networkinterface]]"
related_edges:
  - "[[edges/compute-to-vpc-nic-validate]]"
related_tickets:
  - "[[KAC/KAC-94]]"
tags:
  - resource
  - kacho-vpc
  - ni
---

# NetworkInterface (NIC)

**Домен**: vpc · **владелец**: сервис `kacho-vpc` (`services/vpc/`)
**ID prefix**: `nic` (`ids.PrefixNetworkInterface`) — **не** `enp`: `enp` это op-root vpc
**Owner table**: `kacho_vpc.network_interfaces`
**Scope**: project

**Контракт**: `proto/kacho/cloud/vpc/v1/network_interface.proto`
**Схема**: `services/vpc/internal/migrations/0001_initial.sql` + 0014 (attach-слот)

NIC — **first-class** ресурс: владелец vpc, потребитель compute. Отдельно от Instance,
со своим CRUD и своим жизненным циклом.

## Поля публичной проекции (`message NetworkInterface`)

| Поле | Тип | Заметка |
|---|---|---|
| `id` | string | `nic<17>`; immutable |
| `project_id` | string | ссылка → **iam** `Project` |
| `created_at` | Timestamp | |
| `name`, `description`, `labels` | | |
| `subnet_id` | string | FK → `subnets(id) ON DELETE RESTRICT`; **отсюда наследуется зона** |
| `v4_address_ids` | repeated string | ссылки на [[vpc-address]], не «сырые» IP |
| `v6_address_ids` | repeated string | то же |
| `security_group_ids` | repeated string | дефолт — `default_security_group_id` сети |
| `used_by` | `reference.Reference` | output-only: кто держит NIC |
| `mac_address` | string | output-only, задаётся на Create, cloud-wide UNIQUE, prefix `0e:` |
| `status` | enum `Status` | `PROVISIONING` \| `ACTIVE` \| `AVAILABLE` \| `FAILED` \| `DELETING` |

> [!warning] Что снято с контракта: `reserved 8, 9, 11, 12, 14, 15`
> Прежние `network_id`(8), `primary_v4_address`(9), `instance_id`(11), `index`(12),
> `secondary_v4_addresses`(14), `v6_addresses`(15). Причины названы в самом proto:
> `network_id` **выводится из подсети** и потому не хранится; `instance_id`/`index` ушли
> в `used_by` и на compute-сторону; сырые IP заменены **ссылками** на Address-ресурсы.
> Записка, называющая `network_id` или `primary_v4_address` полем NIC, пережила свой
> предмет.

## Таблица (по DDL)

```
id, project_id, created_at, name, description, labels,
subnet_id            REFERENCES subnets(id) ON DELETE RESTRICT,
security_group_ids   jsonb DEFAULT '[]',
v4_address_ids       jsonb DEFAULT '[]',    -- CHECK jsonb_array_length <= 1
v6_address_ids       jsonb DEFAULT '[]',    -- CHECK jsonb_array_length <= 1
status               text DEFAULT 'AVAILABLE',
mac_address          text  CHECK ~ '^[0-9a-f]{2}(:[0-9a-f]{2}){5}$',
used_by_type, used_by_id, used_by_name  text DEFAULT '',
used_by_index        integer            -- миграция 0014
```

Имена колонок привязки — `used_by_type` / `used_by_id` / `used_by_name`
(**не** `used_by_kind`).

## Слот привязки к инстансу (миграция 0014)

`used_by_index` — device-индекс на инстансе (eth0 = 0, …). Уникальность слота выражена
**partial UNIQUE**, а не глобальной:

```sql
CREATE UNIQUE INDEX ni_used_by_index_uniq
    ON kacho_vpc.network_interfaces (used_by_id, used_by_index)
    WHERE used_by_id <> '';
```

Ключ — пара `(used_by_id, used_by_index)`. Глобальный `UNIQUE(used_by_id)` здесь **ложен**:
у инстанса законно несколько NIC. Свободные интерфейсы (`used_by_id = ''`) из уникальности
исключены предикатом и «пустым слотом» не конфликтуют.

## Attach/Detach — ЖИВЫ, но на internal-листенере

> [!important] Это правка утверждения, пережившего свой предмет
> Прежняя редакция объявляла: «attach/detach RPC удалены, `DETACHED` — единственное штатное
> состояние». Публичные `AttachToInstance` / `DetachFromInstance` действительно сняты
> ([[KAC-266]]) — но привязка **вернулась** на cluster-internal :9091 как
> `InternalNetworkInterfaceService.Attach` / `.Detach` / `.ListByInstance`
> (`proto/kacho/cloud/vpc/v1/internal_network_interface_service.proto`, провязано в
> `services/vpc/internal/handler/internal_network_interface_handler.go` и в карте прав
> сервиса). Значит ATTACHED — достижимое штатное состояние, а не археология.

Свойства этого пути (по комментарию контракта и карте прав):

- **Self-describing payload**: инициатор (compute) присылает всё нужное, а vpc валидирует
  **свои** строки (`network_interfaces` + `subnets`): свободно-или-наше, тот же проект,
  зональная когерентность с исключением REGIONAL/anycast-подсети.
- **kacho-vpc НИКОГДА не зовёт compute обратно** — иначе завёлся бы цикл vpc↔compute.
- **Синхронны** (CAS мгновенный); тенант-facing мутация остаётся async через `Operation`
  на стороне compute, поэтому ban #9 не нарушен.
- Авторизация per-RPC с object-scoped extractor по `nic_id`; `ListByInstance` —
  `scope_filtered` (вызывающий называет инстансы, а у вернувшихся интерфейсов владельцы
  свои, единого объекта для одного вопроса нет).

Форма CAS (та же, что у любой смены владения в Kachō):

```sql
UPDATE network_interfaces
   SET used_by_id = $instance, used_by_type = 'compute_instance', used_by_index = $slot
 WHERE id = $nic_id
   AND (used_by_id = '' OR used_by_id = $instance)
RETURNING …;
```

0 строк ⇒ `FailedPrecondition`. Single-statement UPDATE на одной строке защищён row-lock'ом
(ban #10: никакого «прочитал → проверил → записал»).

## FK-контракт

- `network_interfaces.subnet_id → subnets(id) ON DELETE RESTRICT` — удалить подсеть с NIC нельзя
- CHECK на кардинальность адресов: не более одного v4 и одного v6 на интерфейс

## Жизненный цикл

`AVAILABLE` (свободен) → `ACTIVE` (привязан) → `AVAILABLE` (отвязан) → `DELETING`.
`Delete` под непустым `used_by_id` → `FailedPrecondition`.

## Gotcha

- **Зону NIC не несёт** — берёт из `subnet_id`; зональную когерентность с инстансом
  проверяет vpc в момент Attach.
- **Адреса — ссылки, а не строки.** Чтобы узнать IP, надо пройти по `v4_address_ids` в
  [[vpc-address]]. Единая ресурсная модель: каждый IP — ресурс.
- **MAC клиент задать не может**; он стабилен всю жизнь NIC и Attach/Detach его не меняют.

> [!note] История: kube-ovn-эпоха
> Data-plane-поля (`hv_id`, `sid`, `host_iface`, `netns`, `container_id`,
> `dataplane_revision`, …) удалены до свёртки миграций. В baseline их уже нет; здесь они
> названы как история, а не как поля.

## См. также

[[vpc-subnet]] · [[vpc-address]] · [[vpc-securitygroup]] · [[compute-instance]] · [[../rpc/vpc-networkinterface-service]] · [[../rpc/vpc-internal-network-interface-service]] · [[../edges/compute-to-vpc-nic-validate]]

#resource #vpc #ni
