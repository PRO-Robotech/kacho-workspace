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
