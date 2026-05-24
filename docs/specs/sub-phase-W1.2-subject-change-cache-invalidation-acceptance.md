# Sub-phase W1.2 — `subject_change_outbox` push-drain + gateway authz-cache invalidation on revoke — Acceptance

> **Status**: DRAFT (awaiting `acceptance-reviewer` per CLAUDE.md §Запреты #1).
> **Date**: 2026-05-23
> **YouTrack**: KAC-138 W1.2 (subtask of [KAC-136](https://prorobotech.youtrack.cloud/issue/KAC-136), child of epic [KAC-134](https://prorobotech.youtrack.cloud/issue/KAC-134) "kacho-iam → production-ready"). The KAC-138 issue itself is created by the controller after this doc reaches APPROVED.
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer` (gate per запрет #1, workspace `CLAUDE.md`).
> **Target repos**:
>   - **Primary**: `PRO-Robotech/kacho-iam` — migration 0023, schema/check evolution, JIT/BG emit-paths, `InternalIAMService.PollSubjectChanges` payload extension.
>   - **Primary**: `PRO-Robotech/kacho-api-gateway` — replace whole-cache flush with per-subject invalidation; second `Drainer[T]` instance to push events from outbox directly (eliminates 2s poll lag).
>   - **Touched**: `PRO-Robotech/kacho-proto` — `SubjectChange.subject_id` already exists (mig 0002 schema); `PollSubjectChangesResponse.changes[]` already carries it. May need new event op names in proto comments. Verify on impl-side; no breaking change expected.
>   - **NOT touched**: `kacho-corelib` — generic `Drainer[T]` already shipped in W1.1; W1.2 reuses unchanged.
> **Branch (all repos)**: `KAC-138`.
> **Parent epic plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-master.md` Wave 1.
> **Wave plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-wave1.md` §W1.2.
> **Predecessor**: `sub-phase-W1.1-fga-outbox-drainer-acceptance.md` (APPROVED 2026-05-23).

---

## 0. Преамбула — что эта sub-итерация (précis)

W1.2 — **второй чанк Wave 1**. Закрывает root-cause «после `AccessBindingService.Delete`
(или JIT/break-glass revoke) gateway authz-cache всё ещё возвращает ALLOW в течение 2 секунд +
flush-whole-cache на каждый event» путём:

1. **Расширение схемы** `kacho_iam.subject_change_outbox` (migration 0023): добавить
   `event_type` (`binding_revoke` / `binding_grant` / `jit_revoke` / `bg_revoke` /
   `group_member_change` — широкий набор для будущих consumer'ов); добавить
   `resource_type` + `resource_id` (опциональные — для будущей точечной invalidate-по-resource);
   добавить `sent_at`, `attempt_count`, `last_error` (form parity с `fga_outbox` чтобы
   drainer-of-W1.1 мог дренить без switch'ей в коде). Существующий `op` оставляем как alias
   (CHECK расширяется, не удаляется — backward compat poll-API).
2. **Расширение emit-сайтов** в kacho-iam: `JitPendingService.DenyJITActivation` (handler +
   service layer) / `JitPendingExpirerWorker.Tick` / `BreakGlassService.DenyBreakGlass` /
   `BreakGlassExpirerWorker.Tick` начинают вызывать **new** `EmitSubjectChangeEvent(ctx,
   SubjectChangeEvent{...})` (writes payload jsonb + denormalised columns одной INSERT) в той
   же Writer-tx, что и DB-state-flip UPDATE (atomicity per запрет #10). Existing
   `EmitSubjectChange(ctx, subjectID, op)` остаётся как backward-compat shim (internally
   calls new overload). Подробности — §4.6.
3. **Push-drain через corelib Drainer[T]** (вместо poll-loop'а WS-2.3, который сейчас работает
   с 2s lag). Второй экземпляр `Drainer[SubjectChangeEvent]` запускается **на kacho-iam-side**
   (в `cmd/kacho-iam/main.go` errgroup, parity с W1.1 FGA-drainer):
     - LISTEN канала `kacho_iam_subject_outbox_added` через **локальный** pgxpool (gateway не
       держит pool на iam-DB — запрет #8, DB-per-service).
     - Drainer публикует invalidate через **новый internal RPC**
       `InternalAuthzCacheService.InvalidateSubject(subject, resource)` на каждый
       drained row; api-gateway implements этот RPC на internal listener (port 9091, mTLS) +
       drop'ает per-subject cache entries через `decisionCache.InvalidateSubject(subject)`.
     - Wiring details — §4.2 (kacho-iam side drainer goroutine) + §4.5 (api-gateway side
       server registration на internal mux).
4. **Per-subject invalidate** вместо whole-cache flush: `decisionCache.InvalidateSubject(subject)`
   уже существует (`project/kacho-api-gateway/internal/middleware/authz.go:941`); меняется
   callsite watcher'а с `AuthzMiddleware.InvalidateCache()` (flush-all, line 246) на
   `InvalidateSubject(subject)` для конкретного `subject_id` из drained event'а.
   `InvalidateCache()` остаётся как fallback (когда event без subject_id приходит, e.g.
   `group_member_change` для группы — flush-всё нужен пока group-membership resolver не введён).
5. **Удаление WS-2.3 poll-loop**: `kacho-api-gateway/internal/watcher/subject_change_watcher.go`
   удаляется (или становится fallback на случай Drainer-fail с большим интервалом 30s). Drainer
   обеспечивает sub-second latency.

**End-to-end gain:** revoke binding / JIT-deny / BG-deny → drainer claim'ит row → внутри 100-300ms
RPC-call в **один** gateway-replica (DNS-resolver выбирает по балансировке) → gateway
invalidate per-subject cache → next `Check` для этого subject'а на этой replica hits
OpenFGA и возвращает DENY.

**Latency / consistency promise** (вместе с OQ-W1.2-7 trade-off — см. §8):
- **≥ 1 replica converges within < 1s** of revoke commit — гарантировано push-drain path'ом
  (drainer → gateway InvalidateSubject RPC на одну replica).
- **All HA-replicas converge within ≤ 30s** — гарантировано WS-2.3 safety-net poll-loop
  (бывшие 2s → bumped 30s), который flush'ит каждую replica независимо.
- Полный fanout invalidate (all replicas < 1s) — out of scope W1.2 (см. OQ-W1.2-7 решение
  ниже: не делаем DNS/headless-service fanout — оверкомплексность для kind-deploy без
  обоснованного productivity-выигрыша).

### 0.1 W1.2 НЕ включает

- Перевод sync `WriteTuples`/`DeleteTuples` из `AccessBindingService.Create/Delete` на запись
  через `fga_outbox` — **W1.5** (findings #16/#8).
- Перевод JIT/BG **grant** (approve-path) на outbox — **W1.5** (findings #50/#51/#52).
  W1.2 только покрывает revoke-эмит (без grant-эмит — он сейчас async через fga_outbox в
  будущем W1.5).
- Gateway authz-middleware fail-closed enable — **W1.3**.
- Principal propagation cross-service — **W1.4**.
- Удаление полей `op` / `subject_id` из proto (backward-compat preserved через alias).
- Per-resource invalidate (если кэш-key содержит ResourceID, invalidate должен фильтровать и по
  нему). MVP: invalidate по subject-prefix; per-resource — backlog tikcet'ом если productivity
  cache-hit-rate'а это потребует.

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** (workspace) — кодирование только после `acceptance-reviewer` APPROVED | данный doc — gate; статус выше `DRAFT`. |
| **Запрет #2** — НЕ упоминать "yandex" | в коде/комментариях/тестах не упоминается. |
| **Запрет #3** — НЕ ORM | только handwritten pgx (drainer уже соблюдает) + sqlc если потребуется. |
| **Запрет #4** — НЕ cross-service cascade delete | drainer-event — informational push, не cascade; gateway сам решает, что инвалидировать. |
| **Запрет #5** — НЕ редактировать применённую миграцию | `0002_fga_outbox.sql` НЕ трогаем. Все изменения схемы — в **новой** миграции `0023_subject_change_outbox_v2.sql` (kacho-iam) через `ALTER TABLE ADD COLUMN` + `ALTER TABLE … DROP CONSTRAINT subject_change_op_check; ADD CONSTRAINT subject_change_op_check CHECK (op IN (…расширенный набор…))`. |
| **Запрет #6** — Internal.* НЕ на external TLS endpoint | новый `InternalAuthzCacheService.InvalidateSubject` — **только** на api-gateway internal listener (port 9091, mTLS); НЕ регистрируется в публичном REST mux. |
| **Запрет #7** — НЕ broker | используется in-process drainer + LISTEN/NOTIFY + gRPC peer-call. Kafka/NATS отсутствует. |
| **Запрет #8** — DB-per-service | drainer работает с локальной БД kacho-iam (kacho_iam schema); api-gateway не получает pgxpool на iam-DB. Event'ы пересекают service-boundary через **gRPC** (kacho-iam → api-gateway internal mTLS). |
| **Запрет #9** — async LRO для мутаций | `InvalidateSubject` — internal infra RPC (как `InternalIAMService.Check`), не tenant-mutation → sync RPC допустим (parity с тек. internal). |
| **Запрет #10** — within-service refs DB-level | drainer-claim на `subject_change_outbox` — атомарный CAS-UPDATE (тот же паттерн, что W1.1 для `fga_outbox`); concurrent-race integration-test обязателен (см. §6.3). |
| **Запрет #11** — test-first, тесты в том же PR | W1.2 PR обязан содержать (a) RED-integration-тесты до impl; (b) RED → GREEN пары в PR-описании; (c) минимум: 1 happy + 1 negative + 1 concurrent + 1 end-to-end (≤1s latency). Newman case — **обязателен** (см. §6.4 W1.2-15): **NEW** newman-case `AUTHZ-REVOKE-ENFORCED-A-INV` (verified отсутствует в `project/kacho-iam/tests/newman/cases/authz-deny.py` на момент DRAFT 2026-05-23) к добавлению as RED-first в начале W1.2 — до impl схемы/drainer/gateway. Becomes GREEN после landing push-drain + InvalidateSubject endpoint. |
| **CLAUDE.md §«Принцип переиспользования через kacho-corelib»** | drainer переиспользует `kacho-corelib/outbox/drainer.Drainer[T]` без изменений. |
| **CLAUDE.md §«Within-service refs — DB-уровень обязателен»** | atomic emit subject_change_outbox в той же tx, что и Delete (уже сделано в AccessBinding; повторяется в JIT/BG). |
| **CLAUDE.md §«Кросс-доменные ссылки на ресурсы»** | kacho-iam → api-gateway — новое runtime-edge (reverse direction относительно api-gateway → kacho-iam). См. §«Архитектурное решение» — не образует цикла (api-gateway → iam.Check уже есть; iam → gateway.InvalidateSubject — другой intent, infra-only). |

---

## 2. Глоссарий

- **subject_change_outbox** — таблица в `kacho_iam` schema (мигр. 0002), в которую внутри той же
  tx, что и domain-mutation (AccessBinding.Delete / JIT.Deny / BG.Deny) пишется событие
  «у subject X изменились его grants». До W1.2 — payload `(subject_id, op)`; после W1.2 —
  `(subject_id, op, event_type, resource_type, resource_id, sent_at, attempt_count, last_error)`.
- **subject_id** — FGA-style identifier subject'а, чей grant изменился. Для AccessBinding.Delete —
  `string(binding.SubjectID)` (e.g. `usr_abc123` / `sva_xyz`). Для JIT-revoke — usr / sva
  затронутого pending'а. Для BG.Deny — usr запросившего break-glass.
- **event_type** (новое поле) — категоризация события для consumer'ов:
    - `binding_revoke` — `AccessBindingService.Delete` (заменяет существующий `binding_delete`-op как
      первичный термин; backward compat через `op` колонку).
    - `binding_grant` — `AccessBindingService.Create` (заменяет `binding_upsert`; пока используется
      только для self-flush hint, full grant write — в W1.5).
    - `jit_revoke` — `JitPendingService.Deny` / expiry worker, который cancel'ит approved JIT и снимает grant.
    - `bg_revoke` — `BreakGlassService.Deny` / `BreakGlassService` auto-expire worker.
    - `group_member_change` — изменение членства группы (group affects access transitively;
      резервируется, в W1.2 не emit'ится).
- **op** — legacy-колонка из мигр. 0002. Сохраняется через `ALTER … ADD CHECK` с расширенным
  набором значений (чтобы `PollSubjectChanges`-existing callers не падали). Drainer читает
  `event_type` (новое поле) приоритетно; если `event_type IS NULL` (старые rows) — derive из `op`.
- **InternalAuthzCacheService** — новый gRPC сервис на api-gateway internal listener
  (port 9091, mTLS). Один метод — `InvalidateSubject(InvalidateSubjectRequest) returns (Empty)`.
  Caller — kacho-iam-side drainer; callee — api-gateway. Cluster-internal only, не на external TLS.
- **Per-subject invalidate** — `decisionCache.InvalidateSubject(subject)` (api-gateway authz.go:941)
  снимает только entries с prefix `<subject>|`, не сбрасывая весь кэш. Уже реализовано — W1.2
  переключает callsite с `InvalidateCache()` (flush-all) на per-subject.
- **Drained event** — row из `subject_change_outbox` после успешного `apply()` (= успешного
  RPC-call в api-gateway) → `sent_at = now()`. Идемпотентен: повторный drain — no-op.

---

## 3. Data model — миграция `0023_subject_change_outbox_v2.sql` (kacho-iam, NEW)

### 3.1 Текущее состояние (мигр. 0002, AS-IS)

```sql
CREATE TABLE kacho_iam.subject_change_outbox (
    id            bigserial    PRIMARY KEY,
    subject_id    text         NOT NULL,
    op            text         NOT NULL,
    created_at    timestamptz  NOT NULL DEFAULT now(),
    notified_at   timestamptz,
    CONSTRAINT subject_change_op_check
        CHECK (op IN ('binding_upsert', 'binding_delete', 'group_member_change'))
);
CREATE INDEX subject_change_pending_idx
    ON kacho_iam.subject_change_outbox (created_at) WHERE notified_at IS NULL;
-- + trigger fn kacho_iam.subject_change_outbox_notify() NOTIFY 'kacho_iam_subject_outbox_added'
```

> **Семантика разница**: `notified_at` использовалась как «watcher успел увидеть» (WS-2.3 poll-loop
> не mutate'ит ничего, поэтому field остался NULL у всех historic rows). После W1.2 drainer mark'ит
> `sent_at` (новая колонка), `notified_at` остаётся **alias-view** (см. §3.3).

### 3.2 Новая миграция `0023_subject_change_outbox_v2.sql` (kacho-iam, in scope)

```sql
-- +goose Up
-- +goose StatementBegin
SET search_path TO kacho_iam, public;

-- Drop old CHECK, install widened CHECK (preserve legacy op values + add new).
ALTER TABLE kacho_iam.subject_change_outbox
    DROP CONSTRAINT subject_change_op_check;

ALTER TABLE kacho_iam.subject_change_outbox
    ADD CONSTRAINT subject_change_op_check
    CHECK (op IN (
        'binding_upsert',      -- legacy alias = binding_grant
        'binding_delete',      -- legacy alias = binding_revoke
        'group_member_change', -- reserved
        'binding_grant',
        'binding_revoke',
        'jit_revoke',
        'bg_revoke'
    ));

-- New canonical event_type (preferred); op kept for backward compat for
-- existing consumers (PollSubjectChanges still returns op too).
ALTER TABLE kacho_iam.subject_change_outbox
    ADD COLUMN event_type text;

-- Optional resource refs (NULL when event is subject-wide, e.g. JIT-revoke
-- of an entire pending). When set, future per-resource cache invalidation
-- can scope drops to (subject, resource_type, resource_id).
ALTER TABLE kacho_iam.subject_change_outbox
    ADD COLUMN resource_type text,
    ADD COLUMN resource_id   text;

-- Form parity with kacho_iam.fga_outbox so the generic corelib Drainer[T]
-- can claim rows uniformly. sent_at supersedes notified_at semantically
-- (notified_at stays NULL forever; consumers should prefer sent_at).
ALTER TABLE kacho_iam.subject_change_outbox
    ADD COLUMN sent_at       timestamptz,
    ADD COLUMN attempt_count integer NOT NULL DEFAULT 0,
    ADD COLUMN last_error    text;

-- payload jsonb — required by corelib drainer SELECT contract.
-- kacho-corelib/outbox/drainer/internal.go:185-197 SELECTs columns
-- `id, event_type, payload, attempt_count` and Scans them; without
-- this column drainer fails on init/Scan. The Decoder[T] signature
-- `func(payload []byte) (T, error)` receives ONLY the payload bytes —
-- it does NOT see other row columns. Therefore payload MUST contain
-- the full SubjectChangeEvent JSON for the drainer to function.
--
-- NULLABLE (not NOT NULL) so the ADD COLUMN itself is fast (no
-- rewrite). Backfill below populates payload for every existing row
-- from denormalised columns; after backfill, every NOT-YET-SENT row
-- has a valid payload. The NULL state remains representable for
-- short windows during dual-write concurrent INSERTs from older
-- writers, but in steady state (after this migration commits)
-- all pending rows have payload set.
ALTER TABLE kacho_iam.subject_change_outbox
    ADD COLUMN payload jsonb;

-- One-shot backfill: synthesise payload JSON for every existing row
-- (sent or not) from the denormalised columns. This is safe because:
--   (a) payload format = the same JSON shape SubjectChangeApplier
--       Decoder expects (subject_id, event_type, op, resource_type,
--       resource_id);
--   (b) event_type is derived from op when NULL (mapping below);
--   (c) the backfill is idempotent — `WHERE payload IS NULL` ensures
--       re-running migration is no-op.
UPDATE kacho_iam.subject_change_outbox
   SET payload = jsonb_build_object(
       'subject_id', subject_id,
       'op',         op,
       'event_type', COALESCE(event_type,
                              CASE op
                                  WHEN 'binding_delete' THEN 'binding_revoke'
                                  WHEN 'binding_upsert' THEN 'binding_grant'
                                  ELSE op
                              END),
       'resource_type', COALESCE(resource_type, ''),
       'resource_id',   COALESCE(resource_id,   '')
   )
 WHERE payload IS NULL;

-- Also backfill event_type column so PollSubjectChanges + drainer
-- read consistent canonical values from steady-state.
UPDATE kacho_iam.subject_change_outbox
   SET event_type = CASE op
       WHEN 'binding_delete' THEN 'binding_revoke'
       WHEN 'binding_upsert' THEN 'binding_grant'
       ELSE op
   END
 WHERE event_type IS NULL;

-- Drainer-pending predicate uses sent_at (parity with fga_outbox). The old
-- index on notified_at IS NULL is now stale; replace with sent_at-based.
DROP INDEX IF EXISTS kacho_iam.subject_change_pending_idx;
CREATE INDEX subject_change_pending_v2_idx
    ON kacho_iam.subject_change_outbox (created_at) WHERE sent_at IS NULL;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP INDEX IF EXISTS kacho_iam.subject_change_pending_v2_idx;
CREATE INDEX subject_change_pending_idx
    ON kacho_iam.subject_change_outbox (created_at) WHERE notified_at IS NULL;
ALTER TABLE kacho_iam.subject_change_outbox
    DROP COLUMN payload,
    DROP COLUMN last_error,
    DROP COLUMN attempt_count,
    DROP COLUMN sent_at,
    DROP COLUMN resource_id,
    DROP COLUMN resource_type,
    DROP COLUMN event_type;
ALTER TABLE kacho_iam.subject_change_outbox
    DROP CONSTRAINT subject_change_op_check;
ALTER TABLE kacho_iam.subject_change_outbox
    ADD CONSTRAINT subject_change_op_check
    CHECK (op IN ('binding_upsert', 'binding_delete', 'group_member_change'));
-- +goose StatementEnd
```

### 3.3 Semantics of resulting columns (drainer-side reading)

| Колонка | Поведение |
|---|---|
| `id` | NOTIFY payload (`kacho_iam_subject_outbox_added`); drainer claim'ит по нему. |
| `subject_id` | Affected subject (FGA prefix UNREMOVED — drainer derives full FGA from `subject_type` from outside context if needed; W1.2 keeps subject_id raw, applier prepends `user:` / `service_account:` etc. as needed). |
| `op` | Legacy. Mapped 1-to-1 to event_type when latter is NULL (binding_delete→binding_revoke, binding_upsert→binding_grant). |
| `event_type` (NEW) | Canonical event tag. NULL allowed only for pre-W1.2 rows. New writes from W1.2 MUST set both `op` (alias) and `event_type` for transition period. |
| `resource_type` / `resource_id` (NEW) | Optional. When set, drainer can request finer-grained invalidate. W1.2 MVP — applier ignores them и инвалидирует по subject-prefix; backlog'ed для productivity. |
| `created_at` | Used for catch-up ORDER BY. |
| `sent_at` (NEW) | Drainer mark'ит при success/already-applied (parity with fga_outbox). NULL → pending. |
| `notified_at` (LEGACY) | Не используется drainer'ом. Оставляется как столбец, потому что миграция 0002 уже в проде. |
| `attempt_count` (NEW) | Drainer инкрементит per attempt; `>= MaxAttempts` → row force-poisoned. |
| `last_error` (NEW) | Последняя ошибка applier-а. |
| `payload` (NEW) | jsonb. **Required by corelib drainer SELECT contract** (`outbox/drainer/internal.go:185-197` SELECTs `id, event_type, payload, attempt_count`; `Decoder[T] = func(payload []byte) (T, error)` видит ТОЛЬКО payload-байты, не остальные колонки row). Миграция 0023 делает **one-shot backfill** для всех existing rows (sent или нет) — payload synthesised из денормализованных колонок (`subject_id`, `op`, `event_type`, `resource_*`). Новые writes (W1.2-onwards) `EmitSubjectChangeEvent` сериализуют полный `SubjectChangeEvent` в payload **И** заполняют денормализованные колонки (forward-compat для drainer + backward-compat для still-served `PollSubjectChanges` RPC). Defensive: если drainer всё-таки натыкается на `len(payload)==0` row (race: pre-W1.2 writer commit-нул между ADD COLUMN и backfill), `DecodeSubjectChange` возвращает `ErrPermanent` — row force-poisoned, требует human-attention. |

---

## 4. API / interface contract

### 4.1 Proto: `InternalAuthzCacheService` (kacho-api-gateway side, NEW)

```protobuf
// kacho-proto/proto/kacho/cloud/apigateway/v1/internal_authz_cache_service.proto (NEW)

syntax = "proto3";
package kacho.cloud.apigateway.v1;
import "google/protobuf/empty.proto";

// Internal cache control. Cluster-internal only. NOT registered on the
// external TLS REST mux (workspace CLAUDE.md §запрет #6). Listener:
// api-gateway internal gRPC port (9091, mTLS).
service InternalAuthzCacheService {
  // InvalidateSubject drops decision-cache entries scoped to the given
  // subject (FGA prefix). Called by kacho-iam subject_change_outbox
  // drainer after a revoke/grant mutation commits.
  //
  // Idempotent: a subject with no cached entries returns OK (no error).
  // The response is purposefully empty — subjects-affected count is
  // reported via metric `apigw.authz.cache.invalidate.entries`, not the
  // RPC reply (avoids tail-latency on metric collection).
  rpc InvalidateSubject (InvalidateSubjectRequest)
    returns (google.protobuf.Empty);
}

message InvalidateSubjectRequest {
  // Subject — FGA-style "<type>:<id>", e.g. "user:usr_abc",
  // "service_account:sva_xyz". REQUIRED.
  string subject = 1;

  // ResourceType / ResourceID — optional scope hint. When BOTH set,
  // gateway invalidates only entries matching (subject, resource_type,
  // resource_id). When either empty, gateway invalidates ALL entries for
  // the subject (current MVP — per-resource implementation backlog).
  string resource_type = 2;
  string resource_id   = 3;

  // EventType — diagnostic only (logged); does not influence behaviour.
  // Values: binding_revoke / binding_grant / jit_revoke / bg_revoke.
  string event_type = 4;
}
```

### 4.2 Drainer wiring (kacho-iam main.go, in scope)

```go
// cmd/kacho-iam/main.go (extension — second Drainer[T] alongside FGA one from W1.1)

g.Go(func() error {
    cli := clients.NewInternalAuthzCacheClient(apigatewayInternalAddr) // mTLS dial
    d, err := drainer.New[clients.SubjectChangeEvent](
        pool,
        drainer.Config{
            Table:        "kacho_iam.subject_change_outbox",
            Channel:      "kacho_iam_subject_outbox_added",
            BatchSize:    64,
            PollFallback: 30 * time.Second,
            MaxAttempts:  10,
            BackoffMin:   200 * time.Millisecond, // sub-second push-cycle
            BackoffMax:   10 * time.Second,
            ApplyTimeout: 3 * time.Second,
        },
        clients.DecodeSubjectChange,
        clients.NewSubjectChangeApplier(cli),
        logger.With("component", "subject-change-drainer"),
    )
    if err != nil {
        return fmt.Errorf("subject-change drainer: init: %w", err)
    }
    return d.Run(gctx)
})
```

### 4.3 Applier (kacho-iam/internal/clients/subject_change_applier.go, NEW)

```go
package clients

import (
    "context"
    "encoding/json"
    "errors"

    apigwv1 "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/apigateway/v1"
    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/status"

    "github.com/PRO-Robotech/kacho-corelib/outbox/drainer"
)

type SubjectChangeEvent struct {
    SubjectID    string `json:"subject_id"`
    EventType    string `json:"event_type"`     // canonical (mirrors row's event_type column)
    Op           string `json:"op"`             // legacy alias (informational; drainer's eventType arg wins)
    ResourceType string `json:"resource_type,omitempty"`
    ResourceID   string `json:"resource_id,omitempty"`
}

// DecodeSubjectChange — drainer.Decoder[SubjectChangeEvent].
// Signature `func(payload []byte) (T, error)` — drainer hands us ONLY
// the payload bytes from the `payload jsonb` column (not other row
// columns). Migration 0023 backfills payload for every existing row at
// upgrade time, so steady-state every row has valid JSON here.
//
// `len(payload)==0` indicates a defensive edge: pre-W1.2 writer
// commit-нул INSERT в гонке между ADD COLUMN и UPDATE-backfill
// (window <1s during migration). Treated as permanent error — row
// force-poisoned, requires operator inspection (rare; explicit
// alarm path).
func DecodeSubjectChange(payload []byte) (SubjectChangeEvent, error) {
    var e SubjectChangeEvent
    if len(payload) == 0 {
        return e, errors.Join(drainer.ErrPermanent,
            errors.New("subject_change: payload IS NULL — pre-W1.2 row not backfilled (operator: re-run UPDATE backfill from migration 0023)"))
    }
    if err := json.Unmarshal(payload, &e); err != nil {
        return e, errors.Join(drainer.ErrPermanent, err)
    }
    if e.SubjectID == "" {
        return e, errors.Join(drainer.ErrPermanent, errors.New("subject_change: subject_id empty"))
    }
    // Backward-compat: derive event_type from legacy op if missing
    // (defensive — backfill already does this in SQL).
    if e.EventType == "" {
        switch e.Op {
        case "binding_delete":
            e.EventType = "binding_revoke"
        case "binding_upsert":
            e.EventType = "binding_grant"
        default:
            e.EventType = e.Op
        }
    }
    return e, nil
}

// SubjectChangeApplier — calls api-gateway InternalAuthzCacheService.InvalidateSubject.
//
// Drainer signature: `Applier[T] = func(ctx, eventType string, payload T) error`.
// `eventType` arg is the canonical value scanned from row's `event_type`
// column — that's the single source of truth. We prefer it over
// `e.EventType` from the decoded payload struct (they should match because
// payload is written from the same `event_type` value during emit, but
// drainer's column-scanned value wins in case of any drift).
type subjectChangeApplier struct {
    cli apigwv1.InternalAuthzCacheServiceClient
}

func NewSubjectChangeApplier(cli apigwv1.InternalAuthzCacheServiceClient) drainer.Applier[SubjectChangeEvent] {
    return func(ctx context.Context, eventType string, e SubjectChangeEvent) error {
        // SubjectID raw → FGA-prefixed. Drainer apply context-free; we
        // need a (single-source-of-truth) prefix table. For W1.2 we use a
        // tiny in-package switch (deliberate: deferring full SubjectType
        // resolution avoids touching kacho-iam repo lookups in the apply
        // hot-path).
        fga := fgaPrefixSwitch(e.SubjectID) // e.g. usr_… → "user:usr_…"
        // Prefer canonical eventType from drainer (DB column) over
        // payload's e.EventType. Fall back to payload value if drainer
        // somehow passes empty string (shouldn't happen — defensive).
        et := eventType
        if et == "" {
            et = e.EventType
        }
        _, err := cli.InvalidateSubject(ctx, &apigwv1.InvalidateSubjectRequest{
            Subject:      fga,
            ResourceType: e.ResourceType,
            ResourceID:   e.ResourceID,
            EventType:    et,
        })
        if err == nil {
            return nil
        }
        st, ok := status.FromError(err)
        if !ok {
            return err // network / unknown — transient
        }
        switch st.Code() {
        case codes.NotFound:
            // Gateway reports "no entries for subject" — idempotent success.
            return drainer.ErrAlreadyApplied
        case codes.InvalidArgument:
            return errors.Join(drainer.ErrPermanent, err)
        case codes.Unavailable, codes.DeadlineExceeded, codes.Internal:
            return err // transient — drainer retries with exp backoff
        default:
            return err // default: transient
        }
    }
}

// fgaPrefixSwitch — naive prefix mapper for W1.2. ProductivityV2 ticket
// will canonicalize this (probably move into corelib once two services
// need it). For now: keep colocated, document the rule, unit-test the
// mapping table.
func fgaPrefixSwitch(subjectID string) string {
    switch {
    case len(subjectID) > 4 && subjectID[:4] == "usr_":
        return "user:" + subjectID
    case len(subjectID) > 4 && subjectID[:4] == "sva_":
        return "service_account:" + subjectID
    case len(subjectID) > 4 && subjectID[:4] == "grp_":
        return "group:" + subjectID
    default:
        // Fallback for unrecognised — caller will see no-match invalidate,
        // logged + counted by gateway as miss (NotFound). Safe default.
        return subjectID
    }
}
```

### 4.4 Gateway server-side (kacho-api-gateway, NEW)

```go
// internal/handler/internal_authz_cache_server.go (NEW)

package handler

import (
    "context"

    apigwv1 "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/apigateway/v1"
    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/status"
    "google.golang.org/protobuf/types/known/emptypb"
)

type Invalidator interface {
    // InvalidateSubject returns the number of entries dropped.
    InvalidateSubject(subject string) int
    Invalidate() // fallback whole-cache
}

type InternalAuthzCacheServer struct {
    apigwv1.UnimplementedInternalAuthzCacheServiceServer
    inv    Invalidator
    logger *slog.Logger
}

func NewInternalAuthzCacheServer(inv Invalidator, logger *slog.Logger) *InternalAuthzCacheServer {
    return &InternalAuthzCacheServer{inv: inv, logger: logger}
}

func (s *InternalAuthzCacheServer) InvalidateSubject(
    ctx context.Context, req *apigwv1.InvalidateSubjectRequest,
) (*emptypb.Empty, error) {
    if req.Subject == "" {
        return nil, status.Error(codes.InvalidArgument, "subject required")
    }
    // ResourceType/ResourceID intentionally ignored for MVP (per-subject
    // invalidate is the safe upper bound — over-invalidates same subject's
    // unrelated resources but never under-invalidates). Logged for observability.
    dropped := s.inv.InvalidateSubject(req.Subject)
    s.logger.Info("authz cache invalidate (per-subject)",
        "subject", req.Subject,
        "event_type", req.EventType,
        "resource_type", req.ResourceType,
        "resource_id", req.ResourceID,
        "dropped", dropped,
    )
    if dropped == 0 {
        // Idempotent — nothing to invalidate. Use NotFound so the drainer
        // (kacho-iam side) treats it as ErrAlreadyApplied and marks sent_at.
        return nil, status.Error(codes.NotFound, "no cache entries for subject")
    }
    return &emptypb.Empty{}, nil
}
```

### 4.5 Wiring on gateway (cmd/api-gateway/main.go, IN SCOPE)

```go
// After authzMW construction:
if authzMW != nil {
    // Expose Invalidator-shaped wrapper around the AuthzMiddleware internals.
    // (AuthzMiddleware exposes InvalidateCache; needs new
    //  InvalidateSubject(subject string) int — implementable by exposing the
    //  underlying decisionCache method.)
    inv := authzMW.AsInvalidator()
    cacheSrv := handler.NewInternalAuthzCacheServer(inv, logger)
    apigwv1.RegisterInternalAuthzCacheServiceServer(internalGRPCSrv, cacheSrv)

    // WS-2.3 poll-loop becomes a low-frequency safety net for the push path.
    // Interval bumped from 2s → 30s; on push-path failure it still converges.
    scPoller := clients.NewSubjectChangePoller(backends["iamInternal"])
    scWatcher := watcher.New(scPoller, authzMW.InvalidateCache,
        30 * time.Second, logger)
    go scWatcher.Run(ctx)
    logger.Info("WS-2.3 subject-change watcher (safety-net) started",
        "interval", "30s")
}
```

### 4.6 Subject-emit additions (kacho-iam) — writer signature change + emit-sites

**Writer signature change** (chosen **Option A** from acceptance-reviewer feedback): existing
`EmitSubjectChange(ctx, subjectID, op string) error` остаётся для backward compat (kept callable
by existing AccessBinding paths until migrated). NEW overload added on the same writer:

```go
// EmitSubjectChangeEvent — preferred since W1.2. Serialises the full
// SubjectChangeEvent into the `payload jsonb` column AND writes
// denormalised columns (subject_id, op, event_type, resource_type,
// resource_id) for backward-compat with the still-served
// PollSubjectChanges RPC and for human readability of pg-rows.
// Both writes happen in the same INSERT statement (single row,
// atomic by construction). Caller is responsible for invoking inside
// the same Writer-tx as the domain state-change (atomicity per
// запрет #10) — see emit-site rules below.
//
// SubjectChangeEvent.Op is optional; if empty, set to a sensible
// alias of EventType (binding_revoke→binding_delete,
// binding_grant→binding_upsert, others→same as EventType).
func (w *KachoWriter) EmitSubjectChangeEvent(
    ctx context.Context, evt SubjectChangeEvent,
) error { ... }
```

Existing `EmitSubjectChange(ctx, subjectID, op)` is rewritten internally to call
`EmitSubjectChangeEvent(ctx, SubjectChangeEvent{SubjectID: subjectID, Op: op, EventType: deriveET(op)})`.
This way, existing AccessBinding emit-sites keep working without touching them; new emit-sites
use the richer overload.

**Three new emit-sites** (verified paths; all inside the same Writer-tx as the state-flip UPDATE
for atomicity per запрет #10 — implementer wraps the existing state-change in a
`Writer.Begin/Commit` if not already there):

1. **JIT.Deny (handler-level)** — `internal/apps/kacho/api/jit_pending/handler.go::(Handler).DenyJITActivation`
   (verified line 84) delegates to `internal/service/jit_pending_service.go::(JitPendingService).DenyJITActivation`
   (verified line 305). The emit MUST happen in the service-layer Writer-tx that flips
   `jit_pending.status = 'DENIED'`: open the tx, do the UPDATE, then call
   `w.EmitSubjectChangeEvent(ctx, SubjectChangeEvent{SubjectID: <denied request's subject_id>, EventType: "jit_revoke", Op: "jit_revoke"})`,
   then commit. If the state-change is currently outside an explicit tx, the implementer wraps
   both in `Writer.Begin/Commit`.

2. **JIT auto-expiry worker** — `internal/service/phase7b_workers.go::(JitPendingExpirerWorker).Tick`
   (verified line 145). When the worker expires an approved-but-stale JIT (status flip + grant
   revocation), it must emit `jit_revoke` for the affected subject inside the **same** Writer-tx
   as the status-flip UPDATE. Same wrapping rule as #1: implementer wraps the per-row state-change
   in a Writer-tx if not already wrapped, then calls `EmitSubjectChangeEvent` before commit.

3. **BreakGlass.Deny (handler-level)** — `internal/apps/kacho/api/break_glass/handler.go::(Handler).DenyBreakGlass`
   (verified line 82) delegates to a service-layer Deny method (e.g.
   `internal/service/break_glass_service.go::(BreakGlassService).DenyBreakGlass`, verify exact name
   at impl-start via `grep -n "func.*DenyBreakGlass\|func.*Deny" internal/service/break_glass*.go`).
   Same emit-rule: inside the Writer-tx that flips `break_glass_requests.status = 'DENIED'`,
   call `EmitSubjectChangeEvent(ctx, SubjectChangeEvent{SubjectID: <requester user id>, EventType: "bg_revoke", Op: "bg_revoke"})`,
   then commit.

4. **BreakGlass auto-expiry worker** — `internal/service/phase7_workers.go::(BreakGlassExpirerWorker).Tick`
   (verified line 213). Same as #2: when worker expires an active break-glass session (status flip),
   emit `bg_revoke` inside the same Writer-tx as the state-flip.

**Atomicity guarantee restated** (per запрет #10): every emit-site above is inside the same
Writer.Begin/Commit as the corresponding state-flip UPDATE. The Writer interface (already
established by existing AccessBinding Delete path) commits both INSERT-into-outbox and
state-flip-UPDATE atomically; if any step fails, the tx rolls back and **no** outbox row is
visible to the drainer. Integration test 6.1.4 (extended in §6.1.6 — see Fix #5 below) proves
this with a real testcontainer pgx Begin/Rollback flow.

---

## 5. Test discipline (запрет #11) — RED first

PR обязан содержать (в указанном порядке):

1. **RED phase commit** (testing-only): integration-тесты §6.1-6.5 написаны и закоммичены до impl;
   CI красный по этим тестам.
2. **GREEN phase commits**: impl (migration 0023 → gateway proto+server → iam applier+wiring → iam JIT/BG emit).
3. **End-to-end Newman case** (§6.4 W1.2-15): **NEW** newman-case `AUTHZ-REVOKE-ENFORCED-A-INV`
   к добавлению в `project/kacho-iam/tests/newman/cases/authz-deny.py` (case **не существует**
   на момент DRAFT — verified `grep "REVOKE-ENFORCED" project/kacho-iam/tests/newman/cases/authz-deny.py`
   2026-05-23 = 0 матчей). RED-first: case добавляется и регенерируется через `gen.py` ДО
   старта impl; первый прогон `tests/newman/run.sh` показывает FAIL (либо timeout 5-30s на cache,
   либо 200 ALLOW после revoke). Кейс становится GREEN после landing миграции 0023 + drainer +
   InvalidateSubject endpoint — latency revoke→DENY ≤ 1s на kind-стенде с W1.1+W1.2.

   **Specification кейса** (для импл-агента):
   ```
   Given AAA grants admin@account-A → INV role (binding-create + outbox-emit + drainer applies),
   And INV's first GET /iam/v1/accounts/<account-A> returns 200 (cache populated with ALLOW),
   When AAA revokes the binding (DELETE + subject_change_outbox emit + drainer-push to gateway),
   Then within 1s, INV's next GET /iam/v1/accounts/<account-A> returns 403/PERMISSION_DENIED
        (no 5-30s cache TTL wait).
   ```
4. **Concurrent race-test** (Scenario 6.3.2) — 2 экземпляра kacho-iam (HA-mini) с разными drainer
   pool'ами на одной БД: exactly-once invocation api-gateway InvalidateSubject; gateway-side counter
   ровно N.

Newman-case покрытие — обязательно (запрет #11). Smoke test после deploy: `kubectl exec ...
grpcurl ... AccessBinding.Delete && sleep 1 && grpcurl … Check` → expect DENY.

---

## 6. Сценарии (Given-When-Then) — основа интеграционных тестов

### 6.1 kacho-iam emit-side

#### Сценарий 6.1.1 — AccessBinding.Delete commit пишет canonical event_type

**ID**: W1.2-01

**Given** Postgres testcontainer + kacho-iam миграции (включая 0023) применены
**And** в `kacho_iam.access_bindings` есть row id `acb_test01`, subject_id `usr_alice`

**When** клиент вызывает `AccessBindingService.Delete{id: "acb_test01"}` (через handler-uc-repo
  chain; полноценный integration с DB) и Operation worker завершает doDelete

**Then** в `kacho_iam.subject_change_outbox` ровно одна row для этой Delete операции:
  - `subject_id = "usr_alice"`
  - `op = "binding_delete"` (legacy alias preserved)
  - `event_type = "binding_revoke"` (canonical NEW)
  - `sent_at IS NULL` (pending — drainer ещё не запущен в этом тесте)
  - `attempt_count = 0`

---

#### Сценарий 6.1.2 — JitPendingService.Deny пишет jit_revoke

**ID**: W1.2-02

**Given** в `kacho_iam.jit_pending` есть pending row для subject `usr_bob`, status='PENDING'

**When** клиент вызывает `JitPendingService.Deny{id: "jit_pending_id_x", denyReason: "ungranted"}`

**Then** в `kacho_iam.subject_change_outbox` появилась row с:
  - `subject_id = "usr_bob"`
  - `op = "jit_revoke"`
  - `event_type = "jit_revoke"`
  - `sent_at IS NULL`
**And** jit_pending row.status = 'DENIED' (DB visible после commit)
**And** subject_change_outbox row создана в той же transaction (rollback test ниже)

---

#### Сценарий 6.1.3 — BreakGlassService.Deny пишет bg_revoke

**ID**: W1.2-03

**Given** в `kacho_iam.break_glass_requests` есть pending row для requesterUserID `usr_charlie`

**When** клиент вызывает `BreakGlassService.Deny{id: "bg_id_x", denyReason: "policy violation"}`

**Then** `kacho_iam.subject_change_outbox` имеет row:
  - `subject_id = "usr_charlie"`
  - `op = "bg_revoke"`
  - `event_type = "bg_revoke"`

---

#### Сценарий 6.1.4 — Atomic: Delete-failure после Get-binding → outbox NOT написана

**ID**: W1.2-04

**Given** Postgres testcontainer + AccessBindingService.Delete use-case wired
**And** repo Writer mock'ed so that `AccessBindingsW().Delete` возвращает `ErrFailedPrecondition`
  на вторую попытку Get (simulates concurrent delete)

**When** Delete для существующего id вызывается; doDelete → Get OK → Delete fail → tx Rollback

**Then** `kacho_iam.subject_change_outbox` НЕ содержит row для этого `subject_id` от текущего теста
**And** Operation помечена failed (worker сообщил error)

> Доказывает атомарность на mock-уровне: outbox emit не «leakит» при abort transaction
> через Writer-mock. Уже частично доказано существующим integration test
> (`access_binding_subject_change_integration_test.go`, тест rollback case), W1.2 расширяет до
> полного use-case path'а. **NB**: real-pgx DB-level atomicity (force ROLLBACK после in-tx
> emit) проверяется отдельно в W1.2-22 — этот тест обязателен per запрет #10 и не заменяется
> mock-вариантом.

---

#### Сценарий 6.1.5 — Pre-W1.2 op-only rows читаются drainer'ом корректно

**ID**: W1.2-05

**Given** прямой INSERT в `subject_change_outbox (subject_id, op)` (legacy path; event_type IS NULL)
  с `op = "binding_delete"`

**When** drainer claim'ит и decoder обрабатывает row

**Then** decoder возвращает `SubjectChangeEvent{EventType: "binding_revoke"}` (mapped from op)
**And** applier вызывается с правильным event_type
**And** row помечена `sent_at IS NOT NULL`

---

### 6.2 Drainer + Applier (kacho-iam side)

#### Сценарий 6.2.1 — Single emit → applier RPC invoked within ~300ms via NOTIFY

**ID**: W1.2-06

**Given** Postgres testcontainer (kacho-iam миграции включая 0023) + fake gRPC server
  (`InternalAuthzCacheServer` stub) запущен на random port
**And** Drainer запущен с правильным applier

**When** прямой
  `INSERT INTO kacho_iam.subject_change_outbox (subject_id, op, event_type) VALUES ('usr_test', 'binding_delete', 'binding_revoke')`

**Then** в течение **1 секунды** (CI-stability; на dev ~50-200ms) fake gateway-server получил
  ровно один `InvalidateSubject` call с `subject = "user:usr_test"`, event_type=`binding_revoke`
**And** row помечена `sent_at IS NOT NULL`, `attempt_count = 1`, `last_error IS NULL`

---

#### Сценарий 6.2.2 — Gateway NotFound (no cache entries) → ErrAlreadyApplied success

**ID**: W1.2-07

**Given** fake gateway-server настроен возвращать `codes.NotFound` (cache holes for that subject)

**When** drainer claim'ит row → applier → RPC

**Then** drainer mark'ит row `sent_at IS NOT NULL` (idempotent success per W1.1 §4.4)
**And** `last_error IS NULL`

---

#### Сценарий 6.2.3 — Gateway Unavailable (503) → transient retry → eventually success

**ID**: W1.2-08

**Given** fake gateway: первые 2 attempt'а — `codes.Unavailable`; третий — OK
**And** Drainer.Config: `BackoffMin=100ms`, `BackoffMax=500ms`

**When** INSERT row

**Then** в течение **2 секунд** fake gateway зарегистрировал 3 attempt'а
**And** row `sent_at IS NOT NULL`, `attempt_count = 3`, `last_error IS NULL` (последний reset
  после success — parity с W1.1 поведением)

---

#### Сценарий 6.2.4 — Gateway InvalidArgument (empty subject) → permanent error

**ID**: W1.2-09

**Given** прямой `INSERT INTO subject_change_outbox (subject_id, op, event_type) VALUES ('', 'binding_delete', 'binding_revoke')`

**When** drainer пытается обработать

**Then** decoder возвращает `ErrPermanent` (subject_id empty check в `DecodeSubjectChange`)
**And** row помечена `attempt_count = MaxAttempts`, `last_error LIKE '%subject_id empty%'`
**And** drainer не вызывает RPC и продолжает работу со следующими rows

---

#### Сценарий 6.2.5 — Subject FGA-prefix mapping корректный для usr/sva/grp

**ID**: W1.2-10

**Given** drainer + applier
**And** fake gateway recorder

**When** INSERT три rows: `usr_a`, `sva_b`, `grp_c`

**Then** fake gateway получил ровно 3 InvalidateSubject calls с subjects:
  - `"user:usr_a"` (usr-prefix → user:)
  - `"service_account:sva_b"` (sva-prefix → service_account:)
  - `"group:grp_c"` (grp-prefix → group:)

---

### 6.3 Gateway endpoint behaviour

#### Сценарий 6.3.1 — InvalidateSubject drop'ает per-subject entries

**ID**: W1.2-11

**Given** AuthzMiddleware с decisionCache содержит entries:
  - key prefix `user:usr_a|<hash1>` (3 entries)
  - key prefix `user:usr_b|<hash2>` (5 entries)

**When** `InternalAuthzCacheService.InvalidateSubject{subject: "user:usr_a"}` RPC

**Then** ответ — OK + `Empty{}`
**And** decisionCache содержит только 5 entries (user:usr_b сохранены)
**And** metric `apigw.authz.cache.invalidate.entries{subject="user:usr_a"}` инкрементнут на 3
**And** structured log: `authz cache invalidate (per-subject) subject=user:usr_a dropped=3`

---

#### Сценарий 6.3.2 — InvalidateSubject subject не в кэше → NotFound (idempotent)

**ID**: W1.2-12

**Given** decisionCache пуст

**When** `InvalidateSubject{subject: "user:usr_z"}`

**Then** ответ — `codes.NotFound`, message="no cache entries for subject"
**And** decisionCache остаётся пуст
**And** structured log: `... dropped=0`

> Drainer ловит NotFound → `ErrAlreadyApplied` → row mark'ит sent_at (idempotent semantic).

---

#### Сценарий 6.3.3 — InvalidateSubject с пустым subject → InvalidArgument

**ID**: W1.2-13

**Given** запущен gateway-server

**When** `InvalidateSubject{subject: ""}`

**Then** ответ — `codes.InvalidArgument`, message="subject required"
**And** decisionCache не тронут
**And** drainer ловит InvalidArgument → `ErrPermanent` → row force-poisoned (attempt_count = MaxAttempts)

---

#### Сценарий 6.3.4 — External TLS listener → 404 (endpoint не зарегистрирован)

**ID**: W1.2-14

**Given** kacho-api-gateway запущен с external TLS listener (на test-порту через
  testcontainers/helm umbrella mock) и internal mTLS listener (на отдельном порту)
**And** `InternalAuthzCacheService` зарегистрирован только на internal mux

**When** клиент устанавливает gRPC connection к external listener и вызывает
  `kacho.cloud.apigateway.v1.InternalAuthzCacheService/InvalidateSubject`

**Then** ответ — `codes.Unimplemented` (или connection rejected proxy-resolver'ом до handler-а)
**And** decisionCache не тронут
**And** structured log: `proxy resolver: unknown method ...` (или эквивалент proxy-чисти miss)

> Защита запрета #6: Internal.* не light up на external TLS endpoint. Тест — explicit integration,
> поднимающий оба listener'а с одним handler-set'ом и проверяющий route-isolation.

---

### 6.4 End-to-end (kacho-iam + api-gateway + OpenFGA-stub on testcontainers OR helm umbrella)

#### Сценарий 6.4.1 — Revoke binding → DENY < 1s (cache invalidation push working)

**ID**: W1.2-15 (parity with **NEW** newman case `AUTHZ-REVOKE-ENFORCED-A-INV` — to be added
to `project/kacho-iam/tests/newman/cases/authz-deny.py` as RED-first in W1.2; case **не
существует** на main 2026-05-23, becomes GREEN after this sub-phase lands)

**Given** helm umbrella deployment (kind cluster через `kacho-deploy/make dev-up`) с W1.1+W1.2 fix:
  kacho-iam + api-gateway + OpenFGA HA bootstrap
**And** root token имеет `kacho.cloud.iam.v1.AccessBindingService/*` permission
**And** test creates AccessBinding {subject: user:usr_test, role: viewer, resource: project:prj_a}
**And** wait for fga_outbox drain (W1.1) → OpenFGA имеет tuple
**And** `Check{subject: user:usr_test, action: resourcemanager.projects.get, resource: project:prj_a}` → ALLOW
**And** ALLOW записан в gateway cache (decisionCache entry для usr_test)

**When** client calls `AccessBindingService.Delete{id: ...}` через api-gateway
**And** waits 1 second
**And** calls `Check{subject: user:usr_test, action: ..., resource: project:prj_a}` против
  **той же** api-gateway replica, что и в Given (sticky-session test client, либо single-replica
  deployment для детерминизма; см. §0 latency promise — гарантия `≥ 1 replica converges < 1s`)

**Then** Check возвращает DENY (cache entry для usr_test invalidated и refetched из OpenFGA-no-tuple)
**And** общая end-to-end latency revoke→DENY ≤ 1000ms на этой replica
**And** (multi-replica caveat) другие HA-replicas сходятся в течение ≤ 30s через
  safety-net poll-loop — отдельно проверяется в W1.2-19; W1.2-15 фокус — push-path latency
  на одной replica

---

#### Сценарий 6.4.2 — Gateway briefly Unavailable → drainer retries → eventually invalidated

**ID**: W1.2-16

**Given** umbrella deployment как 6.4.1
**And** gateway internal listener временно (5s) недоступен (`kubectl scale deploy api-gateway --replicas=0` then `--replicas=1`)
**And** root client посылает 1 Delete revoke в момент, когда gateway down

**When** gateway восстанавливается (5s интервал)
**And** drainer retries InvalidateSubject (exp backoff: 200ms, 400ms, 800ms, 1.6s ...)

**Then** в течение **15 секунд** от момента восстановления gateway: InvalidateSubject succeeded
**And** subsequent Check(usr_test) возвращает DENY
**And** subject_change_outbox row помечена `sent_at IS NOT NULL`, `attempt_count >= 2`

---

### 6.5 Concurrency / HA

#### Сценарий 6.5.1 — Two kacho-iam replicas (HA) с двумя drainer'ами — exactly-once RPC

**ID**: W1.2-17

**Given** Postgres testcontainer + 2 экземпляра kacho-iam main (с разными pgxpool'ами) — оба
  drainer'а на одну `subject_change_outbox` table
**And** один fake-gateway recorder (atomic counter per subject_id)

**When** 20 INSERT-ов в subject_change_outbox одной волной

**Then** в течение **3 секунд** все 20 rows `sent_at IS NOT NULL`
**And** оба drainer'а получают NOTIFY на каждую row (LISTEN-канал
  `kacho_iam_subject_outbox_added` broadcasts ко всем listener-ам), но
  **`FOR UPDATE SKIP LOCKED`** в claim-query (drainer's atomic CAS-claim)
  гарантирует, что **ровно один** drainer claims каждую конкретную row;
  второй уже видит её locked и переходит к следующей
**And** counter ровно **20** (не 40 — гарантия exactly-once, не at-least-once;
  no double-invalidate per row)
**And** оба drainer'а отработали ≥ 1 row (load spread; per-replica counter > 0;
  сумма ровно 20)

> Защита через атомарный CAS-claim drainer'а — `UPDATE … WHERE id IN (
> SELECT … FROM <table> WHERE sent_at IS NULL ORDER BY id FOR UPDATE SKIP LOCKED LIMIT $N)`
> (`kacho-corelib/outbox/drainer/internal.go:185-197`, унаследовано из W1.1 §4.2 паттерна).

---

#### Сценарий 6.5.2 — Drainer ребут с pending rows → catch-up на startup

**ID**: W1.2-18

**Given** kacho-iam запущен, drainer offline (ctxCancel), fake-gateway down
**And** в subject_change_outbox 5 pending rows (накопились пока drainer был offline)

**When** drainer перезапускается, fake-gateway up

**Then** в течение **2 секунд** все 5 rows обработаны (catch-up SELECT по `sent_at IS NULL`)
**And** fake-gateway получил 5 InvalidateSubject calls (subject-ordered ASC по `created_at`)

---

### 6.6 Backward compat / safety net

#### Сценарий 6.6.1 — WS-2.3 poll-loop работает как safety net (gateway-side)

**ID**: W1.2-19

**Given** api-gateway запущен с push-drainer SOURCE DISABLED (mimics drainer crash); poll-loop
  watcher запущен с интервалом 30s
**And** напрямую INSERT в `subject_change_outbox` 1 row (bypass drainer)

**When** test ждёт 30s + 1s buffer

**Then** poll-loop вызвал `InvalidateCache()` (whole-cache flush — fallback path)
**And** structured log: `authz decision-cache flushed by subject-change poll`

> Доказывает, что watcher не удалён — он остаётся как safety net (30s интервал acceptable
> при working drainer; критичный degradation-режим: drainer crash + 30s window до cache flush).

---

#### Сценарий 6.6.2 — Migration 0023 forward+reverse без data loss

**ID**: W1.2-20

**Given** Postgres с применённой миграцией 0022 (до W1.2); existing row в subject_change_outbox с
  `(subject_id='usr_old', op='binding_delete', created_at=t0, notified_at=NULL)`

**When** применяется `0023_subject_change_outbox_v2.sql` Up

**Then** существующая row сохранена; новые колонки `event_type=NULL`, `resource_type=NULL`,
  `resource_id=NULL`, `sent_at=NULL`, `attempt_count=0`, `last_error=NULL`
**And** CHECK extended OK (`binding_delete` всё ещё valid)
**And** drainer (с W1.2-кодом) обрабатывает этот row корректно (decoder derive event_type из op)

**And when** применяется Down

**Then** колонки drop'нуты, CHECK сужен обратно к 0002-набору; row сохранена (только op
  field остался)
**And** historic row не выпадает CHECK constraint

---

#### Сценарий 6.6.3 — Legacy row после backfill корректно decoded drainer'ом

**ID**: W1.2-21

**Given** Postgres testcontainer с pre-W1.2 schema (мигр. 0022 включая 0002 — только legacy
  columns); прямой
  `INSERT INTO kacho_iam.subject_change_outbox (subject_id, op) VALUES ('usr_legacy', 'binding_delete')`
  (legacy row, `payload IS NULL`, `event_type IS NULL`)
**And** применяется миграция `0023_subject_change_outbox_v2.sql` Up (включая backfill UPDATE)

**When** drainer запущен; fake-gateway recorder активен

**Then** в течение **1 секунды** drainer:
  - SELECT-ит row с `event_type='binding_revoke'` (backfilled из op), `payload` содержит
    `{"subject_id":"usr_legacy","op":"binding_delete","event_type":"binding_revoke","resource_type":"","resource_id":""}` (backfilled)
  - `DecodeSubjectChange(payload)` возвращает
    `SubjectChangeEvent{SubjectID: "usr_legacy", EventType: "binding_revoke", Op: "binding_delete"}`
  - Applier вызывает `InvalidateSubject{subject: "user:usr_legacy", event_type: "binding_revoke"}`
**And** fake-gateway recorder получил один call
**And** row помечена `sent_at IS NOT NULL`, `attempt_count=1`, `last_error IS NULL`

> Доказывает: backfill миграции 0023 одинаково покрывает sent и pending legacy rows;
> drainer не нуждается в специальной legacy-обработке (всё JSON, как у новых rows).

---

#### Сценарий 6.6.4 — Defensive: payload IS NULL row (race с backfill) → permanent poison

**ID**: W1.2-21b

**Given** Postgres testcontainer с применённой миграцией 0023; прямой
  `INSERT INTO kacho_iam.subject_change_outbox (subject_id, op, event_type) VALUES ('usr_x', 'jit_revoke', 'jit_revoke')`
  **без** payload (simulates pre-W1.2 writer commit'нувший в окне между ADD COLUMN и UPDATE-backfill)
**And** fake-gateway recorder активен

**When** drainer пытается обработать row

**Then** `DecodeSubjectChange([])` возвращает `ErrPermanent` с message
  containing `"payload IS NULL — pre-W1.2 row not backfilled"`
**And** row помечена `attempt_count = MaxAttempts`, `last_error LIKE '%payload IS NULL%'`
**And** fake-gateway recorder не получил ни одного call для этого row
**And** drainer продолжает работу со следующими rows (no infinite-retry-loop)

> Доказывает defense-in-depth: даже если backfill каким-то образом пропустил row (race-окно
> при upgrade), drainer fail-fast'ит на конкретной row и не зависает; operator получает
> alarm на `subject_change_outbox.attempt_count >= MaxAttempts` rows.

---

#### Сценарий 6.6.5 — Atomic emit / rollback: JIT.Deny fail после in-tx emit → outbox row НЕ leaked

**ID**: W1.2-22

**Given** Postgres testcontainer (real pgx, NOT mocked) с применённой миграцией 0023;
  kacho-iam JIT service wired через handler→service→Writer chain
**And** в `kacho_iam.jit_pending` есть pending row для `subjectID='usr_atomic'`, `status='PENDING'`
**And** test hook (через injected error-injector в Writer.Commit или через explicit
  `pgx.BeginTx → ROLLBACK after emit`) форсит ROLLBACK после успешных UPDATE+EmitSubjectChangeEvent

**When** test вызывает full `JitPendingService.DenyJITActivation` path; внутренний Writer-tx
  открывает Begin, делает UPDATE `jit_pending.status='DENIED'`, делает
  INSERT в `subject_change_outbox` (через `EmitSubjectChangeEvent`), затем test-инжектированный
  hook вызывает `tx.Rollback()` вместо Commit

**Then** в новой read-only tx:
  - SELECT из `kacho_iam.jit_pending WHERE id=<denied id>` → `status='PENDING'` (rollback'нут)
  - SELECT из `kacho_iam.subject_change_outbox WHERE subject_id='usr_atomic'` возвращает **0 rows**
    (INSERT тоже откачен — атомарность гарантирована Postgres'ом)
**And** drainer (если запущен) не видит outbox row (он же не commit'нут)
**And** Operation помечена failed/aborted

> **Усиление 6.1.4**: 6.1.4 использовал mock'нутый Writer.Delete (искусственный fail на repo-mock
> level — не доказывает DB-level atomicity). W1.2-22 — real-pgx force-ROLLBACK после in-tx
> emit; единственный способ убедиться, что INSERT в outbox действительно откатывается на
> уровне Postgres. Запрет #10 (within-service refs DB-level) обязывает иметь этот тест.

---

## 7. Definition of Done

- [ ] `acceptance-reviewer` ✅ APPROVED данного doc (запрет #1 gate)
- [ ] Branch `KAC-138` создан в `kacho-iam` + `kacho-api-gateway` + `kacho-proto`
- [ ] **kacho-proto**: `internal_authz_cache_service.proto` (NEW) + регенерация Go-stub; `buf lint` / `buf breaking` зелёные
- [ ] **kacho-iam migration**: `internal/migrations/0023_subject_change_outbox_v2.sql` создана; integration-тест миграции (forward+reverse) GREEN (W1.2-20)
- [ ] **kacho-iam writer**: `EmitSubjectChange` writer обновлён на запись `event_type` (помимо `op`); existing tests AccessBinding Create/Delete всё ещё GREEN
- [ ] **kacho-iam emit-sites**: JIT.Deny + BG.Deny + JIT.expiry emit-ы добавлены; integration-тесты для каждого (W1.2-01/02/03) GREEN
- [ ] **kacho-iam applier**: `internal/clients/subject_change_applier.go` (NEW); unit-тест prefix-mapping table (W1.2-10) GREEN
- [ ] **kacho-iam wiring**: `cmd/kacho-iam/main.go` second `Drainer[T]` instance в errgroup; smoke-test container поднят локально, drainer не падает
- [ ] **kacho-api-gateway proto-server**: `internal/handler/internal_authz_cache_server.go` (NEW); registered только на internal mux (НЕ на external TLS — W1.2-14)
- [ ] **kacho-api-gateway middleware**: `AuthzMiddleware.AsInvalidator()` exposing `InvalidateSubject(subject) int` + `Invalidate()` (через decisionCache); unit-tests
- [ ] **kacho-api-gateway main wiring**: registration на internal listener + poll-loop watcher → 30s safety-net interval (W1.2-19)
- [ ] **kacho-api-gateway observability**: histogram metric `apigw.authz.cache.invalidate.entries`
      (labels: `event_type`, `subject_type`) — записывает count entries, dropped'нутых каждым
      `InvalidateSubject` call. p50/p99 экспортируются в Prometheus/VictoriaMetrics. Цель —
      сделать over-invalidation thrash видимым до prod (если p99 entries-dropped > 100,
      значит cache-key cardinality слишком высока → triggered cache-warm-up storm). Smoke-check
      в W1.2-11 / W1.2-15 — metric инкрементнут на ожидаемое значение.
- [ ] **RED phase**: integration-тесты §6.1-6.6 написаны и закоммичены ДО impl; CI красный по этим тестам; RED-evidence в PR-описании
- [ ] **GREEN phase**: реализация доводит все сценарии §6.1-6.6 до зелёного
- [ ] **Concurrent race-test** (W1.2-17) — без него merge запрещён (запрет #10)
- [ ] **End-to-end newman** — **NEW** case `AUTHZ-REVOKE-ENFORCED-A-INV` добавлен в
      `project/kacho-iam/tests/newman/cases/authz-deny.py` (case не существует на main
      2026-05-23 — verified `grep "REVOKE-ENFORCED"` = 0 матчей); RED-first прогон до impl;
      GREEN после landing migration 0023 + drainer + gateway endpoint (latency revoke→DENY ≤ 1s
      измерена через `tests/newman/run.sh` timing); RED→GREEN evidence в PR-описании
- [ ] **CI green** во всех трёх репо; cross-repo build OK через `replace ../`
- [ ] **PR-set merged** в order: kacho-proto → kacho-api-gateway → kacho-iam
- [ ] **Vault обновлён**:
  - [ ] `obsidian/kacho/edges/iam-to-openfga-grant-write.md` — добавить запись в "История": "2026-XX-XX (W1.2): push-drain subject_change_outbox через generic Drainer; per-subject invalidate; poll-loop → safety net (30s)"
  - [ ] `obsidian/kacho/edges/api-gateway-to-iam-subject-change.md` — обновить (push direction теперь iam→gw, не gw→iam poll); добавить новый edge `iam-to-apigateway-cache-invalidate.md` (NEW reverse edge)
  - [ ] `obsidian/kacho/packages/corelib-outbox-drainer.md` — обновить "Imported by": добавить `kacho-iam/internal/clients/subject_change_applier.go` (W1.2)
  - [ ] `obsidian/kacho/packages/api-gateway-middleware-authz.md` — обновить (new method `AsInvalidator()`)
  - [ ] `obsidian/kacho/rpc/api-gateway-internal-authz-cache-service.md` (NEW) — новый RPC service для internal cache control
  - [ ] `obsidian/kacho/resources/iam-subject-change-event.md` (NEW) — новый ресурс-описание (table + event_type table)
  - [ ] `obsidian/kacho/KAC/KAC-138.md` (создать) — trail + PR-ссылки + ✅ acceptance checklist
- [ ] **YouTrack KAC-138 W1.2 subtask** (create on impl-start):
  - [ ] переведён `To do` → `In Progress` на старте
  - [ ] PR-ссылки прикреплены комментарием (одна на каждый из 3 затронутых репо)
  - [ ] переведён `In Progress` → `Test` → `Done` по merge + smoke pass
- [ ] **Wave-1 tracker** `2026-05-23-iam-prod-ready-wave1.md` обновлён: W1.2 row → ✅ done + дата + PR-ссылки

---

## 8. Open questions (DECISION-NEEDED) — нужно разрешить до старта impl

| ID | Вопрос | Рекомендация автора |
|---|---|---|
| **OQ-W1.2-1** | Endpoint для invalidate — gRPC `InternalAuthzCacheService` (через internal mTLS port 9091) **vs** REST `POST /internal/v1/authz-cache:invalidate`? | **gRPC** (preferred per master plan OQ-W1-3). Internal mTLS на port 9091 уже существует; gRPC даёт типизированный контракт + lower latency; REST не нужен (consumer — kacho-iam internal, не tooling/UI). REST-вариант — out of scope. |
| **OQ-W1.2-2** | W1.2 эмитит subject_change ТОЛЬКО на revoke-paths **vs** также на grant-paths (binding_grant, jit_grant, bg_grant)? | **Только revoke в W1.2**. Grant-path не требует invalidate ALLOW-кэша (новый grant — впервые ALLOW, кэша ещё нет). Self-flush на mutation (existing `MaybeFlushOnMutation`) покрывает request-path replica. Grant emit — backlog ticket для KAC-139 (если возникнет cache-staleness на pending → granted transitions). |
| **OQ-W1.2-3** | Per-resource invalidate (subject + resource_type + resource_id) — реализовать в W1.2 **vs** MVP only-per-subject? | **MVP only-per-subject** для W1.2. resource_type/resource_id колонки добавляем (для future), но gateway-side игнорирует. Over-invalidate same subject's unrelated resources — небольшая cache-warmup цена, безопасна. Per-resource — KAC-140 backlog (cache-hit-rate проксирующий показатель). |
| **OQ-W1.2-4** | FGA-prefix mapping (`usr_X → user:usr_X`) — inline в applier **vs** через shared `kacho-corelib/iam`-helper? | **Inline в applier** для W1.2 (3 префикса, малая таблица). Move в corelib — когда понадобится second consumer (W3-ticker). Документировано в коде. |
| **OQ-W1.2-5** | Удалить ли WS-2.3 poll-loop watcher полностью **vs** оставить как safety net? | **Оставить как safety net (30s интервал)**. Push-drainer failure-mode (crash, OOM, network partition iam↔gateway): без poll-loop стенки запахнут на bind-revoke до restart drainer. Poll-loop с 30s интервал — приемлемая degradation upper-bound. Удалить позже когда drainer уйдёт в production-mature state (Wave 3 finalize). |
| **OQ-W1.2-6** | Drainer wiring location: kacho-iam main **vs** отдельный subprocess **vs** новый sidecar deployment? | **kacho-iam main goroutine** (parity with W1.1 FGA-drainer). HA через replica-count (existing CAS-claim drainer). Sidecar/separate deploy — premature, добавляет infra-сложность без win. |
| **OQ-W1.2-7** | Drainer apply-target (api-gateway): single instance **vs** все replicas (fanout)? | **Single instance** (DNS-based service-discovery → load-balanced single connection per drainer call). Решение принято acceptance-reviewer'ом: §0 latency promise **downgraded** с "< 1s on any gateway replica" на **"≥ 1 replica converges < 1s, all HA-replicas converge ≤ 30s"** (push-path для одной replica + safety-net poll-loop для остальных). Fanout через DNS A-records/headless-service отвергнут — overcomplexity для kind-deploy без обоснованного productivity-выигрыша. См. §0 promise + W1.2-15 test. |
| **OQ-W1.2-8** | `notified_at` column (legacy WS-2.3) — DROP в миграции 0023 **vs** оставить unused? | **Оставить unused** в W1.2 (запрет #5 spirit: безопасный additive migration; field NULL у новых rows тоже допустим). DROP — KAC-141 backlog после Wave 3, когда вся poll-loop инфра ушла. |
| **OQ-W1.2-9** | `kacho_iam.subject_change_outbox` — добавить ли индекс на `(subject_id, sent_at) WHERE sent_at IS NULL` для drainer-claim'а? | **Нет в W1.2 MVP**. Существующий `subject_change_pending_v2_idx (created_at) WHERE sent_at IS NULL` достаточен для FIFO claim. Subject_id-индекс — premature; добавим если EXPLAIN покажет seq-scan в production. |
| **OQ-W1.2-10** | Если api-gateway listener в DNS отсутствует (e.g. dev без api-gateway) — drainer должен skip-emit-loop или fail-loud? | **Fail transient + retry с exp backoff** (drainer default). Operator решает: либо up'ает gateway, либо ставит drainer pause через config-flag. fail-loud на init — нет (drainer запускается в errgroup-горутине, не падая до конца retry budget'а). |

> **Ответы на эти OQ — за `acceptance-reviewer`** (sign-off либо запрос изменений). Без явного
> разрешения OQ-W1.2-1, 5, 7 — impl не стартует (от них зависит публичное API).

---

## 9. Out of scope (явно — оставляем на follow-up chunks)

| Что | Куда |
|---|---|
| Перевод sync `WriteTuples` из `AccessBinding.Create` на запись в `fga_outbox` | **W1.5 Chunk 1** finding #16 |
| Перевод sync `DeleteTuples` из `AccessBinding.Delete` на запись в `fga_outbox` | **W1.5** finding #8 |
| JIT auto-grant запись в `fga_outbox` | **W1.5** finding #50 |
| JIT approve/expiry grant/revoke | **W1.5** finding #51 |
| BreakGlass.ApproveB запись cluster_admin_grants + `fga_outbox` | **W1.5** finding #52 |
| Per-resource cache invalidate (subject + resource scope) | KAC-140 backlog (post-W1, cache-hit-rate driven) |
| FGA prefix mapping в corelib helper | KAC-? backlog (3rd consumer trigger) |
| Удаление WS-2.3 poll-loop полностью | Wave 3 finalize (после maturity proof drainer'а) |
| Удаление `notified_at` legacy column | KAC-141 backlog |
| Gateway authz-middleware fail-closed enable | **W1.3** |
| Principal propagation cross-service | **W1.4** |
| Grant-side subject_change emit (binding_grant / jit_grant / bg_grant) | KAC-139 backlog (cache-staleness on pending→granted) |
| Group-membership change emit (`group_member_change` event type — резервирован) | будущий chunk (когда group-membership resolver введён) |

---

## 10. Traceability — какие findings разблокирует / закрывает W1.2

W1.2 **не закрывает findings** из `2026-05-21-iam-authz-review-remediation-plan.md` напрямую,
но **закрывает root-cause cache-staleness** на revoke flows, который скрыт за множеством authz-deny
test failures:

| Finding | Описание | Связь с W1.2 |
|---|---|---|
| #8 | `AccessBinding.Delete` — sync `DeleteTuples` неполный по scope-комбинациям | W1.5 (sync→outbox); W1.2 обеспечивает cache invalidate синхронно с DB-delete tx commit |
| #16 | `AccessBinding.Create` split-brain DB/FGA | W1.5 закроет; W1.2 — emit `binding_grant` (опц.) для consistency |
| #50/#51/#52 | JIT/BG не пишут в FGA | W1.5 закроет grant; W1.2 — emit revoke (DB-update + cache-invalidate) atomically |

**Прямой effect W1.2**:
- **NEW** newman case `authz-deny.py::AUTHZ-REVOKE-ENFORCED-A-INV` (case **не существует** на
  main 2026-05-23 — verified `grep "REVOKE-ENFORCED" project/kacho-iam/tests/newman/cases/authz-deny.py`
  = 0 матчей; добавляется как RED-first в W1.2 PR; RED на initial-run из-за отсутствия push-drain;
  GREEN после landing migration 0023 + drainer + gateway endpoint).
- Per-subject invalidate (instead of whole-cache flush) — cache-hit-rate up (ожидаемая
  productivity-метрика на dashboard'е, не gated в DoD).
- HA gateway-cluster: каждый replica сходится за < 1s после revoke (push) вместо 2-30s (poll-staleness).

**Newman-effect W1.2 в одиночку**: 1 **новый** case добавляется и переводится RED→GREEN
(`AUTHZ-REVOKE-ENFORCED-A-INV`); coverage grows by +1. Другие existing failures — emergent
в W1.5/W1.6. Если на dev-стенде в момент проведения W1.2 уже merge'нут W1.5 (sync writes → fga_outbox) —
ожидаемый emergent effect может быть выше; измерять через `tests/newman/run.sh && coverage.py`.

---

## 11. Ссылки

- Workspace правила: `../../CLAUDE.md` (запреты, vault, corelib reuse)
- IAM-specific: `../../project/kacho-iam/CLAUDE.md`
- Master plan: `../superpowers/plans/2026-05-23-iam-prod-ready-master.md` Wave 1
- Wave 1 plan: `../superpowers/plans/2026-05-23-iam-prod-ready-wave1.md` §W1.2
- W1.1 acceptance (drainer foundation): `sub-phase-W1.1-fga-outbox-drainer-acceptance.md`
- E3 spec (источник `subject_change_outbox`): `sub-phase-2.0-iam-E3-openfga-rebac-acceptance.md` §4.2
- Existing migration: `project/kacho-iam/internal/migrations/0002_fga_outbox.sql`
- Existing writer: `project/kacho-iam/internal/repo/kacho/pg/access_binding_repo.go:339-352` (`EmitSubjectChange`)
- Existing AccessBinding emit-sites: `project/kacho-iam/internal/apps/kacho/api/access_binding/{create,delete}.go`
- Existing WS-2.3 poll-loop (to be downgraded to safety net): `project/kacho-api-gateway/internal/watcher/subject_change_watcher.go`
- Existing AuthzMW cache (canonical refs):
  `project/kacho-api-gateway/internal/middleware/authz.go:246` — `AuthzMiddleware.InvalidateCache()` (whole-cache flush; current WS-2.3 callsite);
  `project/kacho-api-gateway/internal/middleware/authz.go:941` — `decisionCache.InvalidateSubject(subject) int` (per-subject; W1.2 new callsite for push-drain)
- Existing PollSubjectChanges client/server: `project/kacho-api-gateway/internal/clients/subject_change_client.go` + `project/kacho-iam/internal/apps/kacho/api/internal_iam/handler.go:126+`
- Generic Drainer (reused unchanged from W1.1): `project/kacho-corelib/outbox/drainer/`
- Vault — existing FGA-write edge: `obsidian/kacho/edges/iam-to-openfga-grant-write.md`
- Vault — existing api-gateway↔iam subject-change edge: `obsidian/kacho/edges/api-gateway-to-iam-subject-change.md`
- Vault — drainer package: `obsidian/kacho/packages/corelib-outbox-drainer.md`
- Remediation findings источник: `../superpowers/plans/2026-05-21-iam-authz-review-remediation-plan.md`
