# Sub-phase 0.2 (Resource Manager + Watch infrastructure) — Acceptance

**Документ:** acceptance / sub-phase 0.2
**Дата:** 2026-05-03
**Статус:** Draft, на ревью
**Источник требований:** `04-roadmap-and-phasing.md` §3 «Sub-итерация 0.2», `01-architecture-and-services.md` §2.2, §3, §4; `02-data-model-and-conventions.md` §1–2, §6–10, §14; `00-overview-and-scope.md` §4.
**Утверждение:** approve выставляет агент `acceptance-reviewer` (заказчик не подключается — он проверяет финальный smoke на шаге 7, см. `04-roadmap-and-phasing.md` §2).

---

## 0. Цель sub-итерации (1 абзац)

Sub-итерация 0.2 реализует первый работающий бизнес-сервис платформы Kachō — `kacho-resource-manager` (иерархия Organization → Cloud → Folder) — вместе с инфраструктурной плитой, которую все последующие сервисы унаследуют: in-process Watch Hub с Postgres Outbox, парсером селекторов, общими миграциями (`resource_events` + `resource_version_seq`). После завершения итерации разработчик может напрямую (через port-forward или cluster-internal DNS) дёргать `OrganizationService/List`, `Upsert`, `Delete`, `Watch` и наблюдать события `ADDED` / `MODIFIED` / `DELETED` в gRPC-стриме; default-иерархия (Organization `default` → Cloud `default` → Folder `default`) создаётся автоматически при первом старте. API Gateway (sub-phase 0.6) **не существует** в данной итерации: все сценарии используют `kubectl port-forward` или cluster-internal адрес `resource-manager.kacho.svc.cluster.local:9090`.

**Что НЕ входит в 0.2** (явно отложено):
- `kacho-api-gateway` и REST-мux — sub-phase 0.6.
- VPC, Compute, LoadBalancer-сервисы — sub-phase 0.3–0.5.
- Cross-service gRPC-вызовы `Internal.FolderExists` из других сервисов — появятся в 0.3+; в 0.2 только декларируются методы `ResourceManagerInternal.OrganizationExists`, `.CloudExists`, `.FolderExists` (реализуются, но проверяются тестами в рамках unit/integration, не через другие сервисы).
- AAA (auth, authorization, audit) — отдельная фаза.
- `kacho-corelib/audit/` — только заглушка.
- Пагинация глубже 1000 — зарезервирована архитектурно, но не тестируется в 0.2.
- Finalizers на Organization/Cloud/Folder — у этих ресурсов нет lifecycle и нет finalizers; они удаляются мгновенно при Delete с пустым `finalizers[]` (который всегда пуст — поле не поддерживается для Org/Cloud/Folder согласно `02-data-model-and-conventions.md` §2.1).
- Helm umbrella chart интеграция через `make dev-up` — resource-manager добавляется в helm umbrella, но e2e smoke через port-forward, не через api-gateway/ingress.
- Проверка cluster-internal DNS (`resource-manager.kacho.svc.cluster.local:9090`) из другого Pod-а — отложена до sub-phase 0.6 (api-gateway). Все e2e-сценарии §9 используют исключительно `kubectl port-forward`.

**Зафиксированные соглашения (resolved при ревью):**
- `ALREADY_EXISTS` в данном сервисе **не используется**: upsert-семантика (`name + scope` → create-or-update) всегда выполняет INSERT OR UPDATE. Этот код ошибки зарезервирован для будущих фаз, где может появиться раздельный Create/Update. Сценарий G6 удалён.
- `Organization.spec`, `Cloud.spec`, `Folder.spec` содержат два опциональных поля: `display_name string` и `description string`. Они не несут бизнес-логики — только UI-friendly отображение.
- **Имена integration-тест-функций** следуют паттерну `Test<Resource>_<ScenarioID>_<ShortDesc>` (например, `TestOrganization_D2_NoDiffUpsertNoOp`). E2e bash-скрипты — `kacho-deploy/e2e/0.2/<ID>-<short-desc>.sh`.

---

## 1. Группа A — Watch infrastructure (kacho-corelib/watch + outbox)

Сценарии группы A покрывают пакеты `kacho-corelib/watch/` и `kacho-corelib/outbox/`. Тесты — integration-уровня через testcontainers-Postgres. Референс: `02-data-model-and-conventions.md` §8.

### A1. Транзакционная атомарность outbox + resource

**ID:** 0.2-A1

**Given** Postgres запущен (testcontainers)
**And** миграции `resource_events` и `resource_version_seq` применены (`kacho-corelib/migrations/common/`)
**And** существует таблица `organizations` с колонкой `resource_version BIGINT`
**And** инициализирован `corelib/db.Transactor`

**When** вызывается `outbox.WriteWithResource(ctx, tx, OutboxEntry{EventType: "ADDED", ResourceKind: "Organization", ResourceUID: uid, Data: encodedProto})` внутри транзакции, которая также вставляет запись в `organizations`
**And** транзакция успешно коммитится

**Then** в `organizations` присутствует ровно одна запись с `uid`
**And** в `resource_events` присутствует ровно одна запись с `event_type = 'ADDED'`, `resource_kind = 'Organization'`, `resource_uid = uid`
**And** `resource_version` в записи `organizations` совпадает с `resource_version` в `resource_events`
**And** `resource_version` > 0 (sequence выдал значение)

### A2. Атомарный откат: при rollback транзакции ни ресурс, ни outbox-событие не сохраняются

**ID:** 0.2-A2

**Given** те же предусловия что в A1

**When** вызывается `outbox.WriteWithResource(...)` внутри транзакции
**And** транзакция откатывается (`tx.Rollback(ctx)`)

**Then** в `organizations` записей с указанным `uid` нет
**And** в `resource_events` записей с указанным `resource_uid` нет
**And** `SELECT nextval('resource_version_seq')` выдаёт значение > использованного в откатившейся транзакции (sequence не откатывается, gaps допустимы)

### A3. pg_notify отправляется после commit

**ID:** 0.2-A3

**Given** Postgres запущен (testcontainers)
**And** Go-горутина слушает `LISTEN kacho_resource_manager` через отдельное соединение pgx
**And** инициализирован `outbox.Writer` для канала `kacho_resource_manager`

**When** транзакция с `outbox.WriteWithResource(...)` успешно коммитится

**Then** слушающая горутина получает уведомление на канале `kacho_resource_manager` в течение 500 мс
**And** payload уведомления — пустая строка (`''` — только wake-up, без данных, согласно `02-data-model-and-conventions.md` §8.2)

### A4. Watch Hub стартует и читает события после NOTIFY

**ID:** 0.2-A4

**Given** Postgres запущен (testcontainers) с применёнными миграциями
**And** создан `watch.Hub` для сервиса `resource-manager` (канал LISTEN `kacho_resource_manager`)
**And** Hub запущен (горутина активна, `cursorRV = 0`)
**And** два subscriber-а зарегистрированы в Hub с фильтром `resource_kind = 'Organization'`

**When** в одной транзакции вставляется запись в `organizations` и соответствующая запись в `resource_events` (event_type=ADDED, resource_kind='Organization')
**And** транзакция коммитится, отправляя `pg_notify('kacho_resource_manager', '')`

**Then** Hub просыпается (от NOTIFY либо по ticker 100 мс)
**And** Hub читает новое событие из `resource_events WHERE resource_version > cursorRV`
**And** Hub добавляет событие в ring buffer
**And** оба subscriber-а получают событие в свои каналы в течение 200 мс
**And** `cursorRV` Hub обновляется до `resource_version` нового события

### A5. Ring buffer catch-up для отстающего клиента (в пределах буфера)

**ID:** 0.2-A5

**Given** Postgres запущен (testcontainers)
**And** Watch Hub запущен с ring buffer размером 1024 события
**And** В outbox уже записано N событий (N ≤ 512) начиная с `resource_version = 1`
**And** Hub уже прочитал все N событий (cursorRV = N)

**When** новый Watch-клиент подключается с `resourceVersion = 0` (хочет все события с начала)

**Then** Hub определяет, что `resourceVersion = 0 >= cursorRV - 1024` (в пределах ring)
**And** клиент получает N событий из ring buffer в порядке возрастания `resource_version`
**And** после catch-up клиент подключается к live-stream и получает новые события

### A6. Outbox catch-up для сильно отстающего клиента (вне ring buffer)

**ID:** 0.2-A6

**Given** Postgres запущен (testcontainers)
**And** Watch Hub запущен
**And** В outbox записано 2000 событий (больше ring buffer 1024)
**And** Hub прочитал все 2000 (cursorRV = 2000)
**And** outbox-retention не истёк (все события `created_at > now() - 1 hour`)

**When** новый Watch-клиент подключается с `resourceVersion = 500` (вне ring: `500 < cursorRV - 1024 = 976`)

**Then** Hub определяет, что клиент вне ring buffer
**And** сервер выполняет запрос `SELECT * FROM resource_events WHERE resource_version > 500 ORDER BY resource_version ASC LIMIT 10000`
**And** клиент получает события 501..2000 из outbox в порядке возрастания
**And** после catch-up клиент подключается к live-stream

### A7. Gone 410 при устаревшем resourceVersion (за пределами retention)

**ID:** 0.2-A7

**Given** Postgres запущен (testcontainers)
**And** Watch Hub запущен
**And** В `resource_events` минимальная `resource_version` = 5000 (старые события удалены cleanup)
**And** Retention-cleanup уже выполнился (`DELETE FROM resource_events WHERE created_at < now() - interval '1 hour'`)

**When** Watch-клиент подключается с `resourceVersion = 100` (< минимального в outbox = 5000)

**Then** сервер возвращает gRPC ошибку со статусом `OUT_OF_RANGE` с message `"Gone: resourceVersion too old, please relist"`
**And** `details[]` содержит `ErrorInfo` с `reason = "RESOURCE_VERSION_EXPIRED"` и `domain = "kacho.cloud"`
**And** `details[]` содержит `RequestInfo` с непустым `request_id`
**And** клиент должен выполнить `List` для получения текущего `resourceVersion` и начать новый Watch от него

### A8. Hub ticker fallback при отсутствии NOTIFY

**ID:** 0.2-A8

**Given** Postgres запущен (testcontainers)
**And** Watch Hub запущен с ticker fallback 100 мс
**And** pg_notify не отправляется (имитируем: вставка в `resource_events` без notify)
**And** subscriber зарегистрирован

**When** запись вставлена в `resource_events` без вызова `pg_notify`

**Then** Hub читает новое событие из outbox через ticker (в течение 150 мс)
**And** subscriber получает событие
**And** Hub продолжает работу в штатном режиме

---

## 2. Группа B — Selector parser (kacho-corelib/selector)

Сценарии группы B покрывают пакет `kacho-corelib/selector/`. Тесты — unit-уровня (чистая логика) + integration через testcontainers для проверки SQL-WHERE. Референс: `02-data-model-and-conventions.md` §7.

### B1. FieldSelector по name — точное совпадение

**ID:** 0.2-B1

**Given** инициализирован `selector.Builder` для таблицы `organizations`

**When** вызывается `Build([]Selector{{FieldSelector: &FieldSelector{Name: "default"}}})` 

**Then** возвращается SQL-фрагмент `WHERE (name = $1)` с параметром `["default"]`
**And** SQL параметризован (без конкатенации строк)

### B2. FieldSelector по organizationId

**ID:** 0.2-B2

**Given** инициализирован `selector.Builder` для таблицы `clouds`

**When** вызывается `Build([]Selector{{FieldSelector: &FieldSelector{OrganizationId: "org-uid-abc"}}})` 

**Then** возвращается SQL-фрагмент `WHERE (organization_id = $1)` с параметром `["org-uid-abc"]`

### B3. FieldSelector комбинация — name AND folderId (AND внутри одного Selector)

**ID:** 0.2-B3

**Given** инициализирован `selector.Builder` для таблицы `folders`

**When** вызывается `Build([]Selector{{FieldSelector: &FieldSelector{Name: "dev", CloudId: "cloud-uid-xyz"}}})` 

**Then** возвращается SQL-фрагмент `WHERE (name = $1 AND cloud_id = $2)` с параметрами `["dev", "cloud-uid-xyz"]`
**And** порядок параметров стабилен между вызовами

### B4. LabelSelector — фильтр по одной метке

**ID:** 0.2-B4

**Given** инициализирован `selector.Builder` для таблицы `organizations`

**When** вызывается `Build([]Selector{{LabelSelector: map[string]string{"env": "production"}}})` 

**Then** возвращается SQL-фрагмент `WHERE (labels @> $1::jsonb)` с параметром `{"env":"production"}`
**And** используется GIN-индекс совместимый оператор `@>` (jsonb containment)

### B5. LabelSelector — фильтр по нескольким меткам (AND внутри Selector)

**ID:** 0.2-B5

**Given** инициализирован `selector.Builder`

**When** вызывается `Build([]Selector{{LabelSelector: map[string]string{"env": "production", "team": "platform"}}})` 

**Then** возвращается SQL-фрагмент `WHERE (labels @> $1::jsonb)` с параметром `{"env":"production","team":"platform"}`
**And** совпадение требует наличия обоих ключей (containment semantics)

### B6. FieldSelector AND LabelSelector в одном Selector

**ID:** 0.2-B6

**Given** инициализирован `selector.Builder`

**When** вызывается `Build([]Selector{{FieldSelector: &FieldSelector{Name: "prod-folder"}, LabelSelector: map[string]string{"tier": "premium"}}})` 

**Then** возвращается SQL-фрагмент `WHERE (name = $1 AND labels @> $2::jsonb)` с параметрами `["prod-folder", {"tier":"premium"}]`

### B7. Несколько Selector-ов — OR между ними

**ID:** 0.2-B7

**Given** инициализирован `selector.Builder`

**When** вызывается `Build([]Selector{ {FieldSelector: &FieldSelector{Name: "alpha"}}, {FieldSelector: &FieldSelector{Name: "beta"}} })` 

**Then** возвращается SQL-фрагмент `WHERE ((name = $1) OR (name = $2))` с параметрами `["alpha", "beta"]`
**And** скобки расставлены корректно (без амбигуозного приоритета)

### B8. Пустой список Selector-ов — выборка без фильтра

**ID:** 0.2-B8

**Given** инициализирован `selector.Builder`

**When** вызывается `Build([]Selector{})` (пустой список)

**Then** возвращается пустой SQL-WHERE-фрагмент (нет `WHERE` clause)
**And** функция не возвращает ошибку

### B9. Инъекция через selector — параметризация защищает

**ID:** 0.2-B9

**Given** инициализирован `selector.Builder`

**When** вызывается `Build([]Selector{{FieldSelector: &FieldSelector{Name: "'; DROP TABLE organizations; --"}}})` 

**Then** SQL-фрагмент содержит только параметр-placeholder `$1`, значение не конкатенировано в строку
**And** реальный запрос выполняется корректно (записи с таким именем просто не найдены)

### B10. Integration: selector + SQL работает против реальной БД

**ID:** 0.2-B10

**Given** Postgres запущен (testcontainers) с таблицей `organizations`
**And** в таблице 3 записи: name=`"alpha"` (labels={"env":"dev"}), name=`"beta"` (labels={"env":"prod"}), name=`"gamma"` (labels={"env":"prod","tier":"premium"})

**When** выполняется запрос с `selector.Build([]Selector{ {LabelSelector: map[string]string{"env":"prod"}} })`

**Then** запрос возвращает ровно 2 записи: `"beta"` и `"gamma"`
**And** `"alpha"` не возвращается

---

## 3. Группа C — Common migrations (kacho-corelib/migrations/common)

Сценарии группы C покрывают пакет `kacho-corelib/migrations/common/`. Тесты — integration через testcontainers. Референс: `02-data-model-and-conventions.md` §8, §12.

### C1. Миграция создаёт resource_version_seq

**ID:** 0.2-C1

**Given** Postgres запущен (testcontainers) с пустой схемой

**When** применяется миграция `0001_common_resource_events.sql` из `kacho-corelib/migrations/common/`

**Then** существует sequence `resource_version_seq`
**And** `SELECT nextval('resource_version_seq')` возвращает 1
**And** повторный вызов возвращает 2 (монотонно возрастает)

### C2. Миграция создаёт resource_events с правильной схемой

**ID:** 0.2-C2

**Given** Postgres запущен (testcontainers) с применёнными миграциями из C1

**When** разработчик проверяет схему таблицы `resource_events`

**Then** таблица содержит колонки согласно `02-data-model-and-conventions.md` §8.2:
- `resource_version BIGINT PRIMARY KEY DEFAULT nextval('resource_version_seq')`
- `event_type TEXT NOT NULL CHECK (event_type IN ('ADDED', 'MODIFIED', 'DELETED'))`
- `resource_kind TEXT NOT NULL`
- `resource_uid UUID NOT NULL`
- `data BYTEA` (nullable — для DELETED-tombstone)
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`
**And** существует индекс `resource_events_kind_rv_idx` ON `(resource_kind, resource_version)`
**And** существует индекс `resource_events_cleanup_idx` ON `(created_at)`

### C3. CHECK constraint отклоняет невалидный event_type

**ID:** 0.2-C3

**Given** Postgres запущен (testcontainers) с применёнными миграциями

**When** выполняется `INSERT INTO resource_events (event_type, resource_kind, resource_uid) VALUES ('UNKNOWN', 'Organization', gen_random_uuid())`

**Then** Postgres возвращает ошибку `CHECK constraint violation`
**And** таблица остаётся пустой

### C4. Cleanup-функция удаляет события старше 1 часа

**ID:** 0.2-C4

**Given** Postgres запущен (testcontainers)
**And** В `resource_events` есть 5 записей: 3 с `created_at = now() - interval '2 hours'` (старые), 2 с `created_at = now() - interval '30 minutes'` (свежие)

**When** выполняется cleanup-функция из `kacho-corelib/migrations/common/` (эквивалент `DELETE FROM resource_events WHERE created_at < now() - interval '1 hour'`)

**Then** в таблице остаётся ровно 2 записи (свежие)
**And** 3 старые записи удалены

### C5. Cleanup использует advisory lock для координации реплик

**ID:** 0.2-C5

**Given** Postgres запущен (testcontainers)
**And** Две горутины одновременно пытаются выполнить cleanup
**And** Cleanup использует `pg_advisory_xact_lock(hashtext('kacho_resource_manager_cleanup'))`

**When** обе горутины стартуют одновременно

**Then** только одна горутина выполняет cleanup в каждый момент времени (вторая ждёт или пропускает, если используется `pg_try_advisory_xact_lock`)
**And** данные не повреждаются (нет double-delete ошибок, нет deadlock)

### C6. Миграция идемпотентна при повторном применении (goose up/down/up)

**ID:** 0.2-C6

**Given** Postgres запущен (testcontainers)

**When** goose-миграция применяется, откатывается (`goose down`), затем применяется снова (`goose up`)

**Then** итоговая схема идентична результату первого применения
**And** `goose up` завершается с кодом 0 при повторном вызове на уже применённой миграции (no-op)

---

## 4. Группа D — Resource Manager domain (Organization / Cloud / Folder)

Сценарии группы D покрывают proto `kacho.cloud.resourcemanager.v1` и сервис `kacho-resource-manager`. Тесты — integration через testcontainers (gRPC handler + service + repo + outbox в одном тесте). Референс: `01-architecture-and-services.md` §2.2, §3; `02-data-model-and-conventions.md` §2, §6, §9.

### D1. Upsert: создание новой Organization

**ID:** 0.2-D1

**Given** Postgres запущен с миграциями `kacho_resource_manager`
**And** сервис `OrganizationService` инициализирован
**And** Organization с именем `"my-org"` не существует

**When** клиент вызывает `kacho.cloud.resourcemanager.v1.OrganizationService/Upsert` с payload:
- `organizations[0].metadata.name = "my-org"`
- `organizations[0].metadata.labels = {"owner": "team-platform"}`
- `organizations[0].spec = {}` (пустой spec)

**Then** ответ содержит `organizations[0]` с заполненными:
- `metadata.uid` — непустой UUID v4
- `metadata.name = "my-org"`
- `metadata.creationTimestamp` — не нулевое время
- `metadata.resourceVersion` — непустая строка, содержит десятичное число > 0
- `metadata.labels = {"owner": "team-platform"}`
- `metadata.deletionTimestamp` — не задан (null/absent)
**And** в базе `kacho_resource_manager.organizations` присутствует запись с `name = 'my-org'`
**And** в `resource_events` есть событие `event_type = 'ADDED'`, `resource_kind = 'Organization'`, `resource_uid = <uid из ответа>`
**And** HTTP/gRPC статус = OK

### D2. Upsert: обновление существующей Organization (idempotent)

**ID:** 0.2-D2

**Given** Organization `"my-org"` создана (D1), её `metadata.uid = <uid>` и `metadata.resourceVersion = "1"`

**When** клиент вызывает `OrganizationService/Upsert` с тем же payload (те же `name`, `labels`)

**Then** ответ содержит тот же `metadata.uid = <uid>`
**And** `metadata.creationTimestamp` не изменился
**And** `metadata.resourceVersion` **не изменился** (no-op: нет diff в spec/labels → новая версия не выдаётся, событие MODIFIED не эмитируется — соответствует Kubernetes-семантике и снижает шум в Watch)
**And** в `resource_events` новых событий для данного `uid` не появилось
**And** в БД ровно одна запись с `name = 'my-org'` (не дублируется)

### D3. Upsert: изменение labels Organization генерирует MODIFIED событие

**ID:** 0.2-D3

**Given** Organization `"my-org"` создана с `labels = {"owner": "team-platform"}`

**When** клиент вызывает `OrganizationService/Upsert` с:
- `organizations[0].metadata.name = "my-org"`
- `organizations[0].metadata.labels = {"owner": "team-platform", "env": "prod"}`

**Then** ответ содержит `metadata.labels = {"owner": "team-platform", "env": "prod"}`
**And** `metadata.resourceVersion` больше предыдущего значения
**And** в `resource_events` появляется событие `event_type = 'MODIFIED'`, `resource_kind = 'Organization'`

### D4. Delete: удаление Organization (без finalizers — мгновенное)

**ID:** 0.2-D4

**Given** Organization `"my-org"` создана, её `metadata.uid = <uid>`
**And** `metadata.finalizers[] = []` (пусто — у Organization нет finalizers)

**When** клиент вызывает `OrganizationService/Delete` с:
- `organizations[0].metadata.uid = <uid>`

**Then** ответ — OK
**And** запись `organizations` с `uid = <uid>` физически удалена из БД
**And** в `resource_events` появляется событие `event_type = 'DELETED'`, `resource_uid = <uid>`
**And** повторный `Delete` с тем же uid возвращает `NOT_FOUND`

### D5. List Organizations: возвращает все организации без фильтра

**ID:** 0.2-D5

**Given** Существуют 3 Organization: `"alpha"`, `"beta"`, `"gamma"`

**When** клиент вызывает `OrganizationService/List` с пустым `selectors[]`

**Then** ответ содержит все 3 Organization в массиве `organizations[]`
**And** ответ содержит `resourceVersion` (snapshot-version) — десятичная строка, соответствующая максимальному `resource_version` среди возвращённых записей или текущей позиции sequence
**And** HTTP/gRPC статус = OK

### D6. List Organizations: фильтр по name

**ID:** 0.2-D6

**Given** Существуют 3 Organization: `"alpha"`, `"beta"`, `"gamma"`

**When** клиент вызывает `OrganizationService/List` с:
- `selectors[0].field_selector.name = "alpha"`

**Then** ответ содержит ровно 1 Organization с `metadata.name = "alpha"`
**And** `"beta"` и `"gamma"` не включены в ответ

### D7. List Organizations: фильтр по labels (LabelSelector)

**ID:** 0.2-D7

**Given** Существуют 3 Organization:
- `"alpha"` с `labels = {"env": "dev"}`
- `"beta"` с `labels = {"env": "prod"}`
- `"gamma"` с `labels = {"env": "prod", "tier": "premium"}`

**When** клиент вызывает `OrganizationService/List` с:
- `selectors[0].label_selector = {"env": "prod"}`

**Then** ответ содержит ровно 2 Organization: `"beta"` и `"gamma"`
**And** `"alpha"` не включена

### D8. Upsert: создание Cloud в Organization

**ID:** 0.2-D8

**Given** Organization `"default"` существует с `uid = <org-uid>`

**When** клиент вызывает `kacho.cloud.resourcemanager.v1.CloudService/Upsert` с:
- `clouds[0].metadata.name = "my-cloud"`
- `clouds[0].metadata.organizationId = <org-uid>`
- `clouds[0].metadata.labels = {"region": "kacho-region-a"}`

**Then** ответ содержит `clouds[0].metadata.uid` — непустой UUID
**And** `clouds[0].metadata.organizationId = <org-uid>`
**And** `clouds[0].metadata.creationTimestamp` заполнен
**And** `clouds[0].metadata.resourceVersion` — непустая строка
**And** В таблице `clouds` есть запись с `organization_id = <org-uid>` и `name = 'my-cloud'`
**And** В `resource_events` событие `event_type = 'ADDED'`, `resource_kind = 'Cloud'`

### D9. Upsert: создание Folder в Cloud

**ID:** 0.2-D9

**Given** Organization `"default"` с `uid = <org-uid>` существует
**And** Cloud `"default"` с `uid = <cloud-uid>` в этой Organization существует

**When** клиент вызывает `kacho.cloud.resourcemanager.v1.FolderService/Upsert` с:
- `folders[0].metadata.name = "my-folder"`
- `folders[0].metadata.cloudId = <cloud-uid>`
- `folders[0].metadata.organizationId = <org-uid>`

**Then** ответ содержит `folders[0].metadata.uid` — непустой UUID
**And** `folders[0].metadata.cloudId = <cloud-uid>`
**And** `folders[0].metadata.organizationId = <org-uid>`
**And** В таблице `folders` есть запись с `cloud_id = <cloud-uid>`
**And** В `resource_events` событие `event_type = 'ADDED'`, `resource_kind = 'Folder'`

### D10. List Folders: фильтр по cloudId

**ID:** 0.2-D10

**Given** Cloud `"cloud-a"` с `uid = <cloud-a>` и Cloud `"cloud-b"` с `uid = <cloud-b>` существуют
**And** Folder `"folder-1"` в `<cloud-a>`, Folder `"folder-2"` в `<cloud-a>`, Folder `"folder-3"` в `<cloud-b>`

**When** клиент вызывает `FolderService/List` с:
- `selectors[0].field_selector.cloud_id = <cloud-a>`

**Then** ответ содержит ровно 2 Folder: `"folder-1"` и `"folder-2"`
**And** `"folder-3"` не включена

### D11. Delete Cloud каскадно проверяет наличие Folder — FAILED_PRECONDITION

**ID:** 0.2-D11

**Given** Cloud `"my-cloud"` с `uid = <cloud-uid>` существует
**And** В этом Cloud существует Folder `"my-folder"`

**When** клиент вызывает `CloudService/Delete` с:
- `clouds[0].metadata.uid = <cloud-uid>`

**Then** gRPC статус = `FAILED_PRECONDITION`
**And** `details[]` содержит `PreconditionFailure` с `violations[0].type = "HAS_DEPENDENT_RESOURCES"` и `violations[0].subject = <cloud-uid>`
**And** `violations[0].description` указывает на наличие зависимых Folder
**And** Cloud НЕ удалён из БД

*Реализация:* FK `RESTRICT` на уровне БД (`folders.cloud_id → clouds.uid ON DELETE RESTRICT`). Сервис перехватывает `pgcode.ForeignKeyViolation` (pgx) и конвертирует в `FAILED_PRECONDITION` с заполненным `PreconditionFailure`. Это предпочтительнее explicit SELECT-before-delete для консистентности при concurrent delete.

### D12. Upsert идентификация по name + scope (без uid)

**ID:** 0.2-D12

**Given** Folder `"prod"` в Cloud `<cloud-uid>` НЕ существует

**When** клиент вызывает `FolderService/Upsert` с:
- `folders[0].metadata.name = "prod"`
- `folders[0].metadata.cloudId = <cloud-uid>`
- (без `metadata.uid`)

**Then** сервер создаёт новую Folder, присваивает `metadata.uid`
**And** ответ содержит `metadata.uid` (новый UUID)
**And** повторный вызов с теми же `name + cloudId` обновляет ту же запись (upsert-семантика)

### D13. Delete по name + scope (без uid)

**ID:** 0.2-D13

**Given** Organization `"legacy-org"` существует

**When** клиент вызывает `OrganizationService/Delete` с:
- `organizations[0].metadata.name = "legacy-org"`
- (без `metadata.uid`)

**Then** gRPC статус = OK
**And** Organization физически удалена
**And** В `resource_events` событие `event_type = 'DELETED'`

### D14. Delete Organization с дочерними Cloud — FAILED_PRECONDITION

**ID:** 0.2-D14

**Given** Organization `"parent-org"` с `uid = <org-uid>` существует
**And** В этой Organization существует Cloud `"child-cloud"` с `organization_id = <org-uid>`

**When** клиент вызывает `OrganizationService/Delete` с:
- `organizations[0].metadata.uid = <org-uid>`

**Then** gRPC статус = `FAILED_PRECONDITION`
**And** `details[]` содержит `PreconditionFailure` с:
  - `violations[0].type = "HAS_DEPENDENT_RESOURCES"`
  - `violations[0].subject = <org-uid>`
  - `violations[0].description` содержит указание на наличие дочерних Cloud
**And** Organization НЕ удалена из БД

*Реализация:* FK `RESTRICT` на уровне БД (`clouds.organization_id → organizations.uid ON DELETE RESTRICT`). Сервис перехватывает `pgcode.ForeignKeyViolation` и конвертирует в `FAILED_PRECONDITION` с заполненным `PreconditionFailure`. Симметрично D11.

---

## 5. Группа E — Watch stream (Organization / Cloud / Folder)

Сценарии группы E покрывают Watch RPC для каждого типа ресурса. Тесты — integration через testcontainers. Референс: `01-architecture-and-services.md` §4; `02-data-model-and-conventions.md` §8; `06-api §6.1`.

### E1. Watch: получение ADDED события при Upsert (create) Organization

**ID:** 0.2-E1

**Given** Postgres запущен с миграциями
**And** Watch Hub запущен

**When** клиент открывает Watch стрим `OrganizationService/Watch` с:
- `resourceVersion = <текущий snapshot>`
- `selectors[]` — пустые (все Organization)
**And** (одновременно) другой клиент вызывает `OrganizationService/Upsert` для создания Organization `"new-org"`

**Then** Watch стрим получает событие `WatchEvent` в течение 500 мс:
- `type = ADDED`
- `organization.metadata.name = "new-org"`
- `organization.metadata.uid` — непустой UUID
- `organization.metadata.resourceVersion` — непустая строка

### E2. Watch: получение MODIFIED события при изменении labels

**ID:** 0.2-E2

**Given** Organization `"my-org"` существует с `labels = {"env": "dev"}`
**And** Watch стрим открыт с `resourceVersion = <текущий>`

**When** клиент вызывает `OrganizationService/Upsert` с `"my-org"` и новыми `labels = {"env": "prod"}`

**Then** Watch стрим получает `WatchEvent`:
- `type = MODIFIED`
- `organization.metadata.name = "my-org"`
- `organization.metadata.labels = {"env": "prod"}`
- `organization.metadata.resourceVersion` > предыдущего значения

### E3. Watch: получение DELETED события при Delete

**ID:** 0.2-E3

**Given** Organization `"to-delete"` существует
**And** Watch стрим открыт

**When** клиент вызывает `OrganizationService/Delete` для `"to-delete"`

**Then** Watch стрим получает `WatchEvent`:
- `type = DELETED`
- `organization.metadata.uid` = uid удалённой Organization
- `organization.metadata.name = "to-delete"`

### E4. Watch: фильтрация по name — клиент видит только свои ресурсы

**ID:** 0.2-E4

**Given** Watch стрим открыт с selector `field_selector.name = "target-org"`
**And** Существуют Organization `"target-org"` и `"other-org"`

**When** `"other-org"` обновляется (изменение labels)
**And** `"target-org"` обновляется (изменение labels)

**Then** Watch стрим получает только одно событие (для `"target-org"`)
**And** событие для `"other-org"` NOT поступает в этот стрим

### E5. Watch для Cloud: ADDED/MODIFIED/DELETED

**ID:** 0.2-E5

**Given** Watch стрим открыт `CloudService/Watch` с пустыми selectors
**And** Organization `"default"` существует с `uid = <org-uid>`

**When** (шаг 1) `CloudService/Upsert` создаёт Cloud `"production"` в Organization `<org-uid>`
**And** (шаг 2) `CloudService/Upsert` обновляет Cloud `"production"` — добавляет label `{"status": "active"}`
**And** (шаг 3) `CloudService/Delete` удаляет Cloud `"production"`

**Then** Watch стрим получает 3 события в правильном порядке:
1. `type = ADDED`, `cloud.metadata.name = "production"`
2. `type = MODIFIED`, `cloud.metadata.labels["status"] = "active"`
3. `type = DELETED`, `cloud.metadata.name = "production"`

### E6. Watch для Folder: ADDED/MODIFIED/DELETED

**ID:** 0.2-E6

**Given** Watch стрим открыт `FolderService/Watch` с selector `field_selector.cloud_id = <cloud-uid>`
**And** Cloud `<cloud-uid>` существует

**When** (шаг 1) `FolderService/Upsert` создаёт Folder `"test"` в Cloud `<cloud-uid>`
**And** (шаг 2) `FolderService/Upsert` изменяет её labels
**And** (шаг 3) `FolderService/Delete` удаляет Folder `"test"`

**Then** Watch стрим получает 3 события для `"test"` (ADDED → MODIFIED → DELETED)
**And** события для Folder в других Cloud НЕ поступают в этот стрим

### E7. Watch catch-up: клиент с resourceVersion в прошлом получает missed события

**ID:** 0.2-E7

**Given** 5 Organization создано и каждое имеет `resource_version` 1..5
**And** outbox retention не истёк

**When** клиент открывает Watch стрим с `resourceVersion = 2`

**Then** стрим сначала отправляет catch-up события 3, 4, 5 (ADDED для каждой Organization)
**And** затем стрим переходит в live-режим
**And** новые события поступают в реальном времени

### E8. Watch Gone 410 при истёкшем resourceVersion

**ID:** 0.2-E8

**Given** cleanup уже удалил события с `resource_version < 1000` из outbox
**And** минимальный `resource_version` в `resource_events = 1000`

**When** клиент открывает Watch стрим с `resourceVersion = 50`

**Then** сервер закрывает стрим с gRPC статусом `OUT_OF_RANGE` и message `"Gone: resourceVersion too old, please relist"`
**And** `details[]` содержит `ErrorInfo` с `reason = "RESOURCE_VERSION_EXPIRED"` и `domain = "kacho.cloud"`
**And** `details[]` содержит `RequestInfo` с непустым `request_id`

---

## 6. Группа F — Internal RPC (OrganizationExists / CloudExists / FolderExists)

Сценарии группы F покрывают Internal-методы сервиса `kacho-resource-manager`. В sub-phase 0.2 вызываются только из integration-тестов; реальные cross-service вызовы появятся в 0.3+. Примечание: allowlist api-gateway для блокировки Internal.* проверяется в sub-phase 0.6. Референс: `01-architecture-and-services.md` §3.2; `02-data-model-and-conventions.md` §6.2.

### F1. FolderExists: существующий Folder возвращает exists=true

**ID:** 0.2-F1

**Given** Folder `"dev"` с `uid = <folder-uid>` существует в БД

**When** вызывается `kacho.cloud.resourcemanager.v1.ResourceManagerInternal/FolderExists` с:
- `uid = <folder-uid>`

**Then** ответ: `{exists: true}`
**And** gRPC статус = OK

### F2. FolderExists: несуществующий Folder возвращает exists=false

**ID:** 0.2-F2

**Given** В БД нет Folder с `uid = "nonexistent-uuid"`

**When** вызывается `ResourceManagerInternal/FolderExists` с:
- `uid = "00000000-0000-0000-0000-000000000000"`

**Then** ответ: `{exists: false}`
**And** gRPC статус = OK (не NOT_FOUND — это Exists-метод, который всегда возвращает bool)

### F3. CloudExists: существующий Cloud

**ID:** 0.2-F3

**Given** Cloud `"prod-cloud"` с `uid = <cloud-uid>` существует

**When** вызывается `ResourceManagerInternal/CloudExists` с `uid = <cloud-uid>`

**Then** ответ: `{exists: true}`
**And** gRPC статус = OK

### F4. OrganizationExists: существующая Organization

**ID:** 0.2-F4

**Given** Organization `"default"` с `uid = <org-uid>` существует

**When** вызывается `ResourceManagerInternal/OrganizationExists` с `uid = <org-uid>`

**Then** ответ: `{exists: true}`
**And** gRPC статус = OK

### F5. FolderExists: мягко-удалённый Folder (deletionTimestamp set) — поведение

**ID:** 0.2-F5

**Given** Folder `"zombie"` с `uid = <folder-uid>` имеет `deletion_timestamp != NULL` (soft-deleted, ожидает физического удаления)

**When** вызывается `ResourceManagerInternal/FolderExists` с `uid = <folder-uid>`

**Then** ответ: `{exists: false}`
**And** gRPC статус = OK

*Обоснование:* ресурс с `deletionTimestamp != NULL` находится в процессе удаления и **не должен использоваться как `parent-ref`** в других сервисах (например, нельзя создать Compute Instance в Folder, которая уже помечена к удалению). Поэтому `Exists` возвращает `false` для мягко-удалённых ресурсов — независимо от того, есть ли у них физическая запись в БД. В `resource-manager` у Org/Cloud/Folder нет finalizers, поэтому удаление мгновенное; сценарий фиксирует семантику для будущих фаз (0.3–0.5), где finalizers присутствуют.

---

## 7. Группа G — Negative scenarios

Сценарии группы G покрывают обработку ошибочных входных данных. Коды ошибок согласно `02-data-model-and-conventions.md` §14.

### G1a. Upsert с клиентски заданным metadata.uid — сервер игнорирует или возвращает INVALID_ARGUMENT

**ID:** 0.2-G1a

**Given** Сервис `OrganizationService` запущен
**And** Organization с именем `"new-org"` не существует

**When** клиент вызывает `OrganizationService/Upsert` с payload:
- `organizations[0].metadata.name = "new-org"`
- `organizations[0].metadata.uid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"` (клиент явно задаёт uid)

**Then** (вариант A) `metadata.uid` в ответе **не равен** `"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"` — сервер присвоил новый UUID v4, проигнорировав клиентский uid; в БД запись создана с server-assigned uid
**Or** (вариант B) gRPC статус = `INVALID_ARGUMENT` с `details[].field_violations[0].field = "organizations[0].metadata.uid"`

*Реализация выбирает один вариант и фиксирует его в плане. Оба варианта допустимы; тест пишется под выбранный. У Organization/Cloud/Folder нет поля `status` в proto (нет lifecycle) — `metadata.uid` является единственным server-managed полем, которое клиент не должен задавать.*

### G2. Upsert с невалидным name — INVALID_ARGUMENT

**ID:** 0.2-G2

**Given** Сервис `OrganizationService` запущен

**When** клиент вызывает `OrganizationService/Upsert` с:
- `organizations[0].metadata.name = "INVALID_NAME!"` (содержит uppercase и специальные символы)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest.field_violations[0].field = "organizations[0].metadata.name"`
**And** `details[]` содержит `BadRequest.field_violations[0].description` — объяснение правила (`^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$`)

### G3. Upsert Cloud с несуществующим organizationId — NOT_FOUND

**ID:** 0.2-G3

**Given** Organization с `uid = "00000000-0000-0000-0000-000000000001"` НЕ существует

**When** клиент вызывает `CloudService/Upsert` с:
- `clouds[0].metadata.name = "orphan-cloud"`
- `clouds[0].metadata.organizationId = "00000000-0000-0000-0000-000000000001"`

**Then** gRPC статус = `NOT_FOUND`
**And** `details[]` содержит `ResourceInfo.resource_type = "Organization"`, `resource_name = "00000000-0000-0000-0000-000000000001"`

### G4. Upsert Folder с несуществующим cloudId — NOT_FOUND

**ID:** 0.2-G4

**Given** Cloud с `uid = "00000000-0000-0000-0000-000000000002"` НЕ существует

**When** клиент вызывает `FolderService/Upsert` с:
- `folders[0].metadata.name = "orphan-folder"`
- `folders[0].metadata.cloudId = "00000000-0000-0000-0000-000000000002"`

**Then** gRPC статус = `NOT_FOUND`
**And** `details[]` содержит `ResourceInfo.resource_type = "Cloud"`, `resource_name = "00000000-0000-0000-0000-000000000002"`

### G5. Delete несуществующего ресурса — NOT_FOUND

**ID:** 0.2-G5

**Given** Organization с `uid = "00000000-0000-0000-0000-000000000099"` НЕ существует

**When** клиент вызывает `OrganizationService/Delete` с:
- `organizations[0].metadata.uid = "00000000-0000-0000-0000-000000000099"`

**Then** gRPC статус = `NOT_FOUND`
**And** `details[]` содержит `ResourceInfo.resource_type = "Organization"`

*G6 удалён:* `ALREADY_EXISTS` не используется в `resource-manager` — upsert-семантика (`name + scope` → create-or-update) всегда выполняет INSERT OR UPDATE и никогда не возвращает `ALREADY_EXISTS`. Этот код зарезервирован для будущих фаз (если появится отдельный `Create` RPC без upsert-семантики).

### G7. Concurrent update — ABORTED (OCC protection)

**ID:** 0.2-G7

**Given** Organization `"shared-org"` существует с `metadata.resourceVersion = <R>`

**When** два параллельных gRPC-вызова `OrganizationService/Upsert` для одной и той же Organization отправляются одновременно, каждый с отличными `spec.display_name`:
- вызов A: `organizations[0].metadata.name = "shared-org"`, `organizations[0].spec.display_name = "Version A"`
- вызов B: `organizations[0].metadata.name = "shared-org"`, `organizations[0].spec.display_name = "Version B"`

**Then** ровно один из вызовов завершается с gRPC статусом `OK` (coммит успешен)
**And** второй вызов завершается с gRPC статусом `ABORTED` с message, указывающим на конфликт concurrent update
**And** клиент, получивший `ABORTED`, должен повторить запрос (retry-семантика согласно `02-data-model-and-conventions.md` §14)
**And** в БД ровно одна запись `"shared-org"` с `spec.display_name` победившего вызова

### G8. List с невалидным page_size — INVALID_ARGUMENT

**ID:** 0.2-G8

**Given** Сервис `OrganizationService` запущен

**When** клиент вызывает `OrganizationService/List` с:
- `page_size = 9999` (> 1000 лимита)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[].field_violations[0].field = "page_size"`
**And** `details[].field_violations[0].description` содержит максимальное значение 1000

### G9. Upsert пустого name — INVALID_ARGUMENT

**ID:** 0.2-G9

**Given** Сервис `OrganizationService` запущен

**When** клиент вызывает `OrganizationService/Upsert` с:
- `organizations[0].metadata.name = ""` (пустая строка)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[].field_violations[0].field = "organizations[0].metadata.name"`

### G10. Watch с невалидным resourceVersion — INVALID_ARGUMENT

**ID:** 0.2-G10

**Given** Сервис `OrganizationService` запущен

**When** клиент открывает Watch стрим с:
- `resourceVersion = "not-a-number"` (не десятичное число)

**Then** сервер немедленно возвращает ошибку `INVALID_ARGUMENT`
**And** `details[].field_violations[0].field = "resource_version"`

### G11. Upsert Cloud с пустым organizationId — INVALID_ARGUMENT

**ID:** 0.2-G11

**Given** Сервис `CloudService` запущен

**When** клиент вызывает `CloudService/Upsert` с payload:
- `clouds[0].metadata.name = "orphan-cloud"`
- `clouds[0].metadata.organizationId = ""` (пустая строка)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest` с:
  - `field_violations[0].field = "clouds[0].metadata.organizationId"`
  - `field_violations[0].description` указывает, что поле обязательно

### G12. Upsert Folder с пустым cloudId — INVALID_ARGUMENT

**ID:** 0.2-G12

**Given** Сервис `FolderService` запущен

**When** клиент вызывает `FolderService/Upsert` с payload:
- `folders[0].metadata.name = "orphan-folder"`
- `folders[0].metadata.cloudId = ""` (пустая строка)

**Then** gRPC статус = `INVALID_ARGUMENT`
**And** `details[]` содержит `BadRequest` с:
  - `field_violations[0].field = "folders[0].metadata.cloudId"`
  - `field_violations[0].description` указывает, что поле обязательно

---

## 8. Группа H — Default bootstrap (идемпотентный default Org/Cloud/Folder)

Сценарии группы H покрывают bootstrap-логику при старте сервиса. Тесты — integration через testcontainers + e2e через port-forward. Референс: `01-architecture-and-services.md` §2.2 «Bootstrap».

### H1. Первый старт: создаются default Organization, Cloud, Folder

**ID:** 0.2-H1

**Given** Postgres запущен с применёнными миграциями
**And** Таблицы `organizations`, `clouds`, `folders` — пусты
**And** Сервис `kacho-resource-manager` запускается впервые

**When** сервис завершает инициализацию (bootstrap-функция выполнилась)

**Then** В `organizations` существует запись с `name = 'default'`
**And** В `clouds` существует запись с `name = 'default'`, `organization_id = <default-org-uid>`
**And** В `folders` существует запись с `name = 'default'`, `cloud_id = <default-cloud-uid>`, `organization_id = <default-org-uid>`
**And** Все три `uid` — валидные UUID v4
**And** В `resource_events` — 3 события `ADDED` для каждого типа (Organization, Cloud, Folder)
**And** Сервис готов принимать запросы (health check = OK)

### H2. Повторный старт: bootstrap идемпотентен

**ID:** 0.2-H2

**Given** Сервис уже запускался (default Org, Cloud, Folder существуют в БД)
**And** `default` Organization имеет `uid = <org-uid-original>`

**When** сервис перезапускается (симуляция через `kill + restart` в тесте)

**Then** Bootstrap-функция выполняется снова
**And** В `organizations` по-прежнему ровно одна запись `name = 'default'` с тем же `uid = <org-uid-original>` (UID не изменился)
**And** В `clouds` по-прежнему ровно одна запись `name = 'default'`
**And** В `folders` по-прежнему ровно одна запись `name = 'default'`
**And** Никаких дополнительных записей `name = 'default'` не создано
**And** Новых ADDED-событий в `resource_events` для default-ресурсов не появилось (idempotent)

### H3. Bootstrap не уничтожает пользовательские данные

**ID:** 0.2-H3

**Given** Сервис уже запускался, default Org/Cloud/Folder существуют
**And** Пользователь создал Organization `"user-org"` и Cloud `"user-cloud"`

**When** сервис перезапускается

**Then** `"user-org"` и `"user-cloud"` остаются нетронутыми в БД
**And** Bootstrap создаёт/подтверждает только `name = 'default'`-ресурсы

### H4. e2e smoke: grpcurl List возвращает default-org через port-forward

**ID:** 0.2-H4

**Given** `kacho-resource-manager` Pod запущен в namespace `kacho` и прошёл readiness probe
**And** `kubectl port-forward svc/resource-manager 9090:9090 -n kacho` активен

**When** разработчик выполняет:
```bash
grpcurl -plaintext localhost:9090 \
  kacho.cloud.resourcemanager.v1.OrganizationService/List
```

**Then** команда завершается с кодом 0
**And** stdout содержит JSON с `"organizations"` массивом, включающим объект с `"name": "default"`
**And** В `organizations[0].metadata` заполнены: `uid`, `creationTimestamp`, `resourceVersion`

---

## 9. Группа I — Smoke e2e через port-forward (End-to-end)

Полные e2e-сценарии, которые выполняются через `kubectl port-forward` против реального кластера kind. Все bash-скрипты живут в `kacho-deploy/e2e/0.2/`. **API Gateway отсутствует в 0.2** — прямой gRPC на `localhost:9090` после port-forward.

### I1. Создание Cloud → List показывает новый Cloud

**ID:** 0.2-I1

**Given** `kacho-resource-manager` запущен
**And** Port-forward на `localhost:9090` активен
**And** Default Organization существует с `uid = <org-uid>` (получен через List)

**When** выполняется скрипт `kacho-deploy/e2e/0.2/I1-cloud-upsert-list.sh`:
```bash
# шаг 1: получить org uid
ORG_UID=$(grpcurl -plaintext -d '{}' localhost:9090 \
  kacho.cloud.resourcemanager.v1.OrganizationService/List \
  | jq -r '.organizations[0].metadata.uid')

# шаг 2: создать Cloud
grpcurl -plaintext \
  -d "{\"clouds\":[{\"metadata\":{\"name\":\"e2e-cloud\",\"organizationId\":\"$ORG_UID\"}}]}" \
  localhost:9090 \
  kacho.cloud.resourcemanager.v1.CloudService/Upsert

# шаг 3: проверить List
grpcurl -plaintext \
  -d "{\"selectors\":[{\"fieldSelector\":{\"organizationId\":\"$ORG_UID\"}}]}" \
  localhost:9090 \
  kacho.cloud.resourcemanager.v1.CloudService/List
```

**Then** шаг 1 возвращает непустой UID
**And** шаг 2 возвращает HTTP 200 / gRPC OK с заполненным `metadata.uid`
**And** шаг 3 возвращает массив `clouds[]` содержащий `"name": "e2e-cloud"`

### I2. Watch стрим получает события ADDED → MODIFIED → DELETED в реальном времени

**ID:** 0.2-I2

**Given** Port-forward на `localhost:9090` активен
**And** Default Organization существует

**When** выполняется скрипт `kacho-deploy/e2e/0.2/I2-watch-lifecycle.sh`:
```bash
# Запускаем Watch в фоне, пишем события в файл
grpcurl -plaintext -d '{}' localhost:9090 \
  kacho.cloud.resourcemanager.v1.OrganizationService/Watch \
  > /tmp/watch_events.json &
WATCH_PID=$!

# Ждём подключения Watch
sleep 1

# Создаём Organization
grpcurl -plaintext \
  -d '{"organizations":[{"metadata":{"name":"watch-test-org"}}]}' \
  localhost:9090 kacho.cloud.resourcemanager.v1.OrganizationService/Upsert

# Изменяем labels
grpcurl -plaintext \
  -d '{"organizations":[{"metadata":{"name":"watch-test-org","labels":{"updated":"true"}}}]}' \
  localhost:9090 kacho.cloud.resourcemanager.v1.OrganizationService/Upsert

# Удаляем
grpcurl -plaintext \
  -d '{"organizations":[{"metadata":{"name":"watch-test-org"}}]}' \
  localhost:9090 kacho.cloud.resourcemanager.v1.OrganizationService/Delete

sleep 1
kill $WATCH_PID
```

**Then** `/tmp/watch_events.json` содержит 3 события (каждое — отдельный JSON-объект):
1. `{"type":"ADDED", "organization":{"metadata":{"name":"watch-test-org",...}}}`
2. `{"type":"MODIFIED", "organization":{"metadata":{"labels":{"updated":"true"},...}}}`
3. `{"type":"DELETED", "organization":{"metadata":{"name":"watch-test-org",...}}}`
**And** события идут в порядке их создания (resourceVersion возрастает)

### I3. Watch Gone при устаревшем resourceVersion (integration-тест через testcontainers)

**ID:** 0.2-I3

**Примечание:** сценарий реализован как integration-тест (testcontainers), а не полноценный e2e bash-скрипт, так как достоверно воспроизвести истёкший retention в реальном кластере без искусственного вмешательства затруднительно. Bash-скрипт `kacho-deploy/e2e/0.2/I3-watch-gone.sh` помечается `@manual / @slow` и не включается в автоматический CI.

**Given** Postgres запущен (testcontainers) с применёнными миграциями
**And** В `resource_events` минимальная `resource_version` = 5000 (принудительно выставлена через прямой SQL-запрос внутри testcontainers-соединения: `DELETE FROM resource_events WHERE resource_version < 5000`)
**And** Watch Hub инициализирован после очистки (cursorRV знает о минимальной версии 5000)

**When** вызывается `OrganizationService/Watch` с:
- `resourceVersion = "100"` (заведомо < минимального 5000)

**Then** сервер немедленно закрывает стрим с gRPC статусом `OUT_OF_RANGE` и message `"Gone: resourceVersion too old, please relist"`
**And** `details[]` содержит `ErrorInfo` с `reason = "RESOURCE_VERSION_EXPIRED"` и `domain = "kacho.cloud"`
**And** `details[]` содержит `RequestInfo` с непустым `request_id`

### I4. Integration-тест на testcontainers: атомарность outbox

**ID:** 0.2-I4

**Given** Testcontainers поднимает Postgres с применёнными миграциями `kacho_resource_manager`
**And** Go-тест напрямую вызывает `service.OrganizationService.Upsert(ctx, req)` (без gRPC транспорта)

**When** `Upsert` вызывается для создания Organization `"atomic-test-org"`

**Then** Тест проверяет в одной транзакции:
- `SELECT count(*) FROM organizations WHERE name='atomic-test-org'` = 1
- `SELECT count(*) FROM resource_events WHERE resource_kind='Organization' AND event_type='ADDED'` = 1
- `resource_version` в обоих таблицах совпадает
**And** Тест симулирует сбой после записи в `organizations` но до commit — проверяет rollback (см. A2)
**And** Тест имеет имя `TestOrganization_Upsert_OutboxAtomicity_0_2_I4`

### I5. Helm chart resource-manager деплоится и проходит readiness probe

**ID:** 0.2-I5

**Given** `kind`-кластер поднят (`make dev-up`)
**And** В `kacho-deploy/helm/` присутствует chart для `resource-manager`
**And** Image `prorobotech/kacho-resource-manager:0.2.0` доступен (через `kind load` или локальный registry)

**When** выполняется `helm upgrade --install resource-manager kacho-deploy/helm/resource-manager/ -n kacho --values kacho-deploy/helm/resource-manager/values.dev.yaml`

**Then** Pod `resource-manager-*` переходит в статус `Running` и `Ready 1/1` в течение 60 секунд
**And** `kubectl exec -n kacho ... -- grpc_health_probe -addr :9090` возвращает `status: SERVING`
**And** Лог Pod содержит строку `"bootstrap completed"` или аналогичную (запись об успешном bootstrap)
**And** БД `kacho_resource_manager` содержит таблицы `organizations`, `clouds`, `folders`, `resource_events` (init-контейнер применил миграции)

---

## 10. Definition of Done

Sub-итерация 0.2 считается **завершённой**, когда **все** условия выполнены:

1. **Все сценарии §1–§9** (A1–A8, B1–B10, C1–C6, D1–D14, E1–E8, F1–F5, G1a, G2–G5, G7–G12, H1–H4, I1–I5) покрыты исполняемыми тестами:
   - Integration-тесты (testcontainers-Postgres) в `kacho-resource-manager/internal/service/*_acceptance_test.go` и `kacho-corelib/**/*_test.go` — все зелёные.
   - E2E bash-скрипты в `kacho-deploy/e2e/0.2/*.sh` — все зелёные при запуске `make e2e-test PHASE=0.2`.

2. **Proto** `kacho-proto/proto/kacho/cloud/resourcemanager/v1/` содержит:
   - `organization.proto` — сообщения `Organization`, `OrganizationUpsertRequest/Response`, `OrganizationDeleteRequest/Response`, `OrganizationListRequest/Response`, `OrganizationWatchRequest`, `OrganizationWatchEvent`
   - `cloud.proto` — аналогично для Cloud
   - `folder.proto` — аналогично для Folder
   - `internal.proto` — `ResourceManagerInternal` сервис с методами `FolderExists`, `CloudExists`, `OrganizationExists`
   - `buf lint` и `buf breaking` — зелёные

3. **kacho-corelib** содержит:
   - `watch/` — Hub, Subscribe/Unsubscribe, ring buffer, catch-up логика
   - `outbox/` — Writer, интеграция с Transactor, pg_notify
   - `selector/` — Builder, парсер FieldSelector + LabelSelector, SQL-WHERE генератор
   - `migrations/common/` — `0001_common_resource_events.sql`, cleanup-функция

4. **kacho-resource-manager** реализован:
   - `cmd/resource-manager/main.go` — composition root
   - `internal/domain/` — entity-типы Organization, Cloud, Folder
   - `internal/service/` — OrganizationService, CloudService, FolderService (use-case логика)
   - `internal/repo/` — sqlc-generated queries + handwritten filter-builder
   - `internal/handler/handler.go` — gRPC-хендлеры для публичных RPC (thin transport layer)
   - `internal/handler/internal_handler.go` — gRPC-хендлеры для Internal RPC (`FolderExists`, `CloudExists`, `OrganizationExists`); **не регистрируется** в api-gateway
   - `migrations/` — миграции `kacho_resource_manager` (включая sync из corelib/migrations/common/)
   - `deploy/` — Dockerfile, Helm chart values

5. **Default bootstrap** работает при первом и повторном старте (H1–H3 зелёные).

6. **Helm chart** для `resource-manager` добавлен в `kacho-deploy/helm/` и в `helm/umbrella/Chart.yaml` как опциональная зависимость.

7. **CI** всех затронутых репо зелёный:
   - `kacho-proto`: `buf-lint`, `buf-breaking`, `buf-generate` (без диффа в gen/)
   - `kacho-corelib`: `golangci-lint`, `go test ./...`
   - `kacho-resource-manager`: `golangci-lint`, `go test ./...` (включая integration с testcontainers)
   - `kacho-deploy`: `helm lint`

8. **Naming conventions** соблюдены:
   - Proto package: `kacho.cloud.resourcemanager.v1`
   - DB: `kacho_resource_manager`
   - Env: `KACHO_RESOURCE_MANAGER_*`
   - k8s service: `resource-manager.kacho.svc.cluster.local`
   - Docker image: `prorobotech/kacho-resource-manager:0.2.0`

9. `kacho-workspace/docs/specs/CHANGELOG.md` содержит запись о завершении sub-phase 0.2.

10. Тег `kacho-resource-manager:0.2.0` поставлен на `main` каждого затронутого репо.

---

## 11. Вопросы к acceptance-reviewer (Open questions)

*Все вопросы предыдущего раунда ревью разрешены inline. Блок оставлен для полноты; при следующем раунде сюда добавляются новые неоднозначности.*

*(Нет открытых вопросов)*

---

**После approve этого документа:**
- Конвертация сценариев в тесты — задача субагента `integration-tester`.
- План реализации — `kacho-workspace/docs/plans/sub-phase-0.2-resource-manager-and-watch-plan.md` (через `superpowers:writing-plans`), каждый шаг плана ссылается на идентификаторы сценариев из этого документа.
- Proto-контракт `kacho-proto/proto/kacho/cloud/resourcemanager/v1/` проверяет субагент `proto-api-reviewer` после реализации.
- Схема миграций `kacho_resource_manager` проверяет субагент `db-architect-reviewer` после реализации.
