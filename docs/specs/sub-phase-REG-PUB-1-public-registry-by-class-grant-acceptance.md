# Sub-phase REG-PUB-1 (публичное чтение реестра выдачей роли классу) — Acceptance

> **Статус:** DRAFT
> **Статическая форма:** DRAFT; действующий вердикт выводится из внешнего события и записи ревью,
> привязанной к SHA-256 редакции (`change-graph` §3), а не из этой строки
> **История review:** (только дописывается строкой «дата · круг · вердикт · SHA-256 редакции · путь записи»)
> - 2026-10-17 · круг 1 · CHANGES_REQUESTED · `b15e196748961e988ec91545d1e07e7be30c01f8ca92d0dd76026a8cc12b0236` ·
>   `docs/specs/reviews/sub-phase-REG-PUB-1-public-registry-by-class-grant-acceptance/b15e196748961e988ec91545d1e07e7be30c01f8ca92d0dd76026a8cc12b0236.yaml`
> - 2026-10-17 · круг 2 · APPROVED · `6c7f6f9a40faba5c9822cc94dbf861b4a34d64bae8f36909c196db5f79279f4c` ·
>   `docs/specs/reviews/sub-phase-REG-PUB-1-public-registry-by-class-grant-acceptance/6c7f6f9a40faba5c9822cc94dbf861b4a34d64bae8f36909c196db5f79279f4c.yaml`
>   (строка дописана в редакции 6: запись существовала, строки в истории не было)
> - 2026-10-17 · проверка исполнения правки строки 246 · APPROVED · `649e13bcfe570104b65b897dca81ebe1824e54686eab200f315c783fea82c14a` ·
>   `docs/specs/reviews/sub-phase-REG-PUB-1-public-registry-by-class-grant-acceptance/649e13bcfe570104b65b897dca81ebe1824e54686eab200f315c783fea82c14a.yaml`
>   (строка дописана в редакции 6)
> - 2026-10-17 · правка ПОСЛЕ вердикта `649e13bc…` · редакция 6: роль `registry.public.read` —
>   в форму вложенного правила (`children`) по приёмкам kaname ред. 12 и `kaname#874` ред. 2.
>   Вердикт `649e13bc…` относится к редакции 5 и на эту редакцию не переносится. Что
>   изменено — раздел «Редакция 6: что изменено»
> - 2026-10-17 · редакция 7 (до ревью редакции 6, решение диспетчера (а)): в таблицу
>   «Сценарий → производитель» (строки 01, 10–14, 20–24) дописан производитель `kaname#874`
>   (PR `kaname#879`); фраза «Вне kacho два производителя» — теперь три
> - 2026-10-17 · круг ревью редакции 7 · CHANGES_REQUESTED (B1–B3) · `37d6429abb1f1ab0273f9906e2a776c37af5b2da8d1d21de8606a3a0cc9378de` ·
>   запись — путь даёт рецензент
> - 2026-10-17 · правка ПОСЛЕ вердикта `37d6429a…` · редакция 8: B1 — предусловия П0, П2,
>   «Дано» 01, порядок выкатки и посев переведены на пин с `kaname#874`, посев перемерен
>   (kaname `5f6f29902`); B2 — `rol-reg-get` = `[get, list]` над `registry.registries` без
>   вложенного правила; B3 — «Тогда» сценария 03 конкретным телом роли с краем и отрицанием;
>   важное — команда публикации образа, `yq -o=json -I=0`, строка вывода судьи по факту.
>   Вердикт `37d6429a…` относится к редакции 7 и на эту редакцию не переносится. Что
>   изменено — раздел «Редакция 8: что изменено»
> - 2026-10-17 · проверка исполнения редакции 8 · B1, B2 закрыты; открыт B4 (FORMAT, «Тогда» 03) ·
>   `4646c2364105a338773bb29e7a4a7dc9c1dddc81ae1212529cc84621d4a0d4d8`
> - 2026-10-17 · правка ПОСЛЕ проверки `4646c236…` · редакция 9: B4 — «Тогда» 03 поштучно по
>   полям `children[0]` (публичный край отдаёт пустые ключи); оговорка «пока `kaname#879` не
>   влит» в «Дано» 01; пометка ревизии `5f6f29902` в DoD S1. Вердикт о редакции 8 на эту
>   редакцию не переносится
> - 2026-10-17 · проверка исполнения редакции 9 · APPROVED · `0482a061c4f2497d00b1193769cf0671636b6124a172a3875d268a16f48dbccb` ·
>   `docs/specs/reviews/sub-phase-REG-PUB-1-public-registry-by-class-grant-acceptance/0482a061c4f2497d00b1193769cf0671636b6124a172a3875d268a16f48dbccb.yaml`
>   (строка дописана в редакции 10: запись существовала, строки в истории не было)
> - 2026-10-18 · правка ПОСЛЕ вердикта `0482a061…` · редакция 10: объём сужен решением владельца
>   2026-10-18 — признака «публичный» у реестра нет, доступ задаёт только выдача роли. Сняты
>   `Registry.visibility`, его вывод и консоль (Р2, Р4–Р6, Д1–Д4, Д8 прежних редакций,
>   сценарии 15, 16, 40–45); стадии перенумерованы; S1 — это `kacho#3251` (PR `kacho#3279`).
>   Вердикт `0482a061…` относится к редакции 9 и на эту редакцию не переносится. Что
>   изменено — раздел «Редакция 10: что изменено»
> **Дата:** 2026-10-18 · **редакция:** 10. Прежние редакции, их разделы «что закрыто» и
> решения Д1–Д9 — в истории git этого файла; отпечатки — в строках истории выше
> **Задача:** `PRO-Robotech/kacho#3274` (родитель `#3172`, ветка эпика `3172-identity-own-2`)
> **Механизм (не переоткрывается):** kaname `#856`, `#857`, `#872` (влиты), `#874` — вложенное
> правило роли (PR `kaname#879`, влит, слияние `efac3adf7`), `#495` — ручка анонимного токена
> реестра (PR `kaname#871`, влит, слияние `0b6b21cc9`)
> **Ревизии замера:** kacho `5e4facc5f` (голова `origin/3172-identity-own-2`), kacho `636bd5435`
> (голова PR `kacho#3279`, ветка `3251-registry-public-read`), kacho `81b719b11` (локальная ветка
> `3274` с RED-пробами прежнего объёма); kaname `db8bcb7e8` (`origin/main`)

## Решение владельца, которым сужен объём

Решение владельца 2026-10-18, дословно (комментарий в `kacho#3274`):

> для нашего продукта на данный момент не нужен класс паблик, все характеризуется ролевкой,
> какую поставишь такой вид и будет

Следствие (решение диспетчера, там же): признака «публичный» у реестра нет — ни поля
`visibility: PUBLIC`, ни его вычисления вопросом к kaname, ни показа в консоли. Чтение реестра
и его репозиториев без входа даёт только выдача роли `registry.public.read` (форма `children`)
классу субъектов с целью «реестр X».

## Обзор

Реестр X становится читаемым без входа одной выдачей роли `registry.public.read` (id
`rolb1325b011aa17211d`) классу `system_class:anonymous` с целью X. После неё аноним тянет образы
X и всех его репозиториев, включая созданные позже, и видит их в каталоге плоскости данных;
вошедший без прав в аккаунте читает X и через API-край. Выдача тому же классу
`authenticated` открывает то же только вошедшим. Отзыв выдачи снимает чтение со всех
репозиториев разом. Соседний реестр Y без выдачи не отличается от несуществующего.

Под-фаза доставляет роль в каталог (манифест registry, пин и образ kaname — S1), подключает
анонимный токен плоскости данных на стенде (чарты, значения, второй подъём пина — S3, S4) и
закрепляет поведение пробами края, плоскости данных и настоящим клиентом `docker`. Своего
поля, столбца, метода или флага публичности у registry нет: что выдано, то и видно.

## Что НЕ входит

1. **Признак публичности реестра** — поле `Registry.visibility`, его вычисление вопросом к
   kaname на `Get`/`List`, его отказ `UNAVAILABLE`, отказ пути маски `visibility`, событие
   потока о нём. Сняты решением владельца 2026-10-18. Контракт `registry.proto` не меняется
   (кроме комментариев, DoD S2); утверждение F1 приёмки REG-1 «у `Registry` нет верхнеуровневого
   `visibility`» остаётся верным и не пересматривается.
2. **Консоль.** Отдельного элемента публичности у реестра нет — ни метки, ни переключателя,
   ни пометки «через реестр» у репозитория. Выдачу заводят общей формой прав: она уже знает
   субъект `system_class` и цель-ресурс (`ui-future/iam/src/components/organisms/iam/AccessBindingCreateForm/AccessBindingCreateForm.tsx`,
   `SUBJECT_TYPES`, арм `resources`; `kacho#3238`). Новых проб консоли эта под-фаза не заводит.
3. **Механизм kaname.** Наследование `public_reader`, ворота выдачи классу, вложенное правило
   роли, ручка анонимного токена (Р9, Р10, SC-39, SC-60…73 приёмки kaname; Р5 приёмки
   `kaname#874`) только используются.
4. **Чтение реестра анонимом через API-край** (`/registry/v1/...`): у всех 15 методов
   `RegistryService` пол `required_acr_min = "1"`. Открыть control-plane анониму — смена
   контракта полосы, отдельная приёмка. Здесь закреплён только сегодняшний отказ (REG-PUB-1-30).
5. **Проза `user:*` в примечаниях манифеста registry.** Четыре строки (`manifest.yaml`, блок
   `notes` ресурса `repositories`) переносятся в канон kaname побайтово; их правка — парой
   «канон kaname + манифест kacho», остаток `kacho#3251` (его `DoD-proof`
   https://github.com/PRO-Robotech/kacho/issues/3251#issuecomment-6218949303).
6. **Снятие приёма прежней редакции в kaname** — `kaname#858`.
7. **Отзыв выдачи при удалении реестра** — каскада через границу службы нет (ban #4), Р7.
8. **Поштучная публикация репозитория** (`Repository.visibility`, RG-1 D-7) и
   `defaultRepositoryVisibility` не меняются (инвариант 1, REG-PUB-1-27).

## Опора: одобренные соседи

| сосед | отпечаток (`sha256sum` на ревизии этой редакции) | что закреплено | как эта под-фаза с ним стыкуется |
|---|---|---|---|
| kaname `docs/engineering/acceptance/anonymous-and-authenticated-are-subject-classes.md` @`db8bcb7e8` (`origin/main`), ред. 13 | `dfbe47bfe7b2bb1f047d6462df60019e3b32401f6f93d589cf66b698f6cdb97c` (APPROVED, событие в `kaname#495`) | Р9: выдача классу на `registry_registry:<id>` даёт `v_get`, `v_list` на реестр и наследуемое чтение репозиториев; Р9 п. 4: роль `registry.public.read` — `[get, list]` над `registry.registries` с вложенным правилом `[get, list]` над `registry.repositories`; SC-73: без вложенного правила потомки классу не открываются; Р2: говорящий с личностью несёт класс `anonymous`; Р10: сначала kaname, затем kacho; SC-39 (ред. 13): анонимный поток токена включается ручкой `api-server.registry-token.anonymous-client-id`, умолчание пусто, форма значения закрыта (`^[a-z][a-z0-9]*(-[a-z0-9]+)+$`, ≤ 63 знаков, не форма порождаемого id) | S1 доставляет роль Р9 п. 4; S3–S4 включают поток SC-39 значением закрытой формы (Р9 п. 3). Опора сменилась с ред. 12 (`bd6325e3…`): изменён только SC-39 (диф `5f6f29902..origin/main` — строки SC-39, таблица производителей, DoD S1, S3); Р9, SC-60…73 не тронуты — перепроверено (fa-b7) |
| kaname `docs/engineering/acceptance/nested-rule-reaches-descendants-of-a-named-container.md` @`db8bcb7e8`, ред. 2 | `f12395ae242f85e1120346123286318b3027d87e53f6973f4b8a21ac1bd6d9f6` (APPROVED, событие `kaname#874`) | Р5: классу вложенное правило даёт потомков только через `public_reader` при трёх условиях; ND-03: аноним с `registry.public.read` на X читает X и его репозитории; ND-07 (б): роль прежней формы даёт классу только реестр | REG-PUB-1-20 держится ND-03, REG-PUB-1-13 — ND-07 (б) и SC-73 |
| `docs/specs/sub-phase-REG-1-registry-repository-acceptance.md` (APPROVED 2026-07-20) | `6847687bbd99ee62a158bb09cafcbd0ac911b344b49cdedb8fc218d8c8c8dc11` | F1, REG-1-02: у `Registry` нет верхнеуровневого `visibility` | **не пересматривается** (в редакциях 2–9 пересматривался частично, Д2 снято) |
| `docs/specs/sub-phase-RG-1-registry-repository-overlay-acceptance.md` (APPROVED, ред. 2) | `429461ed56738dc22d71829fce7a99279dbfd04cdc3b6ca03a6a43a87a49423a` | D-6: путь, которым принципал САМ приводит репозиторий к PUBLIC, требует `admin` на реестре; D-7: поштучная публикация | D-6 и D-7 не меняются. Чтение без входа через выдачу роли — путь, гейт которого — право выдать в kaname (Р3), а не D-6. Тексты дерева «единственный рычаг публичности» и «любой путь к PUBLIC — admin-gated» с доставкой роли становятся ложными и переписываются (DoD S2) |

## Перепись производителей (до сценариев)

Команды выполнены на ревизиях из шапки; вывод — дословно или числом.

| что уже есть или чего нет | координата | чем измерено |
|---|---|---|
| в стволе эпика роль не доставлена: раздела `roles` и ключа `publicReadToChildren` в манифесте registry нет; строка `subjects` уже на `system_class` (`kacho#3251`, первая часть, влита) | `services/registry/manifest.yaml` @`5e4facc5f` | `git show 5e4facc5f:services/registry/manifest.yaml \| grep -v '^ *#' \| grep -c -E '^roles:\|publicReadToChildren'` → `0`; строка `- {name: get, subjects: [system_class, user, service_account, 'group#member'], from: [owner, super_admin]}` — есть |
| PR `kacho#3279` (OPEN, ветка `3251-registry-public-read`, голова `636bd5435`, база — ветка эпика) несёт S1 целиком: манифест Р1 п. 1, пин kaname на слияние `kaname#879`, тег образа, `system_class` в `subjectUsersets`, гейт края подстановочных отношений, тип `Rule.children` консоли | 13 файлов: `git diff --stat origin/3172-identity-own-2...636bd5435` | `yq '.roles\|length'` → `1`; `yq -o=json -I=0 '.roles[0]'` → `{"id":"registry.public.read",…,"tier":{"tierType":"iam.cluster","tierId":"cluster_root"},"rules":[{"module":"registry","resources":["registries"],"classes":["get","list"],"children":[{"resources":["repositories"],"classes":["get","list"]}]}]}`; `publicReadToChildren` у `registries` → `true`; `diff` раздела `seed` со стволом эпика — пусто; `go.mod:120` → `github.com/PRO-Robotech/kaname v0.4.1-0.20261017225750-efac3adf7891`; `deploy/helm/umbrella/values.yaml:128` → `tag: main-efac3adf`; `docker manifest inspect docker.io/prorobotech/kaname:main-efac3adf` → код `0` |
| гейты S1 зелёные на голове PR `kacho#3279` | временная копия kacho @`636bd5435` | `GOWORK=off go test ./internal/repohygiene/ -run '<7 проб сценария 01>' -count=1 -v` → код `0`, 7 из 7 PASS; `блоков сверено 27 из 27 · байт сверено 80556`; `перепись: осмотрено путей 7142 · манифестов прочитано 5 · находок 0 (манифестов в индексе 5)`; `GOWORK=off go test ./deploy/ -run 'TestOutsourcedImagePinAgreesWithItsModulePin$' -count=1` → `ok` |
| слияние `kaname#879` (`efac3adf7`) лежит на стволе kaname; слияние `kaname#871` (`0b6b21cc9`, ручка анонимного токена) — позже и в пин PR `kacho#3279` НЕ входит | клон kaname | `git merge-base --is-ancestor efac3adf7891 origin/main` → `0`; `git merge-base --is-ancestor 0b6b21cc9 efac3adf7891` → `1`; `git merge-base --is-ancestor efac3adf7891 0b6b21cc9` → `0`; образы `main-0b6b21cc`, `main-db8bcb7e` — `docker manifest inspect` код `0` |
| ручка kaname есть на стволе kaname: ключ, умолчание пусто, значение чарта | kaname `internal/apps/kaname/config/defaults.go:70`, `cmd/kaname/serve.go:2410`, `deploy/values.yaml:276` (`anonymousClientId: ""`) | `git grep -n -i 'anonymous-client-id\|AnonymousClientID' origin/main -- internal cmd deploy/values.yaml` @`db8bcb7e8` |
| в kacho ни один чарт и ни один профиль не задаёт ни ручку registry `KACHO_REGISTRY_ANONYMOUS_SUBJECT_ID`, ни `anonymous-client-id` вложенного kaname; вложенный чарт kaname рендерит `registry-token` только с `issuer` и `service` | `deploy/helm/umbrella/charts/kaname/templates/configmap.yaml:95-112`; `services/registry/internal/apps/kacho/config/config.go:429` (ручка процесса, умолчание пусто) | `git grep -c -i 'anonymousSubjectId\|ANONYMOUS_SUBJECT_ID\|anonymousClientId\|anonymous-client-id' <рев> -- deploy services/registry/deploy` на `5e4facc5f`, `636bd5435`, `81b719b11` → нет попаданий |
| канон kaname: `public_reader: [system_class]` у реестра; `v_get`, `v_list` реестра принимают `system_class` напрямую; у репозитория `v_get` — `[system_class, …] … or public_reader from parent`, `v_list` — `[user, service_account, group#member] … or public_reader from parent` (поштучная публикация даёт только `v_get`) | kaname `proto/kaname/cloud/iam/v1/fga_model.fga:1315`, `:1357`, `:1358` | прочитано @`db8bcb7e8` |
| id роли `rolb1325b011aa17211d` — тот же в kaname и в пробах ветки `3274` | kaname `internal/apps/kaname/api/access_binding/nested_rule_world_integration_test.go`; kacho `services/registry/tests/newman/cases/registry-public-by-class.py` @`81b719b11` | `git grep -l rolb1325b011aa17211d` |
| у всех методов `RegistryService` пол «1» | `proto/kacho/cloud/registry/v1/registry_service.proto` | `git grep -c 'required_acr_min) = "1"' 5e4facc5f -- …` → `15`; `git grep -c '  rpc ' …` → `15` |
| плоскость данных: без Bearer — `401` с `WWW-Authenticate`; отказ чтения — `404 NAME_UNKNOWN`; отказ записи — `403 DENIED`; `_catalog` фильтрует имена вопросом `v_list`; анонимный `sub` переводится в `system_class:anonymous`, только если задана ручка | `services/registry/internal/dataplane/handler.go` (`servePullOnly`, `servePush`, `serveCatalog`, `challenge`, `writeNotFound`, `writeDenied`); `dataplane/authz.go` (`fgaSubject`) | прочитано @`5e4facc5f` |
| пробы анонима плоскости данных уже есть | `dataplane/system_class_anon_subject_test.go` (`TestSystemClass_SC39_RegistryAsksAsTheAnonymousClass`), `dataplane/handler_anon_test.go` (`TestDataplane_RG1_B03_AnonPullPublic_200`, `TestDataplane_RG1_AnonDisabled_TokenResolvesAsOrdinaryPrincipal` и др.) | `git grep -n 'func Test…' 5e4facc5f -- services/registry` |
| кэш положительных вердиктов registry — 2 с | `config.go:154` `KACHO_REGISTRY_AUTHZ_CACHE_TTL` | прочитано |
| принципалы сквозных наборов | `tests/authz-fixtures/prodseed_matrix.py`: `jwtAccountAdminA`, `jwtProjectEditorA`, `jwtStranger` | прочитано @`5e4facc5f`, строки 918–929 |
| сквозной набор registry достаёт до плоскости данных | `services/registry/tests/newman/cases/registry-docker-facade-lane.py`; `deploy/e2e-shards.json` (`registryDataPlaneBaseUrl`) | `git grep -c registryDataPlaneBaseUrl 5e4facc5f -- deploy/e2e-shards.json` → `1` |
| ветка `3274` (локальная, на origin нет) несёт RED-пробы прежнего объёма: newman `registry-public-by-class.py` (кейсы 10–18, 30, 31, 45 с утверждениями о `visibility`), unit маски `regpub1_visibility_mask_test.go` (15), integration `registry_visibility_regpub1_integration_test.go`, playwright `registry-public-visibility.spec.ts` и jest `RegistryPage.public-visibility.test.tsx` (40–45), проба `regpub1_anonymous_subject_test.go` (28) | `git diff --stat origin/3172-identity-own-2...3274` → 9 файлов, `+7238` | `git ls-remote origin 'refs/heads/*3274*'` → пусто; `grep -o 'REG-PUB-1-[0-9]*'` по кейсам → 10, 11, 12, 13, 14, 15, 16, 17, 18, 30, 31, 45 |
| тексты, которые доставка роли делает ложными («единственный рычаг публичности», «любой путь к PUBLIC — admin-gated») | 8 строк в 6 файлах, из них 1 порождённый | `git grep -n -i "ЕДИНСТВЕННЫЙ рычаг\|Единственный registry-level\|любой путь к PUBLIC\|Единственный рычаг публичности" 636bd5435` → `internal/repohygiene/clienttruth_registry_apisurface.go:17`; `pkg/api/kacho/cloud/registry/v1/registry.pb.go:329, :331` (порождён); `proto/kacho/cloud/registry/v1/registry.proto:54, :56`; `services/registry/docs/content/api/repository.mdx:101`; `ui-future/shared/src/lib/resource-registry.tsx:5194`; `ui-future/shared/src/test/console-ops-match-contract.test.ts:28`. Третий текст того же рода — комментарий `enum Visibility`, `registry.proto:102-108` — прочитан |
| консоль: форма выдачи знает класс и цель-ресурс | `AccessBindingCreateForm.tsx:115`, `:124` (`SubjectType` с `system_class`), `:735` (арм `resources`) | прочитано @`5e4facc5f` |
| повтор активной выдачи — `ALREADY_EXISTS`; право выдать — `requireGrantAuthority` | kaname `access_bindings_active_grant_uniq`; `internal/apps/kaname/api/access_binding/helpers.go` | прочитано (SC-06, SC-20 kaname) |

## Решения

Номера решений прежних редакций сохранены для трассировки; снятые (Р4–Р6, Р8, Д1–Д9) не
переиспользуются.

**Р1. S1 — это `kacho#3251`, PR `kacho#3279`.** Тем же изменением, что уже собрано в PR:

1. `services/registry/manifest.yaml`: `publicReadToChildren: true` на ресурсе `registries` и раздел
   `roles` с ОДНОЙ ролью `registry.public.read` (id `rolb1325b011aa17211d`, ярус
   `{tierType: iam.cluster, tierId: cluster_root}`):

   ```yaml
   rules:
     - module: registry
       resources: [registries]
       classes: [get, list]
       children:
         - resources: [repositories]
           classes: [get, list]
   ```

   Вложенное правило выполняет три условия Р5 приёмки `kaname#874`, поэтому выдача классу
   пишет `public_reader` на названном реестре. Раздел `seed` не тронут. Шапка манифеста
   «живых системных ролей у модуля НОЛЬ» переписывается (doc-truthfulness);
2. пин kaname — не ниже слияния `kaname#879` (`efac3adf7`), тег образа `main-<sha8>` той же
   ревизии в 5 профилях umbrella; каталог прав края и таблица маршрутов сверены на этом пине;
3. `internal/repohygiene/modelrelationproducer_test.go`: `system_class` в `subjectUsersets` —
   отношение из одних вершин субъекта есть выдача, её пишет kaname;
4. гейт края подстановочных отношений отличает подстановку от явной выдачи классу.

Порядок выкатки — Р10 kaname: kaname образом ревизии пина на стенде раньше kacho с этим
манифестом.

**Р2. Публичность — только выдача роли; у registry её представления нет.** Чтение реестра X
без входа есть ровно тогда, когда у класса `anonymous` есть выдача роли с вложенным правилом
над репозиториями и целью X. У registry нет ни поля, ни столбца, ни метода, ни вычисления
этого признака. Узнать, открыт ли реестр, можно перечнем выдач (`GET
/iam/v1/accessBindings:listByScope`) или чтением от имени класса. Любая роль, удовлетворяющая
воротам выдачи классу (только `get` и `list`, SC-21 kaname), даёт ровно то, что в ней написано:
роль без вложенного правила открывает классу метаданные реестра, но не его репозитории
(REG-PUB-1-13).

**Р3. Кто вправе открыть реестр — тот, кто вправе выдать.** Гейты выдачи принадлежат kaname и
не меняются: право выдать (владелец аккаунта либо `admin` на области, SC-20), уровень сессии
«2» (SC-26), свежесть для выдачи классу (SC-25, SC-66); сервисная учётка с правом выдаёт без
уровня и окна (SC-27). `admin` только на объекте реестра без права выдать на области реестр не
открывает: ворота выдачи строже ворот D-6 RG-1 (REG-PUB-1-18).

**Р7. Удаление реестра выдачу не отзывает.** Каскада через границу службы нет (ban #4). id
реестра неизменяем и повторно не выдаётся (ban #15), поэтому выдача на удалённый
`registry_registry:<id>` ничего не открывает; снять её можно глаголом отзыва (REG-PUB-1-17, 29).

**Р9. Анонимный токен плоскости данных на стенде: звенья и порядок.**

1. kaname: ручка `api-server.registry-token.anonymous-client-id` — `kaname#495`, влита
   (`0b6b21cc9`), страж формы при старте, умолчание пусто;
2. **S3, чарты kacho:**
   - чарт registry выводит `KACHO_REGISTRY_ANONYMOUS_SUBJECT_ID` из значения
     `anonymousSubjectId` (умолчание пусто);
   - вложенный чарт kaname стенда (`deploy/helm/umbrella/charts/kaname/templates/configmap.yaml`,
     блок `registry-token:`) выводит `anonymous-client-id` из
     `kaname.config.apiServer.registryToken.anonymousClientId` (умолчание пусто);
   - рендер umbrella отказывает, если оба значения заданы и различаются, — по образцу
     `kaname.laneServiceAud` (`charts/kaname/templates/_helpers.tpl`);
3. **S4, значения и пин:**
   - пин kaname в `go.mod` и тег образа в 5 профилях поднимаются ВТОРОЙ раз — до ревизии ствола
     kaname, в которую влит `kaname#871` (не ниже `0b6b21cc9`; она — потомок `efac3adf7`, так
     что Р1 п. 2 сохраняется), вместе, по Р1 п. 2;
   - профили стенда задают оба значения звена 2 одним идентификатором закрытой формы SC-39
     (`^[a-z][a-z0-9]*(-[a-z0-9]+)+$`, ≤ 63 знаков, не форма порождаемого id), которого нет ни
     у одного принципала. Производитель — S4 этой задачи;
4. **S4, проба:** сквозная проба настоящим клиентом `docker`.

**Порядок исполнения:** S1 (влить PR `kacho#3279`) → S3 (чарты) → S4 (значения и пин) → S2
и S3 (newman на стенде) → S4 (`docker`, 50, 51). Unit/integration S3 (28) и тексты S2 от звеньев
не зависят. Расширение поверхности (ban18-q-security) названо: включённые ручки дают любому
без учётки токен только чтения, и он читает только то, что выдано классу `anonymous`. Без
такой выдачи всё отвечает `404` (REG-PUB-1-21).

**Р10. Вошедший без прав в аккаунте читает открытый реестр и через API-край.** Говорящий с
личностью несёт класс `anonymous` (Р2 kaname), поэтому `GET /registry/v1/registries/{id}` и
`…/repositories` проходят и Check края (`v_get` на реестр), и сужение строк (`v_list`). Ему
видны метаданные реестра: `projectId`, `name`, `description`, `labels`, `regionId`, `endpoint`,
`repositoryCount`. `ListRegistries` с `projectId` чужого проекта показывает ему открытые
реестры этого проекта. Это следствие выдачи анониму, и оно названо здесь (ban18-q-security).

**Соответствие рынку (ban18-q-market-recognition).** Реестр образов, который тянется без
учётки, — общепринятое свойство реестров. Наше отличие: открытость — не флаг реестра, а обычная
выдача роли классу; она заводится, отзывается и пишется в журнал аудита теми же глаголами, что
любая выдача, и видна в перечне прав. Что выдано, то и видно — второго источника правды нет.

## Как строится «Дано»

Все «Дано» строит посев. Ручной правки базы нет.

- **П0 — дерево kacho для S1:** голова PR `kacho#3279` (на ревизии замера `636bd5435`) либо
  ревизия её вливания в ветку эпика. Судья формы собирается из модуля kaname по пину, как его
  зовёт `TestModuleManifestFormIsJudgedByTheOneExecutor`.
- **П1 — integration registry:** плоскость данных собирается `dataplane.New` с поддельным
  проверяющим токена и дублёром решения о доступе (порт `internal/check`), как в пробах пакета
  `dataplane`; X — метка, id из ответа.
- **П2 — стенд** (своё пространство имён `make -C deploy stand-ns-up NS=t3274-<коротко>`,
  сквозной набор registry). Выкачены kaname образом ревизии пина и kacho с этим изменением; для
  сценариев плоскости данных (13, 14, 20–27, 29, 50, 51) — пин и значения S4. Посев набора
  (имена с `{{runId}}`):
  - принципалы `tests/authz-fixtures/prodseed_matrix.py`: **выдающий** `jwtAccountAdminA`
    (право выдать на проекте A1; токен сервисной учётки, SC-27); **редактор**
    `jwtProjectEditorA` (editor на A1, без права выдать); **посторонний** `jwtStranger`
    (вошедший без выдач в аккаунте A);
  - реестры X и Y в проекте A1 через `POST /registry/v1/registries`, `Operation` — `done=true`
    без `error`;
  - репозитории `X/app` и `Y/app`, запушенные через плоскость данных до любой выдачи
    удостоверением вида SECRET выдающего (`SAKeyService.Issue`); репозиторий `Y/pub`,
    созданный `CreateRepository` с `visibility=PUBLIC` (поштучная публикация, D-7);
  - роли `rol-reg-get` (`"rules":[{"module":"registry","resources":["registries"],"verbs":["get","list"]}]`,
    без вложенного правила) и `rol-reg-edit` (`[get, list, update]` над `registry.registries`) —
    `RoleService.Create` в аккаунте A от имени выдающего;
  - **выдача ПЧ** — тело
    `{"subjects":[{"type":"SUBJECT_TYPE_SYSTEM_CLASS","id":"anonymous"}],"roleId":"rolb1325b011aa17211d","scopeType":"iam.project","scopeId":"{{existingProjectId}}","target":{"resources":{"resources":[{"type":"registry.registries","id":"{{registryX}}"}]}}}`,
    отправитель — выдающий;
  - **анонимный токен** — `GET <realm>?service=<service>&scope=repository:<X>/app:pull` без
    `Authorization`; `realm` и `service` берутся из `WWW-Authenticate` первого ответа `401`
    плоскости данных.

  «Материализовано» — опрос раз в 200 мс с пределом 30 с (окно SC-13 kaname) плюс окно
  `KACHO_REGISTRY_AUTHZ_CACHE_TTL` дошёл до ожидаемого ответа. Уборка заводится до создания:
  выдачи, реестры, роли снимаются тем же прогоном и на падении.

## Посев «Дано»: прогон

Редакция 10 прогнала П0: временная копия kacho на голове PR `kacho#3279` `636bd5435`, после
прогона снята.

| «Дано» | команда | исход |
|---|---|---|
| П0: сценарий 01 | `GOWORK=off go test ./internal/repohygiene/ -run 'TestModelCanonAgreesWithPlatformManifests\|TestModuleManifestFormIsJudgedByTheOneExecutor\|TestManifestFormCensusFollowsTheTree\|TestModuleManifestsOfThePlatformAreReadable\|TestManifestIsNotASecondDeclarationOfARight\|TestManifestNamedPredicateIsRunnableInThisTree\|TestConsumerOwnedStructuralRelationsHaveProducers' -count=1 -v` | код `0`, 7 из 7 PASS, `ok`; `блоков сверено 27 из 27 · байт сверено 80556`; `перепись: осмотрено путей 7142 · манифестов прочитано 5 · находок 0 (манифестов в индексе 5)` |
| П0: согласие пина и образа | `GOWORK=off go test ./deploy/ -run 'TestOutsourcedImagePinAgreesWithItsModulePin$' -count=1` | код `0`, `ok` |
| П0: предикаты манифеста DoD S1 | `yq '.roles\|length'`; `yq -o=json -I=0 '.roles[0].rules[0].children[0].resources'`; `diff` раздела `seed` со стволом эпика | `1`; `["repositories"]`; пусто |
| П1 | не перепрогонялось в редакции 10; пробы 28 — те же, что в посеве редакции 8 (`ok`, PASS 115 пакета `dataplane` на `e9ce4ffbd`) | — |
| П2 | стенд не поднимался | — |

Близнец 01 (ключ на `repositories`) мерен в редакции 8 на пине `5f6f29902`: FAIL с находкой
`resources[1].publicReadToChildren: на тип registry_repository не указывает ни один ресурс модуля registry — объявление без следствия`.

## Сценарии

### S1. Манифест, пины и гейты (kacho; `kacho#3251`, PR `kacho#3279`)

#### Сценарий 01: манифест новой редакции даёт блоки, равные канону, и проходит гейты формы

**ID:** REG-PUB-1-01
**Given** П0
**When** `GOWORK=off go test ./internal/repohygiene/ -run TestModelCanonAgreesWithPlatformManifests -count=1 -v`
**Then** `ok`; в выводе `блоков сверено 27 из 27`
**And** `GOWORK=off go test ./internal/repohygiene/ -run 'TestModuleManifestFormIsJudgedByTheOneExecutor|TestManifestFormCensusFollowsTheTree|TestModuleManifestsOfThePlatformAreReadable|TestManifestIsNotASecondDeclarationOfARight|TestManifestNamedPredicateIsRunnableInThisTree|TestConsumerOwnedStructuralRelationsHaveProducers' -count=1 -v` — `ok`; в выводе `TestModuleManifestFormIsJudgedByTheOneExecutor` строка `перепись: осмотрено путей … · манифестов прочитано 5 · находок 0`
**And** `GOWORK=off go test ./deploy/ -run 'TestOutsourcedImagePinAgreesWithItsModulePin$' -count=1` — `ok`
**Близнец (отрицательный):** манифест, в котором ключ `publicReadToChildren` стоит на
`repositories` вместо `registries`: `TestModelCanonAgreesWithPlatformManifests` красный, в выводе
`resources[1].publicReadToChildren: на тип registry_repository не указывает ни один ресурс модуля registry — объявление без следствия`.
Отличие — одно поле: ресурс, на котором стоит ключ.

#### Сценарий 02: роль доставлена — выдача ПЧ принимается

**ID:** REG-PUB-1-02
**Given** П2
**When** выдающий шлёт `POST /iam/v1/accessBindings` с телом «выдача ПЧ»
**Then** ответ — `Operation`; опрос `OperationService.Get` доходит до `done=true` без `error`
**And** `GET /iam/v1/accessBindings/{id}` → `roleId = "rolb1325b011aa17211d"`, субъект
`{"type":"SUBJECT_TYPE_SYSTEM_CLASS","id":"anonymous"}`
**Близнец (отрицательный):** то же тело с `"roleId":"rolb0000000000000000"` (форма id верна, роли
нет) → синхронно `FAILED_PRECONDITION` (HTTP 400), текст `Role rolb0000000000000000 not found`.
Отличие — один факт: существует ли роль.

#### Сценарий 03: роль даёт только чтение

**ID:** REG-PUB-1-03
**Given** П2
**When** `GET /iam/v1/roles/rolb1325b011aa17211d` от выдающего
**Then** `200`; в теле: `rules` — длины 1; `rules[0].module = "registry"`,
`rules[0].resources = ["registries"]`, `rules[0].verbs = ["get","list"]`; `rules[0].children` —
длины 1; `children[0].resources = ["repositories"]`, `children[0].verbs = ["get","list"]`; ключи
`children[0]` `module`, `children`, `resourceNames`, `matchLabels` пусты. Утверждения — поштучно
по полям: край сериализует с `EmitUnpopulated=true` и отдаёт пустые ключи (ND-02 приёмки
`kaname#874`)
**Близнец (отрицательный, форма):** те же утверждения о `GET /iam/v1/roles/{{rolRegGet}}` — проба
красная: `rules[0].children` пуст. Отличие — один факт: вложенное правило.
**Близнец (отрицательный, выдача):** тело «выдача ПЧ» с `"roleId":"{{rolRegEdit}}"` → синхронно
`FAILED_PRECONDITION`, текст SC-21 kaname
`Role <id> grants verbs beyond get and list; a system class subject accepts read-only roles`.
Отличие — один факт: глаголы роли.

### S2. API-край: чтение открытого реестра вошедшим (registry, gateway)

#### Сценарий 10: до выдачи посторонний реестра не видит

**ID:** REG-PUB-1-10
**Given** П2, выдач классам на X нет
**When** посторонний: `GET /registry/v1/registries/{X}`
**Then** `404`, `code` 5 (`NOT_FOUND`): отказ чтения не отличает закрытый реестр от несуществующего
**Близнец:** REG-PUB-1-11 — отличие одно: выдача ПЧ.

#### Сценарий 11: выдача ПЧ открывает реестр и его репозитории постороннему

**ID:** REG-PUB-1-11
**Given** П2; выдача ПЧ создана (REG-PUB-1-02) и материализована
**When** посторонний: `GET /registry/v1/registries/{X}`; `GET /registry/v1/registries/{X}/repositories`;
`GET /registry/v1/registries?projectId={{existingProjectId}}`
**Then** `200`, `id = X`; `200`, в странице репозиторий `app`; `200`, в странице ровно X (Y нет) (Р10)
**And** тело ответа `GET …/registries/{X}` не содержит ключа `visibility` (поля нет, Р2)
**Близнец (отрицательный):** REG-PUB-1-10 — то же без выдачи → `404`.

#### Сценарий 12: отзыв выдачи закрывает реестр

**ID:** REG-PUB-1-12
**Given** REG-PUB-1-11
**When** выдающий шлёт `DELETE /iam/v1/accessBindings/{id}` выдачи ПЧ; `Operation` доходит до `done=true`
**Then** опрос `GET /registry/v1/registries/{X}` от постороннего доходит до `404`, `code` 5, в
пределах окна П2
**Близнец:** REG-PUB-1-11 — до отзыва `200`.

#### Сценарий 17: удаление реестра выдачу не отзывает

**ID:** REG-PUB-1-17
**Given** REG-PUB-1-11; X опустошён и удалён выдающим: теги `X/app` сняты `DeleteTag`,
репозиторий — `DeleteRepository`, затем `DELETE /registry/v1/registries/{X}`; каждая `Operation`
— `done=true` без `error`
**When** `GET /iam/v1/accessBindings/{id}` выдачи ПЧ от выдающего
**Then** `200`; выдача существует, цель — прежний id X (Р7)
**And** `DELETE /iam/v1/accessBindings/{id}` → `Operation`, `done=true` без `error`
**Близнец:** REG-PUB-1-12 — отзыв той же выдачи при живом X проходит так же. Отличие — один
факт: существует ли реестр. Что видит аноним после удаления — REG-PUB-1-29.

#### Сценарий 18: редактор проекта реестр не открывает

**ID:** REG-PUB-1-18
**Given** П2, выдач классам на X нет
**When** редактор шлёт `POST /iam/v1/accessBindings` с телом «выдача ПЧ»
**Then** синхронно `PERMISSION_DENIED` (HTTP 403, `code` 7), тот же текст, что у выдачи
человеку без права (SC-20 kaname); `Operation` не создана; `GET /registry/v1/registries/{X}` от
постороннего → `404` (REG-PUB-1-10)
**Близнец:** REG-PUB-1-02 — то же тело от выдающего принято. Отличие — один факт: право выдать.

#### Сценарий 30: аноним на API-крае отвергается до решения

**ID:** REG-PUB-1-30
**Given** REG-PUB-1-11
**When** `GET /registry/v1/registries/{X}` и `GET /registry/v1/registries/{X}/repositories` без
`Authorization`
**Then** оба → `401`, `code` 16 (`UNAUTHENTICATED`), тело побайтово равно ответу на тот же путь
для закрытого Y (Р7 kaname: выдача классу не меняет отказ на методе с полом «1»)
**Близнец:** REG-PUB-1-11 — тот же путь с удостоверением постороннего → `200`. Отличие — один
факт: удостоверение.

#### Сценарий 31: выдача ПЧ не даёт правки и не открывает соседний реестр

**ID:** REG-PUB-1-31
**Given** REG-PUB-1-11
**When** посторонний: `PATCH /registry/v1/registries/{X}` с телом `{"description":"d-{{runId}}","updateMask":"description"}`;
`GET /registry/v1/registries/{Y}`
**Then** `PATCH` → `404`, `code` 5 (`hide_existence` на отказе правки), `description` X не изменился
(`GET` от выдающего); `GET Y` → `404`, `code` 5
**Близнец (правка):** тот же `PATCH` от выдающего → `Operation`, `done=true`, `description`
применён. Отличие — один факт: вызывающий.
**Близнец (соседний реестр):** REG-PUB-1-11, `GET X` → `200`. Отличие — один факт: реестр в цели выдачи.

### S3. Плоскость данных: что видит аноним (registry; чарты)

Стендовая часть S3 (13, 14, 20–27, 29) исполняется после S3 (чарты) и S4 (значения и пин) —
порядок Р9. Аноним предъявляет анонимный токен П2. Ответы — плоскость данных `/v2/...`.

#### Сценарий 13: роль без вложенного правила открывает реестр, но не репозитории

**ID:** REG-PUB-1-13
**Given** П2; выдающий выдаёт классу `anonymous` роль `rol-reg-get` с целью X (тело «выдача ПЧ» с
`"roleId":"{{rolRegGet}}"`); выдача материализована
**When** посторонний `GET /registry/v1/registries/{X}`; аноним `GET /v2/{X}/app/manifests/latest`
**Then** `GET X` → `200` (у класса `v_get` на реестр); `GET /v2/{X}/app/manifests/latest` → `404`,
`errors[0].code = "NAME_UNKNOWN"`: вложенного правила над `registry.repositories` нет,
`public_reader` не пишется (SC-73 kaname, ND-07 (б), Р5 `kaname#874`)
**Близнец:** REG-PUB-1-20 — та же цель и тот же класс, роль `registry.public.read` → `200`.
Правило верхнего уровня у ролей одно и то же; отличие — один факт: вложенное правило
`[get, list]` над `registry.repositories`.

#### Сценарий 14: выдача классу «вошедшие» не открывает анониму

**ID:** REG-PUB-1-14
**Given** П2; тело «выдача ПЧ» с субъектом `{"type":"SUBJECT_TYPE_SYSTEM_CLASS","id":"authenticated"}`
принято и материализовано
**When** посторонний `GET /registry/v1/registries/{X}/repositories`; аноним
`GET /v2/{X}/app/manifests/latest`
**Then** посторонний → `200`, в странице `app` (выдача действует, SC-69 kaname); аноним → `404
NAME_UNKNOWN`
**Близнец:** REG-PUB-1-20 — субъект `anonymous` → аноним `200`. Отличие — один факт: класс субъекта.

#### Сценарий 20: аноним тянет образ открытого реестра, включая репозиторий, созданный после выдачи

**ID:** REG-PUB-1-20
**Given** REG-PUB-1-11; затем выдающий пушит репозиторий `X/late`
**When** аноним: `GET /v2/{X}/app/manifests/latest`, затем `GET /v2/{X}/app/blobs/<digest слоя>`;
то же для `X/late`
**Then** все четыре → `200`; дайджест тела манифеста равен дайджесту, который вернул push
**Близнец (отрицательный):** REG-PUB-1-21.

#### Сценарий 21: закрытый реестр аноним не отличает от несуществующего

**ID:** REG-PUB-1-21
**Given** П2 без выдачи ПЧ
**When** аноним: `GET /v2/{X}/app/manifests/latest`; `GET /v2/{X}/nonexistent-{{runId}}/manifests/latest`
**Then** оба → `404`, тела побайтово равны, `errors[0].code = "NAME_UNKNOWN"`
**Близнец:** REG-PUB-1-20 — отличие одно: выдача ПЧ.

#### Сценарий 22: аноним перечисляет теги открытого репозитория, а не чужого

**ID:** REG-PUB-1-22
**Given** REG-PUB-1-20
**When** аноним `GET /v2/{X}/app/tags/list`
**Then** `200`, `tags` содержит `latest`
**Близнец (отрицательный):** тот же запрос к `Y/app` → `404 NAME_UNKNOWN`. Отличие — один факт:
реестр в цели выдачи.

#### Сценарий 23: каталог анонима — репозитории открытых реестров и только они

**ID:** REG-PUB-1-23
**Given** REG-PUB-1-20
**When** аноним `GET /v2/_catalog?n=1000`, по ссылкам `Link: rel="next"` до конца
**Then** собранный перечень содержит `{X}/app` и `{X}/late`; не содержит `{Y}/app` и `{Y}/pub`.
Поштучная публикация даёт только `v_get`, не `v_list` (SC-67 kaname, `fga_model.fga:1358`)
**Близнец:** тот же обход от выдающего → перечень содержит `{Y}/app`. Отличие — один факт: вызывающий.

#### Сценарий 24: аноним не пишет — ни в существующий, ни в новый репозиторий

**ID:** REG-PUB-1-24
**Given** REG-PUB-1-11
**When** аноним `POST /v2/{X}/app/blobs/uploads/` и `POST /v2/{X}/new-{{runId}}/blobs/uploads/`;
`PUT /v2/{X}/app/manifests/anon-{{runId}}` с телом существующего манифеста
**Then** каждый → `403`, `errors[0].code = "DENIED"`, текст `requested access to the resource is denied`;
после этого `GET /v2/{X}/app/tags/list` от выдающего тега `anon-{{runId}}` не содержит, а
`_catalog` не содержит `{X}/new-{{runId}}`
**And** аноним `DELETE /v2/{X}/app/manifests/latest` → `405`
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
**When** выдача ПЧ отозвана (как в REG-PUB-1-12)
**Then** опрос `GET /v2/{X}/app/manifests/latest` и `GET /v2/{X}/late/manifests/latest` анонимом
доходит до `404 NAME_UNKNOWN` по обоим в пределах окна П2
**And** `GET /v2/{X}/app/manifests/latest` от выдающего → `200`
**Близнец:** REG-PUB-1-20 — до отзыва `200`.

#### Сценарий 27: поштучная публикация в закрытом реестре работает как прежде

**ID:** REG-PUB-1-27
**Given** П2 без выдачи ПЧ; `Y/pub` опубликован поштучно
**When** аноним `GET /v2/{Y}/pub/manifests/<тег посева>`; `GET /v2/{Y}/pub/tags/list`
**Then** манифест → `200`; `tags/list` → `404 NAME_UNKNOWN` (публикация даёт только `v_get`)
**Близнец:** аноним `GET /v2/{Y}/app/manifests/<тег>` (не опубликован) → `404`. Отличие — один
факт: поштучная публикация.

#### Сценарий 28: integration — анонимный субъект спрашивается классом

**ID:** REG-PUB-1-28
**Given** П1; плоскость данных собрана с `WithAnonymousSubject("<идентификатор закрытой формы>")`;
проверяющий токена отдаёт `sub` = этот идентификатор
**When** `GET /v2/{X}/app/manifests/latest`
**Then** дублёр решения о доступе получил ровно один вопрос: субъект `system_class:anonymous`,
отношение `v_get`, объект `registry_repository:{X}/app`
**Близнец:** та же сборка с `WithAnonymousSubject("")` — субъект вопроса не
`system_class:anonymous` (поток выключен). Отличие — одна ручка.

#### Сценарий 29: после удаления реестра аноним получает отказ чтения

**ID:** REG-PUB-1-29
**Given** REG-PUB-1-17 до отзыва выдачи: X удалён, выдача ПЧ на прежний id X существует
**When** аноним `GET /v2/{X}/app/manifests/latest`
**Then** опрос доходит до `404` с телом, побайтово равным телу REG-PUB-1-21: кортежи репозитория
сняты `DeleteRepository`, кортежи реестра — работником удаления, `public_reader from parent`
ничего не находит. Сценарий утверждает условие, к которому сходится опрос в окне П2
**Близнец:** REG-PUB-1-20 — тот же запрос при живом X → `200`. Отличие — один факт: существует ли реестр.

### S4. Значения стенда и сквозной `docker pull` (стенд)

#### Сценарий 50: `docker pull` открытого образа без входа

**ID:** REG-PUB-1-50
**Given** П2; REG-PUB-1-11; у клиента нет сохранённых учётных данных к хосту плоскости данных
(чистый `DOCKER_CONFIG` во временном каталоге)
**When** `docker pull <хост плоскости данных>/{X}/app:latest`
**Then** код возврата `0`; `docker image inspect` → дайджест репозитория равен дайджесту push
**Близнец (отрицательный):** REG-PUB-1-51.

#### Сценарий 51: `docker pull` закрытого образа без входа и `docker push` анонимом отвергаются

**ID:** REG-PUB-1-51
**Given** П2 без выдачи ПЧ; тот же чистый `DOCKER_CONFIG`
**When** `docker pull <хост>/{X}/app:latest`; затем выдача ПЧ создана и материализована, и
`docker push <хост>/{X}/app:anon-{{runId}}`
**Then** pull — код возврата не `0`, `docker image inspect <хост>/{X}/app:latest` — код не `0`.
Push — код не `0`, вывод содержит `requested access to the resource is denied`; тега
`anon-{{runId}}` в `tags/list` от выдающего нет
**Близнец:** REG-PUB-1-50 — отличие одно: выдача ПЧ (для pull).

## Сценарий → производитель

«Уже производит» — координата прочитана на ревизии из шапки. «Заказан» — производителя нет, его
заводит полоса стадии или названная задача.

| ID | что производит «Тогда» | координата | чем измерено |
|---|---|---|---|
| 01 | сверка с каноном, судья формы, производитель структурного отношения, согласие пина и образа | исполнители из пина kaname (`tools/modelcanoncheck`, `tools/modulemanifestcheck`), зовутся `internal/repohygiene/modelcanonpin_test.go`, `modulemanifestformpin_test.go` — уже производят; манифест, пин, тег, `subjectUsersets` — PR `kacho#3279` (OPEN), **заказано вливание** в ветку эпика | посев редакции 10: 7 из 7 PASS на `636bd5435`; близнец — посев редакции 8 |
| 02, 03 | выдача, отказ «роль не найдена», отказ пишущей роли, тело роли с `children` через край | kaname `access_binding/create.go`, `system_class_gates.go` — уже производят; роль в каталоге и транскодирование `RoleService` по пину — PR `kacho#3279`, **заказано вливание**; newman-кейсы 02, 03 — **заказаны** (в `registry-public-by-class.py` ветки `3274` их нет) | перепись |
| 10–12, 17, 18, 30, 31 | `200`/`404` чтения постороннего, `401` анонима на крае, `403` редактору, выдача переживает реестр | Check края по каталогу (`v_get` на `registry_registry`, канон `fga_model.fga` реестра принимает `system_class`), сужение строк `ListRepositories` и `List`, `hide_existence` у `Update`, kaname Р2 (класс у говорящего с личностью), `requireGrantAuthority`, `auth.go` края — уже производят; роль — PR `kacho#3279`; newman-кейсы — **заказана переделка** кейсов ветки `3274` без утверждений о `visibility` | перепись; кейсы ветки `3274` |
| 13, 14, 20–27, 29 | `200`, `404 NAME_UNKNOWN`, `403 DENIED`, `405`, фильтр `_catalog` | `services/registry/internal/dataplane/handler.go` — уже производит; решения о `v_get`, `v_list` класса и `public_reader` по вложенному правилу — kaname (`kaname#874` влит) — уже производят; анонимный токен на стенде: ручка kaname — `kaname#495` (влит); ручка чарта registry, вывод `anonymous-client-id` вложенным чартом, отказ рендера — **заказаны** (S3); второй подъём пина и тега, значения профилей — **заказаны** (S4); newman-кейсы — **заказаны** (S3) | перепись: ручек в `deploy` — 0 |
| 28 | субъект `system_class:anonymous`; выключенный поток | `dataplane/authz.go` (`fgaSubject`), `WithAnonymousSubject` — уже производит; пробы `TestSystemClass_SC39_RegistryAsksAsTheAnonymousClass`, `TestDataplane_RG1_AnonDisabled_TokenResolvesAsOrdinaryPrincipal` — уже есть | перепись |
| 50, 51 | сквозной `docker pull`, `docker push` | чарты — **заказаны** (S3); значения и пин — **заказаны** (S4); шаг сквозного прогона с настоящим клиентом — **заказан** (S4) | перепись |

Сценариев без производителя, чей производитель не заказан стадией или задачей, — 0. Вне kacho
производителей, которых нет, — 0: `kaname#872`, `#874` (`#879`), `#495` (`#871`) влиты.

## Инварианты, которые изменение не вправе тронуть

1. Поштучная публикация репозитория и `defaultRepositoryVisibility` ведут себя как до изменения
   (REG-PUB-1-27).
2. Отказ чтения на плоскости данных не отличает закрытое от несуществующего (REG-PUB-1-21).
3. На API-крае пол «1» не снимается ни у одного метода registry (REG-PUB-1-30).
4. Класс ничего не пишет ни одним путём (REG-PUB-1-24, 31, 03).
5. У открытости реестра один источник — выдача в kaname; у registry нет ни поля, ни столбца,
   ни флага, ни метода о ней (Р2). Предикат: `git diff <база>...<голова> -- proto/kacho/cloud/registry`
   не прибавляет полей и методов (`buf breaking` — находок 0, `grep -c '^+ *rpc '` → `0`).
6. Раздел `seed` манифеста registry (#914) не меняется.

## DoD

**S1 (манифест, пины, гейты)** — 01, 02, 03; исполнитель — `kacho#3251`, PR `kacho#3279`:
- PR `kacho#3279` влит в ветку эпика `3172-identity-own-2`; на ревизии вливания: `yq '.roles | length'
  services/registry/manifest.yaml` → `1`; `yq -o=json -I=0 '.roles[0].rules[0].children[0].resources'`
  → `["repositories"]`; `diff` раздела `seed` со стволом — пусто; шапка манифеста о разделе
  `roles` переписана;
- пин kaname — потомок `efac3adf7` и на стволе kaname (`git merge-base --is-ancestor efac3adf7891 "$PIN"`
  и `git merge-base --is-ancestor "$PIN" origin/main` → `0`); тег `main-<sha8>` той же ревизии
  в 5 профилях, образ опубликован (`docker manifest inspect` → `0`);
- REG-PUB-1-01 — все команды сценария `ok`, вывод в `DoD-proof`; близнец — красный с находкой дословно;
- `make -C gateway permission-catalog-check rest-route-table-check catalog-splice-check` — код `0`;
- REG-PUB-1-02, 03 — newman-кейсы набора registry на стенде П2.

**S2 (API-край и тексты)** — 10, 11, 12, 17, 18, 30, 31:
- newman на стенде П2: кейсы ветки `3274` (`registry-public-by-class.py`) переписаны без
  утверждений о `visibility`; кейсы 15, 16, 45 сняты; ≥ 1 happy и ≥ 1 negative на метод
  (`testing-newman.md#qa-classes-per-method`); коллекция перегенерирована `gen.py`; новая
  коллекция — с записью ведомости производителя, гейтом набора и назначением шарду;
- **тексты, которые доставка роли делает ложными, переписаны.** Предикат —
  `git grep -n -i "ЕДИНСТВЕННЫЙ рычаг\|Единственный registry-level\|любой путь к PUBLIC\|Единственный рычаг публичности" <голова>`:
  до — 8 строк в 6 файлах (перепись), после — 0. Переписываются `repository.mdx:101` (поле
  описывает собственную публикацию репозитория; чтение без входа даёт и выдача роли
  `registry.public.read` классу на реестр), `resource-registry.tsx:5194`,
  `console-ops-match-contract.test.ts:28`, `clienttruth_registry_apisurface.go:17`,
  `registry.proto:54-57` и `:102-108` (комментарии; у реестра два пути к чтению без входа —
  поштучная публикация под D-6/D-7 и выдача роли классу под гейтами kaname, Р3), `pb.go` —
  `buf generate`; `buf breaking` против базы — находок 0;
- страница сайта документации registry (`services/registry/docs/content/api/registry.mdx` или
  `getting-started.mdx`): как открыть реестр выдачей роли `registry.public.read` классу, Р2, Р3, Р10.

**S3 (плоскость данных и чарты)** — 13, 14, 20–29:
- чарты (Р9 п. 2): ручка чарта registry с пустым умолчанием; вложенный чарт kaname выводит
  `anonymous-client-id`; отказ рендера umbrella при двух разных заданных значениях. Проба
  рендера: оба пусто — ключей нет; оба заданы одинаково — оба в рендере; разные — `helm
  template` с отказом и текстом, называющим обе ручки;
- REG-PUB-1-28 — integration пакета `dataplane`, обе стороны (пробы уже есть);
- newman 13, 14, 20–27, 29 на стенде П2 — после S4 (значения и пин), порядок Р9;
- `deploy/e2e-shards.json`: набор, ходящий в плоскость данных, — на шарде с компонентом registry
  (`assert-shard-coverage.py` зелёный).

**S4 (значения стенда и сквозной `docker pull`)** — 50, 51:
- второй подъём пина kaname и тега образа в 5 профилях — до ревизии ствола kaname с влитым
  `kaname#871` (`git merge-base --is-ancestor 0b6b21cc9 "$PIN"` → `0`);
  `TestOutsourcedImagePinAgreesWithItsModulePin` зелёный;
- профили стенда задают оба значения Р9 п. 2 одним идентификатором закрытой формы SC-39;
  равенство держат отказ рендера (S3) и REG-PUB-1-20;
- шаг сквозного прогона на стенде П2 с настоящим клиентом `docker`, чистый `DOCKER_CONFIG` во
  временном каталоге, снятие образов и каталога в `trap`; вердикт — код возврата шага.

**Снятие прежнего объёма (тем же изменением, что S2):** с ветки `3274` сняты пробы, утверждающие
снятое — `regpub1_visibility_mask_test.go`, `registry_visibility_regpub1_integration_test.go`,
`registry-public-visibility.spec.ts`, `RegistryPage.public-visibility.test.tsx`; предикат —
`git grep -n -i 'visibility' <голова> -- 'services/registry/tests/newman/cases/registry-public-by-class.py'`
не находит утверждений о `Registry.visibility` (допустимы только `Repository.visibility` посева `Y/pub`).

**Все стадии:** `census.sh` до и после прогона стенда → 0; пары RED→GREEN по каждой стадии в
`DoD-proof @<sha>` задачи `kacho#3274`.

## Редакция 10: что изменено

| что | где |
|---|---|
| решение владельца 2026-10-18 и следствие для объёма | раздел «Решение владельца, которым сужен объём»; «Что НЕ входит» пп. 1, 2 |
| сняты `Registry.visibility` и его вывод (прежние Р2, Р4, Р5, Р6, Д1–Д4, Д8), консоль (S5, сценарии 40–45), сценарии 15, 16; F1 REG-1 больше не пересматривается | «Опора», «Решения», «Сценарии» |
| Р2 переписан: открытость — только выдача роли, представления у registry нет; инвариант 5 — с предикатом | «Решения», «Инварианты» |
| S1 — это `kacho#3251`, PR `kacho#3279`; гейты S1 перемерены на его голове `636bd5435` | Р1, «Перепись», «Посев», DoD S1 |
| стадии: S2 — API-край и тексты (прежние S2 и S4), S3 — плоскость данных и чарты, S4 — значения стенда и `docker` (прежняя S6) | «Сценарии», DoD |
| сценарии 10–14, 18, 27, 31 переформулированы через чтение от имени постороннего и анонима вместо `visibility`; 13 и 14 перенесены в S3 | «Сценарии» |
| `kaname#871` влит (`0b6b21cc9`); второй подъём пина — не ниже его; форма значения ручки — закрытая форма SC-39 ред. 13 | Р9, DoD S4; «Опора» — соседняя приёмка kaname сменилась (ред. 13, `dfbe47bf…`), перепроверено |
| снятие RED-проб ветки `3274` прежнего объёма | DoD, «Снятие прежнего объёма» |
