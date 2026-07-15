# Sub-phase RG-1 (Registry Repository config-overlay + explicit lifecycle + visibility) — Acceptance

> **Статус:** ✅ APPROVED (acceptance-reviewer, ревизия r2 — все `❌ CHANGES REQUESTED` адресованы; gate ban #1 ОТКРЫТ). Эпик: kacho-workspace#132.
> **Дата:** 2026-07-15
> **Ревизия r2:** rename-ephemeral auto-promote семантика + сценарий (A23, BLOCKING); registry-`DELETING`
> ACTIVE-guard (A24); X01 named verified-by (projection-audit gate + schema-review); A22 конкретные BVA-лимиты
> `corelib/validate` (64/63/63/256-rune); B13 inherited TTL/audience-enforcement note; D-5 «single-statement CAS»
> реконсиляция upsert(`INSERT`)-vs-rekey(`UPDATE`).
> **Ревьюер:** `acceptance-reviewer`
> **Эпик/тикет:** KAC-\<N\> (завести до старта кода; тип `feature`, кросс-репо)
> **Repos (порядок build-графа):** `kacho-proto` → `kacho-iam` (anon-token + `user:*` tuple governance) →
> `kacho-registry` (overlay/RPC/data-plane) → `kacho-api-gateway` (public RPC registration) →
> `kacho-deploy` → `kacho-workspace` (docs/vault)
> **Формат:** Given-When-Then (только markdown — без кода)
> **Источник эпика:** `docs/plans/registry-expansion-overview.md` §1 (Repository row), §2 «Repo-management»,
> §3 «Repository config overlay» / «Public / anonymous pull», §5 open-decisions #1 (overlay-vs-projection),
> #2 (public/anon), закрываемые этой под-фазой.
> **Нормативка (не дублируется в тело — ссылки):**
> - `.claude/rules/api-conventions.md` — flat-resource + async `Operation`, error-format/тексты, update_mask discipline, camelCase, timestamp-truncate.
> - `.claude/rules/data-integrity.md` §«Within-service инварианты — ТОЛЬКО на DB-уровне» (UNIQUE/CHECK/CAS), §«Cross-domain ссылки» (peer-validate, fail-closed `Unavailable`).
> - `.claude/rules/security.md` §«Internal-vs-external», §«Инфра-чувствительные данные», §«Hardening-инварианты» (#1 INTERNAL-no-leak, #3 object-scoped authz, #5 misleading-comment).
> - `.claude/rules/testing.md` — TDD RED-до-кода, integration+newman в том же PR, behaviour-level regression.
> - `docs/specs/02-data-model-and-conventions.md` §14 (коды ошибок).

---

## 0. Обзор

Сегодня `Repository` в `kacho-registry` — **read-only проекция** движка (source of truth = engine):
репозиторий «появляется» через **register-on-first-push** (первый `docker push` материализует
проекцию + per-repo FGA-authz) и **исчезает** через **unregister-on-last-tag** (удаление последнего
тега снимает проекцию). Своей строки в БД `kacho-registry` у репозитория нет — поэтому у него нет
конфигурации, переживающей пустоту: нельзя пред-создать пустой репозиторий, задать ему
`description`/`labels`, сделать его публичным.

RG-1 вводит **config-overlay первого класса** — DB-owned строку `repository_configs`, ключуемую
натуральным ключом **`(registry_id, name)`**, которая **переживает пустой репозиторий** и **не
ломает** существующее register-on-first-push / unregister-on-last-tag поведение. Overlay и проекция —
**ортогональные слои** над одним ключом `(registry_id, name)`; публичное сообщение `Repository` —
их LEFT JOIN. Поверх overlay добавляются явные async-мутации `CreateRepository` / `UpdateRepository` /
`DeleteRepository` / `RenameRepository`, sync-чтение `GetRepository`, поле `visibility{PRIVATE|PUBLIC}`
с anonymous-pull путём в data-plane, и read-проекция `ListReferrers` (фундамент под будущие
signing/scanning/SBOM под-фазы).

Инвариант изоляции (нерушимо, `security.md`): **бэкенд-движок остаётся Internal-only; публичный
`Repository` несёт только tenant-intent (id-ключ / имя / labels / visibility / привязки) + результат
(counts/size/timestamps); каждый deny — existence-hiding; ни одно инфра-поле (engine namespace,
bucket, host, числовой инфра-id) не появляется на публичной поверхности.**

Заказчик к approve контракта не подключается — он проверяет только финальный smoke/e2e (шаг 7:
`make e2e-test` / `docker pull` anon-public + `grpcurl` CreateRepository).

---

## 1. Ground truth + зафиксированные дизайн-решения

### 1.1 Текущее состояние (что уже есть — не переписываем)

- **Control-plane `RegistryService`** (public :9090, `registry_service.proto`): `Get`/`List` (sync) +
  `Create`/`Update`/`Delete`/`DeleteTag` (async→`Operation`) + `ListRepositories`/`ListTags` (sync,
  проекция) + `ListOperations`. `Registry` — flat, prefix `reg`.
- **`Repository`** (`registry.proto`) — read-only проекция: поля `registry_id, name, tag_count°,
  size_bytes°, updated_at°, artifact_type°/artifact_types[]°, last_pulled_at°, download_count°`
  (`°` = output-only). **Своей строки в БД нет.**
- **Data-plane** (OCI Distribution, `internal/dataplane`): AuthN Bearer-JWT/JWKS → parse → per-request
  FGA-Check → reverse-proxy в движок. Verb-модель: read → `v_get`/`v_list`; push нового repo →
  `v_create@registry_registry`; push существующего → `v_update@registry_repository`. Existence-hiding
  **уже** зафиксировано: read-deny → **404 `NAME_UNKNOWN`**; push-deny → **403 `DENIED`**; зависимость
  недоступна → **503 `UNAVAILABLE`**; DELETE-метод data-plane → **405** (удаление только через CP
  `DeleteTag`). Токена нет → **401 challenge**.
- **register-on-first-push** — на успешном manifest-PUT нового repo эмитится register-intent
  (parent-tuple реестра + owner-tuple толкавшего SA) через fga-proxy (outbox, at-least-once).
  **unregister-on-last-tag** — снятие проекции/authz при удалении последнего тега.
- **Internal-only** (`internal_registry_service.proto`, :9091): `TriggerGarbageCollection`,
  `GetRegistryStats` (`RegistryStats{repository_count, tag_count, total_size_bytes, blob_count,
  last_gc_at}` — инфра-данные, никогда на public).
- **Error-контракт** (`internal/errors`, `shared/serviceerr`): sentinel'ы `ErrNotFound`/`ErrAlreadyExists`/
  `ErrFailedPrecondition`/`ErrInvalidArg`/`ErrUnavailable` → gRPC коды; не-замапленная ошибка → фикс.
  `codes.Internal "internal database error"` (без leak'а pgx-текста, `security.md` hardening-inv #1).

### 1.2 Дизайн-решения RG-1 (locked — закрывают open-decisions #1, #2 overview)

- **D-1. Overlay ⟂ projection, ключ `(registry_id, name)`.** `Repository` идентифицируется натуральным
  ключом `registry_id + name` (**НЕ** генерируемым id-prefix — сохраняем проекционную модель). Репозиторий
  **tenant-виден** (Get/List отдаёт) ⟺ **есть overlay-строка ИЛИ проекция несёт ≥1 тег**. Публичное
  сообщение `Repository` = LEFT JOIN overlay (intent) + projection (result).
- **D-2. Два класса репозиториев.**
  - **Ephemeral** (проекция без overlay) — push-созданный, ведёт себя **как сегодня**:
    register-on-first-push, unregister-on-last-tag, `visibility=PRIVATE` (дефолт), виден пока ≥1 тег,
    **исчезает** при опустошении. Полный back-compat.
  - **Durable/configured** (есть overlay-строка) — создан `CreateRepository`, promoted через
    `UpdateRepository` **или** auto-promoted через `RenameRepository` (ephemeral, A23); **переживает
    пустоту** (Get отдаёт `tagCount=0`), несёт `visibility`/`description`/`labels`; **не** снимается
    unregister-on-last-tag.
- **D-3. `CreateRepository` = вставка overlay-строки, uniqueness — DB `UNIQUE(registry_id, name)`
  (ban #10, не software TOCTOU).** Дубликат overlay → `ALREADY_EXISTS`. Если для имени уже есть
  **проекция** (pushed content) без overlay — Create **adopt**-ит контент (репозиторий становится
  durable, `tagCount` отражает существующие теги): overlay и projection ортогональны, конфликт только
  по overlay-строке. Это конвергентно с register-on-first-push (пред-существующий pushed-repo просто
  получает управление) и **не требует** cross-service fail-closed на create-пути.
- **D-4. `DeleteRepository` = reject-if-tags (v1).** Не-пустой репозиторий (`tagCount>0`) → Operation
  завершается `error` **`FAILED_PRECONDITION "repository is not empty"`** (source of truth
  emptiness = engine, проверяется в worker'е). Пустой durable → снимает overlay + unregister FGA
  repo-tuples (**same-registry only, без cross-service cascade**, ban #4). **Cascade** (снести overlay
  вместе с тегами) — отдельный явный `:deleteWithTags` verb, **вне scope RG-1** (см. §2 Non-goals).
- **D-5. `RenameRepository` — в пределах ОДНОГО реестра (by construction); auto-promote ephemeral→durable.**
  Схема запроса — `{registry_id, repository, new_name}`, где `new_name` — **голое** repo-имя внутри того же
  `registry_id` (поля целевого реестра НЕТ) ⟹ cross-registry rename **структурно невыразим** (нельзя
  даже сформулировать — прежний runtime-reject «другой реестр» был бы недостижим). Overlay-имя +
  engine-контент (теги/манифесты/referrers) становятся адресуемы под новым именем, старое имя → 404
  (CP и data-plane). Коллизия целевого имени (overlay ИЛИ проекция) → `ALREADY_EXISTS`; malformed
  `new_name` ИЛИ `new_name == repository` (no-op) → `INVALID_ARGUMENT` (A19). Engine-remap —
  многошаговая **не-атомарная** OCI-операция; при недоступности движка Operation завершается `error`
  `UNAVAILABLE` **fail-closed**, overlay-имя не меняется, старое имя по-прежнему резолвится (A21 — нет
  состояния «адресуем ни под старым, ни под новым»).
  - **Rename применим и к EPHEMERAL-repo (проекция без overlay).** Ephemeral — дефолтное состояние любого
    pushed-но-неконфигурированного repo: он Get/List-виден и несёт per-repo `v_update`
    (register-on-first-push), поэтому `RenameRepository` над ним **вызываем**. Исход — **auto-promote →
    durable** (A23): rename **материализует** overlay-строку под `new_name` (repo становится
    survives-empty, D-3-style), **а не** reject'ит. Reject через `FAILED_PRECONDITION "repository is not
    configured"` **осознанно отвергнут**: он раскрыл бы durable-vs-ephemeral-различие (config-oracle) при
    том, что оба класса Get/List-видимы и rename-authz (`v_update`+`v_create`) идентична — auto-promote
    единообразен и не течёт наблюдаемым различием.
  - **Реконсиляция «single-statement CAS» с ephemeral-случаем.** Целевое overlay-имя материализуется
    **одним** стейтментом, тип зависит от класса источника: **re-key `UPDATE`** для durable (перенос
    name-колонки существующей overlay-строки, A16/A18), **`INSERT`** для ephemeral auto-promote (новая
    overlay-строка под `new_name`: `visibility` из `default_visibility`, `created_at=now`, adopt
    проекционного контента, A23). В **обоих** случаях уникальность целевого имени энфорсит DB
    `UNIQUE(registry_id, name)` (23505 / 0-rows → `ALREADY_EXISTS`, без software TOCTOU, ban #10) — «CAS»
    здесь = «одностейтментная запись под UNIQUE-backstop», а не буквально `UPDATE`.
- **D-6. `visibility{PRIVATE|PUBLIC}` — authoritative на Repository (overlay), дефолт PRIVATE
  (fail-safe).** DB-CHECK `visibility IN (PRIVATE, PUBLIC)`. `Registry` несёт `default_visibility`
  (mutable через `UpdateRegistry`, дефолт PRIVATE) — сид для новых repo. **Любой путь, где принципал
  САМ приводит repo к PUBLIC — per-repo flip (B02), create-with-explicit-PUBLIC (B08), установка
  `default_visibility=PUBLIC` (B10) — требует admin-tier** (`admin` на `registry_registry`, project-admin).
  Принципал только с `v_create`/`v_update` может задать **лишь PRIVATE** явно.
  **Граница наследования (осознанный gate-at-default, НЕ escalation-hole):** admin, установивший
  `default_visibility=PUBLIC`, УЖЕ прошёл admin-gate за «путь к PUBLIC»; поэтому repo, созданный
  **без явного `visibility`** любым `v_create`-принципалом (в т.ч. НЕ-admin), **наследует PUBLIC** из
  admin-заданного дефолта (B12) — admin-решение «этот реестр по умолчанию публичен» уже авторизовано.
  Чего НЕ-admin не может: задать `visibility=PUBLIC` **явно** (B08) и флипнуть существующий repo (B02).
- **D-7. Anonymous pull + anon-token.** Anonymous-принципал резолвится в FGA-subject **`user:*`**.
  `visibility=PUBLIC` ⟺ существует FGA-tuple **`user:* v_get registry_repository:<reg>/<repo>`**
  (эмитится/снимается transactional-outbox по **итоговому** состоянию overlay, идемпотентно — включая
  repo, ставший PUBLIC **по наследованию дефолта** на create, B12, не только per-repo flip B01).
  Data-plane read для анонима → Check `user:*`: PUBLIC → 200; **PRIVATE или absent → тот же uniform
  404 `NAME_UNKNOWN`** (public-ность **не** existence-oracle). Anon-принципал получает identity через
  **IAM `/token` без Basic-creds** (кросс-репо `kacho-iam`): токен с subject → `user:*`, **read-only
  scope** (несёт только read-verb, аудитория = registry data-plane, ограниченный TTL — B13). Anonymous
  **push невозможен by construction**: anon-token **не** несёт write-verb ⟹ `docker push` даже в
  pull-able PUBLIC-repo → 403/`DENIED` (B14). Governance `user:*`-tuple — через fga-proxy
  (register/unregister wildcard v_get).
- **D-8. `ListReferrers` — read-only проекция referrer-графа** (signatures/SBOM/attestations/generic по
  `subject_digest`), existence-hidden (`v_get`). Фундамент под сигнатуры/скан (те — отдельные под-фазы).
  Data-plane `routeReferrers` (OCI `/v2/.../referrers/<digest>`) уже существует (`servePullOnly relVGet`);
  RG-1 добавляет **control-plane** RPC-проекцию. **Пагинация (RG-1-решение):** ListReferrers отдаёт
  **полный** набор referrer'ов одного `subject_digest`, server-side **bounded** (жёсткий cap как у
  catalog-page 1000), **без** `page_token`/`page_size` — зеркалит OCI single-index `/referrers/<digest>`
  (referrer'ов на один subject inherently немного). Cursor-пагинация (`api-conventions.md §Pagination`) —
  явный follow-up, если кардинальность referrer'ов начнёт расти (см. §2 Non-goals).

---

## 2. Proto / scope (что меняется в `kacho-proto`)

**`registry.proto`:**
- `Repository` += settable overlay-поля: `description` (mutable), `labels` (map, mutable),
  `visibility` (enum, mutable admin-gated), `created_at°` (момент создания overlay, truncate до секунд,
  output-only; для ephemeral-repo — пусто). Проекционные поля (`tag_count`…`download_count`) — без изменений.
- `enum Visibility { VISIBILITY_UNSPECIFIED = 0; PRIVATE = 1; PUBLIC = 2; }`.
- `Registry` += `default_visibility` (Visibility, mutable через `UpdateRegistry`, дефолт PRIVATE).
- Новое сообщение `Referrer { registry_id, repository, subject_digest, digest°, artifact_type° (media-type
  facet), size_bytes°, map<string,string> annotations°, created_at° }`.

**`registry_service.proto`** — новые RPC на `RegistryService` (public :9090):

| RPC | Тип | REST | authz |
|---|---|---|---|
| `GetRepository` | sync | `GET  /registry/v1/registries/{registry_id}/repositories/{repository=**}` | `v_get@registry_repository` (existence-hiding) |
| `CreateRepository` | async→Op | `POST /registry/v1/registries/{registry_id}/repositories` (body) | `v_create@registry_registry` |
| `UpdateRepository` | async→Op | `PATCH /registry/v1/registries/{registry_id}/repositories/{repository=**}` (body) | `v_update@registry_repository` (+ admin для `visibility`) |
| `DeleteRepository` | async→Op | `DELETE /registry/v1/registries/{registry_id}/repositories/{repository=**}` | `v_delete@registry_repository` |
| `RenameRepository` | async→Op | `POST /registry/v1/registries/{registry_id}/repositories/{repository=**}:rename` (body) | `v_update@registry_repository` + `v_create@registry_registry` |
| `ListReferrers` | sync | `GET  /registry/v1/registries/{registry_id}/repositories/{repository=**}/referrers` | `v_get@registry_repository` (existence-hiding) |

- Имена repo содержат `/` (напр. `backend/api`) → REST-сегмент `{repository=**}` (grpc-gateway wildcard).
- **`RenameRepositoryRequest = {registry_id, repository, new_name}`** — `new_name` **голое** repo-имя
  внутри того же `registry_id` (поля целевого реестра НЕТ; cross-registry rename структурно невыразим, D-5).
- **`UpdateRegistry.default_visibility`** — mutable через существующий `RegistryService/Update`; переход
  `default_visibility → PUBLIC` подчинён тому же any-path-to-PUBLIC-admin-gate, что и `Repository.visibility`
  (D-6): не-admin `v_update`-принципал → `PERMISSION_DENIED` (B10); admin → OK (B11).
- Op-envelope: `CreateRepositoryMetadata{registry_id, repository}` resp `Repository`; `Update…` resp
  `Repository`; `DeleteRepositoryMetadata{registry_id, repository}` resp `google.protobuf.Empty`;
  `RenameRepositoryMetadata{registry_id, repository, new_name}` resp `Repository`.
- `permission-catalog` регенерируется (`make permission-catalog`, byte-identical, CI drift-gate,
  `security.md` #4); scope_extractor per-RPC (object-scoped authz, `security.md` #3).

**`kacho-iam`** — anon-token issuance (IAM `/token` выдаёт токен без Basic-creds → subject-принципал
`user:*`, **read-only scope** / только read-verb, аудитория = registry data-plane, **bounded TTL**, **без**
write-verb — контракт B13/B14) + `user:*` public-tuple governance-точка (fga-proxy принимает register/
unregister wildcard v_get). **Не** новый ресурс — расширение существующего token/fga-proxy пути.

### Границы / Non-goals (объявлено вне scope — НЕ tech-debt)

- **Policy-bindings на Repository** (`immutability_mode` / `retention_policy_id` / `scan_policy_id` /
  `signing_policy_id`) из overview §1 — **не добавляем** сейчас (LEAN, ban #11): их ресурсы
  (`RetentionPolicy`/`ScanPolicy`/`SigningPolicy`/`TagProtectionRule`) — отдельные под-фазы. RG-1 кладёт
  только overlay-каркас (`description`/`labels`/`visibility`) + referrer-проекцию как якорь.
- **`DeleteRepository` cascade-with-tags** — явный `:deleteWithTags` verb, отдельная под-фаза (D-4).
- **Per-tag / tag-glob RBAC, RobotToken, Quota, Webhook, Replication, Scan/Sign engine** — overview §2/§5,
  не здесь.
- **Data-plane OCI `DELETE` completeness** (hard-405 сохраняется, overview §5 #10) — не трогаем.
- **Bulk repo delete / bulk rename** — не здесь.
- **Ретро-миграция существующих ephemeral-repo в durable** — forward-only (overlay появляется по явному
  Create/Update); backfill не делаем.
- **`DeleteRepository` delete-vs-push TOCTOU write-fence** — жёсткий deny-push-while-DELETING
  (overview §4 divergence #3) **вне scope RG-1**: reject-if-tags (D-4) проверяет emptiness в worker'е,
  но остаточная гонка «push тега ровно между worker-проверкой пустоты и снятием overlay» **не**
  закрывается write-fence'ом здесь (fail-safe: durable-overlay безопасен сам по себе, а осиротевший тег
  переживается проекцией — не паника). Write-fence — отдельный follow-up (тот же divergence #3, что и
  delete-vs-push у `Registry`), а не неотмеченный gap.
- **Per-platform child-manifest listing для multi-arch index** (overview §2 «Repo-management», тот же
  bullet, что и `ListReferrers`) — RG-1 кладёт **только** `ListReferrers`-проекцию referrer-графа;
  поэлементный листинг child-манифестов multi-arch-индекса — отдельный follow-up.
- **Cursor-пагинация `ListReferrers`** — RG-1 отдаёт bounded full-set одного `subject_digest` (D-8);
  `page_token`/`page_size` — follow-up при росте referrer-кардинальности.

---

## Группа A — Repository config-overlay: lifecycle (Create / Get / Update / Delete / Rename)

> Инвариант: `data-integrity.md §Within-service` — uniqueness `(registry_id, name)` и `visibility`-домен
> выражены **DB-конструкциями** (UNIQUE / CHECK / single-statement CAS), не software check-then-act (ban #10).
> Async-мутации → `Operation` (`api-conventions.md §9`). Existence-hiding deny → `NOT_FOUND` (parity с
> data-plane 404 и существующим `DeleteTag`-хендлером).

### Сценарий A01: CreateRepository пустого durable-repo → Operation → durable, PRIVATE, tagCount=0

**ID:** RG-1-A01-CREATE-EMPTY-HAPPY

**Given** проект `P`, реестр `reg-1` (`<reg>`, ACTIVE) в `P`
**And** имя `backend/api` в `reg-1` свободно (нет overlay-строки, нет проекции)
**And** caller держит `v_create` на `registry_registry:<reg>`

**When** клиент вызывает `RegistryService/CreateRepository` (REST `POST /registry/v1/registries/<reg>/repositories`) с payload:
  - registryId = `<reg>`
  - repository = `backend/api`
  - description = `"api service images"`
  - labels = `{ team: "core" }`
  - (visibility не задан → UNSPECIFIED)

**Then** ответ синхронно содержит `operation.Operation` (непустой `id`, `done=false`)
**And** poll `GET /registry/v1/operations/<opId>` сходится к `done=true` **без** `error`; `response` —
       `Repository` с `registryId=<reg>`, `name="backend/api"`, `visibility=PRIVATE` (унаследован из
       `reg-1.default_visibility=PRIVATE`), `description`/`labels` из запроса, `tagCount=0`,
       `createdAt` заполнен (truncate до секунд)
**And** `GET /registry/v1/registries/<reg>/repositories/backend/api` (GetRepository) отдаёт тот же
       durable `Repository` (overlay пережил пустоту — репозиторий виден без единого тега)
**And** owner-tuple толкающего/создавшего SA эмитится (repo становится push/pull-able его создателем).

### Сценарий A02: CreateRepository дубликат (overlay уже есть) → ALREADY_EXISTS

**ID:** RG-1-A02-CREATE-DUP-NEG

**Given** durable-repo `backend/api` в `reg-1` уже создан (A01)

**When** клиент повторно вызывает `CreateRepository` с `registryId=<reg>`, `repository="backend/api"`

**Then** ответ — gRPC **`ALREADY_EXISTS`** с текстом **`"repository already exists"`**
       (нарушение DB `UNIQUE(registry_id, name)`, SQLSTATE 23505 → sentinel `ErrAlreadyExists`;
       behaviour-level: assert код И текст)
**And** второй overlay-строки не появляется; существующая конфигурация не изменена.

### Сценарий A03: CreateRepository adopt-ит пред-существующую проекцию (pushed content, без overlay) → OK

**ID:** RG-1-A03-CREATE-ADOPT-PROJECTION-EDGE

**Given** ephemeral-repo `legacy/app` в `reg-1` (создан прежде через `docker push`, несёт 3 тега,
       overlay-строки нет)

**When** клиент вызывает `CreateRepository` с `registryId=<reg>`, `repository="legacy/app"`,
       `labels={ owner: "billing" }`

**Then** Operation → `done=true` без `error`; `response` — `Repository`, ставший **durable**
       (overlay-строка вставлена; конфликта нет — overlay и projection ортогональны), с
       `tagCount=3` (adopt существующего контента), `visibility=PRIVATE`, применёнными `labels`
**And** **adopt аддитивен по owner-tuple:** owner-tuple **создающего** (Create-caller) SA **добавляется**
       (репозиторий становится ему управляемым); owner-tuple исходного пушера (эмитированный
       register-on-first-push) **сохраняется** — adopt **никогда** не снимает существующий owner-grant, оба
       принципала остаются владельцами (grant'ы аддитивны)
**And** последующее удаление всех тегов `legacy/app` **не** снимает репозиторий (D-3/D-2: теперь durable),
       в отличие от прежнего ephemeral-поведения.

### Сценарий A04: конкурентные CreateRepository одного имени → ровно один OK, остальные ALREADY_EXISTS

**ID:** RG-1-A04-CREATE-CONCURRENT-CONC

**Given** проект `P`, реестр `reg-1`; имя `svc/x` свободно

**When** N параллельных `CreateRepository(registryId=<reg>, repository="svc/x")` стартуют одновременно

**Then** **ровно одна** Operation завершается `done=true` без `error` (overlay-строка вставлена);
       **все остальные** → `ALREADY_EXISTS "repository already exists"` (DB `UNIQUE`, не software-guard —
       единственная строка проходит по row-lock, `data-integrity.md §Within-service`)
**And** в `repository_configs` ровно одна строка `(<reg>, "svc/x")`; сервис не отдаёт `INTERNAL` с
       leak'ом pgx-текста.

> Integration-тест (testcontainers, concurrent goroutines) на этот путь — обязателен (ban #12,
> `data-integrity.md §Чек-лист` п.5).

### Сценарий A05: CreateRepository с malformed / пустым именем → INVALID_ARGUMENT

**ID:** RG-1-A05-CREATE-BAD-NAME-NEG

**Given** реестр `reg-1`

**When** клиент вызывает `CreateRepository` с (a) `repository=""` **либо** (b) `repository="Bad Name!"`
       (нарушает OCI repo-name grammar: lowercase, `[a-z0-9]+(?:[._-/][a-z0-9]+)*`)

**Then** синхронный gRPC **`INVALID_ARGUMENT`**: (a) → **`"repository is required"`**;
       (b) → **`"invalid repository name '<X>'"`** (валидируется **первым** стейтментом RPC, до repo-вызова —
       `api-conventions.md` malformed-first)
**And** Operation не создаётся; overlay-строка не появляется.

### Сценарий A06: malformed registry_id → INVALID_ARGUMENT (первым стейтментом)

**ID:** RG-1-A06-CREATE-BAD-REGID-NEG

**Given** —

**When** клиент вызывает любой из `GetRepository`/`CreateRepository`/`UpdateRepository`/`DeleteRepository`/
       `RenameRepository`/`ListReferrers` с `registryId="not-a-reg-id"` (не проходит prefix `reg`)

**Then** синхронный gRPC **`INVALID_ARGUMENT "invalid registry id 'not-a-reg-id'"`**
       (`ValidateRegistryID` первым стейтментом, verbatim-зеркало существующего контракта)
**And** ни authz-Check, ни repo-вызов, ни Operation не выполняются.

### Сценарий A07: GetRepository durable пустого repo → sync Repository (overlay projection)

**ID:** RG-1-A07-GET-DURABLE-EMPTY-HAPPY

**Given** durable-repo `backend/api` (A01), tagCount=0; caller держит `v_get@registry_repository:<reg>/backend/api`

**When** клиент вызывает `GetRepository(registryId=<reg>, repository="backend/api")`

**Then** sync-ответ — `Repository` с overlay-полями (`description`/`labels`/`visibility=PRIVATE`/`createdAt`)
       и нулевыми проекционными (`tagCount=0`, `sizeBytes=0`, `artifactTypes=[]`, `lastPulledAt` пуст)
**And** ответ **не содержит** ни одного инфра-поля (engine namespace / bucket / host / числовой инфра-id) —
       `security.md §Инфра-чувствительные данные` (проверяется схемой сообщения + gateway projection-audit).

### Сценарий A08: GetRepository — unauthorized ИЛИ absent → одинаковый NOT_FOUND (existence-hiding)

**ID:** RG-1-A08-GET-EXISTENCE-HIDING-NEG

**Given** (a) durable-repo `secret/svc` существует, но caller **не** держит `v_get` на нём;
       (b) имя `ghost/svc` в реестре **отсутствует** (ни overlay, ни проекция)

**When** клиент вызывает `GetRepository` для (a) `secret/svc` и (b) `ghost/svc`

**Then** **оба** → gRPC **`NOT_FOUND`** с текстом **`"repository not found"`** — байт-в-байт одинаково
       (unauthorized-но-существует **неотличим** от absent; existence-hiding, parity с data-plane 404
       и хендлером `DeleteTag`/`ListTags`)
**And** ни в одном случае наружу не течёт факт существования/тегов чужого репозитория.

### Сценарий A09: UpdateRepository description/labels (v_update) → Operation → Get отражает

**ID:** RG-1-A09-UPDATE-MUTABLE-HAPPY

**Given** durable-repo `backend/api` (A01); caller держит `v_update@registry_repository:<reg>/backend/api`
       (editor-tier, **без** admin)

**When** клиент вызывает `UpdateRepository` с payload:
  - registryId = `<reg>`, repository = `backend/api`
  - description = `"api images v2"`, labels = `{ team: "core", tier: "gold" }`
  - update_mask = `["description","labels"]`

**Then** Operation → `done=true` без `error`; `response` — `Repository` с новыми `description`/`labels`
**And** `GetRepository` отражает изменения; `visibility` не тронут (не в mask).

### Сценарий A10: UpdateRepository — unknown mask-поле → INVALID_ARGUMENT

**ID:** RG-1-A10-UPDATE-UNKNOWN-MASK-NEG

**Given** durable-repo `backend/api`

**When** клиент вызывает `UpdateRepository` с `update_mask=["descriptionx"]` (неизвестное поле)

**Then** синхронный gRPC **`INVALID_ARGUMENT`** (`corevalidate.UpdateMask` с known-set
       `{description, labels, visibility}`; unknown → отказ до применения) — Operation не создаётся.

### Сценарий A11: UpdateRepository — immutable поле в mask → канонический immutable-текст

**ID:** RG-1-A11-UPDATE-IMMUTABLE-MASK-NEG

**Given** durable-repo `backend/api`

**When** клиент вызывает `UpdateRepository` с `update_mask=["name"]` (или `["registryId"]`)

**Then** синхронный gRPC **`INVALID_ARGUMENT "name is immutable after Repository.Create"`**
       (immutable-switch **до** `UpdateMask`, `api-conventions.md` gotcha; смена имени — только
       `RenameRepository`) — Operation не создаётся.

### Сценарий A12: UpdateRepository promote ephemeral→durable (overlay upsert)

**ID:** RG-1-A12-UPDATE-PROMOTE-EDGE

**Given** ephemeral-repo `legacy/tool` (проекция с 2 тегами, overlay нет); caller держит `v_update`

**When** клиент вызывает `UpdateRepository` с `update_mask=["labels"]`, `labels={ archived: "true" }`

**Then** Operation → `done=true` без `error`; overlay-строка **создаётся** (promote → durable),
       `tagCount=2` сохранён; `visibility=PRIVATE`
**And** удаление обоих тегов `legacy/tool` теперь **не** снимает репозиторий (durable, D-2).

### Сценарий A13: DeleteRepository пустого durable-repo → Operation → Get NOT_FOUND

**ID:** RG-1-A13-DELETE-EMPTY-HAPPY

**Given** durable-repo `backend/api`, tagCount=0; caller держит `v_delete@registry_repository:<reg>/backend/api`

**When** клиент вызывает `DeleteRepository(registryId=<reg>, repository="backend/api")`

**Then** Operation → `done=true` без `error` (`response` = Empty); overlay-строка снята,
       FGA repo-tuples реестра unregister'ятся (**same-registry only**, ban #4 — cross-service cascade нет)
**And** последующий `GetRepository(backend/api)` → **`NOT_FOUND "repository not found"`** (репозиторий исчез).

### Сценарий A14: DeleteRepository не-пустого repo → FAILED_PRECONDITION "repository is not empty"

**ID:** RG-1-A14-DELETE-NONEMPTY-NEG

**Given** durable-repo `busy/svc` с ≥1 тегом; caller держит `v_delete`

**When** клиент вызывает `DeleteRepository(registryId=<reg>, repository="busy/svc")`

**Then** authz `v_delete` проходит (sync) → Operation создаётся → **worker** проверяет emptiness
       (source of truth = engine tag-count) → Operation завершается `done=true` **с** `error`
       **`FAILED_PRECONDITION "repository is not empty"`** (reject-if-tags, D-4; cascade — только `:deleteWithTags`)
**And** overlay-строка и теги **сохранены**; репозиторий по-прежнему виден.

> Design-note: emptiness проверяется в worker'е (не sync), чтобы избежать TOCTOU «push тега между
> sync-проверкой и async-delete». Engine недоступен во время проверки → Operation `error`
> **`UNAVAILABLE`** (fail-closed: overlay не сносим, пока не подтвердили пустоту).

### Сценарий A15: DeleteRepository — unauthorized ИЛИ absent → sync NOT_FOUND (Operation НЕ создаётся)

**ID:** RG-1-A15-DELETE-EXISTENCE-HIDING-NEG

**Given** (a) durable-repo `secret/svc`, caller без `v_delete`; (b) absent `ghost/svc`

**When** клиент вызывает `DeleteRepository` для (a) и (b)

**Then** **оба** → синхронный gRPC **`NOT_FOUND "repository not found"`**, Operation **не** создаётся
       (deny синхронно ДО LRO — как существующий `DeleteTag`-хендлер: async-Operation с error раскрыл бы
       факт приёма мутации над чужим/несуществующим repo → existence-oracle).

### Сценарий A16: RenameRepository (durable, старое→новое) → Get(new) OK, Get(old) NOT_FOUND

**ID:** RG-1-A16-RENAME-HAPPY

**Given** durable-repo `old/name` в `reg-1` (с 0 или ≥1 тегами); имя `new/name` в `reg-1` свободно;
       caller держит `v_update@registry_repository:<reg>/old/name` **и** `v_create@registry_registry:<reg>`

**When** клиент вызывает `RenameRepository` (REST `POST /registry/v1/registries/<reg>/repositories/old/name:rename`)
       с payload `{ registryId:<reg>, repository:"old/name", newName:"new/name" }`

**Then** Operation → `done=true` без `error`; `response` — `Repository` под именем `new/name`
       (overlay-имя re-key `UPDATE` существующей строки + engine-контент/теги/referrers re-homed атомарно
       с точки зрения тенанта; FGA-объект перерегистрирован под новым именем, старый — снят)
**And** `GetRepository(new/name)` → OK (все теги видны под новым именем); `GetRepository(old/name)` →
       **`NOT_FOUND`**; data-plane `docker pull <reg>/old/name:<tag>` → **404 `NAME_UNKNOWN`**,
       `docker pull <reg>/new/name:<tag>` → 200.

> Scope-note: A16 — **durable**-путь (overlay-строка уже есть → re-key `UPDATE`, D-5). Rename над
> **ephemeral**-repo (проекция без overlay) auto-promote'ит его в durable через `INSERT` — отдельный
> сценарий **A23** (D-5 reconciliation «single-statement CAS» для upsert/insert-случая).

### Сценарий A17: RenameRepository — целевое имя занято (overlay или проекция) → ALREADY_EXISTS

**ID:** RG-1-A17-RENAME-COLLISION-NEG

**Given** durable-repo `src/a` и durable-repo (или проекция) `dst/b` — **оба существуют** в `reg-1`

**When** клиент вызывает `RenameRepository{ repository:"src/a", newName:"dst/b" }`

**Then** gRPC **`ALREADY_EXISTS "repository already exists"`** (целевое имя занято — overlay `UNIQUE`
       ИЛИ engine-проекция; behaviour-level)
**And** `src/a` остаётся под старым именем без изменений; контент не перемещён.

### Сценарий A18: RenameRepository — конкурентные rename в одно целевое имя → ровно один OK

**ID:** RG-1-A18-RENAME-CONCURRENT-CONC

**Given** durable-repo `src/a` и `src/c`; целевое `dst/z` свободно

**When** параллельно: `Rename{src/a → dst/z}` и `Rename{src/c → dst/z}`

**Then** **ровно один** rename завершается OK; другой → **`ALREADY_EXISTS`** (одностейтментная запись
       целевого overlay-имени — re-key `UPDATE`/`INSERT`, D-5 — защищена DB `UNIQUE(registry_id, name)`:
       второй writer видит занятую строку, 0 rows / 23505, `data-integrity.md §CAS`)
**And** итог когерентен: `dst/z` соответствует ровно одному исходному репозиторию, второй остался под
       своим именем; leak'а pgx-текста нет.

### Сценарий A19: RenameRepository невалидный newName (malformed ИЛИ == текущему) → INVALID_ARGUMENT

**ID:** RG-1-A19-RENAME-BAD-NEWNAME-NEG

**Given** durable-repo `app/x` в `reg-1`; caller держит `v_update@…/app/x` + `v_create@registry_registry:<reg>`

**When** клиент вызывает `RenameRepository{ registryId:<reg>, repository:"app/x", newName:<X> }` с
       (a) `newName="Bad Name!"` (нарушает OCI repo-name grammar `[a-z0-9]+(?:[._-/][a-z0-9]+)*`);
       **либо** (b) `newName="app/x"` (совпадает с текущим `repository`)

**Then** синхронный gRPC **`INVALID_ARGUMENT`**: (a) → **`"invalid repository name 'Bad Name!'"`**
       (валидируется **первым** стейтментом RPC, до repo/engine-вызова); (b) → **`"new name must differ from
       current name"`** (no-op rename отвергается явно)
**And** Operation не создаётся; overlay-имя не меняется; контент не перемещён.

> Резолвит §2↔D-5: `RenameRepositoryRequest{registry_id, repository, new_name}` несёт `new_name` как
> **голое** repo-имя того же `registry_id` — поля целевого реестра НЕТ, поэтому cross-registry rename
> **структурно невыразим** (прежний недостижимый «rename must stay within the same registry» заменён на
> достижимые malformed/no-op кейсы).

### Сценарий A20: ListRepositories — durable-empty в объединении overlay ⊔ projection + v_list row-filter

**ID:** RG-1-A20-LIST-OVERLAY-UNION-EDGE

**Given** в `reg-1`: (1) durable-empty repo `cfg/only` (overlay-строка, `tagCount=0`, без единого тега);
       (2) ephemeral repo `pushed/svc` (проекция, `tagCount=2`, без overlay);
       (3) durable-empty repo `hidden/svc` (overlay-строка, `tagCount=0`)
**And** caller-U держит `v_list` на реестре И на `cfg/only`/`pushed/svc`, но **НЕ** на `hidden/svc`

**When** caller-U вызывает `ListRepositories(registryId=<reg>)`

**Then** результат — **объединение** overlay ⊔ projection (D-1): `cfg/only` **присутствует** несмотря на
       `tagCount=0` (durable пережил пустоту — **изменённая семантика существующего RPC**: раньше пустой
       repo в List не появлялся вовсе), `pushed/svc` присутствует (проекция), **`hidden/svc` отсутствует** —
       отфильтрован per-repo `v_list` row-filter (listauthz, existence-hiding: durable-repo **не** «протекает»
       в List принципалу без `v_list`, `security.md §Публичный List обязан фильтровать`)
**And** пагинация/`page_size`/cursor — как у существующего `ListRepositories` (без регрессии); ни одно
       инфра-поле в элементах не раскрыто (X01).

> Заметка: A01/A07 покрывают только Get для durable-empty; A20 закрывает вторую половину D-1 («List отдаёт»),
> которая меняет **существующий** `ListRepositories`-RPC (result-set → overlay ⊔ projection).

### Сценарий A21: RenameRepository — движок недоступен в середине remap → fail-closed, без частичного rename

**ID:** RG-1-A21-RENAME-ENGINE-UNAVAIL-EDGE

**Given** durable-repo `move/src` в `reg-1` с тегом `v1` (манифест/блобы/referrers в движке); имя `move/dst`
       свободно; caller держит `v_update@…/move/src` + `v_create@registry_registry:<reg>`

**When** клиент вызывает `RenameRepository{ repository:"move/src", newName:"move/dst" }`, но движок
       **недоступен/сбоит** во время re-home тегов/манифестов/referrers (многошаговая **не-атомарная**
       OCI-операция)

**Then** Operation завершается `done=true` **с** `error` **`UNAVAILABLE`** (fail-closed, `data-integrity.md
       §Cross-domain` — не коммитим переименование, пока движок не подтвердил re-home; параллель к A14 delete)
**And** overlay-имя **не изменено** (`move/src`); старое имя **по-прежнему резолвится**:
       `GetRepository(move/src)` → OK, `GetRepository(move/dst)` → **`NOT_FOUND`**, data-plane
       `docker pull <reg>/move/src:v1` → **200**, `docker pull <reg>/move/dst:v1` → **404 `NAME_UNKNOWN`**
**And** **нет** состояния частичного rename, где repo не адресуем **ни** под старым, **ни** под новым именем;
       leak'а pgx/engine-текста нет (X02).

### Сценарий A22: Create/UpdateRepository — границы payload (labels / description / unicode)

**ID:** RG-1-A22-PAYLOAD-BOUNDS-EDGE

**Given** реестр `reg-1`; caller держит `v_create`/`v_update`

**When** клиент вызывает `CreateRepository`/`UpdateRepository` с (a) `labels`, нарушающими границу:
       **65** пар (`MaxLabels=64`, +1) ИЛИ ключ длиной **64** символа (`MaxLabelKeyLen=63`) ИЛИ значение
       длиной **64** символа (`MaxLabelValueLen=63`); (b) `description` длиной **257 rune**
       (`MaxDescriptionLen=256`, лимит по **rune-count UTF-8**, не байтам); (c) валидным
       multibyte-unicode `description` **в пределах 256 rune** (напр. `"службы платформы 平台 🚀"`,
       корректный UTF-8)

**Then** (a) → синхронный **`INVALID_ARGUMENT`** с точным текстом `corelib/validate`: 65 пар →
       **`"too many labels (max 64)"`**; ключ 64 символа →
       **`"invalid label key (1..63 chars, lowercase letters, digits, _-./\@)"`**; значение 64 символа →
       **`"label value exceeds 63 chars"`** — overlay не создаётся/не меняется; (b) →
       **`INVALID_ARGUMENT "description length exceeds 256 chars"`**; (c) → **Operation OK**:
       unicode-`description` (все 4 rune-класса: кириллица/CJK/emoji/ASCII) принят и **round-trip'ит
       байт-в-байт** через `GetRepository` (валидный UTF-8 хранится/отдаётся без искажения), при этом
       control-chars (`\x00`…`\x1f`) в `description` отвергаются как **`INVALID_ARGUMENT`**
**And** все границы валидируются на request-path (до repo-вызова); лимиты — **константы `corelib/validate`**:
       `MaxLabels=64`, `MaxLabelKeyLen=MaxLabelValueLen=63`, `MaxDescriptionLen=256` (rune-count, `Description`
       считает `utf8.RuneCountInString`) — те же, что у `Registry.description/labels` (parity ресурсов).
       **BVA-границы (детерминированно):** at-limit проходит (64 пары / ключ-63 / значение-63 / 256-rune
       description), limit+1 отвергается (65 / 64-char key / 64-char value / 257-rune).

### Сценарий A23: RenameRepository EPHEMERAL-repo → auto-promote в durable под новым именем (survives-empty)

**ID:** RG-1-A23-RENAME-EPHEMERAL-PROMOTE-EDGE

**Given** ephemeral-repo `push/old` в `reg-1` (проекция с 2 тегами `v1`/`v2`, overlay-строки **НЕТ**,
       `visibility=PRIVATE` дефолт); имя `push/new` в `reg-1` свободно (ни overlay, ни проекция); caller
       держит `v_update@registry_repository:<reg>/push/old` (несёт register-on-first-push) **и**
       `v_create@registry_registry:<reg>`

**When** клиент вызывает `RenameRepository{ registryId:<reg>, repository:"push/old", newName:"push/new" }`
       (REST `POST /registry/v1/registries/<reg>/repositories/push/old:rename`)

**Then** Operation → `done=true` без `error`; rename **auto-promote'ит** ephemeral → **durable** (D-5, **не**
       reject): overlay-строка **вставляется** (`INSERT`) под `new_name=push/new` (`visibility` из
       `reg-1.default_visibility`, `createdAt` заполнен, adopt существующего контента), engine-контент
       (теги/манифесты/referrers) re-homed старое→новое; FGA-объект перерегистрирован под `push/new`
**And** `GetRepository(push/new)` → durable `Repository`, **`tagCount=2` сохранён** (оба тега видны под
       новым именем), `createdAt` заполнен; `GetRepository(push/old)` → **`NOT_FOUND`**; data-plane
       `docker pull <reg>/push/old:v1` → **404 `NAME_UNKNOWN`**, `docker pull <reg>/push/new:v1` → **200**
**And** `push/new` теперь **переживает пустоту**: удаление обоих тегов **не** снимает репозиторий
       (durable после promote, D-2/D-3 — контраст с прежним ephemeral-поведением `push/old`, который
       исчез бы при опустошении). Reject `FAILED_PRECONDITION "repository is not configured"` осознанно
       **не** используется — раскрыл бы durable-vs-ephemeral (config-oracle), D-5
**And** target-name uniqueness — DB `UNIQUE(registry_id, name)` (занятое `new_name` → `ALREADY_EXISTS`,
       A17-parity, **включая** ephemeral-INSERT-путь); движок недоступен в середине remap → fail-closed
       `UNAVAILABLE`, overlay-INSERT не коммитится, `push/old` остаётся адресуем (A21-parity); leak'а
       pgx/engine-текста нет.

### Сценарий A24: Create/Update/Delete/Rename Repository в реестре status=DELETING → FAILED_PRECONDITION

**ID:** RG-1-A24-REG-DELETING-NEG

**Given** реестр `reg-2` в терминальном состоянии **`DELETING`** (CAS `ACTIVE→DELETING` уже произошёл;
       `DELETING` — терминальный, revert не предусмотрен); caller **видит** `reg-2` и держит нужный verb
       (`v_create`/`v_update`/`v_delete` соответственно)

**When** клиент вызывает `CreateRepository` / `UpdateRepository` / `DeleteRepository` / `RenameRepository`
       над репозиторием в `reg-2`

**Then** каждая мутация отвергается **`FAILED_PRECONDITION "registry is being deleted"`** — same-DB read
       статуса реестра на request-path (FK `registry_id → registries(id)` гарантирует **существование**
       реестра, но **не** его статус; ACTIVE-guard — явная precondition, parity с существующей
       `Registry`-lifecycle-семантикой, где `DELETING` терминален и мутации не принимаются)
**And** overlay-строка не создаётся/не меняется/не удаляется; Operation не оставляет частичного
       состояния (fail-safe: реестр в разборке не принимает новую repo-конфигурацию, а reject-if-tags
       delete в DELETING-реестре бессмыслен — namespace и так сносится)
**And** это **не** existence-oracle: caller уже доказал доступ к **видимому** реестру, поэтому
       `FAILED_PRECONDITION` честен коду (`security.md §Hardening #5`); **невидимый/чужой** реестр даёт
       `NOT_FOUND` namespace call-gate (X04) — различие «DELETING vs absent» видно только тому, кто и так
       авторизован на реестр.

> Design-note: статус-guard живёт **в use-case** repo-мутаций (same-DB read `registries.status`), а не в
> FK — FK ссылочно проверяет только существование строки реестра. Это тот же fail-safe, что у существующей
> `Registry`-delete (терминальный `DELETING`); RG-1 распространяет его на overlay-мутации репозиториев.

---

## Группа B — visibility{PRIVATE|PUBLIC} + anonymous data-plane pull

> Инвариант: `security.md §Публичная поверхность` + overview §3 «Public/anonymous pull» — anon-путь
> обслуживает **только** PUBLIC-repo; public-ность **не** existence-oracle; **любой путь, где принципал сам
> приводит ресурс к PUBLIC (explicit flip / explicit create-PUBLIC / установка default_visibility=PUBLIC),
> требует admin** — единственное исключение: наследование admin-заданного `default_visibility=PUBLIC` при
> create без явного поля (gate-at-default: admin уже авторизовал дефолт, B12); `user:*` public-tuple —
> governance по итоговому overlay-состоянию (включая inherited-public). Anon-минтинг токена — B13/B14.

### Сценарий B01: project-admin flip PRIVATE→PUBLIC → Get PUBLIC + user:* tuple эмитится

**ID:** RG-1-B01-FLIP-PUBLIC-HAPPY

**Given** durable-repo `public/img` (`visibility=PRIVATE`); caller держит **`admin`** на `registry_registry:<reg>`

**When** клиент вызывает `UpdateRepository` с `update_mask=["visibility"]`, `visibility=PUBLIC`

**Then** Operation → `done=true` без `error`; `GetRepository(public/img)` → `visibility=PUBLIC`
**And** FGA-tuple **`user:* v_get registry_repository:<reg>/public/img`** эмитится через fga-proxy
       (outbox, at-least-once, идемпотентно) — публичный read-grant материализуется.

### Сценарий B02: не-admin editor flip visibility → PERMISSION_DENIED (но description/labels — OK)

**ID:** RG-1-B02-FLIP-NONADMIN-NEG

**Given** durable-repo `public/img`; caller держит `v_update` (editor), но **не** `admin` на реестре

**When** клиент вызывает `UpdateRepository` с `update_mask=["visibility"]`, `visibility=PUBLIC`

**Then** gRPC **`PERMISSION_DENIED "changing repository visibility requires registry admin"`**
       (**НЕ** `NOT_FOUND`: caller уже доказал доступ к repo через `v_update` → его существование ему
       известно → 403 не является oracle; `security.md §Hardening` #5 — deny-код честен коду)
**And** `visibility` не изменён; `user:*` tuple не эмитится
**And** **тот же** caller с `update_mask=["description"]` (без visibility) → Operation OK (editor-путь
       не сломан; admin-gate узок — только на `visibility` в mask).

### Сценарий B03: anonymous docker pull PUBLIC-repo → 200

**ID:** RG-1-B03-ANON-PULL-PUBLIC-HAPPY

**Given** durable-repo `public/img` c `visibility=PUBLIC` (B01), несёт тег `v1` (манифест+блобы в движке)
**And** клиент **без** Kachō-identity (нет `docker login`; anon-принципал → FGA `user:*`)

**When** anon-клиент выполняет `docker pull registry.kacho.local/<reg>/public/img:v1`
       (GET/HEAD manifest + blobs + `GET .../tags/list` + `GET .../referrers/<digest>`)

**Then** каждый read → **200** (Check `user:* v_get` проходит по public-tuple) — pull успешен анонимно
**And** ответы не несут инфра-полей движка (fixed OCI-body, `security.md`).

### Сценарий B04: anonymous docker pull PRIVATE-repo → uniform 404 NAME_UNKNOWN

**ID:** RG-1-B04-ANON-PULL-PRIVATE-NEG

**Given** durable-repo `private/img` c `visibility=PRIVATE` (несёт тег `v1`); anon-клиент (`user:*`)

**When** anon-клиент выполняет `docker pull registry.kacho.local/<reg>/private/img:v1`

**Then** read → **404 `NAME_UNKNOWN`** (`user:* v_get`-tuple отсутствует → Check deny → existing
       read-deny-shape 404, existence-hiding)
**And** ответ **байт-в-байт** совпадает с ответом на absent-repo (см. B05).

### Сценарий B05: anonymous pull ABSENT-repo → идентичный 404 (public-ность не oracle)

**ID:** RG-1-B05-ANON-PULL-ABSENT-ORACLE

**Given** имя `nope/img` в `<reg>` **отсутствует**; anon-клиент

**When** anon-клиент выполняет `docker pull registry.kacho.local/<reg>/nope/img:v1`

**Then** read → **404 `NAME_UNKNOWN`** — **неотличимо** от B04 (private-exists): private-exists и absent
       возвращают одинаковый uniform-404 анониму ⟹ public-ность **не** отличает «private-exists» от
       «absent» (закрывает existence-oracle, overview §3 / open-decision #2).

### Сценарий B06: flip PUBLIC→PRIVATE → user:* tuple снят → anon pull снова 404; авторизованный — 200

**ID:** RG-1-B06-FLIP-PRIVATE-REVOKE-EDGE

**Given** durable-repo `public/img` c `visibility=PUBLIC`, anon pull сейчас 200 (B03); caller-admin

**When** admin вызывает `UpdateRepository{ update_mask:["visibility"], visibility:PRIVATE }`

**Then** Operation OK; FGA-tuple `user:* v_get …` **снимается** (governance по итоговому состоянию)
**And** anon `docker pull …/public/img:v1` теперь → **404 `NAME_UNKNOWN`** (был 200 — revoke-safety)
**And** **авторизованный** принципал с `v_get` на repo по-прежнему → **200** (снятие public-tuple не
       трогает per-subject grants).

### Сценарий B07: anonymous push → 401 challenge; authenticated-without-write → 403 DENIED

**ID:** RG-1-B07-ANON-PUSH-NEG

**Given** repo `public/img` (PUBLIC); (a) anon-клиент без токена; (b) authenticated-принципал **без**
       `v_create`/`v_update`

**When** каждый выполняет `docker push registry.kacho.local/<reg>/public/img:v2`

**Then** (a) anon push → **401** (WWW-Authenticate Bearer challenge — push требует identity; PUBLIC
       даёт только read-grant `user:*`, не write; challenge repo-независим → не oracle);
       (b) authenticated-без-write → **403 `DENIED`** (uniform push-deny, существующая shape;
       `exists`-или-нет неразличимо)
**And** ни в одном случае манифест/блоб не записывается.

### Сценарий B08: CreateRepository с visibility=PUBLIC не-admin'ом → PERMISSION_DENIED (PUBLIC только admin)

**ID:** RG-1-B08-CREATE-PUBLIC-NONADMIN-NEG

**Given** реестр `reg-1`; caller держит `v_create` (создание repo), но **не** `admin`

**When** клиент вызывает `CreateRepository{ repository:"open/x", visibility:PUBLIC }`

**Then** gRPC **`PERMISSION_DENIED "creating a public repository requires registry admin"`**
       (D-6: **любой** путь к PUBLIC требует admin — включая create-with-PUBLIC; v_create-only принципал
       создаёт лишь PRIVATE)
**And** overlay-строка не создаётся (create отвергнут целиком, не «создан PRIVATE молча»)
**And** тот же вызов **без** `visibility` (→ наследует `default_visibility=PRIVATE`) — Operation OK (PRIVATE).
       Инверсия — inherited-**public** при admin-заданном `default_visibility=PUBLIC`: **B12** (не-admin
       create без `visibility` → PUBLIC + `user:*` tuple, gate-at-default; отличается от **явного** PUBLIC здесь).

### Сценарий B09: конкурентные visibility-flip → детерминированное итоговое состояние + tuple-конвергенция

**ID:** RG-1-B09-FLIP-CONCURRENT-CONC

**Given** durable-repo `race/img` (`visibility=PRIVATE`); два admin-caller'а

**When** параллельно: `Update{visibility:PUBLIC}` и `Update{visibility:PRIVATE}`

**Then** overlay `visibility` сериализуется (single-statement UPDATE / xmin-OCC) → итог **детерминирован**
       (одно из PUBLIC/PRIVATE, last-writer по commit-порядку), без потерянного/расщеплённого состояния
**And** presence FGA-tuple `user:* v_get …` **конвергирует** к итоговому `visibility` (outbox-emission
       идемпотентна и at-least-once по финальному состоянию — не «tuple есть, а visibility=PRIVATE»)
**And** integration-тест под `-race` (детерминированно, не `time.Sleep`) фиксирует конвергенцию.

### Сценарий B10: не-admin UpdateRegistry{default_visibility=PUBLIC} → PERMISSION_DENIED

**ID:** RG-1-B10-REGDEFAULT-NONADMIN-NEG

**Given** реестр `reg-1` (`default_visibility=PRIVATE`); caller держит `v_update` на реестре, но **НЕ** `admin`

**When** клиент вызывает `RegistryService/Update` (`UpdateRegistry`) с `update_mask=["defaultVisibility"]`,
       `defaultVisibility=PUBLIC`

**Then** gRPC **`PERMISSION_DENIED "changing default visibility to public requires registry admin"`**
       (D-6: any-path-to-PUBLIC-admin-gate распространяется и на `Registry.default_visibility` — установка
       публичного дефолта = «путь к PUBLIC»; не-admin не может открыть реестр «оптом»)
**And** `default_visibility` не изменён; **тот же** caller с `update_mask=["description"]` → Operation OK
       (admin-gate узок — только на переход `default_visibility→PUBLIC`, editor-путь не сломан).

### Сценарий B11: admin UpdateRegistry{default_visibility=PUBLIC} → Operation OK

**ID:** RG-1-B11-REGDEFAULT-ADMIN-HAPPY

**Given** реестр `reg-1` (`default_visibility=PRIVATE`); caller держит **`admin`** на `registry_registry:<reg>`

**When** клиент вызывает `UpdateRegistry` с `update_mask=["defaultVisibility"]`, `defaultVisibility=PUBLIC`

**Then** Operation → `done=true` без `error`; `GetRegistry(<reg>)` → `defaultVisibility=PUBLIC`
**And** существующие repo **не** перекрашиваются (default — сид только для **новых** repo; per-repo overlay
       `visibility` остаётся authoritative, D-6) — их `visibility` без изменений, `user:*`-tuple'ы не трогаются.

### Сценарий B12: inheritance edge — default=PUBLIC, v_create-only не-admin CreateRepository без visibility → PUBLIC + user:* tuple

**ID:** RG-1-B12-INHERIT-PUBLIC-CREATE-EDGE

**Given** реестр `reg-1` с `default_visibility=PUBLIC` (установлен admin'ом, B11); caller-C держит
       **только** `v_create` на реестре (НЕ `admin`, НЕ `v_update`)

**When** caller-C вызывает `CreateRepository{ registryId:<reg>, repository:"open/inherited" }` **без**
       поля `visibility` (UNSPECIFIED)

**Then** Operation → `done=true` без `error`; `response`/`GetRepository(open/inherited)` →
       **`visibility=PUBLIC`** (унаследован из admin-заданного `default_visibility`; **gate-at-default**,
       НЕ escalation — admin уже авторизовал «этот реестр публичен по умолчанию», D-6)
**And** FGA-tuple **`user:* v_get registry_repository:<reg>/open/inherited`** эмитится через fga-proxy
       (governance по **итоговому** PUBLIC-состоянию, D-7 — inherited-public порождает tuple так же, как
       явный flip B01); anon `docker pull …/open/inherited:<tag>` → 200 (мост к B03)
**And** контраст с **B08**: тот же не-admin, задав `visibility=PUBLIC` **явно**, получил бы `PERMISSION_DENIED`
       — явный путь к PUBLIC требует admin; наследование admin-дефолта — не требует (это и есть закреплённая
       граница «inherited-default vs explicit», а не незакрытая escalation-дыра).

### Сценарий B13: IAM anon-token issuance — /token без Basic-creds → user:* read-only, аудитория, bounded TTL

**ID:** RG-1-B13-ANON-TOKEN-ISSUE-HAPPY

**Given** IAM token-endpoint реестра доступен; клиент **не** предъявляет Basic-creds (docker anon-flow)

**When** клиент запрашивает токен на pull-scope без `Authorization: Basic …`:
       `GET /token?service=<registry>&scope=repository:<reg>/public/img:pull`

**Then** IAM выдаёт **Bearer-токен**, subject которого резолвится в FGA-принципал **`user:*`**; токен несёт
       **только read-verb** (`pull`/`v_get`), **аудиторию = registry data-plane** service, **ограниченный,
       короткоживущий TTL** (bounded)
**And** токен **не** несёт write-scope и **не** несёт identity конкретного пользователя (аноним = wildcard);
       при предъявлении на data-plane read PUBLIC-repo → Check `user:*` проходит (мост к B03)
**And** **enforcement TTL-истечения и audience — унаследованы** от существующего Bearer-JWT/JWKS
       data-plane AuthN, RG-1 **не** вводит новый механизм: просроченный anon-token → **401 challenge**
       (как любой expired-JWT на data-plane), а anon-token с аудиторией registry data-plane, «переигранный»
       на **другом** endpoint, отвергается audience-mismatch'ем существующим валидатором. RG-1 лишь
       **сужает scope** выдаваемого токена (read-only / `user:*`), не ослабляя expiry/audience-контроль —
       тестеру: это **inherited-guarantee**, а не uncovered gap (отдельный сценарий не требуется).

### Сценарий B14: anon-token не несёт write-verb → docker push pull-able PUBLIC-repo → 403 DENIED

**ID:** RG-1-B14-ANON-TOKEN-NOWRITE-NEG

**Given** anon-token с `user:*`/read-only scope (B13); PUBLIC-repo `public/img`, который этим токеном
       успешно **читается** (B03)

**When** клиент с anon-token'ом выполняет `docker push registry.kacho.local/<reg>/public/img:v2`
       (запрашивает `scope=…:push`)

**Then** push отвергается: у anon-token'а **нет** write-verb ⟹ Check `user:* v_create/v_update` deny →
       **403 `DENIED`** (uniform push-deny; PUBLIC даёт `user:*` **только** read-grant, не write —
       публичность репозитория **не** открывает анонимную запись, даже в repo, который токен может тянуть)
**And** ни манифест, ни блоб не записываются.

> B13/B14 — контракт **минтинга** anon-token (kacho-iam), который end-to-end упражняют B03/B04 (pull).
> Anon-token — острейшая новая attack-surface: minting-контракт закреплён **отдельными** сценариями, а не
> только транзитивным pull-покрытием (`security.md §AuthN+AuthZ ВЕЗДЕ` — read-only floor, bounded TTL,
> no write-verb).

---

## Группа C — ListReferrers (read-only проекция referrer-графа; якорь под signing/scanning)

> Инвариант: read-проекция, existence-hidden (`v_get`), без инфра-полей (overview §1 Artifact/Referrer,
> §3 signing/scanning preserve isolation). Data-plane `routeReferrers` уже существует (`servePullOnly
> relVGet`) — RG-1 добавляет CP-проекцию + `Referrer`-message.

### Сценарий C01: ListReferrers(subject_digest) → referrer-проекции + artifact_type facet

**ID:** RG-1-C01-REFERRERS-HAPPY

**Given** durable/ephemeral repo `img/app` с манифестом `subject` (digest `sha256:<D>`), к которому в
       движке привязаны referrer-артефакты (напр. signature + SBOM); caller держит `v_get` на repo

**When** клиент вызывает `ListReferrers` (REST `GET /registry/v1/registries/<reg>/repositories/img/app/referrers?subjectDigest=sha256:<D>`)

**Then** sync-ответ — список `Referrer` (`registryId`, `repository`, `subjectDigest=sha256:<D>`, `digest°`,
       `artifactType°` (media-type facet), `sizeBytes°`, `annotations°`, `createdAt°` truncate-до-секунд)
**And** повторный вызов с `?artifactType=<mediaType>` возвращает **отфильтрованное** подмножество
       (server-side facet по OCI `artifactType`)
**And** ответ — **bounded full-set** одного `subject_digest` (server-side cap как у catalog-page 1000),
       **без** `page_token`/`page_size` (D-8; зеркалит OCI single-index `/referrers/<digest>`; cursor-
       пагинация — follow-up, §2 Non-goals)
**And** ответ не несёт инфра-полей (scanner-engine id / blob-layout / host — те Internal-only, §Non-goals).

### Сценарий C02: ListReferrers — unauthorized ИЛИ absent repo → NOT_FOUND (existence-hiding)

**ID:** RG-1-C02-REFERRERS-EXISTENCE-HIDING-NEG

**Given** (a) repo `secret/app`, caller без `v_get`; (b) absent `ghost/app`

**When** клиент вызывает `ListReferrers` для (a) и (b)

**Then** **оба** → gRPC **`NOT_FOUND "repository not found"`** (одинаково; existence-hiding, parity с
       GetRepository/ListTags).

### Сценарий C03: ListReferrers subject без referrer'ов → пустой список (не 404)

**ID:** RG-1-C03-REFERRERS-EMPTY-EDGE

**Given** repo `img/app` (caller держит `v_get`), digest `sha256:<E>` существует, но referrer'ов не имеет

**When** клиент вызывает `ListReferrers(subjectDigest=sha256:<E>)`

**Then** sync-ответ — **пустой** `referrers=[]` c `200`/OK (авторизованный доступ к repo подтверждён;
       «нет referrer'ов» ≠ «нет доступа/repo» — не смешиваем с existence-hiding-404).

### Сценарий C04: ListReferrers malformed subject_digest → INVALID_ARGUMENT

**ID:** RG-1-C04-REFERRERS-BAD-DIGEST-NEG

**Given** repo `img/app`

**When** клиент вызывает `ListReferrers(subjectDigest="not-a-digest")` (не `sha256:<64-hex>` / OCI-digest grammar)

**Then** синхронный gRPC **`INVALID_ARGUMENT "invalid subject digest 'not-a-digest'"`**
       (валидируется до repo/engine-вызова).

---

## Группа D — back-compat: register-on-first-push / unregister-on-last-tag взаимодействие с overlay

> Инвариант: overlay **НЕ ломает** существующий data-plane lifecycle (D-1/D-2). Ephemeral-путь —
> байт-в-байт как сегодня; durable-путь — новое survives-empty поведение.

### Сценарий D01: push в repo без pre-created overlay → register-on-first-push (ephemeral, PRIVATE)

**ID:** RG-1-D01-BACKCOMPAT-FIRSTPUSH-HAPPY

**Given** имя `fresh/svc` в `<reg>` свободно (ни overlay, ни проекция); авторизованный push-принципал
       (`v_create@registry_registry:<reg>`)

**When** принципал выполняет `docker push registry.kacho.local/<reg>/fresh/svc:v1` (успешный manifest-PUT)

**Then** register-on-first-push **по-прежнему** материализует проекцию + per-repo FGA-authz (parent+owner
       tuple) — **как сегодня** (back-compat, overlay-строка **не** создаётся)
**And** `GetRepository(fresh/svc)` → `Repository` (ephemeral: `visibility=PRIVATE` дефолт, `createdAt` пуст,
       `tagCount=1`); `ListRepositories` показывает его (row-filter `v_list`).

### Сценарий D02: удаление последнего тега EPHEMERAL-repo → репозиторий исчезает (unchanged)

**ID:** RG-1-D02-BACKCOMPAT-LASTTAG-VANISH-EDGE

**Given** ephemeral-repo `fresh/svc` (D01, единственный тег `v1`, overlay нет)

**When** клиент вызывает `DeleteTag(registryId=<reg>, repository="fresh/svc", tag="v1")` → Operation done

**Then** unregister-on-last-tag снимает проекцию/authz (**как сегодня**); `GetRepository(fresh/svc)` →
       **`NOT_FOUND`** (ephemeral исчез при опустошении — поведение не изменилось).

### Сценарий D03: удаление последнего тега DURABLE-repo → репозиторий переживает (survives-empty)

**ID:** RG-1-D03-DURABLE-LASTTAG-SURVIVES-EDGE

**Given** durable-repo `keep/svc` (overlay есть, единственный тег `v1`)

**When** клиент вызывает `DeleteTag(repository="keep/svc", tag="v1")` → Operation done

**Then** проекция опустошается, но overlay-строка + per-repo FGA-authz **сохраняются** (durable,
       unregister-on-last-tag **не** срабатывает при наличии overlay)
**And** `GetRepository(keep/svc)` → `Repository` с `tagCount=0` (репозиторий пережил пустоту — ключевое
       новое поведение overlay, overview §5 #1).

### Сценарий D04: push в pre-created пустой durable-repo → теги появляются, overlay-config сохранён

**ID:** RG-1-D04-PUSH-INTO-PRECREATED-EDGE

**Given** durable-repo `pre/app` создан `CreateRepository` (A01, tagCount=0, `labels={team:core}`,
       `visibility=PRIVATE`); авторизованный push-принципал

**When** принципал выполняет `docker push registry.kacho.local/<reg>/pre/app:v1`

**Then** push успешен; проекция материализует тег `v1`; owner-tuple толкавшего эмитится (immediate-pull
       мост REG-33 работает как обычно)
**And** `GetRepository(pre/app)` → `tagCount=1`, `labels`/`visibility`/`createdAt` из overlay **сохранены**
       (register-on-first-push поверх durable — no-op для config, overlay-строка не перезаписывается).

### Сценарий D05: CreateRepository гонится с first-push того же имени → когерентный durable-с-контентом

**ID:** RG-1-D05-CREATE-VS-PUSH-CONC

**Given** имя `race2/svc` в `<reg>` свободно; один принципал держит и `v_create`

**When** параллельно: (a) `CreateRepository(repository="race2/svc")` и (b) `docker push …/race2/svc:v1`

**Then** overlay-insert (DB-UNIQUE) и projection-материализация — **независимые слои** над `(registry_id,
       name)`: итог всегда когерентен — durable-repo `race2/svc` с overlay-config **и** тегом `v1`
       (adopt-семантика D-3); ни двойной overlay-строки, ни осиротевшего контента
**And** owner-tuple'ы **аддитивны** (как A03): и Create-caller, и first-push-пушер получают/сохраняют
       owner-grant — независимо от порядка выигрыша гонки ни один owner не снимается
**And** сервис не отдаёт `INTERNAL` с pgx-leak; integration-тест (testcontainers + fake-engine push)
       фиксирует отсутствие расщеплённого состояния.

---

## Группа X — cross-cutting: изоляция, fail-closed, INTERNAL-no-leak

### Сценарий X01: публичный Repository/Referrer message не несёт инфра-полей (projection-audit)

**ID:** RG-1-X01-NO-INFRA-LEAK-CONF

**Given** любой durable-repo с контентом; каналы Get/List/ListReferrers

**When** клиент читает `GetRepository` / `ListRepositories` / `ListReferrers`

**Then** ни одно поле ответа не раскрывает: engine namespace/bucket-prefix/storage-driver, host/placement,
       числовой инфра-id, scan-queue/scanner-engine-id (`security.md §Инфра-чувствительные данные`) —
       только tenant-intent (`name`/`labels`/`visibility`/`description`) + result-counts (`tagCount`/
       `sizeBytes`/timestamps/`downloadCount`)
**And** gateway projection-audit (аналог `make audit-list-filter`) гейтит, что additively-добавленное поле
       не утекло на external-поверхность; `RegistryStats`/`GetRegistryStats` остаются Internal-only (:9091).

### Сценарий X02: DB-ошибка в overlay-мутации → фикс. INTERNAL-текст (без pgx-leak)

**ID:** RG-1-X02-INTERNAL-NO-LEAK-NEG

**Given** индуцированный не-sentineled DB-сбой на пути `CreateRepository`/`UpdateRepository`/
       `DeleteRepository`/`RenameRepository` (напр. connection-drop)

**When** клиент вызывает соответствующую мутацию

**Then** ответ (sync-ошибка или Operation `error`) — gRPC **`INTERNAL`** с **фиксированным** текстом
       **`"internal database error"`** (default-ветка `serviceerr`; `security.md §Hardening` #1)
**And** сообщение **не содержит** сырого pgx/driver-текста (host/port/user/db/SQL) — behaviour-level:
       assert `status.Convert(err).Message() == "internal database error"` **и**
       `NotContains(msg, <raw-pgx-text>)` (`testing.md §Regression-lock`).

### Сценарий X03: fga-proxy/iam недоступен при visibility-flip → outbox-эмиссия переживает (at-least-once)

**ID:** RG-1-X03-FGA-OUTBOX-RESILIENCE-EDGE

**Given** durable-repo `pub/x`; admin flip → PUBLIC; fga-proxy (iam) временно недоступен

**When** `UpdateRepository{visibility:PUBLIC}` коммитит overlay-строку, но эмиссия `user:* v_get`-tuple
       в моменте не доходит до iam

**Then** overlay-мутация **не** откатывается из-за недоступности iam (tuple-эмиссия — transactional-outbox,
       at-least-once, **не** синхронный cross-service call на commit-пути); Operation → `done=true`
**And** после восстановления iam outbox-drainer до-эмитит `user:* v_get`-tuple (идемпотентно) → anon pull
       PUBLIC становится 200 без ручного вмешательства (eventual, `architecture.md §outbox`).

> Примечание: это **не** ослабляет fail-closed для data-plane read — пока tuple не материализован, anon
> Check `user:*` deny → 404 (fail-safe: repo остаётся приватным до появления grant, не «открыт по ошибке»).

### Сценарий X04: CreateRepository в реестре, недоступном/невидимом caller'у → NOT_FOUND (namespace call-gate)

**ID:** RG-1-X04-CREATE-NAMESPACE-HIDING-NEG

**Given** реестр `reg-1` существует, но caller **не** член его project (нет `v_list`/`v_create` на namespace)

**When** клиент вызывает `CreateRepository(registryId=<reg>, repository="x/y")`

**Then** gRPC **`NOT_FOUND`** (namespace call-gate: невидимый реестр existence-hidden, parity с
       `ListRepositories` namespaceGate — не `PERMISSION_DENIED`, иначе утечка существования реестра)
**And** overlay-строка не создаётся.

---

## Traceability (сценарий → источник → инвариант)

| Группа | Сценарии | Источник (overview / rule) | Инвариант |
|---|---|---|---|
| A overlay lifecycle | RG-1-A01..A24 | overview §2 «Repo-management», §5 #1 | `data-integrity.md §Within-service` (UNIQUE/CHECK/CAS, ban #10); `api-conventions.md` (async Op, update_mask, malformed-first, pagination); rename fail-closed (§Cross-domain) + ephemeral auto-promote (A23, D-5); registry-DELETING ACTIVE-guard (A24); List overlay ⊔ projection row-filter (`security.md §List-filter`) |
| B visibility + anon + reg-default | RG-1-B01..B12 | overview §2 «Public/private/anon», §3, §5 #2; D-6/D-7 | `security.md §Публичная поверхность` (existence-hiding, PUBLIC-only-admin, gate-at-default inheritance, `user:*` governance) |
| B anon-token (iam) | RG-1-B13..B14 | overview §3 «Public/anonymous pull», D-7; kacho-iam | `security.md §AuthN+AuthZ ВЕЗДЕ` (anon = `user:*`, read-only floor, bounded TTL, no write-verb) |
| C ListReferrers | RG-1-C01..C04 | overview §1 Referrer, §2 «Repo-management» | read-projection existence-hidden; Internal-vs-public |
| D back-compat | RG-1-D01..D05 | overview §2 `[x]` register/unregister lifecycle | overlay ⟂ projection (D-1/D-2), no-regression |
| X cross-cutting | RG-1-X01..X04 | overview §3 isolation | `security.md §Hardening` #1 (INTERNAL-no-leak), §Инфра-данные; `data-integrity.md §Cross-domain` (fail-closed) |

**Named verification paths (two-way traceability, §4.4 — ни один in-scope сценарий не orphan):**
- **RG-1-X01-NO-INFRA-LEAK-CONF** — verified-by: **gateway projection-audit gate** (аналог
  `make audit-list-filter`: additively-добавленное поле `Repository`/`Referrer` не течёт на external-mux) +
  **message-schema review** публичного `Repository`/`Referrer` (`proto-api-reviewer`: ни engine/bucket/host/
  числовой-инфра-id; `RegistryStats`/`GetRegistryStats` остаются Internal-only :9091). Это не Go-unit RED-кейс,
  а гейт-проверка — поэтому вынесен явным verified-by, чтобы не считаться неверифицированным.
- Остальные `RG-1-<Group><NN>` — integration (testcontainers) + newman-кейсы, ID трассируется в имя теста.

ID'ы (`RG-1-<Group><NN>`) трассируются в имена integration- и newman-кейсов.

---

## DoD / acceptance checklist (per-stage; TDD — RED до кода, ban #12)

**Stage proto** — `kacho-proto`:
- [ ] `Repository` += `description`/`labels`/`visibility`/`created_at`; `enum Visibility`; `Registry` +=
      `default_visibility` (mutable через `UpdateRegistry`, admin-gate на →PUBLIC — B10/B11);
      `Referrer`-message; 6 новых RPC (Get/Create/Update/Delete/Rename Repository + ListReferrers) с
      REST-annotations (`{repository=**}`), Op-envelope, authz-options (permission/required_relation/
      scope_extractor/acr_min).
- [ ] `RenameRepositoryRequest{registry_id, repository, new_name}` — `new_name` **голое** repo-имя (без
      target-registry поля, D-5); `ListReferrers` — bounded (без `page_token`/`page_size`, D-8).
- [ ] `buf lint` / `buf breaking` / `buf validate` зелёные; `gen/go` регенерирован.
- [ ] `permission-catalog` регенерирован (`make permission-catalog`), обе embedded-копии byte-identical,
      CI drift-gate зелёный (`security.md` #4).

**Stage iam** — `kacho-iam`:
- [ ] RED-тесты первыми: **B13** anon-token issuance (token без Basic-creds → subject `user:*`, **read-only
      scope**, аудитория = registry data-plane, **bounded TTL**); **B14** anon-token без write-verb → `docker
      push` → **403/DENIED**; `user:*` v_get wildcard register/unregister через fga-proxy.
- [ ] Код: anon-token путь (read-only scope, bounded TTL, no write-verb) + wildcard-tuple governance;
      integration + newman (B13 token-issue happy / B14 push-deny negative; anon pull PUBLIC happy /
      PRIVATE→404 negative).

**Stage registry** — `kacho-registry`:
- [ ] RED-тесты первыми (unit use-case через fake-порты + integration testcontainers):
      A02/A04/A05/A06/A08/A10/A11/A14/A15/A17/A18/A19/A21/A22/A24 (negatives+edge+concurrency, exact-code+text;
      **A24** = registry-DELETING ACTIVE-guard → FAILED_PRECONDITION),
      B02/B04/B05/B07/B08/B10/B12/B14 (existence-hiding+anon+admin-gate+inherit-guard), C02/C04,
      D02/D03/D05, X02/X03/X04; happy/edge A01/A03/A07/A09/A12/A13/A16/A20/A23 (**A23** = rename-ephemeral
      auto-promote → durable/survives-empty), B01/B03/B06/B09/B11, C01/C03, D01/D04.
- [ ] **X01 (no-infra-leak)** — verified-by: gateway projection-audit gate (аналог `make audit-list-filter`,
      additively-added поле не течёт на external) + message-schema review публичного `Repository`/`Referrer`
      (`proto-api-reviewer`); `RegistryStats` остаётся Internal-only (:9091). Не Go-unit RED, а гейт-проверка
      (§4.4 two-way traceability — сценарий не orphan).
- [ ] Миграция (goose): таблица `repository_configs` (PK/`UNIQUE(registry_id, name)`,
      `visibility` CHECK-домен, `created_at`); FK `registry_id → registries(id)` same-DB (ON DELETE
      CASCADE — реестр сносит свои overlay); одностейтментная запись под UNIQUE-backstop для rename
      (re-key `UPDATE` для durable / `INSERT` для ephemeral-promote, D-5/A23) + CAS для visibility.
      **db-architect-reviewer** ревьюит.
- [ ] Repo(sqlc)+handler+outbox (`user:*` tuple emission по **итоговому** visibility — включая inherited-
      public на create, B12) + use-case: overlay⟂projection JOIN; **List result-set = overlay ⊔ projection**
      с `v_list` row-filter (A20); adopt-семантика **аддитивна по owner-tuple** (A03/D05); admin-gate на
      `visibility`-mask **И** на `Registry.default_visibility→PUBLIC` (B10/B11); reject-if-tags worker-
      precondition; **registry-status ACTIVE-guard** (same-DB read `registries.status`; `DELETING` →
      `FAILED_PRECONDITION "registry is being deleted"` для всех overlay-мутаций, A24); rename engine-remap
      **fail-closed `UNAVAILABLE`** без частичного состояния (A21) + **auto-promote ephemeral→durable**
      (`INSERT` overlay под `new_name`, A23); payload-границы labels/description/unicode из `corelib/validate`
      (`MaxLabels=64`/`MaxLabelKeyLen=MaxLabelValueLen=63`/`MaxDescriptionLen=256` rune, A22).
- [ ] Data-plane: anon-принципал (`user:*`) read-path; PUBLIC→200 / PRIVATE|absent→uniform 404 /
      anon-push→401; existing shapes (403 push-deny, 503 dep-down) без регрессии.
- [ ] `RenameRepository` engine-remap (теги/манифесты/referrers под новым именем; старое→404) +
      FGA re-register; **durable re-key `UPDATE`** (A16) и **ephemeral auto-promote `INSERT`** (A23) —
      оба пути покрыты; `ListReferrers` engine-projection.
- [ ] Newman: ≥1 happy (A01/B03) + ≥1 negative (A02/B04/B05) через api-gateway.
- [ ] `go test ./... -race` + `golangci-lint` + `govulncheck` + `make audit-list-filter` зелёные;
      error-тексты assert'ятся behaviour-level (X02 no-leak).

**Stage gateway/deploy** — `kacho-api-gateway` (public-mux регистрация 6 RPC через `api-gateway-registrar`;
Internal.* не на external, `security.md` ban #6) · `kacho-deploy` (helm/compose, anon-token config).

**Stage docs/vault** — `kacho-workspace`: новые vault-записки `resources/registry-repository.md`
(overlay⟂projection, natural-key, durable-vs-ephemeral, visibility), `rpc/registry-registry-service.md`
(6 новых RPC), `edges/registry-to-iam-anon-public.md` (anon-token + `user:*` governance); статус дока → APPROVED.

**Ревью-роли (шаг 6):** `proto-api-reviewer` (proto) · `db-architect-reviewer` (миграция/CAS/UNIQUE/CHECK) ·
`go-style-reviewer` · `system-design-reviewer` (outbox at-least-once, adopt-race D05, visibility-CAS B09).

**Финал (шаг 7):** заказчик — smoke/e2e (`make e2e-test`; anon `/token` без creds → `docker pull` anon-public
+ uniform-404 anon-private; anon push → 403; `grpcurl` CreateRepository→Get durable-empty; `ListRepositories`
показывает durable-empty; admin `default_visibility=PUBLIC` → не-admin create без `visibility` → PUBLIC (+anon 200);
visibility flip → anon 200↔404; rename durable old→404/new→200; rename **ephemeral** (pushed-но-неконфиг)
→ new durable survives-empty после DeleteTag (A23); repo-мутация в `DELETING`-реестре → FAILED_PRECONDITION (A24)).
