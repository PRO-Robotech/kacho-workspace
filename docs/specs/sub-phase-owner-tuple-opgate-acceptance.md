# Sub-phase owner-tuple-opgate (Create-Operation gated on owner-tuple FGA confirm) — Acceptance

> **Статус:** ✅ APPROVED (2026-07-16, acceptance-reviewer rev 2; owner-решения OQ-1/3/4/5 приняты владельцем автономно; OQ-2/6 — impl/proto-выбор, не блокируют)
> **Дата:** 2026-07-16
> **Ревьюер:** `acceptance-reviewer` (единственный gate ✅ APPROVED — ban #1; заказчик к контракту не подключается, проверяет только финальный smoke/e2e).
> **Эпик/тикет:** KAC-`<N>` (fix; cross-service). Ветки `KAC-<N>` в затронутых репо по build-графу.
> **Автор-агент:** `acceptance-author`
> **Затронутые репо:** `kacho-iam`, `kacho-vpc`, `kacho-compute`, `kacho-storage` (owner-resource Create-flow каждого). `kacho-proto` — только если LRO-metadata расширяется additive-полём прогресса (см. §8 OQ-6). Ревью: `system-design-reviewer` (distributed op-completion) + `proto-api-reviewer` (если proto тронут).
> **Опирается на (ground truth):** SEC-D (`docs/specs/sub-phase-SEC-D-services-fga-via-iam-mtls-acceptance.md` — transactional-outbox owner-tuple + register-drainer + sync-registrar), W1.1 (`docs/specs/sub-phase-W1.1-fga-outbox-drainer-acceptance.md` — drainer mechanics), iam-anchor-grant (`docs/specs/iam-anchor-grant-and-invite-activation-fga-acceptance.md` — γ-01 post-commit reconciler), edges `obsidian/kacho/edges/{vpc,compute,storage}-to-iam-fgaproxy.md`, `edges/iam-to-openfga-grant-write.md`.

---

## 0. Обзор

Сегодня при `Create` owner-ресурса (Network / SecurityGroup / Subnet / Instance / Disk /
Volume / AccessBinding) владелец получает **`PermissionDenied` «no direct relations granted»
(403)** на **немедленный** `Update`/`Delete` своего только что созданного ресурса. Причина —
**тайминговое окно**, а не deploy-gap:

- owner-tuple (`project:<projectId> #project @<type>:<id>`; для iam AccessBinding — per-object
  access на `iam_access_binding:<id>`, §4.1) регистрируется в FGA через путь SEC-D:
  `RegisterResource`-intent пишется в `<svc>.fga_register_outbox` **в writer-tx ресурса** (durable)
  → register-drainer → `InternalIAMService.RegisterResource` → IAM `fga_outbox` → IAM drainer →
  OpenFGA. Плюс sync-registrar после commit (**best-effort**: ошибка/лаг → WARN, drainer добивает
  at-least-once). Для iam owner-ресурсов — тот же класс, но in-process (`fga_outbox` + drainer).
- Create-**Operation** помечается `done=true` **раньше**, чем owner-tuple становится виден в FGA.
  Gateway scope_extractor немедленного `Update`/`Delete` резолвит `target→scope` через owner-tuple;
  tuple ещё не виден → `Check` возвращает «no direct relations granted» → 403.
- Register-drainer **на стенде работает** (лог «FGA register-drainer started», таблица
  `kacho_vpc.fga_register_outbox`) — окно закрывается eventually, но `op.done` его обгоняет. Это
  доминирующий остаточный класс падений e2e/newman (~тысячи).

**Решение владельца (2026-07-16, зафиксировано):** Create-Operation **НЕ достигает `done=true`
с успешным результатом, пока owner-tuple не ПОДТВЕРЖДЁН зарегистрированным в FGA
(read-after-register)**. Гарантия контракта:

> Клиент, дождавшийся Create-Operation `done=true` **с результатом-`response` (успех)**, может
> **немедленно** мутировать (`Update`/`Delete`) созданный ресурс своим создателем **без окна 403
> «no direct relations granted»**.

Единообразно для iam/vpc/compute/storage (owner-resource Create). Публичная форма ресурсов и их
REST-пути **не меняются** — фикс поведенческий (op-completion gate), не контрактный.

> [!important] Supersede-note — SEC-D-11 частично разворачивается (осознанно)
> **SEC-D-11** (`sub-phase-SEC-D-...-acceptance.md`, Сценарий SEC-D-11) фиксировал: «IAM
> Unavailable при Create → `Network.Create` Operation завершается `done=true` **без** error
> (tuple-применение асинхронно, не на hot-path Operation)». Данная под-фаза **осознанно меняет
> этот аспект op-completion** для owner-resource Create: op-done теперь **gated на
> read-after-register confirm**, и при недоступности FGA/IAM **дольше confirmation deadline** →
> `op.error(Unavailable)` (§3, OTG-05), а не ложный `done=true(success)`. Это сознательный размен
> владельца: приоритет гарантии «`done(success)` ⟹ нет 403» над «Create всегда success даже при
> IAM down». **Durable-backstop гарантия SEC-D-11 СОХРАНЯЕТСЯ полностью**: owner-tuple/ресурс не
> теряются (intent durable, drainer добивает at-least-once) — меняется только **терминальный
> статус Operation** на deadline-ветке, не durability ресурса (OTG-06). Прочие сценарии SEC-D
> (S1 intent-в-writer-tx, S2 drainer, S3 mTLS) — без изменений.

---

## 1. Связь с регламентом и запретами (нормативно — детали в `.claude/rules/*`, не дублируем)

| Регламент | Где соблюдаем |
|---|---|
| ban #1 (acceptance-first) | данный doc — gate; код только после ✅ APPROVED. |
| ban #6 / `security.md` (Internal.* не на external) | confirm — через существующий `InternalIAMService.Check` (:9091, service→service), не на external endpoint. |
| ban #7 (без брокера) | outbox/drainer — Postgres + LISTEN/NOTIFY (corelib), как SEC-D/W1.1; op-gating не вводит брокера. |
| ban #8/#4 (DB-per-service, no cross-service cascade) | register-intent — в БД своего сервиса; cross-service — только по API (IAM RPC). |
| ban #9 (мутации → Operation) | Create остаётся async через `Operation`; gate — **внутри** жизненного цикла Operation (меняет момент `done`, не форму). |
| ban #10 / `data-integrity.md` | register-intent — durable в writer-tx; drainer-claim — атомарный CAS (SEC-D); concurrent-тест обязателен (OTG-13). |
| ban #11/#12 (TDD, тесты в том же PR) | RED integration + newman до кода; §5 — источник сценариев. |
| `data-integrity.md` §cross-domain / fail-closed | confirm недоступен в отведённый deadline → `op.error UNAVAILABLE` (fail-closed), НЕ ложный success. |
| `polyrepo.md` (ацикличность) | confirm — на **существующем** ребре `svc→iam` (`Check`); iam не зовёт svc обратно; iam-owned ресурсы confirm'ят **in-process** (свой FGA). Нового ребра нет. |
| `api-conventions.md` (error-format) | негативы указывают точный gRPC-код; тексты — часть контракта; `op.error`-код фикса — стабильный. |
| `architecture.md` (clean arch) | confirm-порт в use-case; impl (`Check`-клиент / in-process FGA-read) — в `clients/`; wiring — в `cmd/<svc>`. |

---

## 2. Глоссарий

- **owner-tuple** — tuple, дающий gateway scope_extractor'у резолв `target→scope` (анти-BOLA):
  для vpc/compute/storage — `project:<projectId> #project @<type>:<id>` (эмитится register-intent'ом
  SEC-D); для iam AccessBinding — per-object access на `iam_access_binding:<id>` (§4.1). Без него
  `Check` немедленного мутирующего RPC → «no direct relations granted».
- **read-after-register (confirm)** — read-проба, подтверждающая, что owner-tuple **эффективен**
  в FGA (авторизационный резолв, который выполнит gateway на немедленной мутации, уже проходит).
  Выполняется через существующий `InternalIAMService.Check`/FGA-read — **без нового ребра**.
  Read-only, идемпотентна.
- **op-gating** — Create-Operation достигает `done=true, result=response` **только после**
  успешного confirm. До confirm — `done=false` + progress-metadata `PENDING`.
- **sync-registrar** (SEC-D) — синхронная регистрация owner-tuple после commit. Была best-effort;
  становится **шагом confirm-gate** (её результат подтверждается read-after-register).
- **register-drainer / register-intent** (SEC-D) — durable at-least-once backstop
  (`<svc>.fga_register_outbox` → `RegisterResource`). Сохраняется как есть — op-gating его **не
  ломает** (OTG-06/07).
- **confirmation deadline** — конфигурируемый верхний предел ожидания confirm (≥ нормальной FGA-
  пропагации, ≪ Operation max-lifetime). Превышен → `op.error UNAVAILABLE` (fail-closed).

---

## 3. Выбранный контракт op-completion (зафиксированные решения владельца)

Требование: op **не висит бесконечно** И **не ложно-`done`**. Выбран **bounded-deadline
read-after-register с fail-closed-терминалом**. Наблюдаемое поведение:

1. **Happy (confirm получен):** Operation → `done=true, result=response(<resource-ref>)`. Между
   этим моментом и первой авторизованной мутацией создателя — **нет окна 403**. Латентность
   happy-path ограничена (register+confirm — обычно sub-second).
2. **Pending (confirm ещё не получен):** Operation наблюдаема `done=false` с progress-metadata
   `owner_tuple_registration = PENDING`. Ресурс-строка и register-intent уже durable (writer-tx
   закоммичен).
3. **Timeout (confirm не получен за deadline):** Operation → `done=true, result=error(codes.Unavailable,
   "owner-tuple registration not confirmed")` — **fail-closed**. `done=true` с **успехом** без
   confirm **НЕ выставляется никогда**.
4. Ресурс-строка + register-intent **durable во всех ветках**; register-drainer добивает tuple
   at-least-once даже на timeout-ветке → ресурс становится используемым shortly (OTG-06).

**Точная переформулировка гарантии (для traceability):** гарантия «нет окна 403» относится к
`done=true` **с результатом `response`**. `done=true` с результатом `error` — **отказ**; клиент
НЕ считает ресурс сразу используемым.

### 3.1 Зафиксированные решения (приняты владельцем — НЕ open)

- **[FIX-1] Код на timeout = `codes.Unavailable`** (retryable, паритет SEC-D §6.7 / `data-integrity.md`
  fail-closed для мутаций), стабильный текст `"owner-tuple registration not confirmed"`. **`DeadlineExceeded`
  — отклонён явно** (owner-tuple *регистрация* недоступна — это peer-unavailability, а не истечение
  общего дедлайна запроса; единый код с прочим fail-closed упрощает клиентскую retry-семантику). *(бывш. OQ-1)*
- **[FIX-2] Confirm-read обязан быть consistency-совместим с gateway scope_extractor `Check`.** Это
  **impl-требование**, не опция: confirm-проба обязана читать так, чтобы `op.done(success) ⟹
  следующий gateway `Check` немедленной мутации даёт ALLOW` — т.е. `HIGHER_CONSISTENCY`-preference
  на confirm-`Check`, **либо** тот же read-path/snapshot, что и gateway scope_extractor. Иначе
  eventual-consistency FGA оставит остаточное окно 403 (confirm видит tuple, а gateway `Check` —
  ещё нет). **OTG-04 — behavioral-lock этого требования** (ловит остаточное окно). *(бывш. OQ-3)*
- **[FIX-3] Orphan-tolerance на timeout-ветке (fail-closed без потери id).** На `op.error(Unavailable)`
  созданный ресурс durable, и его id **обнаружим** клиентом: `Operation.metadata` (`Create<Resource>Metadata`,
  populated at op-creation с выделенным resource-id — существующая LRO-конвенция) несёт `<resource-ref>`
  на **всех** терминальных состояниях, включая error. Клиент → `Get(<ref>)` (200, durable) и/или
  повторяет **мутацию** (tuple добивается drainer'ом), **НЕ пере-создаёт** (иначе orphan-дубль).
  **Idempotency-key на Create — ОТДЕЛЬНЫЙ тикет** (вне этой под-фазы). OTG-05b — lock этого. *(бывш. OQ-5)*

**Где выполняется ожидание confirm — НЕ предписывается acceptance'ом** (in-worker короткое окно
vs. hand-off register-drainer'у/confirmation-watcher'у, помечающему op `done` по confirm; оба
удовлетворяют наблюдаемый контракт §3). Выбор — за `rpc-implementer` / `system-design-reviewer`
(§8 OQ-2).

**Обоснование bounded-deadline→error (а не indefinite-pending):** *indefinite-pending* нарушает
«op не висит бесконечно» (перманентно деградированный IAM/FGA → op вечно PENDING, клиент поллит
бесконечно). *bounded-deadline→error* даёт терминал **и** сохраняет гарантию (успех-`done` только
после confirm): «валим» op гарантии, а не ресурс (intent durable, drainer добивает). Deadline
щедрый (нормальная пропагация ≪ deadline) → триггерится только на реальном outage; транзиентный
лаг поглощается in-deadline-ретраями confirm.

---

## 4. Scope (что входит / что НЕ входит)

**Входит — `Create` owner-ресурсов, где 403-окно ВОСПРОИЗВОДИТСЯ (зафиксировано владельцем, бывш. OQ-4):**

| Сервис | Owner-ресурсы (Create op-gated) | Confirm |
|---|---|---|
| **kacho-iam** | **AccessBinding** (канонический iam-представитель) | **in-process** FGA-read (leaf-owner; сети нет) |
| **kacho-vpc** | **Network, SecurityGroup, Subnet** | `InternalIAMService.Check` (существующее ребро svc→iam) |
| **kacho-compute** | **Instance, Disk** | `InternalIAMService.Check` (существующее ребро) |
| **kacho-storage** | **Volume** | `InternalIAMService.Check` (существующее ребро) |

Контракт op-gating **единообразен** и применяется на **общем Create-flow** каждого сервиса (там,
где эмитится owner-tuple register-intent), поэтому sibling owner-ресурсы того же сервиса
(vpc RouteTable/Address/Gateway/NetworkInterface, compute Image/Snapshot, storage Snapshot) **наследуют
gate by construction**. Явными тестами (§5/§6) покрыт **именно перечисленный выше набор** — это
covered/verified scope.

### 4.1 Премисс-подтверждение — iam AccessBinding (owner-tuple, а НЕ grant-tuple)

Проверено по `kacho-proto/proto/kacho/cloud/iam/v1/access_binding_service.proto` +
`kacho-iam/internal/apps/kacho/api/access_binding/{create.go,tuples.go}`:

- **`AccessBinding.Create`** = `POST /iam/v1/accessBindings` (body `*`) → `Operation`
  (metadata `CreateAccessBindingMetadata`, response `AccessBinding`). Gateway-authz **EXEMPT**
  (`permission = "<exempt>"`) — гейтит iam-handler (`requireGrantAuthority`). ⇒ 403 «no direct
  relations» **НЕ** на Create; окно — на **немедленных** `Update`/`Delete`.
- **`AccessBinding.Update`** = `PATCH /iam/v1/accessBindings/{access_binding_id}` и
  **`AccessBinding.Delete`** = `DELETE /iam/v1/accessBindings/{access_binding_id}` — оба несут
  `scope_extractor{object_type:"iam_access_binding", from_request_field:"access_binding_id"}`
  (+ `required_relation` `v_update`/`v_delete`). Резолвят `iam_access_binding:<id> → scope → caller`.
- `AccessBinding.Create` эмитит **in-tx** (fga_outbox, drainer применяет async) **два** класса tuple:
  **(a) grant/role-relation** `subject → <relation> → <resource_type>:<resource_id>` — доступ
  СУБЪЕКТА к ЦЕЛЕВОМУ ресурсу (**НЕ** объект op-gating'а); **(b) binding-OBJECT** — parent-pointer
  `project:<resId> #project @iam_access_binding:<bindingId>` + per-object owner/admin материализация
  на `iam_access_binding:<id>` (γ-01 / rbac-contract-a-fix `ReconcileObject`).
- **Премисс ПОДТВЕРЖДЁН:** gateway `scope_extractor{iam_access_binding}` немедленного Update/Delete
  потребляет **(b)** — объект op-gating-confirm = **binding-OBJECT per-object access (b)**, доступный
  через `scope_extractor{iam_access_binding}`, **а НЕ grant-tuple (a)**.
- **Прецедент:** iam уже запускает **синхронный post-commit reconciler (γ-01, `ReconcileObject`)**,
  чей заявленный intent — «per-object FGA tuples observable when the Operation reports done» (create.go:
  «Both run synchronously post-commit so a GET right after the Operation reports done does not race
  the async drain»). Данный фикс **behaviorally локает** эту гарантию (read-after-register confirm,
  даже когда γ-reconciler unwired/nil-safe и остаётся только async-drain) и **обобщает идентичную
  гарантию** на vpc/compute/storage (у них owner-tuple сейчас применяется **чисто async** через
  SEC-D drainer, без op-done confirm).

**НЕ входит (явно):**
- **op-gating для `Update`/`Delete` СУЩЕСТВУЮЩЕГО ресурса** — вне scope. Мутация существующего
  ресурса не создаёт новый owner-tuple → нового gate/confirm-wait **нет**; поведение как сегодня
  (OTG-16 — no-regression assert). (Update-on-labels re-emit SEC-D/T3.1 — не gate'ится.)
- **`UnregisterResource` / confirm снятия tuple** на Delete — вне scope (Delete не требует
  read-after-register; ресурс исчезает).
- Сам SEC-D механизм (outbox/drainer/sync-registrar/mTLS) — уже поставлен; здесь только
  **confirm-gate поверх** existing sync-registrar + reuse existing `Check`.
- **Idempotency-key на Create** (re-attach на timeout-retry) — отдельный тикет (§3.1 FIX-3).
- Изменение FGA-модели, новых object-типов, новых RPC ресурсов — нет.
- Placement-coherence, cross-service ref-validation — не трогаются (§5 OTG-11/12 — no-regression).

---

## 5. Сценарии (Given-When-Then) — основа integration- и newman-тестов

> ID-формат: `owner-tuple-opgate-<NN>` (трассируется в имена тестов). REST-пути — `/<service>/v1/<resource>`.
> JSON — camelCase. «poll до `done`» = `OperationService.Get(id)` до `done=true` (Watch RPC нет).
> Payload'ы Create — **существующие, без новых полей** (фикс поведенческий).

### 5.1 Happy path + гарантия

#### OTG-01 — Create → op-done(success) → немедленный Update создателем → 200 (vpc Network, canonical, newman)

**ID:** owner-tuple-opgate-01

**Given** dev-стенд (vpc + iam + openfga + api-gateway), register-drainer работает, seed-проект `<proj>`
**And** principal — создатель с permission на `Network.Create`/`Update` в `<proj>`

**When** клиент `POST /vpc/v1/networks {"projectId":"<proj>","name":"net-otg"}` → поллит `OperationService.Get` до `done=true`
**And** сразу после `done=true` (result=`response`) вызывает `PATCH /vpc/v1/networks/{id} {"updateMask":"description","description":"upd"}`

**Then** Create-Operation `done=true`, `result=response`, не `error`
**And** немедленный `PATCH` **принят** (возвращает `Operation`, HTTP 200) — **не** `403 PERMISSION_DENIED "no direct relations granted"`
**And** Update-Operation поллится до `done=true, !error`; `Get` отдаёт `description="upd"`

---

#### OTG-02 — Create → op-done(success) → немедленный Delete создателем → 200 (compute Instance, newman)

**ID:** owner-tuple-opgate-02

**Given** dev-стенд (compute + iam + api-gateway), seed-проект `<proj>`, principal-создатель
**When** клиент создаёт Instance существующим payload `POST /compute/v1/instances` → poll до `done=true, response`
**And** сразу вызывает `DELETE /compute/v1/instances/{id}`

**Then** Create-Operation `done, response`
**And** немедленный `DELETE` **принят** (`Operation`, 200) — **не** 403 «no direct relations granted»
**And** Delete-Operation → `done, !error`; последующий `Get` → `NOT_FOUND`

---

#### OTG-03 — op.done(success) наступает ТОЛЬКО после confirm owner-tuple (integration, ordering)

**ID:** owner-tuple-opgate-03

**Given** testcontainers Postgres схемы сервиса + SEC-D outbox-миграция; fake IAM/FGA confirm-порт под контролем теста (confirm DENY, пока тест не «зарегистрирует» tuple)
**And** Create-flow исполняется worker'ом

**When** worker создаёт ресурс (Insert + register-intent закоммичены), confirm-проба ещё DENY

**Then** Create-Operation наблюдаема `done=false` с progress-metadata `owner_tuple_registration=PENDING`
**And** ресурс-строка durable (`repo.Get` внутри → есть), register-intent durable (`fga_register_outbox` строка)
**And** как только confirm-проба начинает возвращать ALLOW → в течение confirm-окна Operation становится `done=true, result=response`
**And** момент `done=true(success)` **не предшествует** первому ALLOW confirm-пробы (тест фиксирует порядок)

---

### 5.2 Регрессия на owner-tuple-lag (ЯДРО фикса)

#### OTG-04 (КРИТИЧНО) — между op.done(success) и первой мутацией НЕТ 403 «no direct relations granted»

**ID:** owner-tuple-opgate-04

**Given** окружение, воспроизводящее прежний лаг: owner-tuple становится виден в FGA с задержкой (fake-FGA/стенд с искусственной пропагацией; confirm-read и gateway `Check` — под одной consistency-моделью, FIX-2)
**And** до фикса: `Create` op `done` раньше видимости tuple → немедленный `Update` → 403

**When** (integration/e2e) Create → poll до `done, response` → немедленный `Update`/`Delete` создателем в цикле (N повторов, чтобы отловить окно)

**Then** во **всех** N итерациях немедленная мутация **не** возвращает `PERMISSION_DENIED "no direct relations granted"` (регрессия закрыта op-gating'ом)
**And** RED-версия теста (op-gating выключен / прежнее поведение) этот 403 **воспроизводит** — подтверждение, что тест ловит именно баг (ban #12: RED до фикса)
**And** тест — behavioral-lock FIX-2 (consistency): если confirm видит tuple, но gateway `Check` ещё DENY → тест **красный** (ловит остаточное окно)

> Regression-lock на конкретный **код+текст** отсутствия 403 (`testing.md`), не только на «Update прошёл».

---

### 5.3 Failure-mode контракт (fail-closed) + orphan-tolerance

#### OTG-05 — IAM/FGA confirm недоступен/лагает → op НЕ ложно-done; PENDING → timeout → `op.error UNAVAILABLE`

**ID:** owner-tuple-opgate-05

**Given** testcontainers; confirm-порт (fake `Check`) настроен возвращать `Unavailable`/DENY дольше `confirmation deadline` (моделирует IAM/FGA outage)
**And** `confirmation deadline` = маленькое тестовое значение (напр. 500ms), нормальная пропагация ≪ него

**When** worker исполняет `Create` (writer-tx закоммичен — ресурс durable), confirm не достигается за deadline

**Then** до deadline Operation `done=false`, progress-metadata `PENDING` (не ложный success)
**And** по истечении deadline Operation `done=true, result=error`, `code=UNAVAILABLE`, `message="owner-tuple registration not confirmed"` — точный код+текст (стабильный, часть контракта; FIX-1)
**And** `code != DeadlineExceeded` (FIX-1 — явное отклонение альтернативы)
**And** `done=true` с **успехом** за весь тест **не** наблюдалось (invariant: no success-done без confirm)
**And** ресурс-строка и register-intent **остались durable** (не откачены timeout'ом)

---

#### OTG-05b (КРИТИЧНО — orphan-guard) — на timeout-`error` ресурс-ref обнаружим в op.metadata; Get→200; после drainer-добивки мутация → не 403

**ID:** owner-tuple-opgate-05b

**Given** сценарий OTG-05 (op завершилась `done=true, error(UNAVAILABLE, "owner-tuple registration not confirmed")`)

**When** клиент читает `OperationService.Get(<createOpId>)` на error-состоянии

**Then** `Operation.metadata` (`Create<Resource>Metadata`) несёт `<resource-ref>` (id созданного ресурса) — доступен НА error-пути (populated at op-creation, не только на success)
**And** `Get(<resource-ref>)` → **200** (ресурс durable, не orphan-без-id)
**And** затем confirm-порт/IAM «восстанавливается», register-drainer добивает owner-tuple (at-least-once)
**And** после добивки повторная мутация создателем (`Update`/`Delete` того же `<resource-ref>`) → **не** `403 "no direct relations granted"` (owner-tuple теперь виден)
**And** клиент **не** пере-создавал ресурс (id взят из op.metadata) — orphan-дубль не возникает (FIX-3)

> Закрывает fail-closed-дыру: `error(Unavailable)` без обнаружимого id → клиент пере-создаёт → orphan.

---

#### OTG-06 — durable backstop: после «восстановления» IAM/FGA drainer добивает tuple, ресурс используем (SEC-D-11 гарантия сохранена)

**ID:** owner-tuple-opgate-06

**Given** сценарий OTG-05 (op `error` Unavailable по timeout), register-intent durable
**And** confirm-порт/IAM «восстанавливается» (fake ALLOW), register-drainer запущен

**When** register-drainer обрабатывает durable register-intent (at-least-once) и tuple становится эффективен

**Then** register-intent помечен `sent_at IS NOT NULL` (drainer применил) — SEC-D-11 durable-гарантия «tuple не теряется» **сохранена** (supersede §0 не жертвует durability)
**And** `Get(<resource>)` возвращает ресурс (200), последующая мутация создателем → не 403

> Разграничение: op-gating гарантирует **success-path** (нет 403); timeout-path не жертвует durable-гарантией SEC-D.

---

### 5.4 Идемпотентность / at-least-once сохранены

#### OTG-07 — confirm-gate не ломает идемпотентность register-intent и exactly-once drainer'а

**ID:** owner-tuple-opgate-07

**Given** testcontainers; sync-registrar (confirm-шаг) вызывает `RegisterResource` синхронно И drainer позже берёт ту же durable-строку; `RegisterResource` идемпотентен (повтор → `OK`, не `AlreadyExists`) — контракт SEC-A
**And** confirm — read-only (`Check`), идемпотентна

**When** Create-flow: sync-registrar регистрирует + confirm ALLOW (op done); затем register-drainer обрабатывает ту же register-intent-строку

**Then** owner-tuple в FGA присутствует **ровно один раз** (повтор `RegisterResource` не создал дубля, вернул `OK`)
**And** drainer помечает строку `sent_at IS NOT NULL` без ошибки (exactly-once claim SEC-D не сломан op-gating'ом)
**And** confirm-пробы (сколько бы ни ретраились) не мутируют состояние (read-only)

---

### 5.5 Ацикличность / без нового ребра

#### OTG-08 — read-after-register через существующий `InternalIAMService.Check`; нового ребра нет; iam confirm'ит in-process

**ID:** owner-tuple-opgate-08

**Given** реализация фикса в vpc/compute/storage
**When** структурная проверка confirm-пути

**Then** confirm вызывает **существующий** `InternalIAMService.Check` (:9091, тот же authz-conn) — **новых RPC/новых cross-service рёбер не добавлено** (`polyrepo.md` runtime-edges без новой edge-записи сверх существующих `Check`/`RegisterResource`)
**And** iam **не** вызывает vpc/compute/storage обратно (ацикличность сохранена)
**And** для **kacho-iam** owner-ресурсов confirm выполняется **in-process** против собственного FGA-клиента (leaf-owner; сетевого вызова нет) — паритет наблюдаемого контракта, без ребра
**And** карта рёбер `polyrepo.md`/`data-integrity.md` не меняется (confirm — reuse, не new edge)

---

### 5.6 Negative / no-regression (Create-валидации не деградируют)

> op-gating применяется **только после успешного Insert ресурса**. Все прежние Create-валидации
> отрабатывают **до** writer-tx и возвращают те же коды/тексты, что и сегодня.

#### OTG-09 — invalid input / дубль-UNIQUE → те же коды (INVALID_ARGUMENT / ALREADY_EXISTS); gate не достигается

**ID:** owner-tuple-opgate-09
**Given** seed-проект
**When** (a) `Create` с невалидным полем (malformed `projectId` / пустое обязательное поле); (b) `Create` дубля по UNIQUE-констрейнту (напр. повторное имя там, где оно уникально)
**Then** (a) → `INVALID_ARGUMENT` (malformed id → sync `InvalidArgument "invalid <res> id '<X>'"` первым стейтментом), как до фикса; (b) → `ALREADY_EXISTS` (23505→AlreadyExists, как до фикса) — ресурс не создан, confirm-gate **не** входит в игру
**And** для **iam AccessBinding** дубль-Create (5-tuple) — **идемпотентный INSERT возвращает existing** (не `ALREADY_EXISTS`; by-design, proto §Create) → op `done, response` existing-binding; тоже не регрессирует

---

#### OTG-10 — ссылка на несуществующий/неготовый peer → `NOT_FOUND`/`FAILED_PRECONDITION` (как сегодня)

**ID:** owner-tuple-opgate-10
**Given** Create, ссылающийся на несуществующий peer-ресурс (напр. Instance→несуществующий Subnet)
**When** `Create`
**Then** тот же код, что и сегодня (`NOT_FOUND`/`FAILED_PRECONDITION` per `data-integrity.md`); gate не достигается

---

#### OTG-11 — cross-service owner недоступен на Create → `op.error UNAVAILABLE` (существующее fail-closed, отличать от confirm-timeout)

**ID:** owner-tuple-opgate-11
**Given** compute создаёт Instance с NIC, требующим vpc IPAM/ref-валидации; **kacho-vpc недоступен**
**When** `Instance.Create`
**Then** Operation `error UNAVAILABLE` — существующее cross-service fail-closed на request-path (SEC-D-23), **до** writer-tx/gate; **не** confirm-timeout-Unavailable (разные точки; на этой ветке ресурс НЕ создан — в отличие от OTG-05, где создан)

> Оба `Unavailable`, источники разные: OTG-11 — peer ref-validation (до Insert, ресурса нет);
> OTG-05 — owner-tuple confirm (после Insert, ресурс durable). Разграничение зафиксировано.

---

#### OTG-12 — placement-coherence mismatch на Create → `FAILED_PRECONDITION`/точный текст (no-regression)

**ID:** owner-tuple-opgate-12
**Given** Create с zone/region-mismatch (напр. Instance ↔ Disk/NIC разной зоны)
**When** `Create`
**Then** тот же `FAILED_PRECONDITION`/`InvalidArgument` + точный текст (`data-integrity.md` placement-coherence), что и до фикса; anycast/REGIONAL-ветка проходит; gate не достигается на отвергнутом Create

---

#### OTG-16 — Update/Delete СУЩЕСТВУЮЩЕГО ресурса НЕ получают новый gate (no-regression)

**ID:** owner-tuple-opgate-16

**Given** ресурс, созданный ранее (owner-tuple давно эффективен — не свеже-Create)
**When** создатель вызывает `Update`/`Delete` этого существующего ресурса

**Then** Operation обрабатывается **как сегодня** — **без** confirm-wait/op-gating (мутация существующего ресурса нового owner-tuple не создаёт)
**And** латентность op-completion не выросла на confirm-round-trip (gate — только на Create-пути)
**And** (integration) на Update/Delete-flow read-after-register confirm-порт **не** вызывается

---

### 5.7 Concurrency

#### OTG-13 — N конкурентных Create (один проект) → каждая op независимо gated и confirmed; ни одной 403 на немедленной мутации

**ID:** owner-tuple-opgate-13

**Given** testcontainers Postgres; register-drainer + confirm-порт работают; один проект `<proj>`
**When** тест запускает **N=20** конкурентных `Create` разных ресурсов (goroutines), затем для каждой — poll до `done, response` → немедленная мутация создателем

**Then** все 20 Create-Operation достигают `done=true, result=response` (каждая — после confirm своего owner-tuple)
**And** ни одна из 20 немедленных мутаций **не** получает 403 «no direct relations granted»
**And** register-drainer exactly-once claim не сломан (каждая register-intent-строка `sent_at IS NOT NULL` ровно раз; нет double-apply/miss — CAS SEC-D)
**And** тест гоняется под `-race`, детерминированно (`AwaitOpDone`, не `time.Sleep`)

> Concurrent integration-тест обязателен (ban #10/#12).

---

### 5.8 Cross-cutting контракт

#### OTG-14 — единообразие по сервисам (newman-матрица: iam/vpc/compute/storage)

**ID:** owner-tuple-opgate-14

**Given** dev-стенд со всеми сервисами
**When** для каждого представителя — Create → poll до `done, response` → немедленная мутация создателем:
  - iam **AccessBinding**: `POST /iam/v1/accessBindings` (существующий payload) → немедленный `DELETE /iam/v1/accessBindings/{id}` (либо `PATCH /iam/v1/accessBindings/{id} {"updateMask":"labels","labels":{"k":"v"}}`) — оба несут `scope_extractor{iam_access_binding}` (§4.1)
  - vpc **SecurityGroup** (`POST /vpc/v1/securityGroups`), **Subnet** (`POST /vpc/v1/subnets`)
  - compute **Disk** (`POST /compute/v1/disks`)
  - storage **Volume** (`POST /storage/v1/volumes`)

**Then** для **каждого** представителя немедленная мутация создателем **не** возвращает 403 «no direct relations granted» (единообразный op-gating)
**And** для iam AccessBinding немедленная мутация резолвится через `iam_access_binding:<id>` per-object access (объект (b) §4.1), подтверждая, что confirm-target — binding-OBJECT, не grant-tuple

---

#### OTG-15 — публичный контракт ресурсов не изменён (op-форма — additive-only)

**ID:** owner-tuple-opgate-15

**Given** ветки фикса
**When** `buf breaking` против baseline на публичных сервисах iam/vpc/compute/storage

**Then** breaking-diff = 0: форма ресурсов и REST-пути неизменны; `done`/`result`-семантика Operation неизменна
**And** если добавлено progress-metadata-поле `owner_tuple_registration` в LRO-metadata — оно **additive** (клиент, игнорирующий metadata, видит прежний `done`/`result`-контракт). Если решено НЕ вводить proto-поле (кодирование в существующем `Operation.metadata Any`/`description` без новых типов) — proto-diff = 0 (§8 OQ-6)
**And** newman happy-path по существующим публичным RPC — зелёный без изменения запросов/ответов (кроме исчезновения 403-окна)

---

## 6. Список тестов (TDD-red) — что подтверждает сценарии

### 6.1 Integration (testcontainers Postgres, `internal/repo/*integration_test.go` / `internal/clients/*_test.go` / use-case-level с fake confirm-порт)

| Тест | Сценарии | Репо |
|---|---|---|
| `create_op_done_only_after_tuple_confirm` — op `PENDING` пока confirm DENY; `done,response` только после ALLOW; ordering | OTG-03 | vpc (canonical) + compute/storage/iam |
| `create_no_403_window_regression` (КРИТИЧНО) — RED воспроизводит 403 при выкл. gate; GREEN — нет 403 в N итерациях; consistency-lock FIX-2 | OTG-04 | vpc (canonical), реплика в compute/storage/iam |
| `create_confirm_timeout_failclosed` — confirm > deadline → `op.error UNAVAILABLE`+точный текст; `code!=DeadlineExceeded`; no success-done; ресурс+intent durable | OTG-05 | vpc (canonical) + compute/storage |
| `create_timeout_resource_ref_in_metadata` (КРИТИЧНО orphan-guard) — на error op.metadata несёт resource-ref; `Get(ref)`→200; после drainer мутация→не 403; no re-create | OTG-05b | vpc (canonical) + iam |
| `create_confirm_timeout_then_drainer_backstop` — после recovery drainer добивает tuple (`sent_at` set); SEC-D-11 durability сохранена | OTG-06 | vpc |
| `confirm_gate_idempotent_with_drainer` — sync-register + drainer на одной intent; tuple ровно один; exactly-once не сломан; confirm read-only | OTG-07 | vpc |
| `confirm_uses_existing_check_no_new_edge` — confirm через `InternalIAMService.Check` (reuse authz-conn); iam confirm in-process | OTG-08 | vpc/compute/storage + iam |
| `update_delete_existing_not_gated` — Update/Delete существующего ресурса: confirm-порт НЕ вызывается; поведение как сегодня | OTG-16 | vpc/compute |
| `create_concurrent_gated_no_403` — 20 конкурентных Create, каждая confirmed, ни одной 403, drainer exactly-once, `-race` | OTG-13 | vpc (canonical) |
| `create_negatives_no_regression` — invalid/already_exists/notfound/precondition/placement/cross-owner-down → те же коды/тексты; gate не достигается | OTG-09,10,11,12 | vpc/compute |

### 6.2 Newman (black-box через api-gateway, `tests/newman/cases/*.py`)

| Кейс | Сценарии | Репо |
|---|---|---|
| `OTG-create-opdone-immediate-update` (happy) — Network Create → op done → немедленный Update → 200, нет 403 | OTG-01 | vpc |
| `OTG-create-opdone-immediate-delete` (happy) — Instance Create → op done → немедленный Delete → 200, нет 403 | OTG-02 | compute |
| `OTG-uniform-services` (happy-матрица) — AccessBinding/SecurityGroup/Subnet/Disk/Volume: Create→done→немедленная мутация→нет 403 | OTG-14 | iam/vpc/compute/storage |
| `OTG-no-403-window-regression` (regression) — цикл Create→done→immediate-mutate ловит отсутствие 403 «no direct relations granted» | OTG-04 | vpc |
| existing public regression — запросы/ответы неизменны (кроме исчезновения 403-окна) | OTG-15 | all |

### 6.3 Структурные / контрактные гейты

| Гейт | Сценарий |
|---|---|
| confirm — reuse `InternalIAMService.Check`, без нового cross-service ребра (code-review + `polyrepo.md` без новой edge-записи) | OTG-08 |
| `buf breaking` iam/vpc/compute/storage = 0 (op-форма additive-only или без proto-diff) | OTG-15 |
| `make -C services/vpc audit-list-filter` (vpc) зелёный — listauthz не сломан | (регрессия) |

---

## 7. Definition of Done

- [ ] `acceptance-reviewer` ✅ APPROVED данного doc (DRAFT → APPROVED). Остаточные OQ (§8) — impl/proto, не блокируют.
- [ ] KAC-тикет(ы) + ветки `KAC-<N>` в kacho-iam / kacho-vpc / kacho-compute / kacho-storage (порядок по build-графу; при proto-additive — kacho-proto первым).
- [ ] **RED → GREEN**: integration §6.1 написаны **до** кода; КРИТИЧНЫЕ `create_no_403_window_regression` (OTG-04) + `create_confirm_timeout_failclosed` (OTG-05) + `create_timeout_resource_ref_in_metadata` (OTG-05b) + concurrent `create_concurrent_gated_no_403` (OTG-13) — обязательны, без них merge запрещён (ban #10/#12). В PR — пара RED→GREEN.
- [ ] Confirm-порт (read-after-register) в use-case (port-интерфейс); impl — reuse `InternalIAMService.Check`-клиента (vpc/compute/storage) / in-process FGA-read (iam) в `clients/`; wiring — `cmd/<svc>`. **Consistency-совместимость с gateway `Check` (FIX-2)** обеспечена (HIGHER_CONSISTENCY или тот же read-path).
- [ ] Op-completion gate: success-`done` только после confirm; PENDING-metadata; bounded deadline → `op.error UNAVAILABLE` (стабильный текст `"owner-tuple registration not confirmed"`, FIX-1); resource-ref в op.metadata на всех терминалах (FIX-3); ресурс/intent durable во всех ветках.
- [ ] sync-registrar (SEC-D) переиспользован как confirm-шаг; register-drainer/at-least-once не сломан (OTG-06/07); SEC-D-11 durability сохранена.
- [ ] Newman §6.2 (happy + regression) зелёные на dev-стенде; исчезновение 403-окна подтверждено на всех представителях (OTG-14).
- [ ] `buf breaking` = 0 (или только additive metadata-поле) — OTG-15.
- [ ] Финальная верификация per-repo: `go test ./... -race` + `golangci-lint run` + `govulncheck` + (vpc) `make -C services/vpc audit-list-filter` + newman зелёные.
- [ ] Vault-trail:
  - [ ] `obsidian/kacho/edges/{vpc,compute,storage}-to-iam-fgaproxy.md` — секция «op-gating: Create-op ждёт read-after-register confirm (via `Check`, reuse); supersede SEC-D-11 (fail-closed по deadline, durability сохранена)» + «History» с KAC.
  - [ ] `obsidian/kacho/edges/iam-to-openfga-grant-write.md` — «iam confirm in-process (binding-OBJECT per-object access) перед op-done; γ-01 behaviorally locked».
  - [ ] `obsidian/kacho/rpc/iam-internal-iam-service.md` — `Check` used-by op-gating confirm (RPC не меняется).
  - [ ] Затронутые `resources/*` (Network/SecurityGroup/Subnet/Instance/Disk/Volume/AccessBinding) — пометка «Create op-done gated на owner-tuple confirm».
  - [ ] `obsidian/kacho/KAC/KAC-<N>.md` — trail + PR-URL + статус.
- [ ] Соответствующие GitHub Issues (owner-tuple-lag 403) — закрыты со ссылкой на PR; **idempotency-key-на-Create** заведён как отдельный follow-up-Issue (§3.1 FIX-3).
- [ ] YouTrack KAC: `In Progress` → `Test` → `Done` по merge + smoke; PR-ссылки + лог тестов RED→GREEN комментарием.
- [ ] Заказчик — финальный smoke/e2e (`make -C deploy e2e-test` / `grpcurl`): Create Network → poll op done → **немедленный** Update/Delete тем же creator → 200, без 403 «no direct relations granted».

---

## 8. Остаточные Open questions (impl/proto — НЕ блокируют approve)

> OQ-1/OQ-3/OQ-4/OQ-5 — **разрешены** (см. §3.1 FIX-1/2/3 и §4/§4.1). Ниже — только не блокирующие impl/proto-выборы.

| ID | Вопрос | Рекомендация автора |
|---|---|---|
| **OQ-2** | Где ждать confirm: in-worker короткое окно vs. hand-off register-drainer/confirmation-watcher, который флипает op `done` по confirm? | **Hand-off/watcher** предпочтителен (не держит worker-слот на degraded-пути; happy-path — быстрый in-worker confirm через sync-registrar). Acceptance фиксирует **наблюдаемое** (§3/§5); impl-выбор — `system-design-reviewer`. |
| **OQ-6** | Progress-metadata `owner_tuple_registration=PENDING` — новое proto-поле в LRO-metadata (additive) vs кодирование в существующем `Operation.metadata Any`/`description` без новых типов? | **Additive-поле** или reuse существующего metadata — форма LRO не breaking (OTG-15). Если новое поле — `proto-api-reviewer` + `buf breaking`. Минимизировать proto-поверхность. |

---

## 9. Ссылки

- SEC-D (owner-tuple transactional-outbox + register-drainer + sync-registrar, что расширяем; SEC-D-11 supersede): `docs/specs/sub-phase-SEC-D-services-fga-via-iam-mtls-acceptance.md`.
- iam-anchor-grant (γ-01 post-commit reconciler «per-object tuples observable at op-done»): `docs/specs/iam-anchor-grant-and-invite-activation-fga-acceptance.md`.
- W1.1 (drainer mechanics, переиспользуется): `docs/specs/sub-phase-W1.1-fga-outbox-drainer-acceptance.md`.
- Edges (механизм owner-tuple + история): `obsidian/kacho/edges/{vpc,compute,storage}-to-iam-fgaproxy.md`, `edges/iam-to-openfga-grant-write.md`.
- iam Internal RPC (`Check`, `RegisterResource`): `obsidian/kacho/rpc/iam-internal-iam-service.md`; proto `kacho-proto/proto/kacho/cloud/iam/v1/internal_iam_service.proto`.
- AccessBinding премисс (ground truth): `kacho-proto/proto/kacho/cloud/iam/v1/access_binding_service.proto` (scope_extractor `iam_access_binding`, Create authz-exempt), `kacho-iam/internal/apps/kacho/api/access_binding/{create.go,tuples.go}` (grant-tuple vs binding-OBJECT parent-pointer + γ-01 reconciler).
- Правила: `.claude/rules/{api-conventions,data-integrity,security,polyrepo,testing}.md`.
