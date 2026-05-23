# Sub-phase W1.1 — `fga_outbox` drainer (kacho-corelib) — Acceptance

> **Status**: ✅ **APPROVED** by `acceptance-reviewer` 2026-05-23 (gate per CLAUDE.md §Запреты #1). All 7 OQ defaults accepted. 6 minor advisory improvements (non-blocking) tracked in implementation phase. Ready for RED integration tests.
> **Date**: 2026-05-23
> **YouTrack**: KAC-136 W1.1 (subtask of [KAC-136](https://prorobotech.youtrack.cloud/issue/KAC-136), child of epic [KAC-134](https://prorobotech.youtrack.cloud/issue/KAC-134) "kacho-iam → production-ready").
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer` (gate per запрет #1, workspace `CLAUDE.md`).
> **Target repos**:
>   - **Primary**: `PRO-Robotech/kacho-corelib` — new sub-package `outbox/drainer/` (extends existing `outbox/` writer-side).
>   - **First concrete consumer (in scope)**: `PRO-Robotech/kacho-iam` — `internal/clients/fga_applier.go` + wiring in `cmd/kacho-iam/main.go`.
> **Branch (all repos)**: `KAC-136`.
> **Parent epic plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-master.md` (Wave 1, foundational chunk).
> **Wave plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-wave1.md` §W1.1.

---

## 0. Преамбула — что эта sub-итерация (précis)

W1.1 — **первый, foundational чанк Wave 1**. Поставляет универсальный, переиспользуемый
**outbox-drainer** в `kacho-corelib/outbox/drainer/`, расширяющий уже существующий
writer-side `kacho-corelib/outbox/` (Emit + Writer + Event). Drainer слушает `LISTEN/NOTIFY`
канал Postgres, на старте дренит pending-rows (catch-up), декодирует payload и применяет к
target-системе через инжектируемую `Applier[T]`-функцию; идемпотентен; имеет exp-backoff
retry на transient errors; перевод row в terminal-состояние `sent_at IS NOT NULL` либо
`last_error` + `attempt_count` для permanent failures; graceful-shutdown по ctx.

**Первый concrete consumer в scope** — `kacho-iam` FGA-drainer: applier транслирует строку
`fga_outbox` (event_type `fga.tuple.write` | `fga.tuple.delete`, payload — FGA tuple JSON) в
`OpenFGAClient.WriteTuples` / `DeleteTuples` HTTP-call. Wiring — goroutine в
`cmd/kacho-iam/main.go` через `errgroup.Group`.

**Почему сейчас и почему foundational:** taraborn `bootstrap_admin.go` (kacho-iam) уже
**пишет** в `fga_outbox` (см. `internal/apps/kacho/seed/bootstrap_admin.go:135`), миграция
`0002_fga_outbox.sql` создала таблицу + NOTIFY-триггер `kacho_iam_fga_outbox`, но **дренера
нет** → cluster-admin tuple никогда не попадает в OpenFGA → почти каждый authz `Check` в
api-gateway и сервисах fails-because-no-tuple. Все последующие чанки W1 (W1.5 #16/#8/#50/#51/#52
— перевод sync `WriteTuples` из `AccessBinding.Create/Delete`, JIT, BreakGlass на
outbox-pattern; W1.2 — `subject_change_outbox` cache-invalidate drainer на том же generic)
опираются на этот drainer.

**W1.1 НЕ включает:**

- Перевод существующих sync `WriteTuples` в `AccessBindingService.Create/Delete` /
  JIT auto-grant / BreakGlass.ApproveB на запись через `fga_outbox` — это **W1.5**
  (findings #8/#16/#50/#51/#52). W1.1 только поставляет drainer; bootstrap-admin —
  уже-существующий writer, который начнёт реально работать.
- `subject_change_outbox` drainer для cache-invalidate на gateway — отдельный chunk
  **W1.2** (reuses W1.1 generic, отдельный acceptance-doc, отдельный applier).
- Изменения gateway authz-middleware fail-closed — **W1.3**.
- Principal propagation cross-service — **W1.4**.
- Замены fga_outbox schema (event_type `fga.tuple.write|delete`, payload-формат)
  на новый формат — W1.1 принимает схему миграции `0002` AS-IS (см. §3).

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** (workspace) — кодирование только после `acceptance-reviewer` APPROVED | данный doc — gate; статус выше `DRAFT`. |
| **Запрет #2** — НЕ упоминать "yandex" | в коде/комментариях/тестах не упоминается. |
| **Запрет #3** — НЕ ORM | только handwritten pgx + sqlc (если потребуется). Drainer использует `pgx.Conn` для `LISTEN` (dedicated connection, не из pool — `LISTEN` не выживает recycle pool-а), `pgxpool` для catch-up SELECT и UPDATE. |
| **Запрет #5** — НЕ редактировать применённую миграцию | `0002_fga_outbox.sql` (kacho-iam) **не трогаем**. Drainer работает с существующей схемой `(id bigserial PK, event_type text, payload jsonb, created_at timestamptz, sent_at timestamptz, last_error text, attempt_count int)`. Если потребуется доп-индекс — отдельный новый migration-файл (см. §3.3, маркер DECISION-NEEDED). |
| **Запрет #6** — Internal.* НЕ на external TLS endpoint | drainer — внутренняя background-goroutine процесса kacho-iam, не expose'ит gRPC/REST surface. |
| **Запрет #7** — НЕ broker | drainer = in-process LISTEN/NOTIFY + Postgres polling; никакого Kafka/NATS. |
| **Запрет #8** — DB-per-service | drainer работает с БД своего сервиса (kacho-iam → `kacho_iam`); generic-impl принимает `*pgxpool.Pool` от caller'а, не лезет cross-DB. |
| **Запрет #10** — within-service refs DB-level | drainer-claim строки (см. §4.2 «exactly-once») — атомарный `UPDATE … WHERE sent_at IS NULL RETURNING …` (CAS), либо `FOR UPDATE SKIP LOCKED` row-lock. **Никаких** software-side «SELECT pending → check → UPDATE» (TOCTOU). |
| **Запрет #11** — test-first, тесты в том же PR | W1.1 PR обязан содержать (a) RED-integration-тест на testcontainers Postgres до impl; (b) RED → GREEN пару в PR-описании; (c) минимум 1 happy + 1 negative + 1 concurrent race-тест. Newman case в W1.1 **не применим** (drainer — internal infra, не gRPC); newman-добор на end-to-end grant→Check на железе — в W1.5. |
| **CLAUDE.md §«Принцип переиспользования через kacho-corelib»** | drainer — горизонтальный cross-cutting concern, ляжет в corelib, не per-service. |
| **CLAUDE.md §«Within-service refs — DB-уровень обязателен»** | exactly-once claim — атомарный single-statement UPDATE с CAS / row-lock; concurrent-race integration-test обязателен (см. §6.3). |

---

## 2. Глоссарий

- **Outbox** — таблица в БД сервиса, в которую внутри той же транзакции, что и domain-INSERT/UPDATE, пишется событие; consumer (drainer) асинхронно читает и применяет. Гарантия — at-least-once delivery. Уже существующий kacho-corelib `outbox/` package (Emit, Writer, Event) — **writer-side**.
- **Drainer** — фоновый процесс, который читает outbox-rows и применяет к target-системе. **W1.1 поставляет именно его.**
- **Applier[T]** — caller-supplied функция `func(ctx context.Context, payload T) error`, которую drainer вызывает на каждую row. Caller предоставляет decoder `func(jsonb []byte) (T, error)` и applier. Для FGA: `T = FGAOutboxEvent { EventType string; Tuple FGATuple }`, applier вызывает `OpenFGAClient.WriteTuples`/`DeleteTuples`.
- **Idempotent apply** — applier обязан возвращать `nil` при «уже применено» (для OpenFGA: HTTP 409 на write существующего tuple, 404 на delete отсутствующего → wrap в sentinel `ErrAlreadyApplied`, drainer считает успехом и marks `sent_at`).
- **Transient error** — `context.DeadlineExceeded`, network-error, OpenFGA HTTP 5xx; drainer ретраит с exp backoff, `attempt_count++`, `last_error = err.Error()`.
- **Permanent error** — OpenFGA HTTP 4xx (кроме 409), malformed payload (decode fail), CHECK constraint mismatch; drainer marks `last_error` + `attempt_count++`, **не** marks `sent_at` (row остаётся pending, но drainer пропускает её при ретрае пока не пройдёт TTL; см. DECISION-NEEDED OQ-W1.1-4). Опционально — отдельная колонка `failed_at` (см. §3.3).
- **LISTEN/NOTIFY channel** — для kacho-iam fga_outbox: `kacho_iam_fga_outbox` (определён в trigger функции `kacho_iam.fga_outbox_notify()`, payload = `NEW.id::text`).

---

## 3. Data model — таблица `fga_outbox` (AS-IS из миграции 0002)

### 3.1 Существующая схема (НЕ трогаем — запрет #5)

```sql
CREATE TABLE kacho_iam.fga_outbox (
    id            bigserial    PRIMARY KEY,
    event_type    text         NOT NULL,
    payload       jsonb        NOT NULL,
    created_at    timestamptz  NOT NULL DEFAULT now(),
    sent_at       timestamptz,
    last_error    text,
    attempt_count integer      NOT NULL DEFAULT 0,
    CONSTRAINT fga_outbox_event_type_check
        CHECK (event_type IN ('fga.tuple.write', 'fga.tuple.delete'))
);

CREATE INDEX fga_outbox_pending_idx
    ON kacho_iam.fga_outbox (created_at) WHERE sent_at IS NULL;

CREATE OR REPLACE FUNCTION kacho_iam.fga_outbox_notify() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    PERFORM pg_notify('kacho_iam_fga_outbox', NEW.id::text);
    RETURN NEW;
END;
$fn$;

CREATE TRIGGER fga_outbox_notify_trigger
    AFTER INSERT ON kacho_iam.fga_outbox
    FOR EACH ROW EXECUTE FUNCTION kacho_iam.fga_outbox_notify();
```

### 3.2 Семантика колонок (drainer-side reading)

| Колонка | Что значит для drainer |
|---|---|
| `id` | Идентификатор row, payload NOTIFY (caller строит `claim` query по нему). |
| `event_type` | `fga.tuple.write` → applier вызывает `WriteTuples`; `fga.tuple.delete` → `DeleteTuples`. |
| `payload` (JSONB) | Десериализуется drainer'ом в caller-provided тип `T`. Для FGA: `{"user": "user:usr…", "relation": "system_admin", "object": "cluster:default"}`. |
| `created_at` | Используется для ordering (FIFO в пределах "одной волны" NOTIFY) и для TTL-фильтра при catch-up. |
| `sent_at` | NULL → pending; NOT NULL → успешно применено, не трогать. Drainer mark'ит `sent_at = now()` атомарно с claim. |
| `last_error` | Последняя ошибка applier-а (для observability и debugging). Перезаписывается на каждом attempt. |
| `attempt_count` | Инкремент на каждом attempt (успешном или неудачном). При `attempt_count >= max_attempts` (default 10, configurable) drainer перестаёт ретраить (см. §4.4 DLQ-policy). |

### 3.3 Возможные дополнения схемы (DECISION-NEEDED)

См. §«Open questions» OQ-W1.1-3: **нужна ли отдельная колонка `failed_at`** (permanent failure marker) для отличия «retry-loop в процессе» от «отравленная row»? Рекомендация — **НЕТ для W1.1**, обходимся `attempt_count >= max_attempts`-гейтом + ORDER BY на catch-up игнорирует rows с `attempt_count >= max_attempts`. Поднимать тему в W1.2, если опыт продакшна покажет нужду. (Если решено иначе — отдельный migration-файл `0023_fga_outbox_failed_at.sql` в kacho-iam, в scope W1.1.)

---

## 4. API / interface contract — kacho-corelib/outbox/drainer

### 4.1 Public Go API (sketch)

```go
// Package drainer реализует универсальный outbox-drainer для Kachō outbox-pattern.
// Слушает LISTEN/NOTIFY-канал Postgres, дренит pending rows на старте,
// применяет каждую row через caller-supplied Applier[T], атомарно mark'ит
// sent_at. Идемпотентен, retry с exp-backoff, graceful-shutdown по ctx.
package drainer

import (
    "context"
    "time"

    "github.com/jackc/pgx/v5/pgxpool"
)

// Config — параметры конкретного экземпляра drainer-а.
type Config struct {
    // Table — полное имя outbox-таблицы (`<schema>.<table>`), e.g. "kacho_iam.fga_outbox".
    Table string
    // Channel — имя LISTEN-канала, e.g. "kacho_iam_fga_outbox".
    Channel string
    // BatchSize — сколько rows клейм'ить за один catch-up SELECT (default 32).
    BatchSize int
    // PollFallback — интервал poll'а на случай missed NOTIFY (default 30s).
    PollFallback time.Duration
    // MaxAttempts — отметка «poisoned», после которой drainer перестаёт ретраить
    //   (default 10). Permanent-error → mark last_error, drainer пропускает.
    MaxAttempts int
    // BackoffMin/BackoffMax — exp-backoff bounds (default 1s..30s).
    BackoffMin, BackoffMax time.Duration
}

// Decoder[T] — превращает payload JSONB в типизированный T.
// Ошибка decoder-а → permanent error (poisoned row).
type Decoder[T any] func(payload []byte) (T, error)

// Applier[T] — применяет T к target-системе.
// Возвращает nil → success (drainer mark'ит sent_at).
// Возвращает ErrAlreadyApplied → idempotent success (drainer mark'ит sent_at).
// Возвращает любую другую error → transient (retry с exp backoff)
//   ИЛИ permanent (если errors.Is(err, ErrPermanent)).
type Applier[T any] func(ctx context.Context, eventType string, payload T) error

// ErrAlreadyApplied — applier возвращает, когда target-система сообщила «уже есть»
//   (для OpenFGA: HTTP 409 на write existing tuple; HTTP 404 на delete missing tuple).
//   Drainer трактует как success.
var ErrAlreadyApplied = errors.New("drainer: target reports already-applied (idempotent)")

// ErrPermanent — applier wrap'ит в это, если retry бессмыслен (HTTP 4xx не-409,
//   malformed FGA-DSL, etc). Drainer mark'ит last_error и пропускает.
var ErrPermanent = errors.New("drainer: permanent error, no retry")

// Drainer[T] — экземпляр drainer-а для одного outbox-table + один applier.
type Drainer[T any] struct {
    cfg     Config
    pool    *pgxpool.Pool
    decoder Decoder[T]
    applier Applier[T]
    logger  *slog.Logger
}

// New создаёт Drainer; не запускает (вызывайте Run).
func New[T any](
    pool *pgxpool.Pool,
    cfg Config,
    decoder Decoder[T],
    applier Applier[T],
    logger *slog.Logger,
) (*Drainer[T], error)

// Run — основной loop drainer-а. Блокирует до ctx.Done().
//   1) Открывает dedicated pgx.Conn (acquired из pool, hijack — НЕ из pool's recycle pool;
//      see «реализация» §4.5).
//   2) LISTEN cfg.Channel.
//   3) Stage 0: catch-up — SELECT pending rows ORDER BY created_at LIMIT cfg.BatchSize,
//      обрабатывает каждую (claim → decode → apply → mark).
//   4) Stage 1: main loop — select { ctx.Done(); pgx-notification; tick(cfg.PollFallback) },
//      каждое срабатывание → handle one row (по id из payload) или batch (по poll).
//   5) При ctx.Done() — дозавершает текущий in-flight apply (с малым deadline-grace), exit.
//   6) Возвращает nil при clean shutdown, error при unrecoverable (e.g. LISTEN conn драм
//      пятого attempt'а подряд — fail-closed для caller'а решать что делать).
func (d *Drainer[T]) Run(ctx context.Context) error
```

### 4.2 Atomic claim — exactly-once semantics

Drainer на каждую row выполняет **single-statement** атомарный claim:

```sql
UPDATE kacho_iam.fga_outbox
   SET sent_at       = now(),
       attempt_count = attempt_count + 1
 WHERE id = $1
   AND sent_at IS NULL
   AND attempt_count < $2
RETURNING id, event_type, payload, attempt_count;
```

- 0 rows из RETURNING → row либо уже `sent_at NOT NULL` (другая реплика drainer-а выиграла), либо
  `attempt_count >= MaxAttempts` (poisoned). Drainer log'ит DEBUG и переходит к следующей.
- 1 row → claim successful, drainer применяет и при ошибке транзитной ретраит **с тем же
  претендованным id** (sent_at уже выставлен — следующая попытка должна **сбросить** sent_at
  обратно? или клеймить заново с conditional rollback?). См. §4.3.

> **Альтернатива**: `SELECT … FOR UPDATE SKIP LOCKED LIMIT 1` + `UPDATE … RETURNING`. Эквивалентно по race-safety; chose CAS-UPDATE для single-statement simplicity. Race-test (§6.3) подтверждает.

### 4.3 Retry policy

Drainer **не** mark'ит `sent_at` до подтверждения success applier-ом. Шаги:

1. **Pre-attempt claim**: атомарный `UPDATE … SET attempt_count = attempt_count + 1, last_attempt_at = now() WHERE id = $1 AND sent_at IS NULL AND attempt_count < $2 RETURNING ...`. (Если нужно — добавить колонку `last_attempt_at timestamptz`; см. OQ-W1.1-3.)
2. **Apply**: вызвать `applier(ctx, eventType, decoded)`.
3. **На success (nil или ErrAlreadyApplied)**: `UPDATE fga_outbox SET sent_at = now(), last_error = NULL WHERE id = $1`.
4. **На transient error**: `UPDATE fga_outbox SET last_error = $err WHERE id = $1` (attempt_count уже инкрементнут). Ждать `min(BackoffMin * 2^(attempt-1), BackoffMax)` → retry следующей итерации loop'а (или dedicated retry-tick).
5. **На permanent error (errors.Is(err, ErrPermanent) || decoder-fail)**: `UPDATE fga_outbox SET last_error = $err, attempt_count = MaxAttempts WHERE id = $1` (force-poison, drainer больше не возьмёт).

> **Альтернативный подход**: не инкрементировать attempt_count в pre-claim, а делать одной транзакцией post-apply. Drainer-design choice; ключевое — что **на одну привлечённую attempt — ровно один пройденный apply**, и retry виден в `attempt_count`. См. OQ-W1.1-2.

### 4.4 Concrete FGAApplier (kacho-iam side, in scope)

```go
// kacho-iam/internal/clients/fga_applier.go (NEW)

package clients

import (
    "context"
    "encoding/json"
    "errors"

    "github.com/PRO-Robotech/kacho-corelib/outbox/drainer"
)

// FGAOutboxEvent — типизированный payload row из kacho_iam.fga_outbox.
// Соответствует записям из bootstrap_admin.go и (после W1.5) AccessBinding.Create/Delete.
type FGAOutboxEvent struct {
    User     string `json:"user"`
    Relation string `json:"relation"`
    Object   string `json:"object"`
}

// DecodeFGAOutbox — drainer.Decoder[FGAOutboxEvent].
func DecodeFGAOutbox(payload []byte) (FGAOutboxEvent, error) {
    var e FGAOutboxEvent
    if err := json.Unmarshal(payload, &e); err != nil {
        return e, errors.Join(drainer.ErrPermanent, err)
    }
    if e.User == "" || e.Relation == "" || e.Object == "" {
        return e, errors.Join(drainer.ErrPermanent, errors.New("fga payload: missing user/relation/object"))
    }
    return e, nil
}

// NewFGAApplier — фабрика drainer.Applier[FGAOutboxEvent] поверх OpenFGAClient.
func NewFGAApplier(c OpenFGAClient) drainer.Applier[FGAOutboxEvent] {
    return func(ctx context.Context, eventType string, e FGAOutboxEvent) error {
        tup := []FGATuple{{User: e.User, Relation: e.Relation, Object: e.Object}}
        switch eventType {
        case "fga.tuple.write":
            err := c.WriteTuples(ctx, tup)
            if isOpenFGAConflict(err) {
                return drainer.ErrAlreadyApplied
            }
            return err
        case "fga.tuple.delete":
            err := c.DeleteTuples(ctx, tup)
            if isOpenFGAMissing(err) {
                return drainer.ErrAlreadyApplied
            }
            return err
        default:
            return errors.Join(drainer.ErrPermanent,
                fmt.Errorf("unknown event_type %q", eventType))
        }
    }
}
```

### 4.5 Wiring (kacho-iam main.go, in scope)

```go
// cmd/kacho-iam/main.go (extension)

g.Go(func() error {
    d, err := drainer.New[clients.FGAOutboxEvent](
        pool,
        drainer.Config{
            Table:        "kacho_iam.fga_outbox",
            Channel:      "kacho_iam_fga_outbox",
            BatchSize:    32,
            PollFallback: 30 * time.Second,
            MaxAttempts:  10,
            BackoffMin:   1 * time.Second,
            BackoffMax:   30 * time.Second,
        },
        clients.DecodeFGAOutbox,
        clients.NewFGAApplier(openfgaClient),
        logger.With("component", "fga-outbox-drainer"),
    )
    if err != nil {
        return fmt.Errorf("fga drainer: init: %w", err)
    }
    return d.Run(gctx)
})
```

---

## 5. Test discipline (запрет #11) — RED first

PR обязан содержать **integration-тест на testcontainers Postgres**, написанный
ДО кода drainer'а; в PR-описании показать пару `RED (testing-only commit) → GREEN`.
Тест поднимает Postgres-контейнер, накатывает миграции kacho-iam (включая 0002), создаёт
**fake-Applier** (in-memory map с record/replay seam'ом для injection 409/permanent
errors/delay) и проверяет сценарии §6. **Реальный OpenFGA-контейнер в W1.1 — out of
scope** (см. §«Out of scope»); FGAApplier-юнит-тест через `OpenFGAStubClient` (он уже есть)
покрывает 409/missing-mapping. Сквозной end-to-end на железе через api-gateway → kacho-iam →
OpenFGA — в W1.5/W1.6 после того, как production write-path (AccessBinding.Create) реально
будет писать в outbox.

---

## 6. Сценарии (Given-When-Then) — основа интеграционных тестов

### 6.1 Functional happy paths

#### Сценарий 6.1.1 — Single INSERT → applier invoked within ~50ms via NOTIFY

**ID**: W1.1-01

**Given** Postgres testcontainer + миграции kacho-iam применены, fake-Applier-recorder инициализирован, drainer запущен goroutine'ой 100ms назад (LISTEN активен)
**And** `fga_outbox` пуст

**When** тест выполняет
```sql
INSERT INTO kacho_iam.fga_outbox (event_type, payload)
VALUES ('fga.tuple.write', '{"user":"user:usr01","relation":"system_admin","object":"cluster:default"}'::jsonb);
```

**Then** в течение **500ms** (для CI-stability; на dev ~50ms) fake-Applier-recorder содержит ровно одну запись `{eventType: "fga.tuple.write", payload: {User:"user:usr01", Relation:"system_admin", Object:"cluster:default"}}`
**And** row помечена `sent_at IS NOT NULL`, `last_error IS NULL`, `attempt_count = 1`

---

#### Сценарий 6.1.2 — Startup catch-up: 5 pending rows перед запуском drainer'а

**ID**: W1.1-02

**Given** Postgres-контейнер + миграции применены, drainer **ещё не запущен**
**And** в `fga_outbox` уже 5 pending rows (`sent_at IS NULL`), вставлены до старта drainer-а (NOTIFY на них не сработает для нашего listener-а)

**When** drainer запускается

**Then** в течение **2 секунд** (catch-up + ordering by created_at) fake-Applier-recorder содержит 5 записей в порядке `created_at ASC`
**And** все 5 rows помечены `sent_at IS NOT NULL`

---

#### Сценарий 6.1.3 — Delete event applied

**ID**: W1.1-03

**Given** drainer запущен, fake-Applier поддерживает delete-mode

**When** INSERT row `event_type='fga.tuple.delete'`, payload `{"user":"user:usr01","relation":"system_admin","object":"cluster:default"}`

**Then** applier получает вызов с `eventType="fga.tuple.delete"`, payload расшифрован
**And** row помечена `sent_at IS NOT NULL`

---

#### Сценарий 6.1.4 — Idempotent ErrAlreadyApplied → success path

**ID**: W1.1-04

**Given** fake-Applier настроен возвращать `drainer.ErrAlreadyApplied` (моделирует OpenFGA HTTP 409)

**When** INSERT row `event_type='fga.tuple.write'`

**Then** row помечена `sent_at IS NOT NULL`, `last_error IS NULL` (как при успехе)
**And** в логах drainer-а — DEBUG-запись `"target reports already-applied"` (для observability)

---

### 6.2 Negative paths

#### Сценарий 6.2.1 — Transient error → exp backoff retry → eventual success

**ID**: W1.1-05

**Given** fake-Applier настроен возвращать `context.DeadlineExceeded` на первые 2 attempts, `nil` на третий (моделирует transient network error)
**And** `BackoffMin=100ms`, `BackoffMax=500ms` (для теста)

**When** INSERT row

**Then** в течение **2 секунд** fake-Applier зарегистрировал 3 вызова
**And** row помечена `sent_at IS NOT NULL`, `attempt_count = 3`, `last_error IS NULL` (последний reset)
**And** интервалы между attempts ≈ 100ms, 200ms (exp backoff)

---

#### Сценарий 6.2.2 — Permanent error → mark + skip + continue с следующей row

**ID**: W1.1-06

**Given** fake-Applier настроен возвращать `errors.Join(drainer.ErrPermanent, errors.New("bad payload"))` на конкретный payload (e.g. user starts with "BAD:")
**And** другие payload-ы возвращают `nil`

**When** INSERT row A (poisoned), затем INSERT row B (normal) с интервалом 100ms

**Then** row A помечена `attempt_count >= MaxAttempts` (force-poisoned), `last_error LIKE '%bad payload%'`, `sent_at IS NULL` (permanently failed)
**And** row B помечена `sent_at IS NOT NULL` (drainer не застрял на row A)
**And** в логах — WARN на A, DEBUG на B

---

#### Сценарий 6.2.3 — Decoder-fail (malformed JSON payload) → permanent error

**ID**: W1.1-07

**Given** drainer запущен с `DecodeFGAOutbox` decoder-ом

**When** прямой INSERT row с payload `'{"missing_required_field": true}'::jsonb` (decoder вернёт ErrPermanent с "missing user/relation/object")

**Then** row помечена `attempt_count = MaxAttempts`, `last_error LIKE '%missing user/relation/object%'`
**And** drainer продолжает работу (не падает)

---

#### Сценарий 6.2.4 — Postgres connection drop mid-listen → reconnect + catch-up

**ID**: W1.1-08

**Given** drainer запущен, processed 1 row успешно
**And** в `fga_outbox` есть 1 pending row (ещё не процессилась)

**When** тест убивает LISTEN-connection drainer-а (`SELECT pg_terminate_backend(...)` по pid LISTEN-conn-а)

**Then** в течение **5 секунд** drainer переоткрыл connection, выполнил catch-up SELECT, обработал pending row
**And** row помечена `sent_at IS NOT NULL`

---

### 6.3 Concurrency

#### Сценарий 6.3.1 — Two concurrent INSERTs → ровно один apply per row (no double-apply)

**ID**: W1.1-09

**Given** drainer запущен
**And** fake-Applier — атомарный counter, инкрементирующий per-(user, relation, object)-ключ

**When** 2 goroutine'ы параллельно INSERTят 10 rows каждая с разными payload-ами (всего 20 уникальных rows, no payload collisions)

**Then** в течение **3 секунд** все 20 rows помечены `sent_at IS NOT NULL`
**And** fake-Applier-counter показывает ровно 20 уникальных apply (no doubles, no misses)

---

#### Сценарий 6.3.2 — Two drainer instances (HA-mini) → каждая row обработана ровно один раз

**ID**: W1.1-10

**Given** 2 экземпляра drainer-а (моделирует kacho-iam 2 replicas) на одной БД с разными pool-ами
**And** fake-Applier shared (через mu+map), инкрементирует counter per row.id

**When** тест INSERT'ит 20 rows одной волной

**Then** в течение **3 секунд** все 20 rows помечены `sent_at IS NOT NULL`
**And** counter показывает ровно 20 (не 40 — exactly-once across replicas)
**And** оба drainer-а отработали часть rows (load spread, ни один не idle — verified by per-drainer counter)

> Гарантия — атомарный CAS-claim `UPDATE … WHERE sent_at IS NULL RETURNING …` (см. §4.2): второй drainer не получит RETURNING.

---

### 6.4 Graceful shutdown

#### Сценарий 6.4.1 — ctx.Cancel в момент in-flight apply → finishes row + clean exit

**ID**: W1.1-11

**Given** drainer запущен, fake-Applier настроен sleep 500ms перед возвратом nil
**And** INSERT row → applier начал работу

**When** через 100ms после INSERT-а тест вызывает `ctxCancel()`

**Then** в течение **2 секунд** `Run()` возвращает nil (clean exit)
**And** row помечена `sent_at IS NOT NULL` (in-flight apply дозавершился)

---

#### Сценарий 6.4.2 — ctx.Cancel при пустой очереди → немедленный exit (< 500ms)

**ID**: W1.1-12

**Given** drainer запущен, очередь пуста, idle 200ms

**When** ctx cancelled

**Then** `Run()` возвращает nil в течение **500ms**

---

### 6.5 Edge cases

#### Сценарий 6.5.1 — Idle drainer без CPU-burn

**ID**: W1.1-13

**Given** drainer запущен, очередь пуста, нет NOTIFY 5 секунд подряд

**When** тест наблюдает CPU-usage процесса (или count loop-iterations через testing-hook counter)

**Then** drainer не делает > 1 SELECT/sec (poll-fallback `PollFallback=30s` → ровно 0 poll'ов за 5s, только NOTIFY-listen + ctx-tick)
**And** loop-iteration-counter ≤ 5 за 5 секунд (одна iteration per tick)

---

#### Сценарий 6.5.2 — Re-apply same row after restart (idempotency защита)

**ID**: W1.1-14

**Given** drainer 1 запустился, processed row R с `sent_at = T`, exited
**And** drainer 2 запускается заново с теми же миграциями + БД

**When** ничего не INSERTится

**Then** drainer 2 catch-up SELECT не возвращает row R (`WHERE sent_at IS NULL` фильтр)
**And** fake-Applier не вызывается на R

---

#### Сценарий 6.5.3 — Missed NOTIFY (drainer был offline 1 минуту) → poll-fallback catch-up

**ID**: W1.1-15

**Given** drainer запущен, затем `ctxCancel` (offline state), `fga_outbox` получает 3 INSERT-а (NOTIFY ушли в void), затем drainer перезапущен с теми же config

**When** drainer стартует

**Then** в течение **2 секунд** (startup catch-up) все 3 rows применены
**And** poll-fallback timer **не** срабатывает в этом интервале (catch-up уже отработал на startup)

---

## 7. Definition of Done

- [ ] `acceptance-reviewer` ✅ APPROVED данного doc
- [ ] Branch `KAC-136` создан в `kacho-corelib` + `kacho-iam`
- [ ] **RED phase**: integration-тест `kacho-corelib/outbox/drainer/drainer_integration_test.go` написан и закоммичен **до** impl; CI на этом коммите красный по drainer-тесту (compile-fail или test-fail); RED-evidence в PR-описании
- [ ] **GREEN phase**: реализация `kacho-corelib/outbox/drainer/{drainer.go, applier.go, decoder.go, doc.go}` доводит все сценарии §6.1-6.5 до зелёного
- [ ] Concrete FGAApplier в `kacho-iam/internal/clients/fga_applier.go` + decoder
- [ ] Wiring в `kacho-iam/cmd/kacho-iam/main.go` (goroutine в errgroup, graceful shutdown через ctx)
- [ ] Integration-test покрывает все 15 сценариев из §6 (W1.1-01..W1.1-15)
- [ ] Concurrent race-test (Сценарий 6.3.1 и 6.3.2) **обязателен** — без него merge запрещён (запрет #10 + §«Within-service refs DB-level»)
- [ ] kacho-iam wiring smoke-test: запуск контейнера локально с pgConn + `OpenFGAStubClient` (stub из `clients/openfga_client.go`), bootstrap-admin при старте → 1 row в `fga_outbox` → в течение 5s row помечена sent_at NOT NULL → stub-FGA содержит tuple
- [ ] CI green в kacho-corelib (unit + integration) + kacho-iam (drainer-wiring integration test)
- [ ] PR в kacho-corelib merged → tag bump (если есть versioning), kacho-iam `replace ../kacho-corelib` подхватывает (или pin до feature-branch до merge-а corelib)
- [ ] PR в kacho-iam merged
- [ ] Vault обновлён:
  - [ ] `obsidian/kacho/packages/corelib-outbox-drainer.md` — новая узкая запись (1-3KB) на новый sub-package
  - [ ] `obsidian/kacho/packages/corelib-outbox.md` — обновить "See also" ссылкой на drainer
  - [ ] `obsidian/kacho/edges/iam-to-openfga-grant-write.md` — добавить запись в "История": "2026-XX-XX (W1.1): bootstrap-admin grant теперь дренится через corelib drainer; sync writes в AccessBinding всё ещё на месте — W1.5"
  - [ ] `obsidian/kacho/KAC/KAC-136.md` (создать) — trail + PR ссылки + ✅ acceptance checklist
- [ ] YouTrack `KAC-136 W1.1` subtask:
  - [ ] переведён в `In Progress` на старте
  - [ ] PR-ссылки прикреплены комментарием
  - [ ] переведён в `Test` → `Done` по merge + smoke-test
- [ ] Wave-1 tracker `2026-05-23-iam-prod-ready-wave1.md` обновлён: W1.1 row → ✅ done + дата

---

## 8. Open questions (DECISION-NEEDED) — нужно разрешить до старта impl

| ID | Вопрос | Рекомендация автора |
|---|---|---|
| **OQ-W1.1-1** | `kacho-corelib/outbox/` — есть writer-side (`Emit`, `Writer`, `Event`); добавлять **под-пакет** `outbox/drainer/` или класть `drainer.go` рядом? | **Под-пакет**: `outbox/drainer/`. Изолирует API (writer-only-импортёры не тянут drainer-deps), позволяет independent versioning в будущем. Имя package = `drainer`, import path — `github.com/PRO-Robotech/kacho-corelib/outbox/drainer`. |
| **OQ-W1.1-2** | Pre-claim инкремент `attempt_count` (см. §4.3 шаг 1) **vs** post-apply update одной транзакцией? | **Pre-claim**: атомарный single-statement `UPDATE … SET attempt_count = attempt_count + 1, sent_at_attempt = now() WHERE id = $1 AND sent_at IS NULL AND attempt_count < $2 RETURNING …`. Зачем — race-safe claim под двумя репликами; post-apply UPDATE добавляет `sent_at = now()` либо `last_error`. Цена — `attempt_count` инкрементнут даже если apply закрашился до response (но это и есть smysl attempt — попытка). |
| **OQ-W1.1-3** | Добавлять колонку `last_attempt_at timestamptz` и/или `failed_at timestamptz` в схему `fga_outbox`? | **NO для W1.1**: обходимся существующими `last_error` (есть) + `attempt_count >= MaxAttempts` гейтом (no failed_at нужен). Если опыт прод покажет нужду — отдельный migration в kacho-iam-wave2; не блокирует W1.1. |
| **OQ-W1.1-4** | Poisoned row policy: «force `attempt_count = MaxAttempts`» (drainer навсегда пропускает) **vs** «отдельный DLQ-table»? | **Force MaxAttempts** для W1.1. DLQ-table — overkill пока. Operator при необходимости reset вручную (`UPDATE … SET attempt_count = 0, last_error = NULL WHERE id IN (…)`). |
| **OQ-W1.1-5** | Real OpenFGA testcontainer для integration-теста (W1.1) **vs** только fake-Applier? | **Только fake-Applier для W1.1**. Реальный OpenFGA-test уже покрыт `kacho-iam/internal/clients/openfga_client_test.go` + W0.4 bootstrap-job (helm). W1.1 testит **drainer mechanics**, не FGA-wire-protocol; реальный wire — emergent в W1.5 (когда AccessBinding.Create начнёт писать в outbox). |
| **OQ-W1.1-6** | Dedicated pgx.Conn (`pool.Acquire(ctx)` + hijack) для LISTEN **vs** отдельный `pgx.Connect` (вне pool)? | **Hijack из pool**: `pool.Acquire(ctx).Hijack()` — даёт raw `*pgx.Conn` без auto-release; меньше config-duplication. Реconnect logic — caller-side: drainer ловит conn-drop, hijack новый. |
| **OQ-W1.1-7** | `BatchSize=32` на catch-up — sensible default? | Yes для W1.1. Каждая row → 1 HTTP call в OpenFGA (sequential per batch); 32 — баланс between «не залить FGA» и «catch-up прогресс виден». Configurable через Config. |

> **Ответы на эти OQ — за `acceptance-reviewer` (либо явный sign-off, либо запрос изменений).** Без явного разрешения OQ-W1.1-1, 2, 6 — impl не стартует (от них зависит публичное API).

---

## 9. Out of scope (явно — оставляем на follow-up chunks)

| Что | Куда |
|---|---|
| Перевод sync `WriteTuples` из `AccessBinding.Create` на запись в `fga_outbox` | **W1.5 Chunk 1** finding #16 |
| Перевод sync `DeleteTuples` из `AccessBinding.Delete` на запись в `fga_outbox` | **W1.5** finding #8 |
| JIT auto-grant / approve-grant запись в `fga_outbox` | **W1.5** findings #50/#51 |
| BreakGlass.ApproveB запись cluster_admin_grants + `fga_outbox` | **W1.5** finding #52 |
| `subject_change_outbox` drainer для gateway authz-cache invalidate | **W1.2** (reuse W1.1 generic с другим decoder/applier; отдельный acceptance-doc) |
| Real OpenFGA-контейнер в integration-тесте | покрыто отдельно в W0.4 (bootstrap) и W1.5 (end-to-end on kind) |
| Gateway authz-middleware fail-closed enable на dev | **W1.3** |
| Principal propagation cross-service | **W1.4** |
| Newman cases на end-to-end grant→Check на kind | **W1.5/W1.6**, после wiring production write-path через outbox |
| Перевод vpc/compute outbox-таблиц (если будут) на тот же drainer | non-goal в Wave 1 |

---

## 10. Traceability — какие findings разблокирует W1.1

W1.1 **сам по себе не закрывает** findings из `2026-05-21-iam-authz-review-remediation-plan.md`,
но **разблокирует** их fix в W1.5 (Remediation Chunk 1):

| Finding | Описание | Закрывается в | Зависимость на W1.1 |
|---|---|---|---|
| #16 | `AccessBinding.Create` — split-brain DB/FGA (non-fatal Warn на FGA error → DB-row есть, FGA tuple нет) | W1.5 | W1.5 заменяет sync `WriteTuples` на `outbox.Emit(fga_outbox, 'fga.tuple.write', ...)` в той же tx; drainer (W1.1) обеспечивает eventual consistency |
| #8 | `AccessBinding.Delete` — частичное revoke (account+project scope бага), не пишет в FGA при некоторых scope-комбинациях | W1.5 (W0.2/KAC-131/KAC-133 уже частично) | drainer W1.1 пропускает `fga.tuple.delete` events |
| #50 | JIT auto-grant не пишет в FGA | W1.5 | drainer W1.1 |
| #51 | JIT approve/expiry — grant/revoke (не erasure) | W1.5 | drainer W1.1 |
| #52 | BreakGlass.ApproveB — DB row без FGA tuple | W1.5 | drainer W1.1 |
| #47/#48 | Permission-based relation mapping (custom roles → granular permissions) | W1.5 (доменный fix) | независимо от W1.1, в parallel в Chunk 1 |

**Прямой effect W1.1**: bootstrap-admin tuple (Cluster `system_admin` для root user) реально
оказывается в OpenFGA, и `Check`-вызовы для root user'а начинают возвращать ALLOW. Без W1.1
этот tuple sit в `fga_outbox` навсегда.

**Newman-effect W1.1 в одиночку**: ожидается **частичное снижение** failures из 87 на dev-кластере,
если bootstrap-admin tuple был ключом для какой-то части тестов; точная цифра — measured post-deploy,
после Re-run `make e2e-newman` на kind. (Полное закрытие 87 failures — emergent в W1.5/W1.6.)

---

## 11. Ссылки

- Workspace правила: `../../CLAUDE.md` (запреты, vault, kacho-corelib reuse)
- IAM-specific: `../../project/kacho-iam/CLAUDE.md`
- Master plan: `../superpowers/plans/2026-05-23-iam-prod-ready-master.md`
- Wave 1 plan: `../superpowers/plans/2026-05-23-iam-prod-ready-wave1.md` §W1.1
- E3 spec (откуда пришла `fga_outbox` table): `sub-phase-2.0-iam-E3-openfga-rebac-acceptance.md` §4.2
- Существующий writer-side: `project/kacho-corelib/outbox/{emit,event,writer}.go`
- Существующий write-сайт в kacho-iam: `project/kacho-iam/internal/apps/kacho/seed/bootstrap_admin.go` (строки 122-151)
- Миграция (AS-IS): `project/kacho-iam/internal/migrations/0002_fga_outbox.sql`
- OpenFGA client: `project/kacho-iam/internal/clients/openfga_client.go`
- Vault — outbox writer-side: `obsidian/kacho/packages/corelib-outbox.md`
- Vault — FGA-write edge: `obsidian/kacho/edges/iam-to-openfga-grant-write.md`
- Remediation findings (источник #8/#16/#47/#48/#50/#51/#52): `../superpowers/plans/2026-05-21-iam-authz-review-remediation-plan.md`
