---
title: "kacho-iam · internal/repo/kacho/pg/fga_outbox"
category: packages
repo: kacho-iam
layer: repo
tags:
  - packages
  - kacho-iam
  - outbox
  - race-fix
---

# `internal/repo/kacho/pg/fga_outbox`

Writer-tx-scoped emitter для `fga_outbox` table — атомарно складывает FGA grant/revoke
events в outbox в той же транзакции, что и domain-mutation (AccessBinding row, JIT state-row,
BreakGlass approval row). Drainer ([[corelib-outbox-drainer]]) применяет события к OpenFGA с
LISTEN/NOTIFY-уведомлением + fallback-polling.

Закрывает W1.5 findings #8/#16/#47/#48/#50/#51/#52 — split-brain DB/FGA grant-write desync
([[../KAC/KAC-163]]).

## Exported API

| Symbol | Назначение |
|---|---|
| `EmitWriteTx(ctx, tx, ev FGAWriteEvent) error` | INSERT row с `op=write` в `fga_outbox` в данной tx; NOTIFY fires at commit |
| `EmitDeleteTx(ctx, tx, ev FGADeleteEvent) error` | INSERT row с `op=delete` (revoke) в той же tx |
| `FGAWriteEvent` | `{User, Relation, Object}` (FGA tuple-key) + опц. `Condition` |
| `FGADeleteEvent` | `{User, Relation, Object}` |
| `Writer.EmitFGARelationWrite` / `EmitFGARelationDelete` (sub-phase 1.4 S2, iam #161) | co-commit **owner/hierarchy**-tuple для СОБСТВЕННЫХ iam-ресурсов (Account/Project/Group/SA/Role + bootstrap `UpsertFromIdentity`) В writer-tx → тот же `fga_outbox`. Перенос с best-effort POST-COMMIT `relationhook.WriteHierarchyTuple` (терялся при крэше). Без новой миграции (fga_outbox в `0001`). |

Оба `Emit*Tx` принимают `pgx.Tx` (не `Conn`) — это контракт «в одной транзакции с domain
mutation»: writer открывает tx → выполняет domain INSERT/UPDATE/DELETE → выполняет `EmitWriteTx`
или `EmitDeleteTx` → коммитит. Откат tx → outbox row не появляется → FGA не вызывается. Никаких
fire-and-forget вне transaction-границы.

## Имports

- `github.com/jackc/pgx/v5` (для `pgx.Tx`)
- `context`, `encoding/json` из stdlib
- НЕ импортирует `service/` или `domain/` — это pure adapter

## Imported by

- `internal/repo/kacho/pg/access_binding/writer.go` — Create/Delete emit
- `internal/service/jit/jit_service.go` (или соотв. writer) — auto-grant, Approve, Expire emit
- `internal/service/breakglass/bg_service.go` — ApproveB emit
- own-resource writers (Account/Project/Group/SA/Role + bootstrap) — owner/hierarchy-tuple co-commit (sub-phase 1.4 S2)

## Контракт идемпотентности

Drainer применяет каждый row к OpenFGA Write/Delete; FGA `409 Conflict` (tuple уже есть на write
или нет на delete) трактуется как success → row помечается consumed. Это обеспечивает retry-safe
семантику при transient OpenFGA errors / drainer restart.

## Схема `fga_outbox` row

См. migration 0024 (kacho-iam):
- `id` (uuid) — primary key
- `op` (text) — `write` | `delete`
- `user`, `relation`, `object` (text) — FGA tuple key
- `condition` (jsonb, nullable) — для conditional tuples (W2+)
- `created_at` (timestamptz)
- `consumed_at` (timestamptz, nullable) — drainer ставит при success

Связанная UNIQUE / DB-инварианта на `cluster_admin_grants(subject_user_id, project_id)` —
migration 0024 (см. CLAUDE.md §запрет #10: software refcheck запрещён, DB-уровень обязателен).

## Связанные

- [[../KAC/KAC-163]] (W1.5 — внедрение)
- [[../KAC/KAC-137]] (W1.1 — drainer foundation)
- [[../KAC/sub-phase-1.4-tuple-resource-guarantee]] (S2 — own-resource owner-tuple co-commit)
- [[corelib-outbox-drainer]] (применяет события к FGA)
- [[../edges/iam-to-openfga-grant-write]] (runtime-edge)
- [[../packages/iam-authzmap]] (mapping rules для tuple-relation derive)

#packages #kacho-iam #outbox
