# Kachō Registry — Target Tenant-Facing API Design

*Один продукт, форма-якорь = compute: flat resource + async `Operation`, sync-каталоги рядом с launch, reference-law, two-projection, единый тон ошибок. Домен registry ощущается тем же API, что iam/vpc/compute/nlb — узнаваемость знакомой ФОРМОЙ (OCI push/pull), не брендом (ban #2: «registry engine», не имя движка). **Терминология выровнена под индустрию:** группирующая единица образов = **Namespace** (ресурс, prefix `ns`); слово **registry** зарезервировано за serving-host'ом (`endpoint = registry.in-cloud.io`). FGA-объекты (`registry_registry`/`registry_repository`) и модуль `kacho-registry` сохранены как есть (deployed, stability) — переименовано только tenant-facing понятие; leak типа на iam-шве гасится Rosetta-у-каждого-сниппета + inline-аннотацией в echo (см. Правила п.16, cross-module governance в `data-integrity.md`). **`Referrer` в этом домене = ТОЛЬКО OCI-1.1 граф артефактов** (индустриальный immovable-термин); generic reference-law wrapper переименован в **`ResourceRef`** product-wide (НЕ-однокоренной с Referrer — снимает mislabel-риск на шве `Tag.pushedBy`=ResourceRef ⟷ соседний `Referrer`=OCI-граф). **Rename `ResourceRef` — pending cross-module governance** (Правила п.4): приземляется в `data-integrity.md` + compute-vault ОДНИМ change-set ДО объявления registry conformant; до landing — термин помечен pending, не settled.*

## Ментальная модель

Пять опор. У каждой — ОДИН источник истины; всё остальное это проекция.

1. **`Namespace` — группирующий namespace-ресурс, полноценный DB-policy (SoT = `kacho_registry.registries`).** Единственный registry-ресурс со своей генерируемой строкой, prefix `ns`, project-scoped, region-pinned, async CRUD→`Operation`. Всё внутри адресуется относительно него. **Идентичность разведена на два ортогональных поля (spine-восстановление):** `name` — project-scoped human-имя (`UNIQUE(project,name)` как у всех модулей, immutable через Update); `globalSlug°` — derived-once первый сегмент глобального pull-пути (`endpoint/{globalSlug}/{repo}`), по умолчанию `<accountSlug>-<name>` (глобально-уникален by construction — account-slug уникален → не гонишься с невидимыми тенантами), bare-global — только явный opt-in. Резолв на data-plane hot-path: `globalSlug → namespaceId → project` (детерминированный, без project-сегмента в пути). `registry` — это `endpoint`-host, НЕ namespace. **Grant-scope строится по `namespaceId` (`ns-…`), НИКОГДА по `name`/`globalSlug`** (name-based scope синтаксически валиден, но резолвится в неверный fgaObject → тихо-неэффективный грант → робот 404; format-валидация перенесена на iam-СТОРОНУ шва — fail-closed на bind, не тихий 404 на pull, Правила п.7).

2. **`Repository` — overlay ⟂ projection над натуральным ключом `(namespaceId, name)` (SoT = DB overlay-строка `repository_configs` ДЛЯ intent; SoT = registry engine ДЛЯ result).** Два ортогональных слоя над ОДНИМ ключом: durable overlay (`description`/`labels`/`visibility`/`createdAt`) переживает пустоту; read-only projection (`tagCount`/`sizeBytes`/…) существует пока ≥1 тег. Публичный `Repository` = LEFT JOIN. **НЕ** генерируемый prefix — сохранена проекционная модель (имя несёт `/`: `backend/api`). `lifecycle`-enum (не bool) авторитетно сигналит исчезаемость; **явный `CreateRepository` = DURABLE по умолчанию** (explicit intent-create = намерение сохранить каркас), EPHEMERAL — ТОЛЬКО за register-on-first-push путём (Правила п.13).

3. **`Tag` / `Image` / `Referrer` — read-only projections движка (SoT = registry engine).** Tenant их не «создаёт» через CP — материализуются на `docker push`. `Tag` = mutable pointer (`tag → digest°`), `Image` = immutable content-addressed manifest (`digest⊘` = pin), `Referrer` = OCI 1.1 граф артефактов (подпись/SBOM/attestation) по `subjectDigest`. **`Referrer` = ТОЛЬКО OCI-граф** (индустриальный immovable-термин); actor-echo/consumer-ref = generic `ResourceRef`-wrapper, не «Referrer». **Digest = content-address (immutable pin), не отдельный ресурс.**

4. **Docker access-control = identity(iam) ⊕ authz(FGA-Check) ⊕ thin data-plane (SoT identity = iam/Hydra).** SA-key → прозрачный OCI Bearer-challenge (`WWW-Authenticate: Bearer realm=…/iam/token`) → `docker login` → per-request `InternalIAMService.Check(subject, verb, registry_repository:<ns>/<repo>)` → reverse-proxy в engine. Движок НИКОГДА не на wire. Anon-pull = FGA `user:*`. **Долгоживущий credential = iam SA-key**; short-TTL Bearer прозрачно ре-минтится credential-helper'ом (registry-native credential-ресурса НЕТ — минтинг только iam, `registry→iam` ацикличен). Полная цепочка identity→credential (кто впрыскивает Bearer в бутящийся Instance) — в Правилах п.6.

5. **Two-projection изоляция — нерушимый инвариант (SoT инфра = Internal* :9091).** Публичная поверхность = namespace/repo/tag/digest intent + counts/size/timestamps result. Engine-namespace, object-store bucket, storage-driver, blob-layout, numeric-infra-id, GC-очередь, scanner-backend — **только** `Internal*`. Каждый deny — existence-hiding (`NOT_FOUND`, байт-в-байт как реальный miss). Скомпрометированный public API не раскрывает физику движка.

---

## Namespace

> **Namespace** = группа образов (tenant-ресурс). **`registry`** = serving-host (`endpoint`), не эта сущность. Namespace целиком не пуллится — pull всегда адресует `Repository` внутри него. ⚠ **`Namespace` ≠ Kubernetes Namespace** — это registry-scope образов, не k8s-объект.

Flat, prefix `ns`, project-scoped, **REGIONAL** (region-pinned; anycast — зоны не несёт). Async CRUD→`Operation`.

```jsonc
{
  "id": "ns-c9k2m4x7n1p8q3r5t",        // ⊘ 3-char prefix 'ns' + base32; immutable after Create.
                                       //   (prefix 'ns'=Namespace; 'reg-' retired — re-вводил концепт 'registry', от которого rename ушёл)
  "projectId": "proj-7h3n9k2m5p8q1",   // ⊘ scope-координата → flat slug + peer-validate iam (hard-fail)
  "regionId": "eu-north-1",            // ⊘ REGIONAL — регион ПИНИТ storage-locality блобов + origin для future
                                       //   pull-through & cross-region replication; peer-validate geo (hard-fail).
                                       //   OPTIONAL на Create: опущен → сервер берёт account/project-default и echo'ит resolved
                                       //   в Operation.metadata/validateOnly.resolved (образ портируем — не заставляем думать в регионах).
  "placementType": "REGIONAL",         // ⊘ always REGIONAL for registry (OCI content region-scoped by construction) — not a choice.
                                       //   Присутствует ради spine placement-discriminator parity (compute несёт ZONAL/REGIONAL) —
                                       //   осознанный carve-out из LEAN-запрета always-const (Правила п.14), НЕ забытое поле.
  "createdAt": "2026-07-19T08:14:22Z", // ° DB-assigned, truncate до секунд

  // ── идентичность: project-scoped name ⟂ global pull-slug (spine-восстановление) ──
  "name": "payments",                  // ⊘ project-scoped human-имя. UNIQUE(project,name) — СПАЙН-конформно (как все модули);
                                       //   коллизия ловится ТОЛЬКО в СВОЁМ проекте (не гонишься с невидимым чужим тенантом).
                                       //   IMMUTABLE через Update (reject до UpdateMask); меняется ТОЛЬКО RenameNamespace :rename
                                       //   (переслугует globalSlug + перепишет ВСЕ pull-ссылки — дорого).
  "globalSlug": "acme-payments",       // ⊘/° первый сегмент ГЛОБАЛЬНОГО pull-пути endpoint/{globalSlug}/{repo}.
                                       //   DEFAULT (input опущен) → сервер деривит детерминированно '<accountSlug>-<name>' и ECHO'ит сюда —
                                       //   account-slug уникален ⇒ globalSlug глобально-уникален BY CONSTRUCTION (мина невидимого тенанта снята).
                                       //   OPT-IN (input задан явно) → bare-global slug: ТОГДА И ТОЛЬКО ТОГДА probe глобальной доступности,
                                       //   коллизия → ALREADY_EXISTS с tenant-prefix-подсказкой (см. тон ошибок / validateOnly).
                                       //   Immutable через Update; резолв name→ns→project на data-plane идёт ПО globalSlug (детерминизм).
  "description": "Payments team image namespace",  // mutable (LIVE)
  "labels": {                          // mutable (LIVE)
    "team": "payments", "tier": "prod",
    "displayName": "Payments Team"     //   UI pretty-name живёт ЗДЕСЬ (нет top-level displayName — parity с compute Instance / Repository)
  },

  "defaultRepositoryVisibility": {     // mutable admin-gated — сид visibility для НОВЫХ Repository без явного visibility.
    "value": "PRIVATE",                //   (единственный namespace-level visibility-рычаг; сам namespace visibility НЕ несёт —
    "displayName": "New repositories default to private"  //    авторитетный гейт видимости живёт на Repository.visibility ⟺ FGA user:*)
    // PUBLIC ⇒ "New repositories are anonymously pullable by default"
  },

  "endpoint": "registry.in-cloud.io",       // ° derived — public OCI serving host (docker login target). ЭТО и есть 'registry'-host.
  "repositoryCount": 12,                     // ° engine-projected result
  "fgaObject": "registry_registry:ns-c9k2m4x7n1p8q3r5t", // ° ГОТОВЫЙ scope-handle — paste в AccessBinding.scope КАК ЕСТЬ.
                                                          //   registry_registry == ЭТОТ Namespace (FGA-тип заморожен deploy/stability; Rosetta ниже).
                                                          //   Строится по id (ns-…), НЕ по name/globalSlug. Никогда не собирай scope из pull-пути.
  "status": {                                // ° enum + gloss
    "value": "ACTIVE",
    "displayName": "Namespace is serving push/pull"
    // ACTIVE | DELETING ("Namespace is being torn down; mutations rejected")
  }

  // Internal-only (:9091, НИКОГДА на public): engineNamespace, bucketPrefix, storageDriver,
  //   numericInfraId, replicaPlacement — см. NamespaceStats / InternalRegistryService.
}
```

**Update-классы:** `description`/`labels` — LIVE-mutable. `defaultRepositoryVisibility` — LIVE-mutable **admin-gated** (не-admin путь к PUBLIC → `PERMISSION_DENIED` с talking-текстом, см. п.14). `name`/`globalSlug` — **immutable** через `Update` (reject **до** `UpdateMask`, тон `"name is immutable after Namespace.Create"`); меняются **только** `RenameNamespace :rename`→`Operation`. `id`/`projectId`/`regionId`/`placementType`/`createdAt` — immutable. Power-state отсутствует (у namespace нет боевого состояния — не выдумываем STOPPED-gate/next-boot-deferred).

---

## Repository

Overlay ⟂ projection над `(namespaceId, name)`. **Нет generated-id** — натуральный ключ (spine-исключение: OCI-имена несут `/`). Async lifecycle-мутации; read sync.

```jsonc
{
  "namespaceId": "ns-c9k2m4x7n1p8q3r5t",  // ⊘ within-service → flat id + DB FK (ON DELETE CASCADE)
  "name": "backend/api",                  // repo-имя, несёт '/'; PK(namespaceId,name); rename-only через :rename verb
  "pullReference": "registry.in-cloud.io/acme-payments/backend/api", // ° derived (host/{globalSlug}/{repo}), ready-to-use docker ref
  "fgaObject": "registry_repository:ns-c9k2m4x7n1p8q3r5t/backend/api", // ° ГОТОВЫЙ scope-handle — paste в AccessBinding.scope.
                                                                       //   registry_repository == ЭТОТ Repository (FGA-тип заморожен; Rosetta ниже).
                                                                       //   Строится по namespaceId (ns-…)+name, НЕ по globalSlug из pull-пути.

  // ── overlay (DB-owned intent, durable — переживает пустой repo) ──
  "createdAt": "2026-07-19T09:02:41Z",    // ° момент создания overlay (DB RETURNING); пусто для ephemeral-repo
  "description": "Core API service images",  // mutable (LIVE)
  "labels": { "app": "api", "lang": "go" },  // mutable (LIVE)
  "visibility": {                         // mutable admin-gated (any-path-to-PUBLIC ⇒ registry admin) — АВТОРИТЕТНЫЙ гейт видимости
    "value": "PRIVATE",
    "displayName": "Private — pull requires a grant"
    // PUBLIC ⇒ "Public — anonymous pull allowed" (⟺ FGA user:* v_get, eventually-consistent)
  },
  "lifecycle": {                          // ° output-only — ОДИН авторитетный сигнал исчезаемости (заменил durable-bool)
    "value": "DURABLE",
    "displayName": "Kept even when it has no tags"
    // EPHEMERAL ⇒ "Auto-removed when it has no tags" (unregister-on-last-tag; ТОЛЬКО register-on-first-push путь).
    // Явный CreateRepository → DURABLE by default. Установка overlay-поля на EPHEMERAL push-repo AUTO-PROMOTE'ит → DURABLE (Правила п.13).
  },

  // ── projection (read-only, SoT = engine; result) ──
  "tagCount": 7,                          // ° DURABLE-repo с tagCount:0 всё равно виден
  "sizeBytes": 184623104,                 // ° агрегат по repo
  "artifactTypes": [                      // ° facet-набор что лежит в repo
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.cncf.helm.config.v1+json"
  ],
  "updatedAt": "2026-07-19T11:47:03Z",    // ° последний push (engine)
  "lastPulledAt": "2026-07-19T12:20:10Z", // °
  "downloadCount": 4213                   // °

  // Internal-only (:9091): engineRepoPath, blobLayout, placement — НЕ на public.
}
```

**Два класса `lifecycle` (наблюдаемо неразличимы для authz — anti config-oracle):**
- **`EPHEMERAL`** — ТОЛЬКО register-on-first-push (docker push несуществующего repo-имени): projection без явного overlay, `visibility=PRIVATE` (либо namespace-default), исчезает при опустошении (unregister-on-last-tag). Полный back-compat push-пути. На первый push и на пустой ephemeral-repo эмитится warning `EPHEMERAL_AUTOREMOVE` (validateOnly/response), чтобы «push-before-configure» не был молчаливым сюрпризом.
- **`DURABLE`** — есть overlay: **явный `CreateRepository` (даже без overlay-полей) → DURABLE by default** (explicit intent-create = намерение сохранить каркас; skeleton не испаряется на инстинкт «organize teams»); либо Update-auto-promote EPHEMERAL push-repo; либо Rename-auto-promote. Survives-empty, несёт config, unregister-on-last-tag НЕ срабатывает. Опциональный явный вход `lifecycle: DURABLE|EPHEMERAL` в `CreateRepository` перекрывает дефолт (предсказуемый эксплицитный рычаг вместо вывода исчезаемости из «задан ли overlay-field»).

**Update-классы:** `description`/`labels` — LIVE-mutable. `visibility` — LIVE-mutable admin-gated. `namespaceId`/`createdAt` — immutable (reject до UpdateMask). `name` — immutable через `Update`, меняется **только** `:rename` verb (auto-promote ephemeral→durable). `lifecycle`/`tagCount`/`sizeBytes`/`fgaObject`/… — output-only (в `UpdateMask` → unknown-field `InvalidArgument`).

---

## Tag

Mutable pointer внутри repo (SoT = engine). Read-only projection — CP «создание» отсутствует, материализуется `docker push`; CP умеет только `DeleteTag` (async) + read.

```jsonc
{
  "namespaceId": "ns-c9k2m4x7n1p8q3r5t",  // ⊘ within-service → flat + FK
  "repository": "backend/api",            // ⊘ within-service → flat (составной ключ engine)
  "tag": "v1.4.2",                        // human pointer; re-push перемещает на новый digest
  "digest": "sha256:3f8a1c…d7e2",         // ° на что указывает СЕЙЧАС (mutable pointer → immutable content)

  "architectures": ["amd64", "arm64"],    // ° ЕДИНСТВЕННЫЙ denorm в каноническом Tag-ресурсе — реальная ценность для выбора
                                          //   платформы в ListTags без второго fetch. Форма ЕДИНА с Image.architectures (не расходится).
  // mediaType/sizeBytes НЕ дублируются в каноническом Tag: Tag.digest ГАРАНТИРОВАННО есть Image (1:1) →
  //   деривуемы фетчем Image(digest). Denorm mediaType/sizeBytes живёт ТОЛЬКО в ListTags-item (convenience), не здесь —
  //   снимает инвариант-на-неразъезжаемость с полностью-деривуемых 1:1 полей (LEAN, Правила п.14).
  "pushedBy": {                           // ° reference-law actor-echo — generic ResourceRef-wrapper (polymorphic, graceful-dangling); НЕ OCI-Referrer
    "type": "serviceAccount",
    "id": "sa-4k9m2n7p3q1r5t8w6",
    "name": "ci-pusher"                   // ° denormalized; SoT = iam.ServiceAccount (dangling-safe)
  },
  "createdAt": "2026-07-19T11:47:03Z",    // °
  "lastPulledAt": "2026-07-19T12:20:10Z", // °
  "downloadCount": 512                    // °

  // re-push перемещает pointer (digest) АТОМАРНО; architectures-denorm обновляется тем же движением (единственная denorm-точка).
  // Убрано: immutable/signed — были always-false спекулятивной поверхностью (LEAN, ban #11).
  //   'immutable' вернётся с TagProtectionRule; 'signed' деривуем on-demand из ListReferrers(subjectDigest) фильтром
  //   signature-artifactTypes — как хранимое поле не нужен.
}
```

---

## Image

Immutable content-addressed manifest (SoT = engine). **Digest = адресующий pin**, не отдельный ресурс: `Image` адресуется по `digest⊘`, `Tag` на него указывает. Read-only.

```jsonc
{
  "namespaceId": "ns-c9k2m4x7n1p8q3r5t",  // ⊘ within-service → flat + FK
  "repository": "backend/api",            // ⊘ within-service → flat
  "digest": "sha256:3f8a1c…d7e2",         // ⊘ content-address — IMMUTABLE pin (воспроизводимо)

  "mediaType": {                          // ° kind manifest'а
    "value": "application/vnd.oci.image.manifest.v1+json",
    "displayName": "OCI image manifest (single-arch)"
  },
  "sizeBytes": 26743891,                  // ° config + все layer-блобы — ЕДИНСТВЕННЫЙ tenant-значимый размер
                                          //   (убран manifest-doc sizeBytes ~1KB: near-useless рядом с этим)
  "architectures": ["amd64"],             // ° single-arch → одна; для index — DERIVED-convenience = map(manifests[]→architecture)
                                          //   (та же форма, что Tag.architectures; авторитет — manifests[] ниже, как Image.tags reverse-projection)
  "os": "linux",                          // °
  "layerCount": 6,                        // ° без раскрытия blob-digest'ов на публичной поверхности*
  "configDigest": "sha256:9b2e…af41",     // ° content-addr конфига
  "tags": ["v1.4.2", "latest"],           // ° все теги, указывающие на этот digest (reverse-projection)
  "manifests": [                          // ° для index (multi-arch): per-platform child manifests — OCI image-index vocabulary
    { "digest": "sha256:aa11…", "architecture": "amd64", "os": "linux" },  //   (переименовано из children[] — мигрант знает 'manifests' наизусть)
    { "digest": "sha256:bb22…", "architecture": "arm64", "os": "linux" }   //   architectures[] выше = map(manifests→architecture)
  ],
  "createdAt": "2026-07-19T11:46:58Z",    // ° из manifest config (build-time), truncate до секунд
  "pushedAt": "2026-07-19T11:47:03Z"      // ° когда попал в engine

  // *Internal-only (:9091): физический blob-layout, storage-placement layer-блобов,
  //  numeric-infra-id, dedup-refcount — НЕ на public (leak = карта content-addressable стораджа).
}
```

*Reference-law для boot (consumer-side, compute): compute `bootSource` — generic **`ResourceRef`-wrapper** (тонкий, single-id), а НЕ fat-объект. Registry-host+repo+digest упакованы в единый `id`, tag — в `name°`:*
```jsonc
{ "type": "registry.image",              // ⊘ канонический дискриминатор (dotted domain.resource) — соответствует
                                          //   compute-vault (registry.image / storage.snapshot / storage.volume). Compute — ЯКОРЬ; registry конформит ему.
  "id": "ns-c9k2m4x7n1p8q3r5t/backend/api@sha256:3f8a1c…d7e2", // ⊘ единый ключ <namespaceId>/<repository>@<digest>.
                                          //   namespaceId-based → ПЕРЕЖИВАЕТ RenameNamespace (name/globalSlug-based path бы dangl'нул через ацикличную границу).
                                          //   Резолвится в docker-pull-путь на boot существующим ребром compute→registry (resolve edge).
  "name": "v1.4.2" }                      // ° в wrapper'е это поле называется name° (provenance-echo tag, graceful-dangling)
```
*Registry этого не знает (ацикличность: registry→iam only). Тонкий `ResourceRef{type,id,name°}` вмещает ПОЛНУЮ координату в один `id` — reference-law компонуется на шве без special-case на стороне compute (fat-форма требовала бы, чтобы compute парсил чужую составную схему). **Cross-module conformance-тест против compute-vault** (дискриминатор `registry.image` + id-schema `<namespaceId>/<repo>@<digest>` + `name°`-семантика) обязан быть введён и **прогнан ЗЕЛЁНЫМ ДО** объявления conformance — сейчас это assertion, не проверка (Правила п.5).*

---

## Referrer

OCI 1.1 граф артефактов (подпись / SBOM / attestation / generic), привязанных к `subjectDigest`. **Слово `Referrer` в registry-домене зарезервировано за этим OCI-графом** (индустриальный immovable-термин; generic reference-law wrapper — это `ResourceRef`, не путать: `Tag.pushedBy` — `ResourceRef`, а не Referrer). Read-only projection, existence-hidden. Фундамент под signing/scanning.

```jsonc
{
  "namespaceId": "ns-c9k2m4x7n1p8q3r5t",  // ⊘ within-service → flat + FK
  "repository": "backend/api",            // ⊘ within-service → flat
  "subjectDigest": "sha256:3f8a1c…d7e2",  // digest, К КОТОРОМУ привязан артефакт (Image выше)
  "digest": "sha256:cc33…9f10",           // ° content-addr самого referrer-артефакта
  "artifactType": {                       // ° media-type facet + gloss
    "value": "application/vnd.dev.cosign.simplesigning.v1+json",
    "displayName": "Cosign signature"
    // …spdx+json → "SBOM (SPDX)" · in-toto+json → "Attestation" · generic → "Generic artifact"
  },
  "sizeBytes": 2094,                      // °
  "annotations": {                        // ° OCI annotations артефакта
    "org.opencontainers.image.created": "2026-07-19T11:48:00Z"
  },
  "createdAt": "2026-07-19T11:48:00Z"     // °
}
```

*`ListReferrers` — cursor-пагинация по `(created_at, id)` (`page_size` default 50 / max 1000, `nextPageToken`), НЕ жёсткий cap-1000-без-cursor: тяжело-подписанный subject (много signature/attestation) иначе усекается безмолвно.*

*Roadmap (не построено, аддитивно — не молчаливое отсутствие): **ScanResult / VulnerabilityReport** — read-only projection, keyed by Image `digest` (SoT = scanner engine; scanner-backend уже Internal-only) — Harbor/ECR-мигранты рефлекторно ищут CVE-отчёт; сядет тем же projection-паттерном. **TagProtectionRule** — first-class policy-ресурс (НЕ per-tag bool) для release-tag immutability; overwrite-protection пока НЕ энфорсится. Оба зеркалят существующую модель, вводятся аддитивно.*

---

## Getting started: zero to first push

> Docker-секция ниже предполагает, что этот рецепт выполнен. `docker push` НЕ работает standalone — под ним лежат async `CreateNamespace`, geo-region-lookup, iam SA+key, namespace-scope grant И **пост-grant readiness-verify** (без него первый pull/push после grant transient-404 на стоковом docker). Собрано здесь в один runnable-порядок; identity остаётся в iam (ацикличность — registry native-credential не заводит).

**Которая система что делает:**

| Задача | Хост |
|---|---|
| SA / access-key / AccessBinding (grant) / effective-access verify | iam-API-хост (`iam.v1.*`), verify — registry CP `:effectiveAccess` |
| `docker login` / `/iam/token` / `push` / `pull` | `registry.in-cloud.io` (endpoint) |

```bash
# ── Шаг 1 (опц.): geo — выбрать regionId. МОЖНО пропустить (CreateNamespace возьмёт account-default). ──
GET /geo/v1/regions
# → { "regions": [ { "id": "eu-north-1", "displayName": "EU North" }, { "id": "eu-central-1", … } ] }

# ── Шаг 2: iam — ServiceAccount + access-key (долгоживущий credential робота) ──
POST /iam/v1/serviceAccounts        { "projectId": "proj-7h3n9k2m5p8q1", "name": "ci-pusher" }
# → { "id": "sa-4k9m2n7p3q1r5t8w6", … }
POST /iam/v1/serviceAccounts/sa-4k9m2n7p3q1r5t8w6:createAccessKey
# → { "keyId": "key-9x2…", "secret": "<показывается ОДИН раз>" }   # keyId=docker-username, secret=docker-password

# ── Шаг 3: registry — CreateNamespace (async → poll Operation до done) ──
POST /registry/v1/namespaces
     { "projectId": "proj-7h3n9k2m5p8q1", "name": "payments" }     # regionId опущен → server-default; globalSlug опущен → derive '<accountSlug>-payments'
# → Operation { "id": "epd-…", "metadata": { "namespaceId": "ns-c9k2m4x7n1p8q3r5t" }, "done": false }
GET /registry/v1/operations/epd-…    # поллить с inter-poll задержкой ~500ms до done:true
# → done:true, result.response: regionId="eu-north-1" (resolved echo), globalSlug="acme-payments" (derived echo),
#     fgaObject="registry_registry:ns-c9k2m4x7n1p8q3r5t"

# ── Шаг 4: iam — AccessBinding: дать SA право СОЗДАВАТЬ repo на первом push (namespace-scope) ──
#   Тело НИЖЕ — валидный вход iam.v1.AccessBindingService/Create: subject=ОБЪЕКТ{type,id}, поле roleId, scope=литеральная fgaObject-строка.
POST /iam/v1/accessBindings
     {
       "subject": { "type": "serviceAccount", "id": "sa-4k9m2n7p3q1r5t8w6" },  // ОБЪЕКТ, не colon-строка
       "roleId":  "registry.repoCreator",                     // поле roleId; dotted role NAME (SEEDED system-role, НЕ rol-… id)
       "scope":   "registry_registry:ns-c9k2m4x7n1p8q3r5t"    // ЛИТЕРАЛЬНАЯ fgaObject-строка (paste как есть; по id, НЕ по name/globalSlug)
     }
# → AccessBinding { "id": "acb-…", … }   (owner/grant-tuple материализуется eventually-consistent, ~секунды)

# ── Шаг 5 (ОБЯЗАТЕЛЬНЫЙ readiness-gate): registry CP — poll GetEffectiveAccess пока грант не приземлился ──
#   Заменяет grant-propagation-wait, которого НЕТ в стоковом docker (он не ретраит NAME_UNKNOWN и не показывает warning).
#   authenticated CP-read — замыкает EC-петлю симметрично, НЕ становясь data-plane existence-oracle.
until [ "$(GET /registry/v1/namespaces/ns-c9k2m4x7n1p8q3r5t/repositories/backend/api:effectiveAccess \
             ?subject=serviceAccount:sa-4k9m2n7p3q1r5t8w6 | jq -r .createRepo)" = "true" ]; do sleep 2; done
# → { "pull": true, "push": true, "createRepo": true }   # createRepo:true ⇒ SA может создать НОВОЕ repo-имя на первом push

# ── Шаг 6: docker — login + push (одна login-команда покрывает push+pull) ──
docker login registry.in-cloud.io -u key-9x2… -p <secret>
docker tag  localbuild:latest registry.in-cloud.io/acme-payments/backend/api:v1.4.2   # host/{globalSlug}/{repo}:tag
docker push                   registry.in-cloud.io/acme-payments/backend/api:v1.4.2
#   Шаг 5 сделал первый push детерминированным; если пропустили — transient-404 EC-lag → retry-snippet в Docker-секции.
```

---

## RPC surface

Все RPC обоих листенеров несут per-RPC `InternalIAMService.Check` (fail-closed) + object-scoped `scope_extractor` (target→project). mTLS (svc→svc) / TLS+JWT (edge). Мутации → `Operation` (`epd`-prefix); read — sync. Watch нет — полл `OperationService.Get`.

**Rosetta (tenant-имя → FGA object type; типы НЕ переименованы — deployed/stability; leak гасится inline-аннотацией у КАЖДОГО scope-echo, Правила п.16):**

| Tenant-ресурс | FGA object type | Читается как |
|---|---|---|
| `Namespace` | `registry_registry:<namespaceId>` | «the Namespace you created» |
| `Repository` | `registry_repository:<namespaceId>/<name>` | «this Repository» |

### `RegistryService` — public :9090 / REST `/registry/v1/…`

| RPC | Тип | REST | authz |
|---|---|---|---|
| `GetNamespace` | **sync** | `GET /namespaces/{namespaceId}` | `v_get@registry_registry` (existence-hiding; echo `fgaObject`) |
| `ListNamespaces` | **sync** | `GET /namespaces` | listauthz row-filter · **discovery-каталог** |
| `CreateNamespace` | **async→Op** | `POST /namespaces` | `v_create@registry_registry` (+ admin для PUBLIC default) |
| `UpdateNamespace` | **async→Op** | `PATCH /namespaces/{namespaceId}` | `v_update` (+ admin для `defaultRepositoryVisibility`) |
| `RenameNamespace` | **async→Op** | `POST /namespaces/{namespaceId}:rename` | `v_update@registry_registry` (+ global slug-uniqueness при bare-global) |
| `DeleteNamespace` | **async→Op** | `DELETE /namespaces/{namespaceId}` | `v_delete@registry_registry` |
| `GetRepository` | **sync** | `GET /namespaces/{namespaceId}/repositories/{repository=**}` | `v_get@registry_repository` (existence-hiding; echo `fgaObject`) |
| `ListRepositories` | **sync** | `GET /namespaces/{namespaceId}/repositories` | listauthz row-filter · **discovery-каталог** |
| `CreateRepository` | **async→Op** | `POST /namespaces/{namespaceId}/repositories` | `v_create@registry_registry` |
| `UpdateRepository` | **async→Op** | `PATCH …/repositories/{repository=**}` | `v_update@registry_repository` (+ admin для `visibility`) |
| `RenameRepository` | **async→Op** | `POST …/repositories/{repository=**}:rename` | `v_update@registry_repository` + `v_create@registry_registry` |
| `DeleteRepository` | **async→Op** | `DELETE …/repositories/{repository=**}` | `v_delete@registry_repository` (reject-if-tags в worker'е) |
| `GetEffectiveAccess` | **sync** | `GET …/repositories/{repository=**}:effectiveAccess?subject=<type>:<id>` | `v_get@registry_repository` + grant-read (admin-tier для чужого subject; self-subject — viewer) |
| `ListRepositoryGrants` | **sync** | `GET …/repositories/{repository=**}:grants` | admin-tier `v_get@registry_repository` + grant-read (existence-hidden, listauthz row-filter) · **reverse-audit** |
| `ListEffectiveSubjects` | **sync** | `GET /namespaces/{namespaceId}:effectiveSubjects` | admin-tier `v_get@registry_registry` (existence-hidden, listauthz row-filter) · **reverse-audit** |
| `ListTags` | **sync** | `GET …/repositories/{repository=**}/tags` | `v_list@registry_repository` · **discovery-каталог** |
| `GetImage` | **sync** | `GET …/repositories/{repository=**}/images/{digest}` | `v_get@registry_repository` (existence-hiding) |
| `DeleteTag` | **async→Op** | `DELETE …/repositories/{repository=**}/tags/{tag}` | `v_delete@registry_repository` |
| `DeleteImage` | **async→Op** | `DELETE …/repositories/{repository=**}/images/{digest}` | `v_delete@registry_repository` (delete-by-digest; still-tagged → `FAILED_PRECONDITION`) |
| `ListReferrers` | **sync** | `GET …/repositories/{repository=**}/referrers/{subjectDigest}` | `v_get@registry_repository` (existence-hiding, cursor `(created_at,id)`) |
| `ListOperations` | **sync** | `GET /operations` | per-repo row-filter |

`OperationService.Get` — `GET /registry/v1/operations/{id}` (sync poll). `id`/ключ мутируемого ресурса — в `Operation.metadata` СРАЗУ (до `done`).

**`GetEffectiveAccess { subject, repository }` → `{ pull, push, createRepo }`** — authenticated CP-read, замыкающий EC-петлю: ЛЮБОЙ consumer (CI docker-pull, не только compute boot) подтверждает «грант приземлился» и отличает EC-lag от genuine deny **без** ослабления data-plane byte-identical 404. **Subject-кодировка:** в REST-query это `<type>:<id>` colon-строка (URL не несёт nested-object) — **единственное осознанное исключение** из object-кодировки `{type,id}` (используемой в grant-template/body); маппинг двунаправлен 1:1: `{"type":"serviceAccount","id":"sa-4k9m2n7p3q1r5t8w6"}` ⟷ `serviceAccount:sa-4k9m2n7p3q1r5t8w6`.
```jsonc
// GET /registry/v1/namespaces/ns-c9k2m4x7n1p8q3r5t/repositories/backend/api:effectiveAccess?subject=serviceAccount:sa-4k9m2n7p3q1r5t8w6
{ "pull": true, "push": true, "createRepo": false }   // createRepo=false ⇒ этот SA пушит в существующие, но не создаёт новые repo-имена
```

**`ListRepositoryGrants` / `ListEffectiveSubjects`** — reverse access-audit (team-isolation): «КТО может pull этот repo / что видно в этом namespace» без перебора известных субъектов. Admin-tier, existence-hidden (тот же uniform-404 на нет-доступа/absent), listauthz row-filter. Отвечает на прямой вопрос интегратора «команда B точно не видит repo команды A»:
```jsonc
// GET /registry/v1/namespaces/ns-.../repositories/backend/api:grants
{
  "grants": [
    { "subject": { "type": "serviceAccount", "id": "sa-4k9m2n7p3q1r5t8w6", "name": "ci-pusher" },
      "role": "registry.repoCreator", "pull": true, "push": true, "createRepo": true },
    { "subject": { "type": "group", "id": "grp-2n7p3q…", "name": "backend-team" },
      "role": "registry.puller", "pull": true, "push": false, "createRepo": false }
  ],
  "nextPageToken": "eyJjcmVhdGVkX2F0Ijoi…"
}
```

**`DeleteImage` (delete-by-digest)** — паритет `crane`/`oras`/batch-delete: удаляет manifest по digest. Если digest ещё указуем тегом → `FAILED_PRECONDITION "image is still tagged"` (сначала `DeleteTag`). Untagged-манифесты также реклеймятся `Internal GC`. **Data-plane DELETE запрещён** (`405`, см. deny-семантику) — удаление ТОЛЬКО через CP.

### `InternalRegistryService` — cluster-internal :9091 (mTLS + authz, admin-tier)

| RPC | Тип | Данные |
|---|---|---|
| `GetNamespaceStats` | sync | `NamespaceStats{repositoryCount, tagCount, totalSizeBytes, blobCount, lastGcAt}` — инфра-агрегаты |
| `TriggerGarbageCollection` | async→Op | reclaim unreachable/untagged-blob → `GarbageCollectionResult{blobsRemoved, bytesReclaimed}` |
| `GetRepositoryInternal` | sync | full-projection: `engineRepoPath, bucketPrefix, storageDriver, blobLayout, numericInfraId` |

*Internal-листенер НЕ освобождён от authz-Check (defense-in-depth, `security.md`). Никогда не на external :9090.*

### Docker access-control (data-plane, OCI Distribution, публичный TLS `registry.in-cloud.io:443`)

Не RPC-сервис — thin auth-proxy. **Prerequisite — рецепт «Getting started: zero to first push» выше** (SA+key в iam, `CreateNamespace`, namespace-scope grant, **пост-grant `GetEffectiveAccess`-verify**). Основной путь — прозрачный OCI Bearer-challenge (одна `docker login`-команда).

**Поток (docker/kaniko/buildx/credential-helpers следуют realm автоматически):**
```bash
# login — ОДНА команда; keyId=username, secret=password (из шага 2 рецепта)
docker login registry.in-cloud.io -u <keyId> -p <secret>
#    registry отвечает на /v2 запрос:
#      401 WWW-Authenticate: Bearer realm="https://registry.in-cloud.io/iam/token",
#          service="registry-dataplane", scope="repository:acme-payments/backend/api:pull,push"
#    docker сам идёт по realm с Basic(keyId:secret) → iam brokers Hydra Bearer (bounded TTL, минуты)
#    NB: если у subject есть материализующийся binding, /iam/token может вернуть challenge-hint
#        error="grant_pending" + Retry-After (про СОБСТВЕННЫЙ грант вызывающего — НЕ data-plane existence-oracle)

docker tag  localbuild:latest registry.in-cloud.io/acme-payments/backend/api:v1.4.2
docker push                   registry.in-cloud.io/acme-payments/backend/api:v1.4.2
docker pull                   registry.in-cloud.io/acme-payments/backend/api@sha256:3f8a1c…d7e2
```
`POST /iam/token` проксируется nginx-shim'ом **на endpoint-хосте** (`registry.in-cloud.io/iam/token`), НЕ на iam-API-хосте.

**Поток авторизации per-request:**
```
Bearer verify (JWKS via iam :9097, fail-closed) ─▶ parse repo/verb ─▶
  InternalIAMService.Check(subject, verb, registry_repository:<ns>/<repo>)
    pull  → v_get / v_list @ registry_repository
    push существующего repo → v_update @ registry_repository
    push НОВОГО repo-имени → v_create @ registry_registry  (создание repo, не update)
  ─▶ allow: reverse-proxy в engine (движок скрыт) · deny: existence-hiding
```

**Token-scope грамматика:** challenge несёт per-repository scope `repository:<globalSlug>/<repo>:pull,push`, **выведенный registry из запрошенного repo-path+verb** — tenant scope НЕ передаёт. Токен-scope узкий по построению; **авторитетный least-priv — per-repo FGA-Check** (grant-точность — на уровне AccessBinding, не токена).

**Role → capability (tenant-рычаг = имена ролей; все — SEEDED system-роли, создавать не надо):**

| Роль | Scope | Может |
|---|---|---|
| **`registry.repoCreator`** — **DEFAULT CI-роль** | `registry_registry:<ns>` (namespace-scope) | push-existing И **push-new** — это роль, которую требует `docker push` НОВОГО repo (индустриальный рефлекс «robot создаёт repo»). Первый явно-рекомендованный CI-грант. |
| `registry.puller` | `registry_repository:<ns>/<repo>` | `pull` (v_get/v_list) |
| `registry.pusher` *(narrow least-priv для CD)* | `registry_repository:<ns>/<repo>` | push ТОЛЬКО в **pre-created** repo (v_update@registry_repository) — не создаёт новые repo-имена |
| `registry.admin` | `registry_registry:<ns>` | всё выше + admin (visibility→PUBLIC, grant-management, reverse-audit) |

*Двухуровневый push (существующее vs create-on-push) — легитимный least-priv (blast-radius), но recognizable-путь сделан ДЕФОЛТНЫМ: `registry.repoCreator` — первая рекомендация. `registry.pusher` — узкий least-priv для CD, пушащего только в pre-created repos.*

**Говорящий 403 на push-new без create-права** (не bare `DENIED`) — с точным namespace-scope fgaObject для copy-paste-фикса:
```
403 DENIED: creating repository 'backend/api' requires create permission on the namespace.
            this is expected for the first push of a new repo name.
            grant role registry.repoCreator (default CI role, or registry.admin) scope registry_registry:ns-c9k2m4x7n1p8q3r5t
```

**Говорящий PERMISSION_DENIED на visibility→PUBLIC** (зеркалит push-new — называет нужную capability):
```
PERMISSION_DENIED: setting repository visibility to PUBLIC requires registry admin (role registry.admin) on registry_registry:ns-c9k2m4x7n1p8q3r5t
```

**Deny-семантика (единая, anti-oracle):** read-deny **или** absent → одинаковый `404 NAME_UNKNOWN` (байт-в-байт); push-deny → `403 DENIED` (с capability-текстом при push-new); peer down → `503 UNAVAILABLE` (fail-closed); нет токена → `401` challenge; **DELETE data-plane → `405`** — OCI-spec divergence, названа явно с реальными CP-сегментами:
```
405 UNSUPPORTED: manifest/tag deletion is control-plane only.
    use  DELETE /registry/v1/namespaces/ns-c9k2m4x7n1p8q3r5t/repositories/backend/api/tags/v1.4.2
     or  DELETE /registry/v1/namespaces/ns-c9k2m4x7n1p8q3r5t/repositories/backend/api/images/sha256:3f8a1c…d7e2
```

**Read-your-writes для machine-client (docker CLI в CI):** owner/grant-tuple материализуется **eventually-consistent** (~секунды), deny байт-в-байт = existence-hiding (`404 NAME_UNKNOWN`) — **byte-identity НЕ ослабляется** (SPINE anti-oracle, ban #9). docker/kaniko/buildx **НЕ ретраят** `NAME_UNKNOWN` и не показывают `Warning`-header — genuine-deny, absent-repo и EC-lag неразличимы стоковым тулингом. Три выхода (первые два — first-class в ОСНОВНОМ рецепте, не находка внимательного читателя):
1. **`GetEffectiveAccess`-verify — ОБЯЗАТЕЛЬНЫЙ пост-grant шаг** (рецепт Шаг 5): authenticated CP-read закрывает петлю симметрично, не становясь data-plane oracle. `poll until pull:true`/`createRepo:true` заменяет grant-propagation-wait, которого нет в стоковом docker.
2. **`/iam/token` challenge-hint** `error=grant_pending`+`Retry-After` — про СОБСТВЕННЫЙ грант вызывающего (материализующийся binding), не про чужой ресурс → не existence-oracle.
3. **Retry-snippet (default в Шаге 6)** — budget ~10s, **только первый доступ к своему свежему ресурсу**, НИКОГДА genuine deny/absent:
```bash
for i in 1 2 3 4 5; do
  docker pull registry.in-cloud.io/acme-payments/backend/api:v1.4.2 && break
  echo "grant materializing… retry $i"; sleep 2
done
```

**Anonymous public pull:** iam `/iam/token` без Basic → anon Bearer (`sub == AnonymousClientID`, **read-only** scope, никогда write-verb). Data-plane резолвит `sub → user:*`. `Repository.visibility=PUBLIC` ⟺ FGA `user:* v_get registry_repository:<ns>/<repo>`. PUBLIC → 200; PRIVATE/absent → тот же uniform 404. Anon push невозможен by construction (`user:*` не несёт write-relation → 403).

**Credential-lifecycle (k8s imagePullSecret):** долгоживущий credential = **iam SA-key** (`keyId`/`secret`); short-TTL Bearer прозрачно ре-минтится docker credential-helper'ом на request-path. Полная цепочка (OWNED, не молчаливая — зафиксирована в edge-записке `compute-to-registry`): **iam чеканит SA-key → compute впрыскивает его (node `imagePullSecret` / boot credential-helper) → helper обменивает SA-key на short-TTL Bearer per-pull → registry верифицирует** (Правила п.6). `bootSource` несёт только `serviceAccountId`. Для `imagePullSecret` — `dockerconfigjson` на базе SA-key (`registry.in-cloud.io` → Basic `keyId:secret`). **Registry-native credential/robot-ресурса НЕТ** (identity — концерн iam; `registry→iam` ацикличен).

---

## Discovery-каталоги (рядом с мутацией — не гадать id/binding вслепую)

Sync-List'ы сидят рядом с launch/grant; фрагмент — **байт-в-байт валидное тело** запроса ДРУГОГО модуля (subject=ОБЪЕКТ`{type,id}`, поле `roleId`, `scope`=литеральная строка — слепой paste даёт 200, не 400).

**`ListNamespaces`** — «где создать repo / что грантить на namespace-уровне». Response-level `namespaceGrantTemplate` несёт precomputed `fgaObject` (по id) — для namespace-scope create-грантов (`registry.repoCreator`):
```jsonc
{
  "namespaces": [
    {
      "id": "ns-c9k2m4x7n1p8q3r5t",
      "name": "payments",              // project-scoped human-имя
      "globalSlug": "acme-payments",   // ° первый сегмент pull-пути (derived '<accountSlug>-<name>')
      "regionId": "eu-north-1",
      "repositoryCount": 12,
      "endpoint": "registry.in-cloud.io",
      "fgaObject": "registry_registry:ns-c9k2m4x7n1p8q3r5t" // ° namespace scope-handle (по id, НЕ по name/globalSlug).
                                                            //   registry_registry == ЭТОТ Namespace (Rosetta — FGA-тип заморожен deploy/stability)
    }
  ],
  // response-level — заполни subject.id, отправь как БАЙТ-в-байт тело iam.v1.AccessBindingService/Create.
  //   Деривация: scope='registry_registry:<namespaceId>'; roleId — фиксированный set (см. Правила п.7).
  "namespaceGrantTemplate": {
    "bindVia": "iam.v1.AccessBindingService/Create",
    "subject": { "type": "serviceAccount", "id": "<slot: sa-… | user:… id | grp-…>" }, // ОБЪЕКТ {type,id}, не colon-строка
    "roleId":  "registry.repoCreator",   // DEFAULT CI-роль (push-existing И push-new) · | registry.puller | registry.admin
    "scope":   "registry_registry:ns-c9k2m4x7n1p8q3r5t"  // литеральная fgaObject-строка выше — paste как есть (по id)
  },
  "nextPageToken": "eyJjcmVhdGVkX2F0Ijoi…"
}
```

**`ListRepositories`** — «что я могу пуллить / кому грантить repo-scope». Per-item — canonical repo-handle с precomputed `fgaObject`:
```jsonc
{
  "repositories": [
    {
      "namespaceId": "ns-c9k2m4x7n1p8q3r5t",
      "name": "backend/api",
      "visibility": { "value": "PRIVATE", "displayName": "Private — pull requires a grant" },
      "lifecycle": { "value": "DURABLE", "displayName": "Kept even when it has no tags" },
      "tagCount": 7,
      "pullReference": "registry.in-cloud.io/acme-payments/backend/api", // ° готово к docker pull (host/{globalSlug}/{repo})
      "fgaObject": "registry_repository:ns-c9k2m4x7n1p8q3r5t/backend/api" // ° repo scope-handle (по namespaceId+name, НЕ по globalSlug).
                                                                         //   registry_repository == ЭТОТ Repository (Rosetta — тип заморожен)
    }
  ],
  "repositoryGrantTemplate": {
    "bindVia": "iam.v1.AccessBindingService/Create",
    "subject": { "type": "serviceAccount", "id": "<slot>" }, // ОБЪЕКТ {type,id} — та же кодировка, что namespaceGrantTemplate
    "roleId":  "registry.puller",         // repo-scope роли: registry.puller | registry.pusher (narrow CD, pre-created repos).
                                          //   create-on-push — namespace-scope registry.repoCreator (см. ListNamespaces)
    "scope":   "registry_repository:ns-c9k2m4x7n1p8q3r5t/backend/api"  // литеральная fgaObject-строка выше
  },
  "nextPageToken": "eyJjcmVhdGVkX2F0Ijoi…"
}
```

**`ListTags`** — «какой tag/digest выбрать для bootSource / rollback». Item несёт И готовую docker-СТРОКУ (для человека), И тонкий `ResourceRef`-фрагмент под compute (без ручного парсинга — wire-форма согласована на ребре registry↔compute):
```jsonc
{
  "tags": [
    {
      "tag": "v1.4.2",
      "digest": "sha256:3f8a1c…d7e2",
      "architectures": ["amd64", "arm64"],
      "mediaType": "application/vnd.oci.image.index.v1+json",  // ° convenience-denorm ТОЛЬКО в ListTags-item (не в каноническом Tag; деривуем из Image)
      "sizeBytes": 42317,                                      // ° convenience-denorm ТОЛЬКО в ListTags-item
      "pushedAt": "2026-07-19T11:47:03Z",
      "pinnedReference": "registry.in-cloud.io/acme-payments/backend/api@sha256:3f8a1c…d7e2", // ° immutable pin (docker-строка для человека)
      "bootSource": {                    // ° тонкий ResourceRef-wrapper — ложится в compute Instance.Create БЕЗ split/парсинга
        "type": "registry.image",        //   канонический dotted-дискриминатор (см. Image reference-law)
        "id": "ns-c9k2m4x7n1p8q3r5t/backend/api@sha256:3f8a1c…d7e2", // ⊘ <namespaceId>/<repo>@<digest> (rename-survivable pin)
        "name": "v1.4.2"                 // ° provenance-echo (tag)
      }
    }
  ]
}
```

---

## validateOnly (sync dry-run — pre-flight на живом ресурсе)

`Create/Update/Rename/Delete*Repository`, `Create/Update/Rename Namespace`, `DeleteTag/DeleteImage` принимают `validateOnly: true` → **sync**, БЕЗ мутации, БЕЗ `Operation`, БЕЗ state-gate (можно на `DELETING`-namespace — pre-flight). Возвращает `warnings[]` + echo выведенных значений (включая `fgaObject`, resolved region, derived `globalSlug` — scope-строку НИКОГДА не собирать руками). **`CreateRepository` с `validateOnly` — заодно lightweight-echo `fgaObject` по `(namespaceId,name)` БЕЗ требования существования overlay** → покрывает легитимный порядок «grant ДО первого push» (когда `GetRepository`=404, а scope взять неоткуда):

```jsonc
// CreateNamespace { projectId, name: "payments", validateOnly: true }  (regionId + globalSlug опущены)
{
  "valid": true,
  "warnings": [],
  "resolved": {
    "regionId": "eu-north-1",            // из account/project-default (opt-in regionId; echo resolved)
    "placementType": "REGIONAL",
    "globalSlug": "acme-payments",       // ° DERIVED '<accountSlug>-<name>' — глобально-уникален by construction (не гонишься с невидимым тенантом)
    "fgaObject": "registry_registry:<ns-будет-назначен-на-Create>"  // scope-форма (по id, не по name)
  }
}

// CreateNamespace { projectId, name: "payments", globalSlug: "payments", validateOnly: true }  (OPT-IN bare-global slug)
{
  "valid": false,
  "warnings": [
    { "code": "NAMESPACE_NAME_IS_GLOBAL",
      "message": "explicit globalSlug 'payments' is globally unique across ALL tenants and is already taken; omit globalSlug to auto-derive a tenant-prefixed slug (e.g. acme-payments), or choose a tenant-prefixed one" }
  ],
  "resolved": { "regionId": "eu-north-1", "placementType": "REGIONAL" }
}

// CreateRepository { namespaceId, name: "backend/api", validateOnly: true }  (visibility опущен, overlay пуст)
{
  "valid": true,
  "warnings": [
    { "code": "VISIBILITY_INHERITED",
      "message": "visibility not set — inheriting namespace defaultRepositoryVisibility=PUBLIC (repository will be anonymously pullable)" },
    { "code": "LIFECYCLE_DEFAULT_DURABLE",
      "message": "explicit CreateRepository defaults to DURABLE (skeleton kept even with no tags); pass lifecycle:EPHEMERAL for register-on-first-push semantics" }
  ],
  "resolved": {
    "visibility": "PUBLIC",
    "lifecycle": "DURABLE",              // явный Create → DURABLE by default (не EPHEMERAL)
    "adoptsProjection": false,           // нет pushed-контента под этим именем — не adopt
    "pullReference": "registry.in-cloud.io/acme-payments/backend/api",
    "fgaObject": "registry_repository:ns-c9k2m4x7n1p8q3r5t/backend/api" // ° lightweight-echo — готов для grant ДО первого push
  }
}
```

**Cross-module preflight (compute-side):** `compute Instance.Create { …, bootSource, validateOnly: true }` резолвит пересечение `serviceAccountId × registry.puller × registry_repository` и возвращает в `resolved`/`warnings`, авторизован ли boot-SA на pull целевого `bootSource` — ДО реального launch. Это ровно вопрос интегратора «может ли ЭТА SA pull ЭТОТ образ» (эквивалент `GetEffectiveAccess`, см. Правила п.6).

---

## Правила

Нормативный список. Соблюдать как контракт — parity формы с compute/vpc/nlb обязателен.

1. **Flat, без envelope.** Domain-поля на верхнем уровне; никаких `spec`/`status`/`metadata`/`resourceVersion`. Output-only помечены °; enum несут inline `displayName`/gloss.

2. **Read sync, мутации async→`Operation`.** `Get*`/`List*`/`GetImage`/`GetEffectiveAccess`/`ListRepositoryGrants`/`ListEffectiveSubjects`/`ListReferrers` — sync. `Create/Update/Delete/Rename` + `DeleteTag`/`DeleteImage` → `Operation` (prefix `epd`). Watch нет. `id`/ключ мутируемого ресурса — в `Operation.metadata` СРАЗУ (до `done`). Клиент поллит `GET /registry/v1/operations/{id}` с реальной inter-poll задержкой.

3. **`Operation.done` = DURABLE, не downstream-видимость.** `done=true` ⟺ overlay-строка закоммичена. Owner-tuple / `user:* v_get` / engine-remap материализуются eventually-consistent в ограниченном окне (transactional-outbox + drainer + reconciler). Confirm-gate на видимость запрещён (ban #9, phantom-repo). «Создал→сразу мутирую/пуллю своё» — **bounded client-retry** на кратком 403/404 (включая data-plane docker CLI, `404 NAME_UNKNOWN` на первый pull после grant/push), НЕ серверный барьер. **byte-identical data-plane 404 НЕ ослабляется** (anti-oracle spine). Петля замыкается симметрично authenticated CP-read'ом: **`GetEffectiveAccess` — ОБЯЗАТЕЛЬНЫЙ пост-grant readiness-gate в основном рецепте** (poll until `pull`/`createRepo` = true) + опциональный `/iam/token` challenge-hint `error=grant_pending`/`Retry-After` (про собственный грант вызывающего) — ни то, ни другое не становится data-plane existence-oracle.

4. **Reference-law + именование wrapper'а.**
   - within-service (та же БД) → **flat `<x>Id` + DB FK**: `Repository.namespaceId`, `Tag/Image/Referrer.namespaceId+repository` (FK `→ registries(id) ON DELETE CASCADE`, ban #4 same-DB).
   - scope/placement-координата → **flat slug + peer-validate (hard-fail)**: `Namespace.projectId` (peer iam `ProjectService.Get`), `Namespace.regionId` (peer geo `RegionService.Get`), `pushedBy.id` (iam SA). Не найдено/не состояние → `InvalidArgument`/`FailedPrecondition`; peer down → `Unavailable` (fail-closed для мутаций).
   - dependency на чужой owned-ресурс → **generic тонкий wrapper `ResourceRef{type, id, name°}`** (single-id, graceful-dangling, polymorphic): `Tag.pushedBy` (actor-echo), consumer-side compute `bootSource`. Составные ключи упаковываются в единый `id` (registry: `<namespaceId>/<repository>@<digest>`) — НЕ раздувать wrapper в fat-объект (иначе consumer special-case'ит чужую схему). `name°` output-only, SoT у владельца, dangling переживается.
   - **Generic wrapper переименован `Referrer→ResourceRef` product-wide** (НЕ-однокоренной с Referrer — снимает mislabel на шве `Tag.pushedBy`=ResourceRef ⟷ соседний `Referrer`=OCI-граф); **`Referrer` зарезервирован ЭКСКЛЮЗИВНО за registry OCI-1.1 artifact-графом** (immovable-индустриальный термин). **Rename — PENDING cross-module governance, не settled:** приземляется в `data-integrity.md` + compute-vault ОДНИМ change-set (compute bootSource-wrapper включён) ДО объявления registry conformant. До landing — термин помечен pending.

5. **Канонический дискриминатор polymorphic-ref — `registry.image` (dotted `domain.resource`).** Соответствует уже-сошедшемуся compute-vault (`registry.image` / `storage.snapshot` / `storage.volume`). **Compute — эталон-якорь; registry конформит ему** (не наоборот — менять сошедшийся compute-anchor разрушительнее и нарушает spine). **Cross-module conformance-тест против compute-vault** (дискриминатор `registry.image` + id-schema `<namespaceId>/<repo>@<digest>` + `name°`-семантика) обязан быть **введён и прогнан ЗЕЛЁНЫМ ДО** заявления conformance — сейчас это assertion, не проверка; форма иначе тихо разъедется с якорем.

6. **Pull-identity сведена на request-path (fail-closed) + credential-chain явна.** На compute `Instance.Create` с `bootSource` синхронно проверять, что `Instance.serviceAccountId` несёт `registry.puller` (`v_get`) на целевой `registry_repository` — **403 на submit**, не поздний opaque boot-failure. **Единая гарантия (не either/or):** resolve `tag→digest` и boot-pull авторизуются под ОДНИМ subject'ом — ИНАЧЕ отдельный puller-precheck на pull-subject **обязателен** (resolve-success ≠ pull-success при разных subject'ах). **Credential-chain (OWNED, не молчаливая, зафиксирована в edge-записке `compute-to-registry`):** iam чеканит SA-key → compute впрыскивает его (node `imagePullSecret` / boot credential-helper) → helper обменивает SA-key на short-TTL Bearer per-pull → registry верифицирует; `bootSource` несёт только `serviceAccountId`. Для PUBLIC-bootSource `serviceAccountId` **опционален** (`user:*`). `validateOnly`/`GetEffectiveAccess` префлайтят `serviceAccountId × registry.puller × repo`.

7. **authz на КАЖДОМ RPC обоих листенеров + grant-scope деривация ПО id, валидируемая на iam-стороне.** Public :9090 и internal :9091 одинаково: per-RPC `Check` + object-scoped `scope_extractor` (target→project, anti-BOLA). Read → viewer-floor; мутации → `v_create`/`v_update`/`v_delete`; путь к PUBLIC → admin-tier; reverse-audit (`ListRepositoryGrants`/`ListEffectiveSubjects`) → admin-tier existence-hidden. **Деривация grant-scope (два уровня, ПО id — НИКОГДА по name/globalSlug):** repo-scope `fgaObject = registry_repository:<namespaceId>/<name>`; namespace-scope `fgaObject = registry_registry:<namespaceId>`. Role-set (все — **SEEDED system-роли**, создавать не надо): `{registry.puller, registry.pusher (repo-scope), registry.repoCreator, registry.admin (namespace-scope)}`. **Format-валидация scope перенесена на iam-СТОРОНУ шва (cross-module governance, `data-integrity.md`):** iam reject'ит scope, чей object-id-сегмент не prefixed-id (`registry_registry:ns-…` / `registry_repository:ns-…/…`) → `InvalidArgument` НА BIND (`"registry scope must reference a namespace by id (ns-…), not by name"`) — **fail-closed на bind вместо тихого dead-grant → 404 на pull** (silent dead-grant — худший класс отказа). `fgaObject` **всегда echo'ится** (`GetNamespace`/`GetRepository`/`validateOnly.resolved` — включая lightweight-echo pre-push repo/discovery). **AccessBinding seam-конвенция (cross-module governance):** iam-side принимает `roleId` как dotted system-role NAME (governance-решение — либо rename поля `roleId→role`, либо приём ОБЕИХ форм dotted-name/`rol-…` id с echo канонической); registry-дока ссылается на это решение, не закрывает односторонне. permission-catalog генерируется из proto, byte-identical iam-seed↔gateway, CI drift-gate. mTLS/TLS+JWT везде. Documented exception: iam JWKS-route :9097 internal-only unauthenticated-by-design.

8. **Within-service инварианты — на DB-уровне (ban #10).** `PK(namespaceId, name)` для Repository (дубликат/rename-collision → 23505 → `ALREADY_EXISTS`); **`UNIQUE(project_id, name)` для Namespace** (СПАЙН-конформно — коллизия ловится в своём проекте); **`UNIQUE(global_slug)` глобально** (default-derived `<accountSlug>-<name>` уникален by construction; bare-global opt-in → probe + collision → `ALREADY_EXISTS` с tenant-prefix-подсказкой на КАЖДОМ Create-пути кодом `NAMESPACE_NAME_IS_GLOBAL`, не только validateOnly.warnings); `visibility CHECK IN('PRIVATE','PUBLIC')` дефолт PRIVATE (fail-safe); ACTIVE-guard `SELECT registries.status FOR UPDATE` в мутационной tx (`DELETING` → `FAILED_PRECONDITION "namespace is being deleted"`); rename = одностейтментная запись под PK/UNIQUE-backstop; visibility-flip = single-statement CAS. Software check-then-act (TOCTOU) запрещён.

9. **Placement-coherence + rationale.** Дискриминатор `placementType`. `Namespace` — **always REGIONAL** (anycast, `regionId` set, `zoneId` пуст — «not a choice»: OCI-контент region-scoped by construction) → из зональной проверки исключён by construction, остаётся региональная. `regionId` пинит storage-locality блобов + origin для future pull-through/replication (peer-validate geo fail-closed); **OPTIONAL на Create** — опущен → server account/project-default, resolved echo в `Operation.metadata`/`validateOnly.resolved`; если genuinely-required-путь → `InvalidArgument` перечисляет валидные region-id (без отдельного geo-вызова на шаге 0). Registry-ресурсы зон не несут.

10. **Единый тон ошибок (часть контракта).** `"<Resource> <id> not found"` (`"Repository backend/api not found"`); `"<field> is immutable after <R>.Create"` (`"name is immutable after Namespace.Create"`, `"namespaceId is immutable after Repository.Create"`); `"repository is not empty"`; `"image is still tagged"`; `"namespace is being deleted"`. Bare-global slug collision → `ALREADY_EXISTS` с tenant-prefix-подсказкой (`NAMESPACE_NAME_IS_GLOBAL`) на каждом Create-пути. Talking-403/PERMISSION_DENIED на push-new (+ «this is expected for first push of a new repo name») и visibility→PUBLIC несут точный namespace-scope `fgaObject` + нужную роль (copy-paste-фикс). Коды: `INVALID_ARGUMENT`, `NOT_FOUND`, `FAILED_PRECONDITION`, `ALREADY_EXISTS`, `UNAVAILABLE` (peer/engine down, fail-closed мутаций), `INTERNAL` (opaque `"internal database error"`, **без leak'а pgx/engine**). Malformed-id → `InvalidArgument "invalid namespace id '<X>'"` / natural-key → `"invalid repository name '<X>'"` ПЕРВЫМ стейтментом RPC до repo-вызова; well-formed-но-нет → `NotFound`.

11. **`validateOnly:true` — sync dry-run.** Полная валидация БЕЗ мутации/Operation и БЕЗ state-gate (pre-flight на живом/`DELETING` ресурсе). Возвращает `{valid, warnings[], resolved{…}}` с echo выведенных значений (`fgaObject` — включая lightweight-echo pre-push repo для grant-до-push, derived `globalSlug`, resolved region, inherited visibility, `LIFECYCLE_DEFAULT_DURABLE`, `EPHEMERAL_AUTOREMOVE`, `NAMESPACE_NAME_IS_GLOBAL`, adopt-projection, resolved pullReference; cross-module — pull-authz boot-SA). Не пишет outbox, не трогает engine.

12. **Update mutability-классы единообразно.** LIVE-mutable: `description`/`labels`/`visibility`(admin-gated)/`defaultRepositoryVisibility`(admin-gated). immutable (reject **до** `UpdateMask` — иначе generic unknown вместо конвенционного тона): `id`/`name`(rename-only)/`globalSlug`(rename-only)/`namespaceId`/`projectId`/`regionId`/`placementType`/`createdAt`. Пустой mask → full PATCH mutable-полей (immutable из тела silently игнорируются). Unknown/output-only (`lifecycle`/`tagCount`/`fgaObject`/…) в mask → `InvalidArgument`. Power-state неприменим (registry не несёт боевого состояния).

13. **One-shot Create + lifecycle-дефолт + auto-promote + discovery рядом.** `CreateRepository` = вставка overlay + adopt существующей projection в ОДНОЙ Operation; **явный Create → `DURABLE` by default** (explicit intent = сохранить каркас; skeleton не испаряется), опциональный вход `lifecycle: DURABLE|EPHEMERAL` перекрывает. `EPHEMERAL` — ТОЛЬКО register-on-first-push путь; установка overlay-поля на такой push-repo (Update/Rename) AUTO-PROMOTE'ит `EPHEMERAL→DURABLE`; первый push и пустой ephemeral-repo эмитят `EPHEMERAL_AUTOREMOVE`. `ListNamespaces`/`ListRepositories`/`ListTags` сидят рядом с grant/launch; item несёт готовый `pullReference`/`pinnedReference` + тонкий `ResourceRef`-bootSource; форма AccessBinding — response-level `namespaceGrantTemplate`/`repositoryGrantTemplate` (**байт-в-байт валидное тело** `iam.AccessBindingService/Create`: `subject`=ОБЪЕКТ`{type,id}`, поле `roleId`=dotted system-role NAME, `scope`=литеральная fgaObject-строка по id; `registry.repoCreator` — первый рекомендованный CI-грант). Cross-module conformance-тест «template-body валиден как вход текущей request-schema iam.AccessBindingService/Create» обязателен (иначе разъедется при эволюции iam).

14. **LEAN — без vestigial-поверхности (ban #11), с явным carve-out.** Не заводить always-const wire-поля под несуществующие фичи (убраны `Tag.immutable`/`Tag.signed` — вернутся с TagProtectionRule/SigningPolicy аддитивно; `signed` деривуем из `ListReferrers`). Один авторитетный сигнал вместо протекающего bool (`Repository.lifecycle`-enum). Один tenant-значимый размер (`Image.sizeBytes`). **Denorm сужен:** канонический `Tag` несёт ТОЛЬКО `architectures[]` (реальная ценность для платформы в ListTags); `mediaType`/`sizeBytes` — деривуемы из 1:1 Image, живут convenience-denorm'ом ТОЛЬКО в `ListTags`-item (не в каноническом ресурсе → нет инварианта-на-неразъезжаемость на полностью-деривуемых полях). `Image.architectures[]` для index = derived-convenience `map(manifests[]→architecture)` (авторитет — `manifests[]`, как `Image.tags` reverse-projection). **Carve-out:** `Namespace.placementType` — always-REGIONAL-константа, сохранена **осознанно** ради spine placement-discriminator parity (compute несёт ZONAL/REGIONAL), gloss «not a choice» — задокументированное исключение, не забытое поле.

15. **JSON camelCase · id = 3-char prefix + base32 (`ns…`) для Namespace (`reg-` retired); Repository/Tag/Image — natural/content-key by design (spine-исключение: OCI-имена несут `/`, overlay⟂projection, digest=content-address) · Namespace-идентичность разведена: project-scoped `name` (`UNIQUE(project,name)`, spine) ⟂ derived `globalSlug°` (глобальный pull-путь) · timestamps truncate до секунд на КАЖДОМ ресурсе и под-записи (`Referrer`/`Image.manifests` тоже) · vendor-agnostic (ban #2: «registry engine»/«OCI artifact», НИКАКИХ имён чужих движков/облаков в полях/типах/значениях) · в прозе host называть `endpoint`/serving-host, не «registry»; `Namespace` ≠ Kubernetes Namespace (баннер).**

16. **Naming-leak на iam-шве гасится в точке использования (cross-module governance, `data-integrity.md`).** FGA object-типы `registry_registry`/`registry_repository` заморожены (deployed/stability — легитимно, НЕ переименовываются), но tenant-ресурс = `Namespace` → scope-строка `registry_registry:ns-…` читается как «другой продукт» на шве. Митигация: (a) Rosetta-таблица держится вплотную к КАЖДОМУ scope-несущему сниппету + inline-аннотация в fgaObject-echo (`// registry_registry == the Namespace you created`) прямо в JSON-комментариях discovery/Get-ответов, не только одной таблицей; (b) going-forward — iam-side scope-alias `registry_namespace:`/`registry_repository:` как принимаемый синоним, чтобы tenant-facing строки совпали с tenant-термином. Решение — cross-module governance, не закрывается односторонне в registry-доке.
