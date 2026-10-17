# Sub-phase REG-PUB-1 (публичный реестр выдачей классу) — Acceptance

> **Статус:** DRAFT
> **Статическая форма:** DRAFT; действующий вердикт выводится из внешнего события и записи ревью,
> привязанной к SHA-256 редакции (`change-graph` §3), а не из этой строки
> **История review:** (только дописывается строкой «дата · круг · вердикт · SHA-256 редакции · путь записи»)
> - 2026-10-17 · круг 1 · CHANGES_REQUESTED · `b15e196748961e988ec91545d1e07e7be30c01f8ca92d0dd76026a8cc12b0236` ·
>   `docs/specs/reviews/sub-phase-REG-PUB-1-public-registry-by-class-grant-acceptance/b15e196748961e988ec91545d1e07e7be30c01f8ca92d0dd76026a8cc12b0236.yaml`
> **Дата:** 2026-10-17 · **редакция:** 5. Редакция 2 — решения диспетчера Д1–Д8 по вопросам
> В1–В8 редакции 1. Редакция 3 — уточнение к Д5: ручку kaname делает `kaname#495`, значения в
> профилях стенда — производитель стадии S6. Редакция 4 закрывает блокирующие B1–B5 и
> неблокирующие замечания круга 1 (раздел «Редакция 4: что закрыто»); добавлены Д9 (решение
> диспетчера по B1), сценарии 18, 29, 45; посев «Дано» прогнан, числа — раздел «Посев «Дано»:
> прогон». Редакция 5 — решение диспетчера по Д9: вариант (б), правка судьи формы в kaname
> (`kaname#872`); S1 ждёт пин kaname с этой правкой. Вердикт круга 1 относится
> к редакции 3 и на эту редакцию не переносится. Открытых вопросов нет
> **Задача:** `PRO-Robotech/kacho#3274` (родитель `#3172`, ветка эпика `3172-identity-own-2`)
> **Механизм (не переоткрывается):** `PRO-Robotech/kaname#856` (влит, слияние `422d1bc6f`),
> `PRO-Robotech/kaname#857` (влит, `20a8bc67d`); приёмка kaname
> `docs/engineering/acceptance/anonymous-and-authenticated-are-subject-classes.md` @`422d1bc6f`,
> редакция 10, SHA-256 `198db838d0a75b7f5b5bdbd5564bacec23a79cc00550a26e8830f3c6be61aac9`,
> стадия S5, SC-60…73, решения Р9 и Р10, посев П6
> **Ревизии замера:** kacho `e9ce4ffbd` (голова `origin/3172-identity-own-2`), kacho `a95248464`
> (`origin/main`); kaname `422d1bc6f` (`origin/main`), kaname `b1b4543c4` (голова PR `kaname#871`)

## Обзор

Реестр становится публичным одной выдачей роли `registry.public.read` (id
`rolb1325b011aa17211d`) классу `system_class:anonymous` на этот реестр. После неё аноним читает
реестр и все его репозитории, включая созданные позже. Отзыв этой выдачи снимает чтение со
всех репозиториев сразу. Механизм принадлежит kaname и уже влит. Эта под-фаза делает его
доступным в kacho: манифест registry объявляет контейнер публичного чтения и роль, пин и образ
kaname поднимаются, реестр показывает видимость (`Registry.visibility`, только на выход,
выводится из выдачи), консоль включает и выключает публичность. Аноним получает pull, перечень
и отказ на запись через плоскость данных, в том числе обычным `docker pull` без учётки.

## Что НЕ входит

1. **Механизм kaname.** Наследование `public_reader`, ворота выдачи классу, сужение по цели,
   переходный приём прежней редакции (Р9, Р10, SC-60…73 приёмки kaname). Здесь эти решения
   только используются.
2. **Чтение реестра анонимом через API-край** (`/registry/v1/...`). Все 15 методов
   `RegistryService` объявляют пол `required_acr_min = "1"`. Пол «0» вместе с полосой
   `scope_filtered` сборка каталога отвергает (Р6 и SC-35 приёмки kaname). Открыть
   control-plane анониму значит сменить контракт полосы. Это отдельная приёмка с названным
   методом (там же, «Что НЕ входит» п. 1). Здесь закрепляется только сегодняшний отказ
   (REG-PUB-1-30).
3. **Значение видимости «только вошедшим».** Выдача классу `authenticated` работает (SC-69
   приёмки kaname), но `Registry.visibility` её не описывает (Р4, Д3).
4. **Снятие перевода `user:*` → `system_class` в манифесте registry** — `kacho#3251`; порядок с
   этой задачей — Р8. Примечание `before: v_get` ресурса `repositories` («absent that tuple
   `user:*` has no access → uniform 404») после этой под-фазы неверно для публичного реестра,
   но переносится в канон kaname побайтово (SC-70 (г) kaname): его правка здесь сломала бы
   равенство блоков. Это примечание переписывает `kacho#3251`: её DoD требует ноль вхождений
   `user:*` в манифестах, включая комментарии, и правит канон вместе с kaname.
5. **Снятие приёма прежней редакции в kaname** — `kaname#858`. Её условие старта — манифест этой
   под-фазы в стволе kacho и на стендах.
6. **Отзыв выдачи при удалении реестра.** Каскада через границу службы нет (ban #4), и Р7
   объясняет, почему это безопасно.
7. **Поле видимости в потоке изменений реестра.** Событие журнала его не несёт (Р6).

## Опора: одобренные соседи

| сосед | отпечаток (`sha256sum` на ревизии этой редакции) | что закреплено | как эта под-фаза с ним стыкуется |
|---|---|---|---|
| kaname `docs/engineering/acceptance/anonymous-and-authenticated-are-subject-classes.md` @`422d1bc6f`, ред. 10 | `198db838d0a75b7f5b5bdbd5564bacec23a79cc00550a26e8830f3c6be61aac9` | Р9: одна выдача классу на `registry_registry:<id>` даёт `v_get`, `v_list` на реестр и наследуемое чтение репозиториев; Р10: сначала kaname, затем kacho; SC-70 (б): манифест новой редакции даёт блоки, равные канону побайтово | разделы `resources` и `roles` манифеста равны фикстуре П6 kaname `internal/manifest/testdata/registry.public-read-fixture.yaml` @`422d1bc6f`, раздел `seed` — прежний (Р1, REG-PUB-1-01); видимость выводится из выдачи (У3) |
| `docs/specs/sub-phase-REG-1-registry-repository-acceptance.md` (APPROVED 2026-07-20) | `6847687bbd99ee62a158bb09cafcbd0ac911b344b49cdedb8fc218d8c8c8dc11` | F1 и REG-1-02: у `Registry` нет верхнеуровневого `visibility`, авторитетный гейт видимости — `Repository.visibility` | **пересматривается частично** (Д2): появляется `Registry.visibility` только на выход. Авторитет — выдача в kaname, второго источника правды нет. Проверка REG-1-02 «поля `visibility` нет» заменяется проверкой «у нового реестра `visibility = PRIVATE`»; утверждения REG-1-02 об отсутствии `globalSlug`, `displayName` и инфра-полей остаются |
| `docs/specs/sub-phase-RG-1-registry-repository-overlay-acceptance.md` (APPROVED, редакция 2) | `429461ed56738dc22d71829fce7a99279dbfd04cdc3b6ca03a6a43a87a49423a` | D-6: любой путь, которым принципал САМ приводит репозиторий к PUBLIC, требует `admin` на реестре; D-7: поштучная публикация репозитория | поштучная публикация и `defaultRepositoryVisibility` не меняются (REG-PUB-1-27). Публичность реестра — выдача, и её гейт — право выдать в kaname (Р3), а не D-6. Тексты дерева, утверждающие «любой путь к PUBLIC — admin-gated» и «единственный рычаг публичности», переписываются (DoD S2) |

Если редакция соседа сменилась к ревизии ревью, опора перепроверяется до вердикта (fa-b7).

## Перепись производителей (до сценариев)

Команды выполнены на ревизиях из шапки; вывод приведён дословно или числом.

| что уже есть или чего нет | координата | чем измерено |
|---|---|---|
| в манифесте registry ветки эпика нет ни ключа `publicReadToChildren`, ни раздела `roles` | `services/registry/manifest.yaml` | `git grep -c "^roles:" e9ce4ffbd -- services/registry/manifest.yaml` → нет попаданий (rc 1); `git diff --stat a95248464 e9ce4ffbd -- services/registry/manifest.yaml` → пусто (на эпике манифест равен стволу) |
| манифест эпика по-прежнему пишет `user:*` (`kacho#3251` не сделан) | там же | `git grep -c "user:\*" e9ce4ffbd -- services/registry/manifest.yaml` → `5` (одна строка действия и четыре строки примечаний) |
| целевая редакция манифеста — фикстура kaname: две правки к разделам `resources` и `roles`, без правки строки `subjects` | kaname `internal/manifest/testdata/registry.public-read-fixture.yaml` | `diff` фикстуры прежней редакции и фикстуры П6 @`422d1bc6f` → ровно `+publicReadToChildren: true` и `+roles: … registry.public.read`. Тело ствола kacho без комментариев и пустых строк отличается от прежней фикстуры ровно разделом `seed` (9 строк: учётка `kacho-registry` и вступление в `module-relation-writers`, #914), которого в фикстурах kaname нет; разделы `resources` совпадают |
| канон kaname в стволе несёт `public_reader` | kaname `proto/kaname/cloud/iam/v1/fga_model.fga` строки 1307–1361 | прочитано @`422d1bc6f`: `define public_reader: [system_class]` у `registry_registry`; `… or public_reader from parent` в `v_get`, `v_list` у `registry_repository` |
| пин kaname в kacho и тег образа kaname на стендах — до #856, и поднимаются только вместе | `go.mod:120`; `tag: 746-b20866a6` в 5 профилях umbrella (`values.yaml:127`, `values.a8f60d.yaml:624`, `values.fe3455.yaml:194`, `values.fe3455-prod.yaml:294`, `values.prorobotech.yaml:106`); согласие держит `deploy/outsourced_image_pin_agrees_with_module_pin_test.go` | `github.com/PRO-Robotech/kaname v0.4.1-0.20261015230631-b20866a67bb5` @`e9ce4ffbd`; `git grep -n "tag: 746-b20866a6" e9ce4ffbd -- deploy` → 5 строк; образ `docker.io/prorobotech/kaname:main-422d1bc6` опубликован (перечень тегов реестра образов, 228 тегов, есть `main-422d1bc6`) |
| сверка манифестов с каноном из пина | `internal/repohygiene/modelcanonpin_test.go:40` | `git grep -n "func TestModelCanonAgreesWithPlatformManifests" e9ce4ffbd -- internal/repohygiene` → 1 строка |
| судья формы манифеста читает каталог прав, **встроенный в kaname из пина**, а не каталог края kacho | kaname `internal/manifestcheckrun/run.go:176` (`seed.LoadPermissionRegistry`), `internal/apps/kaname/seed/permissions.go:121` (`//go:embed embedded/permission_catalog.json`) | прочитано @`422d1bc6f`; подтверждено опытом E1 (посев ниже): строки, добавленные в `gateway/internal/middleware/embed/permission_catalog.json` kacho, вердикт не меняют |
| привязка записи каталога к ресурсу выводит ресурс из ИМЕНИ СЛУЖБЫ; методы репозитория живут в `RegistryService` и приписываются ресурсу `registries`; kaname объявляет `registry.repositories` ресурсом без собственной службы | kaname `internal/manifest/roleexport/attribution.go` (`splitFQN`), `internal/authzmap/catalog_resource_spelling.go` (`catalogResourcesWithoutOwnService`: «службы `RepositoryService` в контрактах нет»); все 9 методов репозитория в каталоге — `scope_filtered`, `required_relation` пуст | прочитано @`422d1bc6f`; `grep -B2 -A12 '"kacho.cloud.registry.v1.RegistryService/GetRepository"'` встроенного каталога → `"required_relation": ""`, `"scope_filtered": true` |
| действие без отношения (`scope_filtered`) судья освобождает от гейта и классом роли не считает | kaname `internal/manifest/roleexport/producibility.go:156` (`Covers`: `a.Exempt() || a.Internal → continue`) | прочитано; опыт E2 |
| гейт дерева kacho требует производителя у каждого структурного отношения типов потребителей; `system_class` не числится вершиной субъекта | `internal/repohygiene/modelrelationproducer_test.go` (`subjectUsersets`: `user`, `service_account`, `group#member`, `user:*`) | прочитано @`e9ce4ffbd`; с пином `422d1bc6f` гейт красный: `registry_registry#public_reader` «объявлено, но НИ ОДНА точка эмиссии его не пишет» (посев) |
| у `Registry` нет поля `visibility`; есть только `defaultRepositoryVisibility` и `Repository.visibility` | `proto/kacho/cloud/registry/v1/registry.proto` | `git grep -n "Visibility visibility\|Visibility default_repository_visibility" e9ce4ffbd -- proto/kacho/cloud/registry/v1/registry.proto` → `:59`, `:172` |
| держатели и тексты «у реестра нет верхнеуровневого `visibility`» | 12 строк в 7 файлах, из них 2 порождённых | `git grep -n "top-level visibility\|top-level \`visibility" e9ce4ffbd` → 12 строк: `proto/kacho/cloud/registry/v1/registry.proto:55`; `pkg/api/kacho/cloud/registry/v1/registry.pb.go:330` (порождён); `services/registry/internal/apps/kacho/api/registry/f5_default_visibility_test.go:37, :40`; `services/registry/tests/newman/cases/registry-redesign.py:15, :282, :289`; `services/registry/tests/newman/collections/registry-redesign.postman_collection.json:584, :628` (порождён `gen.py`); `services/registry/tests/newman/docs/CASES-INDEX.md` — 2 строки (описание набора и строка кейса `REG-RD-F1-FIELD-ABSENCE`); `ui-future/registry/src/api/types.ts:37` |
| тексты «единственный рычаг публичности» и «любой путь к PUBLIC — admin-gated», которые изменение делает ложными | 8 строк в 6 файлах, из них 1 порождённый | `git grep -n -i "ЕДИНСТВЕННЫЙ рычаг\|Единственный registry-level\|любой путь к PUBLIC\|Единственный рычаг публичности" e9ce4ffbd` → `internal/repohygiene/clienttruth_registry_apisurface.go:17`; `proto/kacho/cloud/registry/v1/registry.proto:54, :56`; `pkg/api/kacho/cloud/registry/v1/registry.pb.go:329, :331` (порождён); `services/registry/docs/content/api/repository.mdx:101`; `ui-future/shared/src/lib/resource-registry.tsx:5194`; `ui-future/shared/src/test/console-ops-match-contract.test.ts:28`. Третий текст того же рода — комментарий `enum Visibility`, `registry.proto:102-108` («ЛЮБОЙ путь, где принципал сам приводит ресурс к PUBLIC … требует registry admin») — прочитан |
| маска `UpdateRegistry`: известные пути и тексты неизменяемых | `services/registry/internal/apps/kacho/api/registry/validate.go` (`knownUpdateFields`, `immutableUpdateFields`); образец отказа поля только на выход — `lifecycle is read-only (system-managed)` у репозитория | прочитано @`e9ce4ffbd` |
| у всех методов `RegistryService` пол «1» | `registry_service.proto` | `git grep -c 'required_acr_min) = "1"' e9ce4ffbd -- …/registry_service.proto` → `15`; `git grep -c '  rpc ' …` → `15`; `"0"` → `0` |
| плоскость данных: без Bearer — `401` с `WWW-Authenticate`; отказ чтения — `404 NAME_UNKNOWN`; отказ записи — `403 DENIED`; `DELETE` — `405`; `_catalog` фильтрует каждое имя вопросом `v_list` | `services/registry/internal/dataplane/handler.go` (`ServeHTTP`, `challenge`, `servePullOnly`, `serveCatalog`, `servePush`, `check`, `writeNotFound`, `writeDenied`) | прочитано @`e9ce4ffbd` |
| плоскость данных переводит анонимный `sub` в `system_class:anonymous`, только если задана ручка; пробы этого уже есть | `dataplane/authz.go` (`fgaSubject`), `config.go:429` `KACHO_REGISTRY_ANONYMOUS_SUBJECT_ID` (умолчание пусто); пробы `TestSystemClass_SC39_RegistryAsksAsTheAnonymousClass`, `TestDataplane_RG1_AnonDisabled_TokenResolvesAsOrdinaryPrincipal`, `TestDataplane_RG1_B03_AnonPullPublic_200`, `…_B04B05_AnonPullPrivateOrAbsent_Uniform404`, `…_B07_AnonPushNoToken_401`, `…_B14_AnonTokenPushPublic_403Denied`, `…_B14_AnonTokenPushNewRepo_403Denied` | `git grep -c KACHO_REGISTRY_ANONYMOUS_SUBJECT_ID e9ce4ffbd -- services/registry/deploy deploy` → нет попаданий: ни один чарт и ни один профиль ручку не задаёт; пробы — посев ниже |
| kaname выпускает анонимный токен, только если задан `AnonymousClientID`; в стволе ручки нет, её вносит `kaname#495` | kaname `internal/registrytokenwire/build.go:41`; `cmd/kaname/serve.go:1218` | `git grep -n AnonymousClientID 422d1bc6f -- cmd internal/config` → нет попаданий (`hard-missing-knob-vs-unseeded`: дефект продукта, а не недосев). `kaname#495` (OPEN), PR `kaname#871` (OPEN, ветка `495`, голова `b1b4543c4`): ключ `api-server.registry-token.anonymous-client-id`, умолчание пусто (`internal/apps/kaname/config/defaults.go:70`), значение чарта `apiServer.registryToken.anonymousClientId: ""` (`deploy/values.yaml:276`), провязка (`cmd/kaname/serve.go:2381`) — `git grep -n "anonymous-client-id\|anonymousClientId" b1b4543c4` |
| стенд kacho ставит kaname СВОИМ вложенным чартом; его конфиг рендерит `registry-token` только с `issuer` и `service` | `deploy/helm/umbrella/charts/kaname/templates/configmap.yaml:95-112` (`$rt := .Values.config.apiServer.registryToken`; `registry-token:` — строка 105); путь значения в umbrella — `kaname.config.apiServer.registryToken.*` | прочитано @`e9ce4ffbd`; `git grep -c "anonymous-client-id\|anonymousClientId" e9ce4ffbd -- deploy services/registry/deploy` → нет попаданий |
| кэш положительных вердиктов registry — 2 с | `config.go:154` `KACHO_REGISTRY_AUTHZ_CACHE_TTL` (умолчание `2s`) | прочитано |
| удаление реестра требует пустого пространства имён и снимает кортежи реестра; удаление репозитория снимает кортежи репозитория | `services/registry/internal/apps/kacho/api/registry/delete.go` (`NamespaceEmpty` до `DELETING` и в работнике; `UnregisterIntentForDelete`); `DeleteRepository` — «unregister FGA repo-tuples» (`registry_service.proto`) | прочитано @`e9ce4ffbd` |
| консоль: карточка реестра показывает `defaultRepositoryVisibility`, репозитория — `visibility`; форма выдачи уже знает `system_class` | `ui-future/registry/src/registerExtensions.tsx:63, :87`; `ui-future/iam/src/components/organisms/iam/AccessBindingCreateForm/AccessBindingCreateForm.tsx:124` | прочитано @`e9ce4ffbd` |
| фикстуры консольных проб: арендатор с проектом, подъём уровня до «2» | `ui-future/e2e/specs/fixtures.ts` (`tenantWithProject`, `scopeIsReady`), `ui-future/e2e/specs/assurance.ts` (`raiseAssurance`), образцы — `system-class-subject.spec.ts`, `registry-tags.spec.ts` | прочитано |
| принципалы сквозных наборов | `tests/authz-fixtures/prodseed_matrix.py`: `jwtAccountAdminA` (администратор аккаунта A), `jwtProjectEditorA` (editor на проекте A1), `jwtStranger` (учётка без выдач); все — токены сервисных учёток, изъятые из пола уровня | прочитано @`e9ce4ffbd`, строки 919–933 |
| сквозной набор registry достаёт до плоскости данных и ручки токена | `services/registry/tests/newman/cases/registry-docker-facade-lane.py`; `deploy/e2e-shards.json` (`registryDataPlaneBaseUrl`) | прочитано |
| повтор активной выдачи — `ALREADY_EXISTS` в исходе операции | kaname `access_bindings_active_grant_uniq`, `create.go` (перевод нарушения уникальности в `codes.AlreadyExists` работником); SC-06 kaname | прочитано @`422d1bc6f` |

## Решения

**Р1. Манифест, пины и гейты S1 — одно изменение.** Тем же коммитом:

1. `services/registry/manifest.yaml`: ровно две правки фикстуры П6 kaname в разделах `resources`
   и `roles` — `publicReadToChildren: true` на ресурсе `registries` и раздел `roles` с ролью
   `registry.public.read` (описание, ярус `{tierType: iam.cluster, tierId: cluster_root}`,
   правило `module: registry`, `resources: [registries, repositories]`, `classes: [get, list]`).
   Раздел `seed` (учётка `kacho-registry`, вступление в `module-relation-writers`, #914) не
   трогается. Шапка манифеста утверждает: «Раздела `roles` здесь нет… живых системных ролей у
   модуля НОЛЬ». Это утверждение переписывается, иначе оно становится ложью (doc-truthfulness);
2. пин kaname в `go.mod` и `go.sum` — до ревизии ствола kaname, в которую влита `kaname#872` (Д9), не ниже `422d1bc6f`; посев П0 мерен на `422d1bc6f`
   (`v0.4.1-0.20261017105825-422d1bc6ff22`);
3. тег образа kaname в 5 профилях umbrella (перепись) — до той же ревизии
   (`main-<sha8>`; в посеве П0 — `main-422d1bc6`), с правкой комментария «Ревизия ветки службы …» у `values.yaml:124`. Без
   этого `TestOutsourcedImagePinAgreesWithItsModulePin` даёт 7 находок (запись круга 1);
4. `internal/repohygiene/modelrelationproducer_test.go`: `system_class` добавляется в
   `subjectUsersets`. Отношение, чей состав — только вершины субъекта, есть выдача; её пишет
   разворачивание привязок kaname, и точки эмиссии в дереве kacho у неё нет by construction.
   Это тот же довод, по которому там уже стоит `user:*`;
5. гейт формы манифеста зеленеет правкой судьи в kaname по Д9; в дереве kacho для этого ничего не
   заводится.

Порядок выкатки — Р10 kaname: kaname с #856 на стенде раньше kacho с этим манифестом.

**Р2. `Registry.visibility` — поле только на выход, выведенное из выдачи.** Новое поле
`Visibility visibility = 13` в `message Registry`. Перечисление `Visibility` прежнее,
`PRIVATE`/`PUBLIC`. Определение, которое заносится в комментарий поля:

- `PUBLIC` — у класса `anonymous` есть публичное чтение этого реестра как контейнера
  (отношение `public_reader` на `registry_registry:<id>`, Р9 kaname). Значит, без входа
  читаются реестр и каждый его репозиторий, включая будущие;
- `PRIVATE` — такого чтения у класса `anonymous` нет.

Своего столбца у поля нет. Значение спрашивается у kaname на каждом чтении `Get` и `List`. Это
и есть «видимость выводится из выдачи» (`kacho#3274`, У3 kaname): выдача, заведённая или
снятая напрямую через API привязок, видна в реестре так же, как выдача из консоли. Пересмотр
F1 записан решением Д2.

**Р3. Кто вправе сделать реестр публичным — тот, кто вправе выдать.** Сделать реестр публичным
значит создать выдачу. Её гейты принадлежат kaname и не меняются: право выдать (владелец
аккаунта либо `admin` на области, SC-20), уровень сессии «2» (SC-26), свежесть не старше
15 минут для выдачи классу (SC-25, SC-66); сервисная учётка с правом выдаёт без уровня и
окна (SC-27). Отличие от D-6 RG-1 называется прямо. `admin` только на объекте реестра без права
выдать на области реестр публичным не делает: ворота выдачи строже ворот D-6, и это сужение, а
не расширение. Путь установки — Д1: установка и снятие идут глаголами `AccessBindingService` с
удостоверением самого вызывающего; консоль составляет запрос сама; своего пишущего метода у
registry нет (REG-PUB-1-18).

**Р4. Видимость описывает «без входа».** Выдача классу `authenticated` при недоступном
`anonymous` оставляет `visibility = PRIVATE`. Без входа реестр не читается, и значение верно
по определению Р2. Перечень выдач (страница прав) показывает выдачу вошедшим отдельно (Д3).

**Р5. Отказ в выводе видимости — отказ чтения.** Если kaname не ответил на вопрос о видимости,
`Get` и `List` отвечают `UNAVAILABLE` с фиксированным текстом и страницы не отдают.
`PRIVATE` наугад — ложь пустым значением (`api-empty-means-empty`), поэтому fail-closed.
Цена (ban18-q-perf) — один вопрос к kaname на `Get` и ⌈N/100⌉ пакетных вопросов на страницу
`List` из N реестров (пакет — до 100 объектов, `sec-page-then-check`). Время замеряется в DoD S2.

**Р6. Поток изменений реестра видимости не несёт.** Нагрузка события журнала — столбцы строки
реестра (`subscriptionjournal/journal.go`), а у видимости столбца нет. Смена выдачи строку
реестра не трогает, поэтому события нет. Комментарий поля называет, какие чтения его
заполняют: `Get` и `List`. В событии потока значение — `VISIBILITY_UNSPECIFIED` («это чтение
поле не вычисляет»). Консоль после своей операции перечитывает реестр (REG-PUB-1-40, 45).

**Р7. Удаление реестра выдачу не отзывает.** Каскада через границу службы нет (ban #4).
Идентификатор реестра неизменяем и повторно не выдаётся (ban #15), поэтому оставшаяся выдача
на удалённый `registry_registry:<id>` ничего не открывает. Перечень выдач показывает её
висячей, снять её можно глаголом отзыва (REG-PUB-1-17, REG-PUB-1-29).

**Р8. С `kacho#3251` эта задача не связана побайтово.** Перевод слова `user:*` в сборщике kaname
временный (`internal/modelrender/render.go`, `subjectWords`). Рендер строки `subjects` с `user:*`
и с `system_class` одинаков. Значит, блоки, порождённые манифестом этой под-фазы, равны канону
при любом порядке двух задач. Эта задача строку `subjects` не правит; какая из двух задач
влита второй, та перебазируется. Предикат — REG-PUB-1-01 в обоих порядках.

**Р9. Сквозной `docker pull` без учётки: звенья и порядок.**

1. kaname: ручка службы `api-server.registry-token.anonymous-client-id` (страж формы при старте,
   умолчание пусто — поток выключен). Её делает `kaname#495`, PR `kaname#871` (Д5); это правка
   kaname вне этой задачи;
2. **S3, чарты kacho:**
   - чарт registry выводит `KACHO_REGISTRY_ANONYMOUS_SUBJECT_ID` из значения
     `anonymousSubjectId` (умолчание пусто);
   - вложенный чарт kaname стенда kacho
     (`deploy/helm/umbrella/charts/kaname/templates/configmap.yaml`, блок `registry-token:` у
     строки 105) выводит `anonymous-client-id` из
     `kaname.config.apiServer.registryToken.anonymousClientId` (умолчание пусто);
   - рендер umbrella отказывает, если оба значения заданы и различаются, — по образцу
     `kaname.laneServiceAud` (`charts/kaname/templates/_helpers.tpl:130-132`): у полосы две
     стороны и одно значение;
3. **S6, значения и пины:**
   - пин kaname в `go.mod` и тег образа kaname в профилях umbrella поднимаются ВТОРОЙ раз — до
     ревизии ствола kaname, в которую влит `kaname#495`; поднимаются вместе по Р1 п. 3;
   - профили стенда kacho задают оба значения звена 2 одним и тем же зарезервированным
     идентификатором, которого нет ни у одного принципала. Производитель — стадия S6 задачи
     `kacho#3274`, а не kaname;
4. **S6, проба:** сквозная проба настоящим клиентом.

**Порядок исполнения:** S1 ждёт пин kaname с правкой судьи формы (`kaname#872`,
Д9). Затем S3 (чарты) → S6 (значения и пины) → S3 (newman 20–27, 29 на стенде) →
S6 (`docker`, 50, 51). S2, S4, S5 и integration-часть S3 (REG-PUB-1-28) от звеньев 1–3 не
зависят. Расширение поверхности (ban18-q-security) названо: включённые ручки дают любому без
учётки токен только чтения, и он читает только то, что выдано классу `anonymous`. Без такой
выдачи всё отвечает `404` (REG-PUB-1-21).

**Р10. Вошедший без прав в аккаунте читает публичный реестр и через API-край.** Говорящий с
личностью несёт класс `anonymous` (Р2 kaname). Поэтому `GET /registry/v1/registries/{id}` и
`…/repositories` для такого вызывающего проходят и Check края (`v_get` на реестр), и сужение
строк в обработчике (`v_list`). Ему видны метаданные реестра: `projectId`, `name`,
`description`, `labels`, `regionId`, `endpoint`, `repositoryCount`. `ListRegistries` с
`projectId` чужого проекта показывает ему публичные реестры этого проекта: обработчик сужает
страницу только вопросом `v_list` (`services/registry/internal/handler/public.go:85-104`). Это
следствие выдачи анониму, и оно названо здесь (ban18-q-security). Консоль предупреждает о нём
в диалоге включения (REG-PUB-1-40).

**Соответствие рынку (ban18-q-market-recognition).** Публичный реестр образов, который тянется
без учётки, — общепринятое свойство реестров. Наше отличие: публичность не флаг реестра, а
обычная выдача роли классу. Она заводится, отзывается и пишется в журнал аудита теми же
глаголами, что любая выдача, и видна в перечне прав.

## Как строится «Дано»

Все «Дано» строит посев. Ручной правки базы нет.

- **П0 — дерево kacho для S1** (проверено прогоном, раздел «Посев «Дано»: прогон»): временная
  копия `e9ce4ffbd`; манифест Р1 п. 1; пин kaname `GOWORK=off go get
  github.com/PRO-Robotech/kaname@422d1bc6f`; тег образа `main-422d1bc6` в 5 профилях; правка Р1
  п. 4. Судья формы (Д9) собирается из копии kaname
  `GOWORK=off go build ./tools/modulemanifestcheck` и наводится на корень копии kacho
  (`-root=`), как его зовёт `TestModuleManifestFormIsJudgedByTheOneExecutor`; в посеве — копия
  `422d1bc6f`, для «И» сценария 01 — ревизия с `kaname#872`.
- **П1 — integration registry** (`testcontainers`, Postgres 16, миграции registry ствола и этого
  изменения). Два реестра в `prj-A` создаются вызовом use-case `Create`; X и Y здесь — **метки**,
  id выдаёт `ids.NewID`, и сценарии ссылаются на значения, захваченные из ответа. Дублёр
  решения о доступе — порт клиента проверки registry (`internal/check`): записывает вопросы и
  отвечает заданной ему таблицей. Он выполняет контракт настоящего тем же кодом разбора ответа
  (`double-must-honor-real-contract`). «Публичное чтение X есть» значит: дублёр отвечает «да»
  на вопрос о публичном чтении класса `anonymous` на X. Форму вопроса выбирает замысел.
  Плоскость данных в П1 собирается `dataplane.New` с поддельным проверяющим токена, как в
  пробах пакета `dataplane`.
- **П2 — стенд** (своё пространство имён `make -C deploy stand-ns-up`, сквозной набор registry). В стенд
  выкачены kaname с #856 и kacho с этим изменением. Для стендовой части S3 и для S6 — ещё
  kaname с `kaname#495` и значения ручек из профиля (Р9 п. 3). Посев набора (своё
  пространство на прогон, имена с `{{runId}}`):
  - принципалы — из `tests/authz-fixtures/prodseed_matrix.py`: **выдающий**
    `jwtAccountAdminA` (администратор аккаунта A: право выдать на проекте A1; токен сервисной
    учётки, уровень и окно свежести к нему не применяются, SC-27); **редактор**
    `jwtProjectEditorA` (editor на A1, без права выдать); **посторонний** `jwtStranger`
    (вошедший без выдач в аккаунте A);
  - реестры X и Y в проекте A1, созданные выдающим через `POST /registry/v1/registries`;
    `Operation` доведена до `done=true` без `error`;
  - репозитории `X/app` и `Y/app`, запушенные через плоскость данных до любой выдачи
    удостоверением вида SECRET выдающего (`SAKeyService.Issue`, как `dataplane-e2e.sh`);
    репозиторий `Y/pub`, созданный `CreateRepository` с `visibility=PUBLIC` (поштучная
    публикация, D-7);
  - роли `rol-reg-get` (`[get]` над `registry.registries`, без имён и меток) и
    `rol-reg-edit` (`[get, list, update]` над `registry.registries`), обе заведены
    `RoleService.Create` в аккаунте A от имени выдающего;
  - **выдача ПЧ** — тело
    `{"subjects":[{"type":"SUBJECT_TYPE_SYSTEM_CLASS","id":"anonymous"}],"roleId":"rolb1325b011aa17211d","scopeType":"iam.project","scopeId":"{{existingProjectId}}","target":{"resources":{"resources":[{"type":"registry.registries","id":"{{registryX}}"}]}}}`,
    отправитель — выдающий;
  - **анонимный токен** — `GET <realm>?service=<service>&scope=repository:<X>/app:pull` без
    `Authorization`; `realm` и `service` берутся из `WWW-Authenticate` первого ответа `401`
    плоскости данных, а не вписываются литералом.

  «Материализовано» значит: опрос раз в 200 мс с пределом 30 с (окно SC-13 kaname) плюс окно
  кэша `KACHO_REGISTRY_AUTHZ_CACHE_TTL` дошёл до ожидаемого ответа. Уборка заводится до
  создания: выдачи, реестры, роли снимаются тем же прогоном и на падении.
- **П3 — консоль на стенде П2.** Человек входит фикстурой `tenantWithProject` (владелец
  своего аккаунта), уровень поднимается `raiseAssurance`, область готова — `scopeIsReady`.
  Реестры X и Z в его проекте создаются через API. Репозиторий `X/app` создаётся
  `CreateRepository` (`POST /registry/v1/registries/{X}/repositories`, тело
  `{"repository":"app"}`; `visibility` не задана, наследуется `PRIVATE`). Оба шага — так же, как
  в `registry-tags.spec.ts`.

## Посев «Дано»: прогон

Временные копии kacho (`e9ce4ffbd`) и kaname (`422d1bc6f`) в `kacho-workspace/tmp`, после
прогона сняты (`git worktree remove`). Стенд П2/П3 и integration П1 не поднимались.

| «Дано» | команда | исход |
|---|---|---|
| П0 без Р1 п. 4 | `GOWORK=off go test ./internal/repohygiene/ ./deploy/ -count=1` | `deploy` — `ok`; `repohygiene` — FAIL, 3 теста: `TestConsumerOwnedStructuralRelationsHaveProducers` (`registry_registry#public_reader` без производителя), `TestModuleManifestFormIsJudgedByTheOneExecutor`, `TestManifestFormCensusFollowsTheTree` (оба — находка B1 дословно) |
| П0 целиком (с Р1 п. 4) | `GOWORK=off go test ./internal/repohygiene/ ./deploy/ -count=1 -v` | `deploy` — `ok`, верхнеуровневых PASS 488, FAIL 0; в том числе `TestOutsourcedImagePinAgreesWithItsModulePin` зелёный при теге `main-422d1bc6`. `repohygiene` — PASS 2636, FAIL 2, SKIP 2 («не выполнилось», не зелёные): красные — `TestModuleManifestFormIsJudgedByTheOneExecutor` и `TestManifestFormCensusFollowsTheTree`, их корень снимает Д9; `TestConsumerOwnedStructuralRelationsHaveProducers` — PASS (структурных 30, на типах потребителей 20). Пропущены `TestFoundationNamesNoMovingPackageOutsideAnImport` и `TestFoundationProdCodeNamesNoForeignTreePath` |
| П1, плоскость данных | `GOWORK=off go test ./services/registry/internal/dataplane/ -count=1 -v` | `ok`, PASS 115, FAIL 0; в том числе 7 проб анонима из переписи (REG-PUB-1-28 и integration-половины 20, 21, 24, 25) |
| E0 — судья kaname без правок на П0 | `modulemanifestcheck -root=<копия kacho>` | код 1; `каталог прав: записей 359 · привязано действий 356`; у registry `правила ролей: … пар (ресурс, класс) 2 · находок 1` — находка B1 |
| E1 — две строки `kacho.cloud.registry.v1.RepositoryService/{Get,List}` с `v_get`/`v_list` на `registry_repository` добавлены только в каталог края kacho | тот же | код 1, та же находка: каталог kacho судья не читает |
| E2 — те же две строки в каталоге, встроенном в kaname, вида `scope_filtered` (без отношения), плюс запись написания `registry.repository → registry.repositories` | судья, собранный из правленой копии kaname | код 1; две находки «класс "get"/"list" на ресурсе "repositories" … не покрывает ни одного пригодного действия. Все 2 действий ресурса освобождены от гейта» |
| E3 — как E2, но строки несут `required_relation` `v_get`/`v_list` и `scope_extractor.object_type` `registry_repository` | тот же | код 0; у registry `пар (ресурс, класс) 4 · находок 0` |

## Сценарии

### S1. Манифест, пины и гейты (kacho)

#### Сценарий 01: манифест новой редакции даёт блоки, равные канону, и проходит гейты формы

**ID:** REG-PUB-1-01
**Given** П0 с пином kaname, в который влита `kaname#872` (Д9)
**When** `GOWORK=off go test ./internal/repohygiene/ -run TestModelCanonAgreesWithPlatformManifests -count=1 -v`
**Then** `ok`; в выводе `блоков сверено 27 из 27`
**And** `GOWORK=off go test ./internal/repohygiene/ -run 'TestModuleManifestFormIsJudgedByTheOneExecutor|TestManifestFormCensusFollowsTheTree|TestModuleManifestsOfThePlatformAreReadable|TestManifestIsNotASecondDeclarationOfARight|TestManifestNamedPredicateIsRunnableInThisTree|TestConsumerOwnedStructuralRelationsHaveProducers' -count=1 -v` — `ok`; в выводе судьи у `services/registry/manifest.yaml` `правила ролей: … находок 0`
**And** `GOWORK=off go test ./deploy/ -run 'TestOutsourcedImagePinAgreesWithItsModulePin$' -count=1` — `ok`
**And** тот же прогон с манифестом, где строка `subjects` переведена на `system_class` (содержимое
`kacho#3251`), — `ok` (Р8)
**Близнец (отрицательный):** манифест Р1, в котором ключ стоит на `repositories` вместо
`registries`. `TestModelCanonAgreesWithPlatformManifests` красный, и в выводе находка
`resources[1].publicReadToChildren: на тип registry_repository не указывает ни один ресурс модуля registry — объявление без следствия`
(SC-70 (в), SC-71 (б) kaname). Отличие — одно поле: ресурс, на котором стоит ключ.

#### Сценарий 02: роль доставлена — выдача ПЧ принимается

**ID:** REG-PUB-1-02
**Given** П2
**When** выдающий шлёт `POST /iam/v1/accessBindings` с телом «выдача ПЧ»
**Then** ответ — `Operation`; опрос `OperationService.Get` доходит до `done=true` без `error`
**And** `GET /iam/v1/accessBindings/{id}` → `roleId = "rolb1325b011aa17211d"`, субъект
`{"type":"SUBJECT_TYPE_SYSTEM_CLASS","id":"anonymous"}`
**Близнец (отрицательный):** то же тело с `"roleId":"rolb0000000000000000"` (форма id верна, роли
с таким id нет) → синхронно `FAILED_PRECONDITION` (HTTP 400), текст
`Role rolb0000000000000000 not found`. Тот же отказ даёт kaname без манифеста Р1 (SC-70 (а)).
Отличие — один факт: существует ли роль.

#### Сценарий 03: роль даёт только чтение

**ID:** REG-PUB-1-03
**Given** П2
**When** `GET /iam/v1/roles/rolb1325b011aa17211d` от выдающего
**Then** `200`; действующие глаголы роли — ровно `get` и `list` над `registry.registries` и
`registry.repositories`, других правил нет
**Близнец (отрицательный):** тело «выдача ПЧ» с `"roleId":"{{rolRegEdit}}"` → синхронно
`FAILED_PRECONDITION`, текст SC-21 kaname
`Role <id> grants verbs beyond get and list; a system class subject accepts read-only roles`.
Отличие — один факт: глаголы роли.

### S2. Видимость реестра в API (registry)

#### Сценарий 10: новый реестр — приватный

**ID:** REG-PUB-1-10
**Given** П2, выдач классам на X нет
**When** `GET /registry/v1/registries/{X}` и `GET /registry/v1/registries?projectId={{existingProjectId}}` от выдающего
**Then** `200`; у X `visibility = "PRIVATE"` в обоих ответах; `defaultRepositoryVisibility = "PRIVATE"`
**Близнец:** REG-PUB-1-11 — отличие одно: выдача ПЧ.

#### Сценарий 11: выдача ПЧ делает реестр публичным

**ID:** REG-PUB-1-11
**Given** П2; выдача ПЧ создана (REG-PUB-1-02) и материализована
**When** `GET /registry/v1/registries/{X}` и `GET /registry/v1/registries?projectId={{existingProjectId}}` от выдающего
**Then** у X `visibility = "PUBLIC"` в обоих ответах; у Y `visibility = "PRIVATE"`. Выдача
сужена целью X (SC-68 kaname)
**And** `GET …/registries/{X}/operations` не содержит операции после `Create`: выдача мутацией
реестра не является
**Близнец (отрицательный):** REG-PUB-1-10 — то же без выдачи → `PRIVATE`.

#### Сценарий 12: отзыв выдачи возвращает приватность

**ID:** REG-PUB-1-12
**Given** REG-PUB-1-11
**When** выдающий шлёт `DELETE /iam/v1/accessBindings/{id}` выдачи ПЧ; `Operation` доходит до `done=true`
**Then** опрос `GET /registry/v1/registries/{X}` доходит до `visibility = "PRIVATE"` в пределах окна П2
**Близнец:** REG-PUB-1-11 — тот же реестр до отзыва: `PUBLIC`.

#### Сценарий 13: роль без правила над репозиториями реестр публичным не делает

**ID:** REG-PUB-1-13
**Given** П2; выдающий выдаёт классу `anonymous` роль `rol-reg-get` на A1 с целью X (тело
«выдача ПЧ» с `"roleId":"{{rolRegGet}}"`); выдача материализована
**When** `GET /registry/v1/registries/{X}` от выдающего
**Then** `visibility = "PRIVATE"`: класс читает метаданные реестра, но не его репозитории, а
`public_reader` не пишется (SC-73 kaname)
**Близнец:** REG-PUB-1-11 — та же цель и тот же класс, роль `registry.public.read` →
`PUBLIC`. Отличие — одно: покрывает ли правило роли `registry.repositories`.

#### Сценарий 14: выдача вошедшим видимость «без входа» не меняет

**ID:** REG-PUB-1-14
**Given** П2; тело «выдача ПЧ» с субъектом
`{"type":"SUBJECT_TYPE_SYSTEM_CLASS","id":"authenticated"}` принято и материализовано
**When** `GET /registry/v1/registries/{X}` от выдающего
**Then** `visibility = "PRIVATE"` (Р4)
**And** `GET /registry/v1/registries/{X}/repositories` от постороннего → `200`, в странице `app`
(выдача действует: контроль живости, SC-69 kaname)
**Близнец:** REG-PUB-1-11 — субъект `anonymous` → `PUBLIC`. Отличие — один факт: класс субъекта.

#### Сценарий 15: видимость нельзя задать правкой реестра

**ID:** REG-PUB-1-15
**Given** П2, X приватный
**When** `PATCH /registry/v1/registries/{X}` от выдающего с телом
`{"visibility":"PUBLIC","updateMask":"visibility"}`
**Then** синхронно `INVALID_ARGUMENT` (HTTP 400, `code` 3), текст
`visibility is read-only (derived from access bindings)`; `Operation` не создана; выдачи нет
**And** тело `{"description":"d-{{runId}}","visibility":"PUBLIC"}` с пустой маской → `Operation`,
`done=true` без `error`; `description` применён; `visibility` осталось `PRIVATE`. Ключ
`visibility` в запросе правки неизвестен, и REST-край отбрасывает его так же, как любой
неизвестный ключ тела (Д8)
**Близнец:** маска `description` с тем же телом → `Operation`, `done=true`, `description`
применён. Отличие — одно: путь маски.

#### Сценарий 16: kaname недоступен — чтение реестра отказывает, а не лжёт

**ID:** REG-PUB-1-16
**Given** П1; дублёр решения о доступе отвечает «доступ есть» на вопрос о чтении X
вызывающим и ошибкой транспорта `Unavailable` на вопрос о публичном чтении
**When** `Get(X)` и `List(prj-A)` через обработчик registry
**Then** оба → `UNAVAILABLE`, текст фиксирован и не содержит текста ошибки транспорта
(`hard-no-err-echo`); `List` не отдаёт ни одной строки
**Близнец:** дублёр отвечает «нет» на вопрос о публичном чтении → `Get` `200`,
`visibility = PRIVATE`. Отличие — один факт: ответил ли kaname.

#### Сценарий 17: удаление реестра выдачу не отзывает

**ID:** REG-PUB-1-17
**Given** REG-PUB-1-11; X опустошён и удалён выдающим: теги `X/app` сняты `DeleteTag`,
репозиторий снят `DeleteRepository`, затем `DELETE /registry/v1/registries/{X}`; каждая
`Operation` — `done=true` без `error` (удаление реестра требует пустого пространства имён,
`delete.go`)
**When** `GET /iam/v1/accessBindings/{id}` выдачи ПЧ от выдающего
**Then** `200`; выдача существует, цель — прежний id X (Р7)
**And** `DELETE /iam/v1/accessBindings/{id}` → `Operation`, `done=true` без `error`
**Близнец:** REG-PUB-1-12 — отзыв той же выдачи при живом X проходит так же. Отличие — один
факт: существует ли реестр. Что видит аноним после удаления — REG-PUB-1-29 (S3).

#### Сценарий 18: редактор проекта реестр публичным не делает

**ID:** REG-PUB-1-18
**Given** П2, X приватный
**When** редактор шлёт `POST /iam/v1/accessBindings` с телом «выдача ПЧ»
**Then** синхронно `PERMISSION_DENIED` (HTTP 403, `code` 7), тот же текст, что у выдачи
человеку без права (SC-20 kaname); `Operation` не создана; `GET /registry/v1/registries/{X}` →
`visibility = "PRIVATE"`
**Близнец:** REG-PUB-1-02 — то же тело от выдающего принято. Отличие — один факт: право выдать.

### S3. Плоскость данных: что видит аноним (registry)

Стендовая часть S3 (20–27, 29) исполняется после S3 (чарты) и S6 (значения и пины) — порядок
Р9. Аноним предъявляет анонимный токен П2. Ответы — плоскость данных `/v2/...`.

#### Сценарий 20: аноним тянет образ публичного реестра, включая репозиторий, созданный после выдачи

**ID:** REG-PUB-1-20
**Given** REG-PUB-1-11; затем выдающий пушит репозиторий `X/late`
**When** аноним: `GET /v2/{X}/app/manifests/latest`, затем `GET /v2/{X}/app/blobs/<digest слоя>`;
то же для `X/late`
**Then** все четыре → `200`; дайджест тела манифеста равен дайджесту, который вернул push
**Близнец (отрицательный):** REG-PUB-1-21.

#### Сценарий 21: приватный реестр аноним не отличает от несуществующего

**ID:** REG-PUB-1-21
**Given** П2 без выдачи ПЧ
**When** аноним: `GET /v2/{X}/app/manifests/latest`; `GET /v2/{X}/nonexistent-{{runId}}/manifests/latest`
**Then** оба → `404`, тела побайтово равны, `errors[0].code = "NAME_UNKNOWN"`
**Близнец:** REG-PUB-1-20 — отличие одно: выдача ПЧ.

#### Сценарий 22: аноним перечисляет теги публичного репозитория

**ID:** REG-PUB-1-22
**Given** REG-PUB-1-20
**When** аноним `GET /v2/{X}/app/tags/list`
**Then** `200`, `tags` содержит `latest`
**Близнец (отрицательный):** тот же запрос к `Y/app` (Y приватный) → `404 NAME_UNKNOWN`.
Отличие — один факт: реестр в цели выдачи.

#### Сценарий 23: каталог анонима — репозитории публичных реестров и только они

**ID:** REG-PUB-1-23
**Given** REG-PUB-1-20
**When** аноним `GET /v2/_catalog?n=1000`, по ссылкам `Link: rel="next"` до конца
**Then** собранный перечень содержит `{X}/app` и `{X}/late`; не содержит `{Y}/app` и `{Y}/pub`.
Поштучная публикация даёт только `v_get`, не `v_list` (SC-67 kaname)
**Близнец:** тот же обход от выдающего → перечень содержит `{Y}/app`. Отличие — один факт:
вызывающий.

#### Сценарий 24: аноним не пишет — ни в существующий, ни в новый репозиторий

**ID:** REG-PUB-1-24
**Given** REG-PUB-1-11
**When** аноним `POST /v2/{X}/app/blobs/uploads/` и `POST /v2/{X}/new-{{runId}}/blobs/uploads/`;
`PUT /v2/{X}/app/manifests/anon-{{runId}}` с телом существующего манифеста
**Then** каждый → `403`, `errors[0].code = "DENIED"`, текст
`requested access to the resource is denied`; после этого `GET /v2/{X}/app/tags/list` от
выдающего тега `anon-{{runId}}` не содержит, а `_catalog` не содержит `{X}/new-{{runId}}`
**And** аноним `DELETE /v2/{X}/app/manifests/latest` → `405` (снято на плоскости данных для всех)
**Близнец:** `POST /v2/{X}/app/blobs/uploads/` от выдающего → `202`. Отличие — один факт: вызывающий.

#### Сценарий 25: без токена — вызов на вход, а не анонимное чтение

**ID:** REG-PUB-1-25
**Given** REG-PUB-1-11
**When** `GET /v2/{X}/app/manifests/latest` без `Authorization`
**Then** `401`, заголовок `WWW-Authenticate: Bearer realm="<realm>",service="<service>"` (без
`error=`); тело `errors[0].code = "UNAUTHORIZED"`
**And** с `Authorization: Bearer <испорченный токен>` → `401` и `error="invalid_token"` в
заголовке: негодное удостоверение анонимом не становится (SC-33 kaname)
**Близнец:** REG-PUB-1-20 — тот же запрос с анонимным токеном → `200`. Отличие — один факт: токен.

#### Сценарий 26: отзыв снимает анонимное чтение со всех репозиториев разом

**ID:** REG-PUB-1-26
**Given** REG-PUB-1-20
**When** выдача ПЧ отозвана (REG-PUB-1-12)
**Then** опрос `GET /v2/{X}/app/manifests/latest` и `GET /v2/{X}/late/manifests/latest`
анонимом доходит до `404 NAME_UNKNOWN` по обоим в пределах окна П2
**And** `GET /v2/{X}/app/manifests/latest` от выдающего → `200` (отозвана только выдача классу)
**Близнец:** REG-PUB-1-20 — до отзыва `200`.

#### Сценарий 27: поштучная публикация в приватном реестре работает как прежде

**ID:** REG-PUB-1-27
**Given** П2 без выдачи ПЧ; `Y/pub` опубликован поштучно
**When** аноним `GET /v2/{Y}/pub/manifests/<тег посева>`; `GET /v2/{Y}/pub/tags/list`;
`GET /registry/v1/registries/{Y}` от выдающего
**Then** манифест → `200`; `tags/list` → `404 NAME_UNKNOWN` (публикация даёт только `v_get`);
у Y `visibility = "PRIVATE"`
**Близнец:** аноним `GET /v2/{Y}/app/manifests/<тег>` (не опубликован) → `404`. Отличие — один факт:
поштучная публикация.

#### Сценарий 28: integration — анонимный субъект спрашивается классом

**ID:** REG-PUB-1-28
**Given** П1; плоскость данных собрана с `WithAnonymousSubject("<зарезервированный id>")`;
проверяющий токена отдаёт `sub` = этот id
**When** `GET /v2/{X}/app/manifests/latest`
**Then** дублёр решения о доступе получил ровно один вопрос: субъект
`system_class:anonymous`, отношение `v_get`, объект `registry_repository:{X}/app`
**Близнец:** та же сборка с пустым `WithAnonymousSubject("")` — субъект вопроса не
`system_class:anonymous` (анонимный поток выключен, secure-by-default). Отличие — одна ручка.

#### Сценарий 29: после удаления реестра аноним получает отказ чтения

**ID:** REG-PUB-1-29
**Given** REG-PUB-1-17 до отзыва выдачи: X удалён, выдача ПЧ на прежний id X существует
**When** аноним `GET /v2/{X}/app/manifests/latest`
**Then** опрос доходит до `404` с телом, побайтово равным телу REG-PUB-1-21. Отказ даёт
`servePullOnly` → `writeNotFound`: кортежи репозитория сняты `DeleteRepository`, кортежи
реестра — работником удаления (`UnregisterIntentForDelete`), поэтому `public_reader from parent`
ничего не находит и Check анонима — «нет». До материализации снятия ответ может прийти от
движка (репозитория в нём уже нет, удаление реестра требует пустоты). Поэтому сценарий
утверждает условие, к которому сходится опрос в окне П2, а не первый ответ
**Близнец:** REG-PUB-1-20 — тот же запрос при живом X → `200`. Отличие — один факт: существует ли реестр.

### S4. API-край (gateway, registry)

#### Сценарий 30: аноним на API-крае отвергается до решения

**ID:** REG-PUB-1-30
**Given** REG-PUB-1-11
**When** `GET /registry/v1/registries/{X}` и `GET /registry/v1/registries/{X}/repositories` без
`Authorization`
**Then** оба → `401`, `code` 16 (`UNAUTHENTICATED`), тело побайтово равно ответу на тот же
путь для приватного Y (Р7 kaname: публичность не меняет отказ на методе с полом «1»)
**Близнец:** REG-PUB-1-31 — тот же путь с удостоверением постороннего → `200`. Отличие — один
факт: удостоверение.

#### Сценарий 31: посторонний вошедший читает публичный реестр и не читает приватный

**ID:** REG-PUB-1-31
**Given** REG-PUB-1-11
**When** от постороннего: `GET /registry/v1/registries/{X}`; `GET /registry/v1/registries/{X}/repositories`;
`GET /registry/v1/registries?projectId={{existingProjectId}}`
**Then** `200`, `visibility = "PUBLIC"`; `200`, в странице `app`; `200`, в странице ровно X (Р10)
**And** `PATCH /registry/v1/registries/{X}` от постороннего (маска `description`) → `404`,
`code` 5: правки у класса нет, существование при отказе правки скрыто (`hide_existence`)
**Близнец (отрицательный):** `GET /registry/v1/registries/{Y}` от постороннего → `404`, `code` 5.
Отличие — один факт: выдача на реестр.

### S5. Консоль (kacho `ui-future`)

#### Сценарий 40: включение публичности из карточки реестра

**ID:** REG-PUB-1-40
**Given** П3; реестр X приватный
**When** человек открывает `/projects/{projectId}/registry/registries/{X}`
**Then** в обзоре строка «Видимость» с меткой `Приватный` и переключатель «Публичный доступ»
в положении «выключено»
**And** человек включает переключатель → диалог с текстом
`Любой, кто обратится без входа, сможет скачивать образы всех репозиториев этого реестра, включая созданные позже, и видеть его название, описание и метки. Запись и удаление остаются только у вас.`
и кнопками «Сделать публичным» и «Отмена»
**And** после «Сделать публичным» консоль шлёт ровно один `POST /iam/v1/accessBindings` с
телом «выдача ПЧ» (`scopeId` — проект реестра, цель — X), доводит `Operation` до `done=true` и
перечитывает реестр. Строка «Видимость» доходит до `Публичный`, переключатель включён
**Близнец:** «Отмена» в диалоге — запросов `POST /iam/v1/accessBindings` ноль, метка
`Приватный`. Отличие — одно действие.

#### Сценарий 41: выключение публичности снимает выдачу

**ID:** REG-PUB-1-41
**Given** REG-PUB-1-40
**When** человек выключает переключатель и подтверждает диалог «Сделать приватным»
**Then** консоль шлёт `DELETE /iam/v1/accessBindings/{id}` ровно той выдачи, что делает X
публичным; `Operation` → `done=true`; метка доходит до `Приватный`
**Близнец:** REG-PUB-1-40 — до выключения метка `Публичный`.

#### Сценарий 42: отказ сервера показан текстом сервера

**ID:** REG-PUB-1-42
**Given** П3, но без `raiseAssurance` (сессия уровня «1»)
**When** человек включает переключатель и подтверждает диалог
**Then** у переключателя показан текст отказа сервера дословно (`permission denied`, форма
SC-26 kaname); переключатель возвращается в «выключено»; метка `Приватный`; выдачи нет
**Близнец:** REG-PUB-1-40 — сессия уровня «2» → выдача создана. Отличие — один факт: уровень сессии.

#### Сценарий 43: публичность, данная не переключателем, показывается и не снимается молча

**ID:** REG-PUB-1-43
**Given** П3; через API создана выдача классу `anonymous` роли `registry.public.read` с целью
`[X, Z]` (два реестра проекта), материализована
**When** человек открывает карточку X
**Then** метка `Публичный`, переключатель включён и недоступен для выключения; под ним текст
`Публичность дана выдачей <id>, которая открывает ещё 1 реестр. Снимите её на странице прав.`
со ссылкой на `/iam/access-bindings/<id>`
**Близнец:** REG-PUB-1-41 — выдача с одной целью X, сделанная переключателем: выключение
доступно и снимает её. Отличие — один факт: число целей выдачи.

#### Сценарий 44: репозиторий публичного реестра помечен как публичный через реестр

**ID:** REG-PUB-1-44
**Given** REG-PUB-1-40; у репозитория `X/app` (П3) собственная `visibility = PRIVATE`
**When** человек открывает карточку репозитория `X/app`
**Then** строка «Видимость» показывает `Публичный (через реестр)`
**Близнец:** тот же репозиторий после REG-PUB-1-41 → `Приватный`. Отличие — один факт: видимость реестра.

#### Сценарий 45: одновременное включение — вторая попытка не показывается как сбой

**ID:** REG-PUB-1-45
**Given** П3; карточка X открыта с меткой `Приватный`; затем через API той же учётной записью
создана выдача ПЧ на X и материализована. Карточка об этом не знает: события потока нет (Р6)
**When** человек включает переключатель и подтверждает диалог
**Then** `Operation` выдачи доходит до `done=true` с `error.code = ALREADY_EXISTS` (SC-06 kaname);
консоль показывает у переключателя текст `Реестр уже сделан публичным.`, перечитывает реестр,
метка доходит до `Публичный`, переключатель включён; текста отказа сервера и красной метки
ошибки нет; второй выдачи нет (`GET /iam/v1/accessBindings:listByScope` по проекту — ровно одна
выдача классу `anonymous` с целью X)
**Близнец:** REG-PUB-1-40 — выдачи до включения не было → `done=true` без `error`, текста
`Реестр уже сделан публичным.` нет. Отличие — один факт: существовала ли выдача.

### S6. Значения стенда и сквозной `docker pull` (стенд)

Значения и пины S6 (Р9 п. 3) — производитель этой стадии; проба 50, 51 исполняется последней
(порядок Р9).

#### Сценарий 50: `docker pull` публичного образа без входа

**ID:** REG-PUB-1-50
**Given** П2; REG-PUB-1-11; у клиента нет сохранённых учётных данных к хосту плоскости
данных (чистый `DOCKER_CONFIG` во временном каталоге)
**When** `docker pull <хост плоскости данных>/{X}/app:latest`
**Then** код возврата `0`; `docker image inspect` → дайджест репозитория равен дайджесту push
**Близнец (отрицательный):** REG-PUB-1-51.

#### Сценарий 51: `docker pull` приватного образа без входа и `docker push` анонимом отвергаются

**ID:** REG-PUB-1-51
**Given** П2 без выдачи ПЧ; тот же чистый `DOCKER_CONFIG`
**When** `docker pull <хост>/{X}/app:latest`; затем выдача ПЧ создана и материализована, и
`docker push <хост>/{X}/app:anon-{{runId}}`
**Then** pull — код возврата не `0`, `docker image inspect <хост>/{X}/app:latest` — код
возврата не `0` (образа локально нет). Push — код возврата не `0`, вывод содержит текст
сервера `requested access to the resource is denied`; тега `anon-{{runId}}` в `tags/list` от
выдающего нет
**Близнец:** REG-PUB-1-50 — отличие одно: выдача ПЧ (для pull).

## Сценарий → производитель

«Уже производит» — координата прочитана на ревизии из шапки. «Заказан» — производителя нет, его
заводит полоса стадии или названная задача.

| ID | что производит «Тогда» | координата | чем измерено |
|---|---|---|---|
| 01 | побайтовая сверка с каноном; находка ключа на ребёнке; судья формы и перепись манифестов; производитель структурного отношения; согласие пина и образа | исполнители из пина kaname: `tools/modelcanoncheck`, `tools/modulemanifestcheck` (зовутся `internal/repohygiene/modelcanonpin_test.go:40`, `modulemanifestformpin_test.go`) — уже производят. **Заказаны:** в kaname — правка судьи формы, `kaname#872` (Д9): правило роли над ресурсом, объявленным «без собственной службы», судится по глаголам модели; в kacho (S1) — манифест Р1 п. 1, пин и тег Р1 п. 2–3, `subjectUsersets` Р1 п. 4 | посев: канон — 27 из 27; судья на `422d1bc6f` красный — находка B1 (E0, E1); глаголы модели у `registry_repository` — `v_get`, `v_list` (kaname `internal/authzmap/tables_gen.go:51`); `TestConsumerOwnedStructuralRelationsHaveProducers` PASS после Р1 п. 4; `TestOutsourcedImagePinAgreesWithItsModulePin` PASS при `main-422d1bc6` |
| 02, 03 | создание выдачи, отказ «роль не найдена», отказ пишущей роли | kaname `internal/apps/kaname/api/access_binding/create.go`, ворота класса `system_class_gates.go` @`422d1bc6f` — уже производят; роль в каталоге — доставка манифеста Р1, **заказана** (S1) | прочитано; SC-21, SC-70 (а) kaname |
| 10–14 | `Registry.visibility` в `Get` и `List` | поле `registry.proto` и вывод в обработчике (`services/registry/internal/handler/public.go`, проекция `internal/apps/kacho/api/registry/mapping.go`) — **заказаны** (S2). Ответ о публичном чтении — kaname `relverdict` через `InternalIAMService.Check` — уже производит (#856, #857) | перепись: поля нет; SC-60, SC-68, SC-69, SC-73 kaname |
| 15 | отказ пути маски `visibility` | `validate.go` — строка `visibility` в таблице путей только на выход, проверка до `corevalidate.UpdateMask` — **заказана** (S2); отбрасывание неизвестного ключа тела — REST-край (`DiscardUnknown`) — уже производит | прочитано `validate.go` |
| 16 | `UNAVAILABLE` при отказе вывода | обработчик registry — **заказан** (S2); образец фиксированного текста — `errAuthzUnavailable` в `services/registry/internal/handler/listauthz.go` — уже производит | прочитано |
| 17 | выдача переживает реестр; отзыв проходит | kaname: выдача не каскадится, `Get` и `Delete` привязки — уже производят; удаление реестра и репозитория — `delete.go`, `DeleteRepository`, `DeleteTag` — уже производят | прочитано |
| 18 | отказ в праве выдать | kaname `requireGrantAuthority` (`internal/apps/kaname/api/access_binding/helpers.go:155`) — уже производит; SC-20 kaname | прочитано @`422d1bc6f` |
| 20–24, 26, 27 | `200`, `404 NAME_UNKNOWN`, `403 DENIED`, `405`, фильтр `_catalog` | `services/registry/internal/dataplane/handler.go` (`servePullOnly`, `serveBlob`, `serveCatalog`, `servePush`, `check`, ветвь `DELETE` в `ServeHTTP`) — уже производит; решение о `v_get`, `v_list`, `v_create`, `v_update` класса — kaname — уже производит. Анонимный токен на стенде: ручка kaname — `kaname#495` (PR `kaname#871`); ручка чарта registry и вывод `anonymous-client-id` вложенным чартом kaname стенда — **заказаны** (S3, Р9 п. 2); второй подъём пина и тега и значения профилей — **заказаны** (S6, Р9 п. 3); кейсы набора — **заказаны** (S3) | перепись; integration-половины — 7 проб анонима, PASS (посев) |
| 25 | `401` с вызовом; `invalid_token` | `handler.go` (`authenticate`, `challenge`) — уже производит; `TestDataplane_RG1_B07_AnonPushNoToken_401` | посев |
| 28 | субъект `system_class:anonymous`; выключенный поток | `dataplane/authz.go` (`fgaSubject`), `WithAnonymousSubject` — уже производит; пробы `TestSystemClass_SC39_RegistryAsksAsTheAnonymousClass`, `TestDataplane_RG1_AnonDisabled_TokenResolvesAsOrdinaryPrincipal` — уже есть | посев: PASS |
| 29 | `404` после удаления реестра | `DeleteRepository` (снятие кортежей репозитория), работник удаления реестра (`UnregisterIntentForDelete`), `servePullOnly` → `writeNotFound` — уже производят; стендовые звенья — как у 20–27 | прочитано `delete.go`, `handler.go` |
| 30 | `401` до решения на методе с полом «1» | kacho `gateway/internal/middleware/auth.go` — уже производит; пол «1» у 15 из 15 методов | перепись |
| 31 | чтение постороннего; `404` на правку и на приватный | Check края по каталогу (`v_get` на `registry_registry`), сужение строк `ListRepositories` и `List` (`listauthz.go`, `public.go:85-104`), `hide_existence` у `Update` — уже производят; Р2 kaname — уже производит | прочитано |
| 40–45 | строка «Видимость», переключатель, диалог, отказ текстом сервера, пометка репозитория, повтор включения | `ui-future/registry/src/registerExtensions.tsx` (обзор реестра и репозитория), клиент `ui-future/registry/src/api/iam.ts` — **заказаны** (S5); выбор выдач реестра — `GET /iam/v1/accessBindings:listByScope` kaname — уже производит; `ALREADY_EXISTS` повтора — kaname `access_bindings_active_grant_uniq` — уже производит; консольная проба — **заказана** (S5), фикстуры `fixtures.ts`, `assurance.ts` — уже есть | прочитано |
| 50, 51 | сквозной `docker pull`, `docker push` | ручка kaname — `kaname#495`; чарты — **заказаны** (S3); значения и пины — **заказаны** (S6); шаг сквозного прогона с настоящим клиентом — **заказан** (S6) | перепись |

Сценариев без производителя, чей производитель не заказан стадией или задачей, — 0. Вне kacho
два производителя: ручка kaname `api-server.registry-token.anonymous-client-id` (`kaname#495`;
под ней 20–27, 29 на стенде и 50, 51) и правка судьи формы — `kaname#872` (Д9;
под ней «И» сценария 01).

## Инварианты, которые изменение не вправе тронуть

1. Поштучная публикация репозитория и `defaultRepositoryVisibility` ведут себя как до изменения
   (REG-PUB-1-27).
2. Отказ чтения на плоскости данных не отличает закрытое от несуществующего (REG-PUB-1-21).
3. На API-крае пол «1» не снимается ни у одного метода registry (REG-PUB-1-30).
4. Класс ничего не пишет ни одним путём (REG-PUB-1-24, REG-PUB-1-03).
5. У видимости ровно один источник — выдача. Столбца, флага, кэша вне окна П2 нет (Р2).
6. Раздел `seed` манифеста registry (#914) не меняется (Р1 п. 1).

## DoD

**S1 (манифест, пины, гейты)** — 01, 02, 03:
- манифест: разделы `resources` и `roles` равны фикстуре П6 kaname, раздел `seed` равен стволу.
  Предикат: `diff <(yq '{"resources": .resources, "roles": .roles}' services/registry/manifest.yaml) <(git -C <клон kaname> show 422d1bc6f:internal/manifest/testdata/registry.public-read-fixture.yaml | yq '{"resources": .resources, "roles": .roles}')` — пусто;
  `diff <(yq '.seed' services/registry/manifest.yaml) <(git show a95248464:services/registry/manifest.yaml | yq '.seed')` — пусто; шапка манифеста о разделе `roles` переписана;
- `go.mod`, `go.sum`: пин kaname — ревизия с `kaname#872`, не ниже `422d1bc6f`; тег `main-<sha8>` той же ревизии в 5 профилях
  umbrella и комментарий `values.yaml:124`; `GOWORK=off go build ./...` зелёный; `replace` нет;
- `modelrelationproducer_test.go`: `system_class` в `subjectUsersets`; инъекция — без него
  `TestConsumerOwnedStructuralRelationsHaveProducers` красный с находкой
  `registry_registry#public_reader`, с ним — зелёный;
- Д9 — пин на ревизии kaname с правкой судьи; REG-PUB-1-01 — все команды сценария `ok`, вывод в `DoD-proof`;
  инъекция близнеца (ключ на `repositories`) — красный с находкой дословно;
- REG-PUB-1-02, 03 — newman-кейсы набора registry на стенде П2.

**S2 (видимость в API)** — 10–18:
- `registry.proto`: `Visibility visibility = 13` у `Registry`, комментарий поля несёт
  определение Р2, перечень чтений, которые его заполняют (Р6), и указание «только на выход»;
  `buf lint` и `buf breaking` против `origin/main` — находок 0; `pkg/api` перегенерирован;
- integration (П1, `testcontainers`): REG-PUB-1-16 и его близнец; `Get` и `List` при «да» и «нет»
  дублёра; в `List` на странице из 250 реестров число вопросов о публичном чтении — 3 (⌈250/100⌉);
- проба маски REG-PUB-1-15 — unit на `validate.go`, обе стороны;
- **держатели F1 заменены, а не сняты (Д2).** Предикат по написанию —
  `git grep -n "top-level visibility\|top-level \`visibility" <голова>`: до изменения 12 строк в
  7 файлах (перепись), после — 0 строк, утверждающих отсутствие поля. Проверки «поля нет» в
  `f5_default_visibility_test.go:40` и в кейсе `REG-RD-F1-FIELD-ABSENCE`
  (`registry-redesign.py:289`) переписаны на «у нового реестра `visibility = "PRIVATE"`».
  Утверждения того же кейса о `globalSlug`, `displayName` и инфра-полях не тронуты. Коллекция
  перегенерирована `gen.py`, `pb.go` — `buf generate`. Тексты `registry.proto:55`,
  `registry-redesign.py:15, :282`, две строки `CASES-INDEX.md` из переписи, `types.ts:37` переписаны;
- **тексты, которые изменение делает ложными, переписаны тем же изменением.** Предикат —
  `git grep -n -i "ЕДИНСТВЕННЫЙ рычаг\|Единственный registry-level\|любой путь к PUBLIC\|Единственный рычаг публичности" <голова>`:
  до — 8 строк в 6 файлах, после — 0. Переписываются:
  - `services/registry/docs/content/api/repository.mdx:101` (публичная страница): «Единственный
    рычаг публичности образа» → поле описывает собственную публикацию репозитория, публичность
    реестра (`Registry.visibility`) открывает чтение поверх неё;
  - `ui-future/shared/src/lib/resource-registry.tsx:5194`;
  - `ui-future/shared/src/test/console-ops-match-contract.test.ts:28`;
  - `internal/repohygiene/clienttruth_registry_apisurface.go:17`;
  - `proto/kacho/cloud/registry/v1/registry.proto:54-57` («Единственный registry-level рычаг»,
    «D-6: любой путь к PUBLIC — admin-gated»): у реестра два пути к публичности —
    `defaultRepositoryVisibility` под D-6 и выдача классу под гейтами kaname (Р3);
  - `registry.proto:102-108` (комментарий `enum Visibility`): перечень путей к PUBLIC дополнен
    публичностью реестра;
  - `registry.proto`, комментарий `Repository.visibility` (у `:169-172`) — по Д4;
- newman: 10–15, 17, 18; ≥ 1 happy и ≥ 1 negative на метод (`testing-newman.md#qa-classes-per-method`);
  новая коллекция — с записью ведомости производителя, гейтом набора и назначением шарду
  (`new-suite-four-things`);
- замер цены Р5 на стенде П2: `GET /registry/v1/registries?projectId=…&pageSize=50`, по 100
  вызовов до и после изменения, p50 и p95 в мс, ревизия и стенд — в `DoD-proof`;
- страница API реестра сайта документации (`services/registry/docs/content/api/registry.mdx`):
  поле `visibility`, Р2, Р4, Р6.

**S3 (плоскость данных)** — 20–29:
- чарты (Р9 п. 2): ручка чарта registry с пустым умолчанием; вложенный чарт kaname стенда
  выводит `anonymous-client-id`; отказ рендера umbrella при двух разных заданных значениях.
  Проба рендера: оба пусто — ключей нет; оба заданы одинаково — оба в рендере; разные — `helm
  template` с отказом и текстом, называющим обе ручки;
- REG-PUB-1-28 — integration пакета `dataplane`, обе стороны (пробы уже есть, посев);
- newman 20–27, 29 на стенде П2 — после S6 (значения и пины), порядок Р9;
- `deploy/e2e-shards.json`: набор, ходящий в плоскость данных, — на шарде с компонентом registry
  (`assert-shard-coverage.py` зелёный).

**S4 (API-край)** — 30, 31: newman на стенде П2.

**S5 (консоль)** — 40–45: компонент — jest-пробы `registerExtensions` (метка, переключатель,
диалог, текст отказа, пометка репозитория, исход `ALREADY_EXISTS`); playwright 40–43, 45 на
стенде П3; тексты — дословно из сценариев.

**S6 (значения стенда и сквозной `docker pull`)** — 50, 51:
- второй подъём пина kaname в `go.mod` и тега образа в 5 профилях — до ревизии ствола kaname
  с влитым `kaname#495`; `TestOutsourcedImagePinAgreesWithItsModulePin` зелёный;
- профили стенда kacho задают оба значения Р9 п. 2 одним зарезервированным идентификатором;
  равенство держат отказ рендера (S3) и REG-PUB-1-20;
- шаг сквозного прогона на стенде П2 с настоящим клиентом `docker`, чистый `DOCKER_CONFIG`
  во временном каталоге, снятие образов и каталога в `trap`; вердикт — код возврата шага, не
  текст.

**Все стадии:** `census.sh` до и после прогона стенда → 0; пары RED→GREEN по каждой стадии в
`DoD-proof @<sha>` задачи `kacho#3274`.

## Решения диспетчера (2026-10-17)

Вопросы В1–В8 редакции 1 решены диспетчером 2026-10-17 по рекомендации автора; Д9 — решение
диспетчера по блокирующему B1 круга 1. Открытых вопросов нет. Варианты, которые не выбраны,
названы вместе с ценой: так видно, от чего отказались.

**Д1 (В1). Путь установки PUBLIC — выдача от имени человека, запрос составляет консоль.**
Установка и снятие — глаголы `AccessBindingService` (`POST /iam/v1/accessBindings`,
`DELETE /iam/v1/accessBindings/{id}`) с удостоверением самого вызывающего. API-клиент делает
реестр публичным тем же вызовом. Пишущего метода видимости у registry нет (Р3). Отвергнуты:
метод registry от имени вызывающего — registry стал бы доверенным пересыльщиком личности к
kaname, это новое ребро и новая поверхность; метод registry, создающий выдачу своей учёткой
после проверки D-6, — учётке нужно право выдавать на области каждого арендатора, и гейты
уровня и свежести kaname обходятся (ban18-q-security).

**Д2 (В2). `Registry.visibility` — только на выход; F1 REG-1 пересмотрен частично.**
Пересмотр записан здесь, а не правкой одобренного документа REG-1: правка изменила бы его
отпечаток, и прежний вердикт к нему бы больше не относился.

- **Что пересмотрено.** В F1 «НЕТ … top-level `visibility`» и одна проверка REG-1-02 —
  отсутствие ключа `visibility` в теле `Get`. С этой под-фазы у `Registry` есть
  `visibility = 13`, только на выход, по определению Р2.
- **Что не пересмотрено.** Всё прочее в F1 и REG-1-02 действует: `id` неизменяем и
  единственный адрес, `:rename`, `globalSlug` и `displayName` отсутствуют, инфра-полей в
  публичном ответе нет. Остаётся в силе и довод F1 «у реестра нет своего рычага видимости»:
  поле не пишется ни одним методом registry (REG-PUB-1-15), а источник — выдача в kaname.
- **Держатели и тексты.** Перепись по написанию — 12 строк в 7 файлах; проверки «поля нет»
  заменяются проверкой «у нового реестра `visibility = PRIVATE`», тексты переписываются (DoD
  S2). Проверка не снимается и не ослабляется: она утверждает новое свойство того же
  предмета (`probe-replaced-not-weakened`).

Отвергнуто: поля нет, консоль выводит публичность сама из `ListByScope`. Тогда видимость не
наблюдаема через API registry, и предикат задачи «видимость, которую показывает реестр» не
исполняется.

**Д3 (В3). Выдача только вошедшим — `PRIVATE`.** Поле описывает «без входа» (Р4).
Отвергнуто значение `AUTHENTICATED = 3`: перечисление `Visibility` общее с
`Repository.visibility`, где это значение пришлось бы отвергать.

**Д4 (В4). `Repository.visibility` сохраняет смысл, консоль ставит пометку «через реестр».**
Поле по-прежнему означает собственную публикацию репозитория. Его комментарий дополняется:
публичность реестра открывает чтение поверх неё. Проводного изменения нет. Консоль показывает
`Публичный (через реестр)` (REG-PUB-1-44). Отвергнуто второе поле действующей видимости: два
поля об одном факте и N вопросов о публичности на страницу `ListRepositories`.

**Д5 (В5). Ручку анонимного токена делает `kaname#495`; новой задачи в kaname нет.** Ручка
делается в `kaname#495`, PR `kaname#871`, ветка `495`. Ключ —
`api-server.registry-token.anonymous-client-id`, значение чарта kaname —
`apiServer.registryToken.anonymousClientId` с пустым умолчанием, при старте стоит страж формы
(перепись, @`b1b4543c4`). Раскладка производителей и порядок — Р9: ручка и страж —
`kaname#495`; чарты kacho (ручка registry и вывод `anonymous-client-id` вложенным чартом kaname
стенда) — S3; второй подъём пина и тега и значения профилей — S6.

**Д6 (В6). При удалении реестра выдачу не отзываем** (Р7, REG-PUB-1-17, 29). Отвергнут отзыв из
процесса удаления registry: учётке registry понадобилось бы право отзыва на области арендатора,
то есть та же поверхность, что у отвергнутого варианта Д1.

**Д7 (В7). Порядок относительно `kacho#3251` не важен** (Р8). Какая из двух задач влита второй,
та перебазируется. REG-PUB-1-01 держит равенство канону в обоих порядках.

**Д8 (В8). Ключ `visibility` в теле правки или создания реестра без маски отбрасывается
REST-краем, как любой неизвестный ключ.** Допущение принято. Путь маски `visibility`
отвергается именованным отказом (REG-PUB-1-15). Поля в `UpdateRegistryRequest` и
`CreateRegistryRequest` ради отказа не заводятся.

**Д9 (по B1 круга 1). Правка судьи формы манифеста в kaname — вариант (б).** Решение
диспетчера 2026-10-17, по замеру E0–E3 (раздел «Посев «Дано»: прогон»).

**Что меняется.** Правило роли над ресурсом, который kaname объявляет ресурсом «без собственной
службы» (`catalogResourcesWithoutOwnService`, `internal/authzmap/catalog_resource_spelling.go`),
судья формы (`internal/manifest/roleexport`) судит по глаголам модели этого типа, а не по
действиям каталога. У `registry_repository` глаголы модели — `v_get`, `v_list`, `v_update`,
`v_delete` (`internal/authzmap/tables_gen.go:51`); классы правила роли `registry.public.read` —
`get` и `list`, поэтому они покрыты `v_get` и `v_list`. Ресурс без объявления «без собственной
службы» судится, как сегодня.

**Производитель:** `kaname#872`, полоса размера S; заводит `git-operator`.
Контракт kacho не меняется, в дереве kacho записей каталога не заводится.

**Предикат:** REG-PUB-1-01 «И» на пине kaname с этой правкой — в выводе судьи у
`services/registry/manifest.yaml` строка `правила ролей: … находок 0`;
`TestModuleManifestFormIsJudgedByTheOneExecutor` и `TestManifestFormCensusFollowsTheTree` —
`ok`. Близнец: то же правило роли с классом, которого у типа нет среди глаголов модели, —
находка остаётся.

**Порядок:** S1 ждёт пин kaname с этой правкой (Р1 п. 2, порядок Р9).

**Поверхность (ban18-q-security):** доступ не меняется. Правится проверка формы манифеста при
сборке, а не решение о доступе. Право роли по-прежнему материализуется в `v_get`/`v_list` на
`registry_repository`.

## Редакция 4: что закрыто

| замечание круга 1 | где закрыто |
|---|---|
| B1 CONSTRUCTIBILITY — «И» сценария 01, производитель гейта формы | Д9 (вариант (б): правка судьи формы в kaname, решение диспетчера по замеру E0–E3); Р1 п. 4 — производитель второго гейта, найденного посевом (`TestConsumerOwnedStructuralRelationsHaveProducers`); сценарий 01 — полный перечень гейтов |
| B2 DoD — сравнение с фикстурой, раздел `seed` | Р1 п. 1, инвариант 6, DoD S1 п. 1 (сравнение разделов `resources` и `roles`, `seed` — со стволом); строка переписи о разнице исправлена (9 строк `seed`) |
| B3 PRODUCER — чарт вложенного kaname, тег образа, второй подъём | Р1 п. 3 (тег вместе с пином в S1); Р9 п. 2 (вложенный чарт, `configmap.yaml:105`, путь `kaname.config.apiServer.registryToken.*`), п. 3 (второй подъём до kaname с #495), порядок S3 → S6 → S3 → S6; таблица производителей 20–27, 29, 50, 51; DoD S1, S3, S6 |
| B4 CONSTRUCTIBILITY — сценарий 17 | анонимная половина — новый сценарий 29 в стендовой части S3 с названным производителем; 17 — только выдача и её отзыв; фраза о независимости в Р9 исправлена (S2 от звеньев не зависит, потому что анонимного шага в S2 нет) |
| B5 DoD — предикат переписи и ложные тексты | перепись: исправленный предикат — 12 строк в 7 файлах, включая `registry.proto:55`; второй предикат — 8 строк в 6 файлах; DoD S2 — оба предиката «до/после» и перечень правок, включая `repository.mdx:101`, `resource-registry.tsx:5194`, `console-ops-match-contract.test.ts:28`, `clienttruth_registry_apisurface.go:17`, `registry.proto:54-57` и `:102-108` |
| отпечатки соседей | таблица опоры, колонка «отпечаток» |
| П3 не сеет `X/app` | П3 — `CreateRepository` |
| П2 — кто вызывает `RoleService.Create`; `sva-edit` | П2 — принципалы `prodseed_matrix.py`; роли создаёт выдающий (`jwtAccountAdminA`); редактор используется в сценарии 18 |
| П1 — id | П1 — X, Y названы метками, id из ответа |
| одновременное включение | сценарий 45 |
| сценарий 21 — два «Дано» | одно: П2 без выдачи ПЧ |
| сценарий 17 — производитель `404` | сценарий 29, производитель назван |
