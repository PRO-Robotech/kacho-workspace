# Sub-phase 2.0 — IAM E1: folder_id → project_id migration — Acceptance

> **Status**: DRAFT v2 — awaiting `acceptance-reviewer` APPROVED (round 2)
> **Date**: 2026-05-17 (v2 amended from reviewer v1 changes)
> **YouTrack**: [KAC-106](https://prorobotech.youtrack.cloud/issue/KAC-106) — child of epic [KAC-104](https://prorobotech.youtrack.cloud/issue/KAC-104)
> **Parent overview**: [[sub-phase-2.0-iam-overview-acceptance]]
> **Sibling predecessor**: [[sub-phase-2.0-iam-E0-skeleton-acceptance]] (E0 — Project ресурс уже live, KAC-105)
> **Blocks**: [KAC-110](https://prorobotech.youtrack.cloud/issue/KAC-110) (E5 — `kacho-resource-manager` нельзя выключить, пока peer-сервисы ещё ссылаются на `folder_id` в RM)
> **Blocked by (must merge first)**: **KAC-113** (`operations.principal` columns в corelib + sync в vpc/compute/loadbalancer/resource-manager — уже занял миграционные слоты 0002 в corelib/vpc/rm и 0008 в compute и 0004 в loadbalancer; без его merge'а corelib `0003_operations_project_id.sql` и per-сервисные rename-миграции конфликтуют по нумерации). Состояние на 2026-05-17: KAC-113 — **merged во все 4 сервиса**, см. per-service migration numbering таблицу в §5.0 ниже.
> **Does NOT block**: E2 / E3 / E4 — те идут параллельно к E1, они работают над auth/authz/UI и не ждут переименования owner-скоупа
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer` (gate per запрет #1, workspace `CLAUDE.md`)
> **Затронутые репо**: `kacho-proto`, `kacho-vpc`, `kacho-compute`, `kacho-loadbalancer`, `kacho-api-gateway`, `kacho-deploy`, `kacho-workspace` (docs)

---

## 0. Преамбула — что эта sub-итерация

E1 — **сквозное переименование owner-скоупа** ресурсов с `folder` на `project` во всех
backend-сервисах Kachō, которые этим скоупом пользуются. После E0 в кодовой базе живут
**обе** модели одновременно:
- `kacho-iam.Project` (новый ресурс, prefix `prj`, owner-scope) — есть, готов.
- `kacho-resource-manager.Folder` (старый ресурс, no-prefix UUID, owner-scope) — есть, используется.
- `kacho-vpc`, `kacho-compute`, `kacho-loadbalancer` — все 3 backend-сервиса ссылаются на
  `folder_id` (TEXT, без cross-DB FK) и зовут `kacho-resource-manager.FolderService.Exists`
  на request-path для валидации.

E1 переключает все 3 backend-сервиса с `folder_id`/`FolderClient` на `project_id`/`ProjectClient`:

| Слой              | Было (после E0)                                       | Становится (после E1)                          |
|-------------------|-------------------------------------------------------|-----------------------------------------------|
| Proto-поля        | `string folder_id = 2`                                | `string project_id = 2`                       |
| БД (VPC/CMP/LB)   | колонка `folder_id text NOT NULL`                     | колонка `project_id text NOT NULL`            |
| Индексы / UNIQUE  | `<res>_folder_id_name_key`                            | `<res>_project_id_name_key`                   |
| Domain-newtypes   | `FolderID string`                                     | `ProjectID string` (если был typed)           |
| Peer-client       | `clients/folder_client.go` → RM gRPC                  | `clients/project_client.go` → kacho-iam gRPC  |
| Кэш               | `clients/folder_cache.go` (LRU+TTL)                   | `clients/project_cache.go` (LRU+TTL, тот же pattern) |
| Env-vars          | `KACHO_VPC_RM__ENDPOINT` / `RESOURCE_MANAGER_GRPC_ADDR` | `KACHO_VPC_IAM__ENDPOINT` / `IAM_GRPC_ADDR` |
| REST paths (gw)   | `/vpc/v1/networks?folderId=<...>`                     | `/vpc/v1/networks?projectId=<...>`            |
| Newman cases      | `folderId` в JSON-телах, `existingFolderId` ENV-var   | `projectId`, `existingProjectId`              |
| Integration tests | `FolderClient` mock, `folder_id` в SQL fixtures        | `ProjectClient` mock, `project_id`           |
| Vault             | `edges/vpc-to-rm-folder-exists.md`                    | `edges/vpc-to-iam-project-validate.md`        |
| Runtime edges     | `kacho-vpc → kacho-resource-manager`                  | `kacho-vpc → kacho-iam`                       |
| RM-сервис         | live, обслуживает все 3 backend-а                     | live (для совместимости/E5), но **никто не зовёт** |

**E1 НЕ включает** (вынесено в другие sub-итерации):

- **Выключение `kacho-resource-manager`** (`Gone 410` на legacy paths, drop БД,
  убрать из helm) — это E5 (KAC-110). E1 оставляет RM **live**, чтобы внешние / legacy /
  тестовые клиенты могли продолжать использовать RM до E5; единственная разница — peer-сервисы
  больше его не зовут.
- **Реальную миграцию данных** `kacho_resource_manager.folders → kacho_iam.projects` —
  это тоже E5. В E1 на dev-стенде `make dev-up` пересоздаёт обе БД с нуля; в prod —
  prod-strategy для миграции данных пишется в E5-acceptance.
- **Auth / authz / Zitadel / OpenFGA** — это E2/E3.
- **Operation.principal** заполнение реальным user'ом — E4. В E1 `principal_type='system'`
  остаётся stub'ом, как в E0.
- **UI** — kacho-ui продолжает показывать `folder/project` alias до E4.
- **`kacho-yc-shim`** (CLI compat `yc --folder-id` → `--project-id` mapping) — out of scope
  для всей фазы 2.0.

После E1 проект попадает в состояние «backend-сервисы знают только Project, RM ещё жив-но-неиспользуем»;
E5 закрывает финальный аккорд (RM gone).

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент / запрет                                                  | Где соблюдаем                                                                                                                                                            |
|---------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Запрет #1** — кодирование только после APPROVED acceptance         | данный документ — gate; статус выше `DRAFT v1`                                                                                                                            |
| **Запрет #2** — НЕ упоминать "yandex"                               | в коде / схеме / proto / комментариях не упоминается; YC-стилистика error-text сохраняется (см. §8)                                                                       |
| **Запрет #3** — НЕ ORM                                              | миграции — handwritten SQL (`ALTER TABLE … RENAME COLUMN`); pgx, не gorm                                                                                                  |
| **Запрет #4** — НЕ каскад через границу сервиса                     | `kacho-iam.Project.Delete` НЕ инициирует cascade на `kacho-vpc.Network`-а в Project; vpc/compute/lb сами обрабатывают dangling-ref (см. §10.4)                          |
| **Запрет #5** — НЕ редактировать применённую миграцию               | каждое переименование колонки — **новая** миграция в каждом сервисе (`0003_rename_folder_to_project.sql` в VPC, etc.); существующая `0001_initial.sql` НЕ правится      |
| **Запрет #6** — Internal.* НЕ на external TLS endpoint              | `kacho-iam.InternalIAMService.LookupSubject` (используется api-gateway в E2/E3) не публикуется на TLS-listener; `ProjectService.Get` — публичный, можно                  |
| **Запрет #8** — DB-per-service                                      | никаких cross-DB FK: `kacho_vpc.networks.project_id` хранит `prj<...>` строкой, без FK на `kacho_iam.projects`                                                            |
| **Запрет #9** — async-only мутации                                  | все Create/Update/Delete в vpc/compute/lb продолжают возвращать `Operation`; правка project_id внутри Operation worker через peer-API                                    |
| **Запрет #10** — within-service refs на DB-уровне                   | `UNIQUE (project_id, name)` partial-index — DB-уровень; software-проверки project-existence — это **cross-service** ref (исключение из #10, см. §«Кросс-доменные ссылки») |
| **Запрет #11** — тесты в том же PR                                  | каждый E1-PR (в каждом из 3 backend-сервисов) содержит integration-test (testcontainers) + newman regression обновлён; формулировки «tests follow-up» **запрещены**       |
| **§«Кросс-доменные ссылки на ресурсы»** workspace `CLAUDE.md`       | новое ребро `* → kacho-iam`: `ProjectClient.Exists(project_id)` на request-path; fail-closed на мутациях, fail-open на чтении уже сохранённых ресурсов                  |
| **YC-стилистика — да, структура — по делу**                         | text ошибок остаётся YC-стиля: `"Project %s not found"`, `"projectId is required"`, regex `^prj[0-9a-z]{17}$`; структура не копируется (Project ≠ YC Folder)              |

---

## 2. Decision Log — фундаментальные решения, зафиксированные до GWT

Все 7 решений ниже резолвят open questions из stub'а §6 (старая v0) и **являются нормативными**
для всех 25+ сценариев. Реализация, расходящаяся с любым из них, — нарушение acceptance.

### Decision D-1 — Hard-rename, не dual-column (Migration Strategy Option A)

**Выбор**: **Option A — Hard rename** (`folder_id` → `project_id` в один шаг, без alias).

**Альтернатива Option B (dual-column transition)**: оставить `folder_id` deprecated, добавить
`project_id`, поддерживать оба на N релизов, потом drop `folder_id`.

**Обоснование выбора A**:

1. **Pre-1.0 контракт**. Kachō ещё не объявил stable API; нет external SLA-bound клиентов.
   Workspace `CLAUDE.md` §«Что это за проект» явно говорит «структурное расхождение с YC — норма»;
   аналогично переход к новой owner-модели — норма.
2. **Чистота кодовой базы**. Dual-column на 2-3 месяца оставит:
   - oneof-логику парсинга в каждом handler'е (`if req.project_id == "" && req.folder_id != "" { ... }`),
   - двойные UNIQUE-индексы (`(folder_id,name)` + `(project_id,name)` partial),
   - двойные backfill-триггеры,
   - тесты «и так и эдак».
   Удалить всё это в E5 — больше работы, чем сделать один hard-rename сейчас.
3. **Нет prod-data на момент E1**. Dev-стенд пересоздаётся `make dev-down -v && make dev-up`
   при каждом значимом изменении; прод-релизов backend-сервисов VPC/CMP/LB не было.
4. **Migration path data**. Если в будущем появится prod-инсталляция с данными — миграция данных
   `folders → projects` будет одна, в E5, по single-shot стратегии (`INSERT INTO projects
   SELECT … FROM folders`). E1-миграции переименования колонок применяются ДО migration данных,
   к этому моменту `kacho_iam.projects` уже создан (E0) и default-`prj_default` живёт.
5. **Rollback**. Down-миграция переименования — симметричная `RENAME COLUMN project_id TO folder_id`;
   тривиальна (см. D-2 § «idempotency / rollback»).
6. **Backward-compat для существующих внешних клиентов**: единственный потребитель API сейчас —
   `kacho-ui` и `tests/newman/*`. Оба под нашим контролем; правятся в том же эпике. Внешних
   yc-CLI-clients или 3rd-party интеграций нет.

**Следствия**:
- Proto-поля переименовываются in-place: `string folder_id = 2;` → `string project_id = 2;`.
  Номер поля = 2 сохраняется (сериализация по тегу, не по имени → wire-compatible на старых
  payload'ах; но JSON-имя меняется → JSON-клиенты ломаются — желаемое поведение).
- В `buf.yaml` каждого .proto добавляется `breaking: { ignore: [FIELD_SAME_NAME] }` ТОЛЬКО для
  файлов, где сделан rename — на ОДИН CI-run. После merge — флаг убирается.
- Клиент, прислывающий старый payload `{ "folderId": "fld-xxx" }`, получает sync `InvalidArgument`
  на каждом Create/Update: `"projectId is required"` (поле `project_id` пустое после JSON-decode'а;
  стандартная проверка required-полей). Это явный поломочный signal, не silent-accept (см. §8 GWT-23).

### Decision D-2 — Two-step ALTER TABLE per resource (ADD + UPDATE + DROP), не RENAME

**Выбор**: на DB-уровне миграция выполняет **3-step pattern**:

```sql
-- 1) ADD nullable
ALTER TABLE kacho_vpc.networks ADD COLUMN project_id text;

-- 2) backfill (dev: пусто, NULL OK; prod-flavored: COPY data)
UPDATE kacho_vpc.networks SET project_id = folder_id;

-- 3) Constraint flip
ALTER TABLE kacho_vpc.networks ALTER COLUMN project_id SET NOT NULL;
ALTER TABLE kacho_vpc.networks DROP COLUMN folder_id;

-- 4) Index rename
DROP INDEX kacho_vpc.networks_folder_id_name_key;
CREATE UNIQUE INDEX networks_project_id_name_key ON kacho_vpc.networks (project_id, name);
DROP INDEX kacho_vpc.networks_folder_idx;
CREATE INDEX networks_project_idx ON kacho_vpc.networks (project_id);
```

**Альтернатива**: `ALTER TABLE … RENAME COLUMN folder_id TO project_id`. Простое, мгновенное,
но:
- Не поддерживает миграцию данных в случае разных типов / преобразований (для нас типы те же,
  но best-practice — две колонки).
- При наличии outbox-triggers, которые ссылаются на `OLD.folder_id` / `NEW.folder_id` явным
  именем — RENAME требует ОДНОВРЕМЕННОГО пересоздания триггера (иначе SQL-ошибка). Триггер-функции
  в VPC ссылаются на `NEW.folder_id` (см. `vpc_outbox_notify` в `0001_initial.sql`), поэтому
  все равно надо пересоздавать функции — ADD/DROP цикл этому не мешает.
- На больших таблицах в prod — `ADD COLUMN` без default не блокирует таблицу (Postgres 11+);
  `UPDATE SET project_id = folder_id` — long-running, можно бить на batch'и; `DROP COLUMN` —
  metadata-only, instant. Total downtime минимален и предсказуем.

**Идемпотентность**: миграции в формате `goose` (как в kacho-vpc и kacho-compute). `goose up`
применяет неприменённые, повторный — no-op. Down-миграция выполняет симметричную операцию
(`ALTER TABLE … ADD COLUMN folder_id text; UPDATE … SET folder_id = project_id; ALTER COLUMN …
SET NOT NULL; DROP COLUMN project_id; …rename indexes…`).

**Тестируется**: Сценарий E1.MIG-04 (rollback flow): `goose up` → данные есть → `goose down 1`
→ старые колонки восстановлены → данные на месте. Сценарий E1.MIG-05 (idempotency): `goose up`
повторно — `Already applied`.

### Decision D-3 — Project-existence cached в каждом peer-сервисе (positive 30s / negative 5s)

**Выбор**: `ProjectClient.Exists(ctx, projectID)` в каждом из 3 backend-сервисов оборачивается
кешем `CachedProjectClient` по образцу существующего `CachedFolderClient` в kacho-vpc
(`internal/clients/folder_cache.go`):

- **Positive TTL** = 30s (project — стабильное свойство, удаляется редко).
- **Negative TTL** = 5s (свеже-созданный project быстро становится виден).
- **MaxSize** = 10_000 entries (LRU-bounded).
- **Fail-open на Unavailable/Internal/DeadlineExceeded** — НЕ кешируется, следующий запрос
  попробует снова.
- **Cache-NotFound** → кешируется как negative (TTL=5s) — короткий, чтобы свеже-созданный
  project быстро виден.

**Альтернативы**:

| Подход | Pro | Con | Verdict |
|--|--|--|--|
| Без кеша | проще; всегда свежие данные | каждый Create делает gRPC RTT в kacho-iam (~2-5ms); под burst 10K RPS — потолок ~3K RPS и нагрузка на iam | rejected |
| Positive-only кеш | проще | поход за свежесозданным project — лишний RTT после Create в iam; иначе negative-кешируется на 30s, ужас | rejected |
| Streaming-invalidate (LISTEN/NOTIFY на iam.project_changes) | реактивно, всегда свежие | нужна dedicated conn к iam-БД, переборщил для тривиальной существования | rejected (overkill) |
| **TTL+LRU с positive 30s / negative 5s** | proven pattern (kacho-vpc FolderClient уже использует); под нагрузкой даёт hit-rate >95%; устаревшие данные ≤30s | data может быть до 30s stale при удалении project | **selected** |

**Замечание для E3**: после E3 (OpenFGA Check-interceptor) project-existence-check может быть
вытеснен в gateway-side вместе с authz; пока в E1 — каждый backend сам.

### Decision D-4 — Move semantics для Project: ресурсы НЕ migrate сами по себе

**Открытый вопрос из stub'а §6.4**: если `kacho-iam.ProjectService.Move(project_id, new_account_id)`,
что должно произойти с ресурсами в peer-сервисах? Cascade-rebind? Reject?

**Выбор**: **ничего не происходит**. Project в peer-сервисах хранится **только по `project_id`**,
не по `(account_id, project_id)`. `account_id` не дублируется в `kacho_vpc.networks`,
`kacho_compute.instances`, `kacho_loadbalancer.target_groups`. Move меняет родительский
`account_id` в `kacho_iam.projects`; peer-сервисы об этом не узнают, и им не нужно — они
по-прежнему оперируют `project_id`. Запросы UI «список сетей в Account X» резолвятся в gateway-side:
1. UI → kacho-iam.ProjectService.List(account_id=acc-X) → список prj-id;
2. UI → kacho-vpc.NetworkService.List(project_id=prj-Y) по каждому prj-Y.

Это симметрично текущему поведению `kacho-resource-manager.FolderService.Move` — там тоже
backend-сервисы не реагируют.

**Тестируется в E1**: Сценарий E1.MV-01 — Move project, переcреaть Network, убедиться, что сеть
по-прежнему резолвится по project_id.

### Decision D-5 — Cross-project ссылки внутри сервиса запрещены DB-уровнем

**Открытый вопрос из stub'а §6.5**: Subnet в Network другого Project — что делать?

**Выбор**: **запрещено**. Subnet.project_id обязан равняться Network.project_id (которому
принадлежит Subnet через `network_id`). Аналогично:
- SecurityGroup.project_id == Network.project_id (SG привязана к Network)
- RouteTable.project_id == Network.project_id
- PrivateEndpoint.project_id == Network.project_id
- NetworkInterface — наследует через Subnet → Network

**DB-level enforcement**: добавить CHECK constraint, который выполняется через подзапрос /
FK на (network_id, project_id) composite. Технически в Postgres CHECK не может содержать
subquery, поэтому используем **trigger-based check** на INSERT/UPDATE:

```sql
CREATE OR REPLACE FUNCTION kacho_vpc.check_subnet_project_matches_network() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE
    parent_project text;
BEGIN
    SELECT project_id INTO parent_project
      FROM kacho_vpc.networks WHERE id = NEW.network_id;
    IF parent_project IS NULL THEN
        RAISE EXCEPTION 'Network % not found', NEW.network_id
            USING ERRCODE = '23503';   -- FK violation flavored
    END IF;
    IF parent_project <> NEW.project_id THEN
        RAISE EXCEPTION 'Subnet.project_id (%) does not match parent Network.project_id (%)',
            NEW.project_id, parent_project
            USING ERRCODE = '23514';   -- CHECK violation flavored
    END IF;
    RETURN NEW;
END;
$fn$;

CREATE TRIGGER subnets_project_matches_network_trg
    BEFORE INSERT OR UPDATE OF project_id, network_id ON kacho_vpc.subnets
    FOR EACH ROW EXECUTE FUNCTION kacho_vpc.check_subnet_project_matches_network();
```

Аналогичные триггеры для SG/RT/PE/NIC. Маппится через `wrapPgErr` в gRPC-status:
- 23503 → `FailedPrecondition "Network <id> not found"`
- 23514 → `InvalidArgument "child resource project does not match parent network project"`

**Тестируется**: Сценарий E1.XPR-01 — Subnet.Create в Network другого project → 23514 →
`InvalidArgument`.

### Decision D-6 — Operations.project_id — добавляется через corelib (отдельный мини-PR в corelib)

**Открытый вопрос из stub'а §6.6**: добавлять ли `project_id` в общую `operations`-таблицу
для удобства UI-фильтрации?

**Выбор**: **да, добавляется**. В `kacho-corelib/operations/migrations/common/0002_operations_project_id.sql`
(новая миграция, после `0001_operations_principal.sql`):

```sql
ALTER TABLE operations ADD COLUMN project_id text NOT NULL DEFAULT '';
CREATE INDEX operations_project_id_idx ON operations (project_id) WHERE project_id <> '';
```

`operations.Repo.Create(ctx, op, principal, projectID)` — расширенная сигнатура.

`projectID` — empty при операциях, которые не привязаны к project (e.g., iam.Account.Create).
Каждый сервис при создании Operation передаёт `projectID` из request'а.

**Альтернатива**: фильтрация через `Operation.metadata.project_id` (Any-payload). Postgres
JSON-path workable, но требует index per metadata-type, неудобный SQL, плохо реюзается между
сервисами. Прямая колонка проще, дешевле, поддерживается из коробки.

**Backward-compat**: default `''` — старые insert'ы без `projectID` работают; UI фильтрует
WHERE `project_id <> ''`.

**Sync через `make sync-migrations`** в каждый из 4 потребителей corelib `operations` (vpc, compute,
loadbalancer, resource-manager — последний нужен ровно до E5, потом drop).

### Decision D-7 — Все 3 backend-сервиса используют kacho-iam.ProjectService.Get (НЕ Exists)

**Открытый вопрос (новый)**: какой именно RPC вызывают peer-сервисы — `Get(id) → Project | NotFound`
или дешёвый `Exists(id) → bool` (boolean-only, без bandwidth на полный Project payload)?

**Выбор**: **`Get(id)`** — публичный RPC из E0. Причины:

1. **Reuse**: `Get` уже существует в E0 (`kacho.cloud.iam.v1.ProjectService.Get(GetProjectRequest)
   returns (Project)`); нет необходимости вводить второй RPC.
2. **Polymorphic future use**: peer-сервисы могут позже захотеть прочитать `display_name`
   project'а для логирования / outbox-event'ов. С `Exists` пришлось бы менять контракт.
3. **Bandwidth — некритично**: project payload ~200 bytes, кешируется на 30s, ~95% hit-rate
   под нагрузкой → реальный RPS на iam-сервис мал.
4. **Mapping**: `peer.ProjectClient.Exists(ctx, id) (bool, error)` — обёртка вокруг `Get`:
   ```go
   _, err := c.iam.ProjectService.Get(ctx, &iamv1.GetProjectRequest{ProjectId: id})
   if err == nil { return true, nil }
   if status.Code(err) == codes.NotFound { return false, nil }
   return false, err
   ```
   Кешируется boolean-результат (см. D-3).

**Не вводим `kacho-iam.InternalProjectService.Exists`** в E1 — иначе будет 4 разных API на
проверку существования (`Exists` в Internal, `Get` в публичном, FK в БД, кеш в peer). Один путь.

### Decision D-8 — Network.Move (и любой parent-resource.Move) с existing children: REJECT

**Открытый вопрос (новый, BLOCKER 3 из v1 review)**: триггер `check_child_project_matches_network`
из D-5 срабатывает на INSERT/UPDATE дочерних таблиц (Subnet/SG/RT/PE/NIC), но **НЕ** на
UPDATE `networks.project_id`. То есть `Network.Move(prj-A → prj-B)` оставит children с
`project_id='prj-A'`, тогда как Network уже `project_id='prj-B'` — будет nbd-state.

**Выбор**: **(c) REJECT Move если у parent'а есть children** — самый простой и явный путь.

**Альтернативы**:

| Вариант | Pro | Con | Verdict |
|---|---|---|---|
| (a) Trigger BEFORE UPDATE OF project_id ON networks с проверкой children | DB-level invariant | надо подобный trigger на каждый parent-table (5+ для VPC, 2 для compute, 1 для LB); сложно поддерживать | partial-use (см. §D-5+ ниже) |
| (b) Каскадный UPDATE children при Move parent | "магически работает" | нарушает single-row CAS-pattern; меняет семантику Move (теперь это multi-row TX, медленно, locking); сложный rollback при partial | rejected |
| **(c) REJECT Move если у parent'а есть children** | **простой; predictable; согласуется с FK ON DELETE RESTRICT pattern (parent нельзя удалить если есть children)** | UX чуть хуже — клиенту надо сначала Delete children, потом Move | **selected** |

**Enforcement**:

- **Application sync precheck** в `NetworkService.Move::worker` (vpc) — через `Repo.Reader(ctx)`:
  ```go
  // Count children across all 5 child-tables before allowing Move
  var (
      cntSubnets, cntRTs, cntSGs, cntPEs, cntNICs int
  )
  err := tx.QueryRow(ctx, `SELECT count(*) FROM kacho_vpc.subnets WHERE network_id=$1`, networkID).Scan(&cntSubnets)
  // ... similarly для route_tables, security_groups, private_endpoints, network_interfaces ...
  total := cntSubnets + cntRTs + cntSGs + cntPEs + cntNICs
  if total > 0 {
      return service.ErrFailedPrecondition.Wrap(fmt.Errorf("network has children, move children first (%d subnets, %d route_tables, %d security_groups, %d private_endpoints, %d network_interfaces)", cntSubnets, cntRTs, cntSGs, cntPEs, cntNICs))
  }
  ```

- **DB-level backstop**: BEFORE UPDATE OF project_id ON networks trigger:
  ```sql
  CREATE OR REPLACE FUNCTION kacho_vpc.check_network_no_children_on_project_change() RETURNS trigger
  LANGUAGE plpgsql AS $fn$
  DECLARE total int;
  BEGIN
      IF NEW.project_id = OLD.project_id THEN RETURN NEW; END IF;
      SELECT count(*) INTO total FROM (
          SELECT 1 FROM kacho_vpc.subnets WHERE network_id = NEW.id
          UNION ALL SELECT 1 FROM kacho_vpc.route_tables WHERE network_id = NEW.id
          UNION ALL SELECT 1 FROM kacho_vpc.security_groups WHERE network_id = NEW.id
          UNION ALL SELECT 1 FROM kacho_vpc.private_endpoints WHERE network_id = NEW.id
          UNION ALL SELECT 1 FROM kacho_vpc.network_interfaces WHERE subnet_id IN (SELECT id FROM kacho_vpc.subnets WHERE network_id = NEW.id)
      ) c;
      IF total > 0 THEN
          RAISE EXCEPTION 'network has children, cannot move (% total children)', total USING ERRCODE = '23514';
      END IF;
      RETURN NEW;
  END;
  $fn$;
  CREATE TRIGGER networks_no_children_on_project_change_trg
      BEFORE UPDATE OF project_id ON kacho_vpc.networks
      FOR EACH ROW EXECUTE FUNCTION kacho_vpc.check_network_no_children_on_project_change();
  ```

  Логика: **sync precheck в worker = UX/правильный текст ошибки**, **DB trigger = invariant
  (defense-in-depth)** — даже direct `psql UPDATE networks SET project_id=…` поймает.

- **Симметрично**: для kacho-compute (Instance.Move если бы был, в Compute сейчас нет — N/A),
  для kacho-loadbalancer (NLB.Move если бы был, тоже N/A в текущем scope). VPC — единственный,
  где Network.Move реализован сейчас.

**Тестируется**: новый сценарий **E1.VPC-05** (см. §6.4 ниже).

### Decision D-9 — Defense-in-depth: immutable parent.project_id на DB-уровне

**Дополнение к D-5 (BLOCKER 5 из v1 review)**: помимо запрета Move с children (D-8), напрямую
защищаем consistency — `parent.project_id` (Network/Hypervisor-equivalent в других сервисах)
может меняться **только через worker-path** (через Move RPC). Прямое `UPDATE networks SET project_id='...'`
через admin psql — запрещено.

**Механизм**: trigger session-variable guard.

```sql
CREATE OR REPLACE FUNCTION kacho_vpc.enforce_parent_move_via_worker() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
    IF NEW.project_id = OLD.project_id THEN RETURN NEW; END IF;
    IF current_setting('app.allow_parent_move', true) IS DISTINCT FROM 'true' THEN
        RAISE EXCEPTION 'direct UPDATE of %.project_id forbidden, use Move RPC', TG_TABLE_NAME
            USING ERRCODE = '42501';   -- INSUFFICIENT_PRIVILEGE flavored
    END IF;
    RETURN NEW;
END;
$fn$;

CREATE TRIGGER networks_project_id_immutable_trg
    BEFORE UPDATE OF project_id ON kacho_vpc.networks
    FOR EACH ROW EXECUTE FUNCTION kacho_vpc.enforce_parent_move_via_worker();
```

**Worker-flow** в `NetworkService.Move::worker`:
```go
err := r.tx.WithTx(ctx, func(tx pgx.Tx) error {
    // 1) allow parent-move в текущей TX'и
    if _, err := tx.Exec(ctx, `SET LOCAL app.allow_parent_move = 'true'`); err != nil {
        return err
    }
    // 2) D-8 check (children count) — UDF или inline
    // 3) UPDATE networks SET project_id = ...
    return nil
})
// SET LOCAL — TX-scoped, после COMMIT обнуляется
```

**Симметрично для compute / loadbalancer parent-resources** (если они есть; в E1 — только VPC.Network
имеет Move с project_id rebind, см. §6.4).

**Маппинг ошибки**: `42501` → gRPC `PermissionDenied "direct UPDATE forbidden, use Move RPC"`.
В нормальных условиях недостижимо из приложения (worker всегда ставит SET LOCAL), достижимо только
из admin psql.

**Тестируется**: интегр-тест в kacho-vpc `network_repo_integration_test.go::TestDirectUpdateProjectIdRejected` —
прямой `UPDATE` без SET LOCAL → exception 42501.

---

## 3. Target architecture (как было / как становится)

### 3.1 До E1 (state after E0 merged)

```
                       ┌──────────────┐
                       │  kacho-ui    │  (continues to call /resource-manager/v1/folders)
                       └──────┬───────┘
                              │
                              ▼
                       ┌────────────────────┐
                       │  kacho-api-gateway │
                       │ rest mux:          │
                       │  /vpc/v1/networks?folderId=...│
                       │  /compute/v1/instances?folderId=...│
                       │  /loadbalancer/v1/nlbs?folderId=... │
                       │  /resource-manager/v1/folders/*    │
                       │  /iam/v1/projects/*  (new, E0)     │
                       └─┬────────┬──────────┬──────────────┘
                         │        │          │
                         ▼        ▼          ▼
                  ┌──────────┐ ┌──────────┐ ┌──────────┐
                  │ kacho-vpc│ │k-compute │ │k-loadbal.│
                  │ folder_id│ │folder_id │ │folder_id │
                  │ in tables│ │in tables │ │in tables │
                  └────┬─────┘ └────┬─────┘ └────┬─────┘
                       │            │            │
                       └────────┬───┴────────┬───┘
                                ▼            ▼
                       ┌────────────────────────┐
                       │ kacho-resource-manager │
                       │   FolderService.Exists │
                       │   FolderService.Get    │
                       │   (все 3 backend       │
                       │    зовут для validation)│
                       └────────────────────────┘

                       ┌──────────────┐
                       │  kacho-iam   │  (live, но peer-сервисы не зовут)
                       │  ProjectSvc  │
                       │  (E0 ready)  │
                       └──────────────┘
```

### 3.2 После E1 (state after this sub-itr merged)

```
                       ┌──────────────┐
                       │  kacho-ui    │  (calls /iam/v1/projects + new /vpc/v1/networks?projectId)
                       └──────┬───────┘
                              │
                              ▼
                       ┌────────────────────┐
                       │  kacho-api-gateway │
                       │ rest mux:          │
                       │  /vpc/v1/networks?projectId=... │  ← rename
                       │  /compute/v1/instances?projectId│  ← rename
                       │  /loadbalancer/v1/nlbs?projectId│  ← rename
                       │  /resource-manager/v1/folders/* │  (still live; для совместимости)
                       │  /iam/v1/projects/*             │
                       └─┬────────┬──────────┬──────────────┘
                         │        │          │
                         ▼        ▼          ▼
                  ┌──────────┐ ┌──────────┐ ┌──────────┐
                  │ kacho-vpc│ │k-compute │ │k-loadbal.│
                  │ project_id│ │project_id│ │project_id│
                  │ in tables │ │in tables │ │in tables │
                  └────┬─────┘ └────┬─────┘ └────┬─────┘
                       │            │            │
                       └────────┬───┴────────┬───┘
                                ▼            ▼
                       ┌────────────────────────┐
                       │  kacho-iam             │
                       │  ProjectService.Get    │  ← все 3 backend здесь
                       │  (LRU+TTL cache в      │
                       │   каждом peer-сервисе) │
                       └────────────────────────┘

                       ┌────────────────────────┐
                       │ kacho-resource-manager │  (live, but NO requests from peers)
                       │  FolderService.Get/...│  (Prometheus counter == 0 from peers)
                       │  E5 will retire        │
                       └────────────────────────┘
```

### 3.3 Per-service skeleton change

Каждый из 3 backend-сервисов получает следующую структуру изменений:

```
kacho-<svc>/
├── internal/migrations/
│   ├── 0001_initial.sql           ← НЕ ТРОГАЕМ (запрет #5)
│   ├── 0002_operations_principal.sql (или другой existing) — НЕ ТРОГАЕМ
│   └── 0003_rename_folder_to_project.sql   ← НОВАЯ — ADD/UPDATE/DROP по каждой таблице
├── internal/clients/
│   ├── folder_client.go           ← DROP (или rename в project_client.go)
│   ├── folder_cache.go            ← DROP (или rename в project_cache.go)
│   ├── resourcemanager_client.go  ← DROP (заменяется на iam_client.go)
│   ├── iam_client.go              ← НОВЫЙ (gRPC client к kacho-iam ProjectService)
│   └── project_cache.go           ← НОВЫЙ (LRU+TTL, copy-pasted из folder_cache.go pattern)
├── internal/repo/
│   ├── <resource>_repo.go         ← rename folder_id → project_id во всех SQL queries
│   └── iface.go / port.go         ← FolderClient → ProjectClient port-интерфейс
├── internal/service/
│   ├── <resource>.go              ← переключиться на projectClient.Exists() в worker'е
│   └── validate.go                ← переименовать validateFolderID → validateProjectID
├── internal/domain/
│   └── <resource>.go              ← поле FolderID → ProjectID (если был typed; в VPC не было)
├── cmd/<svc>/main.go              ← composition root: NewIAMClient вместо NewFolderClient
└── tests/newman/cases/*.py        ← все 'folderId' → 'projectId'
```

---

## 4. Migration strategy (детально, ссылка из §2 D-1/D-2)

### 4.1 Хронология: один эпик = 7 PR'ов в строгом порядке

PR-chain (повторяет workspace `CLAUDE.md` §«Кросс-репо зависимости и порядок выполнения»):

| #  | Репо                  | Ветка             | Что делает                                                                 | Зависит от |
|----|-----------------------|-------------------|----------------------------------------------------------------------------|------------|
| 1  | kacho-corelib         | `KAC-106`         | operations.project_id колонка + Repo.Create(ctx,op,principal,projectID)    | none       |
| 2  | kacho-proto           | `KAC-106`         | folder_id → project_id в vpc/compute/loadbalancer всех .proto + regen gen/ | none       |
| 3  | kacho-vpc             | `KAC-106`         | migration 0003 + iam_client.go + project_cache.go + rewrite repo/service   | #1, #2     |
| 4  | kacho-compute         | `KAC-106`         | то же                                                                      | #1, #2     |
| 5  | kacho-loadbalancer    | `KAC-106`         | то же                                                                      | #1, #2     |
| 6  | kacho-api-gateway     | `KAC-106`         | REST routes folderId → projectId (если есть в URL paths)                   | #2         |
| 7  | kacho-deploy          | `KAC-106`         | helm values: KACHO_*_IAM__ENDPOINT env vars; RM env vars остаются          | #3, #4, #5 |
| 8  | kacho-workspace       | `KAC-106`         | docs/specs + obsidian vault entries (resources/, edges/, KAC/KAC-106.md)   | все выше   |

До merge-а PR #1 (corelib): PR #3/#4/#5 в их CI temporary pin'ят
`replace github.com/PRO-Robotech/kacho-corelib => ../kacho-corelib` к feature-ветке `KAC-106`
(`ref: KAC-106` в `.github/workflows/ci.yaml`). После merge corelib → unpin → merge backend PR's.

### 4.2 Per-resource list — что переименовать в каждом сервисе

#### kacho-vpc (8 ресурсов)

| Таблица              | Колонка folder_id | UNIQUE                       | INDEX folder      | Outbox trigger ref |
|----------------------|-------------------|------------------------------|-------------------|--------------------|
| networks             | да                | `networks_folder_id_name_key`| `networks_folder_idx` | да (`NEW.folder_id` в `vpc_outbox_notify`) |
| subnets              | да                | partial `_folder_id_name_key`| `subnets_folder_idx`  | да |
| addresses            | да                | partial `_folder_id_name_key`| `addresses_folder_idx`| да |
| route_tables         | да                | partial `_folder_id_name_key`| `route_tables_folder_idx` | да |
| security_groups      | да                | partial `_folder_id_name_key`| `sg_folder_idx`   | да |
| gateways             | да                | partial `_folder_id_name_key`| `gateways_folder_idx` | да |
| private_endpoints    | да                | partial `_folder_id_name_key`| `private_endpoints_folder_idx` | да |
| network_interfaces   | да                | partial `_folder_id_name_key`| (см. 0001_initial.sql) | да |

`address_pools` — admin-only, **не** имеет folder_id (миграция 0021 уже убрала), не trogaem.

Все 8 переименований в **одной** миграции `0003_rename_folder_to_project.sql`. В одной TX'и.

Триггер-функция `vpc_outbox_notify` пересоздаётся (ссылается на `NEW.folder_id` — теперь
`NEW.project_id`). Аналогично функции `subnet_auto_pick_rt`, `subnets_outbox_emit_route_table_change`
если ссылаются.

Дополнительно — новые триггеры из D-5 (Subnet/SG/RT/PE/NIC project matches parent Network).

#### kacho-compute (4 ресурса)

| Таблица     | Колонка folder_id | UNIQUE                         | INDEX folder        |
|-------------|-------------------|--------------------------------|---------------------|
| disks       | да                | `disks_folder_name_uniq`       | `disks_folder_idx`  |
| images      | да                | `images_folder_name_uniq` + `images_family_idx (folder_id,family,...)`| `images_folder_idx` |
| snapshots   | да                | `snapshots_folder_name_uniq`   | `snapshots_folder_idx` |
| instances   | да                | `instances_folder_name_uniq`   | `instances_folder_idx` |

`hypervisors` — admin-only ресурс, **не имеет** folder_id (см. compute 0006 migration).
`zones`/`regions` — geography, тоже без folder_id (admin-scope).

#### kacho-loadbalancer (2 ресурса)

| Таблица                | Колонка folder_id     | UNIQUE                 | INDEX folder           |
|------------------------|------------------------|------------------------|------------------------|
| target_groups          | да (UUID type)         | `UNIQUE(folder_id,name)` | `target_groups_folder_idx` |
| network_load_balancers | да (UUID type)         | `UNIQUE(folder_id,name)` | `nlb_folder_idx`       |

⚠️ В loadbalancer колонка **`UUID`**, не `TEXT` (исторически). После переименования тип
**остаётся `UUID`** — это backward-compat с уже сохранёнными rows. Project_id (`prj` + 17 chars
crockford-base32) представим как UUID-like, но это формально не UUID-v4. Возможна **migration
типа column** (`TEXT`) в отдельной миграции, но это out-of-scope E1; в E1 — keep UUID type,
проверить, что crockford-base32 `prjXXX...` валидно проходит в Postgres UUID-парсер.

> **OPEN QUESTION для acceptance-reviewer**: project_id формат `prj` + 17 чарактеров crockford-base32
> — это 20-символьная строка, **не валидный UUID**. Postgres UUID-парсер потребует точного формата
> `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` (36 chars с дефисами). Значит:
> - либо в loadbalancer миграции тип меняется на `TEXT` (single ALTER, fast);
> - либо вводится отдельный конвертор и хранится UUID-form (плохо: id-mismatch с другими сервисами).
>
> **Рекомендация**: type → `TEXT`, как vpc/compute. Включается в эту же миграцию `0005_rename_folder_to_project.sql`
> (loadbalancer уже на миграции 0004). См. Scenario E1.LB-04.

### 4.3 Backward-compat policy — JSON и gRPC

| Источник запроса           | Старый payload `{folderId}` | Новый payload `{projectId}` |
|----------------------------|------------------------------|----------------------------|
| kacho-ui                   | переписывается в этом же эпике, новые payload только |
| tests/newman/*             | переписывается, новые payload |
| yc-CLI (теоретически)      | сломается (`InvalidArgument "projectId is required"`) — ожидаемо, yc-shim out of scope |
| 3rd-party скрипты на curl  | сломаются (то же) — нет таких пользователей сейчас |
| gRPC-clients (e.g. peer)   | wire-compatible по field-number=2 (sent as folder_id payload arrives as project_id field) — но **только при wire-compat**; JSON-API через grpc-gateway сломается, как описано |

**Принципиально**: hard-break — желаемое поведение. Не «soft accept folderId silently» —
тогда было бы непонятно, мигрировал клиент или нет; ошибка лучше silent corruption.

---

## 5. Декомпозиция по сервисам — пошагово

### 5.0 Per-service migration numbering (нормативно, BLOCKER 1 fix)

**Реальное состояние миграционных слотов на 2026-05-17** (после merge'а KAC-113 во все сервисы),
проверенное через `ls project/<svc>/internal/migrations/` и `ls project/kacho-corelib/migrations/common/`:

| Сервис | Last applied migration (HEAD) | E1 corelib-sync file (operations.project_id) | E1 rename file (folder→project) |
|---|---|---|---|
| **kacho-corelib/migrations/common/** | `0002_operations_principal.sql` | **`0003_operations_project_id.sql`** (source) | n/a (corelib не хранит domain-tables) |
| **kacho-vpc/internal/migrations/** | `0002_operations_principal.sql` (after squashed `0001_initial.sql`) | `0003_operations_project_id.sql` (synced from corelib) | `0004_rename_folder_to_project.sql` |
| **kacho-compute/internal/migrations/** | `0008_operations_principal.sql` (after 0001-0007) | `0009_operations_project_id.sql` (synced) | `0010_rename_folder_to_project.sql` |
| **kacho-loadbalancer/internal/migrations/** | `0004_operations_principal.sql` (after 0001-0003) | `0005_operations_project_id.sql` (synced) | `0006_rename_folder_to_project.sql` + UUID→TEXT |
| **kacho-resource-manager/internal/migrations/** | `0002_operations_principal.sql` | `0003_operations_project_id.sql` (synced — needed для consistency corelib-sync; column unused в RM до E5; см. §16.3 resolved) | n/a (RM out of E1 rename-scope per D-X / §10 «не выключаем, но peers не зовут») |

**Правило применения**: в каждом из 4 backend-сервисов (corelib потребители) `make sync-migrations`
копирует **новый** `0003_operations_project_id.sql` из `kacho-corelib/migrations/common/` в
`internal/migrations/` под per-сервисным номером (см. таблицу выше). После этого создаётся
**отдельная** rename-миграция следующим номером.

**Любое расхождение с этой таблицей при реализации = нарушение acceptance** (D-2 / DoD-1..3).

Все литералы `0002_operations_project_id.sql` / `0003_rename_folder_to_project.sql` ниже в
документе **читать через эту таблицу** — то есть в kacho-vpc rename-миграция = `0004_...sql`
(не `0003`), в kacho-compute = `0010_...sql` (не `0003`), в kacho-loadbalancer = `0006_...sql`
(не `0005`).

**DoD addendum**: «Migration numbering verified против реального состояния каждого репо перед
merge'м PR» — каждый PR с миграцией обязан содержать в описании вывод `ls internal/migrations/`
ДО и ПОСЛЕ изменения.

### 5.1 kacho-corelib (Step 1 / PR #1)

**Файлы**:
- `migrations/common/0003_operations_project_id.sql` — новый файл (номер per §5.0 таблицы; **NOT** 0002 — слот 0002 занят `0002_operations_principal.sql` из KAC-113):

  ```sql
  -- +goose Up
  ALTER TABLE operations ADD COLUMN project_id text NOT NULL DEFAULT '';
  CREATE INDEX operations_project_id_idx ON operations (project_id) WHERE project_id <> '';

  -- +goose Down
  DROP INDEX IF EXISTS operations_project_id_idx;
  ALTER TABLE operations DROP COLUMN project_id;
  ```

- `operations/repo.go` — расширить сигнатуру `Create`:
  ```go
  func (r *Repo) Create(ctx context.Context, op Operation, principal Principal, projectID string) error
  ```
  Принципал — уже Principal struct, добавляем projectID 4-м параметром.

- `operations/types.go` — добавить поле `ProjectID string` в `Operation` struct (output);
  заполняется при SELECT.

**Тесты**:
- `operations/repo_test.go` (integration, testcontainers) — testInsertWithProjectID:
  insert op с `projectID="prj-abc"` → SELECT и проверить колонку, проверить index используется.

**Sync**: `make sync-migrations` в каждый из 4 потребителей: vpc, compute, loadbalancer, resource-manager.

**Acceptance**: Сценарий E1.COR-01 (см. §7).

### 5.2 kacho-proto (Step 2 / PR #2)

**Файлы** — заменить в каждом `.proto` (find & replace):

```
proto/kacho/cloud/vpc/v1/network.proto:                  string folder_id = 2;  →  string project_id = 2;
proto/kacho/cloud/vpc/v1/subnet.proto:                   string folder_id = 2;  →  string project_id = 2;
proto/kacho/cloud/vpc/v1/address.proto:                  string folder_id = 2;  →  string project_id = 2;
proto/kacho/cloud/vpc/v1/route_table.proto:              string folder_id = 2;  →  string project_id = 2;
proto/kacho/cloud/vpc/v1/security_group.proto:           string folder_id = 2;  →  string project_id = 2;
proto/kacho/cloud/vpc/v1/gateway.proto:                  string folder_id = 2;  →  string project_id = 2;
proto/kacho/cloud/vpc/v1/network_interface.proto:        string folder_id = 2;  →  string project_id = 2;
proto/kacho/cloud/vpc/v1/network_service.proto:          string folder_id = ... →  string project_id = ...   (List + Move requests)
proto/kacho/cloud/vpc/v1/subnet_service.proto:           ...                    →  ...
proto/kacho/cloud/vpc/v1/address_service.proto:          ...                    →  ...
proto/kacho/cloud/vpc/v1/route_table_service.proto:      ...                    →  ...
proto/kacho/cloud/vpc/v1/security_group_service.proto:   ...                    →  ...
proto/kacho/cloud/vpc/v1/gateway_service.proto:          ...                    →  ...
proto/kacho/cloud/vpc/v1/network_interface_service.proto:...                    →  ...
proto/kacho/cloud/vpc/v1/private_endpoint*.proto:        ...                    →  ...
proto/kacho/cloud/compute/v1/disk.proto:                 string folder_id = 2;  →  string project_id = 2;
proto/kacho/cloud/compute/v1/image.proto:                ...                    →  ...
proto/kacho/cloud/compute/v1/snapshot.proto:             ...                    →  ...
proto/kacho/cloud/compute/v1/instance.proto:             ...                    →  ...
proto/kacho/cloud/compute/v1/*service.proto:             folder_id → project_id (CreateXxx, ListXxxRequest, MoveXxxRequest)
proto/kacho/cloud/loadbalancer/v1/target_group.proto:    string folder_id = 2;  →  string project_id = 2;
proto/kacho/cloud/loadbalancer/v1/network_load_balancer.proto: ...              →  ...
proto/kacho/cloud/loadbalancer/v1/*service.proto:        folder_id → project_id
```

**REST аннотации** — обновить `google.api.http` query/path:
- `/vpc/v1/networks?folderId={folder_id}` → `/vpc/v1/networks?projectId={project_id}`
- `MoveNetworkRequest`: `destination_folder_id` → `destination_project_id`

**buf.yaml**:
- На время `KAC-106` ветки: `breaking: { ignore: [FILE_SAME_PACKAGE, FIELD_SAME_NAME] }`
  ТОЛЬКО для затронутых файлов. После merge — флаг возвращается обратно.

**Regen**:
```bash
make gen   # buf generate → gen/go/kacho/cloud/{vpc,compute,loadbalancer}/v1/*.pb.go обновляются
```

**Тесты**:
- `buf lint` — должен пройти после переименования (тестируется в CI).
- `buf breaking --against .git#branch=main` — упадёт; ignore-flag временно разрешает.

**Acceptance**: Сценарий E1.PRO-01, E1.PRO-02, E1.PRO-03.

### 5.3 kacho-vpc (Step 3 / PR #3)

#### 5.3.1 Миграция `0004_rename_folder_to_project.sql` (номер per §5.0 таблицы — slot 0003 занят corelib-synced `operations_project_id`)

```sql
-- +goose Up
BEGIN;

-- Drop outbox notify trigger temporarily (references NEW.folder_id)
DROP TRIGGER IF EXISTS vpc_outbox_notify_trg ON kacho_vpc.networks;
DROP TRIGGER IF EXISTS vpc_outbox_notify_trg ON kacho_vpc.subnets;
DROP TRIGGER IF EXISTS vpc_outbox_notify_trg ON kacho_vpc.addresses;
DROP TRIGGER IF EXISTS vpc_outbox_notify_trg ON kacho_vpc.route_tables;
DROP TRIGGER IF EXISTS vpc_outbox_notify_trg ON kacho_vpc.security_groups;
DROP TRIGGER IF EXISTS vpc_outbox_notify_trg ON kacho_vpc.gateways;
DROP TRIGGER IF EXISTS vpc_outbox_notify_trg ON kacho_vpc.private_endpoints;
DROP TRIGGER IF EXISTS vpc_outbox_notify_trg ON kacho_vpc.network_interfaces;
DROP FUNCTION IF EXISTS kacho_vpc.vpc_outbox_notify();

-- Drop indexes referring folder_id
DROP INDEX IF EXISTS kacho_vpc.networks_folder_id_name_key;
DROP INDEX IF EXISTS kacho_vpc.networks_folder_idx;
DROP INDEX IF EXISTS kacho_vpc.subnets_folder_id_name_key;
DROP INDEX IF EXISTS kacho_vpc.subnets_folder_idx;
DROP INDEX IF EXISTS kacho_vpc.addresses_folder_id_name_key;
DROP INDEX IF EXISTS kacho_vpc.addresses_folder_idx;
DROP INDEX IF EXISTS kacho_vpc.route_tables_folder_id_name_key;
DROP INDEX IF EXISTS kacho_vpc.route_tables_folder_idx;
DROP INDEX IF EXISTS kacho_vpc.security_groups_folder_id_name_key;
DROP INDEX IF EXISTS kacho_vpc.sg_folder_idx;
DROP INDEX IF EXISTS kacho_vpc.gateways_folder_id_name_key;
DROP INDEX IF EXISTS kacho_vpc.gateways_folder_idx;
DROP INDEX IF EXISTS kacho_vpc.private_endpoints_folder_id_name_key;
DROP INDEX IF EXISTS kacho_vpc.private_endpoints_folder_idx;
DROP INDEX IF EXISTS kacho_vpc.network_interfaces_folder_id_name_key;
-- network_interfaces also: any folder-related idx

-- Rename columns: ADD project_id, copy data, DROP folder_id
ALTER TABLE kacho_vpc.networks            ADD COLUMN project_id text;
UPDATE kacho_vpc.networks            SET project_id = folder_id;
ALTER TABLE kacho_vpc.networks            ALTER COLUMN project_id SET NOT NULL;
ALTER TABLE kacho_vpc.networks            DROP COLUMN folder_id;

ALTER TABLE kacho_vpc.subnets             ADD COLUMN project_id text;
UPDATE kacho_vpc.subnets             SET project_id = folder_id;
ALTER TABLE kacho_vpc.subnets             ALTER COLUMN project_id SET NOT NULL;
ALTER TABLE kacho_vpc.subnets             DROP COLUMN folder_id;

-- ... similarly for addresses, route_tables, security_groups, gateways, private_endpoints, network_interfaces

-- Recreate indexes with project_id
CREATE UNIQUE INDEX networks_project_id_name_key ON kacho_vpc.networks (project_id, name);
CREATE INDEX        networks_project_idx        ON kacho_vpc.networks (project_id);

CREATE UNIQUE INDEX subnets_project_id_name_key ON kacho_vpc.subnets (project_id, name) WHERE name <> '';
CREATE INDEX        subnets_project_idx         ON kacho_vpc.subnets (project_id);

-- ... similarly for addresses, route_tables, security_groups, gateways, private_endpoints, network_interfaces

-- Recreate outbox notify function with NEW.project_id
CREATE OR REPLACE FUNCTION kacho_vpc.vpc_outbox_notify() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE
    seq bigint;
BEGIN
    INSERT INTO kacho_vpc.vpc_outbox(resource_type, event_type, resource_id, payload)
    VALUES (TG_ARGV[0], TG_OP, NEW.id,
            jsonb_build_object(
                'id', NEW.id,
                'name', NEW.name,
                'project_id', NEW.project_id    -- renamed from folder_id
            ))
    RETURNING sequence_no INTO seq;
    PERFORM pg_notify('vpc_outbox', seq::text);
    RETURN NEW;
END;
$fn$;

-- IMPORTANT 12 (v1 review): все 8 outbox-триггеров явно перечислены (не "similarly"-handwave)
CREATE TRIGGER vpc_outbox_notify_trg AFTER INSERT OR UPDATE ON kacho_vpc.networks
    FOR EACH ROW EXECUTE FUNCTION kacho_vpc.vpc_outbox_notify('network');
CREATE TRIGGER vpc_outbox_notify_trg AFTER INSERT OR UPDATE ON kacho_vpc.subnets
    FOR EACH ROW EXECUTE FUNCTION kacho_vpc.vpc_outbox_notify('subnet');
CREATE TRIGGER vpc_outbox_notify_trg AFTER INSERT OR UPDATE ON kacho_vpc.addresses
    FOR EACH ROW EXECUTE FUNCTION kacho_vpc.vpc_outbox_notify('address');
CREATE TRIGGER vpc_outbox_notify_trg AFTER INSERT OR UPDATE ON kacho_vpc.route_tables
    FOR EACH ROW EXECUTE FUNCTION kacho_vpc.vpc_outbox_notify('route_table');
CREATE TRIGGER vpc_outbox_notify_trg AFTER INSERT OR UPDATE ON kacho_vpc.security_groups
    FOR EACH ROW EXECUTE FUNCTION kacho_vpc.vpc_outbox_notify('security_group');
CREATE TRIGGER vpc_outbox_notify_trg AFTER INSERT OR UPDATE ON kacho_vpc.gateways
    FOR EACH ROW EXECUTE FUNCTION kacho_vpc.vpc_outbox_notify('gateway');
CREATE TRIGGER vpc_outbox_notify_trg AFTER INSERT OR UPDATE ON kacho_vpc.private_endpoints
    FOR EACH ROW EXECUTE FUNCTION kacho_vpc.vpc_outbox_notify('private_endpoint');
CREATE TRIGGER vpc_outbox_notify_trg AFTER INSERT OR UPDATE ON kacho_vpc.network_interfaces
    FOR EACH ROW EXECUTE FUNCTION kacho_vpc.vpc_outbox_notify('network_interface');

-- D-5: cross-project ref triggers (Subnet/SG/RT/PE/NIC project matches parent Network)
CREATE OR REPLACE FUNCTION kacho_vpc.check_child_project_matches_network() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE parent_project text;
BEGIN
    SELECT project_id INTO parent_project FROM kacho_vpc.networks WHERE id = NEW.network_id;
    IF parent_project IS NULL THEN
        RAISE EXCEPTION 'Network % not found', NEW.network_id USING ERRCODE = '23503';
    END IF;
    IF parent_project <> NEW.project_id THEN
        RAISE EXCEPTION 'project_id (%) does not match parent network project_id (%)',
            NEW.project_id, parent_project USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$fn$;

-- IMPORTANT 12 (v1 review): D-5 child-project-matches-network triggers — все 5 child-tables явно
CREATE TRIGGER subnets_project_matches_network_trg
    BEFORE INSERT OR UPDATE OF project_id, network_id ON kacho_vpc.subnets
    FOR EACH ROW EXECUTE FUNCTION kacho_vpc.check_child_project_matches_network();
CREATE TRIGGER security_groups_project_matches_network_trg
    BEFORE INSERT OR UPDATE OF project_id, network_id ON kacho_vpc.security_groups
    FOR EACH ROW EXECUTE FUNCTION kacho_vpc.check_child_project_matches_network();
CREATE TRIGGER route_tables_project_matches_network_trg
    BEFORE INSERT OR UPDATE OF project_id, network_id ON kacho_vpc.route_tables
    FOR EACH ROW EXECUTE FUNCTION kacho_vpc.check_child_project_matches_network();
CREATE TRIGGER private_endpoints_project_matches_network_trg
    BEFORE INSERT OR UPDATE OF project_id, network_id ON kacho_vpc.private_endpoints
    FOR EACH ROW EXECUTE FUNCTION kacho_vpc.check_child_project_matches_network();
-- network_interfaces ссылается на network через subnet (transitive), отдельная trigger-функция:
CREATE OR REPLACE FUNCTION kacho_vpc.check_nic_project_matches_subnet_network() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE parent_project text;
BEGIN
    SELECT n.project_id INTO parent_project
      FROM kacho_vpc.subnets s
      JOIN kacho_vpc.networks n ON n.id = s.network_id
     WHERE s.id = NEW.subnet_id;
    IF parent_project IS NULL THEN
        RAISE EXCEPTION 'Subnet/Network for NIC not found' USING ERRCODE = '23503';
    END IF;
    IF parent_project <> NEW.project_id THEN
        RAISE EXCEPTION 'NIC.project_id (%) does not match parent network project_id (%) via subnet', NEW.project_id, parent_project USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$fn$;
CREATE TRIGGER network_interfaces_project_matches_subnet_network_trg
    BEFORE INSERT OR UPDATE OF project_id, subnet_id ON kacho_vpc.network_interfaces
    FOR EACH ROW EXECUTE FUNCTION kacho_vpc.check_nic_project_matches_subnet_network();

-- D-8 trigger (BLOCKER 3 fix): Network.Move с children → REJECT
CREATE OR REPLACE FUNCTION kacho_vpc.check_network_no_children_on_project_change() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE total int;
BEGIN
    IF NEW.project_id = OLD.project_id THEN RETURN NEW; END IF;
    SELECT count(*) INTO total FROM (
        SELECT 1 FROM kacho_vpc.subnets WHERE network_id = NEW.id
        UNION ALL SELECT 1 FROM kacho_vpc.route_tables WHERE network_id = NEW.id
        UNION ALL SELECT 1 FROM kacho_vpc.security_groups WHERE network_id = NEW.id
        UNION ALL SELECT 1 FROM kacho_vpc.private_endpoints WHERE network_id = NEW.id
        UNION ALL SELECT 1 FROM kacho_vpc.network_interfaces WHERE subnet_id IN (
            SELECT id FROM kacho_vpc.subnets WHERE network_id = NEW.id
        )
    ) c;
    IF total > 0 THEN
        RAISE EXCEPTION 'network has children, cannot move (% total children)', total USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$fn$;
CREATE TRIGGER networks_no_children_on_project_change_trg
    BEFORE UPDATE OF project_id ON kacho_vpc.networks
    FOR EACH ROW EXECUTE FUNCTION kacho_vpc.check_network_no_children_on_project_change();

-- D-9 trigger (BLOCKER 5 fix): immutable parent.project_id вне worker-path
CREATE OR REPLACE FUNCTION kacho_vpc.enforce_parent_move_via_worker() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
    IF NEW.project_id = OLD.project_id THEN RETURN NEW; END IF;
    IF current_setting('app.allow_parent_move', true) IS DISTINCT FROM 'true' THEN
        RAISE EXCEPTION 'direct UPDATE of %.project_id forbidden, use Move RPC', TG_TABLE_NAME
            USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$fn$;
CREATE TRIGGER networks_project_id_immutable_trg
    BEFORE UPDATE OF project_id ON kacho_vpc.networks
    FOR EACH ROW EXECUTE FUNCTION kacho_vpc.enforce_parent_move_via_worker();

-- Sync corelib operations.project_id: предполагается ОТДЕЛЬНАЯ миграция 0003_operations_project_id.sql
-- (synced из corelib через `make sync-migrations` ДО этой 0004_rename-миграции; см. §5.0 таблица).

COMMIT;

-- +goose Down
BEGIN;
-- симметричные операции в обратном порядке
-- (DROP triggers, ADD COLUMN folder_id, UPDATE SET folder_id = project_id, DROP project_id,
--  recreate folder_id indexes, recreate old outbox_notify function with NEW.folder_id)
COMMIT;
```

#### 5.3.2 Peer-client замена

Удалить:
- `internal/clients/folder_client.go`
- `internal/clients/folder_cache.go`
- `internal/clients/folder_cache_test.go`
- `internal/clients/resourcemanager_client.go`

Создать:
- `internal/clients/iam_client.go`:
  ```go
  package clients

  import (
      "context"
      iamv1 "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/iam/v1"
      "google.golang.org/grpc"
      "google.golang.org/grpc/codes"
      "google.golang.org/grpc/status"
  )

  type ProjectClient struct {
      iam iamv1.ProjectServiceClient
  }

  func NewProjectClient(conn *grpc.ClientConn) *ProjectClient {
      return &ProjectClient{iam: iamv1.NewProjectServiceClient(conn)}
  }

  func (c *ProjectClient) Exists(ctx context.Context, projectID string) (bool, error) {
      _, err := c.iam.Get(ctx, &iamv1.GetProjectRequest{ProjectId: projectID})
      if err == nil { return true, nil }
      if status.Code(err) == codes.NotFound { return false, nil }
      return false, err
  }
  ```

- `internal/clients/project_cache.go` — copy `folder_cache.go` pattern, rename Folder → Project,
  port-интерфейс `repo.ProjectClient` (см. ниже).

В `internal/repo/iface.go` (или ports.go) — port-интерфейс:
```go
type ProjectClient interface {
    Exists(ctx context.Context, projectID string) (bool, error)
}
```

В `internal/service/*.go` — `folderClient.Exists` → `projectClient.Exists`. Error-message
текст: `"Folder with id %s not found"` → `"Project %s not found"` (см. §8.1).

`composition root` (`cmd/vpc/main.go`):
```go
iamConn, err := grpcclient.Dial(cfg.IAM.Endpoint, ...)
rawProjectClient := clients.NewProjectClient(iamConn)
projectClient := clients.NewCachedProjectClient(rawProjectClient, clients.ProjectCacheConfig{
    PositiveTTL: cfg.ProjectCacheTTL,
    NegativeTTL: cfg.ProjectCacheNegativeTTL,
    MaxSize:     cfg.ProjectCacheSize,
})
```

#### 5.3.3 Config — env vars

В `internal/config/config.go` (либо `apps/kacho/config/`):
```go
type Config struct {
    // ...existing...
    IAM struct {
        Endpoint string `env:"KACHO_VPC_IAM__ENDPOINT" envDefault:"kacho-iam:9090"`
    }
    ProjectCacheTTL         time.Duration `env:"KACHO_VPC_PROJECT_CACHE_TTL"         envDefault:"30s"`
    ProjectCacheNegativeTTL time.Duration `env:"KACHO_VPC_PROJECT_CACHE_NEGATIVE_TTL" envDefault:"5s"`
    ProjectCacheSize        int           `env:"KACHO_VPC_PROJECT_CACHE_SIZE"        envDefault:"10000"`
}
```

Удалить `RM` / `ResourceManager` config-блок целиком.

#### 5.3.4 Repo — sqlc / handwritten queries

Все `WHERE folder_id = $1` → `WHERE project_id = $1`. Все `ORDER BY folder_id, ...` → `project_id`.
Все `INSERT (... folder_id ...) VALUES (... $1 ...)` → `... project_id ...`.

Для sqlc — перегенерить через `make sqlc-gen` после переименования колонок в migration + перегенерации
schema-snapshot. (kacho-vpc использует не sqlc, а handwritten pgx — упрощает.)

#### 5.3.5 Newman cases

Find & replace во всех `tests/newman/cases/*.py`:
- `'folderId': '{{existingFolderId}}'` → `'projectId': '{{existingProjectId}}'`
- В environments JSON: добавить ENV-var `existingProjectId` (=`prj_default` ID seeded E0).
- ENV-var `existingFolderId` можно оставить как **alias на `existingProjectId`** до окончания E1
  rollout, но в reality в JSON-телах больше не используется.

Перегенерить коллекции `python3 tests/newman/scripts/gen.py`.

### 5.4 kacho-compute (Step 4 / PR #4) — аналогично VPC

Файл `0010_rename_folder_to_project.sql` (номер per §5.0 таблицы — slots 0001-0008 уже заняты,
slot 0009 = corelib-synced `0009_operations_project_id.sql`):
- ADD/UPDATE/DROP для `disks`, `images`, `snapshots`, `instances` (4 таблицы).
- Indexes: `disks_folder_idx`, `disks_folder_name_uniq`, `images_folder_idx`,
  `images_folder_name_uniq`, `images_family_idx` (включает `folder_id`!), `snapshots_folder_idx`,
  `snapshots_folder_name_uniq`, `instances_folder_idx`, `instances_folder_name_uniq` —
  drop + recreate с `project_id`.
- ⚠️ `images_family_idx` композитный `(folder_id, family, created_at DESC) WHERE family <> ''` —
  recreate как `(project_id, family, created_at DESC) WHERE family <> ''`.

Peer-clients — drop `resourcemanager_client.go`, создать `iam_client.go` + кеш.

`internal/clients/instance_client.go`, `subnet_client.go` — **не трогаем**, они для других целей
(peer-API в обратную сторону — compute может проверить subnet в vpc и т.п.).

Config: `KACHO_COMPUTE_IAM__ENDPOINT`.

### 5.5 kacho-loadbalancer (Step 5 / PR #5)

Особенность — UUID-тип колонки `folder_id`. См. §4.2 OPEN QUESTION.

Recommendation миграции `0006_rename_folder_to_project.sql` (номер per §5.0 таблицы — slots
0001-0004 existing, slot 0005 = corelib-synced `0005_operations_project_id.sql`):
```sql
-- +goose Up
BEGIN;

-- target_groups
ALTER TABLE target_groups ADD COLUMN project_id text;
UPDATE target_groups SET project_id = folder_id::text;   -- UUID → TEXT
ALTER TABLE target_groups ALTER COLUMN project_id SET NOT NULL;
DROP INDEX IF EXISTS target_groups_folder_idx;
-- composite UNIQUE constraint (folder_id, name)
ALTER TABLE target_groups DROP CONSTRAINT target_groups_folder_id_name_key;  -- adjust to actual constraint name
ALTER TABLE target_groups DROP COLUMN folder_id;
ALTER TABLE target_groups ADD CONSTRAINT target_groups_project_id_name_key UNIQUE (project_id, name);
CREATE INDEX target_groups_project_idx ON target_groups (project_id);

-- similarly network_load_balancers

COMMIT;
```

Peer-clients: drop `folder_client.go`, создать `iam_client.go` + кеш.

Сервис newman-cases пока минимальный (loadbalancer не имеет full newman suite vpc-уровня),
но любые existing — переписываются на `projectId`.

### 5.6 kacho-api-gateway (Step 6 / PR #6)

Изменения минимальные — REST аннотации идут из proto (через grpc-gateway), поэтому регенерация
после PR #2 (kacho-proto) автоматически отрезолвит rename. Но:
- **REST URL paths**, если в gateway есть hardcoded маршруты, ссылающиеся на `folderId` —
  переписать (`/vpc/v1/networks?folderId=...` → `?projectId=...`).
- **Route prefix matching** — если есть code, который разбирает query-param `folderId` для
  routing — переписать.
- **Auth-interceptor** (если уже добавлен в E2) — он работает с opaque resource-id и не
  знает про project_id, ничего менять не нужно.

Проверить через `grep -rin folderId project/kacho-api-gateway/internal/` — допустимо нулевое
число after PR.

### 5.7 kacho-deploy (Step 7 / PR #7)

В helm values для каждого из vpc/compute/loadbalancer:

```yaml
# values.yaml — kacho-vpc
env:
  - name: KACHO_VPC_IAM__ENDPOINT
    value: "kacho-iam.{{ .Values.namespace }}.svc.cluster.local:9090"
  # remove KACHO_VPC_RM__ENDPOINT / KACHO_VPC_RESOURCE_MANAGER_GRPC_ADDR
  - name: KACHO_VPC_PROJECT_CACHE_TTL
    value: "30s"
  - name: KACHO_VPC_PROJECT_CACHE_NEGATIVE_TTL
    value: "5s"
  - name: KACHO_VPC_PROJECT_CACHE_SIZE
    value: "10000"
```

Аналогично compute, loadbalancer.

`kacho-iam` chart должен exposить port 9090 (уже сделано в E0 — Service `kacho-iam:9090`).

`kacho-resource-manager` — **НЕ выключаем**, helm values остаются, helm chart остаётся. Просто
никто его не зовёт.

### 5.8 kacho-workspace (Step 8 / PR #8)

- Этот файл (полностью переписанный из stub'а).
- `obsidian/kacho/resources/vpc-network.md`, `compute-instance.md`, `lb-nlb.md`,
  `lb-target-group.md`, `compute-disk.md`, `compute-image.md`, `compute-snapshot.md`,
  `vpc-subnet.md`, `vpc-address.md`, `vpc-security-group.md`, `vpc-route-table.md`,
  `vpc-gateway.md`, `vpc-private-endpoint.md`, `vpc-network-interface.md` — заменить
  `folder_id` → `project_id` в FK contract и lifecycle секциях.
- `obsidian/kacho/edges/vpc-to-rm-folder-exists.md` — пересоздать как
  `edges/vpc-to-iam-project-validate.md` (то же для compute, lb).
- `obsidian/kacho/edges/compute-to-rm-folder-exists.md` → `edges/compute-to-iam-project-validate.md`.
- `obsidian/kacho/edges/lb-to-rm-folder-exists.md` → `edges/lb-to-iam-project-validate.md`.
- `obsidian/kacho/packages/vpc-internal-clients.md` — обновить (folderClient → projectClient).
- `obsidian/kacho/KAC/KAC-106.md` — создать или обновить с финальными PR-URL'ами.
- Workspace `CLAUDE.md` §«Карта владельцев доменов» — обновить (Project → kacho-iam, для всего
  E1+ кода).

---

## 6. GWT-сценарии (25+)

Каждый сценарий имеет уникальный ID формата `E1.<DOMAIN>-<NN>`. Все сценарии нормативны.

### 6.1 Schema migration (5 сценариев)

#### Сценарий E1.MIG-01: Миграция применяется на чистой БД (dev pristine)

**ID**: E1.MIG-01
**Тип**: Happy path / fresh install

**Given** новый dev-стенд: `make dev-down -v && make dev-up`
**And** `kacho_vpc` БД создана с пустыми таблицами после `0001_initial.sql`, `0002_operations_principal.sql`, и `0003_operations_project_id.sql` (последняя — corelib-synced из `make sync-migrations`)
**And** миграция `0004_rename_folder_to_project.sql` ещё не применена

**When** запускается `kacho-vpc-migrator up` (либо при старте через embedded migrator)

**Then** миграция применяется успешно (exit-code 0)
**And** в `kacho_vpc.goose_db_version` появляется запись `0004_rename_folder_to_project`
**And** `\d kacho_vpc.networks` показывает колонку `project_id text NOT NULL` и **отсутствует** `folder_id`
**And** `\d kacho_vpc.networks` показывает индекс `networks_project_id_name_key` и `networks_project_idx`; **отсутствуют** `networks_folder_id_name_key`, `networks_folder_idx`
**And** аналогично для всех 8 таблиц: subnets, addresses, route_tables, security_groups, gateways, private_endpoints, network_interfaces
**And** `vpc_outbox_notify` функция пересоздана и ссылается на `NEW.project_id` (через `SELECT prosrc FROM pg_proc WHERE proname='vpc_outbox_notify'` найти строку с `'project_id'`)
**And** триггеры `subnets_project_matches_network_trg`, аналогичные для SG/RT/PE существуют

#### Сценарий E1.MIG-02: Миграция применяется на БД с pre-existing данными (dev backfill)

**ID**: E1.MIG-02
**Тип**: Backfill / data preservation

**Given** dev-стенд работает, в `kacho_vpc.networks` есть 3 строки:
  - `(id=enp-aaa, folder_id=fld-001, name=net-1, ...)`
  - `(id=enp-bbb, folder_id=fld-002, name=net-2, ...)`
  - `(id=enp-ccc, folder_id=fld-001, name=net-3, ...)`
**And** в `kacho_vpc.subnets` — 2 связанные подсети с теми же `folder_id`
**And** ни одна строка не имеет NULL `folder_id`

**When** запускается миграция `0004_rename_folder_to_project.sql`

**Then** миграция выполняется в одной транзакции, без partial-apply
**And** после миграции 3 строки `networks` имеют `project_id` = старому `folder_id`:
  - `(id=enp-aaa, project_id=fld-001, name=net-1)`
  - `(id=enp-bbb, project_id=fld-002, name=net-2)`
  - `(id=enp-ccc, project_id=fld-001, name=net-3)`
**And** 2 строки `subnets` сохранили родительские project_id (соответствуют network'у)
**And** UNIQUE-индекс `networks_project_id_name_key` НЕ нарушен (все 3 имени уникальны в скоупе project_id)

Note: в dev мы переиспользуем строки `fld-XXX` как `project_id` (формально это синтаксически не `prj`-prefix, но БД-колонка `text`, не валидирует format). После E5-data-migration `kacho_iam.projects` создаст соответствующие `prj-XXX` записи, и backend-данные переключатся на новые ID. В E1 — никакой реальной row-data conversion, только schema-rename.

#### Сценарий E1.MIG-03: Миграция не оставляет NULL в required колонке

**ID**: E1.MIG-03
**Тип**: NOT NULL invariant

**Given** dev-стенд с pre-existing данными как в E1.MIG-02
**And** все строки `networks` имеют непустой `folder_id`

**When** миграция применяется

**Then** после миграции `SELECT COUNT(*) FROM kacho_vpc.networks WHERE project_id IS NULL OR project_id = ''` = 0
**And** `\d kacho_vpc.networks` показывает `project_id text NOT NULL`
**And** попытка `INSERT INTO kacho_vpc.networks (id, name, ...) VALUES ('enp-zzz', 'no-project-net', ...)` без `project_id` падает с ошибкой `NOT NULL constraint violation` (SQLSTATE `23502`)

#### Сценарий E1.MIG-04: Down-миграция (rollback)

**ID**: E1.MIG-04
**Тип**: Rollback / reversibility

**Given** миграция `0004_rename_folder_to_project.sql` применена, есть данные

**When** запускается `kacho-vpc-migrator down 1` (откатывает одну миграцию)

**Then** миграция откатывается успешно
**And** `\d kacho_vpc.networks` показывает колонку `folder_id text NOT NULL` (восстановлена)
**And** `\d kacho_vpc.networks` показывает индексы `networks_folder_id_name_key`, `networks_folder_idx` (восстановлены)
**And** **отсутствуют** `project_id`, `networks_project_id_name_key`, `networks_project_idx`
**And** функция `vpc_outbox_notify` снова ссылается на `NEW.folder_id`
**And** данные сохранены: 3 networks с правильными `folder_id` значениями (теми же, что были до up-миграции)

#### Сценарий E1.MIG-05: Идемпотентность

**ID**: E1.MIG-05
**Тип**: Idempotency

**Given** миграция `0004_rename_folder_to_project.sql` уже применена

**When** запускается `kacho-vpc-migrator up` повторно

**Then** goose сообщает `goose: no migrations to run. current version: 4`
**And** exit-code 0
**And** schema не меняется (диагностика через `\d` показывает то же самое)

### 6.2 Proto rename (3 сценария)

#### Сценарий E1.PRO-01: buf lint и breaking прохолят с ignore-flag

**ID**: E1.PRO-01
**Тип**: Proto contract validation

**Given** в `kacho-proto/proto/kacho/cloud/vpc/v1/network.proto` поле переименовано `folder_id` → `project_id` (field number = 2)
**And** в `buf.yaml` временно прописан `breaking: { ignore: [FIELD_SAME_NAME] }` ТОЛЬКО для затронутых файлов

**When** запускается `buf lint` и `buf breaking --against .git#branch=main`

**Then** `buf lint` проходит без ошибок: новое имя поля `project_id` соответствует style-guide правилу `FIELD_LOWER_SNAKE_CASE` (default buf lint rule из категории `BASIC`), как и старое `folder_id` — оба snake_case. Никаких иных lint-issues не появляется (например, `MESSAGE_PASCAL_CASE` — структуры не трогаем; `PACKAGE_DIRECTORY_MATCH` — пути остаются).
**And** `buf breaking` без ignore-flag упал бы с `FIELD_SAME_NAME` (документировано в commit-message)
**And** `buf breaking` с ignore-flag проходит зелёным
**And** в PR-описании явно отмечено «breaking change — ignored field-rename per acceptance E1.PRO-01»

#### Сценарий E1.PRO-02: gen/go регенерируется корректно

**ID**: E1.PRO-02
**Тип**: Code generation

**Given** все 22 .proto файла vpc/compute/loadbalancer переименованы

**When** запускается `make gen` (`buf generate`)

**Then** в `gen/go/kacho/cloud/vpc/v1/network.pb.go` существует поле `ProjectId string` в struct `Network`
**And** **отсутствует** поле `FolderId`
**And** GeneratedJSON-теги: `json:"projectId,omitempty"` (camelCase)
**And** аналогично для CreateNetworkRequest, ListNetworksRequest (поле `ParentId` или `ProjectId` зависит от RPC), MoveNetworkRequest (`DestinationProjectId`)
**And** соответствующие изменения в compute/loadbalancer gen'е
**And** `git diff gen/` показывает только переименования (не unrelated изменения)

#### Сценарий E1.PRO-03: JSON wire-format meets expectations

**ID**: E1.PRO-03
**Тип**: Wire-format / serialization

**Given** клиент шлёт payload `POST /vpc/v1/networks` через grpc-gateway

**When** клиент шлёт **новый** JSON-payload:
```json
{
  "name": "net-prj-1",
  "projectId": "prj-aaa",
  "description": "test"
}
```

**Then** запрос успешно демаршалится в `CreateNetworkRequest{ProjectId: "prj-aaa", Name: "net-prj-1", Description: "test"}`
**And** worker создаёт Network с `project_id='prj-aaa'`

**When (negative)** клиент шлёт **старый** JSON-payload:
```json
{
  "name": "net-prj-2",
  "folderId": "fld-old"
}
```

**Then** grpc-gateway игнорирует unknown JSON-key `folderId` (json strict-mode = `false` is default in grpc-gateway)
**And** `CreateNetworkRequest.ProjectId` равен `""` (пустая строка)
**And** sync-валидация в handler'е падает: `InvalidArgument "projectId is required"`
**And** HTTP-status 400 Bad Request
**And** **никакая Operation не создаётся** (sync-fail до Operation.New)

### 6.3 ProjectClient (5 сценариев)

#### Сценарий E1.CLI-01: Positive cache hit

**ID**: E1.CLI-01
**Тип**: Cache positive

**Given** kacho-vpc стартован, `CachedProjectClient` инициализирован с `PositiveTTL=30s`
**And** `kacho-iam.ProjectService.Get("prj-aaa")` возвращает Project (existing)
**And** первый запрос `Network.Create(projectId="prj-aaa")` уже прошёл, cache содержит entry

**When** второй запрос `Network.Create(projectId="prj-aaa")` стартует в worker'е (внутри 30s окна)

**Then** worker не делает gRPC-вызов в kacho-iam (cache hit)
**And** `projectClient.Exists("prj-aaa")` возвращает `(true, nil)` за <1ms (in-process map lookup)
**And** Network.Create продолжается, успешно создаётся row в БД
**And** Prometheus counter `kacho_vpc_project_cache_hits_total{result="positive"}` инкрементируется

#### Сценарий E1.CLI-02: Negative cache short TTL

**ID**: E1.CLI-02
**Тип**: Cache negative

**Given** kacho-vpc стартован, cache пустой
**And** `kacho-iam.ProjectService.Get("prj-zzz")` возвращает NotFound

**When** клиент шлёт `Network.Create(projectId="prj-zzz")` (первый раз)

**Then** worker делает gRPC-вызов в kacho-iam → NotFound → `Exists` возвращает `(false, nil)`
**And** worker возвращает `NotFound "Project prj-zzz not found"` (текст YC-style)
**And** Operation помечается `done=true`, `error.code=NOT_FOUND`
**And** cache содержит entry `(prj-zzz, exists=false, expiresAt=now+5s)`

**When** клиент повторяет тот же запрос через 3s (внутри 5s negative TTL)

**Then** worker НЕ делает gRPC-вызов (cache hit)
**And** возвращает NotFound тот же текст

**When** клиент повторяет через 6s (за пределами 5s TTL)

**Then** worker снова делает gRPC-вызов (cache miss / expired)

#### Сценарий E1.CLI-03: Fail-open на Unavailable

**ID**: E1.CLI-03
**Тип**: Resilience / fail mode

**Given** kacho-iam находится в restart loop, gRPC-соединение возвращает `Unavailable`
**And** cache пустой

**When** клиент шлёт `Network.Create(projectId="prj-aaa")`

**Then** worker делает gRPC-вызов → получает `Unavailable`
**And** **НЕ кеширует** результат (fail-open semantics)
**And** возвращает `Unavailable "project check: rpc error: code = Unavailable desc = ..."` (либо `Internal`, в зависимости от текущего mapping policy сервиса)
**And** Operation помечается `error.code=UNAVAILABLE`
**And** Prometheus counter `kacho_vpc_project_cache_misses_total{reason="upstream_error"}` инкрементируется

**When** клиент повторяет запрос через 1s (kacho-iam восстановился)

**Then** worker снова делает gRPC-вызов (cache не закеширован)
**And** получает success → cache positive entry → Network.Create продолжается

#### Сценарий E1.CLI-04: Dead peer not blocking async workers

**ID**: E1.CLI-04
**Тип**: Async resilience

**Given** kacho-iam недоступен полностью
**And** клиент шлёт burst 100 `Network.Create` запросов, каждый с уникальным `projectId`

**When** все 100 запросов попадают в workers (Operations созданы)

**Then** каждый worker делает gRPC-вызов с context-deadline = 5s (default grpc-call deadline)
**And** все 100 Operations завершаются с `error.code=UNAVAILABLE` в течение ~5s (parallel timeout)
**And** kacho-vpc сервис **не виснет**, продолжает принимать новые запросы (healthz зелёный)
**And** workers возвращаются в pool через 5s, ready для новых задач

#### Сценарий E1.CLI-05: Gracefully degraded reads (dangling-ref на List)

**ID**: E1.CLI-05
**Тип**: Dangling ref / graceful degradation

**Given** kacho-vpc содержит 2 Network'а с `project_id='prj-deleted'`
**And** kacho-iam **удалил** проект `prj-deleted` (синхронно через ProjectService.Delete; cascade на peer-сервисы запрещён, см. запрет #4)
**And** cache в kacho-vpc уже содержит positive entry `prj-deleted` (создан 20s назад, ещё валиден)

**When** клиент шлёт `Network.List(projectId="prj-deleted")`

**Then** kacho-vpc **НЕ зовёт** ProjectClient (List operations не валидируют project — это чтение уже сохранённого)
**And** запрос возвращает обе Network'а как `OK` с их полями (включая `project_id="prj-deleted"`)
**And** UI получает 2 сетки и может пометить их как `dangling` визуально (если знает, что project удалён)

**When** клиент шлёт `Network.Create(name="new-net", projectId="prj-deleted")` через 5s (кеш всё ещё valid → 25s)

**Then** worker **берёт positive из cache** → `projectClient.Exists("prj-deleted")` возвращает `(true, nil)` (stale!)
**And** Network успешно создаётся в БД с `project_id='prj-deleted'`
**And** это **acceptable** — eventual consistency window ≤30s (positive TTL)

**When** клиент повторяет Create через 35s (cache expired)

**Then** worker делает свежий gRPC-вызов в kacho-iam → NotFound
**And** возвращает `NotFound "Project prj-deleted not found"`

(Acceptable behavior — внутри 30s window race-window есть; зафиксирована в Decision D-3.)

### 6.4 Use-case update — kacho-vpc (4 сценария)

#### Сценарий E1.VPC-01: Network.Create с project_id

**ID**: E1.VPC-01
**Тип**: Happy path

**Given** kacho-iam работает, `prj_default` существует (seed E0)
**And** kacho-vpc стартован с `KACHO_VPC_IAM__ENDPOINT=kacho-iam:9090`

**When** клиент шлёт `POST /vpc/v1/networks`:
```json
{
  "name": "net-prj-01",
  "projectId": "prj_default",
  "description": "first project-scoped network",
  "labels": {"env": "dev"}
}
```

**Then** sync-валидация проходит (`name`, `project_id` non-empty, labels valid)
**And** Operation создаётся с `metadata.project_id="prj_default"` (через corelib operations.project_id field — Decision D-6)
**And** worker делает `projectClient.Exists("prj_default")` → cache miss → gRPC к kacho-iam → `(true, nil)`
**And** row создаётся `INSERT INTO kacho_vpc.networks (id, project_id, name, ...) VALUES ('enp-xxx', 'prj_default', 'net-prj-01', ...)`
**And** в `vpc_outbox` создаётся `Network.CREATED` с payload `{project_id: "prj_default", ...}`
**And** Operation помечается `done=true`, response = Network proto
**And** клиент через `OperationService.Get` получает финальный Network с `projectId="prj_default"`

#### Сценарий E1.VPC-02: Network.Move на новый project

**ID**: E1.VPC-02
**Тип**: Move semantics

**Given** Network `enp-yyy` существует в `prj-source`
**And** target project `prj-target` существует в kacho-iam (тот же или другой Account — не важно, см. Decision D-4)

**When** клиент шлёт `POST /vpc/v1/networks/enp-yyy:move`:
```json
{
  "destinationProjectId": "prj-target"
}
```

**Then** sync-валидация проходит (`destinationProjectId` non-empty)
**And** Operation создаётся
**And** worker делает `projectClient.Exists("prj-target")` → `(true, nil)`
**And** `UPDATE kacho_vpc.networks SET project_id='prj-target' WHERE id='enp-yyy'` (атомарно, в одной TX'и; UNIQUE-проверка `(project_id, name)` срабатывает если в target project уже есть Network с тем же именем → 23505 → `ALREADY_EXISTS`)
**And** в `vpc_outbox` создаётся `Network.UPDATED` с новым `project_id`
**And** Operation помечается `done=true`

**Negative variant**: target project не существует → `NotFound "Project prj-nonexistent not found"`.

#### Сценарий E1.VPC-03: Subnet.Create наследует project_id от Network через cross-project check

**ID**: E1.VPC-03
**Тип**: D-5 cross-project enforcement happy path

**Given** Network `enp-aaa` существует, `project_id='prj-acme'`
**And** клиент создаёт Subnet с **тем же** project_id

**When** клиент шлёт `POST /vpc/v1/subnets`:
```json
{
  "name": "subnet-aaa-1",
  "projectId": "prj-acme",
  "networkId": "enp-aaa",
  "zoneId": "kacho-zone-a",
  "v4CidrBlocks": ["10.0.0.0/24"]
}
```

**Then** sync-валидация проходит
**And** worker делает `projectClient.Exists("prj-acme")` → success
**And** `INSERT INTO kacho_vpc.subnets (id, project_id, network_id, name, ...) VALUES ('e9b-xxx', 'prj-acme', 'enp-aaa', 'subnet-aaa-1', ...)`
**And** триггер `subnets_project_matches_network_trg` проверяет `parent.project_id == NEW.project_id`: `prj-acme == prj-acme` → OK
**And** Subnet создаётся

#### Сценарий E1.VPC-04: FK ON DELETE RESTRICT — Project.Delete cross-service не cascade

**ID**: E1.VPC-04
**Тип**: запрет #4 — нет каскада через границу сервиса

**Given** в kacho-iam существует `prj-acme`
**And** в kacho-vpc — 3 Network'а с `project_id='prj-acme'`

**When** клиент шлёт `DELETE /iam/v1/projects/prj-acme`

**Then** kacho-iam **НЕ зовёт** kacho-vpc для проверки (по дизайну — запрет #4, см. workspace `CLAUDE.md`)
**And** в kacho-iam Project.Delete либо проходит, либо отвергается своей собственной FK-проверкой `RESTRICT` если есть AccessBinding'и с `resource_id=prj-acme` (см. E0 §«AccessBinding»)
**And** допустим **вариант A — Delete проходит**: project удалён в kacho-iam
**And** в kacho-vpc 3 Network'а **остаются live** (dangling reference на `project_id='prj-acme'`)

**When** клиент шлёт `Network.List(projectId="prj-acme")`

**Then** возвращаются 3 Network'а (List не валидирует project — см. E1.CLI-05)

**When** клиент шлёт `Network.Create(name="new", projectId="prj-acme")` после истечения cache TTL

**Then** `projectClient.Exists("prj-acme")` → `(false, nil)`
**And** worker возвращает `NotFound "Project prj-acme not found"`
**And** Operation помечается failed

(Сценарий фиксирует "graceful dangling-ref" подход.)

#### Сценарий E1.VPC-05: Network.Move с existing children → FailedPrecondition (D-8)

**ID**: E1.VPC-05
**Тип**: D-8 enforcement — REJECT Network.Move если у parent'а есть children

**Given** Network `enp-with-kids` существует в `prj-A`
**And** в `kacho_vpc.subnets` есть 3 row'а с `network_id='enp-with-kids'` (`sn-1`, `sn-2`, `sn-3`)
**And** в `kacho_vpc.route_tables` есть 0 rows для этого network
**And** в `kacho_vpc.security_groups` есть 0 rows
**And** target project `prj-B` существует в kacho-iam

**When** клиент шлёт `POST /vpc/v1/networks/enp-with-kids:move`:
```json
{ "destinationProjectId": "prj-B" }
```

**Then** sync-валидация проходит (`destinationProjectId` non-empty)
**And** Operation создаётся (PENDING)
**And** worker делает `projectClient.Exists("prj-B")` → success
**And** worker выполняет sync-precheck (per D-8): `SELECT count(*) FROM kacho_vpc.subnets WHERE network_id='enp-with-kids'` → 3
**And** worker суммирует counts по 5 child-tables → 3 total
**And** worker возвращает `FailedPrecondition`
**And** Operation помечается `done=true`, `error.code=FAILED_PRECONDITION`, `error.message="network has children, move children first (3 subnets, 0 route_tables, 0 security_groups, 0 private_endpoints, 0 network_interfaces)"`
**And** `SELECT project_id FROM kacho_vpc.networks WHERE id='enp-with-kids'` → `'prj-A'` (не изменено)
**And** `SELECT count(*) FROM kacho_vpc.subnets WHERE network_id='enp-with-kids'` → 3 (не изменено)

**Oracle / verification**:
```bash
# GET /iam/v1/operations/{op_id}
{
  "done": true,
  "error": {
    "code": 9,                                   # FAILED_PRECONDITION
    "message": "network has children, move children first (3 subnets, 0 route_tables, 0 security_groups, 0 private_endpoints, 0 network_interfaces)"
  }
}
```

**D-9 backstop tested**: если клиент пытается direct psql `UPDATE kacho_vpc.networks SET project_id='prj-B' WHERE id='enp-with-kids'` (без `SET LOCAL app.allow_parent_move = 'true'` — что worker делает в TX'и):
- Сначала срабатывает `networks_project_id_immutable_trg` (D-9) → `42501 "direct UPDATE of networks.project_id forbidden, use Move RPC"`.
- Даже если admin bypass'нет D-9 (set session var), сработает `networks_no_children_on_project_change_trg` (D-8) → `23514 "network has children, cannot move (3 total children)"`.

**Implementation note**: `NetworkService.Move::worker` flow:
1. `BEGIN`
2. `SET LOCAL app.allow_parent_move = 'true'` (D-9 bypass — только в TX'и worker'а)
3. Reader-precheck — count children, если ≥1 → return ErrFailedPrecondition (D-8 sync path)
4. `UPDATE networks SET project_id = $1 WHERE id = $2` (D-9 trigger пропустит, D-8 trigger тоже — children=0)
5. `COMMIT`

### 6.5 Use-case update — kacho-compute (3 сценария)

#### Сценарий E1.CMP-01: Instance.Create с project_id, валидация project существует

**ID**: E1.CMP-01
**Тип**: Happy path

**Given** kacho-iam работает, `prj_default` существует
**And** в kacho-vpc есть Subnet `e9b-sub1` с `project_id='prj_default'`
**And** в kacho-compute есть Image `ub-2204`

**When** клиент шлёт `POST /compute/v1/instances`:
```json
{
  "name": "vm-01",
  "projectId": "prj_default",
  "zoneId": "kacho-zone-a",
  "platformId": "standard-v3",
  "resourcesSpec": {"cores": 2, "memory": "4Gi"},
  "bootDiskSpec": {"diskId": "..."},
  "networkInterfaceSpecs": [{"subnetId": "e9b-sub1"}]
}
```

**Then** sync-валидация проходит
**And** worker делает `projectClient.Exists("prj_default")` в kacho-compute → success
**And** дополнительно — peer-вызов в kacho-vpc для валидации `subnetId` (через существующий `subnet_client.go`, не меняется)
**And** Instance создаётся с `project_id='prj_default'`

#### Сценарий E1.CMP-02: Disk.Create с project_id

**ID**: E1.CMP-02
**Тип**: Happy path

**Given** prj `prj_default` существует, image `ub-2204` присутствует

**When** клиент шлёт `POST /compute/v1/disks`:
```json
{
  "name": "boot-disk-01",
  "projectId": "prj_default",
  "zoneId": "kacho-zone-a",
  "size": "10Gi",
  "typeId": "network-ssd",
  "imageId": "..."
}
```

**Then** Disk создаётся успешно, row содержит `project_id='prj_default'`
**And** worker делает `projectClient.Exists("prj_default")` → success
**And** Operation помечается done

#### Сценарий E1.CMP-03: Image.Create — partial UNIQUE сохраняет семантику family-uniqueness в project scope

**ID**: E1.CMP-03
**Тип**: UNIQUE constraint preservation

**Given** в kacho-compute есть Image `(id=img-1, project_id=prj-acme, family=ubuntu-22-04)`

**When** клиент шлёт Create Image с `name='img-2', project_id='prj-acme', family='ubuntu-22-04'`

**Then** Image создаётся (имена разные, UNIQUE `(project_id, name)` partial allow)
**And** `images_family_idx` (composite `(project_id, family, created_at DESC) WHERE family <> ''`) содержит обе записи
**And** «latest family image» query (`SELECT ... ORDER BY created_at DESC LIMIT 1`) использует этот индекс

### 6.6 Use-case update — kacho-loadbalancer (2 сценария)

#### Сценарий E1.LB-01: NLB.Create с project_id

**ID**: E1.LB-01
**Тип**: Happy path (loadbalancer)

**Given** в kacho-iam — `prj_default`
**And** в kacho-vpc — Subnet `e9b-sub1` с `project_id='prj_default'`
**And** в kacho-loadbalancer есть TargetGroup `tg-1` в `prj_default`

**When** клиент шлёт `POST /loadbalancer/v1/networkLoadBalancers`:
```json
{
  "name": "nlb-01",
  "projectId": "prj_default",
  "regionId": "kacho-region-1",
  "listenerSpecs": [...],
  "attachedTargetGroups": [{"targetGroupId": "tg-1"}]
}
```

**Then** sync-валидация проходит
**And** worker делает `projectClient.Exists("prj_default")` в kacho-loadbalancer → success
**And** NLB создаётся с `project_id='prj_default'`

#### Сценарий E1.LB-02: TargetGroup.Create — UNIQUE (project_id, name)

**ID**: E1.LB-02
**Тип**: UNIQUE constraint after rename

**Given** существует TargetGroup `(id=tg-1, project_id='prj_default', name='backend-pool')`

**When** клиент шлёт Create новой TargetGroup с теми же `project_id='prj_default'`, `name='backend-pool'`

**Then** worker пытается INSERT → 23505 (UNIQUE violation)
**And** возвращает `ALREADY_EXISTS "Target group with name 'backend-pool' already exists in project 'prj_default'"` (text YC-style)
**And** Operation помечается failed

### 6.7 api-gateway routing (2 сценария)

#### Сценарий E1.GW-01: REST query-param projectId работает

**ID**: E1.GW-01
**Тип**: Routing happy

**Given** gateway зарегистрировал regenerated proto-stubs (после PR #2)
**And** kacho-vpc запущен с переименованными колонками

**When** клиент шлёт `GET /vpc/v1/networks?projectId=prj_default`

**Then** gateway маршрутизирует на `NetworkService.List(ListNetworksRequest{ProjectId: "prj_default"})`
**And** возвращается список сетей в этом project
**And** HTTP-status 200

#### Сценарий E1.GW-02: Legacy query-param folderId возвращает ошибку или игнорируется

**ID**: E1.GW-02
**Тип**: Routing negative — backward-compat policy enforcement

**Given** gateway зарегистрировал ТОЛЬКО новые proto-stubs (нет folderId-параметра)

**When** клиент шлёт `GET /vpc/v1/networks?folderId=fld-old`

**Then** grpc-gateway игнорирует unknown query-param `folderId`
**And** `ListNetworksRequest.ProjectId` равен `""`
**And** сервис возвращает `InvalidArgument "projectId is required"` либо (если List допускает пустой scope — depends on existing service rule) возвращает unfiltered list
**And** в любом случае — НЕ silent-resolution через старый folder_id

(Текст ошибки финализируется по реальному поведению существующего `NetworkService.List` — если он допускает list-without-folder-filter сейчас, поведение симметрично переименовывается; если нет — `InvalidArgument`.)

### 6.8 Backward-compat (3 сценария)

#### Сценарий E1.BC-01: Старый клиент со `{"folderId": "..."}` body — InvalidArgument

**ID**: E1.BC-01
**Тип**: Hard-break enforcement (backward-compat layer)

> **Различение E1.PRO-03 vs E1.BC-01** (IMPORTANT 7 v1 review): оба сценария тестируют поведение
> при старом payload `{"folderId":"..."}`, но фокус разный:
> - **E1.PRO-03 (proto wire-format layer)**: фиксирует, что grpc-gateway правильно демаршалит
>   обе варианта (новый `projectId` → success path; старый `folderId` → unknown field, drop,
>   `ProjectId=""`). Тест на корректность proto wire / grpc-gateway JSON marshaller.
> - **E1.BC-01 (backward-compat policy layer)**: фиксирует, что policy — **hard-break**, а не
>   silent-accept; пользователь получает явную ошибку, что мигрировать; sync-validation падает с
>   YC-style текстом «projectId is required», Operation НЕ создаётся.
>
> Оба нужны как независимые проверки (одно — wire-format, второе — policy enforcement).

**Given** клиент использует legacy JSON-body (не обновился к новому контракту)

**When** клиент шлёт `POST /vpc/v1/networks` с:
```json
{"name": "old-style", "folderId": "fld-001"}
```

**Then** grpc-gateway demarshals → `CreateNetworkRequest{Name: "old-style", ProjectId: ""}` (folderId — unknown field, drop)
**And** sync-validation падает: `InvalidArgument "projectId is required"`
**And** HTTP-status 400
**And** Operation **не создаётся**

#### Сценарий E1.BC-02: Wire-format gRPC client (по field-number) — accepted (bytes-compat)

**ID**: E1.BC-02
**Тип**: wire-compat for protobuf binary

**Given** existing gRPC binary client сериализует с старой схемой `folder_id = 2`
**And** на wire: tag=2, type=string, value="prj_default"

**When** клиент посылает binary protobuf payload

**Then** новый сервер декодирует tag=2 как `project_id` (имя поля не передаётся в proto wire-format — только tag-number)
**And** `req.ProjectId = "prj_default"`
**And** запрос проходит как валидный

(Это нормальное поведение proto3 — wire-compat by tag-number. JSON-API ломается, но gRPC binary
работает. Acceptable.)

#### Сценарий E1.BC-03: kacho-resource-manager остаётся live, отвечает на legacy запросы

**ID**: E1.BC-03
**Тип**: RM live during E1

**Given** kacho-resource-manager задеплоен и работает
**And** kacho-vpc / compute / loadbalancer **больше его не зовут**

**When** external клиент шлёт `GET /resource-manager/v1/folders` напрямую

**Then** RM отвечает 200 + список folders (если есть)
**And** ничего в kacho-vpc/compute/lb не сломалось

**When** инспектируется Prometheus

**Then** `kacho_resource_manager_grpc_server_handled_total{grpc_method="Exists"}` counter после E1
после момента apply миграций **не растёт** (peer-сервисы не зовут)
**And** counter `kacho_resource_manager_grpc_server_handled_total{grpc_method="Get"}` растёт только при прямых external запросах

### 6.9 Newman regression (3 сценария)

#### Сценарий E1.NEW-01: kacho-vpc newman cases зелёные с projectId

**ID**: E1.NEW-01
**Тип**: Newman regression

**Given** все `tests/newman/cases/*.py` в kacho-vpc обновлены: `folderId` → `projectId`
**And** environments JSON содержит `existingProjectId=prj_default`
**And** dev-стенд поднят, kacho-iam seed'нул `prj_default`

**When** запускается `python3 tests/newman/scripts/gen.py && tests/newman/scripts/run.sh`

**Then** все ~736 newman test-кейсов (test-case == один Postman request с pre-/post-scripts) проходят (0 fail)
**And** в `out/summary.txt`: `Pass: 3380+ / Fail: 0` — общее число **ассертов** (один кейс содержит ~4-5 ассертов: status-code, response-schema, response-body fields, side-effect verification, и т.п.); т.е. ~736 test-cases × ~4.6 assertions/case ≈ 3380+ assertions total. Метрика `Pass: 3380+` — total assertions; `cases ran: 736` — test count (IMPORTANT 9 v1 review разъяснение).
**And** **никакая запись** в `out/*.json` не содержит строки `folderId` в request bodies (только historic test names allowed — search with `grep -r 'folderId' out/ | grep -v '^\s*$'` returns clean)

#### Сценарий E1.NEW-02: kacho-compute newman cases зелёные

**ID**: E1.NEW-02
**Тип**: Newman regression (compute)

**Given** все `tests/newman/cases/*.py` (compute) обновлены: `folderId` → `projectId`
**And** environments JSON содержит `existingProjectId=prj_default`

**When** запускается newman regression suite kacho-compute

**Then** все existing compute newman кейсы проходят (0 fail)
**And** test report содержит ассерты с `projectId`-полями

#### Сценарий E1.NEW-03: kacho-loadbalancer newman cases зелёные

**ID**: E1.NEW-03
**Тип**: Newman regression (loadbalancer)

**Given** existing newman suite для loadbalancer (если есть; **иначе** — заведён follow-up KAC-N issue ДО merge KAC-106 PR с обязательством добавить минимум 1 happy + 1 negative newman case в течение того же спринта; формулировка `«out-of-scope skip»` ЗАПРЕЩЕНА в commit-message / PR-description — запрет #11 workspace `CLAUDE.md`)
**And** updated к projectId

**When** запускается suite

**Then** все cases проходят
**And** UUID-to-TEXT migration (Decision D-2 / Scenario E1.LB-04) verified: новые project_id строки длиной 20 chars принимаются Postgres

#### Сценарий E1.LB-04: UUID → TEXT type migration верифицируется

**ID**: E1.LB-04
**Тип**: Type migration

**Given** до E1: колонка `target_groups.folder_id` имеет тип `UUID`
**And** в БД есть существующие rows с валидными UUID-folder_id'ами

**When** применяется миграция `0005_rename_folder_to_project.sql` в kacho-loadbalancer

**Then** колонка `target_groups.project_id` создаётся как `text`
**And** `UPDATE target_groups SET project_id = folder_id::text` — UUID кастится в text-представление (`xxxxxxxx-xxxx-...`)
**And** `ALTER COLUMN project_id SET NOT NULL` проходит
**And** колонка `folder_id` дропается

**When** клиент создаёт новый TargetGroup с `project_id="prj_default"` (20-char crockford)

**Then** INSERT проходит — `text` тип принимает любую строку
**And** `SELECT project_id FROM target_groups` возвращает 20-char строку без UUID-cast

**Policy: down-migration для UUID → TEXT type change** (IMPORTANT 13 v1 review):
- Down-направление миграции `0006_rename_folder_to_project.sql` в loadbalancer **НЕ поддерживается**
  для type-change компонента: однажды переключив колонку с `UUID` на `TEXT` и записав туда новые
  20-char crockford-base32 строки (формально не валидные UUID-v4 / UUID-v7), back-cast `text::uuid`
  упадёт с `22P02 invalid input syntax for type uuid`.
- Down-миграция предлагает только symmetrical RENAME (project_id → folder_id) без type-cast — но
  это **оставит TEXT-колонку под именем folder_id**, что нарушит существующую схему `UUID`-типа
  старого кода. Поэтому down-flow для loadbalancer-rename **запрещён** в production-flavored
  использовании; для dev — приемлемо использовать `make dev-down -v && make dev-up` для full
  recreate БД.
- В down-секции миграции добавляется `RAISE EXCEPTION 'down migration not supported for type-change
  UUID→TEXT; recreate DB instead'` (или эквивалент в goose down-stub).
- Зафиксировано как **расширение D-2** (`§2.D-2 — Two-step ALTER…`): для kacho-loadbalancer
  down-flow type-change не reversible. В D-2 sentence добавляется ссылка на этот override.

### 6.10 Сценарии cross-project enforcement (D-5)

#### Сценарий E1.XPR-01: Subnet.Create в Network другого project — отвергается

**ID**: E1.XPR-01
**Тип**: Cross-project rejection

**Given** Network `enp-aaa` в `prj-acme`
**And** клиент пытается создать Subnet с `network_id='enp-aaa'`, но `project_id='prj-other'`

**When** клиент шлёт `POST /vpc/v1/subnets`:
```json
{
  "name": "wrong-project-subnet",
  "projectId": "prj-other",
  "networkId": "enp-aaa",
  "zoneId": "kacho-zone-a",
  "v4CidrBlocks": ["10.0.0.0/24"]
}
```

**Then** sync-валидация проходит (оба ID непусты)
**And** worker делает `projectClient.Exists("prj-other")` → если existing → `(true, nil)`
**And** `INSERT INTO kacho_vpc.subnets ...` — триггер `subnets_project_matches_network_trg` срабатывает
**And** PostgreSQL поднимает `RAISE EXCEPTION ... USING ERRCODE = '23514'`
**And** `wrapPgErr` маппит 23514 → `InvalidArgument "child resource project does not match parent network project"`
**And** Operation помечается failed с этим текстом

#### Сценарий E1.XPR-02: SecurityGroup в Network другого project — отвергается

**ID**: E1.XPR-02
**Тип**: Cross-project rejection (SG)

**Given** Network `enp-aaa` в `prj-acme`

**When** клиент шлёт CreateSecurityGroup с `network_id=enp-aaa, project_id=prj-other`

**Then** триггер `security_groups_project_matches_network_trg` срабатывает
**And** Operation помечается `InvalidArgument`

### 6.11 Сценарии corelib (D-6)

#### Сценарий E1.COR-01: Operations.project_id заполняется во всех 3 сервисах

**ID**: E1.COR-01
**Тип**: corelib operations.project_id end-to-end

**Given** kacho-vpc / compute / loadbalancer применили corelib-synced миграцию `operations_project_id.sql` (per §5.0 таблица — `0003` в vpc/rm, `0009` в compute, `0005` в loadbalancer)
**And** clients создают ресурсы в `prj_default`

**When** клиент создаёт Network в vpc, Instance в compute, NLB в loadbalancer

**Then** в `kacho_vpc.operations` есть запись с `project_id='prj_default'`
**And** аналогично в `kacho_compute.operations`, `kacho_loadbalancer.operations`
**And** `SELECT * FROM operations WHERE project_id = 'prj_default'` работает в каждой БД и использует index `operations_project_id_idx`
**And** UI запрос `OperationService.List(project_id='prj_default')` через api-gateway возвращает все операции в этом project (по mux'у — отдельные запросы в каждый сервис, потом merge)

### 6.12 Сценарии smoke (deploy)

#### Сценарий E1.SMK-01: make dev-up поднимает обновлённые сервисы

**ID**: E1.SMK-01
**Тип**: Smoke deploy

**Given** все 7 PR'ов смержены в main соответствующих репо
**And** kacho-deploy/values.yaml обновлены (KACHO_*_IAM__ENDPOINT, no RM endpoints)

**When** запускается `cd kacho-deploy && make dev-down -v && make dev-up`

**Then** все pods становятся `Ready`:
  - `kacho-iam-0` Ready (E0 baseline)
  - `kacho-vpc-0` Ready (с новыми миграциями `0003_operations_project_id` + `0004_rename_folder_to_project`)
  - `kacho-compute-0` Ready (с новыми миграциями `0009_operations_project_id` + `0010_rename_folder_to_project`)
  - `kacho-loadbalancer-0` Ready (с новыми миграциями `0005_operations_project_id` + `0006_rename_folder_to_project`)
  - `kacho-resource-manager-0` Ready (live, но peer-сервисы не зовут)
  - `kacho-api-gateway-0` Ready
**And** `curl http://api-gateway:18080/healthz` → 200
**And** `make psql SVC=vpc` → `\d kacho_vpc.networks` показывает `project_id`, не `folder_id`

#### Сценарий E1.SMK-02: end-to-end smoke — создать project, создать network, создать subnet, создать instance

**ID**: E1.SMK-02
**Тип**: End-to-end smoke

**Given** dev-стенд поднят
**And** через api-gateway доступен `/iam/v1/projects`, `/vpc/v1/networks`, etc.

**When** клиент выполняет:
1. `POST /iam/v1/projects` → создаётся `prj-smk-01` в `acc_default`.
2. `POST /vpc/v1/networks` с `projectId="prj-smk-01"` → создаётся Network `enp-XXX`.
3. `POST /vpc/v1/subnets` с `projectId="prj-smk-01", networkId="enp-XXX"` → создаётся Subnet `e9b-YYY`.
4. `POST /compute/v1/instances` с `projectId="prj-smk-01"` ссылаясь на subnet → создаётся Instance.

**Then** все 4 операции возвращают `Operation` объекты
**And** все 4 Operations через `OperationService.Get(opID)` финализируются с `done=true`
**And** созданные ресурсы видны через `Get` RPC
**And** `kacho_resource_manager` НЕ получал ни одного gRPC-запроса (verified через Prometheus / логи)

### 6.13 Сценарии grep-clean (DoD #6)

#### Сценарий E1.GRP-01: Нет упоминаний folder_id/folderId в публичных API контрактах

**ID**: E1.GRP-01
**Тип**: Code hygiene / DoD enforcement

**Given** все 7 PR'ов смержены

**When** запускается:
```bash
cd kacho-workspace
grep -rin 'folder_id\|FolderID\|folderId' \
    project/kacho-vpc/ \
    project/kacho-compute/ \
    project/kacho-loadbalancer/ \
    --exclude-dir=vendor \
    --exclude-dir=gen \
    --exclude="0001_initial.sql" \
    --exclude="0002_*.sql"   # exclude unchanged migrations (запрет #5)
```

**Then** output **пустой** (либо содержит только matches в historic test names, commit messages, deprecated comments что explicit allow-list)
**And** `grep -rin 'folder_id\|folderId' project/kacho-proto/proto/kacho/cloud/{vpc,compute,loadbalancer}/v1/` — пустой
**And** vault check: `grep -rin 'folder_id' obsidian/kacho/{resources,edges}/` — должен содержать только пометки `(legacy, see KAC-106)` либо быть пустым

#### Сценарий E1.GRP-02: Все 3 backend-сервиса НЕ импортируют RM proto-stubs

**ID**: E1.GRP-02
**Тип**: Dependency cleanup

**Given** все 7 PR'ов смержены

**When** запускается:
```bash
grep -rin 'kacho/cloud/resourcemanager' project/{kacho-vpc,kacho-compute,kacho-loadbalancer}/internal/
```

**Then** output **пустой**
**And** `cat project/kacho-vpc/go.mod | grep PRO-Robotech/kacho-resource-manager` — пустой (нет `replace ../kacho-resource-manager`)
**And** аналогично для compute, loadbalancer

---

## 7. Definition of Done (полный список)

Эпик KAC-106 (E1) **не закрывается**, пока все нижеперечисленные пункты не зелёные.

### 7.1 Code

- [ ] **DoD-1**: Все 8 таблиц в `kacho_vpc` переименованы (`folder_id` → `project_id`, индексы переименованы, outbox-триггер пересоздан).
- [ ] **DoD-2**: Все 4 таблицы в `kacho_compute` переименованы (disks/images/snapshots/instances), включая composite index `images_family_idx`.
- [ ] **DoD-3**: Все 2 таблицы в `kacho_loadbalancer` переименованы (target_groups, network_load_balancers); тип колонки изменён `UUID` → `TEXT` (E1.LB-04).
- [ ] **DoD-4**: Proto-поля во всех 22+ .proto-файлах vpc/compute/loadbalancer переименованы; `gen/go/...` регенерирован.
- [ ] **DoD-5**: `ProjectClient` (с TTL+LRU кешем) полностью заменяет `FolderClient` в всех 3 backend-сервисах.
- [ ] **DoD-6**: `grep -rin 'folder_id\|folderId\|FolderID' project/{kacho-vpc,kacho-compute,kacho-loadbalancer}/` — пусто (за исключением неизменяемых historic миграций 0001-0002 — запрет #5).
- [ ] **DoD-7**: kacho-iam `ProjectService.Get` отвечает корректно на peer-вызовы.
- [ ] **DoD-8**: Backward-compat: old JSON payload `{folderId}` → явная ошибка `InvalidArgument "projectId is required"`, **не** silent-accept.
- [ ] **DoD-9**: Cross-project enforcement (D-5): Subnet/SG/RT/PE в Network другого project → `InvalidArgument` (DB triggers).
- [ ] **DoD-10**: `operations.project_id` колонка добавлена в corelib + synced во все 4 потребителя (vpc/compute/loadbalancer/resource-manager).

### 7.2 Tests

- [ ] **DoD-11**: Все integration-тесты в kacho-vpc / kacho-compute / kacho-loadbalancer зелёные (testcontainers Postgres, новая schema с `project_id`).
- [ ] **DoD-12**: Все newman cases во всех 3 сервисах зелёные с `projectId` payload (E1.NEW-01/02/03).
- [ ] **DoD-13**: corelib operations integration-test (E1.COR-01) зелёный.
- [ ] **DoD-14**: Concurrent-race test для cross-project trigger: parallel Subnet.Create в Network А и моментальный Move(Network А → другой project) — проверить, что D-5 trigger катчит inconsistency.
- [ ] **DoD-15**: `make e2e-test` smoke (E1.SMK-02) проходит чисто.

### 7.3 Deploy & operations

- [ ] **DoD-16**: `make dev-up` поднимает все обновлённые сервисы; healthz зелёный на каждом (E1.SMK-01).
- [ ] **DoD-17**: kacho-resource-manager остаётся live в стенде, но Prometheus counter `kacho_resource_manager_grpc_server_handled_total` от peer-сервисов = 0 (verified в течение 5 минут после smoke).
- [ ] **DoD-18**: Env vars `KACHO_*_RM__ENDPOINT` / `RESOURCE_MANAGER_GRPC_ADDR` удалены из helm values трёх сервисов; добавлены `KACHO_*_IAM__ENDPOINT` + `KACHO_*_PROJECT_CACHE_*`.

### 7.4 Docs & vault

- [ ] **DoD-19**: Все vault-entries `resources/<svc>-<resource>.md` обновлены (folder → project).
- [ ] **DoD-20**: 3 vault entries `edges/<svc>-to-rm-folder-exists.md` пересозданы как `edges/<svc>-to-iam-project-validate.md`.
- [ ] **DoD-21**: `KAC/KAC-106.md` создана с финальными PR-URL'ами всех 7 PR + status updated.
- [ ] **DoD-22**: Этот документ финализирован, status = `APPROVED`.

### 7.5 Cross-repo housekeeping

- [ ] **DoD-23**: CI `ref:` строки в `.github/workflows/ci.yaml` каждого репо после merge **возвращены** на `ref: main` (или удалены целиком, default). Verify-command (IMPORTANT 11 v1 review):
  ```bash
  for r in kacho-corelib kacho-proto kacho-vpc kacho-compute kacho-loadbalancer kacho-api-gateway kacho-deploy; do
      echo "=== $r ==="
      grep -n "ref:" project/$r/.github/workflows/*.yaml 2>/dev/null | grep -v "main" | grep -v "^$"
  done
  # Expected: empty output (или строки с ref: main только)
  ```
- [ ] **DoD-24**: Ветки `KAC-106` в каждом из 7 репо **удалены** после merge (см. workspace `CLAUDE.md` §«git-флоу под задачу»). Verify: `for r in ...; do (cd project/$r && git branch -r | grep KAC-106); done` → empty.
- [ ] **DoD-25**: `buf.yaml` ignore-flag `FIELD_SAME_NAME` снят после merge PR #2.
- [ ] **DoD-26**: **api-gateway prefix routing для `prj`** (BLOCKER 4 fix v1 review): **N/A в текущей архитектуре**. Проверено: `kacho-api-gateway/internal/restmux/mux.go` НЕ содержит prefix-router code path для project-id; `prj`-prefix используется только в `opsproxy/proxy.go::prefixToBackend` для `Operation.id`-prefix routing (а не для resource-id). Project IDs (`prj…`) приходят в request bodies как параметры RPC — gateway проксирует по имени RPC (`iam.v1.ProjectService.Get`, `vpc.v1.NetworkService.Create` с `project_id` field в body), не по ID-prefix. Подтверждение: `grep -rn "prj\|projectId" project/kacho-api-gateway/internal/restmux/` — пустое (no prefix-routing code для project IDs). DoD-26 = «зафиксировано, что prefix routing для `prj` НЕ требуется в plumbing sense; роутинг проходит по RPC name».
- [ ] **DoD-27**: **Migration numbering verified** против реального состояния каждого репо (BLOCKER 1 fix v1 review): каждый PR с миграцией обязан содержать в описании вывод `ls internal/migrations/` ДО и ПОСЛЕ изменения, и эти номера обязаны соответствовать таблице §5.0. Reviewer обязан reject'нуть PR с расхождением.

---

## 8. Backward-compat policy и текст ошибок (YC-стилистика)

### 8.1 Сводная таблица текстов ошибок

| Сценарий                                              | Code               | Текст                                                                                  |
|-------------------------------------------------------|--------------------|----------------------------------------------------------------------------------------|
| projectId пустой / отсутствует в request              | INVALID_ARGUMENT   | `"projectId is required"`                                                              |
| projectId формально невалидный (не `prj` prefix)      | INVALID_ARGUMENT   | `"invalid project id '<X>'"` (по аналогии с `corevalidate.ResourceID` в VPC)            |
| projectId well-formed, но в kacho-iam отсутствует     | NOT_FOUND          | `"Project %s not found"` (YC-style)                                                    |
| kacho-iam недоступен (Unavailable)                    | UNAVAILABLE        | `"project check: rpc error: code = Unavailable ..."`                                   |
| Child resource project ≠ parent network project       | INVALID_ARGUMENT   | `"child resource project does not match parent network project"`                       |
| Duplicate (project_id, name)                          | ALREADY_EXISTS     | `"<resource> with name '<name>' already exists in project '<project_id>'"`             |
| Old `folderId` JSON-payload sent                      | INVALID_ARGUMENT   | `"projectId is required"` (тот же, что для otherwise empty projectId)                  |
| Cross-service cascade attempt (e.g. kacho-iam.Project.Delete trying to cascade) | — (запрещено)  | enforce запрет #4 — kacho-iam просто удаляет project, peer-сервисы переживают |

### 8.2 Backward-compat дополнительно

- **No silent-accept** старого `folderId` — Hard-break (см. Decision D-1).
- **No alias** в proto.
- **Wire-format protobuf binary** — wire-compat по tag-number (gRPC binary clients продолжают работать; см. E1.BC-02).
- **JSON-API через grpc-gateway** — ломается (явный signal клиенту обновить контракт).
- **kacho-resource-manager API endpoints** — `/resource-manager/v1/folders/*` остаются доступными (live до E5).

### 8.3 Migration window guidance (для prod-инсталляции в будущем)

(Не применимо к E1 в текущем dev-only-режиме, но фиксируется для E5 / последующих фаз):

1. До миграции — все peer-сервисы вызывают `kacho-iam.ProjectService.Get` через cache (TTL=30s).
   До этого момента в `kacho-iam.projects` уже должны быть Project'ы (через E5 data-migration
   `INSERT INTO kacho_iam.projects SELECT id, account_id, name, ... FROM kacho_resource_manager.folders`).
2. `goose up` миграция rename — single-TX, applied in seconds для dev / в зависимости от data-size для prod.
3. Rolling restart peer-сервисов с новой схемой / новым кодом.
4. Verify через E1.SMK-01 / E1.SMK-02.

---

## 9. Risks и mitigations

| Risk                                                                           | Likelihood | Impact   | Mitigation                                                                                                                 |
|--------------------------------------------------------------------------------|------------|----------|----------------------------------------------------------------------------------------------------------------------------|
| Outbox notify function пересоздана с ошибкой (forgotten field)                  | Medium     | High     | Code review + integration test, проверяющий outbox payload (`{project_id: ...}` присутствует, не `{folder_id: ...}`)        |
| Newman cases пропустили какой-нибудь `folderId` (тест проходит, но не валидирует) | Medium     | Medium   | grep-clean check на `out/*.json` после run (E1.NEW-01 last assertion)                                                       |
| Cross-project triggers (D-5) ломают legitimate test cases                       | Low        | High     | Concurrent-race integration-test (DoD-14); внимательное review trigger логики                                              |
| Loadbalancer UUID → TEXT type change ломает existing data                       | Low        | High     | E1.LB-04 verification; в dev данные пересоздаются, в prod — пока нет данных                                                |
| kacho-iam перегружается под burst из peer-кешей (cold start)                    | Low        | Medium   | TTL+LRU кеш с positive 30s — 95%+ hit rate под нагрузкой; pre-warm не требуется                                            |
| `make sync-migrations` забывает скопировать новый corelib `0002_operations_project_id.sql` в один из 4 потребителей | Medium | Medium | Make-target обязателен в DoD-10; CI check `find migrations/common -name '*.sql' \| count` равен `find project/<svc>/migrations -name '*operations*' \| count` |
| Регресс existing newman cases из-за переименования env-var `existingFolderId` → `existingProjectId` | Medium | Low | Поддерживать ENV-alias `existingFolderId=existingProjectId` ВРЕМЕННО (один спринт), затем удалить |
| kacho-ui не успевает мигрировать на projectId payload в этом же эпике           | Low        | High     | UI работа — параллельно в E4; до E4 — minimal UI patch для смены `folderId` → `projectId` в API-calls + ENV-alias в gateway |
| Race-condition: Project удалён в kacho-iam пока worker peer создаёт ресурс под него | Medium | Low      | Cache TTL 30s покрывает; eventual consistency window. Worker fail = Operation failed (OK)                                  |
| buf breaking ignore-flag забыли снять после merge                              | Low        | Low      | DoD-25; post-merge hook на github actions check (manual)                                                                   |
| **User-confusion**: ресурсы успешно создаются 30s после удаления project (cache stale window — E1.CLI-05 / D-3) | Medium | Low | Поведение задокументировано в D-3 / E1.CLI-05 как «acceptable eventual consistency window». UI должен показывать project как «deleted» сразу после DELETE (по своему own read pattern, не через peer), чтобы пользователь не пытался создавать новые ресурсы. После 30s window — `NotFound` возвращается, ресурс не создаётся. Документация для UI и tooling: «после ProjectService.Delete рекомендуется НЕ создавать новые ресурсы в peer-сервисах в течение ~30s».|

---

## 10. Out of scope (явно отложено)

1. **Выключение kacho-resource-manager** (`Gone 410`, drop helm chart, drop БД) — E5 (KAC-110).
2. **Реальная prod-data migration** `folders → projects` — E5; в E1 на dev-стенде data пересоздаётся.
3. **Auth / authz / Zitadel / OpenFGA** — E2/E3.
4. **Operation.principal заполнение реальным user'ом** — E4; в E1 stub `'system'` остаётся.
5. **UI signup-flow + IAM admin block** — E4.
6. **kacho-yc-shim** (CLI compat `yc --folder-id` → `--project-id`) — out of scope всей фазы 2.0.
7. **Cross-account ресурсный sharing** — out of scope фазы 2.0 (один Account = один tenant).
8. **Quota / billing на уровне Project** — отдельная фаза.
9. **MFA / WebAuthn** — Zitadel feature, не enforce'им в Kachō.
10. **Audit-storage сервиса** — отдельная фаза `kacho-audit`.
11. **Renaming kacho-resource-manager → kacho-something-else** — не делается; репо остаётся, deprecated.
12. **Изменение в `kacho-vpc-implement` (data-plane)** — он не использует folder_id вообще, не затрагивается.
13. **Изменение в `kacho-vpc-operator`/`kacho-compute-operator`** (если такие репо есть в workspace) — out of scope, проверить отдельно при доступности.
14. **Sync KAC-113 в legacy сервисы** (BLOCKER 2 fix v1 review) — **отдельная prerequisite-задача-blocker**, делается ДО E1 start. KAC-113 (operations.principal) уже занял миграционные слоты 0002 в corelib/vpc/rm + 0008 в compute + 0004 в loadbalancer; sync во все 4 backend-сервиса завершён на 2026-05-17 (task #26 completed). E1 стартует только при подтверждении этого факта.

---

## 11. Decision Log (нормативный, источник истины для реализации)

| ID  | Decision                                                                        | Rationale                                                                | Sections          |
|-----|---------------------------------------------------------------------------------|--------------------------------------------------------------------------|-------------------|
| D-1 | Hard-rename (Option A), no dual-column                                          | pre-1.0, нет prod-clients, чистота кодовой базы                          | §2.D-1, §4.3      |
| D-2 | Two-step ALTER (ADD/UPDATE/DROP), не RENAME COLUMN                              | data preservation pattern, outbox trigger pareto, prod-safe              | §2.D-2, §5.3.1    |
| D-3 | TTL+LRU cache в каждом peer (positive 30s / negative 5s / maxSize 10k / fail-open) | proven pattern из FolderCache; performance-cost-balance                  | §2.D-3, §6.3      |
| D-4 | Project.Move не cascade'ит на peer-сервисы                                       | DB-per-service, peer хранит только project_id, не account_id             | §2.D-4, §6.VPC-02 |
| D-5 | Cross-project refs (Subnet/SG/RT/PE in Network) запрещены DB-trigger'ом         | within-service invariant; запрет #10 (no software-only)                  | §2.D-5, §6.XPR-01 |
| D-6 | `operations.project_id` колонка в corelib operations table                       | UI filtering convenience; one-shot corelib mini-PR                        | §2.D-6, §6.COR-01 |
| D-7 | Peer-сервисы зовут `kacho-iam.ProjectService.Get`, не `Exists`                  | reuse existing E0 API; bandwidth некритично с кешем                       | §2.D-7            |
| D-8 | Network.Move (и parent.Move в любом сервисе) с existing children → REJECT       | single-row CAS pattern preserved; согласуется с FK ON DELETE RESTRICT     | §2.D-8, §6.4 (E1.VPC-05) |
| D-9 | parent.project_id immutable вне worker-path (D-9 trigger + SET LOCAL bypass)    | defense-in-depth для D-8; direct admin psql UPDATE → 42501                | §2.D-9            |

Реализация, расходящаяся с любым из D-1..D-9, — нарушение acceptance.

---

## 12. Связь с регламентом (повтор для acceptance-reviewer)

Этот раздел дублирует §1 в табличной форме для ускорения review.

| Регламент / запрет | Сценарий, который верифицирует |
|---|---|
| Запрет #1 (acceptance-gate)            | данный документ                                  |
| Запрет #2 (no "yandex")                | manual grep по PR diff'ам                        |
| Запрет #3 (no ORM)                     | migrations handwritten; review SQL files          |
| Запрет #4 (no cross-service cascade)   | E1.VPC-04, §10                                    |
| Запрет #5 (no edit applied migrations) | новая миграция 0003 (vpc/compute) / 0005 (lb)    |
| Запрет #6 (Internal.* не на TLS)       | не затрагивается; ProjectService.Get — public    |
| Запрет #8 (DB-per-service)             | no cross-DB FK; project_id хранится как TEXT     |
| Запрет #9 (async-only)                 | все Create/Update/Delete возвращают Operation     |
| Запрет #10 (within-service refs DB)    | D-5 triggers; UNIQUE constraints                 |
| Запрет #11 (tests in same PR)          | DoD-11/12/13/15; формулировка «follow-up» запрещена |

---

## 13. Acceptance gate

Этот документ переходит в статус `APPROVED` после `acceptance-reviewer` отдаёт `✅ APPROVED`
с conditions либо без.

**До APPROVED**: запрещено:
- Открывать ветки `KAC-106` в любом из 7 репо.
- Стартовать `superpowers:writing-plans` / `rpc-implementer` / `migration-writer` /
  `integration-tester` / `api-gateway-registrar` / `service-scaffolder`.
- Делать любые правки в `kacho-vpc/internal/migrations/`, `kacho-compute/internal/migrations/`,
  `kacho-loadbalancer/internal/migrations/`, `kacho-proto/proto/`.

**После APPROVED**: стандартный workflow per workspace `CLAUDE.md` §«Документооборот»:
1. `superpowers:writing-plans` — детальный план выполнения (опционально, для крупных).
2. Параллельно (но в порядке dependency graph):
   - kacho-corelib (PR #1) — `migration-writer` + `integration-tester`.
   - kacho-proto (PR #2) — `proto-sync` + `proto-api-reviewer`.
3. После #1, #2 merged:
   - kacho-vpc / compute / loadbalancer (PR #3,#4,#5 параллельно) — `migration-writer` + `rpc-implementer` + `integration-tester` + `db-architect-reviewer` + `go-style-reviewer`.
4. После #3-#5 merged: api-gateway (#6) — `api-gateway-registrar`.
5. После #6 merged: deploy (#7).
6. Финальный smoke E1.SMK-01/02 — заказчик подключается к проверке (per workspace `CLAUDE.md`).
7. Docs (#8) — обновление vault + этого acceptance + closing KAC-106.

---

## 14. Артефакты

### 14.1 Vault entries (создать/обновить в PR #8)

**Создать новые**:
- `obsidian/kacho/edges/vpc-to-iam-project-validate.md` (1-2KB; replaces `vpc-to-rm-folder-exists.md`).
- `obsidian/kacho/edges/compute-to-iam-project-validate.md`.
- `obsidian/kacho/edges/lb-to-iam-project-validate.md`.
- `obsidian/kacho/KAC/KAC-106.md` (per workspace `CLAUDE.md` §«KAC-тикеты — обязательный trail»).
- `obsidian/kacho/packages/vpc-internal-clients.md` (если ещё нет; описывает ProjectClient + CachedProjectClient pattern).
- `obsidian/kacho/packages/compute-internal-clients.md`.
- `obsidian/kacho/packages/lb-internal-clients.md`.

**Обновить existing**:
- `obsidian/kacho/resources/vpc-network.md` (FK contract field rename).
- `obsidian/kacho/resources/vpc-subnet.md` (cross-project trigger note).
- `obsidian/kacho/resources/vpc-address.md` (FK contract field rename).
- `obsidian/kacho/resources/vpc-route-table.md`, `vpc-security-group.md`, `vpc-gateway.md`,
  `vpc-private-endpoint.md`, `vpc-network-interface.md`.
- `obsidian/kacho/resources/compute-instance.md`, `compute-disk.md`, `compute-image.md`,
  `compute-snapshot.md`.
- `obsidian/kacho/resources/lb-nlb.md`, `lb-target-group.md`.
- `obsidian/kacho/rpc/vpc-network-service.md` и аналогичные RPC-карточки — обновить REST mapping.

**Удалить** (после verifying что заменены):
- `obsidian/kacho/edges/vpc-to-rm-folder-exists.md`
- `obsidian/kacho/edges/compute-to-rm-folder-exists.md`
- `obsidian/kacho/edges/lb-to-rm-folder-exists.md`

### 14.2 PR-list template (для KAC-106 YT-комментария)

```
# KAC-106 PR chain (per §5.0 migration numbering)

0. [PREREQ] KAC-113 (operations.principal columns) — MERGED ACROSS ALL 4 SERVICES
   (without this, corelib next-slot 0003 conflicts with already-merged 0002_operations_principal)
1. corelib (operations.project_id → 0003_operations_project_id.sql):  PRO-Robotech/kacho-corelib#<NN>
2. proto (folder_id → project_id):    PRO-Robotech/kacho-proto#<NN>
3. vpc (sync 0003 + rename 0004 + project client):  PRO-Robotech/kacho-vpc#<NN>
4. compute (sync 0009 + rename 0010 + project client): PRO-Robotech/kacho-compute#<NN>
5. loadbalancer (sync 0005 + rename 0006 + UUID→TEXT + project client): PRO-Robotech/kacho-loadbalancer#<NN>
6. api-gateway (routing — proto regen, no prefix-router changes per DoD-26): PRO-Robotech/kacho-api-gateway#<NN>
7. deploy (helm values + env vars):   PRO-Robotech/kacho-deploy#<NN>
8. workspace (docs + vault):          PRO-Robotech/kacho-workspace#<NN>
```

### 14.3 YT-tracking

- Tracking-issue: KAC-106 (этот эпик-таск).
- Parent epic: KAC-104.
- Blocked by: KAC-105 (E0 — Project ресурс live, merged, prereq satisfied) + **KAC-113** (operations.principal migration, занявший слоты 0002 в corelib/vpc/rm + 0008 в compute + 0004 в loadbalancer; должен быть **merged во все 4 backend-сервиса** ДО старта E1 кодинга — без этого corelib 0003_operations_project_id.sql и per-сервисные rename-миграции конфликтуют по нумерации; статус на 2026-05-17: merged, см. §5.0).
- Blocks: KAC-110 (E5 будет ждать E1).
- Sprint: текущий «Первый спринт» (board 183-12, sprint 186-22) — добавить через `Board kacho ...`.
- Поле «агент»: `acceptance-author` (этот), затем при code-phase — `migration-writer`,
  `rpc-implementer`, `integration-tester`, ревьюеры.

### 14.4 Артефакты в PR-комментариях (DoD)

Каждый из 7 PR обязан в описании содержать:
- Ссылка на этот acceptance: `Closes part of KAC-106 (acceptance §<N>)`.
- Список затронутых GWT-сценариев: `Verifies E1.MIG-01, E1.MIG-02, E1.CLI-01...`.
- Лог `make test` (integration + newman) — pass-fail tally в комментарии.
- Лог `make dev-up` smoke (для PR #7) — все pods Ready.

---

## 15. Changelog

| Версия | Дата       | Автор             | Что изменилось                                                                                                |
|--------|------------|-------------------|--------------------------------------------------------------------------------------------------------------|
| v0     | 2026-05-17 | acceptance-author | STUB — placeholder с scope/DoD/open-questions, без полных GWT                                                |
| v1     | 2026-05-17 | acceptance-author | **Полный документ**: 25+ GWT-сценариев (MIG 5, PRO 3, CLI 5, VPC 4, CMP 3, LB 3, GW 2, BC 3, NEW 3, XPR 2, COR 1, SMK 2, GRP 2 = 38 сценариев), 7 Decision Log entries, 8-PR cross-repo chain, полная migration strategy ADD/UPDATE/DROP, YC-style error texts, vault artefacts list, DoD из 25 пунктов |
| v2     | 2026-05-17 | acceptance-author | **Fixes по acceptance-reviewer v1 round 1** (5 blockers + 9 important + nits + resolved open Qs). Главное: см. §«Changelog v2 — overview правок» ниже. |

### Changelog v2 — overview правок (для acceptance-reviewer round 2)

**5 BLOCKERS fixed**:

1. **BLOCKER 1 (migration numbering)** — добавлен §5.0 с per-service таблицей реальных
   миграционных слотов на 2026-05-17 (после merge KAC-113). Все литералы `0002`/`0003`
   `operations_project_id.sql` и `0003`/`0005` `rename_folder_to_project.sql` в документе
   заменены на правильные: corelib `0003`, vpc `0003+0004`, compute `0009+0010`,
   loadbalancer `0005+0006`, resource-manager `0003` (sync-only). Добавлен **DoD-27**
   (migration numbering verified per PR через `ls internal/migrations/`).

2. **BLOCKER 2 (KAC-113 dependency)** — зафиксирована в `Blocked by` в header'е, в §10
   Out-of-scope item #14, в §14.2 PR-chain как PR-0 PREREQ, в §14.3 YT-tracking blocked-by.

3. **BLOCKER 3 (Network.Move с children)** — новый **Decision D-8** (REJECT, не cascade,
   не error-prone trigger): sync precheck в `NetworkService.Move::worker` через
   `Repo.Reader(ctx)`, плюс DB-trigger `networks_no_children_on_project_change_trg` как
   defense-in-depth. Новый GWT-сценарий **E1.VPC-05** (Network.Move с 3 subnets → FailedPrecondition).

4. **BLOCKER 4 (gateway prefix routing для `prj`)** — добавлен **DoD-26**: проверено
   фактическое состояние `kacho-api-gateway/internal/restmux/mux.go` — gateway НЕ использует
   prefix routing для project IDs, маршрутизация идёт по RPC name (proto-stubs регенерируются
   из PR #2); **N/A в plumbing sense**. Зафиксировано как resolved open Q #5.

5. **BLOCKER 5 (immutable parent.project_id на DB-уровне)** — новый **Decision D-9**:
   trigger `networks_project_id_immutable_trg` (BEFORE UPDATE OF project_id) с session-var
   guard `app.allow_parent_move`; worker делает `SET LOCAL app.allow_parent_move = 'true'` в TX'и
   Move'а. Direct admin `psql UPDATE` → 42501 (PermissionDenied). Симметрично может быть применено
   к compute/loadbalancer (в E1 их parent.Move'ов нет, добавится при появлении).

**9 IMPORTANTS fixed**:

- **6** (E1.PRO-01): уточнено правило `FIELD_LOWER_SNAKE_CASE` (`buf lint` BASIC rule).
- **7** (E1.BC-01 vs E1.PRO-03): добавлен note явно отделяющий wire-format layer (PRO-03)
  от backward-compat policy layer (BC-01) — оба нужны как независимые тесты.
- **8** (risk «user-confusion»): добавлена строка в §9 risk-table про 30s eventual consistency
  window при удалении project в kacho-iam и UI guidance.
- **9** (736 vs 3380): добавлено разъяснение «test-cases × ~4-5 assertions/case ≈ total assertions».
- **10** (Operations.project_id в RM): resolved через sync ДО E5 + drop в E5 (§16.3).
- **11** (DoD-23 grep): добавлен bash verify-snippet (for-loop по 7 repos).
- **12** (outbox triggers): все 8 outbox-триггеров vpc явно перечислены (вместо «similarly»).
  Также явно перечислены 5 D-5 child-project-matches triggers + D-8/D-9 triggers.
- **13** (loadbalancer down-migration policy): добавлена policy в E1.LB-04 — down НЕ
  поддерживается для type-change UUID→TEXT; goose down stub содержит RAISE EXCEPTION либо
  ссылку на `make dev-down -v`.
- **14** (E1.NEW-03 «follow-up»): заменено `«out-of-scope skip»` на `«follow-up KAC-N issue
  заведён ДО merge с обязательством добавить тесты в том же спринте»`; формулировка
  «out-of-scope skip» явно ЗАПРЕЩЕНА в commit-message / PR-description (запрет #11).

**Open Qs resolved**:

- **#3** (Operations.project_id в RM): RESOLVED — sync для consistency corelib-source, drop при E5.
- **#5** (api-gateway prefix routing): RESOLVED через DoD-26 (N/A — routing по RPC name, не prefix).
- **#6** (kacho-yc-shim): RESOLVED — verified, что shim mothballed (нет CI, нет в helm umbrella,
  нет depending consumers); E1 не затрагивает.

**Все остальные секции** (D-1..D-7, GWT scenarios E1.MIG-01..04 / PRO-01..03 / CLI-01..05 /
VPC-01..04 / CMP-01..03 / LB-01..02 / GW-01..02 / BC-01..03 / XPR-01..02 / COR-01 / SMK-01..02 /
GRP-01..02 / NEW-01..03 / LB-04) — без изменений по существу, только point-fixes по номерам миграций.

---

## 16. Открытые вопросы для acceptance-reviewer (приоритетные)

Несмотря на полностью описанный документ, эти вопросы могут потребовать pre-APPROVE дискуссии:

1. **UUID → TEXT в loadbalancer** (Scenario E1.LB-04 / §4.2 OPEN QUESTION) — подтверждение,
   что type change приемлем в одной миграции с rename. Альтернатива (keep UUID + format-mismatch
   с vpc/compute) хуже, но это явное structural отклонение.

2. **D-5 trigger на 5 child-tables** (subnets, security_groups, route_tables, private_endpoints,
   network_interfaces) — стоит ли verify через 5 отдельных integration-тестов или один-два
   достаточно? Если один — какие два child-types выбрать?

3. **Operations.project_id в kacho-resource-manager** — **RESOLVED v2** (IMPORTANT 10 v1 review):
   sync ДО E5 (RM остаётся live, peers не зовут, но колонка `project_id` добавляется в `kacho_resource_manager.operations` через `make sync-migrations` для consistency с corelib source-of-truth);
   default `''`, никогда не заполняется (RM не имеет concept of project — он управляет Folder'ами).
   Drop колонки — при E5 в одной миграции с drop всей RM-БД. Зафиксировано в §5.0 таблица
   (last column: «n/a (RM out of E1 rename-scope)») и §10 Out-of-scope item #14.

4. **Env-var alias `existingFolderId` в newman environments** — оставить on transition, удалить
   сразу? Risk #1: остаётся «жив» grep-clean, но `existingProjectId=existingFolderId` явный
   alias не путает. Risk #2: удалить сразу — простота, но если newman cases в каком-то месте
   используют `existingFolderId` (упустили в массовом rename) — упадут.

5. **api-gateway prefix routing** — **RESOLVED v2 через DoD-26** (BLOCKER 4 fix v1 review):
   N/A в текущей архитектуре. `kacho-api-gateway/internal/restmux/mux.go` НЕ использует prefix
   routing для project-id; `prj`-prefix фигурирует только в `opsproxy/proxy.go::prefixToBackend`
   (routing Operation.id, не resource-id). Project IDs (`prj…`) приходят как parameters RPC,
   gateway проксирует по имени RPC. См. DoD-26.

6. **kacho-yc-shim** — **RESOLVED v2**: `ls project/kacho-yc-shim/` показывает существующий код
   (buf.gen.yaml, endpoint/, gen/, iam/, Makefile, proto/, README.md, shimproxy/), НО:
   - НЕТ `.github/workflows/` директории (CI не зелёный, фактически не валидируется в pipeline);
   - НЕТ упоминания `yc-shim` в `kacho-deploy/helm/umbrella/values.dev.yaml` (не деплоится в стенде);
   - НЕТ зависимости от него у kacho-ui / tests / newman (`grep -rn yc-shim project/{kacho-ui,kacho-test,kacho-deploy}/` — empty);
   → **shim is mothballed / archive-only**, признан **архивом** до отдельного решения о
   возрождении. E1 НЕ затрагивает yc-shim; если в будущем он восстанавливается, его придётся
   обновить под новый projectId-контракт отдельным эпиком (out-of-scope E1, §10 item #6).

7. **Hostnames vpc-pods в helm** — `kacho-iam:9090` предполагает Service `kacho-iam` в том же
   namespace. Verify, что helm chart выкатывает Service с этим именем (E0 task — должно быть
   готово).

---

> **End of acceptance E1 (KAC-106) v2.** Передаётся `acceptance-reviewer` для review round 2.
> v2 покрывает все 5 BLOCKERS + 9 IMPORTANTS + nits + 3 resolved open Qs из v1 review feedback;
> overview всех изменений — §15 «Changelog v2».
