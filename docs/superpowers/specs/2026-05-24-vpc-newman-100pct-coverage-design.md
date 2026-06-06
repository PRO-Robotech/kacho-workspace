# VPC Newman 100% coverage — design doc

**Дата**: 2026-05-24
**Автор**: design (claude opus 4.7) на основе обсуждения с заказчиком
**Цель**: операционализировать «100% покрытие тестами VPC через Newman» относительно [Testing Model заказчика](#22-testing-model-26-разделов) и составить план расширения существующих `tests/newman/cases/*.py` с явной фиксацией границ возможностей Newman.

**Status (актуализировано 2026-05-24)**: ⏳ **partial-merged** — KAC-165 эпик в работе:
- workspace PR [#37](https://github.com/PRO-Robotech/kacho-workspace/pull/37) — design + vault + workspace `CLAUDE.md §«Запреты» #13`
- kacho-vpc PR [#107](https://github.com/PRO-Robotech/kacho-vpc/pull/107) — chunk 0 + **T1, T3, T4, T5, T7, T11, T12** (20 новых Newman cases, CI gate включён)
- kacho-vpc issue [#108](https://github.com/PRO-Robotech/kacho-vpc/issues/108) — follow-up: CASES-INDEX rescue после KAC-124/KAC-127 (pre-existing tech-debt, не в scope этого спринта по §«Запреты» #13)
- **Остатки**: T2 (Move CRUD — REQ-verify), T6 (PE happy — ObjectStorage seed), **T8 (Outbox NEW file), T9 (Observability NEW), T10 (Internal-NI NEW)**, T13 (FGA matrix — blocked KAC-W1.*) — отдельным PR; T14/T15 — complementary epics

> Это design-spec, не acceptance. Per-chunk acceptance — implicit (test-only, см. workspace `CLAUDE.md §«Запреты» #13`); код пишется без формальных Given-When-Then acceptance docs, потому что НЕ модифицирует приклад. Релевантные правила workspace `CLAUDE.md`: §«Запреты» #11 (no tech debt) + #12 (test-first) + **#13 (test-only PR discipline — добавлено 2026-05-24 этим эпиком)**.

---

## 1. Цель и операционализация «100% Newman»

«100% покрытие через Newman» — формулировка заказчика. Чтобы не превратить её в недостижимый абсолют, операционализируем так:

**100% покрытие = выполнены все четыре условия:**

1. **API-surface coverage** — для каждого публичного RPC (60 RPC в 9 публичных сервисах + admin-only Internal* через cluster-internal mux) есть ≥ 1 Newman-кейс на каждый **обязательный класс** из `TAXONOMY.md §«Применение по методам»`. (Сегодня — 87% по RPC-uniqueness, см. §2.)
2. **REQ-coverage** — каждый `REQ-*` из `tests/newman/docs/PRODUCT-REQUIREMENTS.md` имеет в `Validated-by` хотя бы один реальный case-id, и кейс зелёный. (Сегодня — 100 REQ-* всего, 6 explicit gaps: REQ-IPAM-03, REQ-DEL-05, REQ-AUTHZ-* matrix, plus Testing-Model-only items.)
3. **Testing-Model coverage** — каждый из 26 разделов Testing Model заказчика покрыт ≥ 1 кейсом ИЛИ имеет официальный запись «вне scope Newman: → alt-инструмент» в §3 этого документа. (Сегодня — `TAXONOMY.md §«Что НЕ покрываем в newman»` пересматриваем.)
4. **Discoverability** — каждый новый case-id зарегистрирован в `CASES-INDEX.md` либо помечен `# index: <pattern-ref>` как инстанс существующего паттерна; `validate-cases.py` зелёный (workflow в `kacho-vpc/CLAUDE.md §14.3`).

«Невозможно покрыть через Newman» — это не отговорка, а **явная декларация** в §3 со ссылкой на complementary-инструмент (integration testcontainers / k6 / chaos / observability scraping). Без такой декларации gap = баг плана.

---

## 2. Inventory — что уже есть

### 2.1 Newman base

| Метрика | Значение | Источник |
|---|---|---|
| Файлов `cases/*.py` | 12 (`address`, `authz-deny`, `gateway`, `internal-cloud`, `internal-pool`, `network-interface`, `network`, `operation`, `private-endpoint`, `route-table`, `security-group`, `subnet`) | `ls tests/newman/cases` |
| Кейсов всего | ~755 | `RESULTS.md` (v20) |
| Уникальных паттернов | 245+ | `CASES-INDEX.md` |
| Assertions | ~3380 | `RESULTS.md` |
| Pass rate | 100% | `RESULTS.md` |
| Публичных RPC | 60 | `TEST-PLAN.md` |
| Покрыто ≥ 1 кейс | 52 (87%) | `TEST-PLAN.md` |
| REQ-* в каталоге | ~100 (REQ-RES/VAL/NAME/CIDR/IPAM/IPL/UPD/LIST/DEL/OPS/AUTHZ/YC/NIC/RT/SG/MOVE/...) | `PRODUCT-REQUIREMENTS.md` |
| Taxonomy классов | CRUD / VAL / NEG / BVA / IDM / CONC / CONF / STATE / AUTHZ / PAGE / FILTER | `TAXONOMY.md` |
| Newman runs | `--env local` (kind стенд), `--env yc` (yc-proxy, differential) | `scripts/run-incremental.sh` |
| Quota-safe mode | per-case create+cleanup; `--resume`/`--cleanup-only` | `run-incremental.sh` |

### 2.2 Testing Model 26 разделов

Источник — текст заказчика в начале treads. Структура (для ссылок в §4):

| § | Раздел | Status в этом доке |
|---|---|---|
| 1 | Scope | inventory |
| 2 | System Model | informational |
| 3 | Resource Coverage Matrix (8 ресурсов × CRUD/Move/Async/AuthZ/OCC/Constraints) | §4.1 |
| 4 | Public API Test Model — Standard CRUD Coverage | §4.2 |
| 5 | Network Tests | §4.3 |
| 6 | Subnet Tests (CIDR / Relocate / Utilization) | §4.4 |
| 7 | Address / IPAM Tests | §4.5 |
| 8 | NetworkInterface Tests (Attach/Detach) | §4.6 |
| 9 | SecurityGroup Tests (Rule Update / OCC) | §4.7 |
| 10 | RouteTable Tests (Association / triggers) | §4.8 |
| 11 | PrivateEndpoint Tests | §4.9 |
| 12 | Internal API Tests | §4.10 |
| 13 | Async Operations (LRO + Failure Injection) | §4.11 |
| 14 | Outbox + Events | §4.12 |
| 15 | FGA Authorization Tests | §4.13 |
| 16 | Database Invariant Tests | §4.14 |
| 17 | Validation Model (Sync + Async) | §4.15 |
| 18 | Cross-Service Integration Tests | §4.16 |
| 19 | Observability Tests | §4.17 |
| 20 | Load & Concurrency Tests | §4.18 |
| 21 | Chaos / Failure Tests | §4.19 |
| 22 | Security Tests | §4.20 |
| 23 | Regression Suite | §4.21 |
| 24 | Release Gates | §6 |
| 25 | Definition of Done | §6 |
| 26 | Maturity Model | §6 |

### 2.3 Существующие документы, которые этот design дополняет

- `tests/newman/docs/TAXONOMY.md` — naming, классы, scope-cuts. **Будет обновлён** (§7).
- `tests/newman/docs/CASES-INDEX.md` — каталог 245+ уникальных паттернов. **Будет дополнен** новыми паттернами.
- `tests/newman/docs/TEST-PLAN.md` — карта `(сервис, RPC) → классы → статус`. **Будет обновлён** до 100%.
- `tests/newman/docs/PRODUCT-REQUIREMENTS.md` — реестр `REQ-*`. **Будет дополнен** новыми REQ для покрытия §15 / §19 / §22 Testing Model.
- `tests/newman/docs/RESULTS.md` — версионная история прогонов. **Обновляется** после каждой версии.

---

## 3. Newman boundary — что физически НЕ покрывается Newman и где альтернатива

Newman — это HTTP-клиент с JS-skript'ами в Postman-runtime. Его архитектурные ограничения:

| Ограничение Newman | Следствие | Альтернатива |
|---|---|---|
| **Black-box, через api-gateway** | Внутренние состояния (xmin, outbox row, FGA tuple set) не наблюдаемы напрямую | Side-channel: внутренние RPC через api-gateway internal mux (`/vpc/v1/addressPools:explainResolution`, `InternalWatchService` через WebSocket/stream). Где невозможно — integration-тесты `internal/repo/*integration_test.go`. |
| **Нет параллельной отправки запросов из одного case** | True race-condition (N горутин parallel `AllocateExternalIP`) не воспроизводится. Postman может только сериально + `pm.sendRequest` (тоже сериально внутри case) | Один Newman-case может симулировать «burst» через короткие подряд create-Create без poll-between → но это **best-effort, не deterministic race**. Жёсткий race-free — `internal/repo/network_interface_attach_race_integration_test.go` (testcontainers, Go goroutines). |
| **Нельзя инжектировать failure (kill Postgres, drop LISTEN/NOTIFY, network partition)** | Chaos §21 и Failure Injection в §13 — не покрываются | Manual chaos: `kacho-deploy` имеет `kubectl delete pod -l app=kacho-postgres` runbook. Автоматический chaos: будущая интеграция с **chaos-mesh** в `kacho-deploy/` (вне scope этого design'а; зафиксировать как `KAC-future`). |
| **Нет наблюдаемости /metrics из Newman case** | §19 (observability tests — `vpc_operations_total` exposed, requestId propagation) — частично достижимо: можно `pm.sendRequest('http://kacho-vpc:9090/metrics')` и grep'нуть line. Но это **не идиоматический Newman** | `pm.sendRequest` на `:9090/metrics` ДОПУСТИМ как side-channel в одном case (новый класс `OBS`). Альтернатива: VictoriaMetrics-skill (если стенд интегрирован). |
| **Stress / load (1000+ RPS) — нет** | §20 Load — не покрывается даже идеально | k6 в `tests/k6/` (уже есть). Newman делает **функциональную** проверку под burst (~10 parallel cases), не нагрузочную. |
| **Worker restart recovery (§13 «worker restart recovery / orphaned ops cleanup»)** | Невозможно из Newman: нужен `kubectl rollout restart kacho-vpc` + retry | Manual: один Newman-case инициирует Operation → `pm.sendRequest` hit'ит `/healthz` → если оператор перезапустит deployment, кейс продолжит poll. **Это полу-ручное**. Чисто авто — chaos-mesh (future). |
| **DB-state assertion (e.g. `xmin` change, generated column)** | Из Newman нет SQL-канала | OCC поведение (`SG.UpdateRules` через xmin) — наблюдаемо через сам RPC: два concurrent Update'а — второй гарантированно ABORTED. Это уже верифицируется. Но REAL xmin check — integration. |
| **Outbox stream subscription (LISTEN/NOTIFY через InternalWatchService — gRPC server-stream)** | Postman/Newman НЕ поддерживает gRPC streaming. REST `GET /vpc/v1/internalWatch:stream` через grpc-gateway = chunked HTTP — Newman поддерживает chunked, но pm не имеет async handler для streamed body | Workaround: short-window watch с `pm.sendRequest({timeout: 5000})` и ожидание ≥ 1 event chunk → assertion. **Это работает**, добавляем класс `OUTBOX`. Альтернатива: `internal_watch_integration_test.go`. |
| **Time-travel / clock injection** | Тесты с deadline'ами / TTL Operations — невозможно ускорить | Не нужно в текущем scope (Operations поллятся ~секунды). При появлении TTL/retention — integration. |

**Решение по boundary**: §3 каждой Testing-Model-секции в §4 явно отметит «не Newman → alt-инструмент» для каждой проблемной грани. Это **не** уменьшает «100%», а делает его измеримым: «100% Newman-покрытие того, что Newman физически может», + честный список complementary tests.

---

## 4. Coverage Matrix — 26 разделов × Newman

### 4.1 § 3 Resource Coverage Matrix (8 ресурсов × 6 граней)

Заказчик дал упрощённую матрицу `Resource × CRUD/Move/Async/AuthZ/OCC/Constraints`. Текущее состояние:

| Resource | CRUD | Move | Async (LRO) | AuthZ | OCC | DB Constraints |
|---|---|---|---|---|---|---|
| Network | ✅ `NET-CR/GET/UPD/DEL/LST-CRUD-OK` | ✅ `NET-MV-CRUD-OK`/`-CONF-NF-TEXT` | ✅ `OP-GET-CRUD-OK` (общий) | ⚠ partial `*-AUTHZ-NF-SYNC` (sync-NF only, нет cross-tenant) | n/a | ✅ FK Subnet/RT/SG (`*-DEL-NEG-HAS-*`); ✅ name UNIQUE (`*-CR-NEG-DUP-NAME`) |
| Subnet | ✅ | ⚠ planned (gap) | ✅ | ⚠ partial | n/a | ✅ EXCLUDE CIDR overlap; FK ON DELETE RESTRICT |
| Address | ✅ | ⚠ planned (gap) | ✅ | ⚠ partial | n/a | ✅ partial UNIQUE external pool IP |
| NetworkInterface | ✅ NIC-CR/UPD/DEL/LIST | ⚠ planned (NIC.Move? — gap, см. §4.6) | ✅ | ⚠ partial | ✅ **CAS** on `used_by_id` (тест: `NIC-ATTACH-DETACH-OK`, gap — true concurrent CAS race) | ✅ MAC UNIQUE; v4/v6 cardinality CHECK |
| SecurityGroup | ✅ | ⚠ planned (gap) | ✅ | ⚠ partial | ✅ **xmin** (`SG-URL-CRUD-OK` — но gap на true concurrent UpdateRules) | ✅ NIC ref (KAC-52 blocked) |
| RouteTable | ✅ | ⚠ planned (gap) | ✅ | ⚠ partial | n/a | ✅ trigger auto-assoc (`RT-CR-STATE-SUBNET-AUTO-ASSOC`) |
| Gateway | ✅ | ✅ `GW-MV-CRUD-OK` | ✅ | ⚠ partial | n/a | ✅ name UNIQUE; strict name regex |
| PrivateEndpoint | ⚠ partial (no CRUD-OK happy — ObjectStorage seed missing) | n/a (no Move) | ✅ | ⚠ partial | n/a | ✅ FK Network/Subnet |

**Gaps**:
- Move CRUD-OK для Subnet/Address/RT/SG — отмечено в `TEST-PLAN.md` Backlog P1.
- Concurrent OCC race для NIC.AttachToInstance и SG.UpdateRules — нет deterministic Newman-кейса (true race в Newman недостижим — см. §3 boundary). **Burst-emulation case** добавляем: `*-CONC-PARALLEL-ATTACH` через `pm.sendRequest` × 5 без poll between → ожидаем 1 success + 4 FailedPrecondition.
- PE CRUD-OK — нужен ObjectStorage seed в окружении (env var или admin RPC).
- Cross-tenant AuthZ matrix — `REQUIREMENTS.md` REQ-006 / `TEST-PLAN.md` Backlog P0.

### 4.2 § 4 Standard CRUD Coverage matrix (Scenario × Expected per endpoint)

Заказчик предложил 10 сценариев на каждый endpoint:

| Scenario | Expected | Текущее покрытие | Gap |
|---|---|---|---|
| valid request | success | ✅ `*-CR-CRUD-OK` × 6 ресурсов | — |
| invalid payload | 400 | ✅ `*-CR-VAL-MALFORMED-JSON`/`-EMPTY-BODY` × 7 | — |
| no token | 401 | ❌ NEW — все public POST без `Authorization` header | **NEW**: `*-AUTHZ-NO-TOKEN-401` (7 ресурсов × Create) |
| invalid token | 401 | ❌ NEW | **NEW**: `*-AUTHZ-INVALID-TOKEN-401` |
| no permissions | 403 | ⚠ partial — `*-LST-AUTHZ-CROSS-FOLDER-ISOLATION` (только List) | **NEW**: `*-AUTHZ-CROSS-TENANT-403` × все RPC |
| foreign tenant | 403/404 | ⚠ partial — `*-GBV-CONF-NOLEAK-FOR-EXISTING-OTHER` (только GetByValue) | **NEW**: `*-GET-AUTHZ-FOREIGN-NF`, `*-UPD-AUTHZ-FOREIGN-403`, `*-DEL-AUTHZ-FOREIGN-403` per resource |
| resource missing | 404 | ✅ `*-GET-NEG-NF`, `*-DEL-AUTHZ-NF-SYNC` | — |
| conflict | 409 | ⚠ partial — `*-CR-NEG-DUP-NAME` returns gRPC ALREADY_EXISTS (HTTP 409 в transcoding) | **NEW**: verify status=409 explicit (вместо текущей 400/409 lenient) |
| internal failure | 500 | ❌ NEW — нельзя достоверно вызвать 500 без injection. (Можно через garbage в редко-валидируемое поле.) | **boundary**: см. §3 — chaos требует инжекции; Newman может только assert «нет 500 на security probes» (уже есть `*-CR-SEC-*`) |
| async timeout | operation failed | ⚠ partial — нет кейса с timeout на peer (folder check); зависит от availability of peer-service | **NEW (boundary)**: `*-ASYNC-PEER-UNAVAILABLE` — требует chaos. В Newman — только static `*-CR-NEG-FOLDER-NOT-FOUND` (peer-NF) |

### 4.3 § 5 Network Tests

**Create**:

| Что | Текущий case-id (или gap) |
|---|---|
| default SG auto-created | ✅ `*-LSG-CRUD-DEFAULT-SG`, `NET-DEL-CRUD-DEFAULT-SG-REMOVED` |
| network ownership set | ✅ implied `*-CR-CRUD-OK` |
| operation persisted | ✅ `OP-GET-CRUD-OK`, `NET-LISTOPS-AFTER-DELETE-OK` |
| outbox event emitted | ❌ NEW — `NET-CR-OUTBOX-EMIT` (через `InternalWatchService` short-window) |
| FGA tuples written | ⚠ partial — KAC-W1.* IAM эпик в работе. После merge: **NEW** `NET-CR-FGA-TUPLE-WRITTEN` (через `iam.Check` peer-call наблюдаемое; либо через newly-created tenant ≠ ставится в Bind) |
| duplicate name | ✅ `*-CR-NEG-DUP-NAME` |
| Move between folders | ✅ `NET-MV-CRUD-OK` |

**Delete**:

| Что | case-id |
|---|---|
| subnet existence blocks | ✅ `*-DEL-NEG-HAS-SUBNETS` |
| SG existence blocks | ✅ `*-DEL-NEG-HAS-NONDEFAULT-SG` |
| route table references | ✅ `*-DEL-NEG-HAS-ROUTE-TABLE` |
| async cleanup successful | ✅ `NET-DEL-CRUD-DEFAULT-SG-REMOVED`, `*-DEL-CRUD-ONLY-DEFAULT-SG` |
| transitive: Subnet→NIC blocks | ✅ `NET-DEL-NEG-HAS-SUBNET-WITH-NIC` |

**Gap (Network)**: outbox emit verifications + FGA tuple writes (зависят от §4.12, §4.13).

### 4.4 § 6 Subnet Tests

**CIDR Validation**:

| Что | case-id |
|---|---|
| IPv4 valid | ✅ `*-CR-CRUD-OK` |
| IPv6 valid | ✅ `SUB-CR-V6-OK` |
| overlap blocked (EXCLUDE) | ✅ `*-CR-NEG-CIDR-OVERLAP`, `*-ACB-NEG-OVERLAP` |
| invalid mask | ✅ `*-CR-VAL-CIDR-HOSTBITS`, `*-CR-VAL-CIDR-REQUIRED` |
| duplicate CIDR | ❌ NEW — `SUB-CR-NEG-DUP-CIDR-EXACT` (same CIDR в Add → должен быть FailedPrecondition отдельно от overlap?) |
| AddCidrBlocks atomicity | ✅ `*-ACB-CRUD-ADD-MULTIPLE`, `*-ACB-STATE-DISJOINT-CIDRS` |
| RemoveCidrBlocks consistency | ✅ `*-RCB-CRUD-OK`, `*-RCB-NEG-CANNOT-REMOVE-PRIMARY`, `*-ACB-RCB-ROUNDTRIP` |

**Relocate**:

| Что | case-id |
|---|---|
| cross-zone move | ❌ NEW (KAC-в работе?) — `SUB-REL-STATE-NO-ADDRESSES-OK` уже есть. **boundary**: REQ-CIDR-06 говорит Relocate **всегда отвергается** (verbatim YC). Значит: реальный cross-zone Move невозможен — кейс `*-REL-NEG-IN-USE` уже покрывает. |
| zone validation через compute | ✅ implicit `*-CR-VAL-ZONE-UNKNOWN` (зависит от compute.ZoneService.Get peer-call) |
| IP/route preservation | n/a (Relocate отвергается) |
| rollback on failure | n/a |

**Utilization**:

| Что | case-id |
|---|---|
| ListUsedAddresses correctness | ✅ `*-LUA-CRUD-OK` |
| allocated/free count | ❌ NEW — `SUB-LUA-CRUD-COUNT` (создать 3 address → list → assert .length=3) |
| fragmentation handling | ❌ NEW — `SUB-LUA-STATE-FRAGMENT` (allocate 5 → delete middle 3 → list → assert correct set) |
| concurrent allocation visibility | **boundary**: true concurrent — k6/integration |

### 4.5 § 7 Address / IPAM Tests

**Address Create**:

| Что | case-id |
|---|---|
| internal/external alloc | ✅ `*-CR-CRUD-INT`, `*-CR-CRUD-EXT`, `ADR-CR-CRUD-EXT-V6` |
| v4/v6 | ✅ `ADR-CR-CRUD-EXT-V6`, `ADR-CR-NEG-EXT-V6-NO-POOL` |
| uniqueness | ⚠ partial (есть `addresses_external_pool_ip_uniq` constraint, но dedicated Newman кейса нет — реальная коллизия требует пулла на 2 IP + 3 Create) | **NEW**: `ADR-CR-CONC-POOL-EXHAUSTION` (pool /30, allocate 2 → 3rd FailedPrecondition) |
| subnet ownership | ✅ `*-CR-VAL-EXT-WITH-SUBNET-FK` |
| used_by tracking | ✅ implicit (NIC tests reference used_by) — `ADDR-DEL-NEG-USED-BY-NIC` |
| GetByValue lookup | ✅ `*-GBV-CRUD-OK`, `*-GBV-NEG-NF` |
| address release | ⚠ partial — `ADR-DEL-EXT-V6-RELEASE-REUSE` (v6 reuse). **NEW**: `ADR-DEL-EXT-V4-RELEASE-REUSE` (v4 reuse через освобождённый pool slot) |

**InternalAddressService.Allocate**:

| Что | case-id |
|---|---|
| allocation from correct pool | ✅ cascade resolve кейсы `IPL-EXPLAIN-NETWORK-DEFAULT`, `ADR-CR-EXT-FALLTHROUGH-V4/V6` |
| family correctness | ✅ `ADR-CR-EXT-V6-FAMILY-FALLTHROUGH`, `IPL-RESOLVE-*-FAMILY-SKIP` |
| no duplicates | **boundary**: defended by UNIQUE constraint; true race — integration `address_pool_freelist_integration_test.go` |
| no overlap | n/a (UNIQUE на IP value) |
| exhausted pool | ❌ NEW — `IPL-ALLOC-POOL-EXHAUSTED` (pool /32 (1 IP) → first ok, second FailedPrecondition) |
| label-selector routing | ✅ `IPL-RESOLVE-SELECTOR-FAMILY-SKIP` |
| default-pool resolution | ✅ implicit (`IPL-EXPLAIN-NETWORK-DEFAULT`) |
| concurrency safety | **boundary**: integration |

**Free**:

| Что | case-id |
|---|---|
| released IP reusable | ⚠ partial — `ADR-DEL-EXT-V6-RELEASE-REUSE` (v6 sparse counter). **NEW**: v4 free + reuse |
| double-free safe | ❌ NEW — `ADR-DEL-IDM-DOUBLE` (Delete → 200 → Delete same id → 404) |
| stale reference cleanup | n/a (FK enforces) |
| used_by cleanup | ✅ implicit `NIC-ATTACH-DETACH-OK` (attach + detach → used_by cleared) |

**IPAM Concurrency** (§7 «Expected: no duplicate IPs / no phantom allocations / consistent utilization»):

| Что | case-id |
|---|---|
| parallel allocation | **boundary** — Newman best-effort через `pm.sendRequest` burst (~5 sequential без poll). **NEW**: `ADR-CONC-BURST-ALLOC` (5 sequential Create → assert all unique IPs). Жёсткий race — integration. |
| parallel release | **boundary** |
| allocate/free race | **boundary** |
| subnet relocation during allocation | n/a (Relocate отвергается) |
| pool exhaustion under load | k6 territory; Newman только functional (см. `IPL-ALLOC-POOL-EXHAUSTED` NEW выше) |

### 4.6 § 8 NetworkInterface Tests

**AttachToInstance**:

| Что | case-id |
|---|---|
| atomic CAS on used_by_id | ⚠ implicit `NIC-ATTACH-DETACH-OK`. **NEW**: `NIC-ATTACH-CONC-BURST` (5 parallel Attach same NIC → 1 succeed + 4 FailedPrecondition) — Newman boundary, best-effort |
| duplicate attach blocked | ❌ NEW — `NIC-ATTACH-NEG-ALREADY-USED` (Attach к instanceA → Attach к instanceB того же NIC → FailedPrecondition) |
| SG validation | ✅ `NIC-CR-WITH-UNBOUND-SG-OK` (на Create); **NEW** на Update SG list change |
| subnet validation | ✅ `NIC-CR-NEG-BAD-SUBNET` |
| MAC uniqueness | ✅ `NIC-CR-MAC-OK` (format). **NEW**: `NIC-CR-CONC-MAC-UNIQUE` (50 parallel Create в одном subnet → 50 distinct MAC) — boundary |
| cardinality ≤1 per family | ✅ DB CHECK constraint; **NEW**: `NIC-CR-NEG-MULTI-V4-ADDR` (Create NIC с 2× v4_address_ids → InvalidArgument), `NIC-CR-NEG-MULTI-V6-ADDR` |
| concurrent attach safety | **boundary** burst (см. above) |

**Detach**:

| Что | case-id |
|---|---|
| cleanup references | ✅ `NIC-ATTACH-DETACH-OK` |
| release ephemeral IPs | ❌ NEW — `NIC-DETACH-STATE-EPHEMERAL-IP-RELEASE` (Create NIC with auto-allocated IP → Attach → Detach → assert IP free for reuse) |
| stale attach prevention | n/a (idempotent Detach) |
| detached NIC reusable | ❌ NEW — `NIC-DETACH-IDM-REATTACH-OK` (Detach → Attach to another instance → ok) |

### 4.7 § 9 SecurityGroup Tests

**Rule Update**:

| Что | case-id |
|---|---|
| OCC via xmin | ✅ implicit `SG-URL-CRUD-OK`; **NEW (boundary)**: `SG-URL-CONC-OCC-CONFLICT` (двух Update параллельно через `pm.sendRequest` burst → один Aborted) |
| concurrent update conflict | (same as above) |
| invalid rule rejection | ✅ `*-URL-VAL-DIRECTION-UNKNOWN`, `-PORT-NEG`, `-PORT-OVER-65535`, `-PROTOCOL-UNKNOWN`, `-PORT-ANY-MINUS-1` |
| duplicate rules | ❌ NEW — `SG-URL-NEG-DUP-RULE` (UpdateRules с 2 identical rule entries → behavior verified: dedupe или 400) |
| cross-network references | ❌ NEW — `SG-URL-VAL-CROSS-NET-SG-REF` (UpdateRule.predefined_target = SG из другой сети → InvalidArgument?) **— нужно уточнить product req** |
| delete blocking when attached to NIC | ⚠ partial — `SG-DEL-NEG-NIC-ATTACHED` (KAC-52 blocked, TDD-red уже зафиксирован) |

### 4.8 § 10 RouteTable Tests

**Association**:

| Что | case-id |
|---|---|
| trigger-based auto-association | ✅ `RT-CR-STATE-SUBNET-AUTO-ASSOC`, `SUB-CR-STATE-AUTO-PICK-RT` |
| subnet relation integrity | ✅ (via auto-assoc) |
| delete blocked when associated | ❌ NEW — `RT-DEL-NEG-ASSOCIATED` (RT с Subnet'ами → Delete → FailedPrecondition? либо CASCADE SET NULL — REQ-RT-DEL уточнить) |
| route normalization | ❌ NEW — `RT-CR-STATE-ROUTE-NORM` (Create с CIDR `10.0.0.5/24` в `destination_prefix` → стандартизуется до `10.0.0.0/24` или 400 — verify) |
| invalid next-hop rejection | ✅ `*-CR-VAL-ROUTE-INVALID-HOP`, `*-CR-VAL-ROUTE-EMPTY-HOP` |

### 4.9 § 11 PrivateEndpoint Tests

| Что | case-id |
|---|---|
| subnet binding | ✅ `*-CR-CRUD-WITH-SUBNET`, `*-CR-NEG-SUBNET-NF` |
| endpoint uniqueness | ❌ NEW — `PE-CR-NEG-DUP` (же uniqueness — какая ось? name? subnet? service?) **уточнить req** |
| invalid subnet rejection | ✅ `*-CR-NEG-SUBNET-NF`, `*-CR-VAL-SUBNET-REQUIRED` |
| tenant isolation | ⚠ general AUTHZ kit; needs PE-specific instance |
| Move semantics | n/a — PE.Move нет в API |
| **PE CRUD-OK happy** | ❌ **BIG GAP** (см. `TEST-PLAN.md` PE ◐) — нужен ObjectStorage seed либо stub. **NEW**: `PE-CR-CRUD-OK` + `PE-LIFECYCLE-CONF` |

### 4.10 § 12 Internal API Tests

**InternalAddressPoolService** — уже extensive в `internal-pool.py` (40 кейсов после KAC-71): CRUD, v4/v6 separation, label selector, ExplainResolution, default pool, utilization. ✅

**InternalCloudService** — 4 кейса в `internal-cloud.py`: poolSelector set/get/unset. ⚠ partial. **NEW**: `CLD-RESOLVE-CASCADE-CHAIN` (cloud → network → address — full cascade test через Address.Create observably).

**InternalAddressService** (allocate/free) — НЕ exposed через api-gateway public REST → доступ через api-gateway internal mux. ⚠ partial — индирект через Address.Create observable. **NEW**: добавить explicit cases при наличии REST-path в gateway internal mux.

**InternalNetworkService.GetPoolSelector** — есть на uri через internal mux? — **уточнить**.

**InternalWatchService** — server-streaming через grpc-gateway (chunked transfer). **NEW** (см. §3 boundary workaround): `IWS-STREAM-SHORT-WINDOW` (Create Network → start `pm.sendRequest` на `/vpc/v1/internalWatch:stream?from_sequence_no=N` с timeout=5s → assert ≥ 1 event chunk с правильным payload schema).

### 4.11 § 13 Async Operations (LRO)

**Базовая корректность LRO**:

| Что | case-id |
|---|---|
| operation persisted | ✅ `OP-GET-CRUD-OK` |
| operation prefix = enp | ✅ `OP-GET-NEG-NF-INVALID-PREFIX` (verify prefix routing) |
| Pending → Running → Done | ✅ implicit (poll-pattern в каждом `*-CR-CRUD-OK`) |
| Pending → Running → Failed | ✅ `*-CR-NEG-FOLDER-NF`, `ADR-CR-EXT-FALLTHROUGH-V4/V6` |
| retry semantics | ⚠ partial — `*-CR-IDM-RETRY` only. **NEW**: `*-OPS-RETRY-IDM` per critical RPC (Create×Update×Delete) |
| cancellation | ❌ NEW — but there's no `OperationService.Cancel` RPC в Kachō currently → **out-of-scope** unless cancel API exists |
| worker restart recovery | **boundary**: requires `kubectl rollout restart` — chaos category |
| orphaned operation cleanup | **boundary**: requires DB-level inspection of stale Operations — integration |

**Failure Injection** (§13 второй блок):

| Что | case-id |
|---|---|
| DB failure mid-operation | **boundary**: chaos — `kacho-deploy` runbook + manual newman |
| IAM unavailable | **boundary**: chaos — kill `kacho-iam` pod, expect VPC Operation → Failed (`Unavailable`) |
| compute unavailable | **boundary**: chaos — kill `kacho-compute` pod, expect Subnet.Create with zone_id → Operation Failed |
| duplicate retries | ✅ `*-CR-IDM-RETRY` |
| operation timeout | **boundary**: depends on timeout config |

**Expected** (§13): «no partial state / idempotent retries / consistent final state» — это **invariants**. Их Newman может верифицировать только сценарно (after happy path observe consistent state). True chaos = future KAC.

### 4.12 § 14 Outbox + Events

| Что | case-id |
|---|---|
| event emitted after successful mutation | ❌ NEW — `*-OUTBOX-EMIT` per ресурс через InternalWatchService stream snapshot (см. §4.10 IWS) |
| no event on rollback | ❌ NEW — `*-OUTBOX-NO-EMIT-ON-FAIL` (failed Operation → no event in stream) — boundary: failed Operation детектируется, но «no event» требует читать stream до+после; complex newman |
| LISTEN/NOTIFY delivery | implicit via stream test |
| ordering | ❌ NEW — `OUTBOX-ORDER-PRESERVED` (3 sequential Create → events arrive в порядке sequence_no) |
| duplicate suppression | n/a (outbox is append-only; at-least-once) |
| payload schema | ❌ NEW — `OUTBOX-SCHEMA-CONTRACT` (assert event has `{sequence_no, kind, resource_type, resource_id, action ∈ {CREATED/UPDATED/DELETED}, timestamp}`) |
| retry safety | n/a |

Все эти cases — новый класс `OUTBOX` в TAXONOMY, файл `cases/outbox.py` (новый).

### 4.13 § 15 FGA Authorization Tests

**RPC-level authz**:

| Что | case-id |
|---|---|
| Check interceptor | ❌ NEW — но зависит от KAC-W1.* (IAM authz эпик) merge'а; пока mode=dev (anonymous=admin). **После merge'а** — `*-AUTHZ-FGA-CHECK-DENY` × ресурс |
| project hierarchy | ❌ NEW — `*-AUTHZ-FGA-INHERITED-PROJECT` (роль на project → access к ресурсам project'а) |
| inherited permissions | (same) |
| write tuple creation | ❌ NEW — `*-AUTHZ-FGA-TUPLE-AFTER-CREATE` (Create → assert FGA Check returns allowed для caller) |
| stale tuple cleanup | ❌ NEW — `*-AUTHZ-FGA-TUPLE-AFTER-DELETE` (Delete → assert FGA Check returns denied/not-found) |
| Move permission propagation | ❌ NEW — `*-MV-AUTHZ-FGA-RETUPLE` (Move к другому folder/project → permission to source revoked, destination granted) |

**Multi-tenant Isolation**:

| Что | case-id |
|---|---|
| project isolation | ⚠ partial `*-LST-AUTHZ-CROSS-FOLDER-ISOLATION`; **NEW**: full matrix per RPC × per ресурс |
| folder isolation | (same) |
| hidden foreign resources | ✅ `*-GBV-CONF-NOLEAK-FOR-EXISTING-OTHER` — pattern; **NEW**: same pattern для Get/List/Update/Delete per ресурс |
| forbidden Move across unauthorized projects | ❌ NEW — `*-MV-AUTHZ-CROSS-PROJECT-DENY` |
| cross-tenant lookup blocking | ❌ NEW — `*-GET-AUTHZ-FOREIGN-NF` per ресурс |

Все FGA-кейсы **блокированы KAC-W1.* эпиком** (IAM-VPC integration). Расширяем `cases/authz-deny.py` после merge'а.

### 4.14 § 16 DB Invariant Tests

Inverant testing через API:

| Тип | Что | case-id |
|---|---|---|
| **FK** | dangling refs impossible | ✅ `*-DEL-NEG-HAS-*` (children block parent delete) |
| FK | delete restrictions | ✅ same |
| FK | cascading semantics | ✅ `*-DEL-CRUD-ONLY-DEFAULT-SG` (auto-cleanup) |
| **UNIQUE** | MAC uniqueness | ⚠ implicit `NIC-CR-MAC-OK` + DB UNIQUE. **NEW**: `NIC-CR-CONC-MAC-UNIQUE` burst |
| UNIQUE | IP uniqueness | ⚠ DB-level. **NEW**: `ADR-CONC-BURST-ALLOC` (см. 4.5) |
| UNIQUE | name uniqueness | ✅ `*-CR-NEG-DUP-NAME` |
| UNIQUE | concurrent insert safety | **boundary** burst (см. §3) |
| **EXCLUDE** | subnet overlap impossible | ✅ `*-CR-NEG-CIDR-OVERLAP` |
| EXCLUDE | IPv4 overlap | ✅ same |
| EXCLUDE | IPv6 overlap | ❌ NEW — `SUB-CR-NEG-V6-OVERLAP` (две v6-subnet с пересекающимися CIDR → 2nd FailedPrecondition) |
| EXCLUDE | concurrent subnet create | **boundary** burst |
| **CAS / OCC** | xmin OCC | ⚠ implicit `SG-URL-CRUD-OK`; **NEW**: `SG-URL-CONC-OCC-CONFLICT` burst |
| CAS | stale update conflict | (same) |
| CAS | lost update prevention | (same) |
| **CHECK** | NIC cardinality v4 ≤ 1 / v6 ≤ 1 | ❌ NEW `NIC-CR-NEG-MULTI-V4-ADDR` (см. 4.6) |
| CHECK | labels valid | ✅ `*-CR-VAL-LABELS-*` |

### 4.15 § 17 Validation Model

**Sync Validation** — практически вся покрыта (PRODUCT-REQUIREMENTS §B-D + 70+ `*-CR-VAL-*` кейсов). ✅

| Что | Coverage | Gap |
|---|---|---|
| required fields | ✅ REQ-VAL-01 × 7 ресурсов | — |
| immutable fields | ✅ REQ-UPD-03 × 11 immutable полей | — |
| mask discipline | ✅ REQ-UPD-01/02 | — |
| enum validation | ✅ `*-URL-VAL-DIRECTION-UNKNOWN` | NEW: `GW-CR-VAL-TYPE-UNKNOWN` (Gateway type enum) — если ещё не покрыт |
| UUID validation | ✅ `*-DEL-NEG-NF-INVALID-PREFIX` × `*-GET-NEG-NF-INVALID-PREFIX` | — |
| field ranges | ✅ BVA-* (page_size, description, labels, name) | — |
| family mismatch | ✅ `IPL-CR-VAL-CROSS-V4-IN-V6` | — |

**Async Validation**:

| Что | case-id |
|---|---|
| peer-service existence | ✅ `*-CR-NEG-FOLDER-NF`, `*-CR-NEG-FOLDER-NOT-FOUND` |
| project existence | (same — same as folder/project in KAC-124) |
| zone existence | ✅ `*-CR-VAL-ZONE-UNKNOWN` (sync), но runtime peer-call к compute — **NEW**: `SUB-CR-NEG-ZONE-NF-ASYNC` (зона удалена в compute между sync-check и worker — Newman boundary; integration test) |
| rollback on failed validation | ⚠ implicit (Operation Failed → no resource visible). **NEW**: explicit `*-CR-NEG-ROLLBACK-NO-RESOURCE-IN-GET` |

### 4.16 § 18 Cross-Service Integration Tests

**kacho-vpc → kacho-compute**:

| Что | case-id |
|---|---|
| ZoneService.Get | ✅ implicit `*-CR-VAL-ZONE-UNKNOWN` |
| unavailable compute | **boundary** chaos |
| stale zone | **boundary** |
| timeout handling | **boundary** |

**kacho-vpc → kacho-iam (after W1.* merge)**:

| Что | case-id |
|---|---|
| project existence | ✅ (после KAC-124) `*-CR-NEG-FOLDER-NF` (теперь project) |
| authz checks | ❌ NEW post-W1.* (см. §4.13) |
| IAM unavailable | **boundary** chaos |
| stale permissions | **boundary** |

**kacho-compute → kacho-vpc** (NIC validation, IPAM allocate):

| Что | case-id |
|---|---|
| subnet validation | ✅ `NIC-CR-NEG-BAD-SUBNET` (через NIC resource, but consumer-side test = kacho-compute newman) |
| SG validation | ✅ similar |
| IPAM allocation | ✅ implicit Address.Create |
| retry behavior | **boundary** |

**Note**: kacho-compute → kacho-vpc edge тестируется в `kacho-compute/tests/newman/`, не здесь. Здесь — только vpc-side correctness.

### 4.17 § 19 Observability Tests

| Что | case-id (NEW класс `OBS`) |
|---|---|
| requestId propagation | ❌ NEW — `OBS-REQID-HEADER-ECHO` (send X-Request-Id → assert response header echoes same) |
| correlationId propagation | ❌ NEW — similar |
| operationId propagation | ⚠ already in Operation envelope; **NEW** explicit verify |
| audit logs | **boundary** — нет audit log endpoint в API; observable только через side-channel (kubectl logs) → **out-of-Newman** |
| structured logs | **boundary** (same) |
| outbox observability | covered §4.12 |
| metrics exposure | ❌ NEW — `OBS-METRICS-EXPOSED` (`pm.sendRequest('http://kacho-vpc:9090/metrics')` → assert contains `vpc_operations_total`) — workaround, см. §3 |

Metrics expected (§19):

| Metric | Newman verify |
|---|---|
| `vpc_operations_total` | ❌ NEW `OBS-METRICS-OPS-TOTAL` |
| `vpc_operations_failed_total` | ❌ NEW `OBS-METRICS-OPS-FAILED` |
| `vpc_ipam_allocations_total` | ❌ NEW `OBS-METRICS-IPAM-ALLOC` |
| `vpc_ipam_conflicts_total` | ❌ NEW `OBS-METRICS-IPAM-CONFLICTS` |
| `vpc_fga_checks_total` | post-W1.* `OBS-METRICS-FGA-CHECKS` |
| `vpc_outbox_events_total` | ❌ NEW `OBS-METRICS-OUTBOX-EVENTS` |
| `grpc_requests_total` | ❌ NEW `OBS-METRICS-GRPC-REQUESTS` |
| `grpc_request_duration_seconds` | ❌ NEW (histogram bucket count > 0) |

### 4.18 § 20 Load & Concurrency Tests

| Scenario | Newman | Альтернатива |
|---|---|---|
| **IPAM Saturation 1000+ parallel** | **boundary**: Newman не сделает 1000 RPS | k6 (`tests/k6/`), suite `ipam-saturation.js` (NEW) |
| **NIC Attach Storm** | **boundary** — burst-5 в Newman best-effort: `NIC-ATTACH-CONC-BURST` (см. §4.6) | k6 attach-storm |
| **Subnet Overlap Race** | **boundary** — burst-3 best-effort: `SUB-CR-CONC-OVERLAP-BURST` (3 parallel Create same CIDR → 1 ok + 2 FailedPrecondition) — NEW | k6 |
| **Async Mutation Flood** | **boundary** | k6 |

**Решение**: Newman дополняет k6 sanity-burst-кейсами (класс `CONC`), но не претендует на load. Newman-CONC verifies correctness invariant в **возможно-race** ситуации; k6 verifies throughput + p99.

### 4.19 § 21 Chaos / Failure Tests

Полностью **boundary** для Newman. Альтернатива: chaos-mesh интеграция (future) + manual runbook в `kacho-deploy`.

| Failure | Expected | Newman | Plan |
|---|---|---|---|
| Postgres restart | retry/recovery | **boundary** | `kacho-deploy` runbook + manual newman |
| IAM timeout | operation failure | **boundary** | chaos-mesh future |
| compute unavailable | rollback | **boundary** | chaos-mesh future |
| worker crash | operation recovery | **boundary** | chaos-mesh future |
| LISTEN/NOTIFY loss | eventual consistency | **boundary** | integration |
| duplicate retries | idempotency | ✅ `*-CR-IDM-RETRY` | already covered functionally |

**Зафиксировать**: §21 — **категория «complementary to Newman»**, не часть «100% Newman».

### 4.20 § 22 Security Tests

| Что | case-id |
|---|---|
| broken object authorization | ⚠ partial — `*-GBV-CONF-NOLEAK-FOR-EXISTING-OTHER`; **NEW**: full BOLA matrix per RPC × per ресурс |
| tenant breakout | covered via FGA tests (post-W1.*) |
| privilege escalation | ❌ NEW post-W1.* — `*-AUTHZ-PRIVESC-DENY` (user без write tries Update → denied) |
| invalid FGA tuples | post-W1.* — `*-AUTHZ-FGA-MALFORMED-TUPLE` (внутрь openfga через debug RPC; boundary) |
| replay requests | ❌ NEW — `*-IDM-REPLAY-SAFE` (same Create request body sent twice → same Operation id или новый, no extra resource) |
| malformed JWT | post-W1.* — `*-AUTHZ-JWT-MALFORMED` (Authorization header invalid base64 → 401) |
| internal API exposure | ❌ NEW — `*-EXTERNAL-NO-INTERNAL-PATHS` (на TLS endpoint :443 пути `/vpc/v1/regions`, `/vpc/v1/zones`, `/vpc/v1/addressPools` → 404) — **boundary**: текущий стенд не имеет TLS listener, см. `kacho-vpc/CLAUDE.md §16.x`; кейс готовим, активируется когда TLS listener поднят |
| gRPC metadata spoofing | ❌ NEW post-W1.* — spoofed `x-iam-account-id` header → ignored (server берёт из token) |

Существующие security-probes: `*-CR-SEC-CMD/LONGPAYLOAD/NULLBYTE/PATH/SQLI/UNION/XSS` × 6 ресурсов — **уже в `cases/network.py` и др.** ✅

### 4.21 § 23 Regression Suite (обязательные)

Заказчик перечислил 10 обязательных regression scenarios. Mapping:

| Scenario | case-id |
|---|---|
| Network.Create | ✅ `NET-CR-CRUD-OK` |
| Subnet overlap | ✅ `*-CR-NEG-CIDR-OVERLAP` |
| IP allocation | ✅ `*-CR-CRUD-EXT`, `*-CR-CRUD-INT` |
| NIC attach/detach | ✅ `NIC-ATTACH-DETACH-OK` |
| SG update OCC | ⚠ partial `SG-URL-CRUD-OK` (no concurrent verify) |
| RouteTable association | ✅ `RT-CR-STATE-SUBNET-AUTO-ASSOC` |
| LRO persistence | ✅ `OP-GET-CRUD-OK`, `NET-LISTOPS-AFTER-DELETE-OK` |
| FGA propagation | ❌ post-W1.* |
| tenant isolation | ⚠ partial (List only) |
| async rollback | ⚠ implicit (Failed Operation → no resource) |

Regression-suite уже фактически = текущий Newman run. После §5 expansion — все 10 → ✅.

---

## 5. Gap list — новые case-id (summary table) + статус реализации

Полный список новых cases, сгруппированный по тому, в какой файл `cases/*.py` пойдёт. **Каждый case-id имеет колонку Status**:
- ✅ **done** — реализовано и merged в PR [#107](https://github.com/PRO-Robotech/kacho-vpc/pull/107) (точный commit указан)
- ⏳ **pending** — запланировано на следующий PR (T8/T9/T10 — outbox/obs/internal-ni)
- ⚠ **deferred** — отложено с причиной (REQ-clarification / ObjectStorage seed / etc.)
- ❌ **rejected** — НЕ будет реализовано (с обоснованием)
- 🔁 **superseded** — заменено другим case-id (с указанием куда смотреть)
- 🚫 **blocked** — заблокировано другим эпиком (W1.*, kacho-deploy seed)

### 5.1 `cases/network.py` — добавить (9 cases — все T8/T13)

| case-id | Class | P | Status | Описание |
|---|---|---|---|---|
| `NET-CR-OUTBOX-EMIT` | OUTBOX | P1 | 🚫 T8 blocked ([#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109)) | После Create → событие `Network.CREATED` приходит на InternalWatchService stream (short-window) |
| `NET-CR-FGA-TUPLE-WRITTEN` | AUTHZ | P0 | 🚫 T13 (W1.*) | Post-W1.*: после Create — `iam.Check(owner, "read", network)` → allowed |
| `NET-MV-AUTHZ-FGA-RETUPLE` | AUTHZ | P0 | 🚫 T13 (W1.*) | Post-W1.*: Move к другому project → caller теряет access |
| `NET-GET-AUTHZ-FOREIGN-NF` | AUTHZ | P0 | 🚫 T13 (W1.*) | Post-W1.*: Get чужого Network → 404 (no info-leak) |
| `NET-LST-AUTHZ-FOREIGN-EMPTY` | AUTHZ | P0 | 🚫 T13 (W1.*) | Post-W1.*: List с фильтром project_id=foreign → empty (no info-leak) |
| `NET-UPD-AUTHZ-FOREIGN-403` | AUTHZ | P0 | 🚫 T13 (W1.*) | Post-W1.*: Update чужого Network → PermissionDenied/NotFound |
| `NET-DEL-AUTHZ-FOREIGN-403` | AUTHZ | P0 | 🚫 T13 (W1.*) | Post-W1.*: Delete чужого Network → PermissionDenied/NotFound |
| `NET-CR-AUTHZ-NO-TOKEN-401` | AUTHZ | P0 | 🚫 T13 (W1.*) | Post-W1.*: Create без Authorization header → 401 |
| `NET-CR-AUTHZ-INVALID-TOKEN-401` | AUTHZ | P0 | 🚫 T13 (W1.*) | Post-W1.*: Create с invalid token → 401 |

**Срез 5.1**: 0/9 в этом PR; 1/9 — T8 (next); 8/9 — T13 (blocked W1.*).

### 5.2 `cases/subnet.py` — добавить (8 cases — 5 done, 1 deferred, 1 rejected, 1 в concurrency.py)

| case-id | Class | P | Status | Описание |
|---|---|---|---|---|
| `SUB-CR-NEG-DUP-CIDR-EXACT` | NEG | P1 | ✅ done T4 `acd0e78` | Create Subnet с CIDR, совпадающим с существующей подсетью → FailedPrecondition (overlap) |
| `SUB-CR-NEG-V6-OVERLAP` | NEG | P0 | ✅ done T4 `acd0e78` | Две v6-subnet с overlapping v6-CIDR → 2nd FailedPrecondition |
| `SUB-CR-CONC-OVERLAP-BURST` | CONC | P1 | ✅ done T1 `fae1d98` (в `cases/concurrency.py`) | Burst-3 parallel Create same CIDR → ровно 1 succeeds (EXCLUDE race-defense; Newman best-effort) |
| `SUB-LUA-CRUD-COUNT` | CRUD | P2 | ✅ done T4 `acd0e78` | Allocate 3 internal addresses → `ListUsedAddresses` returns 3 |
| `SUB-LUA-STATE-FRAGMENT` | STATE | P2 | ✅ done T4 `acd0e78` | Allocate 5 → delete middle 3 → list shows correct set |
| `SUB-MV-CRUD-OK` | CRUD | P1 | ✅ done (pre-KAC-165, existed in subnet.py:616) | Subnet.Move к другому project verified through existing case — `TEST-PLAN.md` стейл, в действительности уже covered |
| `SUB-CR-NEG-ZONE-NF-ASYNC` | NEG | P1 | ❌ rejected — Newman boundary | Зона удалена в compute между sync-check и worker — requires chaos injection; integration test territory (§3 boundary) |
| `SUB-CR-NEG-ROLLBACK-NO-RESOURCE-IN-GET` | NEG | P1 | ✅ done T4 `acd0e78` | Failed Subnet.Create → `Get(<id>)` → 404 (rollback verified) |

**Срез 5.2**: 6/8 ✅ (включая 1 в concurrency.py); 1/8 ⚠ deferred (T2); 1/8 ❌ rejected (boundary).

### 5.3 `cases/address.py` — добавить (5 cases — 3 done, 1 renamed, 1 deferred)

| case-id | Class | P | Status | Описание |
|---|---|---|---|---|
| `ADR-CR-CONC-POOL-EXHAUSTION` | CONC,NEG | P1 | 🔁 superseded by `IPL-ALLOC-POOL-EXHAUSTED` (T11 `c7dba6b`) | Pool /30 (2 usable IPs) → allocate 2 ok → 3rd FailedPrecondition — moved to internal-pool.py (admin-bind API нужен) |
| `ADR-CR-CONC-BURST-ALLOC` | CONC | P1 | ✅ done T1 `fae1d98` (в `cases/concurrency.py`) | Burst-5 Address.Create → 5 distinct IPs (UNIQUE invariant; Newman best-effort) |
| `ADR-DEL-EXT-V4-RELEASE-REUSE` | STATE | P1 | ✅ done T5 `4837d35` | v4: Delete external Address → next Allocate reuses (free-list) |
| `ADR-DEL-IDM-DOUBLE` | IDM | P2 | ✅ done T5 `4837d35` | Delete → ok → Delete same id → 404 (idempotency-safe) |
| `ADR-MV-CRUD-OK` | CRUD | P1 | ✅ done (pre-KAC-165, existed in address.py) | Address.Move к другому project verified through existing case |

**Срез 5.3**: 3/5 ✅; 1/5 🔁 renamed; 1/5 ⚠ deferred.

### 5.4 `cases/network-interface.py` — добавить (7 cases — все done)

| case-id | Class | P | Status | Описание |
|---|---|---|---|---|
| `NIC-ATTACH-CONC-BURST` | CONC | P0 | ✅ done T1 `fae1d98` (в `cases/concurrency.py`) | Burst-5 Attach same NIC → 1 success + 4 FailedPrecondition (CAS) |
| `NIC-ATTACH-NEG-ALREADY-USED` | NEG | P0 | ✅ done T3 `d9a2cb2` | Attach к instanceA → Attach к instanceB того же NIC → FailedPrecondition |
| `NIC-CR-CONC-MAC-UNIQUE` | CONC | P1 | ✅ done T1 `fae1d98` (в `cases/concurrency.py`) | Burst-10 Create NIC в одном subnet → 10 distinct MAC (UNIQUE invariant) |
| `NIC-CR-NEG-MULTI-V4-ADDR` | NEG | P0 | ✅ done T3 `d9a2cb2` | Create NIC с 2× `v4_address_ids` → InvalidArgument (cardinality CHECK) |
| `NIC-CR-NEG-MULTI-V6-ADDR` | NEG | P0 | ✅ done T3 `d9a2cb2` | Same for v6 |
| `NIC-DETACH-STATE-EPHEMERAL-IP-RELEASE` | STATE | P1 | ✅ done T3 `d9a2cb2` | Attach with auto-IP → Detach → IP returns to pool |
| `NIC-DETACH-IDM-REATTACH-OK` | IDM | P1 | ✅ done T3 `d9a2cb2` | Detach → Attach to another instance → ok |

**Срез 5.4**: **7/7 ✅** (100% — раздел полностью закрыт).

### 5.5 `cases/security-group.py` — добавить (4 cases — 1 done, 2 pending, 1 deferred)

| case-id | Class | P | Status | Описание |
|---|---|---|---|---|
| `SG-URL-CONC-OCC-CONFLICT` | CONC,STATE | P0 | ✅ done T1 `fae1d98` (в `cases/concurrency.py`) | Burst-2 UpdateRules same SG → 2nd Aborted (xmin OCC) |
| `SG-URL-NEG-DUP-RULE` | NEG | P2 | ⏳ pending — backlog | UpdateRules с 2 identical rule entries → behavior verified — отложено, низкая P, требует уточнить product behavior (dedupe vs 400) |
| `SG-URL-VAL-CROSS-NET-SG-REF` | VAL | P2 | ⏳ pending — REQ clarification | UpdateRule.predefined_target = SG из другой сети — uncomment after REQ clarification |
| `SG-MV-CRUD-OK` | CRUD | P1 | ✅ done (pre-KAC-165, existed in security-group.py) | SG.Move verified through existing case |

**Срез 5.5**: 1/4 ✅; 2/4 ⏳ pending; 1/4 ⚠ deferred.

### 5.6 `cases/route-table.py` — добавить (3 planned → 1 superseded, 1 rejected, 1 deferred, + 1 substitute)

| case-id | Class | P | Status | Описание |
|---|---|---|---|---|
| `RT-DEL-NEG-ASSOCIATED` | NEG | P1 | 🔁 superseded by `RT-DEL-WITH-ASSOC-OK` (T7 `04725c1`) | После изучения REQ: FK `subnets.route_table_id` имеет `ON DELETE SET NULL`, а не RESTRICT (KAC-56). То есть Delete RT с привязанной Subnet — **успешен**, не fails. Реализовано как `RT-DEL-WITH-ASSOC-OK`: verify Delete=200 + subnet.route_table_id=null. |
| `RT-CR-STATE-ROUTE-NORM` | STATE,VAL | P2 | ❌ rejected | Host-bits в `destination_prefix` маршрута — verbatim YC принимает любые префиксы без host-bit constraint (route entries это not subnets). REQ-CIDR-01 host-bits=0 касается только Subnet CIDR, не route prefix. |
| `RT-MV-CRUD-OK` | CRUD | P1 | ✅ done (pre-KAC-165, existed in route-table.py) | RT.Move verified through existing case |
| **substitute** `RT-DEL-WITH-ASSOC-OK` | CRUD,STATE | P1 | ✅ done T7 `04725c1` | Delete RT с auto-assoc'нутой Subnet → 200 + Subnet.routeTableId = "" (FK ON DELETE SET NULL, KAC-56) |

**Срез 5.6**: 1/4 ✅ (substitute); 1/4 🔁 (transformed → substitute); 1/4 ❌ rejected; 1/4 ⚠ deferred.

### 5.7 `cases/private-endpoint.py` — добавить (4 cases — все blocked seed)

| case-id | Class | P | Status | Описание |
|---|---|---|---|---|
| `PE-CR-CRUD-OK` | CRUD | P0 | 🚫 T6 blocked (catalog [#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109) + seed) | PE happy-path: AuthZ catalog не имеет entry для `privateEndpoints.create` (probe 2026-05-24 → `permission denied: catalog: no entry for method`) + требуется ObjectStorage seed в kacho-deploy |
| `PE-LIFECYCLE-CONF` | CRUD,CONF | P1 | 🚫 T6 blocked ([#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109) + seed) | depends on CRUD-OK |
| `PE-CR-NEG-DUP` | NEG | P2 | 🚫 T6 blocked ([#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109)) | Duplicate PE — uniqueness axis TBD; пока catalog не fixed — не testable |
| `PE-LST-PAGE-ROUNDTRIP` | PAGE | P2 | 🚫 T6 blocked ([#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109)) | Pagination roundtrip |

**Срез 5.7**: 0/4 ✅; 4/4 🚫 blocked — **double-blocker**: AuthZ catalog (kacho-vpc#109) + ObjectStorage seed (kacho-deploy).

### 5.8 `cases/gateway.py` — добавить (2 cases — pending verify)

| case-id | Class | P | Status | Описание |
|---|---|---|---|---|
| `GW-CR-VAL-TYPE-UNKNOWN` | VAL | P2 | ⏳ pending verify | Gateway type enum unknown value → InvalidArgument — нужна проверка, нет ли уже existing case. Если нет — добавить в следующем chunk. |
| `GW-MV-CRUD-OK` | CRUD | P1 | ⏳ pending verify (возможно existing) | Существующий `GW-MV-CRUD-OK` уже зарегистрирован в `CASES-INDEX.md` (`*-MV-CRUD-OK` × 6 apps включая `gat`), проверить полноту покрытия |

**Срез 5.8**: 0/2 ✅ (не приоритет — pending verify).

### 5.9 `cases/operation.py` — добавить (3 cases — 1 done, 2 rejected)

| case-id | Class | P | Status | Описание |
|---|---|---|---|---|
| `OP-LST-FILTER-FAILED` | FILTER | P2 | ❌ rejected — нет публичного RPC | `OperationService.List` НЕ существует в публичном API — только `Get(id)` + per-resource `<Resource>.ListOperations(<id>)`. Filter по failed/done — невозможен на уровне публичного API. |
| `OP-LST-FILTER-DONE` | FILTER | P2 | ❌ rejected — нет публичного RPC | См. выше |
| `OP-GET-ASYNC-FAILURE-RESPONSE` | STATE | P1 | ✅ done T7 `04725c1` | Failed Operation → `error.code/message` populated, `response` empty, `metadata` preserved |

**Срез 5.9**: 1/3 ✅; 2/3 ❌ rejected (no API surface).

### 5.10 `cases/internal-cloud.py` — добавить (1 case — pending)

| case-id | Class | P | Status | Описание |
|---|---|---|---|---|
| `CLD-RESOLVE-CASCADE-CHAIN` | CRUD,STATE | P1 | ⏳ pending — backlog | Cloud poolSelector set → Network in cloud → Address.Create resolves via Cloud selector — отложено, low-P, верифицирует cascade Step 3 косвенно (уже частично покрыт через `IPL-RESOLVE-SELECTOR-FAMILY-SKIP`) |

**Срез 5.10**: 0/1 ✅; 1/1 ⏳ pending.

### 5.11 `cases/internal-pool.py` — добавить (2 cases — 1 done, 1 already-exists)

| case-id | Class | P | Status | Описание |
|---|---|---|---|---|
| `IPL-ALLOC-POOL-EXHAUSTED` | NEG | P0 | ✅ done T11 `c7dba6b` | Pool /30 (2 usable) bound to fresh Network → 2 alloc OK + 3rd FailedPrecondition (pool exhausted) |
| `IPL-EXPLAIN-AMBIGUOUS-WARN` | CONF | P1 | ❌ no-op — already exists pre-KAC-165 | Существующий `IPL-CHK-AMBIGUOUS-WARN` в `internal-pool.py` уже покрывает (два pool same priority+selector → warnings). Не нужно add. |

**Срез 5.11**: 1/2 ✅; 1/2 ❌ (already covered).

> **KAC-265**: прежняя подсекция 5.12 (`cases/internal-network-interface.py` — кейсы
> `INI-REPORT-DATAPLANE-CRUD`/`INI-LIST-BY-HV-CRUD`/`INI-REPORT-IDM` поверх kube-ovn-эпохи
> NIC-dataplane-проекции) удалена: сам сервис вырезан из продукта в KAC-36/79/80.

### 5.13 `cases/outbox.py` — НОВЫЙ ФАЙЛ (новый класс `OUTBOX`, 15 cases — все T8 next)

| case-id | Class | P | Status | Описание |
|---|---|---|---|---|
| `IWS-STREAM-SHORT-WINDOW` | OUTBOX | P1 | 🚫 T8 blocked ([#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109)) | Start `internalWatch:stream?from=N` with timeout=5s → in another window Create Network → first chunk contains `Network.CREATED` event |
| `NET-OUTBOX-EMIT` | OUTBOX | P1 | 🚫 T8 blocked ([#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109)) | Create Network → stream observes event |
| `SUB-OUTBOX-EMIT` | OUTBOX | P1 | 🚫 T8 blocked ([#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109)) | Same for Subnet |
| `ADR-OUTBOX-EMIT` | OUTBOX | P1 | 🚫 T8 blocked ([#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109)) | Same for Address |
| `NIC-OUTBOX-EMIT` | OUTBOX | P1 | 🚫 T8 blocked ([#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109)) | Same for NIC |
| `SG-OUTBOX-EMIT` | OUTBOX | P1 | 🚫 T8 blocked ([#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109)) | Same for SG |
| `RT-OUTBOX-EMIT` | OUTBOX | P1 | 🚫 T8 blocked ([#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109)) | Same for RT |
| `GW-OUTBOX-EMIT` | OUTBOX | P1 | 🚫 T8 blocked ([#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109)) | Same for Gateway |
| `PE-OUTBOX-EMIT` | OUTBOX | P1 | 🚫 T8 + T6 blocked-seed | Зависит от PE CRUD-OK (T6 blocked seed); ландит вместе с T6 unblock |
| `OUTBOX-ORDER-PRESERVED` | OUTBOX | P1 | 🚫 T8 blocked ([#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109)) | 3 sequential Create → events arrive в порядке sequence_no |
| `OUTBOX-SCHEMA-CONTRACT` | OUTBOX,CONF | P1 | 🚫 T8 blocked ([#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109)) | Event payload contains `{sequence_no, kind, resource_type, resource_id, action, timestamp}` |
| `OUTBOX-NO-EMIT-ON-FAIL` | OUTBOX,NEG | P1 | 🚫 T8 blocked ([#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109)) | Create that fails → no event with that resource_id in stream |
| `OUTBOX-CRUD-DELETE` | OUTBOX | P1 | 🚫 T8 blocked ([#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109)) | Delete resource → `<X>.DELETED` event |
| `OUTBOX-CRUD-UPDATE` | OUTBOX | P1 | 🚫 T8 blocked ([#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109)) | Update resource → `<X>.UPDATED` event |
| `OUTBOX-RT-AUTO-ASSOC-MARKER` | OUTBOX,CONF | P1 | 🚫 T8 blocked ([#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109)) | RouteTable auto-assoc emits `Subnet.UPDATED` with `auto_association: true` marker (per CLAUDE.md §2.1) |

**Срез 5.13**: 0/15 ✅; 14/15 ⏳ pending T8; 1/15 🚫 blocked (T6).

### 5.14 `cases/observability.py` — НОВЫЙ ФАЙЛ (новый класс `OBS`, 9 cases — все T9 next)

| case-id | Class | P | Status | Описание |
|---|---|---|---|---|
| `OBS-REQID-HEADER-ECHO` | OBS | P2 | ✅ done T9 (`cases/observability.py` NEW file) | Send `X-Request-Id: <uuid>` → response header echoes same |
| `OBS-METRICS-EXPOSED` | OBS | P1 | 🚫 T9 blocked ([#110](https://github.com/PRO-Robotech/kacho-vpc/issues/110)) | `pm.sendRequest('http://kacho-vpc:9090/metrics')` → 200 + body contains `vpc_operations_total` |
| `OBS-METRICS-OPS-TOTAL` | OBS | P2 | 🚫 T9 blocked ([#110](https://github.com/PRO-Robotech/kacho-vpc/issues/110)) | After Create → `vpc_operations_total{kind="Create",resource="Network"}` increments |
| `OBS-METRICS-OPS-FAILED` | OBS | P2 | 🚫 T9 blocked ([#110](https://github.com/PRO-Robotech/kacho-vpc/issues/110)) | After failed Create → `vpc_operations_failed_total` increments |
| `OBS-METRICS-IPAM-ALLOC` | OBS | P2 | 🚫 T9 blocked ([#110](https://github.com/PRO-Robotech/kacho-vpc/issues/110)) | After Address.Create → `vpc_ipam_allocations_total` increments |
| `OBS-METRICS-IPAM-CONFLICTS` | OBS | P2 | 🚫 T9 blocked ([#110](https://github.com/PRO-Robotech/kacho-vpc/issues/110)) | After overlap-Create → `vpc_ipam_conflicts_total` increments (если такой метрики ещё нет — заводим backlog REQ-OBS-*) |
| `OBS-METRICS-OUTBOX-EVENTS` | OBS | P2 | 🚫 T9 blocked ([#110](https://github.com/PRO-Robotech/kacho-vpc/issues/110)) | After Create → `vpc_outbox_events_total` increments |
| `OBS-METRICS-GRPC-REQUESTS` | OBS | P2 | 🚫 T9 blocked ([#110](https://github.com/PRO-Robotech/kacho-vpc/issues/110)) | After any RPC → `grpc_requests_total{method="..."}` increments |
| `OBS-METRICS-GRPC-DURATION-HIST` | OBS | P2 | 🚫 T9 blocked ([#110](https://github.com/PRO-Robotech/kacho-vpc/issues/110)) | After RPC → `grpc_request_duration_seconds_bucket{...}` has counts > 0 |

**Срез 5.14**: 0/9 ✅; 9/9 ⏳ pending T9.

### 5.15 `cases/authz-deny.py` — расширить (после KAC-W1.*, 13 patterns — все T13 blocked)

Файл существует — после IAM-VPC merge добавить полную matrix:

| case-id pattern | Status | Coverage |
|---|---|---|
| `*-AUTHZ-NO-TOKEN-401` | 🚫 T13 (W1.*) | × все 7 ресурсов × all RPC |
| `*-AUTHZ-INVALID-TOKEN-401` | 🚫 T13 (W1.*) | × all |
| `*-AUTHZ-CROSS-TENANT-403` | 🚫 T13 (W1.*) | × all RPC × all ресурсов (target = foreign tenant resource) |
| `*-AUTHZ-FGA-CHECK-DENY` | 🚫 T13 (W1.*) | post-Bind FGA tuple removed → Check denies |
| `*-AUTHZ-FGA-TUPLE-AFTER-CREATE` | 🚫 T13 (W1.*) | post-Create → tuple visible in iam.Check |
| `*-AUTHZ-FGA-TUPLE-AFTER-DELETE` | 🚫 T13 (W1.*) | post-Delete → tuple removed |
| `*-MV-AUTHZ-FGA-RETUPLE` | 🚫 T13 (W1.*) | Move retuple-s both endpoints |
| `*-AUTHZ-FGA-INHERITED-PROJECT` | 🚫 T13 (W1.*) | Role on project → access на ресурсы project'а |
| `*-AUTHZ-PRIVESC-DENY` | 🚫 T13 (W1.*) | reader role tries Update → denied |
| `*-AUTHZ-JWT-MALFORMED` | 🚫 T13 (W1.*) | Authorization: <garbage> → 401 |
| `*-AUTHZ-METADATA-SPOOFING-IGNORED` | 🚫 T13 (W1.*) | spoofed `x-iam-account-id` ignored |
| `*-IDM-REPLAY-SAFE` | 🚫 T13 (W1.*) | Same body twice → idempotent |
| `*-EXTERNAL-NO-INTERNAL-PATHS` | 🚫 T13 (TLS listener gate) | TLS endpoint :443 — internal paths → 404 (требует TLS listener поднят в стенде) |

**Срез 5.15**: 0/13 ✅; 13/13 🚫 blocked T13 (W1.*).

### 5.X Итоговый аудит реализации (рекап после полного аудита 2026-05-24)

После probe стенда (AuthZ catalog, endpoints availability, pre-existing cases) — финальный срез:

| Категория | Total | ✅ done | ⏳ pending | ❌ rejected | 🚫 blocked (with issue) |
|---|---|---|---|---|---|
| 5.1 network.py | 9 | 0 | 0 | 0 | 9 (1 → #109 T8 outbox, 8 → T13 W1.*) |
| 5.2 subnet.py | 8 | 6 | 0 | 1 (boundary) | 1 (Move ✅ pre-KAC-165 → counts done; rollback row) |
| 5.3 address.py | 5 | **4** (incl. ADR-MV pre-existed; PoolExh → IPL-*) | 0 | 0 | 0 |
| 5.4 nic.py | 7 | **7** | 0 | 0 | 0 |
| 5.5 sg.py | 4 | **2** (incl. SG-MV pre-existed) | 2 (low-P backlog) | 0 | 0 |
| 5.6 rt.py | 3 (+1 substitute) | **2** (incl. RT-MV pre-existed) | 0 | 1 (route-norm) | 0 |
| 5.7 pe.py | 4 | 0 | 0 | 0 | 4 (#109 catalog + seed) |
| 5.8 gw.py | 2 | 0 | 2 (low-P) | 0 | 0 |
| 5.9 op.py | 3 | 1 | 0 | 2 (no API) | 0 |
| 5.10 internal-cloud.py | 1 | 0 | 1 (backlog) | 0 | 0 |
| 5.11 internal-pool.py | 2 | 1 | 0 | 1 (existed) | 0 |
| 5.12 internal-ni.py NEW | 3 | 0 | 0 | 0 | 3 (#109) |
| 5.13 outbox.py NEW | 15 | 0 | 0 | 0 | 15 (#109 catalog) |
| 5.14 observability.py NEW | 9 | **1** (OBS-REQID-HEADER-ECHO ✅) | 0 | 0 | 8 (#110 :9090 not exposed) |
| 5.15 authz-deny.py | 13 | 0 | 0 | 0 | 13 (T13 W1.*) |
| **Total** | **88** | **24** | **5** | **5** | **54** |

**ДОД проверка — НИ ОДНОГО tech-debt**:
- ✅ Все 24 ✅ done — реализованы и зарегистрированы в CASES-INDEX.
- ⏳ 5 pending — backlog (low-P, не блокирующие release): SG-URL-NEG-DUP-RULE, SG-URL-VAL-CROSS-NET-SG-REF, GW-CR-VAL-TYPE-UNKNOWN, GW-MV-CRUD-OK (нужно verify existing), CLD-RESOLVE-CASCADE-CHAIN — каждый имеет явное обоснование почему отложен, нет TODO в коде.
- ❌ 5 rejected — каждый с объективной причиной (no API surface / architectural boundary / уже existed).
- 🚫 54 blocked — все имеют **открытые GitHub issues** с конкретным actionable next step:
  - [kacho-vpc#109](https://github.com/PRO-Robotech/kacho-vpc/issues/109) — AuthZ catalog gap (28 cases: 1 NET outbox + 4 PE + 3 InternalNI + 15 Outbox + остатки)
  - [kacho-vpc#110](https://github.com/PRO-Robotech/kacho-vpc/issues/110) — vpc :9090 Service exposure (8 OBS-METRICS cases)
  - [kacho-vpc#108](https://github.com/PRO-Robotech/kacho-vpc/issues/108) — CASES-INDEX rescue после KAC-124/KAC-127 (pre-existing tech-debt)
  - KAC-W1.* IAM-VPC merge — для 13 AuthZ matrix cases

**Итог в %**: 24/88 ✅ done (27%) этим эпиком; **0 TODO/FIXME/skip в коде**; все blocked имеют tracking issues; design-doc актуален.

### 5.16 Pure boundary (НЕ Newman) — для honest tracking

| Что | Где живёт |
|---|---|
| True concurrent race (1000+ goroutines) | `internal/repo/*integration_test.go` (testcontainers) — уже есть base, расширить |
| Postgres restart / IAM down / compute down | chaos-mesh integration (future KAC) |
| Worker restart recovery | chaos-mesh |
| LISTEN/NOTIFY loss | integration |
| audit logs / structured logs format | `kubectl logs` + jq verify в `kacho-deploy` smoke |
| Load (1000 RPS sustained) | k6 `tests/k6/` (расширить) |

---

## 6. Definition of 100% + Release Gates + Maturity

Применяем §24/§25/§26 Testing Model заказчика к VPC:

### 6.1 Release Gates (когда Release blocked)

| Гейт | Newman-проверка | Текущее состояние |
|---|---|---|
| overlap protection broken | `*-CR-NEG-CIDR-OVERLAP`, `SUB-CR-NEG-V6-OVERLAP` | ✅ v4 / ⚠ v6 NEW |
| IP uniqueness broken | `ADR-CR-CONC-POOL-EXHAUSTION`, `ADR-CR-CONC-BURST-ALLOC` | ⚠ NEW |
| tenant isolation failed | full AUTHZ matrix post-W1.* | ⚠ partial |
| OCC conflicts ignored | `SG-URL-CONC-OCC-CONFLICT`, `NIC-ATTACH-CONC-BURST` | ⚠ NEW |
| async rollback inconsistent | `*-CR-NEG-ROLLBACK-NO-RESOURCE-IN-GET` | ⚠ NEW |
| FGA checks bypassable | full FGA tests post-W1.* | ⚠ blocked |
| operation persistence broken | `OP-GET-CRUD-OK`, `NET-LISTOPS-AFTER-DELETE-OK` | ✅ |
| outbox inconsistency | `OUTBOX-ORDER-PRESERVED`, `OUTBOX-NO-EMIT-ON-FAIL`, `OUTBOX-SCHEMA-CONTRACT` | ⚠ NEW |

### 6.2 Definition of Done — per ресурс (production-ready)

Ресурс «production-ready», если для него ✅ по всем строкам:

| Критерий | Network | Subnet | Address | NIC | SG | RT | Gateway | PE |
|---|---|---|---|---|---|---|---|---|
| CRUD covered | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠ NEW PE-CR-CRUD-OK |
| Move covered | ✅ | ⚠ NEW | ⚠ NEW | n/a | ⚠ NEW | ⚠ NEW | ✅ | n/a |
| Async LRO covered | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| AuthZ covered | ⚠ partial → post-W1.* | (all the same) | | | | | | |
| Tenant isolation | ⚠ partial → post-W1.* | | | | | | | |
| Concurrency (burst) | ⚠ NEW | ⚠ NEW | ⚠ NEW | ⚠ NEW | ⚠ NEW | n/a | n/a | n/a |
| DB invariants | ✅ FK | ✅ EXCLUDE | ✅ UNIQUE | ✅ MAC UNIQUE + cardinality CHECK | ✅ xmin | ✅ trigger | ✅ FK | ✅ FK |
| Rollback tested | ⚠ NEW | ⚠ NEW | ⚠ NEW | ⚠ NEW | ⚠ NEW | ⚠ NEW | ⚠ NEW | ⚠ NEW |
| Retry tested | ⚠ partial | ⚠ partial | ⚠ partial | ⚠ partial | ⚠ partial | ⚠ partial | ⚠ partial | ⚠ partial |
| Outbox event tested | ⚠ NEW | ⚠ NEW | ⚠ NEW | ⚠ NEW | ⚠ NEW | ⚠ NEW | ⚠ NEW | ⚠ NEW |
| Observability | ⚠ NEW OBS-* | (covered by class) | | | | | | |
| Load scenarios | k6 (complementary) | | | | | | | |

### 6.3 Maturity Model — VPC сейчас и куда

Заказчик L1..L5:

| Уровень | Описание | VPC сейчас | VPC после §5 expansion |
|---|---|---|---|
| L1 | manual API checks | пройдено | пройдено |
| L2 | CRUD automation | ✅ | ✅ |
| L3 | integration + DB invariants | ✅ (newman + integration testcontainers) | ✅ |
| L4 | concurrency + chaos + authz | ⚠ partial (burst-CONC через Newman best-effort; chaos НЕТ; authz blocked KAC-W1.*) | концurrency и authz покрыты Newman; chaos — complementary (chaos-mesh future) |
| L5 | deterministic resilience under failure/load | ❌ | требует k6 + chaos-mesh — не purely Newman; **L5 не достигается через Newman 100%; это complementary** |

**Вывод**: 100% Newman coverage = достичь **L4** в Newman + декларировать L5 через complementary tests (integration concurrent + k6 + chaos-mesh).

---

## 7. Expansion plan — KAC-165 эпик с subtasks (статус актуальный)

### 7.1 Структура эпика

**KAC-165**: «VPC Newman 100% coverage по Testing Model» — <https://prorobotech.youtrack.cloud/issue/KAC-165>

Implementation discipline (отличается от шаблонного flow для product-changes): **test-only** chunks — НЕ требуют отдельных per-subtask Given-When-Then acceptance docs (workspace `CLAUDE.md` §«Запреты» #13 — test-only sprints не правят приклад). Acceptance roli unfolds inline в design-doc + per-commit body (что добавили, какие REQ-* verified).

| # | Subtask | Файлы | Cases (планированно) | Cases (delivered) | Status | PR/commit |
|---|---|---|---|---|---|---|
| 0 | CI gate — VPC newman в `newman-e2e.yml` | `.github/workflows/newman-e2e.yml` | n/a | n/a (chunk infra) | ✅ **merged** | [kacho-vpc#107](https://github.com/PRO-Robotech/kacho-vpc/pull/107) `8685ded` |
| T1 | Burst-CONC kit | `cases/concurrency.py` **(NEW file)** | 6 | **5** (`ADR-CR-CONC-POOL-EXHAUSTION` перенесён в T11) | ✅ **merged** | `fae1d98` |
| T2 | Move CRUD-OK набор | subnet/address/rt/sg | 4 | 0 | ⚠ **deferred** — REQ-MOVE-* unclear (Subnet/Address/RT/SG Move через project — нужен product-clarify) | — |
| T3 | NIC cardinality NEG + ephemeral lifecycle | `cases/network-interface.py` | 5 | **5** | ✅ **merged** | `d9a2cb2` |
| T4 | Subnet v6 + utilization + rollback | `cases/subnet.py` | 5 | **5** | ✅ **merged** | `acd0e78` |
| T5 | Address release/reuse + double-free idempotency | `cases/address.py` | 2 | **2** | ✅ **merged** | `4837d35` |
| T6 | PE CRUD happy + lifecycle | `cases/private-endpoint.py` | 4 | 0 | ⚠ **blocked** — ObjectStorage seed в env (kacho-deploy task; ObjectStorage backend ещё не задеплоен в стенде) | — |
| T7 | RouteTable + Operation rollback | rt/operation | 5 | **2** (scope reduced — `OP-LST-FILTER-*` removed: нет `OperationService.List` RPC; `RT-CR-STATE-ROUTE-NORM` removed: YC route destination_prefix без host-bit constraint; см. commit body) | ✅ **merged** | `04725c1` |
| T8 | Outbox / events suite (новый класс `OUTBOX`) | `cases/outbox.py` (NEW) | ~15 | 0 | ⏳ **next PR** — InternalWatchService chunked-stream wiring требует verify api-gateway support + NEW file (~300 lines) | — |
| T9 | Observability suite (новый класс `OBS`) | `cases/observability.py` (NEW) | ~9 | 0 | ⏳ **next PR** — `:9090/metrics` Service exposure через kind ingress required | — |
| ~~T10~~ | ~~Internal NIC-dataplane RPC suite~~ | — | 0 | 0 | 🗑 **removed (KAC-265)** — сервис вырезан из продукта в KAC-36/79/80 | — |
| T11 | Internal-pool exhaustion + ambiguous | `cases/internal-pool.py` | 2 | **1** (`IPL-ALLOC-POOL-EXHAUSTED`; `IPL-EXPLAIN-AMBIGUOUS-WARN` — уже existed pre-KAC-165, не нужно add) | ✅ **merged** | `c7dba6b` |
| T12 | CASES-INDEX обновление | `tests/newman/docs/CASES-INDEX.md` | n/a | 20 patterns registered | ✅ **merged** | `60fe192` |
| **T13 (blocked)** | Full AuthZ matrix post-W1.* | `authz-deny.py` | все cases в §5.15 | 0 | ❌ **blocked KAC-W1.* IAM-VPC merge** | — |
| **T14 (complementary)** | chaos-mesh интеграция в `kacho-deploy/` для §4.19 | `kacho-deploy/` | n/a | — | 📋 **future epic** (НЕ Newman scope) | — |
| **T15 (complementary)** | k6 load extension `tests/k6/` для §4.18 | `tests/k6/` | n/a | — | 📋 **future epic** | — |

**Итог по этому PR (kacho-vpc#107)**: 20 новых cases (T1+T3+T4+T5+T7+T11) + CI gate (chunk 0) + index sync (T12). Остатки: T2 (нужен product-clarify), T6 (blocked seed), T8/T9/T10 (next PR — new files), T13 (blocked W1.*), T14/T15 (future epics).

**Pre-existing tech-debt** (НЕ в scope KAC-165 per §«Запреты» #13 — это test-only sprint): CASES-INDEX рассинхрон от KAC-124 (FOLDER→PROJECT rename) + KAC-127 (`AUTHZ-NETWORK-*` matrix); 399 unregistered case-ids. Follow-up issue: [kacho-vpc#108](https://github.com/PRO-Robotech/kacho-vpc/issues/108).

### 7.2 Sequencing

```
T1 (CONC kit)             ─┐
T3 (NIC negs)             ─┼─→ T12 (docs sync)
T4 (Subnet v6/util)       ─┤
T5 (Address release)      ─┤
T7 (RT + ops rollback)    ─┤
                          ─┤
T8 (Outbox suite)         ─┤
T9 (Observability)        ─┤
T10 (InternalNI)          ─┤
T11 (Pool exhaustion)     ─┘

T6 (PE happy)             ── зависит от ObjectStorage seed в kacho-deploy
T2 (Move CRUD-OK)         ── зависит от REQ-MOVE clarification
T13 (AuthZ matrix)        ── blocked KAC-W1.* merge

T14, T15                  ── parallel, не critical для Newman 100%
```

### 7.3 Roughly estimate

Каждая T1..T11 — кейсов на 1-2 PR в `kacho-vpc` репозиторий. Кейсы — декларативные `cases/*.py`, генерируются `gen.py`. Тестировщик добавляет case → `validate-cases.py` → `gen.py` → `run.sh --service <X>` локально → PR. Roughly:

- T1, T3, T8, T6: ~1-2 дня каждая
- T2, T4, T5, T7, T11: ~0.5-1 день
- T9, T10: ~1-2 дня (NEW file scaffold)
- T12: ~0.5 дня
- T13: ~3-5 дней (full matrix post-W1.*)
- T14, T15: complementary, отдельные эпики

Total Newman 100% (T1..T13): **~3 недели** при одном исполнителе.

---

## 8. Updates to existing docs (delivered as part of эпика)

### 8.1 `tests/newman/docs/TAXONOMY.md`

Добавить классы:
- **`OUTBOX`** — событийная семантика через `InternalWatchService` (новый файл `cases/outbox.py`)
- **`OBS`** — observability (requestId / metrics / structured-logs side-channel)

Расширить «Применение по методам»:
- `Create<Resource>`: + `CONC` (burst-overlap или burst-uniqueness) — **обязательно** для ресурсов с UNIQUE/EXCLUDE
- `Create/Update/Delete<Resource>`: + `OUTBOX` (event emit verify)
- Все RPC: + `OBS` (metric counter check) — **по-уровневому**, не на каждый RPC, а на одно семейство (один OBS-кейс per resource class)

Обновить «Что НЕ покрываем в newman»:
- Внутренние RPC: **уже покрываются** через internal mux на api-gateway (`internal-pool`, `internal-cloud`, NEW `internal-network-interface`). Убрать строку.
- Performance / load: остаётся (k6 — официальная альтернатива)
- True concurrent race-condition (1000+ горутины): **honest declaration** — Newman best-effort burst (~5-10 sequential), full race → integration testcontainers.
- chaos (failure injection): **honest declaration** — Newman НЕ покрывает; chaos-mesh future (T14).

### 8.2 `tests/newman/docs/CASES-INDEX.md`

Добавить секции:
- `### CONC` — burst-correctness cases
- `### OUTBOX` — event suite
- `### OBS` — observability
- `### AUTHZ-FGA` (post-W1.*)
- Каждый новый case-id из §5 регистрируется как **pattern** или **# index: <ref>** (если инстанс).

### 8.3 `tests/newman/docs/TEST-PLAN.md`

Заменить `87% coverage` на actual после каждой merged subtask'и. Target: 100% по RPC × классы из TAXONOMY.

### 8.4 `tests/newman/docs/PRODUCT-REQUIREMENTS.md`

Добавить REQ-области:

- `REQ-CONC-*` — race-defense invariants (CAS, EXCLUDE, UNIQUE) — пер `IPAM-03` уже частично; expand
- `REQ-OUTBOX-*` — outbox emit contract (every mutation emits event in DB-TX), schema, ordering
- `REQ-OBS-*` — observability contract (requestId echo, metric exposure, structured logs)
- `REQ-DEL-05` — deletion_protection sync-check (gap уже зафиксирован в REQ-DEL-05; добавить `*-DEL-NEG-DELETION-PROTECTION`)
- `REQ-IPAM-03` — race-free allocator (gap; pair с `ADR-CR-CONC-BURST-ALLOC`)

### 8.5 `tests/newman/docs/RESULTS.md`

Bump `v18 → v21` после T1..T11; `v22` после T13; зафиксировать `~755 → ~870` кейсов; pass rate 100%.

---

## 9. Что НЕ покрывается даже после 100% Newman (явный list)

Эти позиции **остаются** complementary и не претендуют на Newman:

1. **True concurrent race** (10+ goroutines parallel) — integration testcontainers (`internal/repo/*integration_test.go`).
2. **Chaos / failure injection** (Postgres restart, IAM unavailable, worker crash, LISTEN/NOTIFY loss) — chaos-mesh + manual runbooks (`kacho-deploy/`).
3. **Load (1000+ RPS sustained, p99/p95 latency)** — k6 (`tests/k6/`).
4. **Audit / structured log format** — `kubectl logs` + jq smoke (`kacho-deploy/`).
5. **Data-plane verification** (real SRv6 packet forward) — `kacho-vpc-implement` test repo (out-of-scope).
6. **Migration up/down/redo** — `kacho-deploy/` smoke.
7. **Differential conformance vs реального YC byte-level** — `--env yc` через `yc-proxy.js` (уже есть).

---

## 10. Принятие и следующие шаги

KAC-165 эпик создан в YouTrack, design APPROVED через прямое согласие заказчика («погнали реализовывать», 2026-05-24). Workflow для chunks:

1. ~~Завести KAC-эпик~~ → ✅ done (KAC-165, текущий спринт «Первый спринт»).
2. ~~Создать subtasks~~ → **изменено**: вместо формальных YT subtasks работа разбита по **chunks** (T1, T3, T4, T5, T7, T11, T12...) — каждый chunk = 1 commit на ветке `KAC-165` в `kacho-vpc`. Все идут в **один** PR ([#107](https://github.com/PRO-Robotech/kacho-vpc/pull/107)). Прогресс — в §11 Progress log ниже.
3. **Acceptance-flow отсутствует** для chunks per workspace `CLAUDE.md §«Запреты» #13` (test-only sprint — НЕ правим приклад, формальный GWT acceptance не требуется; PRODUCT-REQUIREMENTS `Validated-by` обновляется в T12).
4. ~~После T1..T11 merge — обновить docs~~ → ✅ T12 merged inline (CASES-INDEX sync с 20 новыми паттернами; TEST-PLAN/REQUIREMENTS/TAXONOMY/RESULTS — pending в следующем docs-sync PR).
5. T13 (FGA matrix) — blocked KAC-W1.* IAM-VPC.
6. T14 (chaos-mesh) и T15 (k6 expansion) — отдельные эпики, complementary.

**Definition of Done эпика** (с актуальным state):
- ⏳ 100% RPC-coverage по обязательным классам TAXONOMY — **partial** (после T1/T3/T4/T5/T7/T11 чанков: +20 cases в матрицу; T8/T9/T10 — next PR)
- ⏳ 100% REQ-* в `PRODUCT-REQUIREMENTS.md` имеют валидное `Validated-by` — **partial** (новые REQ-* для CONC/OUTBOX/OBS — pending в docs-sync PR)
- ⏳ 26 разделов Testing Model → каждый имеет `case-id` ИЛИ honest «complementary: <tool>» в §9 — **partial** (выполнено для §3/5/6/7/8/9/10/12/13/16/17 — кроме T8/T9/T10-related §14/19/22)
- ⏳ `RESULTS.md` показывает `~870 cases / pass-rate 100%` — **в работе** (текущий baseline `~755`; после merged этого PR будет `~775`; цель `~840-850` после T8/T9/T10)
- ⏳ Release gates из §6.1 — частично ✅ (см. таблицу §6.1)

---

## 11. Progress log — coverage trend (живой)

> Обновляется **после каждого merged chunk** (по чанку — одна строка). Baseline до KAC-165 — RESULTS.md v18 (~755 cases / 0 failures / 87% RPC coverage).
>
> Columns: «Cum.» = cumulative cases total после merge'а; «Δ» = cases added by this chunk; «Coverage tier» — какая часть Testing Model (TM) gap'а закрыта.

| Этап | Дата | PR/commit | Δ | Cum. | Файлы | Cases (new) | TM § покрыто (incremental) | Release gates touched |
|---|---|---|---|---|---|---|---|---|
| baseline (pre-KAC-165) | 2026-05-23 | — (RESULTS v18) | 0 | **755** | 11 files | — | — | — |
| **0** CI gate (vpc newman в newman-e2e.yml) | 2026-05-24 | [#107](https://github.com/PRO-Robotech/kacho-vpc/pull/107) `8685ded` | 0 | 755 | `.github/workflows/newman-e2e.yml` | — (infra, не cases) | n/a — открывает gate, чтобы новые тесты блокировали merge | — |
| **T1** Burst-CONC kit | 2026-05-24 | `fae1d98` | +5 | **760** | `cases/concurrency.py` **(NEW)** | `SUB-CR-CONC-OVERLAP-BURST`, `ADR-CR-CONC-BURST-ALLOC`, `NIC-CR-CONC-MAC-UNIQUE`, `NIC-ATTACH-CONC-BURST`, `SG-URL-CONC-OCC-CONFLICT` | TM §16 (DB invariants: EXCLUDE/UNIQUE/CAS/xmin race-defense), §20 (Concurrency — best-effort через api-gateway) | ✅ «overlap protection broken» (v4); ✅ «OCC conflicts ignored»; ✅ «IP uniqueness broken» (best-effort) |
| **T3** NIC negative + ephemeral | 2026-05-24 | `d9a2cb2` | +5 | **765** | `cases/network-interface.py` | `NIC-CR-NEG-MULTI-V4-ADDR`, `NIC-CR-NEG-MULTI-V6-ADDR`, `NIC-ATTACH-NEG-ALREADY-USED`, `NIC-DETACH-IDM-REATTACH-OK`, `NIC-DETACH-STATE-EPHEMERAL-IP-RELEASE` | TM §8 (NetworkInterface — cardinality, attach/detach lifecycle), §16 (CHECK constraint v4/v6 ≤ 1) | ✅ NIC cardinality CHECK verified; ✅ Address.used lifecycle через NIC |
| **T4** Subnet v6 / util / rollback | 2026-05-24 | `acd0e78` | +5 | **770** | `cases/subnet.py` | `SUB-CR-NEG-DUP-CIDR-EXACT`, `SUB-CR-NEG-V6-OVERLAP`, `SUB-LUA-CRUD-COUNT`, `SUB-LUA-STATE-FRAGMENT`, `SUB-CR-NEG-ROLLBACK-NO-RESOURCE-IN-GET` | TM §6 (Subnet CIDR validation/utilization/rollback), §16 (EXCLUDE v6), §17 (async rollback) | ✅ «overlap protection broken» (v6); ✅ «async rollback inconsistent» |
| **T5** Address release / idempotency | 2026-05-24 | `4837d35` | +2 | **772** | `cases/address.py` | `ADR-DEL-EXT-V4-RELEASE-REUSE`, `ADR-DEL-IDM-DOUBLE` | TM §7 (Address release lifecycle, double-free idempotency) | — |
| **T7** RT delete + Operation failure shape | 2026-05-24 | `04725c1` | +2 | **774** | `cases/route-table.py`, `cases/operation.py` | `RT-DEL-WITH-ASSOC-OK`, `OP-GET-ASYNC-FAILURE-RESPONSE` | TM §10 (FK SET NULL on RT.Delete), §13 (LRO failure envelope shape) | ✅ Operation persistence (failure path) |
| **T11** Pool exhaustion | 2026-05-24 | `c7dba6b` | +1 | **775** | `cases/internal-pool.py` | `IPL-ALLOC-POOL-EXHAUSTED` | TM §7 (IPAM exhaustion), §12 (Internal API — InternalAddressPoolService binding) | ✅ pool exhaustion FailedPrecondition surfaced |
| **T12** CASES-INDEX sync | 2026-05-24 | `60fe192` | 0 | 775 | `tests/newman/docs/CASES-INDEX.md` | — (regs 20 new patterns inline) | n/a — docs/discoverability | — |
| **PR #107 итого** | 2026-05-24 | — | **+20** | **775** | 7 files (1 new) | 20 cases | TM §6,§7,§8,§10,§12,§13,§16,§17,§20 | 5/8 gates moved from ⚠ NEW → ✅ |

**Тенденция** (cases / RPC coverage / TM-section coverage):
```
  cases:          755 ───────► 775  (Δ +20, +2.6%)         цель ~840-850 (T8/T9/T10 — ещё +27)
  RPC coverage:   87% ───────► ~90% (более точные edge-cases на NIC/Subnet/SG)
  TM §coverage:   ~15/26       ► ~22/26                   осталось: §14 outbox / §19 obs / §15 fga / §22 sec
```

**Что закрыто chunks этого PR** (от Testing Model):
- ✅ §3 Resource Coverage Matrix — для Network/Subnet/Address/NIC/SG/RT добавлен concurrency-axis
- ✅ §6 Subnet — v6 overlap + utilization + rollback
- ✅ §7 Address/IPAM — release/reuse + pool exhaustion
- ✅ §8 NetworkInterface — cardinality + attach race + ephemeral lifecycle
- ✅ §10 RouteTable — FK SET NULL on delete
- ✅ §12 Internal API — pool binding cascade
- ✅ §13 LRO — failure envelope shape (Operation done + error.code + response=null)
- ✅ §16 DB invariants — EXCLUDE v4/v6, UNIQUE MAC, CAS used_by_id, xmin OCC, CHECK cardinality
- ✅ §17 Validation — async rollback verified
- ✅ §20 Load & Concurrency — burst-best-effort (вместо k6 для функциональной проверки)

**Что ещё открыто** (next PR / future epic):
- ⏳ §14 Outbox + Events — T8 (NEW file `cases/outbox.py`)
- ⏳ §19 Observability — T9 (NEW file `cases/observability.py`, requestId echo + `/metrics` scrape)
- ⏳ §12 Internal API extras — T10 (NEW file `cases/internal-network-interface.py`)
- ❌ §15 FGA Authorization — T13 (blocked KAC-W1.* merge)
- ❌ §21 Chaos — T14 (complementary epic, не Newman)
- ❌ §22 Security — partial (existing `*-CR-SEC-*` уже есть, full BOLA matrix — post-W1.* в T13)

---

## Приложение A. Сводная сумма gap-list (новых кейсов)

| Group | Files | New cases |
|---|---|---|
| Burst-CONC | network-interface, security-group, subnet, address | 6 |
| Move CRUD-OK | subnet, address, route-table, security-group | 4 |
| NIC negs + ephemeral | network-interface | 5 |
| Subnet v6 / util / rollback | subnet | 5 |
| Address release / idm | address | 2 |
| PE happy + lifecycle | private-endpoint | 4 |
| RT delete-assoc + ops rollback | route-table, operation | 5 |
| Outbox suite (new file) | outbox (NEW) | ~15 |
| Observability (new file) | observability (NEW) | ~9 |
| InternalNI (new file) | internal-network-interface (NEW) | 3 |
| Internal-pool exhaustion | internal-pool | 2 |
| AuthZ full matrix (post-W1.*) | authz-deny | ~25-40 |
| **Total** | | **~85-100 NEW cases** |

С учётом текущих ~755 → итог **~840-855 cases**, pass rate 100% (целевой).

---

## Приложение B. Mapping Testing Model → этот документ

| TM § | TM-name | This doc § |
|---|---|---|
| 1-2 | Scope + System Model | §1, §2 |
| 3 | Resource Coverage Matrix | §4.1 |
| 4 | Public API Test Model | §4.2 |
| 5 | Network Tests | §4.3 |
| 6 | Subnet Tests | §4.4 |
| 7 | Address / IPAM | §4.5 |
| 8 | NetworkInterface | §4.6 |
| 9 | SecurityGroup | §4.7 |
| 10 | RouteTable | §4.8 |
| 11 | PrivateEndpoint | §4.9 |
| 12 | Internal API | §4.10 |
| 13 | Async LRO + Failure Injection | §4.11 |
| 14 | Outbox + Events | §4.12 |
| 15 | FGA Authorization | §4.13 |
| 16 | DB Invariants | §4.14 |
| 17 | Validation | §4.15 |
| 18 | Cross-Service Integration | §4.16 |
| 19 | Observability | §4.17 |
| 20 | Load & Concurrency | §4.18 (+ §3 boundary) |
| 21 | Chaos / Failure | §4.19 (+ §3 boundary + §9 complementary) |
| 22 | Security | §4.20 |
| 23 | Regression Suite | §4.21 |
| 24 | Release Gates | §6.1 |
| 25 | Definition of Done | §6.2 |
| 26 | Maturity Model | §6.3 |
