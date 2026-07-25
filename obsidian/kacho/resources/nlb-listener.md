---
title: Listener
aliases:
  - Listener (nlb)
  - nlb Listener
category: resource
domain: nlb
id_prefix: lst
owner_table: kacho_nlb.listeners
owner_db: kacho_nlb
folder_level: true
status: stable
related_rpc:
  - "[[rpc/nlb-listener-service]]"
related_packages:
  - "[[packages/nlb-domain]]"
  - "[[packages/nlb-apps-kacho-api-listener]]"
tags:
  - resource
  - kacho-nlb
  - listener
---

# Listener (nlb)

**Domain**: nlb
**ID prefix**: `lst`
**Owner table**: `kacho_nlb.listeners`
**Folder-level**: yes (через LB → Project)

## Fields (domain)

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `ids.IsValid("lst")` | |
| `load_balancer_id` | TEXT NOT NULL | within-service FK → load_balancers(id) RESTRICT | **immutable** |
| `project_id` | TEXT | denorm from LB — берётся locking-read'ом строки LB, не software-snapshot'ом | keyset + authz-scope |
| `region_id` | TEXT | denorm from LB | на wire **нет** (proto `reserved 4`) |
| `name` | TEXT | DNS-1123 regex | partial UNIQUE per LB |
| `protocol` | TEXT | `TCP` \| `UDP` | **immutable** |
| `port`, `target_port` | INT | `1..65535` | `port` **immutable** |
| `proxy_protocol_v2` | BOOL | default `false` | mutable |
| `default_target_group_id` | TEXT | within-service FK (0018/0023 — composite `(target_group, project)`) | mutable; на wire дублируется как `target_group_id` |
| `status` | TEXT | `CREATING/ACTIVE/UPDATING/DELETING` | enum CHECK |
| `ip_version`, `address_id`, `allocated_address`, `subnet_id`, `vip_origin` | TEXT | — | **vestigial**: колонки живы, прод-код их не пишет; с proto сняты (`reserved 12-15`) |

Derived output-only (не персистятся): `resolved_backend_port°` (эхо `TargetGroup.port`, 0 если TG не
резолвится) и `substatus°` (`OK` ⟺ TG резолвится, иначе `MISCONFIGURED`).

## Constraints / indexes

- PK + FK `load_balancer_id` RESTRICT
- UNIQUE `(load_balancer_id, port, protocol)` (GWT-DB-006) — при одном VIP на семейство у LB это **и есть** уникальность `(VIP, port, protocol)`
- Partial UNIQUE `(load_balancer_id, name) WHERE name <> ''`
- Keyset `(project_id, created_at DESC, id)`, GIN `labels_gin`
- Trigger `lb_status_recompute` → пересчёт `LB.status` после INSERT/UPDATE/DELETE листенера

## VIP — НЕ на листенере

Listener адреса не несёт и не аллоцирует: VIP — свойство [[nlb-load-balancer]] (один `vpc.Address` на
семейство, источник задаётся per-family на `LoadBalancer.Create`). Листенер — это `(port, protocol)` на
VIP родительского LB и обслуживает **все** его семейства сразу; per-listener выбора семейства нет.

- `Listener.Create` — чистый INSERT в одной writer-TX (+ outbox `nlb_listener CREATED` /
  `nlb_load_balancer UPDATED` + FGA-register-intent), **без** обращения к vpc; статус сразу `ACTIVE`
  (durable-handle/`CREATING`-фаза не нужна — аллоцировать нечего). INSERT берёт `FOR NO KEY UPDATE` на
  строке LB → сериализуется с `LoadBalancer.Move` (иначе stale `project_id`, TOCTOU) и с
  `MarkDeleting` (иначе листенер, вставленный после mark, расклинил бы Delete на FK-RESTRICT).
- `Listener.Delete` VIP **не освобождает** — адрес принадлежит LB и переживает листенер. Release идёт
  только на `LoadBalancer.Delete` / компенсации Create-саги / free-ip-reconciler:
  [[../edges/nlb-to-vpc-vip-allocation]].
- Vestigial-остаток: `SetAllocatedAddress`/`SetVIP` в repo не имеют прод-вызывающих; `Delete` читает
  `address_id` в legacy-release-ветке, которая на практике не срабатывает (колонка всегда пуста).

## Immutability rules

`load_balancer_id`, `protocol`, `port` — `InvalidArgument` при Update (ДО `UpdateMask`).
Mutable: `name`, `description`, `labels`, `default_target_group_id`/`target_group_id`, `proxy_protocol_v2`.

## Lifecycle

`ACTIVE → (UPDATING → ACTIVE)* → DELETING`. Create завершается сразу в `ACTIVE`. Delete снимает строку;
DB-триггер пересчитывает `LB.status` (`ACTIVE → INACTIVE`, если wired-листенеров не осталось).

## Gotchas

- Два листенера на одном VIP допустимы только при разных `(port, protocol)` — держит
  `UNIQUE (load_balancer_id, port, protocol)`, а не какой-либо VIP-индекс.
- Listener-level partial-UNIQUE `(region_id, allocated_address, port, protocol)` **снят миграцией 0025**:
  он энфорсил колонку, которую прод-код не пишет → partial-предикат `allocated_address <> ''` не матчил
  ни одной строки. История: создан `0001`, снят `0009` (VIP → LB), ошибочно возвращён `0021` под
  нереализованный listener-VIP-редизайн.
- `region_id`/`ip_version` у листенера на wire **нет** — берутся с родительского LB.

## See also

[[../packages/nlb-apps-kacho-api-listener]] [[../rpc/nlb-listener-service]] [[nlb-load-balancer]] [[../edges/nlb-to-vpc-vip-allocation]]

#resource #kacho-nlb #listener
