---
title: FGA register-pipeline throughput inversion + drainer false-poison
category: kac
tags: [kacho-iam, kacho-corelib, kac, fix, architecture, race-fix]
ticket_id: TBD
status: done
type: fix
repos: [kacho-corelib, kacho-iam]
opened: 2026-07-23
---

# FGA register-pipeline throughput inversion (+ drainer false-poison)

> [!important] Статус приведён к дереву продукта — волна сверки vault 2026-08-05
> Сверено с `PRO-Robotech/kacho@96b2879a` (ствол `redesign/integration` — её предок).
> Прежний статус — `in-progress`; он пережил свой предмет и держался на списке
> пунктов, часть которых больше не существует как единица работы.
>
> **done.** Обе половины закрыты в дереве: захват строк очереди умеет не брать те, у которых в своей секции есть недоставленный предшественник, и умеет **исключать отравленные** из блокирующего набора — `pkg/outbox/drainer/`. Класс целиком выведен в `data-integrity.md` §«Outbox-drainer concurrency», включая требование, чтобы проба была меж-пакетной.

> [!warning] Production-readiness finding — measured, не гипотеза
> Owner-tuple материализация НЕ держит темп под write-нагрузкой → тенант не видит
> свои свежесозданные ресурсы в List. Затрагивает ВСЕ сервисы; compute — канарейка.

## Симптом
compute List-includes отдают **`[]`** для своего свежего ресурса под suite-нагрузкой
(disk/image/instance/snapshot lst-includes, 9 кейсов). Idle — fine (материализация 186ms).

## Root (measure-first, aab23c0d, числа)
| Метрика | Значение |
|---|---|
| Idle материализация v_list | 186ms · OpenFGA Write 2-3ms (healthy) |
| **Create-worker** | **~6.7 ops/s** |
| **Register-drainer** | **~0.5 rows/s (12× медленнее!)** |
| Backlog | worker-ops 58-61k · outbox 13.7k · oldest-age 11→29мин (растёт) |
| Probe под 6-thread burst | НЕ материализован за 30s (151 poll) |

**Throughput inversion:** producer (6.7/s) >> consumer (0.5/s) → backlog расходится
безгранично → v_list-латентность → минуты→never → List пуст. Механизм: `RegisterResource`/
`ReconcileObjectForward` таймаутит **5s** под concurrency + флуд `already exists` (grpc 2017);
drainer применяет строки **ПОСЛЕДОВАТЕЛЬНО**, блокируясь на полный ApplyTimeout per timed-out
apply → 0.5/s ceiling. Idle=fine (пустой backlog → NOTIFY-drainer мгновенен) → **не** coverage-gap.

## Почему 2 прошлых фикса промахнулись
Целили в **read**-сторону: compute sync-registrar Image/Snapshot (bf42627 — валидный parity, но
ортогонально); Class-A iam ListObjects HIGHER_CONSISTENCY + compute empty-cache (d68f9f6 — не
помогло, т.к. List пуст = tuple НЕ написан, strong-read пустоты не находит). Root — **write/
materialization throughput**, не read.

## Фиксы
1. ✅ **False-poison correctness** (`e2bf116`, corelib `pkg/outbox/drainer`): `applyCtx`/`dbCtx`
   минтились одномоментно с одним ApplyTimeout → full-timeout apply expire'ил dbCtx →
   `markTransientFailure` падал → transient-cap не срабатывал → attempt→MaxAttempts →
   **false-poison → owner-tuple intent теряется НАВСЕГДА** (нарушение transient-no-poison).
   Fix: свежий dbCtx budget после apply. TDD RED→GREEN, `-race` green, system-design APPROVE.
   Реальный data-loss баг (не только throughput).
2. 🔄 **Throughput** (in-progress, aab23c0d): Lever A — **drainer apply-concurrency** (sequential→
   bounded worker-pool, `FOR UPDATE SKIP LOCKED` уже даёт per-row claim; owner-tuple'ы
   commutative → order-independent) — главный рычаг; Lever B — redundant-write delta (если
   applyAfterCommit read-delta сломан/racy). db-architect + system-design ОБЯЗАТЕЛЬНЫ. Цель:
   consumer ≥ producer. Fallback: если рискованно рашить critical exactly-once — scoped epic.

## Затронутые сущности vault
- [[grant-materialization-omirror-root]] · [[opgate-eventual-consistency-lesson]] (EC by design)
- corelib `pkg/outbox/drainer` · iam `reconcile/forward.go` `ReconcileObjectForward`

## Операционка
Стенд kind несёт **chronic backlog** (58k/13.7k, усилен stress-замером) → **hard-reset
ПЕРЕД re-валидацией** (drainer 0.5/s его за часы не разгребёт). Затем deploy iam → re-seed →
re-run compute → подтвердить List-includes green + backlog не растёт.

## Более глубокий слой (выявлен после deploy drainer-concurrency)

Drainer apply-concurrency (N=16, `ca424e4`) **НУЛЛИФИЦИРОВАН** более глубоким bottleneck'ом:
iam `ReconcileObjectForward` для КАЖДОГО объекта **контендит на per-BINDING advisory-lock +
читает `current_members` того же matching binding'а**. Все объекты, шарящие project-editor
binding, сериализуются на нём → `acquire binding lock <bid>: timeout: context deadline exceeded`.
16 concurrent applies ждут ОДИН binding-lock → concurrency съедена.

**Усилено stress-артефактом (подтверждено):** measure-агент создал **14,199 target_members на
ОДНОМ binding** (`acb394t7e6cy0881gcsx`) → `current_members` read = O(N=14k) per-object → O(N²)
total → timeout. **Нормальная нагрузка (suite ~200 объектов на СВЕЖИЙ binding) сюда не грузит**
(200 members read = fast). Т.е. compute-фейлы = **stand-pollution артефакт**, НЕ normal-load дефект.

**Layered bottlenecks** (каждый фикс вскрывал следующий — systematic-debugging «architecture»):
sequential-drainer (fixed ca424e4) → per-binding lock contention → **O(N²) current_members read**.

## Scalability epic (latent, для high-density проектов)
O(N²) per-binding `current_members` read в `ReconcileObjectForward` — реальный production concern
для проекта с 10k+ ресурсов на одном editor-binding (не блокирует normal-load/suite, но
масштабируется квадратично). Фикс: scope read к материализуемому объекту, не ВСЕМ members
binding'а; или per-object lock вместо per-binding. Отдельный architecture-epic + design review.

## ⚠️ REGRESSION suspect: drainer-коммиты сломали mirror-materialization (clean-stand)

Full rebuild → clean stand: **ОДИН disk, 30s, GET 404** (не burst, не throughput). Disk create→
op-done(no-error)→GET 404 = iam `resource_mirror`/scope-resolution НЕ материализуется. Config OK
(store-id MATCH `01KY8ENM6T32S3N7FT219RRS3Y`, sync-registrar «enabled», drainer running, 0 iam-errors,
outbox drains). Но mirror absent → gateway scope_extractor не резолвит disk→project → hide-existence 404.

**Timeline-улика:** compute-GET **работал 21:49** (Class-A задеплоен, drainer-коммиты — НЕТ) → **404
после деплоя `ca424e4`+`e2bf116` (23:40)** + rebuild. Сильный кандидат: **drainer apply-concurrency
split `processRowInTx`→`applyRow`+`markRow` (ca424e4) ИЛИ fresh-dbCtx (e2bf116) внёс регрессию** —
apply «succeeds» + outbox marks sent, но mirror-write не происходит/теряется под split. Integration
`-race` + dual-review НЕ поймали (не покрыли mirror-materialization e2e-путь). НЕ root-caused до quick-fix
за разумный marathon-investigation.

**→ НЕ пушить commit-стек** пока не разрешена регрессия (нельзя протолкнуть mirror-loss в trunk).
Focused-debug (свежая сессия): git-bisect ca424e4/e2bf116 vs stand-issue; verify RegisterResource
mirror-write под concurrent drainer; проверить applyRow/markRow не роняет mirror-эффект.

## Status
- [x] measure-first root · [x] false-poison correctness code (`e2bf116`, но см. regression-suspect)
- [x] throughput fix drainer apply-concurrency (`ca424e4`) + dual-review — **но suspect mirror-regression**
- [x] deeper root: per-binding O(N²) (stress-pollution 14k) · [x] full rebuild → clean-stand validation
- [x] **clean-stand выявил mirror-materialization регрессию** (GET-404, single-disk) post-drainer-commits
- [ ] **focused-debug: bisect drainer-commits vs stand-issue** (свежая сессия — не marathon-end)
- [ ] resolve → push commit-стек → scalability-epic O(N²) per-binding + pipeline throughput/latency
- [ ] 6 доменов (geo/storage/vpc/registry/nlb/iam-core) re-validate на clean stand (были green pre-rebuild)

#kacho-iam #kacho-corelib #kac #fix #architecture
