# Kachō · Registry (`kacho-registry`) — целевой tenant-facing дизайн

> [!note] Переписано под действующую модель 2026-08-07 (замер на `0d1ed3b8`)
> Прежняя редакция была построена вокруг ресурса **`Namespace`** с префиксом `ns-` и вокруг
> **`globalSlug°`** — человекочитаемого первого сегмента pull-пути. Оба решения **отменены**
> владельцем 2026-07-20 (`integration-status.md`, приёмка
> `docs/specs/sub-phase-REG-1-registry-repository-acceptance.md`), а второе с тех пор — прямое
> нарушение **core rule #15**. Документ приведён к дереву; шапка называет, что именно правилось,
> и предикат для каждой строки — чтобы следующая сверка была перемером, а не чтением.
>
> | Что стояло | Что в дереве | Предикат |
> |---|---|---|
> | ресурс `Namespace`, prefix `ns` | `message Registry`, `PrefixRegistry = "reg"` | `grep -ro 'Namespace' proto/kacho/cloud/registry/ \| wc -l` → **0**; `grep -n PrefixRegistry pkg/ids/ids.go` |
> | `globalSlug°` в pull-пути, bare-global opt-in, `UNIQUE(global_slug)` | поля нет ни в контракте, ни в схеме; pull-путь `$domain/$registryId/$repo:$tag` | `grep -rn 'global_slug' proto/ services/registry/internal --include=*.proto --include=*.go` → **0**; `grep -rn 'UNIQUE' services/registry/internal/migrations/*.sql` |
> | `RenameNamespace` → `:rename` на реестре | RPC нет; единственный rename — `RenameRepository` | `grep -o '^  rpc [A-Za-z]*' proto/kacho/cloud/registry/v1/registry_service.proto` |
> | `name` immutable | `name` **mutable** через `Update`; immutable-набор — `id`/`projectId`/`regionId`/`placementType` | `services/registry/internal/apps/kacho/api/registry/validate.go` (`immutableUpdateFields`) |
> | 21 public RPC, включая `GetEffectiveAccess`, `ListRepositoryGrants`, `ListEffectiveSubjects`, `GetImage`, `DeleteImage` | **15** public RPC; ни одного из перечисленных пяти | `grep -c '^  rpc ' …/registry_service.proto` → **15**; `grep -rl 'EffectiveAccess' --include=*.proto --include=*.go .` → **0** |
> | REST-база `/registry/v1/namespaces/…` | `/registry/v1/registries/…` | `grep -o '"/registry/v1/[^"]*"' …/registry_service.proto` |
> | операции с префиксом `epd`, поллинг `/registry/v1/operations/{id}` | префикс `rop`; поллинг единого края `/operations/{id}` | `grep -n PrefixOperationReg pkg/ids/ids.go`; `proto/kacho/cloud/operation/operation_service.proto` |
> | «Все RPC несут `scope_extractor`» | `scope_extractor` у **5** из 15; у **10** край объявлен `<exempt>`, Check и существование-скрытие делает handler | `grep -c '"<exempt>"' …/registry_service.proto` → **10** |
> | роли `registry.repoCreator`/`puller`/`pusher`/`admin` | таких ролей в дереве нет; доступ выдаётся каталожными системными ролями и глаголами `v_*` | `grep -rn 'repoCreator' --include=*.go --include=*.sql .` → **0** |
>
> **Что уцелело и переписано не было** (эта работа от отката не зависела): docker
> access-control (identity iam ⊕ FGA-Check ⊕ тонкий data-plane), two-projection изоляция,
> overlay ⟂ projection у `Repository`, lifecycle `DURABLE`/`EPHEMERAL`. Блокер «перевести
> FGA-типы под tenant-имя» **снят как утративший предмет**: `registry_registry` /
> `registry_repository` соответствуют ресурсу, переводить нечего, Rosetta не нужна.
>
> **Остаточный след отката, который ещё жив в дереве** (называю, а не чиню — это чужой файл):
> `pkg/ids/ids.go`, список router-классификации `hyphenFormPrefixes`, несёт запись `"ns"` с
> комментарием «registry: Namespace». Это приём формы, которую сегодня **никто не эмитит**:
> генерация реестра — `ids.NewID(ids.PrefixRegistry)`, слитная форма `reg…`.

*Один продукт, форма-якорь — compute: flat-ресурс без envelope, `Get`/`List` sync, мутации →
`Operation`, sync-каталоги рядом с мутацией, reference-law по классу ссылки, two-projection,
единый тон ошибок. Домен `kacho.cloud.registry.v1`, схема `kacho_registry`, id-префикс ресурса
`reg`, op-префикс домена `rop`. Рёбра наружу — **только исходящие**: `registry → geo`
(существование региона) и `registry → iam` (существование проекта, per-RPC Check, регистрация
owner-tuple, публичный JWKS). Ни одного вызова обратно в consumer'ов — ацикличность держится by
construction. Вендор-нейтральность (ban #2): в прозе — «движок реестра», «OCI-артефакт»; имён
чужих облаков и движков нет ни в полях, ни в типах, ни в значениях.*

Легенда: `°` — **output-only** (сервер выставляет, на вход не принимается); `⊘` — обязательный
immutable-after-Create вход. JSON — camelCase через REST-край. Cross-service ссылки (`projectId`,
`regionId`) — TEXT **без FK**, валидируются peer-API владельца; within-service ссылки — настоящие
FK в одной БД.

---

## Ментальная модель

Пять опор. У каждой — ОДИН источник истины; всё остальное — проекция.

1. **`Registry` — тенантская единица группировки образов и единственный ресурс домена со своей
   генерируемой строкой** (SoT = `kacho_registry.registries`). Prefix `reg`, project-scoped,
   **REGIONAL** (anycast — зоны не несёт), async CRUD → `Operation`. Всё внутри адресуется
   относительно него. **Идентичность — одна, и она в URL:** `id` immutable, глобально-уникален
   by construction, и это **единственная** внешне-адресуемая координата (core rule #15). `name` —
   косметический project-scoped label (`UNIQUE(project,name)` среди живых), меняется обычным
   `Update` и **не участвует в адресации**. Слово «namespace» в этом домене — индустриальный
   термин OCI («реестр как namespace образов»), а не имя ресурса.

2. **`Repository` — overlay ⟂ projection над натуральным ключом `(registryId, name)`**
   (SoT = DB-строка наложения `repository_configs` ДЛЯ намерения; SoT = движок ДЛЯ результата).
   Два ортогональных слоя над ОДНИМ ключом: durable-наложение (`description`/`labels`/
   `visibility`/`createdAt°`) переживает пустоту; read-only проекция (`tagCount°`/`sizeBytes°`/
   `artifactTypes°`/…) существует, пока есть содержимое. Публичный `Repository` = LEFT JOIN.
   Генерируемого id **нет** — осознанное исключение из хребта: OCI-имена несут `/`
   (`backend/api`). `lifecycle°`-enum авторитетно сигналит исчезаемость.

3. **`Tag` и `Referrer` — read-only проекции движка** (SoT = движок). Тенант их не «создаёт»
   через control-plane — они материализуются на `docker push`. `Tag` = mutable указатель
   (`tag → digest°`) на immutable контент; `Referrer` = узел OCI-1.1 графа артефактов
   (подпись / SBOM / аттестация), привязанный к `subjectDigest`. **Digest — content-address,
   а не отдельный ресурс.**

4. **Docker access-control = identity (iam) ⊕ authz (FGA-Check) ⊕ тонкий data-plane**
   (SoT identity = iam/Hydra). Ключ сервис-аккаунта → прозрачный OCI Bearer-challenge
   (`WWW-Authenticate: Bearer realm=…`) → `docker login` → per-request `InternalIAMService.Check`
   на `registry_repository:<registryId>/<repo>` → reverse-proxy в движок. Движок **никогда не на
   wire**. Анонимный pull = FGA `user:*`. Долгоживущий credential — **ключ сервис-аккаунта в
   iam**; short-TTL Bearer прозрачно ре-минтится credential-helper'ом. Собственного
   credential-ресурса registry **не заводит** (identity — концерн iam, ребро `registry → iam`
   ациклично).

5. **Two-projection изоляция — нерушимый инвариант** (SoT инфры = `Internal*` :9091). Публичная
   поверхность = намерение (реестр / репозиторий / тег / digest) + результат (счётчики, размеры,
   отметки времени). Engine-namespace, bucket объектного хранилища, storage-driver, blob-layout,
   числовой инфра-идентификатор, очередь сборки мусора — **только** `Internal*`. Каждый отказ на
   чтении — существование-скрытие (`NOT_FOUND`, байт-в-байт как настоящий промах).

---

## Registry

> **`Registry`** — тенантский реестр образов. Хост обслуживания называется `endpoint°` и
> производится **по id**: `<serving-host>/<registryId>`. Реестр целиком не пуллится — pull всегда
> адресует `Repository` внутри него.

Flat, prefix `reg`, project-scoped, **REGIONAL**. Async CRUD → `Operation`.

```jsonc
{
  "id": "reg7h9x2k4m8p0q1r5",          // ⊘ prefix 'reg' + crockford-base32 (слитная legacy-форма).
                                       //   Immutable PK и ЕДИНСТВЕННАЯ внешняя адресация (core rule #15):
                                       //   операции смены id не существует — ни ':rename', ни 'rename id'.
  "projectId": "prj-7h3n9k2m5p8q1",    // ⊘ scope-координата; peer-validate iam (fail-closed)
  "regionId": "eu-north-1",            // ⊘ REGIONAL-якорь: пинит locality блобов. ОБЯЗАТЕЛЕН на Create,
                                       //   peer-validate geo.v1.RegionService.Get (промах → FAILED_PRECONDITION,
                                       //   geo недоступен → UNAVAILABLE). Immutable — перенос региона сломал бы locality.
  "placementType": "REGIONAL",         // ⊘ всегда REGIONAL («не выбор»): OCI-контент региональный by construction.
                                       //   Осознанный carve-out из LEAN-запрета на константу — ради parity
                                       //   placement-дискриминатора с compute/vpc (см. Правила п.10).
  "createdAt": "2026-07-19T08:14:22Z", // ° DB-assigned, truncate до секунд

  "name": "payments",                  // косметический project-scoped label. UNIQUE(project,name) среди ЖИВЫХ
                                       //   (partial UNIQUE WHERE status<>'DELETING'). MUTABLE через Update по
                                       //   обычной update_mask-дисциплине; смена НЕ трогает id/endpoint°/pull-путь.
  "description": "Payments team images",  // mutable
  "labels": {                          // mutable; участвуют в label-scoping прав
    "team": "payments", "tier": "prod",
    "displayName": "Payments Team"     //   человеческое имя для UI живёт ЗДЕСЬ (top-level displayName нет — parity)
  },

  "defaultRepositoryVisibility": "PRIVATE",  // mutable, admin-gated. Сид visibility для НОВЫХ Repository,
                                       //   созданных без явного visibility. Единственный рычаг видимости уровня
                                       //   реестра — сам Registry top-level `visibility` НЕ несёт; авторитетный
                                       //   гейт живёт на Repository.visibility ⟺ FGA `user:*`.
                                       //   Смена НЕ перекрашивает существующие репозитории.

  "endpoint": "registry.in-cloud.io/reg7h9x2k4m8p0q1r5",  // ° derived ПО id: "<serving-host>/<id>".
                                       //   Стабилен через любую смену name — это и есть проверяемое следствие #15.
  "repositoryCount": 12,               // ° проекция движка
  "status": "ACTIVE"                   // ° ACTIVE | DELETING (DELETING терминален: forward-only delete,
                                       //   иначе partial-UNIQUE конфликтует с повторным Create того же имени)

  // Internal-only (:9091, НИКОГДА на public): engine-namespace, bucket, storage-driver,
  //   blob-layout, числовой инфра-id — см. InternalRegistryService.
}
```

**Классы изменяемости.** `description` / `labels` / `name` — mutable. `defaultRepositoryVisibility`
— mutable **admin-gated** (любой путь к `PUBLIC` требует registry admin). `id` / `projectId` /
`regionId` / `placementType` / `createdAt` — immutable; в `update_mask` → `INVALID_ARGUMENT` с
каноничным тоном `"<field> is immutable after Registry.Create"`. Боевого состояния у реестра нет —
power-модели (`:start`/`:stop`) не выдумываем.

**Почему адресация по id, а не по человекочитаемому слагу.** Одной фразой, ради которой в этом
документе снят целый прежний раздел: **имена меняются и глобально коллизят** — слаг в URL сделал бы
pull-путь ломким при переименовании и конфликтным между тенантами, поэтому core rule #15 прямо
запрещает деривацию глобального человекочитаемого слага в URL вместо id.

---

## Repository

Overlay ⟂ projection над `(registryId, name)`. **Генерируемого id нет** — натуральный ключ.
Мутации наложения — async → `Operation`; чтение — sync.

```jsonc
{
  "registryId": "reg7h9x2k4m8p0q1r5",  // ⊘ within-service → flat id + DB FK (ON DELETE CASCADE)
  "name": "backend/api",               // имя несёт '/'; PK(registryId,name); immutable через Update —
                                       //   меняется ТОЛЬКО RenameRepository (внутри ТОГО ЖЕ реестра:
                                       //   поля целевого реестра в запросе нет, cross-registry rename
                                       //   структурно невыразим)

  // ── наложение (DB-owned намерение, durable — переживает пустой репозиторий) ──
  "createdAt": "2026-07-19T09:02:41Z", // ° момент создания наложения; пусто у ephemeral-репозитория
  "description": "Core API service images",  // mutable
  "labels": { "app": "api", "lang": "go" },  // mutable
  "visibility": "PRIVATE",             // mutable admin-gated — АВТОРИТЕТНЫЙ гейт видимости.
                                       //   PUBLIC ⟺ FGA-tuple `user:* v_get registry_repository:<reg>/<repo>`
                                       //   (анонимный pull), материализуется eventually-consistent.
                                       //   Не задано на Create → наследует Registry.defaultRepositoryVisibility.
  "lifecycle": "DURABLE",              // ° ОДИН авторитетный сигнал исчезаемости (заменил протекающий
                                       //   вывод «есть ли строка наложения»). DURABLE — survives-empty.
                                       //   EPHEMERAL — register-on-first-push, исчезает при опустошении.

  // ── проекция (read-only, SoT = движок) ──
  "tagCount": 7,                       // ° DURABLE-репозиторий с tagCount:0 всё равно виден
  "sizeBytes": 184623104,              // ° агрегат по уникальным блобам
  "artifactType": "ARTIFACT_TYPE_CONTAINER_IMAGE",   // ° доминирующий тип (первый из набора)
  "artifactTypes": ["ARTIFACT_TYPE_CONTAINER_IMAGE"],// ° НАБОР типов: контейнерный образ / helm-чарт / иной.
                                       //   Дискриминатор — config.mediaType репрезентативного манифеста:
                                       //   образ и чарт несут одинаковый top-level media-type.
  "updatedAt": "2026-07-19T11:47:03Z", // ° последний push
  "lastPulledAt": "2026-07-19T12:20:10Z", // ° нулевая отметка — ни один тег не скачивался
  "downloadCount": 4213                // °

  // Internal-only (:9091): путь репозитория в движке, blob-layout, размещение — НЕ на public.
}
```

**Два класса `lifecycle°` (для authz наблюдаемо неразличимы — анти-оракул конфигурации):**

- **`EPHEMERAL`** — путь register-on-first-push (`docker push` несуществующего имени): проекция без
  наложения, `visibility` наследуется, исчезает при опустошении. Полная обратная совместимость
  push-пути.
- **`DURABLE`** — есть строка наложения: **явный `CreateRepository` → `DURABLE` by default**
  (явное намерение создать = намерение сохранить каркас, скелет не испаряется), либо
  auto-promote `EPHEMERAL → DURABLE` при установке overlay-поля через `Update`/`Rename`.
  Survives-empty, несёт конфигурацию.

> **`lifecycle` на ВХОДЕ `CreateRepository` принимает только `UNSPECIFIED` и `DURABLE`; явный
> `EPHEMERAL` отвергается** `INVALID_ARGUMENT` с именем поля. Это не незавершённость: явный Create
> материализует строку наложения, а репозиторий со строкой наложения переживает опустошение **by
> construction** — просить при этом «исчезни, когда опустеешь» значит просить взаимоисключающее.
> Поле при этом **не снято с контракта намеренно**, хотя несёт единственное осмысленное значение:
> REST-край разбирает тело с отбрасыванием неизвестных ключей, поэтому снятое поле не отвергалось
> бы, а **молча игнорировалось** — вызывающий получил бы 200 вместо именованного отказа. Поле
> существует, чтобы отказу было чем называться. (Ср. `api-conventions.md` §«Принято-и-проигнорировано
> — ЗАПРЕЩЕНО»: это и есть третий законный исход — отвергать явно.)

**Классы изменяемости.** `description` / `labels` — mutable. `visibility` — mutable admin-gated.
`registryId` / `createdAt` — immutable. `name` — immutable через `Update` (только
`RenameRepository`). `lifecycle` / `tagCount` / `sizeBytes` / `artifactTypes` / … — output-only:
в `update_mask` → `INVALID_ARGUMENT`.

**ACTIVE-guard.** Мутация наложения в реестре со `status = DELETING` → `FAILED_PRECONDITION`;
проверка — `SELECT … FOR UPDATE` в той же транзакции, не software check-then-act (ban #10).

---

## Tag

Mutable указатель внутри репозитория (SoT = движок). Read-only проекция: control-plane «создания»
нет — материализуется `docker push`; control-plane умеет `DeleteTag` (async) и чтение.

```jsonc
{
  "registryId": "reg7h9x2k4m8p0q1r5",  // ⊘ within-service → flat
  "repository": "backend/api",         // ⊘ within-service → flat (составной ключ движка)
  "tag": "v1.4.2",                     // человеческий указатель; re-push перемещает его на новый digest
  "digest": "sha256:3f8a1c…d7e2",      // ° на что указывает СЕЙЧАС (mutable указатель → immutable контент)

  "mediaType": "application/vnd.oci.image.index.v1+json",  // ° вид манифеста
  "sizeBytes": 26743891,               // ° манифест + слои
  "architecture": "linux/amd64",       // ° "<os>/<arch>"; для multi-arch индекса — "multi-arch";
                                       //   для не-контейнерного артефакта — пусто
  "createdAt": "2026-07-19T11:46:58Z", // ° из конфига образа (build-time); пусто, если конфиг его не несёт
  "lastPulledAt": "2026-07-19T12:20:10Z", // ° нулевая отметка — тег ещё не скачивался
  "pushedBy": "sva-4k9m2n7p3q1r5t8w6", // ° субъект последнего push, если известен движку
  "downloadCount": 512                 // °
}
```

`ListTags` — курсорная пагинация (`pageSize` 0→50, максимум 1000; `nextPageToken`), как у всех
списков продукта.

---

## Referrer

Узел OCI-1.1 графа артефактов (подпись / SBOM / аттестация / generic), привязанный к
`subjectDigest`. Read-only проекция, существование-скрытие как у `Repository`. Фундамент под
подписи и сканирование.

```jsonc
{
  "registryId": "reg7h9x2k4m8p0q1r5",  // ⊘
  "repository": "backend/api",         // ⊘
  "subjectDigest": "sha256:3f8a1c…d7e2", // digest, К КОТОРОМУ привязан артефакт
  "digest": "sha256:cc33…9f10",        // ° content-address самого артефакта
  "artifactType": "application/vnd.dev.cosign.simplesigning.v1+json", // ° media-type facet;
                                       //   server-side фильтруемый параметром запроса
  "sizeBytes": 2094,                   // °
  "annotations": {                     // ° OCI-аннотации артефакта
    "org.opencontainers.image.created": "2026-07-19T11:48:00Z"
  },
  "createdAt": "2026-07-19T11:48:00Z"  // ° truncate до секунд
}
```

> **`ListReferrers` сегодня отдаёт ограниченный полный набор одного `subjectDigest`** — серверный
> потолок, как у каталожной страницы, **без** `pageToken`/`pageSize`/`nextPageToken`. Это записано
> в самом контракте, а не выведено: курсорная пагинация — заявленный follow-up (см.
> §«Не построено»). Пока её нет, тяжело подписанный subject усекается серверным потолком —
> и это названо здесь, чтобы отсутствие не читалось как молчаливое.
>
> **Имя `Referrer` в этом домене зарезервировано за OCI-графом** (индустриальный неперемещаемый
> термин). Generic-обработчик зависимости на чужой ресурс — это `reference.Referrer`, а мишень
> выдачи прав — `iam.v1.ResourceRef`; трёхстороннее разведение имён settled в
> `api-conventions.md` §«Reference-типы». Канонический rename registry-типа в `OciReferrer`
> запланирован в REG-2 (ломающее изменение домена) — Phase-0 мёртвого скелета не заводит.

---

## Getting started: от нуля до первого push

> Docker-секция ниже предполагает, что этот рецепт выполнен. `docker push` **не работает
> standalone** — под ним лежат async `Create` реестра, выбор региона, сервис-аккаунт с ключом в
> iam и выдача прав на реестр. Собрано в один исполнимый порядок; identity остаётся в iam
> (ацикличность — собственного credential registry не заводит).

**Которая система что делает:**

| Задача | Хост |
|---|---|
| сервис-аккаунт / ключ доступа / выдача прав | control-plane iam (`iam.v1.*`) через api-gateway |
| `Create` реестра, каталоги, удаление тега | control-plane registry (`/registry/v1/…`) через api-gateway |
| `docker login` / обмен токена / `push` / `pull` | `endpoint`-хост реестра (data-plane) |

```bash
# ── Шаг 1: geo — выбрать regionId (обязателен на Create) ──────────────────────
GET /geo/v1/regions
# → { "regions": [ { "id": "eu-north-1", … }, { "id": "eu-central-1", … } ] }

# ── Шаг 2: iam — ServiceAccount + ключ доступа (долгоживущий credential робота) ─
POST /iam/v1/serviceAccounts   { "projectId": "prj-7h3n9k2m5p8q1", "name": "ci-pusher" }
POST /iam/v1/serviceAccounts/{id}:createAccessKey
# → { keyId, secret }   # keyId = docker-username, secret = docker-password (секрет виден ОДИН раз)

# ── Шаг 3: registry — Create (async → поллить Operation до done) ──────────────
POST /registry/v1/registries
     { "projectId": "prj-7h3n9k2m5p8q1", "name": "payments", "regionId": "eu-north-1" }
# → Operation { "id": "rop7h9x2k4m8p0q1r5", "done": false,
#               "metadata": { "registryId": "reg7h9x2k4m8p0q1r5" } }   ← id доступен СРАЗУ, до done

GET /operations/rop7h9x2k4m8p0q1r5     # единый край операций; поллить с РЕАЛЬНОЙ паузой между поллами
# → done:true → result.response: { id, endpoint: "registry.in-cloud.io/reg7h9x2k4m8p0q1r5", … }
#   ВСЕГДА проверяй result.error ПЕРЕД тем как брать id из metadata: id аллоцируется до async-фейла,
#   и на ошибке в metadata лежит идентификатор несозданного ресурса.

# ── Шаг 4: iam — выдать сервис-аккаунту права на этот реестр ──────────────────
#   Форма запроса принадлежит iam и здесь НЕ переписывается (два места об одном предмете
#   разъезжаются): субъект + роль + якорь области + мишень. Мишень для реестра — ResourceRef
#   с типом `registry.registries` и id реестра; для отдельного репозитория — `registry.repositories`.
#   Точная схема запроса — module-iam.md; глаголы, которые нужны, — таблица в §«Права» ниже.

# ── Шаг 5: docker — login + push (одна login-команда покрывает push и pull) ───
docker login registry.in-cloud.io -u <keyId> -p <secret>
docker tag  localbuild:latest registry.in-cloud.io/reg7h9x2k4m8p0q1r5/backend/api:v1.4.2
docker push                   registry.in-cloud.io/reg7h9x2k4m8p0q1r5/backend/api:v1.4.2
#   Средний сегмент — immutable id реестра. Смена name реестра его НЕ меняет.
```

> [!important] Здесь стоял шаг «poll `GetEffectiveAccess` пока грант не приземлился» — его снято
> **Такого RPC в дереве нет** (`grep -rl 'EffectiveAccess' --include=*.proto --include=*.go .` →
> **0 файлов**), и рецепт не вправе ссылаться на несуществующий шаг: обязательный шаг готовности,
> которого нельзя выполнить, делает весь рецепт неисполнимым, а «его же кто-то напишет» — не
> состояние продукта. **Выбрано: шаг снят из рецепта**, а сама идея вынесена в §«Не построено» как
> предложение без владельца. Что стоит на этом месте сегодня — ниже, в §«Read-your-writes»:
> собственный pull толкавшего разведён мостом на стороне сервиса, а не ожиданием на стороне
> клиента.

---

## RPC surface

`RegistryService` — **15** public RPC (:9090 → REST `/registry/v1/…`); `InternalRegistryService` —
**2** RPC (cluster-internal :9091, gRPC-only, REST-края нет). Чтение — sync; мутации → `Operation`
(op-префикс домена `rop`, поллинг единого края `GET /operations/{id}`, маршрутизация по префиксу
id). Watch не существует.

**FGA-объекты — консистентны с именами ресурсов, Rosetta не нужна:**

| Ресурс | FGA object type | scope-handle |
|---|---|---|
| `Registry` | `registry_registry` | `registry_registry:<registryId>` — по immutable id, никогда по `name` |
| `Repository` | `registry_repository` | `registry_repository:<registryId>/<name>` |

### `RegistryService` — public :9090 / REST `/registry/v1/…`

| RPC | Тип | REST | authz на крае |
|---|---|---|---|
| `Get` | sync | `GET /registries/{registryId}` | `v_get@registry_registry`, `scope_extractor` |
| `List` | sync | `GET /registries` | `<exempt>` — scope-filtered: страница фильтруется в handler'е |
| `Create` | async→Op | `POST /registries` | `v_create` на родителе-проекте (объекта реестра ещё нет) |
| `Update` | async→Op | `PATCH /registries/{registryId}` | `v_update`, `scope_extractor`, hide-existence |
| `Delete` | async→Op | `DELETE /registries/{registryId}` | `v_delete`, `scope_extractor`, hide-existence |
| `ListOperations` | sync | `GET /registries/{registryId}/operations` | `v_list@registry_registry`, `scope_extractor`; фильтр по `resourceId = registryId` |
| `GetRepository` | sync | `GET …/repositories/{repository=**}` | `<exempt>` → handler |
| `ListRepositories` | sync | `GET …/repositories` | `<exempt>` → handler (call-gate + row-filter) |
| `CreateRepository` | async→Op | `POST …/repositories` | `<exempt>` → handler |
| `UpdateRepository` | async→Op | `PATCH …/repositories/{repository=**}` | `<exempt>` → handler |
| `DeleteRepository` | async→Op | `DELETE …/repositories/{repository=**}` | `<exempt>` → handler |
| `RenameRepository` | async→Op | `POST …/repositories/{repository=**}:rename` | `<exempt>` → handler |
| `ListTags` | sync | `GET …/repositories/{repository}/tags` | `<exempt>` → handler |
| `DeleteTag` | async→Op | `DELETE …/repositories/{repository}/tags/{tag}` | `<exempt>` → handler |
| `ListReferrers` | sync | `GET …/repositories/{repository=**}/referrers` | `<exempt>` → handler; `subjectDigest` и `artifactType` — параметры запроса |

> **Почему у десяти RPC край объявлен `<exempt>` — и почему это НЕ дыра.** Per-repo решение
> принимается на **составном** объекте `registry_repository:<registryId>/<repo>`, а экстрактор
> края умеет взять ровно одно поле верхнего уровня — составить из двух он не может. Поэтому
> per-repo `Check` и существование-скрытие выполняет **handler**, и причина записана в самом
> контракте рядом с записями. Это тот случай, когда «поставить любую запись, лишь бы была»
> означало бы проверку, отвечающую всем: отношение уровня кластера выполняется подстановочным
> tuple'ом (`security.md` §«Отношение, выполнимое подстановочным знаком»). Отказ на репозитории
> **или** невидимый реестр → единообразный `NOT_FOUND` — не `PERMISSION_DENIED`, иначе получился
> бы оракул существования. Единственное исключение — admin-гейт на видимость: там вызывающий уже
> доказал доступ, и `PERMISSION_DENIED` честен.
>
> `List` реестров объявлен `<exempt>` по другой причине и по другому правилу: он
> **scope-filtered** — страница читается курсором из своей БД и проверяется пачкой прав на
> идентификаторы **этой** страницы. authN при этом остаётся обязательным.

> **Порядок объявления repository-scoped RPC значим и не косметичен.** REST-край пробует
> зарегистрированные позже маршруты раньше, а `{repository=**}` матчит и пустой хвост, — поэтому
> catch-all объявлен **перед** под-ресурсами, а точный `…/repositories` — **после** catch-all'а.
> Пересортировка по алфавиту/CRUD ломает роутинг молча. Deep-wildcard `{repository=**}` несут
> `GetRepository`/`UpdateRepository`/`DeleteRepository`/`RenameRepository`/`ListReferrers`; у
> `ListTags`/`DeleteTag` переменная **одно-сегментная**.

### `InternalRegistryService` — cluster-internal :9091 (mTLS + authz)

| RPC | Тип | Данные |
|---|---|---|
| `TriggerGarbageCollection` | async→Op | освобождение недостижимых/нетегированных блобов → `GarbageCollectionResult{registryId, blobsRemoved, bytesReclaimed}`; `admin@registry_registry` |
| `GetRegistryStats` | sync | `RegistryStats{registryId, repositoryCount, tagCount, totalSizeBytes, blobCount, lastGcAt}` — инфра-агрегаты; `system_viewer@cluster` |

*Internal-листенер **не освобождён** от authz-Check (defense-in-depth, `security.md`). REST-края
у него нет — на external :9090 эти методы не появляются ни при каких условиях.*

---

## Docker access-control (data-plane, OCI Distribution)

Не RPC-сервис — тонкий auth-proxy перед движком. Отдельная поверхность на своём хосте
(`endpoint`), публичный TLS. Основной путь — прозрачный OCI Bearer-challenge: одна команда
`docker login`, дальше работает стандартный инструментарий (docker / kaniko / buildx /
credential-helpers следуют realm автоматически).

**Разбор пути.** Data-plane читает `/v2/<registryId>/<repo>/…` и требует, чтобы **первый сегмент
был валидным id реестра** — иначе маршрут не резолвится и ответ единообразен с промахом. Сегменты
декодируются и проверяются на выход за пределы пути. Это прямое следствие core rule #15: адресует
id, а не имя.

**Поток авторизации на каждый запрос:**

```
проверка Bearer (JWKS через iam :9097, fail-closed) ─▶ разбор repo/verb ─▶
  InternalIAMService.Check(subject, verb, registry_repository:<registryId>/<repo>)
    pull                          → v_get / v_list @ registry_repository
    push в СУЩЕСТВУЮЩИЙ репозиторий → v_update    @ registry_repository
    push НОВОГО имени              → v_create     @ registry_registry  (создание, не изменение)
  ─▶ allow: reverse-proxy в движок (движок скрыт) · deny: см. семантику отказа
```

**Семантика отказа (единая, анти-оракул):**

| Ситуация | Ответ |
|---|---|
| нет токена | `401` + `WWW-Authenticate: Bearer realm=…, service=…` |
| отказ на чтении **или** отсутствие | `404 NAME_UNKNOWN` — **байт-в-байт одинаково** |
| отказ на записи | `403 DENIED` — единообразно, существует цель или нет |
| зависимость недоступна | `503` — fail-closed, никогда «разрешить» |
| `DELETE` на data-plane | `405 METHOD_NOT_ALLOWED` — **до** движка и независимо от прав |

**`DELETE` на data-plane отвергается намеренно** — это осознанное расхождение с OCI-спекой,
названное явно: единственный путь удаления — control-plane `DeleteTag`, где удаление проходит
`Operation`, права и аудит.

**Анонимный публичный pull.** Обмен токена без учётных данных выдаёт анонимный Bearer, который
резолвится в `user:*`. `Repository.visibility = PUBLIC` ⟺ существует tuple
`user:* v_get registry_repository:<registryId>/<repo>`. PUBLIC → 200; PRIVATE или отсутствует →
тот же единообразный 404 (публичность **не** является оракулом существования). Анонимный push
невозможен by construction: подстановочный субъект не несёт ни одного пишущего отношения, и это
зафиксировано в модели, а не в коде. Анонимный доступ **выключен by default**: пока
соответствующий субъект не сконфигурирован, ни один токен в `user:*` не резолвится.

**Read-your-writes для машинного клиента.** Owner-tuple и per-repo объект материализуются
**eventually-consistent** (`Operation.done` = ресурс durable, и только это — ban #9). Стоковый
docker `NAME_UNKNOWN` не ретраит и предупреждения не показывает, поэтому «отказ по праву»,
«нет такого» и «лаг материализации» для него неразличимы. Что с этим сделано:

- **Мост для собственного pull толкавшего.** Успешный push нового репозитория фиксирует факт
  «этот субъект запушил этот репозиторий», и путь чтения консультируется с этой записью, пока
  штатное отношение не материализовалось. Запись **ключуется по субъекту** — чужой субъект её не
  имеет, поэтому единообразный 404 для всех остальных сохраняется, и межтенантного раскрытия нет
  by construction. Мост схлопывается сам: как только настоящая проверка прав впервые ответила
  «да», запись снимается, и последующий отзыв прав действует немедленно. Плюс срок годности как
  второй ограничитель.
- **Ограниченный повтор на клиенте** — для первого доступа к **своему** свежему ресурсу, и
  никогда для негативных, чужих и заведомо отсутствующих: повтор там маскирует настоящий отказ.
- **Байт-идентичность 404 не ослабляется ни в одном из этих случаев.**

---

## Права: чем выдаётся доступ

Решение о доступе принимает **модель прав**, а не самодельная проверка в коде
(`security.md` §«Авторизация живёт в МОДЕЛИ»). Домен вносит в модель два типа объектов и по пять
глаголов на каждом.

**Глаголы и что они открывают:**

| Глагол | На `registry_registry` | На `registry_repository` |
|---|---|---|
| `v_get` | прочитать реестр | pull репозитория (в т.ч. `user:*` — публичный анонимный pull) |
| `v_list` | перечислять | перечислять теги/содержимое |
| `v_create` | создать репозиторий — **в том числе push нового имени** | — |
| `v_update` | изменить реестр | push в существующий репозиторий, изменить наложение |
| `v_delete` | удалить реестр | удалить репозиторий/тег |

Плюс тирные отношения `admin` / `editor` / `viewer` и `owner`: создатель ресурса держит полный
набор глаголов на **своём** объекте (per-object вывод, не иерархический каскад). Репозиторий —
child реестра: `super_admin` наследуется от родителя, собственного указателя на проект у него нет.

**Двухуровневый push — намеренный least-privilege.** «Push в существующий репозиторий» и «push
нового имени» — разные глаголы на разных объектах: первый ограничен одним репозиторием, второй
даёт право заводить новые имена в реестре. Радиус поражения при утечке ключа CI поэтому разный, и
это ровно тот выбор, который выдающий должен делать сознательно.

**Отказ на push нового имени говорящий** — он называет недостающую способность и объект, на
который её надо выдать, чтобы вызывающий чинил выдачу, а не гадал. То же на переводе видимости в
`PUBLIC`: сообщение называет требуемый уровень (`registry admin`), а не отделывается словом
«запрещено». Тексты отказов — часть контракта (см. Правила п.7).

> **Здесь стояли роли `registry.repoCreator` / `registry.puller` / `registry.pusher` /
> `registry.admin` — таких ролей в дереве нет** (`grep -rn 'repoCreator'` → 0). Сегодня доступ
> выдаётся каталожными системными ролями (`admin` / `edit` / `view`, спроецированными на типы
> `registry.registries` и `registry.repositories`) либо собственной ролью с правилом на эти типы.
> Выделенный набор доменных ролей с человеческими именами — разумное предложение, но это
> **предложение**, и оно вынесено в §«Не построено». Называть его здесь готовым значило бы обещать
> способность, за которую никто не отвечает.

---

## Списки-каталоги

Списки сидят рядом с мутацией, чтобы не гадать идентификаторы вслепую. Что они отдают сегодня:

- **`List`** (реестры проекта) — страница `Registry` + `nextPageToken`; фильтрация — по правам на
  идентификаторы **этой** страницы.
- **`ListRepositories`** — страница `Repository` (наложение LEFT JOIN проекция) + `nextPageToken`.
- **`ListTags`** — страница `Tag` + `nextPageToken`.
- **`ListReferrers`** — ограниченный полный набор одного `subjectDigest` (см. оговорку в §Referrer).

**Scope-handle строит клиент, и правило деривации — одна строка:**
`registry_registry:<registryId>` и `registry_repository:<registryId>/<name>`. Оба сегмента уже
лежат в ответе списка (`id`, `registryId`, `name`), поэтому отдельного поля-эха контракт не несёт.

> **Здесь стояли `namespaceGrantTemplate` / `repositoryGrantTemplate` и поле `fgaObject°` на
> каждом ресурсе — ни того, ни другого в контракте нет** (`grep -rn 'fga_object\|grant_template'
> proto/kacho/cloud/registry/` → 0). Идея — готовое к вставке тело запроса выдачи прав — остаётся
> осмысленной и записана в §«Не построено» вместе с условием, без которого её нельзя вводить:
> **тело обязано быть проверяемо валидным входом текущей схемы iam**, иначе шаблон разъедется с
> той схемой при первой же её эволюции и будет отдавать 400 с видом инструкции. Пока такой
> проверки нет — правило деривации выше короче и не может протухнуть.

---

## Правила

Нормативный список. Соблюдать как контракт; parity формы с compute / vpc / nlb обязателен.

1. **Flat, без envelope.** Domain-поля на верхнем уровне; никаких `spec`/`status`/`metadata`/
   `resourceVersion`. Output-only помечены `°`.

2. **Чтение sync, мутации async → `Operation`.** `Get*`/`List*` — sync. `Create`/`Update`/
   `Delete`/`RenameRepository`/`DeleteTag` → `Operation` (op-префикс домена `rop`). Watch нет.
   Идентификатор/ключ мутируемого ресурса — в `Operation.metadata` **сразу**, до `done`. Клиент
   поллит единый край `GET /operations/{id}` **с реальной паузой между поллами** и **проверяет
   `result.error` прежде, чем брать идентификатор из `metadata`**: он аллоцируется до async-фейла,
   и на ошибке в `metadata` лежит идентификатор несозданного ресурса.

3. **`Operation.done` = ресурс durable, а НЕ видимость downstream-эффекта.** `done=true` ⟺ строка
   закоммичена. Owner-tuple, `user:* v_get`, регистрация репозитория материализуются eventually
   (транзакционная очередь + дренаж + реконсайлер). Гейт `done` на видимость **запрещён** (ban #9 —
   он рождает фантомный ресурс). «Создал → сразу пуллю своё» закрывается ограниченным повтором на
   клиенте и мостом собственного push'а на сервисе, **не** серверным барьером; байт-идентичность
   404 на data-plane при этом не ослабляется.

4. **Адресация — только по immutable `id` (core rule #15).** `id` реестра — единственная внешняя
   координата: он в pull-пути (`$domain/$registryId/$repo:$tag`), в `endpoint°`, в scope-handle,
   в cross-service ссылке. Операции смены `id` **не существует**. `name` — косметический
   project-scoped label (`UNIQUE(project,name)` среди живых), меняется свободно и **никогда** не
   попадает в URL. Деривация глобального человекочитаемого слага в URL вместо id **запрещена**:
   имена меняются и глобально коллизят — слаг сделал бы pull-путь ломким при переименовании и
   конфликтным между тенантами.

5. **Reference-law по классу ссылки.**
   - within-service (та же БД) → **flat `<x>Id` + настоящий FK**: `Repository.registryId`,
     регистрация репозитория (`→ registries(id) ON DELETE CASCADE` — same-DB cascade, это **не**
     cross-service каскад, ban #4 не задет).
   - scope/placement-координата → **flat id + peer-validate у владельца, fail-closed**:
     `projectId` (iam `ProjectService.Get`), `regionId` (geo `RegionService.Get`). Промах →
     `FAILED_PRECONDITION`, владелец недоступен → `UNAVAILABLE`.
   - зависимость на чужой owned-ресурс → **generic `reference.Referrer{type,id,name°}`**
     (graceful-dangling); мишень выдачи прав → **`iam.v1.ResourceRef{type,id}`**; OCI-граф → **`Referrer`
     этого домена**. Три семантики — три типа, а не перегрузка одного (`api-conventions.md`).

6. **Within-service инварианты — на DB-уровне (ban #10).** Партиальный `UNIQUE(project_id, name)
   WHERE status <> 'DELETING'` для реестра (имя, освобождённое переходом в `DELETING`, немедленно
   доступно снова); `PRIMARY KEY (registry_id, name)` для наложения репозитория; `CHECK` на домен
   видимости с дефолтом `PRIVATE` (fail-safe); `CHECK (placement_type = 'REGIONAL' AND region_id
   <> '')`; `CHECK` на домен `lifecycle`; ACTIVE-guard `SELECT … FOR UPDATE` в мутационной
   транзакции. Software check-then-act запрещён. Дубль ключа → 23505 → `ALREADY_EXISTS`;
   конкурентный create → ровно один побеждает.

7. **Единый тон ошибок (часть контракта).** `"<Resource> <id> not found"`;
   `"<field> is immutable after Registry.Create"`; `"repository is not empty"`; отказ на видимость
   называет требуемую способность. Коды: `INVALID_ARGUMENT`, `NOT_FOUND`, `FAILED_PRECONDITION`,
   `ALREADY_EXISTS`, `PERMISSION_DENIED`, `UNAVAILABLE` (peer/движок недоступны — fail-closed для
   мутаций), `INTERNAL` (**фиксированный opaque-текст, без утечки драйвера/SQL/движка**).
   Malformed id — **первым стейтментом RPC** до обращения к хранилищу → `INVALID_ARGUMENT
   "invalid registry id '<X>'"`; well-formed-но-нет → `NOT_FOUND`. Клиент различает линии по
   `reason`-токену в деталях статуса, не парся прозу.

8. **authN и authZ на каждом запросе обоих листенеров.** mTLS (service→service) / TLS+JWT (край).
   Внутренний листенер **не** освобождён. Там, где составной объект не выразим экстрактором края,
   запись каталога честно объявляет `<exempt>`, а `Check` + существование-скрытие выполняет
   handler — и это записано рядом с записью. Отношение, выполнимое подстановочным tuple'ом, годится
   **только** для глобального справочника; ни один RPC этого домена справочником не является.
   Каталог прав генерируется из контракта, обе встроенные копии байт-идентичны, гейт дрейфа роняет
   сборку.

9. **Two-projection.** Публичная поверхность несёт намерение и результат. Engine-namespace,
   bucket, storage-driver, blob-layout, числовой инфра-идентификатор, очередь сборки мусора —
   **только** `Internal*` :9091. Новое инфра-поле по умолчанию едет в `Internal*`, а не на public.

10. **Placement.** Дискриминатор `placementType` всегда `REGIONAL` («не выбор»): OCI-контент
    региональный by construction, зоны реестр не несёт → из зональной проверки когерентности
    исключён, остаётся региональная. `regionId` обязателен на Create, peer-validate geo
    fail-closed, immutable. Константа `placementType` сохранена **осознанно** — ради parity
    placement-дискриминатора с родственными доменами; это задокументированное исключение из
    LEAN-запрета на always-const поле, а не забытое поле.

11. **Update-дисциплина.** Immutable-поле в маске отвергается **до** проверки известности маски —
    иначе вместо каноничного тона вызывающий получит generic «unknown field». Пустая маска →
    full-PATCH изменяемых полей (immutable из тела молча игнорируются) и **не является обходом
    admin-гейта**. Output-only поле в маске → `INVALID_ARGUMENT`.

12. **Валидация формата — ДО замыкания по правам на списках.** `pageToken`/`pageSize`/формат id
    проверяются раньше, чем список коротко замкнётся на пустом гранте: иначе вызывающий без прав
    получает `200 []` на мусорный курсор вместо `400`. Проверяется **порядок**, а не валидатор:
    проба даёт неопознанного вызывающего вместе с мусорным курсором и требует `INVALID_ARGUMENT`,
    плюс парный положительный контроль.

13. **LEAN — без vestigial-поверхности (ban #11).** Не заводить always-const поля под
    несуществующие фичи и не держать поле «на будущее». Поле публичного запроса обязано иметь
    читателя в прод-коде: принять и молча выбросить — не исход (`api-conventions.md`
    §«Принято-и-проигнорировано»). Единственное задокументированное исключение — вход
    `lifecycle` у `CreateRepository`, который существует **чтобы отвергать явно** (см. §Repository).

14. **Тесты в том же PR (ban #12).** Integration с настоящей БД на каждый DB-инвариант, включая
    конкурентные сценарии; e2e через api-gateway — минимум один положительный и один
    отрицательный на RPC. Regression security/leak-фикса локает **наблюдаемое** — текст и код, а
    не только код. Ни один e2e-кейс не пропускается и не ослабляется (`testing.md`).

---

## Не построено (названо явно, чтобы отсутствие не было молчаливым)

Ни один пункт ниже **не** является частью действующего контракта. Каждый назван вместе с тем,
чего не хватает, чтобы его ввести.

| Что | Состояние | Что требуется прежде |
|---|---|---|
| **REG-2 — редизайн read-only проекций движка** | не начат; зафиксирован в Out-of-scope приёмки REG-1 | rename `Referrer → OciReferrer` (ломающее, домен registry); реформа `Tag`; `GetImage`/`DeleteImage`. **Отдельно решить конфликт имени:** `Image` сегодня — ресурс домена storage (загрузочный образ), и одноимённый ресурс в registry различается только FQN. Читаемость на шве требует решения, а не умолчания |
| **Курсорная пагинация `ListReferrers`** | контракт несёт ограниченный полный набор, `nextPageToken` нет | решение о форме курсора; сегодня усечение серверным потолком — наблюдаемое поведение, а не дефект реализации |
| **`GetEffectiveAccess` («может ли этот субъект pull этого репозитория»)** | **не существует**; был выдан прежней редакцией за обязательный шаг рецепта | владелец и приёмка. Вопрос осмысленный, но у ответа два разных читателя (человек в отладке и робот в CI), и от этого зависит и форма, и тир прав. Пока его нет — рецепт на него ссылаться **не вправе** |
| **Обратный аудит доступа** («кто может pull этот репозиторий», «что видно в этом реестре») | не существует | та же приёмка; поверхность admin-тира с существование-скрытием и построчной фильтрацией |
| **Доменные роли с человеческими именами** (`puller` / `pusher` / «создатель репозиториев» / `admin`) | не существует; доступ выдаётся каталожными системными ролями и глаголами `v_*` | сид ролей в iam + проекция в селекторы правил; без последнего роль невидима discovery и не материализует глаголы |
| **Готовое к вставке тело запроса выдачи прав в ответах списков** | не существует | cross-module проверка «тело валидно как вход текущей схемы iam», иначе шаблон разъедется с ней молча |
| **`validateOnly` (sync dry-run)** | не существует ни в одном RPC домена | решение о наборе эхуемых значений; сегодня pre-flight'а нет, и это видно |
| **Ребро `compute → registry`** (резолв загрузочного источника) | **не существует** — в `services/compute` ноль импортов контракта registry, клиента нет | COMP-2 (сага резолва/материализации). Контракт compute уже несёт дискриминатор `registry.image`, но `resolvedDigest°` и материализованный том — output-only и заполняются той же сагой. **Грамматику первого сегмента идентификатора надо свести явно**: адресация registry требует, чтобы им был immutable `registryId`, а комментарий поля на стороне compute этого не проговаривает. Свести — в module-compute.md и записке ребра, не односторонне здесь; новое ребро фиксируется в `polyrepo.md` |
| **`ScanResult` / `VulnerabilityReport`** | не построено | отдельный домен-владелец сканирования; ляжет тем же паттерном проекции, keyed по digest |
| **Правило неизменяемости тега** (защита релизных тегов) | не построено; перезапись тега сегодня не ограничена | first-class ресурс политики, **не** булев флаг на теге |
| **Миграция генерации id `reg → reg-`** (дефисный канон) | не сделана намеренно; генерация эмитит слитную форму | отдельный инкремент. Router принимает обе формы аддитивно, поэтому миграция ничего не гейтит |
