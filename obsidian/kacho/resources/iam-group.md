---
title: Group
aliases:
  - Group (iam)
  - iam Group
category: resource
domain: iam
id_prefix: grp
owner_table: kacho_iam.groups
owner_db: kacho_iam
folder_level: false
status: done
related_rpc:
  - "[[rpc/iam-group-service]]"
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
tags:
  - resource
  - kacho-iam
  - iam
---

# Group

**Domain**: iam (account-scoped collection User/SA для упрощения раздачи прав)
**ID prefix**: `grp` (20 chars)
**Owner tables**: `kacho_iam.groups` (+ `kacho_iam.group_members` для membership)
**Folder-level**: no (account-scoped)
**Status (E0)**: backend в [[KAC-112]].

## Fields (groups)

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `ids.IsValid("grp")` | |
| `account_id` | TEXT | FK → accounts(id) RESTRICT | NOT NULL |
| `name` | TEXT | `^[a-z][-a-z0-9]{2,62}$` | UNIQUE (account_id, name) |
| `description` | TEXT | `<=256` chars | |
| `labels` | JSONB | `kacho_labels_valid` | |
| `created_at` | TIMESTAMPTZ | server-set | |

## Membership table `group_members`

| Field | Type | Note |
|---|---|---|
| `group_id` | TEXT | FK → groups(id) ON DELETE CASCADE |
| `member_type` | TEXT | CHECK `IN ('user','service_account')` |
| `member_id` | TEXT | **полиморфная ref** — без FK, защищается триггером |
| `added_at` | TIMESTAMPTZ | server-set |

PRIMARY KEY (group_id, member_type, member_id) — идемпотентный AddMember.

## Constraints / indexes

- `groups_account_fk` FK → `accounts(id)` RESTRICT
- `groups_account_name_unique` UNIQUE (account_id, name)
- `group_members_group_fk` FK → `groups(id)` ON DELETE CASCADE
- **Trigger** `group_members_member_exists_trg` (BEFORE INSERT/UPDATE) — проверяет existence row в `users` либо `service_accounts` (по `member_type`); SQLSTATE 23503/23514 → `FailedPrecondition`.
- `group_members_member_idx` (member_type, member_id)
- `groups.labels` — колонка с baseline (CHECK `kacho_labels_valid`); **GIN `jsonb_path_ops` добавлен migration 0041** (раньше колонка была, индекса под `labels @> matchLabels` не было).

## Lifecycle

- **Group**: Create / Update / Delete — async через `Operation`. Delete → CASCADE по `group_members`. `labels` mutable через `Update` (`update_mask=labels`).
- **Membership**: `AddMember`, `RemoveMember`, `ListMembers` — отдельные async-RPC.

## Label-selectability + List-видимость (DIVERGENCE-A / T3.3)

- **Label-selectable** (own-resource `labels`): label-грант `{module:iam, resources:["group"], matchLabels:{…}}` материализует `v_list` на matching-группы (`groups.labels @> matchLabels`), iam-direct same-DB (НЕ mirror), containment по iam-hierarchy. Реверс O-4 (раньше iam content-типы не были label-selectable).
- **`List` = `viewer ∪ v_list`** (эталон role.List): anonymous → empty; FGA error → `Unavailable`; admin/owner/cluster-admin через FGA viewer tier-cascade. `Get == List` resolver. (Раньше `group.List` был голым repo-passthrough.)

## FGA membership mirror (КРИТИЧНО для group-based authz)

> [!important] Membership должно зеркалиться в FGA, иначе group-subject binding не даёт доступа
> AccessBinding с group-субъектом эмитит FGA userset-tuple `<obj>#<rel>@group:<gid>#member`
> (access_binding/tuples.go `subjectRef`). Чтобы FGA Check резолвил ЧЛЕНА группы, нужен
> member-tuple `group:<gid>#member@<user|service_account>:<id>`.

- **AddMember.doAdd** co-commit'ит `EmitFGARelationWrite{user|service_account:<id>, member, group:<gid>}`
  в той же writer-tx, что `INSERT group_members` (SEC-D / запрет #10, fix 9e4f2e6).
- **RemoveMember.doRemove** — симметричный `EmitFGARelationDelete`.
- **Тип объекта = `group`** (FGA userset-тип, на который ссылается binding), **НЕ `iam_group`**
  (object-scope hierarchy-тип, который эмитит group Create: `iam_group:<id>#account@account:<acc>`).
  member-tuple на `iam_group` НЕ резолвит binding userset (проверено real-FGA тестом GM-3).
- `member_type` (`user`/`service_account`) = канонический FGA user-prefix → маппится verbatim
  (та же логика, что `subjectRef` для subject-стороны binding'а).
- **Backfill**: migration `0029_backfill_group_member_fga_tuples` эмитит member-tuple intent
  для всех существующих `group_members` (идемпотентно `WHERE NOT EXISTS`); drainer применяет at-least-once.
- Был баг (до 9e4f2e6): AddMember писал ТОЛЬКО `group_members` → group-binding userset резолвился
  в пусто → члены не получали доступ, ExpandAccess не находил членов (E-31 RBACSUBJ-EXPAND-GROUP-OK red).

## Gotchas

- `member_id` без FK (полиморфно) — целостность через триггер `group_members_member_exists`; нельзя добавить несуществующего user/sa.
- Cascade User/SA delete (через тригерную FK alternativу) **не реализован** в E0 — удаление User-а с активной GroupMembership → `FailedPrecondition` от service-слоя (см. [[iam-user]]).
- AddMember идемпотентен — PRIMARY KEY на (group, type, id) → 23505 → `AlreadyExists` mapped в `Created (no-op)` (если так выбрана семантика; иначе error — см. acceptance §7).

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-group-service]] [[iam-user]] [[iam-service-account]] [[../KAC/KAC-105]]

#resource #kacho-iam #iam
