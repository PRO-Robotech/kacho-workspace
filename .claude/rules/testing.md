# Тестирование (строгий TDD)

## Test-first — обязательно (ban #12)

**Сначала тест, потом код.** Падающий тест (RED) пишется и **прогоняется ДО** кода
фикса/фичи — подтверждается, что падает по нужной причине (фича/фикс отсутствует, не
опечатка). Затем код → GREEN. Касается **всех** уровней — Go unit/integration И
newman-кейсов. Newman/integration-тест, написанный уже ПОСЛЕ кода, — нарушение (даже если зелёный).

Чанк из нескольких изменений: написать ВСЕ падающие тесты первыми → RED по всем → чинить
по одному в GREEN. В PR/отчёте показывать пару «RED → GREEN»; заявлять о готовности без неё нельзя.

Каждый PR с новым RPC / новым полем / новым oneof-case / новой публичной функцией обязан содержать **в том же PR**:
- **Integration-тест** (`internal/repo/*integration_test.go`) — testcontainers Postgres, SQL-сторона,
  включая concurrent-race-сценарии для CAS/UNIQUE/EXCLUDE.
- **Newman-кейс** (`tests/newman/cases/*.py` → `gen.py`) — black-box через api-gateway, ≥1 happy + ≥1 negative.

«out of scope / follow-up / TBD» как обоснование отсутствия тестов — запрещено. Единственное
исключение: PR ссылается на **уже открытый** KAC-тикет под эти тесты (`Tests-followup: KAC-N`),
заведённый и привязанный к эпику ДО merge. Reviewer/агент reject'ит PR без тестов.

## Test-only PR (ban #13)

Задача «дописать тесты под существующий функционал»:
- **Прод-код НЕ трогаем** — только `tests/`/`docs/`. Любой `internal/`/`cmd/`/`migrations/`-фикс → отдельный PR со своим KAC.
- **TODO/FIXME/`pm.test.skip`/закомментированный assert — запрещены** в тестах так же строго, как в проде.
- **TDD-red против реального бага прода** = finding, не tech-debt: (a) GitHub Issue (`bug` + `verified-by:test`);
  (b) в кейсе `# verifies <issue-url>` (без skip); (c) кейс остаётся красным до фикса прода —
  допустимое исключение из «100% pass» с декларацией в `RESULTS.md` «Known failing — product bugs» + KAC-trail.

## Пирамида и инфраструктура

- **unit** (`apps/kacho/api/<resource>/usecase_test.go`, `internal/handler/*_test.go`) — mock port-интерфейсов
  из `internal/repo/repomock`/`kachomock`; LRO дожидаются детерминированно (`AwaitOpDone`), не `time.Sleep`.
  Если service-тест требует Postgres → утечка adapter в use-case.
- **integration** (`internal/repo/*integration_test.go`) — testcontainers Postgres 16; CRUD, EXCLUDE/FK/UNIQUE,
  outbox-транзакционность, CAS/OCC/SKIP-LOCKED races. Под нагрузкой Docker может таймаутить — гонять `-p 1` при contention.
- **e2e/newman** (`tests/newman/`) — главная regression-инфра; декларативные `cases/*.py` → `gen.py` → Postman-коллекции;
  только HTTP через api-gateway. Workflow нового кейса: `validate-cases.py` (уникальность + CASES-INDEX) → `gen.py`.
- **fuzz** (`internal/fuzz/`) и **k6/ghz** (нагрузка) — где применимо.

### e2e-инварианты (выведено из e2e-newman стабилизации; применять во ВСЕХ suite'ах)

- **Read-your-writes eventual-consistency retry.** opgate (create confirm-gate) снят по
  design-review: `Operation.done` = ресурс DURABLE, но owner/hierarchy FGA-tuple материализуется
  **eventually-consistent** (authz/list-filter negative-cache TTL ≈5s). ПЕРВЫЙ Get/Update/Delete
  **своего** только что созданного ресурса может кратко отдать `403`/`404`, а List — не содержать
  его. Это read-your-writes лаг, чинится **на клиенте** bounded-retry, не сервер-барьером. В newman:
  `retry_until_authorized(step)` (retry на 403/404 у Get/Update/Delete своего свежего ресурса),
  `retry_until_present(step, "<idVar>")` (retry у List пока свой свежий id отсутствует). Budget
  покрывает ~10s. Оборачивать ТОЛЬКО первый доступ к своему ресурсу — НИКОГДА negative/cross-account/
  absent-id/`lst-excludes` (retry там маскирует реальный deny). Касается hand-written `cases/*.py`
  ТАК ЖЕ, как generator-блоков (частый промах — обёрнут mutate, но не последующий verify/list).
- **Authz-first толерантность негативов.** Gateway гейтит authz ДО backend-валидации. Create без
  scope-поля (напр. `projectId`) → `project:*` unscoped → **fail-closed 403** (не 400). Get/Update/
  Delete/`:verb` по несуществующему/malformed id → 403 (scope_extractor не резолвит target→project),
  а не только 404. Negative-кейсы обязаны толерировать `oneOf([400,403,404])` (`assert_absent_id_rejected`),
  иначе ложно падают на корректном authz-first 403.
- **Per-service fixture isolation (директива #2).** Каждый resource-suite (vpc/nlb/compute) держит
  **свой account + home/cross projects** (`setup.sh`), НЕ общий account-A/projA1/projA2 — иначе grant/
  revoke или залистанный ресурс одного suite течёт в ожидания другого (cross-suite collision) и
  параллельный прогон небезопасен. Общий 6-субъектный **authz-deny matrix** остаётся на shared-account
  (это его контракт). Suite-scope через `existingProjectId`/`existingProjectCrossId`, дефолтный actor
  гранится editor на ОБА своих проекта.
- **Идемпотентность прогона.** Фикстур-ресурсы с UNIQUE(name) обязаны нести `{{runId}}`-суффикс —
  фиксированное имя коллизит `409 AlreadyExists` на повторном прогоне (даже max-len BVA — вшивай runId
  в пределах лимита). Cleanup своих ресурсов обязателен (leak → пул растёт, list-контракты плывут).

Методология: skills `testing-code-coach` (unit/integration), `testing-product-coach` (black-box техники),
`load-testing-coach` / `<svc>-load-testing` (нагрузка). Финальная верификация перед merge:
`go test ./... -race` + `golangci-lint run` + `govulncheck` + newman зелёные.

## Regression-lock security/leak-фиксов — на уровне ОБСЕРВАБЛА (выведено из audit-раундов)

Security/leak/PII-фикс обязан локать **наблюдаемое поведение**, а не только gRPC-код — иначе
рефактор, реинтродуцирующий баг, оставляет suite зелёным:

- **Error-leak фикс** (INTERNAL → фикс. текст): assert `status.Convert(err).Message() == "internal error"`
  (или `NotContains(msg, <raw-err-text>)`), НЕ только `status.Code(err) == codes.Internal`.
- **PII-фикс**: assert `NotContains(logBuf, <email/token>)` на success- И error-пути (харнесс logBuf).
- **APICONV-фикс** (timestamp/malformed-id/immutable-msg/SQLSTATE): assert точный текст/усечение/код.
- **Каждый security-багфикс несёт свой regression-тест в ТОМ ЖЕ PR** (ban #12) — не «code-level», а
  «behaviour-level». RPC, в который сел фикс, но который был вообще без функционального теста, —
  добери handler-level unit (fake-порты) в том же PR.
- **Concurrency-фикс** (wg-drain, race) — тест под `-race`, детерминированно (blocker держит слот,
  backlog копится, Stop→Wait должен завершиться), не `time.Sleep`.

## Newman e2e — eventual-consistency дисциплина (выведено из owner-tuple раундов)

Kachō eventually-consistent (`api-conventions.md` Operation.done), поэтому black-box newman
обязан быть **robust к read-your-writes окну**, но НИКОГДА не маскировать реальный дефект:

- **create→immediate-mutate/get СВОЕГО ресурса** → **bounded-retry** на transient `403`/`404`
  (owner-tuple/материализация ещё не видна): helper `retry_until_authorized` (retry SELF на 403/404,
  budget×interval ≈ покрытие 6-10s, **fail-open по budget → реальный assert падает если не сошлось**,
  никогда бесконечно). **create→list-includes СВОЕГО ресурса** → `retry_until_present` (retry пока id
  отсутствует в 200-массиве). Оборачивать ТОЛЬКО первый пост-create доступ к своему свежему ресурсу.
  НЕ оборачивать: negatives, cross-account deny, sync-4xx (get-404/immutable-400), давно-существующие.
- **op-poll с РЕАЛЬНОЙ inter-poll задержкой** (busy-wait ~400-500ms в retry-петле, budget покрывает
  async-op tail ~15s): back-to-back поллы без задержки хаммерят и сами создают нагрузку.
  **Правило проверяемо и относится к КАЖДОЙ рукописной петле, не только к хелперам gen.py**:
  любой `pm.execution.setNextRequest(pm.info.requestName)` (self-retry) ОБЯЗАН иметь busy-wait
  **непосредственно перед ним** — `const _x = Date.now(); while (Date.now() - _x < N) void 0;`
  (newman исполняет test-script синхронно и вызывает setNextRequest ДО любого setTimeout →
  busy-wait — единственный способ реально разнести поллы). Без него петля на 30 итераций
  покрывает **~0.15s**, а не секунды: op завершался за 3.6s, а кейс сдавался мгновенно
  (инцидент `IAM-USR-INV-CRUD-OK`; sweep нашёл **51** такую петлю в 26 case-файлах iam/registry/nlb).
  **Задержку размеряй от cap петли, а не константой**: `delay = clamp(30000/cap, 100..500)ms` —
  caps в delay-less петлях исторически раздували именно чтобы компенсировать отсутствие
  ожидания (`POLL_CAP=300`), поэтому фиксированные 500ms дали бы 150s worst-case. Проверка
  (grep-гейт): каждый `setNextRequest(pm.info.requestName)` имеет `while (Date.now() - _` в
  пределах 4 строк выше. **Симптом класса**: «поллер сдался, хотя async-хвост был здоров» —
  выглядит как materialization-лаг сервиса, а на деле проба вообще не ждала.
- **Per-suite fixture isolation (директива, корень cross-suite collision):** каждый resource-suite
  (vpc/nlb/compute) сидится в **свой account + project**, НЕ в общий (иначе PROJECT-scope грант одной
  суиты течёт в матрицу другой → ложные over-show/leak, вынужденный whitelist). Общий shared-tenant
  контракт (6-subject authz-deny matrix) — намеренное исключение, остаётся на общем аккаунте.
- **Параллельный прогон суит** (независимы при изоляции) — `newman-parallel.sh` fan-out iam/vpc/compute/nlb
  после единого seed → wall-time = max(суита), убирает serial-timeout. Debug — точечно: `newman run
  collections/<битая>.json` + `--folder <case>`; Go-фикс → `make reload-svc SVC=x` (patch без dev-up) → re-run той коллекции.
- **negative-authz-ordering толерантность:** gateway scope_extractor fail-closes `403` на unscoped/
  well-formed-nonexistent id ДО backend-валидации (authz-first, anti-BOLA) → negative-кейс, ждущий
  `400`/`404`, обязан принимать **`403|400|404`** (`assert_unscoped_rejected`/`assert_absent_id_rejected`).
  Это не маскировка: authz-отказ на недоступный объект — защитимое поведение. Malformed-id и GET-by-id
  доходят до backend (400/404) — их НЕ ослаблять. Реальный product-баг в тексте/коде → Go-фикс + RED-lock, НЕ толерантность.
- **Fixture-seed обязан проверять `op.error` перед извлечением resource-id из `metadata`.** Kachō Operation
  несёт **pre-allocated id в `metadata` ДАЖЕ на `done:true` с `error`** (id аллоцируется до async-фейла). Хелпер
  `ensure_<resource>`, читающий `metadata.<res>Id` без проверки `result.error`, вернёт **фантомный id** несозданного
  ресурса → пропатчит его в env → downstream FGA-биндинги пишутся против фантома (gateway 200), а cross-service
  peer-check (`vpc/compute → iam ProjectService.Get`) отдаёт `NOT_FOUND` → каскад. Всегда: op-poll до `done` → assert
  `!op.error` → только тогда извлекай id. Флейки-фикстура — предпочти **self-seed свежего ресурса per-case** (не
  shared-литерал env-var, который мог async-упасть) — как `discover_zone`/`create_suite_project`.
- **Serialised suite (`--jobs 1`) для pool-contended ресурсов.** Кейсы, аллоцирующие из ограниченного пула
  (external VIP/AddressPool, N адресов), под `--jobs >1` исчерпывают пул → `could not allocate` → phantom-ресурс →
  каскад. Либо больший пул (seed-CIDR), либо `--jobs 1` для этой суиты, либо перевод на pool-independent ресурс
  (INTERNAL вместо EXTERNAL). Проверь **recycle-on-delete** — если пул не возвращает адрес на Delete, это product-баг.

## Параллельный newman — слоёная parallel-safety (выведено из e2e-newman стабилизации 2026-07, serial 90мин→parallel ~35мин)

`newman-parallel.sh` fan-out суит требует НЕ одного фикса, а **пирога** — каждый слой обнажает следующий. При «довести
параллельный e2e до зелёного» проверяй ВСЕ (не сдавайся на «ещё 1 суита» — хвост движется, но конечен):

1. **Throughput материализации grant** — owner-tuple создателя должен материализоваться быстро под N× нагрузкой. Форвард
   fast-path (`ReconcileObjectForward`, additive per-object, **SHARE**-advisory-lock не EXCLUSIVE → concurrent creates
   сосуществуют). Full `ReconcileObject` (EXCLUSIVE-lock) сериализует — под параллелью дрейнит. См. `data-integrity.md`.
2. **Create vs update дискриминатор** — `RegisterResource` зовётся и на **label-UPDATE** (не только create). Additive-forward
   (никогда не delete) роняет revoke при удалении label → grant persists. Fast-path обязан: нет existing-members ⇒ create→forward;
   есть ⇒ update→full (delete-stale). Иначе revoke не залипает (`post-revoke {allowed:true}`).
3. **Волновая изоляция iam** — iam-СОБСТВЕННАЯ authz-материализация (AccessBinding CRUD, label-revoke) идёт full-path
   EXCLUSIVE-lock; под конкурентной leaf-нагрузкой (vpc/compute/nlb регистрируют ресурсы) дрейнит (get-confirms 404,
   revoke-not-sticking). Гони iam **отдельной волной** (`PHASE2_SERVICES=iam` в newman-parallel.sh) — без конкурирующей нагрузки.
4. **Полная fixture-изоляция** (серийно скрыта, параллельно рвётся): (a) **shared no-binding subject** — grant-суиты его
   реально грантят → течёт в see-nothing leak-guard'ы через account→project containment → выделенный **never-granted**
   `jwtPureNoBindings`; (b) **AddressPool default-per-(zone,kind)** — zone-collapse (3 geo-зоны, zoneC≡zoneD) + cross-service
   shared CIDR EXCLUDE → disjoint CIDR-блоки + serial-tail contended-коллекций (`serial-collections.txt`); (c) **account-member
   visibility floor** — `ProjectService.List` возвращает ВСЕ проекты аккаунта члену → бьёт by-label narrowing → fresh per-run
   private account для exact-visibility кейсов.
5. **Shared-resource CIDR/name collision маскируется под EC-флейк** — «блуждающий» флейк (1-2 РАЗНЫЕ суиты/прогон) часто НЕ
   eventual-consistency, а **детерминированная коллизия**: subnet-CIDR `10.{hash(runId)%N}.{seq}.0/24` — общий runId → тот же
   октет для всех коллекций, `seq` рестартит с 1 в каждом newman-процессе → параллельные процессы коллизят; какой hash попадёт
   на насыщенную band — дрейфует по прогонам → «блуждание». Фикс: широкая run-random энтропия ОБОИХ октетов (~56k /24), НЕ
   retry-обёртки. При «блуждающем» флейке — **проверь shared-resource collision (CIDR/pool/name) ПЕРЕД тем как винить EC**.
6. **Idempotency/phantom под параллелью**: ALREADY_EXISTS (prior grant не отревокан — best-effort teardown принял transient
   403 → binding остался ACTIVE → strict-create UNIQUE-slot занят) → preclean-revoke обязан **ретраить DELETE на 403** до успеха,
   не fire-forget. «not found» под нагрузкой — phantom-id ([[op.error перед metadata]] выше) ИЛИ peer-RYW → `retry_create_until_present`
   message-discriminated (retry на 400/404+`/not found/`; валидационные 400 «cover all zones»/«overlap» проходят сквозь).
7. **Ordering-tolerance негативов**: peer-first-vs-authz-first — `move.go` зовёт `ProjectService.Get(dst)` ДО authz → недоступный
   dst → hide-existence 400 «not found» до scope-Check. STRICT-403-негатив неверен → tolerant `400/403/404, never 200`; реальный
   scope-deny всё равно pinned отдельным precond'ом (не маскировка).

**Мета**: массовая параллелизация большого e2e (65+ коллекций) — инженерная задача пирога throughput+isolation+idempotency,
а не «добавить retry». Retry-обёртки — для истинного read-your-own-writes EC-окна; НЕ лечат collision/phantom/idempotency
(там — fixture-изоляция/энтропия/preclean-retry). Прод-фиксы (форвард/lock/delete-stale) — TDD+db-review; тест-фиксы не маскируют.
