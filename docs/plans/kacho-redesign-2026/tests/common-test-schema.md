# Kachō — КАНОНИЧНАЯ common-test-schema тестового harness

> Нормативный эталон, к которому приводятся **все** сервисы монорепо
> (`iam · geo · vpc · compute · storage · registry · nlb`). Извлечён из reference-эталонов
> `services/vpc/tests/newman/` (vpc — reference per rules), `services/iam/tests/newman/`
> (richest), `tests/authz-fixtures/setup.sh`, `deploy/scripts/newman-parallel.sh` и
> vpc integration-tests (`internal/repo/*integration_test.go`). Правила-источник:
> `.claude/rules/testing.md` (§e2e-инварианты, §Newman EC-дисциплина, §параллельный newman),
> `api-conventions.md` (Operation.done ≠ downstream-visibility), `data-integrity.md`.
>
> **Источник истины для генерируемых артефактов — декларативные `cases/*.py`.**
> Postman-коллекции `collections/*.json` — **генерируются** `scripts/gen.py`; править
> руками их запрещено.

---

## 1. Обязательный layout дерева `tests/newman`

Каждый сервис (`services/<svc>/tests/newman/`, gateway — `gateway/tests/newman/`) держит:

```
tests/newman/
├── README.md                       — назначение, quick-start, принципы (black-box, изоляция, ECP/BVA)
├── cases/                          — ИСТОЧНИК ИСТИНЫ: декларативные Python case-наборы
│   ├── <resource>.py               — публичные RPC ресурса (Get/List/Create/Update/Delete/:verb)
│   ├── internal-<x>.py             — Internal*/admin-only RPC (prefix IPL-*/CLD-*; на {{internalBaseUrl}})
│   └── authz-deny.py               — per-RPC authz-gate deny-matrix (shared-tenant, 6 субъектов)
├── collections/                    — СГЕНЕРИРОВАННЫЕ Postman v2.1 JSON (НЕ править руками)
│   └── <resource>.postman_collection.json
├── environments/
│   └── local.postman_environment.json   — local stand (api-gateway public :18080 / internal :18081)
├── scripts/
│   ├── gen.py                      — генератор коллекций из cases/* (+ инжектит helper-namespace)
│   ├── validate-cases.py           — MANDATORY pure-Python CI-гейт: dup-id + CASES-INDEX-покрытие
│   ├── run.sh                      — прогон одного/всех сервисов (--jobs fan-out, serial-collections.txt)
│   └── run-incremental.{sh,js}     — по одному кейсу + cleanup (низкий resource-footprint); опционально
├── docs/
│   ├── TAXONOMY.md                 — классы кейсов (CRUD/VAL/NEG/BVA/IDM/CONC/CONF) + naming
│   ├── TEST-PLAN.md                — карта покрытия RPC × класс
│   ├── CASES-INDEX.md              — каталог УНИКАЛЬНЫХ паттернов кейсов (гейт validate-cases)
│   ├── PRODUCT-REQUIREMENTS.md     — нормативные REQ-* (источник conformance)
│   ├── REQUIREMENTS.md             — бэклог testability-asks (не нормативный)
│   └── RESULTS.md                  — последний прогон pass/fail + «Known failing — product bugs» + история
├── serial-collections.txt          — (опц.) коллекции, что НЕ гоняются concurrent (pool/CIDR/default-partition contention)
└── out/                            — newman raw + summary.txt (gitignored)
```

Fixture-seed живёт **не в каждом suite**, а централизованно: `tests/authz-fixtures/setup.sh`
(общий per-service isolation seed) + `deploy/scripts/newman-parallel.sh` (оркестратор).
Мини-фикстуру `crud-fixture/setup.sh` (как в iam) допустимо держать локально для standalone-прогона —
но она обязана быть **строгим subset** authz-fixtures и делегировать ей при наличии.

**Декларативные структуры (`gen.py`):** `Step(name, method, path, body, pre_script,
test_script, auth, internal)` и `Case(id, title, classes, priority, steps)`.
`path` — относительный (`{{baseUrl}}`/`{{internalBaseUrl}}` префикс автоматически);
`internal=True` → запрос идёт на cluster-internal REST listener (Internal*-RPC на public 404 by design, ban #6).

---

## 2. Обязательные хелперы (сигнатуры + когда применять / НЕ применять)

Все определены в `scripts/gen.py` и инжектятся в namespace каждого `cases/*.py`.
**Каждый сервис несёт идентичный набор** — parity обязателен (расхождение сигнатур = дефект схемы).

### 2.1 Ассерт-хелперы (детерминированные, без retry)

| Хелпер | Назначение |
|---|---|
| `assert_status(code)` | `pm.response.code === code` |
| `assert_grpc_code(code, code_name)` | `body.code === code` (grpc-gateway `{code,message,details}`) |
| `assert_operation_envelope()` | mutation → `{id: /^[a-z0-9]+$/, metadata: object}` (async Operation) |
| `assert_field_violation(field)` | `details[].BadRequest.fieldViolations[].field === field` |
| `assert_transcode_error()` | 400 + непустое тело (JSON-transcoding-ошибка) |
| `save_from_response(jsonpath, env_var)` | сохранить значение из response в env |
| `poll_operation_until_done()` | poll-step `GET /operations/{{opId}}` до `done` |

### 2.2 Negative-толерантность (authz-first) — **НЕ оборачивать в retry**

```python
assert_unscoped_rejected()      # unscoped create/list (без projectId) → oneOf([400,403]) / code oneOf([3,7])
assert_absent_id_rejected()     # Get/Update/Delete/:verb по absent/malformed id → oneOf([400,403,404]) / code oneOf([3,5,7])
```

Обоснование (обязательное, `security.md` «authz-first», `testing.md` §negative-ordering):
gateway scope_extractor **fail-close'ит 403 ДО** backend-валидации (не может резолвить
target→project для anti-BOLA у несуществующего/битого id). STRICT-`404`/`400`-негатив
ложно падает на корректном `403`. Толерантность `400|403|404` **не маскировка** — семантика
негатива (rejected) сохранена; реальный scope-deny всё равно пинится отдельным precond-шагом.
Malformed-id и GET-by-id доходят до backend (400/404) — их message-контракт
(`"<Resource> <id> not found"`) проверяется на GET-пути **точным текстом**, не ослабляется.

### 2.3 EC read-your-writes retry-хелперы — оборачивать **ТОЛЬКО первый доступ к своему свежему ресурсу**

```python
retry_until_authorized(step, budget=25, interval_ms=500, retry_on=(403,404))
retry_until_present(step, id_env_var, budget=25, interval_ms=500)
retry_until_absent(step, still_present_expr, budget=25, interval_ms=500)   # mirror — для revoke/leak-guard окна
```

**`retry_until_authorized(step)`** — bounded-retry SAME request (setNextRequest→self) пока
код в `retry_on` (default 403/404), busy-wait `interval_ms` между попытками. Причина:
opgate снят по design-review — `Operation.done` = ресурс DURABLE, но owner/creator FGA-tuple
материализуется **eventually-consistent** (at-least-once drainer + reconciler + sync-registrar).
Первый post-create Get/Update/Delete своего свежего ресурса может кратко отдать 403/404.
Это read-your-writes лаг — чинится **на клиенте**, НЕ серверным барьером
(`api-conventions.md`: гейтить `done` на видимость downstream — ban #9, phantom).

**`retry_until_present(step, idVar)`** — retry LIST пока СВОЙ свежий id **отсутствует** в
200-массиве (list-authz visibility окно; 200 отдаётся, но id absent → 403/404-retry не
применим). **`retry_until_absent(step, expr)`** — MIRROR: retry «must-be-empty» leak-guard
пока `expr` truthy (revoke/contamination окно под параллелью).

**Budget-семантика (все три):** `budget × interval_ms` ограничивает ожидание (~10-13s),
**fail-open по budget** — real assertion прогоняется РОВНО раз на терминальном ответе и
**ПАДАЕТ**, если не сошлось. Никогда не бесконечно, никогда не замаскировано. Step
переименовывается (`-rya<N>`/`-lst<N>`/`-abs<N>`) чтобы self-retry `setNextRequest(requestName)`
резолвился в СЕБЯ (иначе newman прыгает на первый одноимённый step).

**НЕ оборачивать (жёсткий запрет):** negatives, cross-account deny, absent/malformed-id,
sync-4xx (get-404 / immutable-400), давно-существующие ресурсы, `lst-excludes`-guard'ы.
Retry там **маскирует реальный deny**. Частый промах: обёрнут mutate, но НЕ последующий
verify/list — оборачивать нужно именно первый verify своего ресурса.

### 2.4 op-poll с РЕАЛЬНОЙ inter-poll задержкой

`poll_operation_until_done()` → уникальное имя `poll-op-<N>` (self-retry), до **30 попыток
× ~500ms busy-wait** (≈15s async-op tail, p95 3s / max 10s). Back-to-back поллы без задержки
хаммерят и сами создают нагрузку (Koren #1). Guard: пустой `opId` (предыдущий шаг sync-reject
403) или non-200 → poll-ассерты скипаются чисто, не добавляются к failure-count. Сохраняет
`lastOpError`/`lastOpResponse` в env.

### 2.5 `ensure_<resource>` — op.error ПЕРЕД извлечением id (анти-phantom)

Fixture-seed helper (`setup.sh`: `ensure_account`/`ensure_project`/…):

```
POST → op_id → poll_op(op_id) до done:true → ASSERT !result.error → ТОЛЬКО тогда metadata.<res>Id
```

**Kachō Operation несёт pre-allocated id в `metadata` ДАЖЕ на `done:true` с `error`** (id
аллоцируется до async-фейла). Хелпер, читающий `metadata.<res>Id` без проверки `result.error`,
вернёт **фантомный id** несозданного ресурса → пропатчит в env → downstream FGA-биндинги
пишутся против фантома (gateway 200), а cross-service peer-check (`vpc/compute → iam
ProjectService.Get`) отдаёт `NOT_FOUND` → каскад. `authz-fixtures/setup.sh` дополнительно
**верифицирует** seeded project через `ProjectService.Get` и WARN'ит на phantom. Флейки-фикстура
→ предпочесть **self-seed свежего ресурса per-case** (не shared-литерал env-var).

---

## 3. Fixture-изоляция (директива #2) + runId + cleanup

### 3.1 Per-service изоляция — КАЖДЫЙ resource-suite держит СВОЙ account + home/cross projects

Корень cross-suite collision (#276): shared `account-A/projA1/projA2` на все resource-suite →
grant/revoke или залистанный ресурс одного suite течёт в ожидания другого (account→project
containment) → параллельный прогон небезопасен. **Фикс** (`authz-fixtures/setup.sh` Phase B):

```
ACCOUNT_VPC = ensure_account("authz-vpc")   → VPC_HOME="authz-vpc-home"   + VPC_CROSS="authz-vpc-cross"
ACCOUNT_CMP = ensure_account("authz-compute")→ COMPUTE_PROJ + COMPUTE_CROSS (+ network/subnet/sg seed)
ACCOUNT_NLB = ensure_account("authz-nlb")   → NLB_PROJ (+ external-VIP AddressPool)
```

Каждый suite патчится **таргетно** (не общим глобом — иначе один `existingProjectId` затрёт
другой) в env:  `existingProjectId` / `existingProjectCrossId`. Дефолтный actor
(`jwtProjectAdminA1`) гранится editor на **ОБА** своих проекта (create-in-home + list-in-cross).

В `cases/*.py` suite-scope резолвится через `PRE_GLOBAL` (в `gen.py`):
```
_suiteProjectId      = existingProjectId || projectA1Id   (fallback на shared matrix для standalone dev)
_suiteProjectCrossId = existingProjectCrossId || projectA2Id
```

**Исключения (намеренно shared):** 6-субъектная **authz-deny matrix** — её контракт держится
на shared-account (`projectA1Id`/`B1Id` напрямую). Never-granted subject `jwtPureNoBindings`
(ни один suite его НЕ грантит) — для exact-visibility leak-guard'ов, отдельно от `userNOB`
(его access-binding-suite грантит). Exact-visibility-кейсы → fresh per-run private account.

### 3.2 runId-суффикс + zone-resolve (`PRE_GLOBAL`, первым в каждой коллекции)

`runId` — 10-символьный `[a-z0-9]` (без точки, проходит name-regex), генерится раз на прогон.
**Каждый фикстур-ресурс с UNIQUE(name) несёт `{{runId}}`-суффикс** (`net-cr-{{runId}}`):
фиксированное имя коллизит `409 AlreadyExists` на повторном прогоне (даже max-len BVA — runId
вшивается в пределах лимита). Zone-id резолвится ОДНАЖДЫ синхронно из geo-каталога (первым
item коллекции — `GET /geo/v1/zones`, best-effort, fallback на committed `existingZoneId`).

### 3.3 Shared-resource entropy (параллель)

CIDR/pool/name под параллелью коллизят детерминированно (маскируется под EC-флейк). Subnet-CIDR
несёт **широкую run-random энтропию ОБОИХ октетов** (~56k /24), НЕ узкий `hash(runId)%N`.
Cross-service shared-CIDR — disjoint блоки (напр. `100.100.0.0/16` internal-pool / `100.101.0.0/16`
address). При «блуждающем» флейке (1-2 РАЗНЫЕ суиты/прогон) — **сначала проверь
collision (CIDR/pool/name), потом вини EC**.

### 3.4 Cleanup

Cleanup своих ресурсов **обязателен** (leak → пул растёт, list-контракты плывут): каждый CRUD-кейс
завершается `cleanup-delete`-шагом. Preclean-revoke обязан **ретраить DELETE на 403** до успеха
(best-effort teardown, принявший transient 403 → binding остался ACTIVE → ALREADY_EXISTS на
повторном прогоне). `run-incremental.{sh,js}` даёт periodic + `--cleanup-only`.

---

## 4. gen / validate / parallel workflow

### 4.1 Порядок (обязательный)

```
1. правишь/добавляешь cases/<x>.py               (декларативно, TDD: RED-кейс ДО прод-фикса)
2. python3 scripts/validate-cases.py             # ← MANDATORY CI-гейт, pure-Python, без сети
3. python3 scripts/gen.py [<service>]            # регенерит collections/*.json (НЕ править руками)
4. ./scripts/run.sh [--service <x>] [--jobs N]   # newman → out/<svc>.json + summary.txt
```

`validate-cases.py` (hard-fail exit 1): **(1)** дубль case-id среди ВСЕХ кейсов (внутри/между
файлами/helper-блоки) запрещён; **(2)** каждый case-id зафиксирован в `docs/CASES-INDEX.md` —
суффикс-паттерн `*-<SUFFIX>` ИЛИ литеральный id в тексте, ЛИБО помечен `# index: <ref>` рядом с
`id=` (инстанс известного паттерна). Исключение: `internal-*.py` (admin/IPAM) — каталогизированы
заметкой, но dup-id-проверка работает. Также вызывается как `gen.py --validate`.

### 4.2 Параллельный прогон

`run.sh` fan-out'ит коллекции одного сервиса с cap `--jobs` (default 4); коллекции из
`serial-collections.txt` (по одному стему на строку, `#`-comments) гоняются **строго по одной**
(pool/CIDR/default-partition contention — напр. AddressPool `is_default (zone,kind)` + zone-collapse).

`deploy/scripts/newman-parallel.sh` — оркестратор всех сервисов:
1. port-forward gateway public(:18080)+internal(:18081) + iam-internal(:19091), mTLS client-cert для grpcurl;
2. seed `authz-fixtures/setup.sh` ОДИН раз (per-service isolated) + patch env каждого suite;
3. seed pool-фикстуры (nlb external-VIP AddressPool) — best-effort;
4. `gen.py` для каждого suite;
5. **двухволновой scheduler**: `PHASE2_SERVICES=iam` (default) идёт **отдельной второй волной**,
   НЕ concurrent с leaf-нагрузкой — iam-собственная authz-материализация (AccessBinding CRUD,
   label-revoke) full-path EXCLUSIVE-lock, под пиковой leaf-нагрузкой дрейнит. nlb форсится
   `--jobs 1` (shared external AddressPool исчерпывается под `--jobs>1` → phantom);
6. aggregate: per-suite summary, non-zero exit если ЛЮБАЯ красная.

wall-time = `dev-up + max(wave1) + wave2(iam)` вместо `sum(all)` (serial 90мин → parallel ~35мин).

---

## 5. Integration-требования (`internal/repo/*integration_test.go`)

### 5.1 testcontainers-харнесс (shared, `integration_test.go`)

```go
func setupTestDB(t testing.TB) string {
    pgc, _ := postgres.Run(ctx, "postgres:16-alpine",
        postgres.WithDatabase("kacho_<domain>_test"),
        postgres.WithUsername(...), postgres.WithPassword(...),
        postgres.BasicWaitStrategies())
    t.Cleanup(func() { _ = pgc.Terminate(ctx) })
    // goose.SetBaseFS(migrations.FS); goose.Up(db, ".")   ← реальные миграции сервиса
    return appendSearchPathOptions(dsn)   // search_path=kacho_<domain>,public
}
```

Каждый тест: `if testing.Short() { t.Skip(...) }` первым стейтментом (`make test-short` их
пропускает). Реальные goose-миграции (не хардкод DDL) — тест верифицирует ту же схему, что прод.

### 5.2 Concurrent-race goroutines — на КАЖДЫЙ спорный DB-инвариант (обязательно, `data-integrity.md` §чек-лист п.5)

Инвариант, меняемый конкурирующими путями (CAS attach/detach, UNIQUE, EXCLUDE, SKIP-LOCKED
allocate, OCC/xmin), обязан нести integration-тест с **N goroutine на спорный путь** — ровно
одна транзакция проходит, остальные получают ожидаемый sentinel. Эталон:

```go
var wg sync.WaitGroup; errs := [2]error{}
wg.Add(2)
for i := 0; i < 2; i++ {
    go func(idx int) { defer wg.Done()
        _, errs[idx] = uc.Execute(ctx, req /* пересекающийся CIDR / тот же owner-slot */)
    }(i)
}
wg.Wait()
// ровно 1 успех; проигравший — codes.FailedPrecondition/AlreadyExists (маппинг SQLSTATE)
```

Покрытые классы (vpc-эталон): `ConcurrentOverlap` (EXCLUDE gist), `SetReferenceRace`
(single-statement CAS → `pgx.ErrNoRows` → FailedPrecondition), `ConcurrentAllocateUnique`
(FOR UPDATE SKIP LOCKED freelist), `security_group_occ` (xmin OCC), `DeleteVsConcurrentAttach`
(FOR UPDATE toctou), `default_sg_cas`. **Без concurrent-теста race не ловится unit'ом — не мёржим.**

Под нагрузкой Docker таймаутит: гонять `go test -p 1` при contention.

---

## 6. Regression-lock на уровне ОБСЕРВАБЛА (security/leak-фиксы)

Security/leak/PII/APICONV-фикс локает **наблюдаемое поведение**, не только gRPC-код — иначе
рефактор, реинтродуцирующий баг, оставляет suite зелёным (`testing.md` §regression-lock):

| Класс фикса | Что ассертить (НЕ только код) |
|---|---|
| Error-leak (INTERNAL → фикс. текст) | `status.Convert(err).Message() == "internal error"` **или** `NotContains(msg, <raw-pgx-text>)` |
| PII | `NotContains(logBuf, <email/token>)` на success- И error-пути |
| APICONV (timestamp/malformed-id/immutable/SQLSTATE) | точный текст/усечение/код (`"<field> is immutable after <R>.Create"`, truncate до секунд) |
| Hide-existence 404 | deny-текст **byte-identical** реальному miss (`"<Resource> <id> not found"`) |
| Concurrency (wg-drain/race) | под `-race`, детерминированно (blocker держит слот, backlog копится, Stop→Wait завершается), НЕ `time.Sleep` |

Каждый security-багфикс несёт свой behaviour-level regression-тест в ТОМ ЖЕ PR (ban #12).
Newman-эквивалент: message-контракт (`assert_field_violation`, точный NotFound-текст на GET-пути).

---

## 7. Чеклист «сервис соответствует common-test-schema, если…»

- [ ] **Layout**: есть `tests/newman/{cases,collections,environments,scripts,docs,out}` + `README.md`;
      `scripts/{gen.py,validate-cases.py,run.sh}`; `docs/{TAXONOMY,TEST-PLAN,CASES-INDEX,PRODUCT-REQUIREMENTS,RESULTS}.md`.
- [ ] **Коллекции генерируются**: `collections/*.json` — продукт `gen.py`, руками не правлены; `cases/*.py` — источник истины.
- [ ] **validate-cases зелёный**: 0 дублей case-id, каждый id в `CASES-INDEX.md` или помечен `# index:`.
- [ ] **Хелперы parity**: `assert_status/grpc_code/operation_envelope/field_violation`, `save_from_response`,
      `poll_operation_until_done`, `assert_unscoped_rejected`, `assert_absent_id_rejected`,
      `retry_until_authorized`, `retry_until_present`, `retry_until_absent` — идентичные сигнатуры vpc/iam.
- [ ] **op-poll**: `poll_operation_until_done` — уникальное имя `poll-op-<N>`, ~500ms inter-poll busy-wait, budget 30 (~15s), guard на пустой opId.
- [ ] **EC-retry дисциплина**: обёрнут ТОЛЬКО первый доступ к своему свежему ресурсу; negatives/cross-account/absent-id — НЕ обёрнуты; budget fail-open.
- [ ] **Anti-phantom**: `ensure_<resource>` проверяет `!op.error` ПЕРЕД `metadata.<res>Id`; seed верифицирует project через `ProjectService.Get`.
- [ ] **Fixture-изоляция**: suite сидится в СВОЙ account + home/cross project (`authz-fixtures/setup.sh` Phase B), патчится таргетно в `existingProjectId`/`existingProjectCrossId`; shared только authz-deny matrix + never-granted subject.
- [ ] **runId + cleanup**: все UNIQUE(name)-ресурсы несут `{{runId}}`; каждый CRUD-кейс имеет `cleanup-delete`; preclean-revoke ретраит DELETE на 403.
- [ ] **Shared-entropy**: CIDR/pool/name — широкая run-random энтропия; contended-коллекции в `serial-collections.txt`.
- [ ] **Параллель**: `run.sh --jobs` fan-out; `newman-parallel.sh` two-wave (iam в PHASE2, nlb `--jobs 1`).
- [ ] **Integration**: `internal/repo/*integration_test.go` — testcontainers `postgres:16-alpine`, реальные goose-миграции, `testing.Short()`-skip; каждый CAS/UNIQUE/EXCLUDE/OCC/SKIP-LOCKED-инвариант — concurrent-goroutine тест (ровно 1 winner); `-p 1` при contention.
- [ ] **Regression-lock**: каждый security/leak/PII/APICONV-фикс ассертит message/лог/текст (обсёрвабл), не только gRPC-код, в ТОМ ЖЕ PR.
- [ ] **RESULTS.md**: 100% pass кроме declared «Known failing — product bugs» (rule #13) с KAC-trail.
- [ ] **TDD**: RED-кейс написан и прогнан ДО прод-фикса; newman-кейс ПОСЛЕ кода — нарушение (даже если зелёный).
