---
title: "RBAC Contract-A flat — bootstrap signup owner-binding fallout (ROOT flat-403)"
ticket_id: rbac-2026-contract-a-flat-fallout
status: test
type: fix
repos:
  - kacho-iam
  - kacho-deploy
prs:
  - https://github.com/PRO-Robotech/kacho-iam/pull/230
  - https://github.com/PRO-Robotech/kacho-deploy/pull/122
opened: 2026-06-24
tags:
  - kac
  - kacho-iam
  - fix
  - domain
  - usecase
  - repo
---

# RBAC Contract-A flat — bootstrap signup owner-binding fallout

**Status**: test (iam branch `rbac-contract-a-flat-fallout` → PR #230; deploy PR #122 flat-configmap pin)
**Type**: fix — ROOT of remaining flat-403 (~90%); continues [[rbac-2026-contract-a-fix-iam-content-forward]] / [[rbac-2026-224-owner-wildcard-content]]
**Acceptance**: `docs/specs/rbac-explicit-model-2026-acceptance.md` — D-4 / D-8a / C-01 / C-01b
**Commit**: `685b1ad`

## Первопричина (ОДИН механизм, ~90% остаточных flat-403)

`bootstrapPersonalResources` (`internal/apps/kacho/api/user/internal_upsert.go`) — LIVE signup /
Kratos-provision путь И activated-invitee owns-zero путь — был рассинхронизирован с
Account.Create owner-путём (`account/create.go doCreate`) под flat-моделью:

1. создавал account-scoped self-binding с **admin**-ролью (`rol21232f297a57a5a74`), не **owner**
   (`OwnerRoleID rol72122…`) → `ownerBindingFor` / owner `*.*` forward-mat движок его НЕ видел;
2. эмитил только хардкод `bootstrapTuples` (tier + hierarchy pointers), НИ ОДНОГО per-object
   content-tuple;
3. НЕ вызывал `ReconcileBinding` (use-case не имел reconciler-поля).

Под flat hierarchy-pointer'ы доступа не дают → bootstrap-юзер 403 на content своего аккаунта
(project / access_binding / group / cross-service). Класс-3 (get-self) — отдельная D-4-дыра: self-tuple
`iam_user:<U>#subject@user:<U>` нигде в проде не эмитился (модель `iam_user.viewer = subject or editor`).

## Фикс (parity с account/create.go; переиспользует owner forward-mat движок + индекс 0038/0039)

- bootstrap account-scoped binding → **owner**-binding (OwnerRoleID, scope=ACCOUNT,
  deletion_protection, Subjects, OWNER-BINDING ledger, grant-audit) — co-commit в bootstrap writer-tx (ban #10);
- post-commit `ReconcileBinding(ownerBindingID)` → scope-self verbs на `account:<A>` + owner `*.*`
  ARM_ANCHOR forward над содержимым (default project, iam-native, cross-service mirror);
- reconciler прокинут в ОБА composition root — gRPC InternalUserService (`wiring.go`) И
  Kratos provision-hook (`hooks_mux.go`, LIVE signup путь);
- self-tuple `iam_user:<U>#subject@user:<U>` эмитится в `bootstrapTuples` (D-4 get-self);
- дроп redundant `admin@account` bootstrap-tuple (tier материализует owner-binding reconcile — D-4 single path).

Activated-invitee bootstrap переиспользует ту же функцию; `invite.go doInvite` уже forward-mat'ит
свежеприглашённого user + project AB через reconcile-events.

## TDD (testcontainers) RED→GREEN

`internal/repo/kacho/pg/bootstrap_owner_mat_integration_test.go` гоняет РЕАЛЬНЫЙ UpsertFromIdentity
use-case wired с reconciler. **RED** (5/5 fail на pre-fix: admin-binding, нет owner-binding, нет
content-tuples, нет self-tuple — диагностированный flat-403). **GREEN** после фикса:
owner-binding shape; per-object owner mat на project (`project:<id>` admin+v_get) / own
access_binding / cross-service network; self-tuple emit.
**Регрессия GREEN**: Account.Create owner-path, upsert/invite (T-I3/T-I5/T-E4), owner-iam-content,
#224 owner-wildcard, review1 dual-member ledger, emitted-tuples.

## Затронутые сущности vault

[[iam-user]] · [[iam-access-binding]] · [[iam-account]] · [[rbac-2026-contract-a-fix-iam-content-forward]] · [[rbac-2026-224-owner-wildcard-content]]
edge: [[api-gateway-to-iam-authorize]] (signup провижн → bootstrap)

## flat-newman результат (CI run 28101726088, commit 685b1ad)

**Крупный сдвиг от baseline.** Полностью ЗЕЛЁНЫМИ стали (были red в диагнозе): **iam-group,
iam-role, iam-service-account, iam-account, iam-authz-grant-check-propagation**.
iam-access-binding: **73 → 24** fail.

**Остаток red — ОДИН pre-existing forward-mat gap (drain-vs-done race), НЕ bootstrap-fallout:**
iam-project (5), iam-access-binding (24), iam-rbac-subjects (33: add-member 403 + 32 derived poll),
label-revoke-vpc (3), authz-deny (1). Механизм: per-object `Check(viewer, project|iam_access_binding:<id>)`
на api-gateway гоняется СРАЗУ после `Operation.done`, но owner-content tuple материализуется
forward в `fga_outbox` и применяется в OpenFGA **асинхронно** drainer'ом (LISTEN/NOTIFY) — done
выставляется до drain → single-shot get-confirms проигрывает гонку → 403. role/group/sa GREEN т.к.
их Get резолвится через account-tier `viewer` (каскад от tier), не через свежедренутый per-object tuple.
Это property #228 forward-mat-дизайна (reconciler→outbox→async-drain), всплывшее под flat (per-object
Check стал authoritative). Зафиксировано отдельным issue: **kacho-iam#232** (нужен system-design-reviewer
для drain-vs-done контракта; fix — sync live `RelationStore.WriteTuples` по ledger перед Operation done,
как invite.go; outbox остаётся durable backstop).

## #232 хвост — НЕ просто drain-race: batch-limit + computed-only-tier (sync-FGA отказывал)

После sync-FGA материализации (d2b715a6) остался ТОЛЬКО `iam-access-binding` get-confirms 403
(+ derived `authz-deny delete-ab-teardown`). Диагноз уточнён за пределы «drain-vs-done»:
sync-FGA-запись (`reconcile.applyAfterCommit` → `RelationStore.WriteTuples`) слала ВЕСЬ собранный
tuple-set ОДНОГО `ReconcileObject` прохода в ОДИН OpenFGA `/write`. Для `ReconcileObject("iam.accessBinding", id)`
fan-out идёт по ДВУМ bounded `*.*` ARM_ANCHOR биндингам на populated-аккаунте (owner-binding +
свежевыданный peer `*.*` view-binding), каждый материализует per-object tuples по всему контенту →
батч (a) **превышает дефолтный OpenFGA `maxTuplesPerWrite=100`** И (b) несёт tuple, который OpenFGA
**отвергает для sibling-объекта с computed-only tier** (`iam_role#viewer` не принимает direct user —
модель `viewer: editor`/`editor: admin`). OpenFGA реджектит ВЕСЬ батч 400 → НИ ОДИН tuple не лёг,
включая валидный owner `iam_access_binding#viewer/admin`. `applyAfterCommit` best-effort (логирует,
не возвращает) → немедленный GET опережает async-дренаж (который пишет ПО-СТРОЧНО, лимит не бьёт) → 403.
account/group/role get-after-create зелены: их fan-out < 100 и без computed-only sibling.

**Фикс (kacho-iam#230, commit `281d924f`) — 2 слоя:**
- `OpenFGAHTTPClient.WriteTuples/DeleteTuples` чанкуют по ≤100 (`maxTuplesPerWriteRequest`) — большой
  fan-out применяется несколькими запросами, не реджектится целиком. Async-дренаж пишет по-строчно → не затронут.
- `syncFGAWriter.WriteTuples` (create-path read-after-write closer) на ошибке батча ретраит ПО-ТУПЛУ —
  один невалидный/over-limit tuple дропает только себя (паритет с per-tuple изоляцией дренажа). Валидные
  owner `iam_access_binding` viewer/admin/v_* ложатся синхронно до Operation.done; durable fga_outbox +
  дренаж — at-least-once backstop.

**TDD RED→GREEN:** `internal/clients/openfga_write_chunk_test.go` (httptest эмулирует per-request лимит:
un-chunked >100 реджект RED → chunked GREEN) + `syncfga_read_after_write_e2e_integration_test.go`
`TestSyncFGA_ReadAfterWrite_PopulatedAccount_OwnerViewerCheckImmediately` (real OpenFGA+PG, дренаж НЕ
запущен, populated-аккаунт >100 fan-out; RED со стэшнутыми прод-фиксами 403 → GREEN). chunk-тест прогнан -race.

**Сопутствующая находка (НЕ в scope, follow-up issue):** reconciler эмитит computed-only tier-tuple
`iam_role#viewer`/`editor`, который модель отвергает; доступ к iam_role фактически несут direct `v_*`
(iam_role verb-bearing), так что отклонённый tier-tuple НЕ load-bearing — после per-tuple-изоляции
безвреден (дренаж пойзонит одну строку). Стоит чистки в reconcile.ruleObjectTuples (не эмитить tier для
computed-only-tier типов) — отдельным PR.

## #232 финал — flat-newman poll-for-propagation стабилизация (commit `d2a7fb6d`)

После sync-FGA фикса (`281d924f`) продукт-корректность доказана ДЕТЕРМИНИРОВАННО integration-тестами,
но flat-umbrella newman **МЕРЦАЛ** между прогонами (4f8c24bb: authz-deny+iam-access-binding;
281d924f: +iam-account+iam-user). Диагноз: **eventual-consistency на grant→access под CI-нагрузкой** —
доступ материализуется синхронно (sync-FGA-write до Operation.done), но ВИДИМОСТЬ на api-gateway authz-gate
(`<caller> editor|viewer on iam_access_binding:<id>` через account-anchor parent-tuple) пропагируется на удар
позже op-done → «create → СРАЗУ GET/DELETE, ждёт 200» интермиттентно 403. Это TIMING, не дыра.

**Решение (e2e-poll, прод НЕ тронут):** конвертация read-after-write кейсов в poll-for-propagation.
- `gen.py`: новый `poll_request_until_status` — зеркало `get_until_gone`. Ретраит ТОТ ЖЕ запрос (bounded
  POLL_CAP, изолированный per-step счётчик) пока код в propagation-window-сете (здесь 403-only), реальные
  asserts на терминальном/converged ответе. Опц. `retry_predicate` для LIST read-after-write (200, но свежей
  строки ещё нет в наборе). Легитимно ТОЛЬКО т.к. доступ доказанно появляется — не-converging deny падает на cap.
- `iam-access-binding` (9 forward-mat reads на свежем crudAcbId/flowAcbId): get-confirms / verify-original-survives /
  get-ok (GET 200); list-by-resource / list-by-subject-self / list-by-account-owner (LIST содержит crudAcbId);
  delete / delete-as-owner / revoke-delete (DELETE 200). 403-only retry (строка существует; 404 — реальная аномалия).
  Negative / no-leak / must-DENY кейсы — single-shot (не маскируем).
- `authz-deny` AUTHZ-AB-CR ALLOW teardown: НЕ продукт-баг, а control-flow баг харнеса. Шейренные имена шагов
  (poll-op-create / poll-op-delete) + env vars across 3 ALLOW-кейсов → `setNextRequest(requestName)` бледил
  control flow (self-re-poll прыгал в СЛЕДУЮЩИЙ кейс, СКИПАЯ его create POST → poll чужого op как др. principal →
  404 anti-leak → teardown id не резолвился → DELETE с литералом `{{...}}` → 400). Фикс: per-case-уникальные имена
  шагов + env vars, reset teardown-vars на create, retry op-poll на 404-visibility-window, fallback на well-formed
  garbage acb (чистый 404/403) при нерезолве — никогда литерал-темплейт.

**iam-user `list-nonmember` (saw 1, want 0)** и **iam-account `get-after-delete` (200 past cap)** — downstream:
первый = no-leak, корень = IAM-ACB delete flake (теперь poll-стабилен → tuple снимается → leak уходит);
второй = delete-side propagation (уже polls через get_until_gone). Оба НЕ конвертированы в forward-poll
(не маскировка negative/delete-side); наблюдаем после re-run.

## DoD

- [x] owner-binding + ReconcileBinding в bootstrap (оба composition root)
- [x] self-tuple emit (get-self)
- [x] integration RED→GREEN + регрессия (CI: integration testcontainers SUCCESS)
- [x] go build / vet / gofmt / golangci-lint / govulncheck / gosec / Trivy (CI) зелёные
- [x] flat-newman: bootstrap-ROOT класс закрыт (5 сьютов fully green)
- [x] #232 хвост: root cause = batch-limit + computed-only-tier sync-FGA reject (НЕ просто drain-race);
      fix chunk + per-tuple-resilient sync-FGA write (commit `281d924f`); TDD RED→GREEN
- [x] #232 финал: flat-newman poll-for-propagation стабилизация (commit `d2a7fb6d`) — read-after-write
      кейсы (iam-access-binding 9 reads + authz-deny teardown) конвертированы в poll; generic
      `poll_request_until_status` helper в gen.py; прод НЕ тронут, без skip/TODO
- [ ] flat-umbrella 2× стабильно зелёный (re-run gate): iam-access-binding + authz-deny + cascades
      (iam-account/iam-user) → forward-mat-класс 0; остаток только whitelist + cross-repo
- [ ] coordinated merge с kacho-deploy#122 (revert flat-pin → main после deploy#122) — #230 готов;
      после меня — system-design-review sync-live-write
- [ ] follow-up issue: reconciler не должен эмитить computed-only tier-tuple на iam_role (cosmetic, non-load-bearing)
