---
title: ServiceAccount
aliases:
  - ServiceAccount (iam)
  - iam ServiceAccount
  - SA
category: resource
domain: iam
id_prefix: sva
owner_table: kacho_iam.service_accounts
owner_db: kacho_iam
folder_level: false
status: done
related_rpc:
  - "[[rpc/iam-service-account-service]]"
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
  - "[[KAC-127]]"
tags:
  - resource
  - kacho-iam
  - iam
---

# ServiceAccount

**Domain**: iam (machine-identity, account-scoped + optional project_id since KAC-127).
**ID prefix**: `sva` (20 chars).
**Owner table**: `kacho_iam.service_accounts`.
**Status**: KAC-105 базовый, **KAC-127 Phase 1** добавил `project_id` (optional, preferred над account-scope) + `enabled` flag.

## Fields (KAC-127 extended)

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `ids.IsValid("sva")` | |
| `account_id` | TEXT | FK → accounts(id) RESTRICT | NOT NULL |
| `project_id` | TEXT NULL | FK → projects(id) RESTRICT (KAC-127) | optional, preferred scope |
| `name` | TEXT | `^[a-z][-a-z0-9]{2,62}$` | UNIQUE (account_id, name) |
| `description` | TEXT | `<=256` chars | |
| `enabled` | BOOL | default `true` (KAC-127) | false → SA не может authenticate |
| `labels` | JSONB | `kacho_labels_valid` (mig 0041) | tenant-facing метки; **mutable** через Update; делают SA label-selectable |
| `created_at` | TIMESTAMPTZ | server-set | |

## Constraints / indexes

- `service_accounts_pkey` PRIMARY KEY (id)
- `service_accounts_account_fk` FK → `accounts(id)` ON DELETE RESTRICT
- `service_accounts_project_fk` FK → `projects(id)` ON DELETE RESTRICT (KAC-127)
- `service_accounts_account_name_unique` UNIQUE (account_id, name)
- CHECK: `service_accounts_name_check`, `service_accounts_description_check`
- **`labels` jsonb** (migration 0041): `NOT NULL DEFAULT '{}'` + CHECK `kacho_iam.kacho_labels_valid(labels)` + GIN `jsonb_path_ops` (под `labels @> matchLabels`).

## FK contract (in-bound)

- `service_account_oauth_clients.sva_id → service_accounts(id) ON DELETE CASCADE` (KAC-127; 1:1)
- `federation_trust_policies.service_account_id → service_accounts(id) ON DELETE CASCADE` (KAC-127)
- `group_members.member_id` (when `member_type='service_account'`) — soft-ref через триггер.
- `access_bindings.subject_id` (when `subject_type='service_account'`) — soft-ref.

## Lifecycle

- **Create / Update / Delete** — все async через `Operation`.
- **Disable (KAC-127)**: `enabled=false` → AuthN-interceptor (Phase 2) запретит `client_credentials` grant; existing tokens продолжают работать до natural `exp` (или revoke через [[iam-session-revocation]]).
- **Key-credentials** — KAC-127 Phase 5 через [[iam-service-account-oauth-client]] (Class A static Hydra client).
- **Federation** — KAC-127 Phase 5 через [[iam-federation-trust-policy]] (Class B OIDC federation).

## Label-selectability + List-видимость (DIVERGENCE-A / T3.3)

- **Label-selectable** (own-resource `labels`, mig 0041): label-грант `{module:iam, resources:["serviceAccount"], matchLabels:{…}}` материализует `v_list` на matching-SA (`service_accounts.labels @> matchLabels`), iam-direct same-DB (НЕ mirror), containment по iam-hierarchy. `labels` mutable через `Update` (`update_mask=labels`); Create/Update request `labels` несут полный annotation-set (паритет account/project — раньше SA request-`labels` были без аннотаций, доведены до паритета).
- **`List` = `viewer ∪ v_list`** (эталон role.List): anonymous → empty; FGA error → `Unavailable`; self-floor; admin/owner/cluster-admin через FGA viewer tier-cascade. `Get == List` resolver.
- **membership-over-show устранён** — член аккаунта больше не видит все SA автоматически (только себя + viewer/v_list-видимые); admin/owner — без visibility loss.

## Gotchas

- `account_id` immutable.
- `project_id` — optional (KAC-127); если задан, должен принадлежать SAME `account_id` (Phase 1 service-CHECK).
- KAC-127: удаление SA каскадно удаляет `service_account_oauth_clients` + `federation_trust_policies` (CASCADE). НЕ каскадит на GroupMember/AccessBinding (soft-ref).
- На KAC-105: SA без OAuthClient не может «логиниться» — только хранится как identity-stub. KAC-127 Phase 5 включает реальный workload identity flow.

## Module service-accounts (SEC-C, least-priv ReBAC)

[[../KAC/SEC-C-iam-fga-proxy-sa-roles]] seed-миграция `0009` сидит **5 системных module-SA**
(детерминированный `'sva'||substr(md5('kacho-<svc>'),1,17)`), anchored к системному
account/user (`account_id NOT NULL` constraint): `kacho-vpc`, `kacho-compute`, `kacho-nlb`,
`kacho-vpc-operator`, `kacho-api-gateway` (имена — эпик §4.1 п.6 канон).

- **Backing RBAC-v2 роль** на каждый SA (cluster-scoped, `is_system`, детерминированный `rol`-id
  из `md5('module.<svc>_sa')` — имя `module.<svc>_sa`, post-dot сегмент без дефиса per
  `roles_system_name_check`). Permission-строки **строго 4-сегментные** `module.resource.*.verb`,
  эмпирически из `kacho-proto/gen/permission_catalog.json` (напр. `vpc.subnets.*.get`,
  `vpc.subnetses.*.list`, `iam.projectses.*.list`). compute: addresses CRUD + subnets/sg/projects get;
  vpc: zones.get + projects.get; nlb: subnets.get + projects.get; vpc-operator: read-only list/get;
  api-gateway: minimal `iam.projects.*.get` (identity-only, authz по user-JWT).
- **AccessBinding** SA→роль на cluster scope (`scope=1`), `acb`-id детерминированный, idempotent.
- **ReBAC relation-tuple** `service_account:<sva>#fga_writer@iam_fgaproxy:system` в `fga_outbox`
  для vpc/compute/nlb (FGA-proxy право); vpc-operator/api-gateway — **без** (least-priv).
- **cert→SA mapping** (OQ-C-5): SPIRE-SAN `spiffe://kacho.cloud/ns/<ns>/sa/kacho-<svc>` →
  тот же детерминированный `sva`-id (`authzguard.SANToServiceAccountID`). Без новой колонки.

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-service-account-service]] [[../rpc/iam-internal-iam-service]] [[iam-account]] [[iam-project]] [[iam-service-account-oauth-client]] [[iam-federation-trust-policy]] [[../KAC/KAC-105]] [[../KAC/KAC-127]] [[../KAC/SEC-C-iam-fga-proxy-sa-roles]]

#resource #kacho-iam #iam
