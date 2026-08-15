---
title: SecurityGroup
aliases:
  - SecurityGroup (vpc)
  - vpc SecurityGroup
  - SG
category: resource
domain: vpc
id_prefix: sgr
owner_table: kacho_vpc.security_groups
owner_db: kacho_vpc
project_level: true
status: stable
verified_against: "ствол redesign/integration, сверено 2026-08-05"
related_rpc:
  - "[[rpc/vpc-securitygroup-service]]"
related_packages:
  - "[[packages/vpc-apps-kacho-api-securitygroup]]"
tags:
  - resource
  - kacho-vpc
  - securitygroup
---

# SecurityGroup

**Домен**: vpc · **владелец**: сервис `kacho-vpc` (`services/vpc/`)
**ID prefix**: `sgr` (`ids.PrefixSecurityGroup`) — **не** `enp`
**Owner table**: `kacho_vpc.security_groups`
**Scope**: project; сеть — через `network_id`

**Контракт**: `proto/kacho/cloud/vpc/v1/security_group.proto`
**Схема**: `services/vpc/internal/migrations/0001_initial.sql` + 0003 (снят `status`), 0005, 0027 (домен правил)

## Поля публичной проекции (`message SecurityGroup`)

| Поле | Тип | Заметка |
|---|---|---|
| `id` | string | `sgr<17>`; immutable |
| `project_id` | string | ссылка → **iam** `Project` |
| `created_at` | Timestamp | |
| `name`, `description`, `labels` | | |
| `network_id` | string | FK → `networks(id) ON DELETE RESTRICT`; **required + immutable** |
| `rules` | repeated `SecurityGroupRule` | правила группы |
| `default_for_network` | bool | группа назначена сети дефолтной |
| `used_by` | repeated `reference.Reference` | output-only, **derived-on-read**: NIC, у которого этот SG в `security_group_ids`, и Network, у которой он `default_security_group_id`. **Не** «правило другой SG ссылается сюда» |

### `SecurityGroupRule`

`id` (генерируется сервером), `description`, `labels`, `direction` (`INGRESS`/`EGRESS`,
required), `ports` (`PortRange{from_port,to_port}` в 0..65535), `protocol_name`,
`protocol_number`, и **oneof `target`** с опцией `exactly_one`:
`cidr_blocks` \| `security_group_id` \| `predefined_target`.

> [!note] `status` снят с контракта — и это зафиксировано резервированием
> `reserved 8; reserved "status";` в proto, `0003_drop_security_group_status.sql` в схеме
> (сняты и колонка, и CHECK). Причина, названная в самой миграции: у SG нет
> провизионинг-стадии, статус никем не наблюдался. Номер и JSON-имя зарезервированы,
> чтобы их нельзя было переиспользовать.

## Правила живут JSONB-колонкой, а домен значений — DB-CHECK'ом (0027)

Колонка `security_groups.rules jsonb NOT NULL DEFAULT '[]'`. Ограничение
`security_groups_rules_domain` вызывает функцию `kacho_vpc.kacho_sg_rules_domain_valid(rules)`
(рядом — `kacho_sg_rule_expressible`, `kacho_sg_protocol_name_valid`,
`kacho_sg_protocol_names`): невыразимое правило в таблицу не попадает — это DB-инвариант,
а не software-проверка (ban #10).

Секция Down у 0027 снимает только проверку и прямо оговаривает, что **обратного заполнения
нет**: удалённые невыразимые правила восстановить неоткуда. Полезный образец честного
отката.

## `network_id` — обязателен и неизменяем

Обязателен на Create; в известное множество маски `Update` не входит, поэтому в маске даёт
`INVALID_ARGUMENT`. Причина не косметическая: правило SG→SG осмысленно только внутри одной
сети — группы разных сетей друг друга не видят. Раз `network_id` immutable, проверка цели
правила не является TOCTOU.

## OCC через `xmin` — только на правилах

- Общий `Update` (name/description/labels/rule_specs) — без OCC.
- `UpdateRules` / `UpdateRule` — `UPDATE … WHERE xmin::text = $expected`; 0 строк ⇒
  `FailedPrecondition` (не `Aborted`).

## FK-контракт

- `security_groups.network_id → networks(id) ON DELETE RESTRICT` — сеть с живой SG не удалить
- NIC ↔ SG — многие-ко-многим через JSONB-массив `network_interfaces.security_group_ids`
  (через границу таблиц FK тут нет: массив)

## Жизненный цикл

Состояние одно (см. выше про снятый `status`). Мутации async через `Operation`.

## Gotcha

- **SG→SG-правило валидно только внутри одной сети**: цель из другой сети или
  несуществующая → `INVALID_ARGUMENT` с `BadRequest.field_violations`.
- **Дефолтная SG создаётся inline при `Network.Create`**
  (`services/vpc/internal/apps/kacho/api/network/create.go`), а привязывается к сети
  internal-ручкой `InternalNetworkService.SetDefaultSecurityGroupId` (`system_admin`).
- **`used_by` считается на чтении** и является зеркалом, а не источником истины;
  dangling-ссылку надо переживать грациозно.
- **`SecurityGroupService.Move` не существует** — снят вместе с прочими Move ([[KAC-266]]).
- REST правил: `PATCH /vpc/v1/securityGroups/{id}/rules` и
  `PATCH /vpc/v1/securityGroups/{id}/rules/{rule_id}`.

## См. также

[[vpc-network]] · [[vpc-networkinterface]] · [[../rpc/vpc-securitygroup-service]]

#resource #vpc #securitygroup
