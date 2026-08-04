---
title: "nlb → iam: SEC-D FGA owner-tuple register (transactional-outbox → mTLS)"
aliases:
  - nlb fga register
  - nlb to iam RegisterResource
category: edge
caller_repo: kacho-nlb
callee_repo: kacho-iam
sync_async: async
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[SEC-D-services-fga-via-iam-mtls]]"
  - "[[EPIC-SEC-mtls-iam-authz]]"
tags:
  - edge
  - kacho-nlb
  - kacho-iam
  - cross-service
  - fga
  - internal
  - security
---

> [!success] Active since SEC-D (2026-06-11) · payload расширен epic-rsab T3/D4 (2026-06-20)
> Заменяет прямой best-effort FGA-write [[nlb-to-iam-creator-tuple]] (GitHub Issue N5). Owner-hierarchy tuple intent пишется в outbox в той же writer-tx, что и INSERT/DELETE/UPDATE ресурса; register-drainer применяет его через `InternalIAMService.RegisterResource`/`UnregisterResource` по opt-in mTLS.
> **T3 (D4)**: payload теперь несёт `labels` + `parent_project_id` + монотонный `source_version` (зеркало compute-β) → IAM наполняет output-only `resource_mirror`, питающий γ-`bySelector{matchLabels}`. НЕ новое ребро — расширен payload существующего. Эмит на **Create** И **Update-when-labels-in-mask** (non-labels Update → mirror no-op).
> **sync-primary (2026-07-18)**: Create дополнительно вызывает `RegisterResource` **синхронно** сразу после commit (best-effort `SyncRegistrar`) — закрывает read-your-writes окно owner-tuple. Async drainer остаётся at-least-once backstop'ом; `Operation.done` НЕ гейтится (ban #9). См. секцию ниже.

# nlb → iam: SEC-D FGA owner-tuple register

**Caller**: `kacho-nlb` register-drainer (corelib `outbox/drainer` на `kacho_nlb.fga_register_outbox`; applier `internal/clients/iam/register_applier.go`)
**Callee**: `kacho-iam.InternalIAMService.RegisterResource` / `UnregisterResource` (port :9091, Internal-only)
**Protocol**: gRPC cluster-internal, per-edge mTLS (`cfg.MTLS.IAMRegister`; обязателен на развёрнутом стенде — см. §mTLS)
**Sync/Async**: **async** — мутация ресурса возвращает Operation сразу; tuple-применение off-hot-path через drainer (intent durable).

## Поток (Вариант A, эпик §3.1)

1. Create/Delete worker: `w.FGARegisterOutbox().Emit(fga.register|fga.unregister, intent)` в той же writer-tx, что и INSERT/DELETE ресурса (один commit, no dual-write).
2. Trigger `fga_register_outbox_notify_trg` → `pg_notify('kacho_nlb_fga_register_outbox', id)` будит drainer.
3. Drainer (FOR UPDATE SKIP LOCKED claim, exactly-once across pods) декодит intent, на каждый tuple зовёт `RegisterResource`/`UnregisterResource`.
4. `sent_at` ставится после OK; иначе retry (backoff) — intent остаётся durable.

## Tuple-набор (one row = весь набор ресурса, OQ-SEC-D-2)

> [!warning] Таблица описывала набор, который приёмная сторона ОТВЕРГАЛА (исправлено 2026-08-05)
> Здесь перечислялись `admin`-кортеж создателя и родительский указатель `load_balancer`.
> Закрытый набор iam принимает **только** связи владения `{project, account, parent, owner}`
> — привилегии выписывает флоу AccessBinding, — поэтому оба отвергались **на каждой
> доставке**. Сегодня в дереве (`internal/domain/fga_intent.go`) эмитируется **только**
> `project`, и godoc это прямо оговаривает. Имена `admin`/`load_balancer` в коде остались,
> потому что это реальные отношения модели, просто пишет их не модуль.
>
> Из этого класса стоит унести не факт, а признак: **эмиссия ≠ применение**. Тест
> «намерение эмитировано» оставался зелёным ровно на этом дефекте; утверждать надо то, что
> принимающая сторона **примет** (`data-integrity.md` §«Межсервисное намерение»).

| Ресурс | register-intent (сегодня) |
|---|---|
| NetworkLoadBalancer | `project:<pid> #project @lb_network_load_balancer:<id>` |
| Listener | `project:<pid> #project @lb_listener:<id>` |
| TargetGroup | `project:<pid> #project @lb_target_group:<id>` |

Доступ создателя материализуется **не** этим кортежем, а реконсайлером iam по привязкам —
пообъектно (`data-integrity.md` §flat Contract-A). Delete → симметричный `fga.unregister`.

## Mirror-feed payload (epic-rsab T3 / D4, T3-02)

`domain.FGARegisterIntent` (`internal/domain/fga_intent.go`) + emitter (`internal/repo/kacho/pg/fga_register_outbox_emitter.go`) + applier (`internal/clients/iam/register_applier.go`):

- `labels` — копия tenant-меток ресурса (`domain.LabelsToMap`), питает γ matchLabels. ТОЛЬКО labels+parent — НЕ underlay/placement (`security.md` инфра-чувствительные).
- `parent_project_id` — owning project (γ containment «объект под scope»). `parent_account_id` — пусто (nlb не резолвит project→account на hot-path; IAM graceful).
- `source_version` — стампится emitter'ом из DB-clock `jsonb_set(payload,'{source_version}',to_jsonb(now()))` внутри writer-tx → монотонен per-object → IAM mirror UPSERT last-source-state-wins (reordered stale intent → no-op).
- **Эмит на Update**: TG/LB `update.go` → `tgMirrorIntent`/`lbMirrorIntent` (project-tuple + refreshed labels, без creator) при `labels` в mask или пустом mask (full PATCH); non-labels mask → no-op. NLB-ресурсы: NetworkLoadBalancer + TargetGroup (Listener — child, без project-scope labels).
- **Move** — без изменений: использует minimal `*UnregisterIntent` (labels-refresh на Move вне scope T3-02).

## Error → drainer classification (`classifyRegisterErr`)

| IAM reply | drainer | эффект |
|---|---|---|
| OK (incl. идемпотентный повтор, SEC-A) | mark `sent_at` | applied; replay не дублирует |
| `AlreadyExists` (defensive) | `ErrAlreadyApplied` → sent | idempotent success |
| `InvalidArgument` | `ErrPermanent` → poison | malformed tuple, без бесконечного retry (SEC-D-14) |
| `PermissionDenied` | `ErrPermanent` → poison | **исправлено 2026-08-05**: отказ по правам зависит от (вызывающий, отношение, объект) — идентичный повтор пройти не может. Прежняя редакция объявляла его transient; в дереве (`register_applier.go`, `case codes.InvalidArgument, codes.PermissionDenied`) он терминален, как и у vpc/compute/storage/registry (5 из 5) |
| `Unavailable`/`Deadline`/транспорт | raw → transient retry | IAM down → intent durable, добивается после recover (SEC-D-11) |

> [!note] Почему «временный» здесь был опаснее, чем выглядел
> Дренаж держит временную строку на единицу **ниже** порога отравления, поэтому она никогда
> не покидает блокирующий набор claim-запроса, и ни одна последующая строка её партиции не
> клеймится. То есть один отвергнутый intent глушил бы **все** последующие намерения того же
> объекта на всё окно повторов — и одинаково для выдачи и для **снятия** прав, причём
> «работает» и «не отозвано» выглядят снаружи одинаково (`data-integrity.md` §«Межсервисное
> намерение»). Отравление вместо этого даёт ограниченную паузу: периодический
> `RedrivePoisoned` (`cmd/kacho-loadbalancer/backstop.go`) переигрывает такие строки.

## mTLS (S3)

Per-edge `cfg.MTLS.IAMRegister` (`grpcclient.TLSClient`); iam internal listener —
`RequireAndVerifyClientCert`. Несовпадение → transport-error → `Unavailable` (intent
durable, SEC-D-20/21). PKI/helm-wiring — SEC-F.

> [!warning] По этому ребру передаются ЗАПИСИ О ПРАВАХ — mTLS здесь не опция
> Ребро пишет owner-tuple, то есть то, из чего потом выводится доступ к ресурсу. Значит цена
> неаутентифицированного писателя тут — не «утечка транспорта», а **выдача прав**. Per-edge
> включатель был введён ради поэтапной раскатки PKI (SEC-F) и остаётся **переходной формой**:
> на любом РАЗВЁРНУТОМ стенде (kind/CI/local/prod) mTLS на этом ребре обязателен, а
> production boot-guard обязан отказывать в старте, если ребро живое и не защищено
> (`security.md` §AuthN+AuthZ ВЕЗДЕ п.1 + §Production-mode п.1). «Internal = trusted, сеть
> закрытая» — прямо запрещённое допущение: внутренний периметр не доверенный.
>
> Симметрично требуется **сужение списком**: принимающая сторона обязана держать непустой
> allow-list SAN'ов законных отправителей. Пустой список означает «не сужаем», а не
> «запрещаем»; этот класс уже находили в четырёх сервисах, причём дважды комментарий рядом
> утверждал обратное (`security.md` §AuthN+AuthZ ВЕЗДЕ п.5).

## sync-primary owner-tuple registrar (2026-07-18) — replaces removed opgate

Because nlb registered owner-tuples **only** via this async NOTIFY-driven drainer,
`LoadBalancer/Listener/TargetGroup` Create-op-done raced ahead of owner-tuple
FGA-visibility under full-suite load → creator hit transient 403 (`lacks
v_update/v_delete`) on immediate mutate and 404 (hide-existence) on Get of its own
resource, inflating newman `retry_until_authorized` busy-wait (nlb suites were the
timeout casualty).

**Removed approach (opgate confirm-gate, commit 4d3f35d):** gated Create-op
`done=success` on `check.OwnerConfirmer.Confirm` seeing `v_update` ALLOW. **Deleted
as a ban #9 violation** (`api-conventions.md` `Operation.done` = resource durability,
NOT downstream-visibility): gating `done` on eventually-consistent FGA-visibility
redefines the Operation contract and yields a **phantom-resource** on fail-closed
(row committed, name UNIQUE-taken, but op=ERROR). Rationale: `api-conventions.md`
§`Operation.done` + `data-integrity.md` cross-domain authz (opgate removal, 2026-07).

**Current fix — sync-primary registrar** (`internal/clients/iam/sync_registrar.go`
`SyncRegistrar`, port `iam.Registrar` aliased in each create ports.go; wired in
`cmd/kacho-loadbalancer/wiring.go`; mirrors vpc `internal/clients/iam_sync_registrar.go`):
after durable commit of the resource **and** its `fga_register_outbox` intent, the
create use-case synchronously calls `RegisterResource` for the same tuples (per-call
5s deadline; `source_version=now()` → monotonic ≥ DB-stamp → async re-apply is a
stale no-op). Closes the read-your-writes window at create-time; durable outbox +
register-drainer remain the at-least-once backstop.

- **BEST-EFFORT (ban #9):** `SyncRegistrar` error is logged (`slog.Warn`) and
  **swallowed** by the use-case — NEVER fails the Operation, NEVER gates `done`.
  Residual visibility lag covered by bounded client-retry, not a server barrier.
- **Про «доброкачественный отказ прокси» (устарело как описание причины):** синхронный путь
  и сейчас не считает `PermissionDenied`/`InvalidArgument` поводом шуметь, но **предмета
  этого послабления больше нет** — отвергаемые `admin`/`load_balancer` не эмитируются вовсе
  (см. предупреждение к таблице). Послабление, которому нечего исключать, — само по себе
  находка: если такой отказ снова начнёт приходить, он теперь означает **настоящую**
  поломку прав, а не известную мелочь.
- **vs vpc (сверено 2026-08-05 — расхождение УСТРАНЕНО):** здесь стояло «у vpc
  sync-registrar fail-closed — латентный риск фантома». Сегодня vpc ведёт себя так же, как
  nlb: `api/*/create.go` логируют предупреждение и продолжают, объясняя это ровно тем же
  доводом (провалить операцию после коммита значит отдать вызывающему код узла прав на уже
  созданный ресурс, чьё имя/CIDR уже заняты, — фантом). Расходится только **godoc**
  `SyncRegistrar` в vpc, который всё ещё обещает fail-closed; верен код.

## See also

[[iam-register-resource-callee-contract]] (приёмная сторона: закрытый набор отношений,
гашение повторной доставки, пост-коммитный форвард) · [[nlb-to-iam-creator-tuple]]
(deprecated direct path) · [[../rpc/iam-internal-iam-service]] · [[vpc-to-iam-fgaproxy]] ·
[[compute-to-iam-fgaproxy]] · [[storage-to-iam-fgaproxy]] · [[registry-to-iam-fga-register]] ·
[[iam-to-nlb-resource-lifecycle]] · [[iam-openfga-confirm-read-consistency]] ·
[[../KAC/SEC-D-services-fga-via-iam-mtls]]

#edge #kacho-nlb #kacho-iam #cross-service #fga #internal #security
