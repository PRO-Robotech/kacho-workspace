---
title: audit_outbox (iam)
category: resource
domain: iam
id_prefix: evt
owner_table: kacho_iam.audit_outbox
folder_level: outbox
status: stable
related_rpc:
  - "[[rpc/iam-internal-cluster-service]]"
  - "[[rpc/iam-internal-iam-service]]"
related_packages: []
tags:
  - resource
  - kacho-iam
  - iam
  - internal
---

# audit_outbox (iam)

Durable, append-only IAM compliance event-log table (`kacho_iam.audit_outbox`,
migration baseline `0001_initial`). A drainer streams rows into the audit topic;
the kacho-iam side commits the **domain mutation + audit row in the SAME
writer-tx** (запрет #10) — commit-together-or-rollback-together, no orphan rows.

## Columns / CHECKs

`id, event_type, tenant_account_id, event_payload jsonb, status, attempts,
created_at, next_attempt_at`. CHECKs: `audit_outbox_id_check`
(`^evt_[0-9A-HJKMNP-TV-Za-hjkmnp-tv-z]{20,30}$`), `audit_outbox_event_type_check`
(`^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$`, len 1..128),
`audit_outbox_payload_object_ck` (payload is a JSON object), `audit_outbox_status_check`.

> [!warning] id generator (bug #126)
> Emit paths MUST use `newAuditEventID()` → `evt_<22-char>` (satisfies the
> {20,30} floor). `domain.NewKac127ID` emits a 17-char body that **fails**
> `audit_outbox_id_check` → silent 23514 reject at INSERT (the latent bug #126).

## event_type taxonomy (sub-phase 5.2 emit expansion)

`iam.<resource>.<action>`. Existing: `iam.access_binding.granted/revoked`.
Wave A #1 (cluster-admin + session) added:

| event_type | emitter |
|---|---|
| `iam.cluster_admin.granted` | GrantAdmin (fresh **or** reactivate; no-op repeat emits nothing) |
| `iam.cluster_admin.revoked` | RevokeAdmin |
| `iam.session.revoked` | session Revoke (single jti) |
| `iam.session.all_revoked` | session Revoke (revoke_all_user_tokens=true) |
| `iam.session.force_logout` | InternalIAMService.ForceLogout |

Wave A #2 (CRUD slice) added (emit inside the async Operation **worker-tx**, atomic with the INSERT/UPDATE/DELETE):

| event_type | emitter |
|---|---|
| `iam.account.created/updated/deleted` | AccountService Create/Update/Delete |
| `iam.project.created/updated/deleted` | ProjectService Create/Update/Delete (Move RPC absent → no `moved`) |
| `iam.user.created` | InternalUserService.UpsertFromIdentity (bootstrap insert) |
| `iam.user.updated` | UpsertFromIdentity activate-invite (mirror-fields) |
| `iam.user.deleted` | UserService.Delete |
| `iam.service_account.created/updated/deleted` | ServiceAccountService C/U/D |
| `iam.group.created/updated/deleted` | GroupService C/U/D (member± out of this slice) |
| `iam.role.created/updated/deleted` | RoleService C/U/D (Update payload = `changed_fields`, no perms blob) |

Update events carry `changed_fields` (applied mutable fields); a no-op update
(value unchanged) commits nothing → emits nothing (emit-per-committed-change).

Wave A #3 (SAKey issue/revoke, FINAL slice) added (emit inside the async Operation **worker-tx**, atomic with the key-mapping mutation):

| event_type | emitter |
|---|---|
| `iam.sa_key.issued` | SAKeyService.IssueSAKey (atomic with `service_account_oauth_clients` INSERT) |
| `iam.sa_key.revoked` | SAKeyService.RevokeSAKey (atomic with the mapping DELETE) |

SAKey payload carries **only** non-secret identifiers: `actor`, `service_account_id`,
`key_id` (`soc_…`), `key_algorithm`, `resource_type`/`resource_id` — **never** the
private key PEM, `client_secret`, or any token (acceptance 5.2-36). The Hydra
OAuth2-client side-effect is created/deleted *outside* the worker-tx; the audit
row records only the DB-committed fact.

Payload keys are **snake_case** (`actor`, `resource_type`, `resource_id`,
`account_id`, `name`/`email`/`display_name`, `changed_fields`) for parity with
the existing access_binding/cluster/session rows.

## Emit-in-tx wiring

- **Shared port**: `service.AuditOutboxEmitter.EmitTx(ctx, tx, AuditEvent)` —
  pg adapter `kachopg.AuditOutboxEmitter` (txAsPgx + `AuditOutboxRepo.InsertTx`).
  Used by cluster Grant/RevokeAdmin use-cases inside their `txb.Begin` tx.
- **CRUD writer-tx**: `kacho.Writer.EmitAuditEvent(ctx, service.AuditEvent)` (Wave
  A #2) — pg `writeTx` delegates to the shared `insertAuditEventTx` helper (same
  `AuditOutboxRepo.InsertTx` + `newAuditEventID`), so the async CRUD use-cases emit
  inside their `shared.DoWithWriteTx` closure (atomic with the mutation) while
  staying pgx-free. No SQL duplication — one emit path for adapter + writer-tx.
  Principal captured **sync** in `Execute` (worker ctx may lack it), passed in.
- **Session/force-logout** had no caller-tx (single-statement pool adapter), so
  `SessionRevocationsAdapter` gained tx-scoped `RevokeTx` / `RevokeAllUserTokensTx`
  (Begin → revoke upsert → audit InsertTx → Commit), preserving the existing
  `ON CONFLICT … DO UPDATE` / `UpsertRevokeAll` (GREATEST) contracts.
- **SAKey** (Issue/Revoke) own a raw `pgx.Tx` from their local `TxBeginner.Begin`
  (`commitMapping` for Issue, `doRevoke` for Revoke). A narrow `sa_keys.auditEmitter`
  port (`EmitTx(ctx, service.Tx, AuditEvent)`) takes the same shared
  `kachopg.AuditOutboxEmitter`; the raw `pgx.Tx` satisfies `service.Tx` directly
  (`txAsPgx`), so the audit row INSERTs on the exact tx that persists/deletes the
  mapping — no new adapter, no SQL duplication.
- **emit-per-committed-change**: an idempotent no-op (already-active grant) emits
  nothing; a concurrent same-jti upsert emits one row per committed tx.
- **actor**: always from `authzguard.PrincipalUserID` (anti-spoof), never a body field.
- **no secrets** in payload (security.md): session carries only `token_jti`
  (the revoked token's id, not the token).

## See also

[[../rpc/iam-internal-cluster-service]] [[../rpc/iam-internal-iam-service]]
[[../rpc/iam-access-binding-service]]

#resource #kacho-iam #iam #internal
