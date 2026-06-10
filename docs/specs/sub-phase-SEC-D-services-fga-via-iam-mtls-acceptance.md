# Sub-phase SEC-D — vpc/compute/nlb: FGA via IAM (transactional-outbox) + opt-in mTLS — Acceptance

> **Статус:** DRAFT
> **Дата:** 2026-06-11
> **Ревьюер:** `acceptance-reviewer` (единственный gate ✅ APPROVED — ban #1; заказчик к контракту не подключается, проверяет только финальный e2e/smoke)
> **Эпик/тикет:** KAC-<N> (subtask of эпик `[EPIC] SEC — mTLS + IAM-fronted authz`, см. `docs/specs/sub-phase-SEC-mtls-iam-authz-epic.md`)
> **Автор-агент:** `acceptance-author`
> **Затронутые репо:** `kacho-vpc`, `kacho-compute`, `kacho-nlb` (+ outbox-миграция в каждом через `migration-writer` / `db-architect-reviewer`).
> **Зависит от:** SEC-A (proto: `InternalIAMService.RegisterResource`/`UnregisterResource`, idempotent, permission `iam.fgaproxy.write`), SEC-B (corelib mTLS creds в `grpcsrv`/`grpcclient` + config `TLSServer`/`TLSClient`), SEC-C (IAM применяет `RegisterResource`/`Unregister` через свой `fga_outbox`+drainer, идемпотентность GWT, client-cert→SA mapping).

---

## 0. Обзор

SEC-D устраняет прямой доступ vpc/compute/nlb к FGA (нарушение требования эпика **#6**) и
закрывает связанный с ним dual-write-баг (эпик §3.1 C1, GitHub Issue **N5**). Сегодня
vpc/compute публикуют owner/hierarchy-tuple **best-effort** через `fgawrite.Emit(...)` уже
**после** `commit` ресурса; ошибка проглатывается (`fgawrite.go`: «Failures are logged,
never returned»). При сбое FGA tuple теряется навсегда → per-resource `Check` = DENY →
пользователь создал ресурс и не видит его.

SEC-D реализует **Вариант A (transactional-outbox, эпик §3.1 / §6.1)**: намерение
«register owner-tuple» пишется строкой в outbox **в той же writer-tx, что и Insert
ресурса** (один commit — no dual-write). Отдельный drainer (corelib `outbox/drainer`,
под advisory-lock) вызывает `InternalIAMService.RegisterResource` по mTLS; IAM применяет
tuple через свой `fga_outbox`+drainer. IAM `Unavailable` → drainer retry с backoff,
**tuple не теряется**, Operation не падает. Симметрично: Delete ресурса → Unregister-intent.

Параллельно SEC-D включает **opt-in mTLS** (corelib SEC-B) на исходящих рёбрах
vpc/compute/nlb (server + client cert), управляемый per-edge флагами; `enable=false` =
текущее insecure-поведение (dev backward-compat, эпик §5).

**Публичные ресурсные контракты НЕ меняются** (требование эпика **#8**): proto-форма
Network/Subnet/SG/RT/Address/Gateway/NIC, Instance/Disk/Image/Snapshot,
NLB/Listener/TargetGroup и их REST-пути остаются прежними; новое — только Internal IAM
FGA-proxy (доставлен в SEC-A), который vpc/compute/nlb **вызывают**, а не определяют.

### Трассировка требований эпика → стадии SEC-D

| Эпик | Где закрывается в SEC-D |
|---|---|
| #6 (модули не ходят в FGA напрямую — только через IAM) | S1 (удаление `openfga_write_client.go` + `fgawrite`-direct-HTTP), S2 (drainer→IAM по mTLS) |
| #8 (контракты не меняются, кроме Internal FGA-proxy) | S1/S2 — vpc/compute/nlb только consumer'ы Internal RPC из SEC-A; public proto-diff = 0 (Сценарий SEC-D-22) |
| #1/#5 (mTLS opt-in, не ломает dev; раздельные client+server cert) | S3 (mTLS server+client per-edge, enable=false=insecure) |
| §3.1 C1 / §6.1 (dual-write → Вариант A outbox) | S1 (intent в writer-tx), S2 (drainer добивает) |
| §6.7 (fail-closed: IAM Unavailable для мутаций) | S2 (drainer retry; для NIC IPAM cross-service мутации — Unavailable), S3 (mTLS handshake fail → Unavailable) |
| §6.5 (rollback per-edge feature-flag) | S3 (каждое ребро independent enable; mismatch → Unavailable) |
| GitHub Issue N5 (best-effort dual-write) | S1 (закрытие — outbox в writer-tx; Issue → closed по merge) |

### Не входит в SEC-D (явно)

- Сами proto-RPC `RegisterResource`/`UnregisterResource` и permission `iam.fgaproxy.write` — **SEC-A** (здесь только consumption).
- IAM-сторона применения tuple (`fga_outbox`+drainer в kacho-iam, client-cert→SA mapping, least-priv SA-роли seed) — **SEC-C**.
- corelib TLS-creds primitives (`grpcsrv`/`grpcclient` TLS, identity-extractor из client-cert) — **SEC-B** (здесь — их wiring в vpc/compute/nlb).
- cert-manager PKI, per-svc Certificate ×2, helm mTLS-values, NetworkPolicy openfga←iam — **SEC-F**.
- api-gateway backend-dial на mTLS — **SEC-E**. Оператор + kube-ovn на mTLS — **SEC-G**.

---

## 1. Связь с регламентом и запретами (нормативно — детали в `.claude/rules/*`, не дублируем)

| Регламент | Где соблюдаем в SEC-D |
|---|---|
| ban #1 (acceptance-first) | данный doc — gate; код только после ✅ APPROVED. |
| ban #6 / `security.md` (Internal.* не на external) | `RegisterResource`/`UnregisterResource` — Internal-only RPC IAM (:9091), вызываются service→service напрямую, не через external endpoint. |
| ban #7 (без брокера) | outbox = in-process LISTEN/NOTIFY + Postgres; drainer = corelib `outbox/drainer`; никакого Kafka/NATS. |
| ban #8 / #4 (DB-per-service, no cross-service cascade) | outbox-таблица — в БД своего сервиса (`kacho_vpc`/`kacho_compute`/`kacho_nlb`); cross-service связь — только по API (IAM RPC). |
| ban #9 (мутации → Operation) | Create/Update/Delete остаются async через `Operation`; outbox-intent — внутри worker writer-tx. |
| ban #10 / `data-integrity.md` (within-service инварианты на DB-уровне; CAS claim, concurrent race-тест) | drainer-claim — атомарный `UPDATE … WHERE sent_at IS NULL …` (как в W1.1); concurrent-тест обязателен (Сценарии SEC-D-12, SEC-D-13). |
| ban #11/#12 (TDD, тесты в том же PR) | RED integration + newman (где применимо) до кода; §6 — источник сценариев. |
| `data-integrity.md` §cross-domain / §6.7 | IAM недоступен для мутации tuple → drainer retry (intent durable); cross-service NIC IPAM-мутация при vpc `Unavailable` → `Unavailable`. |
| `api-conventions.md` (error-format) | негативные сценарии указывают точный gRPC-код; тексты ошибок — часть контракта. |
| `architecture.md` (clean arch) | drainer wiring — в `cmd/<svc>/main.go` (composition root); applier — `internal/clients/` adapter; port — в use-case. |

---

## 2. Глоссарий (SEC-D-специфика)

- **FGA-register-intent** — строка в outbox-таблице сервиса с `event_type` ∈
  {`fga.register`, `fga.unregister`} и payload — набор tuple-«намерений» (project-hierarchy,
  creator, parent-link), которые нужно зарегистрировать в IAM для созданного/удалённого ресурса.
  Пишется **в той же writer-tx, что и Insert/Delete ресурса**.
- **register-drainer** — экземпляр corelib `outbox/drainer` в каждом из vpc/compute/nlb,
  применяющий FGA-register-intent через вызов `InternalIAMService.RegisterResource`
  (или `UnregisterResource`) по mTLS. Под `pg_advisory_xact_lock` — одна реплика дренит.
- **`RegisterResource` (idempotent, SEC-A)** — Internal RPC IAM: повтор того же owner-tuple →
  gRPC `OK` (НЕ `AlreadyExists`); это контракт, от которого зависит retry-цепочка.
- **`UnregisterResource` (idempotent, SEC-A)** — Internal RPC IAM: delete отсутствующего tuple → `OK`.
- **per-edge mTLS flag** — независимый `enable` на каждое исходящее ребро сервиса
  (`vpc→iam`, `vpc→compute`, `compute→iam`, `compute→vpc`, `nlb→iam`, `nlb→vpc`, `nlb→compute`)
  + server-side enable на listener сервиса. `enable=false` → insecure (текущее поведение).
- **mTLS edge** — пара (server-cert на принимающем listener + client-cert на дилящем
  клиенте, оба из internal CA); `RequireAndVerifyClientCert` на сервере.
- **grep-gate** — DoD-проверка эпика §5: `grep -rn "openfga" <svc>/internal/clients/` = 0
  (прямого FGA-клиента в clients/ больше нет).

---

## 3. Стадии (каждая — самостоятельный end-to-end deliverable со своим DoD)

SEC-D дробится на 3 стадии. Стадии выполняются по порядку (S1 → S2 → S3), но **каждая
мёржится отдельным PR-набором** и оставляет main в рабочем состоянии:

| Стадия | Содержание | Тип-флага в main |
|---|---|---|
| **S1** | outbox-миграция в vpc/compute/nlb; FGA-register-intent пишется в writer-tx ресурса (Create→register, Delete→unregister); `fgawrite.Emit`-direct-HTTP заменён на outbox-write; `openfga_write_client.go` удалён | Поведение per-resource Check НЕ деградирует: intent durable; **register-drainer ещё не включён** → новый flag `KACHO_<SVC>_FGA_REGISTER_DRAINER_ENABLED` (default `false`) — при false старый best-effort путь оставлен **временно** недоступен? Нет: S1 включает запись intent + drainer одновременно в dev (drainer default-on внутри одного сервиса, ибо без него ресурсы вообще не получат tuple). См. §3.1. |
| **S2** | register-drainer → `InternalIAMService.RegisterResource`/`UnregisterResource`; идемпотентность; retry на `Unavailable`; критичный «IAM down → tuple не теряется» | drainer-on (in-process, не cross-cluster flag) |
| **S3** | mTLS server+client per-edge через corelib (SEC-B); per-edge `*_MTLS_ENABLED` флаги; `enable=false`=insecure; fail-closed на handshake-mismatch | `*_MTLS_ENABLED` default `false` (dev unchanged) |

### 3.1 Замечание по S1 «no-regression»

Старый `fgawrite.Emit` best-effort выполнял запись tuple после commit. SEC-D заменяет
его на: (a) запись intent в outbox в той же tx + (b) register-drainer, применяющий intent
через IAM. Чтобы S1 не оставил ресурсы без tuple, **запись intent и register-drainer
поставляются в одном PR-наборе стадии** (drainer — внутренняя goroutine, не cross-cluster
rollout-flag). FGA НЕ становится недостижимым — IAM по-прежнему доступен по существующему
ребру (mTLS включается только в S3). Таким образом после S1+S2 поведение «ресурс получает
tuple» **строго лучше** прежнего (durable intent vs lost-on-error), а dev продолжает
работать (drainer дилит IAM insecure, как сегодня все service→service).

---

## 4. Какие tuple пишет каждый сервис (для точности payload в сценариях)

| Сервис | tuple-типы в register-intent (источник — текущий `fgawrite`) |
|---|---|
| **kacho-vpc** | project-hierarchy: `project:<projectId> #project @vpc_<resource>:<id>` для каждого создаваемого ресурса (network/subnet/security_group/route_table/address/gateway/network_interface); + при Network.Create — также `vpc_security_group:<defaultSgId>` (KAC-133). |
| **kacho-compute** | project-hierarchy: `project:<projectId> #project @compute_<resource>:<id>` (instance/disk/image/snapshot). |
| **kacho-nlb** | project-hierarchy: `project:<projectId> #project @lb_*:<id>`; creator: `<subject> #admin @lb_*:<id>` (если principal не system); parent-link: напр. `lb_network_load_balancer:<lbId> #load_balancer @lb_listener:<id>`. |

`RegisterResource`-payload (SEC-A контракт) принимает набор tuple-намерений; SEC-D
сериализует именно эти типы. На Delete — симметричный `UnregisterResource` для
project-hierarchy/parent-link tuple созданного ресурса.

---

## 5. Test discipline (ban #11/#12) — RED first

Каждый PR-набор стадии содержит integration-тест на testcontainers Postgres, написанный
**до** кода, с парой `RED → GREEN` в описании. Список тестов — §7. Где применимо (S2
end-to-end через api-gateway, S3 mTLS-mismatch на железе) — newman happy+negative. Drainer
mechanics уже покрыт corelib W1.1; SEC-D добавляет **consumer-applier** (RegisterResource)
+ outbox-в-writer-tx + concurrent-claim + IAM-down-resilience.

---

## 6. Сценарии (Given-When-Then) — основа integration- и newman-тестов

> ID-формат: `SEC-D-<NN>` (трассируется в имена тестов). REST-пути — `/<service>/v1/<resource>`.
> JSON — camelCase. Для async-мутаций «`Operation.done && !error`, затем `Get`» подразумевает
> полл `OperationService.Get(id)` до `done=true` (Watch RPC не существует).

### 6.1 S1 — intent в writer-tx ресурса (transactional-outbox), удаление прямого FGA

#### Сценарий SEC-D-01 — Create пишет FGA-register-intent в той же writer-tx, что и Insert (vpc)

**ID:** SEC-D-01

**Given** testcontainers Postgres со схемой `kacho_vpc` + новой outbox-миграцией применённой
**And** register-drainer **остановлен** (изолируем запись от применения)
**And** проект `proj-aaaaaaaaaaaaaaaaa` существует (peer ProjectClient — stub `exists=true`)

**When** worker исполняет `Network.Create` (project_id=`proj-aaaaaaaaaaaaaaaaa`, name=`net-a`) до `Commit()`

**Then** после `Commit()` в outbox-таблице сервиса ровно одна строка с `event_type='fga.register'`, `resource_kind='Network'`, `resource_id=<netId>`, `sent_at IS NULL`
**And** payload строки содержит tuple-намерение `project:proj-aaaaaaaaaaaaaaaaa #project @vpc_network:<netId>`
**And** в той же tx уже есть domain-outbox-строка `Network/CREATED` (обе видны после одного Commit)

---

#### Сценарий SEC-D-02 — Insert ресурса откатывается → register-intent НЕ остаётся (атомарность)

**ID:** SEC-D-02

**Given** Postgres + outbox-миграция; register-drainer остановлен
**And** worker writer-tx искусственно прерывается (`Abort()` вместо `Commit()` — напр. inline default-SG creation вернула ошибку)

**When** worker исполняет `Network.Create` и tx абортится

**Then** в outbox-таблице **нет** строки `fga.register` для этого ресурса (intent и Insert — один commit; оба откатились)
**And** в таблице `networks` нет orphan-строки

---

#### Сценарий SEC-D-03 — Delete пишет FGA-unregister-intent в той же writer-tx (vpc)

**ID:** SEC-D-03

**Given** Network `net-a` существует без детей; register-drainer остановлен

**When** worker исполняет `Network.Delete(<netId>)` до `Commit()`

**Then** после `Commit()` в outbox-таблице есть строка `event_type='fga.unregister'`, `resource_id=<netId>`, `sent_at IS NULL`
**And** payload содержит tuple-намерение на удаление `project:... #project @vpc_network:<netId>` (+ default-SG, если применимо)
**And** строка ресурса `networks.<netId>` удалена в той же tx (либо обе видны, либо ни одной)

---

#### Сценарий SEC-D-04 — compute: Instance.Create пишет register-intent в writer-tx

**ID:** SEC-D-04

**Given** Postgres `kacho_compute` + outbox-миграция; register-drainer остановлен; project существует

**When** worker исполняет `Instance.Create` (project_id, name=`vm-a`) до `Commit()`

**Then** после `Commit()` ровно одна строка `fga.register`, `resource_kind='Instance'`, `resource_id=<instId>`, `sent_at IS NULL`
**And** payload содержит `project:<projectId> #project @compute_instance:<instId>`

---

#### Сценарий SEC-D-05 — nlb: LoadBalancer.Create пишет register-intent (project + creator + parent-link)

**ID:** SEC-D-05

**Given** Postgres `kacho_nlb` + outbox-миграция; register-drainer остановлен
**And** principal в контексте — `user:usr-xxxxxxxxxxxxxxxxx` (не system)

**When** worker исполняет `NetworkLoadBalancer.Create` (project_id, name=`lb-a`) до `Commit()`

**Then** после `Commit()` строка `fga.register`, `resource_id=<lbId>`, `sent_at IS NULL`
**And** payload содержит project-hierarchy `project:<projectId> #project @lb_network_load_balancer:<lbId>` И creator `user:usr-xxxxxxxxxxxxxxxxx #admin @lb_network_load_balancer:<lbId>`

---

#### Сценарий SEC-D-06 — nlb: system-initiated Create НЕ пишет creator-tuple (только project-hierarchy)

**ID:** SEC-D-06

**Given** Postgres `kacho_nlb` + outbox-миграция; register-drainer остановлен
**And** principal — system / unauthenticated (`SubjectFromPrincipal` → "")

**When** worker исполняет `NetworkLoadBalancer.Create`

**Then** payload register-intent содержит project-hierarchy tuple, но **не** содержит creator-tuple (паритет с прежним `EmitCreator`-skip-on-empty-subject)

---

#### Сценарий SEC-D-07 — `openfga_write_client.go` удалён; grep openfga в clients/ = 0 (структурный гейт)

**ID:** SEC-D-07

**Given** ветки SEC-D смёржены в каждом из kacho-vpc / kacho-compute / kacho-nlb

**When** выполняется DoD-проверка `grep -rn "openfga" <repo>/internal/clients/`

**Then** для всех трёх репо вывод пуст (exit code 1) — прямого FGA-HTTP-клиента в `clients/` нет
**And** файлы `internal/clients/openfga_write_client.go` (vpc, compute) отсутствуют
**And** `internal/fgawrite/` (vpc/compute/nlb) либо удалён, либо более не делает прямой FGA-вызов (только сериализация intent для outbox)

---

#### Сценарий SEC-D-08 — GitHub Issue N5 (best-effort dual-write) закрыт

**ID:** SEC-D-08

**Given** S1 смёржен (intent в writer-tx, прямой best-effort путь удалён)

**When** ревьюер проверяет GitHub Issue N5 в kacho-vpc и kacho-compute (эпик §3.1 «прод-баг N5»)

**Then** оба Issue закрыты с ссылкой на SEC-D PR; в теле — обоснование «dual-write устранён транзакционным outbox»

---

### 6.2 S2 — register-drainer → IAM.RegisterResource (mTLS), идемпотентность, IAM-down resilience

#### Сценарий SEC-D-09 — happy: register-intent применён через IAM.RegisterResource, intent помечен sent

**ID:** SEC-D-09

**Given** Postgres + outbox-миграция; register-drainer запущен; fake `InternalIAMClient` (record-recorder, возвращает `OK`)
**And** в outbox одна строка `fga.register` (`@vpc_network:<netId>`, `sent_at IS NULL`)

**When** drainer получает NOTIFY / catch-up

**Then** в течение 2s fake-IAMClient зафиксировал ровно один вызов `RegisterResource` с tuple-намерением `project:... #project @vpc_network:<netId>`
**And** outbox-строка помечена `sent_at IS NOT NULL`, `last_error IS NULL`

---

#### Сценарий SEC-D-10 — happy: unregister-intent применён через IAM.UnregisterResource

**ID:** SEC-D-10

**Given** register-drainer запущен; fake-IAMClient возвращает `OK`
**And** в outbox одна строка `fga.unregister` для `@compute_instance:<instId>`

**When** drainer обрабатывает строку

**Then** fake-IAMClient зафиксировал один вызов `UnregisterResource` с соответствующим tuple
**And** outbox-строка помечена `sent_at IS NOT NULL`

---

#### Сценарий SEC-D-11 (КРИТИЧНО) — IAM Unavailable при Create → ресурс создан, owner-tuple НЕ потерян навсегда (drainer добивает после восстановления)

**ID:** SEC-D-11

**Given** Postgres + outbox-миграция; register-drainer запущен
**And** fake-IAMClient настроен возвращать `codes.Unavailable` на первые N вызовов, затем `OK` (моделирует IAM down → recovery)
**And** `BackoffMin=100ms`, `BackoffMax=500ms` (для теста)

**When** worker исполняет `Network.Create` (commit успешен — ресурс durable), drainer пытается применить register-intent, получает `Unavailable` N раз

**Then** `Network.Create` Operation завершается `done=true` без error (мутация НЕ падает из-за недоступности IAM — §6.1/§6.7: tuple-применение асинхронно, не на hot-path Operation)
**And** `Get(<netId>)` возвращает ресурс с заполненными `id`, `createdAt`, `name`
**And** outbox-строка register-intent остаётся `sent_at IS NULL`, `last_error LIKE '%Unavailable%'`, `attempt_count` растёт (intent durable, не потерян)
**And** после «восстановления» IAM (fake начинает возвращать `OK`) в течение 2s drainer добивает: fake-IAMClient зафиксировал успешный `RegisterResource`, outbox-строка `sent_at IS NOT NULL`
**And** окно DENY на per-resource Check конечно и закрывается (в отличие от прежнего best-effort — навсегда DENY)

---

#### Сценарий SEC-D-12 — повторный drainer-вызов идемпотентен (RegisterResource повтор → OK, не AlreadyExists)

**ID:** SEC-D-12

**Given** register-drainer запущен; fake-IAMClient моделирует SEC-A-контракт: повтор того же tuple → `OK` (НЕ `AlreadyExists`)
**And** drainer применил register-intent, но «упал» **до** записи `sent_at` (моделируем crash между apply и mark — kill после RPC OK, до UPDATE)

**When** drainer перезапускается и повторно берёт ту же строку (`sent_at` всё ещё NULL)

**Then** второй вызов `RegisterResource` с тем же tuple возвращает `OK` (идемпотентно)
**And** drainer помечает строку `sent_at IS NOT NULL` без ошибки
**And** в IAM (через fake-recorder) tuple присутствует ровно один раз — повтор не создал дубль и не вернул `AlreadyExists`

---

#### Сценарий SEC-D-13 — concurrent: две реплики register-drainer → каждый intent применён ровно раз (advisory-lock / CAS-claim)

**ID:** SEC-D-13

**Given** Postgres + outbox-миграция; **две** реплики register-drainer на одной БД (моделирует 2 pod'а сервиса) с разными pool'ами
**And** fake-IAMClient — shared counter per tuple
**And** advisory-lock (`pg_advisory_xact_lock`) и/или атомарный claim `UPDATE … WHERE sent_at IS NULL RETURNING …` на claim-пути

**When** тест INSERT'ит 20 register-intent строк одной волной

**Then** в течение 3s все 20 строк помечены `sent_at IS NOT NULL`
**And** fake-IAMClient-counter показывает ровно 20 успешных `RegisterResource` (no double-apply, no miss — exactly-once across replicas)

> Гарантия — атомарный CAS-claim (`data-integrity.md`); concurrent integration-тест обязателен (ban #10).

---

#### Сценарий SEC-D-14 — permanent error от IAM (InvalidArgument на malformed tuple) → poison, не бесконечный retry

**ID:** SEC-D-14

**Given** register-drainer запущен; fake-IAMClient возвращает `codes.InvalidArgument` (моделирует SEC-C poison-классификацию — невалидный tuple)
**And** в outbox строка с заведомо невалидным payload

**When** drainer обрабатывает строку

**Then** строка помечена poisoned (`attempt_count >= MaxAttempts`, `last_error LIKE '%InvalidArgument%'`), `sent_at IS NULL` (не retry бесконечно)
**And** drainer продолжает обрабатывать следующие (нормальные) строки — не застревает на poison

---

#### Сценарий SEC-D-15 — e2e (newman, через api-gateway): Create → Get показывает ресурс после применения tuple

**ID:** SEC-D-15

**Given** dev-стенд (vpc + iam + openfga + api-gateway), register-drainer работает, mTLS=off (dev)
**And** project существует, principal с permission на ресурс

**When** клиент вызывает `POST /vpc/v1/networks` (payload: projectId, name) → получает `Operation`; поллит `OperationService.Get` до `done=true`

**Then** Operation `done=true`, `!error`
**And** в течение разумного окна (eventual) `GET /vpc/v1/networks/{id}` возвращает 200 с `id`, `createdAt`, `name`, `projectId` (per-resource Check резолвится — tuple применён через IAM)
**And** `DELETE /vpc/v1/networks/{id}` → Operation done → последующий `GET` → 404

---

### 6.3 S3 — opt-in mTLS server+client (per-edge флаги)

#### Сценарий SEC-D-16 — mTLS disabled (default) → текущее insecure-поведение, dev не сломан

**ID:** SEC-D-16

**Given** все `*_MTLS_ENABLED` флаги = `false` (default), сервисы стартуют как сегодня
**And** corelib `TLSServer.enable=false` / `TLSClient.enable=false`

**When** vpc дилит iam (`RegisterResource`), compute дилит vpc (NIC IPAM), nlb дилит iam/vpc/compute

**Then** все вызовы проходят по insecure-каналу (как до SEC-D)
**And** существующие integration/newman-тесты зелёные без изменений конфигурации (backward-compat, эпик §5)

---

#### Сценарий SEC-D-17 — mTLS enabled на ребре vpc→iam → handshake успешен с валидным client-cert

**ID:** SEC-D-17

**Given** mTLS включён на ребре vpc→iam: IAM internal listener `TLSServer.enable=true` (server-cert + client-CA, `RequireAndVerifyClientCert`); vpc-клиент `TLSClient.enable=true` (client-cert vpc + server-CA + server_name `<iam-svc>`)
**And** оба cert выпущены одним internal CA (SEC-B/SEC-F primitive; тест — self-signed CA в testcontainers/bufconn)

**When** vpc register-drainer вызывает `InternalIAMService.RegisterResource` по mTLS

**Then** TLS-handshake успешен, IAM принимает peer (client-cert verified из internal CA)
**And** RPC возвращает `OK`, register-intent помечен `sent_at IS NOT NULL`
**And** server-side: client-cert identity (SPIFFE-like SAN `spiffe://kacho/<sva-id>`) доступна IAM для логирования (инвариант principal⟺mTLS, эпик I2; mapping SA — SEC-C)

---

#### Сценарий SEC-D-18 — mTLS edge compute→vpc (NIC IPAM) → handshake успешен

**ID:** SEC-D-18

**Given** mTLS включён на ребре compute→vpc: vpc internal listener TLSServer.enable=true; compute-клиент TLSClient.enable=true (client-cert compute + server-CA + server_name `<vpc-svc>`)

**When** compute вызывает vpc `InternalAddressService` (IPAM-аллокация) при NIC-spec-валидации

**Then** handshake успешен, RPC проходит по mTLS
**And** insecure-вызов на тот же listener (без client-cert) отклоняется (см. SEC-D-20)

---

#### Сценарий SEC-D-19 — mTLS edge vpc→compute (zone_id validation) → handshake успешен

**ID:** SEC-D-19

**Given** mTLS включён на ребре vpc→compute: compute internal/public listener TLSServer.enable=true; vpc-клиент TLSClient.enable=true (server_name `<compute-svc>`)

**When** vpc вызывает `compute.v1.ZoneService.Get` при валидации `zone_id` (Subnet.Create)

**Then** handshake успешен, RPC проходит по mTLS; Subnet.Create Operation завершается `done=true`

---

#### Сценарий SEC-D-20 — fail-closed: client без client-cert на mTLS-listener → отклонён (не insecure-fallback)

**ID:** SEC-D-20

**Given** IAM internal listener `TLSServer.enable=true` (`RequireAndVerifyClientCert`)
**And** клиент дилит без client-cert (insecure или TLS-only без cert)

**When** клиент вызывает `RegisterResource`

**Then** TLS-handshake отклонён сервером (нет валидного client-cert из internal CA); клиент получает transport-ошибку, маппящуюся в `codes.Unavailable` (fail-closed для мутаций, §6.7)
**And** сервер НЕ откатывается на insecure (нет downgrade)

---

#### Сценарий SEC-D-21 — per-edge mismatch (client mTLS-on, server mTLS-off) → Unavailable, детектируется e2e

**ID:** SEC-D-21

**Given** на ребре vpc→iam: vpc-клиент `TLSClient.enable=true`, но IAM-listener `TLSServer.enable=false` (insecure) — конфигурационный mismatch (rollback per-edge, §6.5)

**When** vpc register-drainer пытается вызвать `RegisterResource`

**Then** вызов завершается transport-ошибкой → `codes.Unavailable`
**And** register-intent остаётся durable (`sent_at IS NULL`, retry) — mismatch не теряет tuple
**And** e2e per-edge тест ловит mismatch как `Unavailable` (а не silent-success)

> Симметричный mismatch (server mTLS-on, client mTLS-off) → SEC-D-20 (отклонение по отсутствию client-cert).

---

### 6.4 Cross-cutting / контрактные

#### Сценарий SEC-D-22 — публичные ресурсные контракты не изменены (proto breaking-diff = 0)

**ID:** SEC-D-22

**Given** ветки SEC-D (vpc/compute/nlb потребляют Internal IAM FGA-proxy из SEC-A; своих public proto-изменений не вносят)

**When** выполняется `buf breaking` против baseline на публичных сервисах vpc/compute/nlb

**Then** breaking-diff = 0 (форма Network/Subnet/.../Instance/.../NLB/Listener/TargetGroup и REST-пути неизменны — требование #8)
**And** newman happy-path по существующим публичным RPC проходит без изменений запросов/ответов

---

#### Сценарий SEC-D-23 — cross-service мутация при недоступном owner → Unavailable (fail-closed, не tuple-path)

**ID:** SEC-D-23

**Given** dev-стенд; compute создаёт Instance с NIC-spec, требующим vpc IPAM-аллокации Address
**And** kacho-vpc недоступен (peer down)

**When** клиент вызывает `Instance.Create` с NIC, ссылающимся на vpc Subnet/SG

**Then** Operation завершается с `error` `codes.Unavailable` (fail-closed для cross-service мутации на request-path, `data-integrity.md` §cross-domain / §6.7)

> Это существующее cross-service-поведение (валидация NIC-spec на request-path), не FGA-tuple-path; включено для разграничения: FGA-register — асинхронно через outbox (SEC-D-11), а cross-service ref-validation — синхронно fail-closed. SEC-D не меняет это поведение, сценарий фиксирует разграничение.

---

## 7. Список тестов (TDD-red) — что подтверждает сценарии

### 7.1 Integration (testcontainers Postgres, per-repo `internal/repo/*integration_test.go` / `internal/clients/*_test.go`)

| Тест | Сценарии | Репо |
|---|---|---|
| `outbox_register_intent_in_writer_tx` — Create пишет `fga.register` в той же tx; Abort → нет intent | SEC-D-01, SEC-D-02 | vpc, compute, nlb |
| `outbox_unregister_intent_on_delete` — Delete пишет `fga.unregister` в той же tx | SEC-D-03 | vpc, compute, nlb |
| `register_intent_payload_shape` — payload содержит ожидаемые tuple (project/creator/parent-link) | SEC-D-04, SEC-D-05, SEC-D-06 | compute, nlb |
| `register_drainer_happy_apply` — drainer → fake-IAM `RegisterResource`, intent sent | SEC-D-09 | vpc (canonical) + compute/nlb |
| `register_drainer_unregister_apply` — drainer → fake-IAM `UnregisterResource` | SEC-D-10 | vpc |
| `register_drainer_iam_down_then_recover` (КРИТИЧНО) — IAM Unavailable N раз → intent durable → recover → applied; Operation не падает; Get отдаёт ресурс | SEC-D-11 | vpc (canonical), реплика в compute/nlb |
| `register_drainer_idempotent_reapply` — crash между apply и mark; повтор `RegisterResource`→OK, tuple ровно один | SEC-D-12 | vpc |
| `register_drainer_concurrent_two_replicas` — exactly-once across 2 replicas (CAS/advisory-lock) | SEC-D-13 | vpc (canonical) |
| `register_drainer_permanent_poison` — IAM InvalidArgument → poison, не бесконечный retry, не блокирует очередь | SEC-D-14 | vpc |
| `mtls_edge_handshake_ok` — bufconn/testcontainers: server TLSServer + client TLSClient (self-signed internal CA), RPC OK; peer client-cert SAN доступен | SEC-D-17, SEC-D-18, SEC-D-19 | vpc, compute, nlb |
| `mtls_no_client_cert_rejected` — RequireAndVerifyClientCert → no-cert client отклонён, маппинг → Unavailable, нет insecure-downgrade | SEC-D-20 | vpc/iam-listener (consumer-side в compute/nlb) |
| `mtls_disabled_default_insecure` — enable=false → insecure, прежнее поведение | SEC-D-16 | vpc, compute, nlb |

### 7.2 Newman (black-box через api-gateway, `tests/newman/cases/*.py`)

| Кейс | Сценарии | Репо |
|---|---|---|
| `SEC-D-create-get-after-tuple` (happy) — Create → Operation done → Get показывает ресурс (tuple применён eventual); Delete → Get 404 | SEC-D-15 | vpc (+ аналог compute/nlb) |
| `SEC-D-edge-mtls-mismatch` (negative) — per-edge mismatch → вызов завершается Unavailable, intent durable | SEC-D-21 | vpc→iam |
| `SEC-D-cross-service-owner-down` (negative) — Instance.Create при vpc down → Operation error Unavailable | SEC-D-23 | compute |
| existing public regression — без изменений запросов/ответов (контракт #8) | SEC-D-22 | vpc, compute, nlb |

### 7.3 Структурные / контрактные гейты

| Гейт | Сценарий |
|---|---|
| `grep -rn "openfga" <repo>/internal/clients/` = 0 во всех трёх репо | SEC-D-07 |
| `buf breaking` public-сервисы vpc/compute/nlb = 0 diff | SEC-D-22 |
| GitHub Issue N5 closed (vpc + compute) с ссылкой на PR | SEC-D-08 |
| `make audit-list-filter` (vpc) зелёный — listauthz не сломан | (регрессия) |

---

## 8. Definition of Done (SEC-D)

- [ ] `acceptance-reviewer` ✅ APPROVED данного doc (статус DRAFT → APPROVED).
- [ ] KAC-тикет(ы) + ветки `KAC-<N>` в kacho-vpc / kacho-compute / kacho-nlb (порядок по build-графу; depends-on SEC-A/B/C merged или pinned к feature-ветке).
- [ ] **S1**: outbox-миграция в каждом репо (`migration-writer`; ревью `db-architect-reviewer` — FK/индексы/NOTIFY-триггер); FGA-register/unregister-intent пишется в writer-tx ресурса (Create/Delete); `openfga_write_client.go` (vpc, compute) удалён; `fgawrite` direct-HTTP убран.
- [ ] **S2**: register-drainer (corelib `outbox/drainer`) + applier `RegisterResource`/`UnregisterResource` (`internal/clients/iam_register_applier.go`), wiring в `cmd/<svc>/main.go` под advisory-lock; идемпотентность + retry на Unavailable.
- [ ] **S3**: mTLS server+client через corelib SEC-B; per-edge `*_MTLS_ENABLED` флаги (default false); client-cert + server-cert wiring; fail-closed на handshake-mismatch.
- [ ] **RED → GREEN**: integration-тесты §7.1 написаны до кода; КРИТИЧНЫЙ `register_drainer_iam_down_then_recover` (SEC-D-11) + concurrent `register_drainer_concurrent_two_replicas` (SEC-D-13) — обязательны, без них merge запрещён (ban #10/#12).
- [ ] Newman §7.2 (≥1 happy + ≥1 negative per репо) зелёные на dev-стенде.
- [ ] **grep-gate** SEC-D-07: `grep -rn "openfga" internal/clients/` = 0 в vpc/compute/nlb.
- [ ] **proto breaking-diff = 0** на публичных сервисах vpc/compute/nlb (SEC-D-22).
- [ ] GitHub Issue N5 закрыт в kacho-vpc и kacho-compute (SEC-D-08).
- [ ] Финальная верификация per-repo: `go test ./... -race` + `golangci-lint run` + `govulncheck` + (vpc) `make audit-list-filter` + newman зелёные.
- [ ] Vault-trail:
  - [ ] `obsidian/kacho/edges/vpc-to-iam-fga-register.md` (новая) — outbox→drainer→RegisterResource по mTLS; «History» с KAC.
  - [ ] `obsidian/kacho/edges/compute-to-iam-fga-register.md` (новая); `obsidian/kacho/edges/nlb-to-iam-fga-register.md` (новая/обновление nlb→iam edge).
  - [ ] `obsidian/kacho/packages/<svc>-fgawrite.md` — пометить «direct-FGA удалён, теперь outbox-intent» (или удалить запись, если пакет удалён).
  - [ ] `obsidian/kacho/rpc/iam-internal-iam-service.md` — `RegisterResource`/`UnregisterResource` как consumed-by vpc/compute/nlb (RPC определён в SEC-A).
  - [ ] `obsidian/kacho/KAC/KAC-<N>.md` — trail + PR-URL + статус.
- [ ] YouTrack KAC: `In Progress` на старте → `Test` → `Done` по merge + smoke; PR-ссылки + лог тестов комментарием.
- [ ] Заказчик — финальный smoke/e2e (`make e2e-test` / `grpcurl`): создать Network → Get показывает ресурс; mTLS-профиль (enable=true) handshake-ok на vpc→iam.

---

## 9. Open questions (DECISION-NEEDED до старта impl)

| ID | Вопрос | Рекомендация автора |
|---|---|---|
| **OQ-SEC-D-1** | Отдельная новая outbox-таблица `fga_register_outbox` per-сервис **vs** переиспользование существующей domain-`*_outbox` с новым `event_type`? | **Отдельная таблица** `<svc>_fga_register_outbox` (или общий outbox с CHECK на `event_type IN ('fga.register','fga.unregister')`) — изолирует FGA-relay-drainer от domain-Watch-drainer (разные applier, разные failure-режимы). Финал — за `db-architect-reviewer`. От ответа зависит миграция (S1). |
| **OQ-SEC-D-2** | Payload register-intent — один tuple на строку **vs** набор tuple (project+creator+parent-link) одной строкой? | **Набор одной строкой** (атомарность «весь набор tuple ресурса» = одна `RegisterResource`-транзакция в IAM; меньше строк). `RegisterResource` (SEC-A) принимает repeated tuple — согласовать форму с SEC-A. |
| **OQ-SEC-D-3** | register-drainer — отдельный экземпляр corelib `outbox/drainer` **vs** расширение domain-drainer тем же generic? | **Отдельный экземпляр** того же generic (W1.1 `outbox/drainer`) с другим Channel/Table/Applier — переиспользование без дублирования (`architecture.md`). |
| **OQ-SEC-D-4** | На Delete — какие именно tuple слать в unregister (только project-hierarchy/parent-link, creator оставить)? | **project-hierarchy + parent-link** (ресурс удалён → его место в иерархии исчезает); creator-tuple — на усмотрение SEC-C (IAM может GC по object). Согласовать с SEC-C. |
| **OQ-SEC-D-5** | S1 «no-regression»: register-drainer default-on в dev или за флагом? | **default-on** (drainer — внутренняя goroutine; без него ресурсы не получат tuple — деградация хуже текущей). mTLS на ребре drainer→iam — отдельный per-edge флаг S3 (default off). |
| **OQ-SEC-D-6** | Список mTLS-рёбер в scope SEC-D — фиксируем все исходящие из vpc/compute/nlb (vpc→iam, vpc→compute, compute→iam, compute→vpc, nlb→iam, nlb→vpc, nlb→compute) + server-listener каждого? | **Да** — все service-listener'ы vpc/compute/nlb (server) + все их исходящие client-дилы. api-gateway→backend — SEC-E; operator→vpc — SEC-G. |

> Ответы на OQ — за `acceptance-reviewer` (sign-off либо CHANGES REQUESTED). OQ-SEC-D-1/2 влияют на миграцию и форму `RegisterResource`-payload — разрешить до impl.

---

## 10. Ссылки

- Эпик-дизайн (ground truth): `docs/specs/sub-phase-SEC-mtls-iam-authz-epic.md` (§1 требования, §3.1 Вариант A, §6 distributed-решения).
- Образец outbox-drainer acceptance: `docs/specs/sub-phase-W1.1-fga-outbox-drainer-acceptance.md` (corelib drainer mechanics — переиспользуется).
- Прежний best-effort dual-write (что удаляем): `project/kacho-vpc/internal/clients/openfga_write_client.go`, `project/kacho-vpc/internal/apps/kacho/fgawrite/fgawrite.go`, `project/kacho-compute/internal/clients/openfga_write_client.go`, `project/kacho-nlb/internal/fgawrite/fgawrite.go`.
- Call-site Create (vpc): `project/kacho-vpc/internal/apps/kacho/api/network/create.go` (`fgawrite.Emit` после Commit — заменяется на outbox-intent в tx).
- corelib writer-side: `project/kacho-corelib/outbox/emit.go`; drainer: `project/kacho-corelib/outbox/drainer/`.
- corelib транспорт (SEC-B target): `project/kacho-corelib/grpcsrv/server.go`, `project/kacho-corelib/grpcclient/`.
- config TLS-stubs: `project/kacho-compute/internal/config/config.go` (`*_TLS` bool-флаги), vpc `TLSClient`-stub.
- Internal IAM FGA-proxy (SEC-A): `project/kacho-proto/proto/kacho/cloud/iam/v1/internal_iam_service.proto`.
- Правила: `.claude/rules/{api-conventions,data-integrity,security,testing,polyrepo}.md`.
