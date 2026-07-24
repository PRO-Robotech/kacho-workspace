---
title: API-UX ревью редизайна — панель критиков (раунд 1)
category: kac
tags: [kacho-proto, kacho-api-gateway, kac, docs, conventions, architecture]
ticket_id: TBD
status: in-progress
type: docs
repos: [kacho (monorepo)]
opened: 2026-07-24
---

# API-UX ревью редизайна — панель критиков

Оценка публичной поверхности **глазами пользователя API** (не на корректность — на восприятие,
освоение, простоту). 8 независимых линз → adversarial-синтез с отсевом. Отраслевые ожидания
использованы как ОРИЕНТИР; имена вендоров в артефакты не выносятся (ban #2).

Линзы: ресурсная модель · соответствие типовым ожиданиям · первый час работы · кросс-доменная
консистентность · эргономика ошибок¹ · модель размещения/сети · IAM-UX¹ (¹ — заблокированы
классификатором, перезапускаются).

## Главное: каркас силён, проблемы — в «упаковке»

Ни одна линза не потребовала переделки модели ресурса, транзакционной семантики или authz-модели.
Плоский envelope выдержан во всех 7 доменах, «Get/List sync + мутации→Operation» — без исключений,
`update_mask` на всех 43 канонических Update, cursor-пагинация едина, tombstone-дисциплина
(`reserved` по номерам И именам) системна, осознанные отклонения оформлены как документированные
carve-out'ы. Это выше типового уровня для API такого объёма.

## Приоритизированные рекомендации


### 1. Открыть путь «пустой проект → первая VM»: сид каталогов + платформенный каталог образов (_moderate_)

**Почему:** Единственная находка, полностью блокирующая освоение. На свежем кластере `GET /geo/v1/zones` → [], `GET /compute/v1/machineTypes` → [] (проверено: в services/geo/internal/migrations ни одного INSERT, 0015_machine_types.sql — CREATE TABLE без сида), а storage.Image создаётся ИСКЛЮЧИТЕЛЬНО из своего Snapshot/Volume при `ListImagesRequest.project_id` required — значит обязательный `bootSource` заполнить нечем: замкнутый круг. Каталоги наполняются только через Internal-API на :9091, куда тенант по определению не ходит. Ошибка приходит поздно и не по адресу («Zone not found» вместо «каталог не инициализирован»), а валидатор compute вдобавок отсылает к RPC `ImageCatalog`, которого в репо нет (serv

**Что сделать:** (а) Идемпотентные goose-сиды по готовому образцу services/storage/internal/migrations/0004_seed_disk_types.sql (`ON CONFLICT DO NOTHING`): baseline Region/Zone в geo и 3-5 MachineType в compute. (б) Ввести платформенный каталог образов: `Image.visibility {PRIVATE|PUBLIC}` + снять required с `project_id` в ListImages для PUBLIC-scope (либо отдельный read-only `ImageCatalogService`, на который уже ссылается текст ошибки), вернуть `family` + «последний в семействе» — эта способность была в compute.Image (image.proto:52-57) и редизайн её потерял, не заменив. (в) При пустом каталоге отвечать `FAILED_PRECONDITION "placement catalog is not initialized"`, а не `NOT_FOUND` на конкретный id — это отли

### 2. Пометить compute-семейство блочного хранилища deprecated: одна каноническая ветка вместо двух живых (_cheap-additive_)

**Почему:** Проверено: gateway регистрирует ОБА семейства одновременно — compute Disk/Image/Snapshot/DiskType (mux.go:406-419) и storage Volume/Image/Snapshot/DiskType (:453-467). Различить их в API нечем: во всём дереве proto всего 5 `deprecated = true`, ни одного здесь. Поля расходятся (`size`/`typeId`/`instanceIds[]` против `sizeBytes`/`diskTypeId`/`usedBy[]`/`updatedAt`), возможности расходятся (`:relocate` есть только у compute, `attachments` только у storage), а `Instance.bootDisk`/`secondaryDisks` ссылаются на `volumeId` — то есть выбравший «логичную» ветку `/compute/v1/disks` упирается в тупик на этапе attach, потратив на интеграцию недели. Сам strangler обоснован (снос требует data-migration, р

**Что сделать:** `option deprecated = true` на все RPC compute Disk/Image/Snapshot/DiskType + первой строкой докстринга `DEPRECATED — superseded by storage.v1.<X>`; в docs-site — таблица соответствия полей (`size`→`sizeBytes`, `typeId`→`diskTypeId`, `instanceIds`→`usedBy`); в OpenAPI/докcайте не показывать оба семейства равноправно; в плане зафиксировать срок снятия с публичного mux и не выпускать GA с обоими. То же — для compute ImageService: `family`/«последний в семействе» переносить в storage.Image (см. п.1), а не оставлять как приманку на отмирающей поверхности.

### 3. Нормализовать `ResourceRef.type` в AuthorizeService: сейчас корректный грант даёт тихий deny (_cheap-additive_)

**Почему:** Проверено в коде: `domain.ValidTargetType` принимает для `AccessBinding.target` dotted-форму и мапит её в bare (`compute.instance` → `compute_instance`), а `authorize_service.go:266` строит FGA-объект как `fmt.Sprintf("%s:%s", req.Resource.Type, req.Resource.ID)` — то есть Check требует УЖЕ bare-форму. Один и тот же proto-message `ResourceRef` в двух RPC одного сервиса требует несовместимых словарей, а два его докстринга в соседних файлах (authorize_service.proto:216-224 и access_binding.proto:191-196) документируют противоположные формы. Пользователь выдаёт грант на конкретный инстанс — принято; проверяет его тем же значением — `{allowed:false, denyReasons:["no path"]}`, неотличимо от «прав

**Что сделать:** Нормализовать `ResourceRef.type` через уже существующий `authzmap.objectTypes` на входе Check/BatchCheck/ListSubjects/ExpandRelations — принимать обе формы (аддитивно, существующих вызывающих не ломает); нераспознанный тип отвергать `INVALID_ARGUMENT`, а НЕ превращать в `allowed:false`. Свести докстринги обоих файлов к одной канонической (dotted) форме, bare/FGA-форму объявить внутренней. Regression: dotted и bare на Check дают одинаковое решение; мусорный тип → 400, не `allowed:false`.

### 4. Проход doc-truthfulness по proto: справочник обязан описывать этот продукт и этот контракт (_cheap-additive_)

**Почему:** proto — единственный источник REST-справки и docstring'ов сгенерированного SDK, и он систематически расходится с реализацией. 122 упоминания несуществующего «folder» над полем `project_id` (миграция folder→project доехала до модели, но не до текста) — новичок читает описание базового поля владения при знакомстве с ЛЮБЫМ ресурсом и идёт искать ресурс, которого нет. `filter` в compute/vpc обещает `AND`/`IN`/`!=` и поля `status`/`zone_id`/`platform_id`, а фактический whitelist — `["name"]` (проверено по всем repo), причём два обещанных поля вообще `reserved`; в storage/nlb текст честный — то есть контракт, выученный на одном сервисе, ложен в соседнем. `CreateSubnetRequest.placement_type` описан

**Что сделать:** (а) Механическая замена folder→project по ~45 proto + `_suiteFolderId`→`_suiteProjectId` в newman-фикстурах (правка комментариев, wire не затрагивается). (б) Текст `filter` привести к фактическому whitelist везде (эталон — storage/nlb). (в) `placement_type` переписать: «Output-only, server-derived from exactly one of zone_id / region_id; передача на Create → INVALID_ARGUMENT», и пометить output-only на read-проекции; прогнать тот же аудит по остальным Create*Request после F6-редизайна. (г) Удалить/заменить 62 doc-ссылки на реальные якоря docs-site. (д) Вычистить вендор-упоминания из публичных proto; `gce_*`/`aws_*`-поля в instancegroup/instance_group.proto:1001-1011 перевести в `reserved` — 

### 5. Убрать silent-ignore: «принял ⇒ применил, иначе синхронно отверг» (_cheap-additive_)

**Почему:** API принимает то, чего не делает, и не говорит об этом. Проверено: `order_by` объявлен в 15 request-сообщениях (compute/storage) и не читается ни одной строкой прод-кода — `GetOrderBy` встречается только в сгенерированных .pb.go; клиент ставит `orderBy=createdAt desc`, получает 200 и старый порядок, а справка вдобавок врёт про дефолт («id asc» вместо фактического `(created_at, id) ASC`). Шесть полей `CreateInstanceRequest` (`network_settings`, `filesystem_specs`, `local_disk_specs`, `maintenance_policy`, `maintenance_grace_period`, `serial_port_settings`) не переносятся хендлером вообще — ресурс создан, настройка выброшена, предупреждения нет. Пометка «(legacy)» живёт только в комментарии: в

**Что сделать:** Ввести правило и закрыть его гейтом. Конкретно: непустой `order_by` → `INVALID_ARGUMENT` сейчас, поле удалить до GA (реализовывать не надо — см. rejected); шесть полей Create — либо `reserved` по номерам и именам (механика в этом же файле уже применена для retired-набора), либо синхронный `INVALID_ARGUMENT "<field> is not supported"` по образцу того, как vpc отвергает клиентский `placement_type`; на ВСЕ поля с пометкой «(legacy)» проставить `[deprecated = true]` + строку «superseded by <новое поле>» (сейчас во всём дереве 5 `deprecated`, в compute — ноль). CI-гейт: каждое поле публичного request-сообщения либо читается хендлером, либо `reserved`, либо отвергается.

### 6. Публиковать OpenAPI и закрыть дрейф proto↔gateway: перестать рекламировать неотдаваемый API (_cheap-additive_)

**Почему:** Вся tenant-поверхность — REST через grpc-gateway, но машиночитаемого описания REST в дереве нет ни одного файла: проверено, в proto/buf.gen.yaml три плагина (go, go-grpc, grpc-gateway) и НЕТ protoc-gen-openapiv2. Инженер первого часа вынужден читать .proto и в уме применять маппинг `google.api.http` + camelCase-JSON, чтобы собрать один запрос: ни импорта в HTTP-клиент, ни SDK на не-Go, ни песочницы. Хуже — прочитанное системно врёт в большую сторону: compute объявляет 15 публичных сервисов, mux регистрирует 6; `/gpuClusters`, `/hostGroups`, `/instanceGroups`, `/placementGroups`, `/filesystems`, `/snapshotSchedules` и ещё 4 семейства описаны с полными путями и authz-аннотациями, но дают 404; 

**Что сделать:** (а) Добавить protoc-gen-openapiv2 в buf.gen.yaml и публиковать спеку артефактом — одна строка конфигурации, и она же закрывает «нет справочника». (б) Фильтровать спеку по фактически зарегистрированным в restmux сервисам (permission-catalog уже генерируется и знает реальный набор — брать оттуда). (в) Нереализованным RPC/сервисам — `option deprecated = true` либо `[NOT YET SERVED]` первой строкой докстринга, чтобы дрейф был виден в самом proto. (г) CI-гейт «каждый public RPC из proto либо зарегистрирован в restmux, либо помечен» — тот же класс, что уже закрытый `permission-catalog-check`.

### 7. Канонизировать словарь authz-идентификаторов — это единственное, что пользователь пишет руками (**ЛОМАЮЩЕЕ**)

**Почему:** Разрешения и типы объектов — публичная поверхность (`GET /iam/v1/permissionCatalog` отдаётся пользователю, на эти строки ссылаются роли, которые администратор пишет сам), и именно там больше всего небрежности. Проверено: `compute.instanceses.list`, `vpc.addresseses.list`, `vpc.gatewaies.get` рядом с `vpc.gatewayses.list`, `vpc.used_addresseses.listUsedAddresses`, `iam.issue_s_a_keies.issue` — 17 артефактов наивной плюрализации, для одного ресурса два разных написания. Сегмент ресурса в единственном числе в compute/vpc/iam и во множественном в storage/registry/loadbalancer: правило, выученное на `compute.instance`, на `storage.volume` даёт молча пропущенный токен (rule-compiler fail-closed SK

**Что сделать:** Одна грамматика — singular lowerCamel (`compute.instance`, `storage.volume`, `loadbalancer.listener`, `registry.repository`): она уже покрывает большинство ключей и совпадает с формой `Referrer.type`. (а) Заменить генератор плюрализации явной таблицей, регенерировать permission-catalog (обе embedded-копии + CI-гейт byte-identical уже есть). (б) Привести storage/registry/loadbalancer к singular; мигрировать без слома — принимать старую форму как алиас при чтении правил роли + разовый backfill сохранённых `rules[]`, отдавать в каталоге только каноничную. (в) Вынести словарь в ЕДИНЫЙ Go-справочник, из которого эмитят `Referrer.type` все сервисы (сейчас у каждого своя локальная константа), приме

### 8. Один канон написания путей: `:camelCaseVerb` + camelCase-подколлекции (_cheap-additive_)

**Почему:** REST-путь — самая заучиваемая часть API, и сейчас в нём три конкурирующие идиомы, причём расходятся они не только между доменами, но и внутри одного ресурса. vpc: `POST /subnets/{id}:add-cidr-blocks` (kebab) и `POST /addressPools/{id}:addCidrBlocks` (camel) — один глагол, один домен, два написания; `/networks/{id}/route_tables` и `/security_groups` (snake) при том, что те же ресурсы верхним уровнем `/vpc/v1/routeTables` и `/vpc/v1/securityGroups`. compute: `:attachDisk`/`:start`/`:stop` соседствуют с `/updateMetadata`, `/addOneToOneNat`, `/removeOneToOneNat`, `/updateNetworkInterface` — глагол сегментом пути, выглядящий как под-ресурс, которого нет. Плюс рассинхрон `{address_pool_id}`/`{pool

**Что сделать:** Канон: действие — всегда `:camelCaseVerb` после id, под-коллекция — всегда `/camelCasePlural`. Зарегистрировать каноничные пути как `additional_bindings` (аддитивно, ничего не ломает): 7 kebab-роутов vpc (`:add-cidr-blocks`/`:remove-cidr-blocks` ×2, `:add-routes`/`:remove-routes`/`:update-route`), 4 slash-глагола compute, 2 snake-подколлекции vpc, `groups/{id}:listMembers`→`/members`; старые пометить deprecated и снять до GA. Свести `{address_pool_id}`/`{pool_id}` к одному имени. Переосмыслить `POST|DELETE /networks/{id}/addressPoolBinding` — POST/DELETE на существительное это третья форма, отличная от обеих принятых. CI-гейт: регулярка по `google.api.http`, роняющая PR на `-` или `_` в хвос

### 9. Дописать контракт Operation (EC-окно + phantom-id) и убрать асимметрию Get/List операций (_moderate_)

**Почему:** Два факта, без которых клиент пишется неправильно, сегодня живут только во внутренних правилах и в тестовых хелперах, а не в контракте (проверено: слов eventual/read-your-writes/retry в proto нет). Первый: `done:true` — это durability предмета мутации, но НЕ видимость в authz/List, поэтому первый Get/Update/Delete своего свежего ресурса может кратко отдать 403/404, а List — не содержать его; пользователь читает контракт буквально и заводит баг «Create вернул done, а Get 404» — и формально он прав. Второй: `metadata.<res>Id` заполнен pre-allocated id ДАЖЕ при `done:true` с `error` — клиент, читающий id без проверки `result.error`, уносит в конфиг id несозданного ресурса (внутри проекта это уж

**Что сделать:** (а) Дописать в operation.proto два абзаца контракта: `done == true` = durability предмета мутации, доступ вызывающего материализуется eventually (порядок окна ~10s; ожидаемая реакция клиента — bounded retry ПЕРВОГО обращения к своему свежему ресурсу, и только к нему); `metadata` несёт pre-allocated id, валидный ТОЛЬКО когда `result == response` — при `result == error` id ссылается на несозданный ресурс. (б) Авторизовать `OperationService.Get` против ресурса-цели операции (из `metadata`) тем же relation, что и `ListOperations`, сохранив 404-вместо-403 для неавторизованных (no-leak); если creator-only остаётся сознательно — симметрично закрыть `ListOperations` тем же предикатом и записать прав

### 10. Сделать модель размещения наблюдаемой и энфорсимой: сигнал есть, гарантии нет (_moderate_)

**Почему:** geo спроектирован как честный discovery-слой (`openForPlacement°` + `placementBlockedReason°` в одном вызове, фильтры, project-scope EXEMPT) — и это сильная сторона. Но проверено: символ `OpenForPlacement` не встречается ни в одном сервисе-потребителе; все peer-валидации (compute/vpc/storage/nlb) проверяют только existence. Значит разместиться в административно закрытой зоне можно молча: ресурс durable-создан, `done:true` без error, узнать — только по тому, что data-plane никогда не материализуется. Платформа публикует сигнал «сюда нельзя» и сама его игнорирует. Дальше: ZONAL-балансировщик не отдаёт свою зону вообще (нужны три Get в трёх доменах, чтобы прочитать координату собственного ресур

**Что сделать:** (а) Общий `geoconsumer.ValidatePlacement` во всех peer-валидациях zone/region: закрытая координата → `FAILED_PRECONDITION` с причиной из `placementBlockedReason` и подсказкой `GET /geo/v1/zones?openForPlacement=true` (флаг уже приходит в peer-Get, доп. вызова не нужно); в доке зафиксировать advisory-TOCTOU — на такой отказ клиент делает re-discover, а не ретрай той же зоны. (б) Output-only `zone_id` на NetworkLoadBalancer (пусто ⇒ REGIONAL/anycast, читается в одном вызове) + опциональный input `zone_id` на Create для INTERNAL_ZONAL как authoritative pin, снимающий order-dependence. (в) Derived output-only `region_id` на ZONAL-подсети + сделать `region_id` опциональным на nlb.Create при задан

### 11. Единый хелпер текстов ошибок: имя поля в ошибке = имя поля на проводе (_cheap-additive_)

**Почему:** REST camelCase-only, а в ошибках имена полей то camelCase, то snake_case — вплоть до двух написаний ОДНОГО поля одного ресурса (`owner_user_id` и `ownerUserId` в Account, `scopeType` рядом с `subject_type` в AccessBinding). Пользователь отправляет `ipv4CidrPrimary`, получает претензию к `v4_cidr_blocks[0]` — имени, которого в его запросе нет и которое он не найдёт ни в своём коде, ни в спеке: сопоставить можно только зная внутреннюю доменную модель. Тон not-found расходится так же: `"Subnet %s not found"` и `"subnet %s not found"`, `"Address not found"` вовсе без id, `"repository not found"` со строчной и без id. Тексты объявлены частью контракта — и прямое следствие разнобоя: требование sec

**Что сделать:** Один хелпер на монорепо: `errmsg.NotFound(Resource, id)` и `errmsg.Immutable(jsonField, Resource)`, где `jsonField` — ВСЕГДА camelCase (то же имя, что на wire), `Resource` — ВСЕГДА PascalCase-имя proto-message; `BadRequest.FieldViolation.field` отдавать JSON-именем поля запроса, а не именем доменной структуры. Прогнать замену по всем 7 сервисам (правка строковая, прод-логика не меняется), закрыть behaviour-тестами на точный текст (testing.md это уже требует) и одним тестом на byte-identity deny-текста и miss-текста. Заодно свести два текста одной ошибки «несуществующая зона»: vpc/storage отдают `unknown zone id '<X>'`, compute — `Zone <X> not found`.

### 12. Довести registry до паритета по обвязке и закрыть функциональную дыру с вложенными репозиториями (**ЛОМАЮЩЕЕ**)

**Почему:** registry — системный выброс на фоне остальных шести доменов, и одно из расхождений не стилистическое, а функциональное: имя репозитория по грамматике допускает слэши (`team/app` валиден), на Get/Delete объявлен `{repository=**}`, а на ListTags/DeleteTag — односегментный `{repository}`, то есть теги вложенного репозитория через REST недостижимы, хотя сам репозиторий создать и получить можно. Плюс `int32 page_size` при `int64` во всех остальных доменах (общий SDK-хелпер пагинации не компилируется), ноль аннотаций `(required)`/`(length)` против 25-159 в остальных доменах при том, что `regionId` реально энфорсится, `filter` только у ListRegistries (в большом реестре поиск репозитория/тега невозм

**Что сделать:** `{repository}` → `{repository=**}` в ListTags/DeleteTag + newman-кейс с именем `team/app` (это баг, не стиль). `int32`→`int64` на 4 полях page_size. Проставить `(required)` на `project_id` и `(length)` на `page_token`/`filter` по образцу остальных доменов. Добавить `filter` с тем же whitelist `name=` в ListRepositories/ListTags. `ListReferrers` — либо cursor-пагинация как везде, либо явное «bounded full set» в описании RPC (сейчас это сказано только в комментарии, наружу не видно). `RegistryStatus` вложить в `Registry` (`Registry.Status`) — голые `ACTIVE`/`DELETING` тогда проходят префикс-правило линтера без исключения и совпадают со всеми доменами.

### 13. Pre-GA breaking-микробатч формы: `usedBy`, VolumeType, `updatedAt` (**ЛОМАЮЩЕЕ**)

**Почему:** Три мелких расхождения, каждое из которых после GA дорожает на порядок, а сейчас стоит один тикет. (1) `usedBy` у NetworkInterface — одиночный объект (`Reference used_by = 18`), у Address/SecurityGroup/Volume — `repeated` (проверено): общий рендерер «кем занят ресурс» падает на `.map()` внутри ОДНОГО домена, а комментарий в proto сам говорит «по образцу Address.used_by» — то есть это непреднамеренный дрейф. (2) Домен storage сознательно ушёл от «disk» к «Volume» — в этом и смысл раскола, — но каталог типов остался `DiskType` / `/storage/v1/diskTypes` / `Volume.disk_type_id`, при том что compute-зеркало называет то же значение `volumeTypeId`, а дизайн-канон — `VolumeType` с префиксом `vt-`: т

**Что сделать:** Одним тикетом до GA: `NetworkInterface.used_by` → `repeated` (сегодня 0..1, семантика не теряется, форма унифицируется); storage `DiskType`→`VolumeType`, `/storage/v1/diskTypes`→`/storage/v1/volumeTypes`, `Volume.disk_type_id`→`volume_type_id` (совпадёт с compute-зеркалом и каноном `vt-`); `updated_at` во все публичные ресурсы (аддитивно, truncate до секунд как `created_at`). Закрепить в api-conventions.md: обязательный envelope нового ресурса = `id/projectId/createdAt/updatedAt/name/description/labels`, `usedBy` — ВСЕГДА `repeated reference.Reference`, forward-зависимость — ВСЕГДА `reference.Referrer`; иначе разрыв воспроизведётся на следующем ресурсе.

### 14. `BootSource`: один дискриминатор и полная ссылка на образ из реестра (**ЛОМАЮЩЕЕ**)

**Почему:** Грамматика ОБЯЗАТЕЛЬНОГО поля самого частого Create закрепляется у пользователей прямо сейчас, и в ней две проблемы. Первая: на одном сообщении два поля означают одно и то же — строковый `type` (заполнять надо) и enum `image_kind` (заполнять НЕЛЬЗЯ, вход отвергается 400); пользователь, увидев типизированное поле, естественно выбирает его и получает ошибку. Вторая, важнее: для `registry.image` принимается ссылка вида `ml/bert-trainer:cu121` — БЕЗ идентификатора реестра, хотя канон адресации платформы (core rule #15) — `$domain/$registryId/$repo:$tag`, и реестров у проекта может быть несколько. Выразить «этот образ из реестра A, а не из B» физически нечем, а сервер не может однозначно разрешит

**Что сделать:** Оставить ОДИН дискриминатор: либо `image_kind` сделать единственным входом, либо `image_kind` перевести в `reserved` и оставить строковый `type` (сейчас enum на входе бесполезен). Для `registry.image` потребовать `registryId` — отдельным полем или в составе ссылки по каноничной форме `$registryId/$repo:$tag` — и отвергать неполную ссылку `INVALID_ARGUMENT` уже сейчас, пока пользователи не закрепили короткую форму.

## Осознанные отличия — не менять код, объяснить в доке

- Async-first как продуктовое решение. Мутации ВСЕГДА возвращают Operation, Watch-RPC не существует (поллинг List 2-5с или Operation.Get для in-flight). Ни одна линза не потребовала это менять — но в «Getting started» это должно стоять первым разделом с готовым фрагментом поллинга, иначе async читаетс
- `Operation.done` = durability предмета мутации, а не видимость downstream-эффекта. Это осознанный контракт (ban #9; confirm-gate на видимость owner-tuple был удалён по system-design-review, потому что рождал phantom-ресурс). Объяснить в доке следствие для клиента: доступ создателя к свежему ресурсу 
- Registry Repository адресуется натуральным ключом (именем) в URL и pull-пути и имеет `:rename` — прямое отступление от core rule #15. Решение защитимо (совместимость с типовым клиентским инструментарием контейнерных реестров; opaque id в pull-пути сломал бы экосистему), но нигде на публичной поверхн
- Ресурсы VPC не несут `status` намеренно: у Network/Subnet/SecurityGroup/RouteTable нет provisioning-жизненного цикла, наблюдаемое состояние — Operation (у SecurityGroup поле было и снято через `reserved`). Это правильный способ отклоняться (фейковый always-ACTIVE был бы хуже), но сегодня это знание 
- `GET /operations/{id}` без префикса `/<service>/v1/` — намеренная форма, а не недосмотр: Operation единственный кросс-сервисный ресурс, gateway фанаутит по 3-символьному префиксу id, и «своего» сервиса у него нет. Дефект здесь один и он в доке: docs-site публикует `GET /operation/v1/operations/{id}`
- Ось размещения (geo Region/Zone) читается любым аутентифицированным тенантом без project-scope Check — задокументированное исключение (иначе zero-binding тенант получал бы 403 ещё на этапе выбора zoneId). Объяснить это в публичной доке рядом с каталогом зон, иначе «почему этот эндпоинт не требует пр
- Две проекции ресурса (публичная lean + Internal* с инфра-полями) — намеренная защита: placement по железу, underlay, host-интерфейсы и числовые инфра-идентификаторы живут только на :9091. Без объяснения отсутствие этих полей на публичном ресурсе читается как «данных нет». Добавить в докcайт короткий
- `filter` — намеренно узкий whitelist (`name=`), а не язык запросов; `page_token` — opaque; порядок всегда `(created_at, id) ASC`. После правки текстов (рек. №4) это надо не спрятать, а объявить: одна грамматика, один текст ошибки на мусор, предсказуемая пагинация. geo сознательно не отдаёт filter-DS
- Специализированные RPC IAM (`:expandAccess`, `:listSubjectPrivileges`, `:listAssignableRoles`) — не варианты List, а вычисляемые проекции доступа. Вынести их в докcайте в отдельный раздел «аналитика доступа», чтобы они не читались как шесть способов сделать одно и то же (см. rejected — заменять их g
- Стратегия strangler compute→storage: назвать её вслух — какие ресурсы канонические, какие уходят, в какой фазе снимаются, таблица соответствия полей. Пока это живёт только во внутреннем плане, пользователь видит две равноправные ветки (см. рек. №2).
- id-префиксы: `epd` — это и Disk, и compute-Operation; `fd8` — и Image, и Snapshot; сосуществуют legacy-слитная форма, hyphen-форма (`ins-`, `mt-`) и geo-слаги. Докстринг pkg/ids обещает «тип ресурса читается по префиксу» — это неправда для пересекающихся префиксов. Привести докстринг к реальности НЕ

## Отклонено синтезом (противоречит принципам продукта)

- «Отдавать машиночитаемый reason-токен (`ACCESS_PROPAGATING` / `RESOURCE_NOT_READY`) в `google.rpc.ErrorInfo` на 403/404, чтобы клиент ретраил по признаку» (conventions-gap, first-hour-dx). ОТКЛОНЕНО: различимый токен на deny — это existence-oracle. security.md §6 требует, чтобы hide-existence-отказ 
- «Реализовать `order_by`» (conventions-gap, consistency — как одна из трёх опций). ОТКЛОНЕНО как направление: пагинация намеренно cursor-based на `(created_at, id) ASC` с opaque `page_token`; вторая ось сортировки либо ломает стабильность курсора, либо требует второго курсорного ключа на каждый допус
- «Заменить `AccessBindingService.ListByScope` / `ListBySubject` / `ListByRole` на generic `List?filter=subjectId=…`» (consistency). ОТКЛОНЕНО: каждая из этих RPC несёт СВОЙ `scope_extractor` в permission-catalog — именно так энфорсится object-scoped authz (security.md §3, анти-BOLA): caller проверяет
- «Добить per-resource `:listAccessBindings`/`:setAccessBindings`/`:updateAccessBindings` до всех ~20 остальных ресурсов» (consistency — как одна из двух опций). ОТКЛОНЕНО: AccessBinding принадлежит iam (карта владельцев, data-integrity.md §5); размазывание записи грантов по 7 сервисам множит authz-wr
- «`/operations/{id}` должен стать `/operation/v1/operations/{id}` ради единообразия с `/<service>/v1/<resource>`» (consistency). ОТКЛОНЕНО в части мотивировки: Operation — намеренно единственный кросс-сервисный ресурс, gateway маршрутизирует его по префиксу id, владеющего сервиса у него нет, и сервис
- «Мигрировать все id-префиксы на hyphen-канон и выдать мнемоничные префиксы всем ресурсам сразу» (resource-model). ОТКЛОНЕНО в объёме: B3 прямо задаёт going-forward-модель — router принимает ОБЕ формы аддитивно, а сервисы мигрируют свой префикс ПО ОДНОМУ в собственном редизайне; big-bang ломает все с
- «Привести админ-каталоги к синхронной форме, раз storage DiskType и vpc AddressPool уже отвечают ресурсом» (consistency — как одна из двух опций). ОТКЛОНЕНО в этом направлении: ban #9 говорит, что мутации возвращают Operation, и 2 из 4 админ-каталогов (geo Region/Zone, compute MachineType) это соблю

## Затронутые сущности vault
- [[audit-divergence-redesign-vs-main]] · [[redesign-2026]]

#kacho-proto #kacho-api-gateway #kac #docs #conventions #architecture
