---
title: RegistryService
aliases:
  - RegistryService (registry)
  - registry RegistryService
proto_file: kacho/cloud/registry/v1/registry_service.proto
category: rpc
backend: kacho-registry
backend_port: 9090
visibility: public
domain: registry
related_resource: "[[resources/registry-repository]]"
methods_count: 15
async_methods: 8
status: stable
verified_against: "перечень RPC и REST-маршруты сверены с proto и обработчиками PRO-Robotech/kacho@ee679467 в ОБЕ стороны 2026-08-06 (ветка agent/ci-github-hosted-runners, потомок ствола redesign/integration@50e5e624); тексты ошибок и поля запросов построчно не пересматривались"
tags:
  - rpc
  - kacho-registry
  - registry
---

# RegistryService (registry)

**Контракт**: `proto/kacho/cloud/registry/v1/registry_service.proto`
**Backend**: сервис `kacho-registry`, публичный листенер **:9090**
**Ресурсы**: `Registry` (записки нет) · [[resources/registry-repository]] · `Tag` (записки нет)

Управляющая поверхность реестра. **Тянуть и класть образы здесь нельзя** — это делает
отдельная поверхность OCI Distribution на собственном листенере (см. §«Три поверхности»).

Записка заведена 2026-08-06: до неё на неё ссылались [[resources/registry-repository]] и
[[KAC/RG-1-registry-repository-overlay]], а самой записки не существовало.

## Методы (15)

### Реестр как ресурс

| Метод | Ответ | Sync/Async | REST |
|---|---|---|---|
| `Get` | `Registry` | sync | `GET /registry/v1/registries/{registry_id}` |
| `List` | `ListRegistriesResponse` | sync | `GET /registry/v1/registries` |
| `Create` | `Operation` | async | `POST /registry/v1/registries` |
| `Update` | `Operation` | async | `PATCH /registry/v1/registries/{registry_id}` |
| `Delete` | `Operation` | async | `DELETE /registry/v1/registries/{registry_id}` |
| `ListOperations` | `ListRegistryOperationsResponse` | sync | `GET …/{registry_id}/operations` |

### Репозиторий и теги (вложенные в реестр)

| Метод | Ответ | Sync/Async | REST |
|---|---|---|---|
| `GetRepository` | `Repository` | sync | `GET …/{registry_id}/repositories/{repository=**}` |
| `ListRepositories` | `ListRepositoriesResponse` | sync | `GET …/{registry_id}/repositories` |
| `CreateRepository` | `Operation` | async | `POST …/{registry_id}/repositories` |
| `UpdateRepository` | `Operation` | async | `PATCH …/{registry_id}/repositories/{repository=**}` |
| `DeleteRepository` | `Operation` | async | `DELETE …/{registry_id}/repositories/{repository=**}` |
| `ListTags` | `ListTagsResponse` | sync | `GET …/{repository}/tags` |
| `DeleteTag` | `Operation` | async | `DELETE …/{repository}/tags/{tag}` |
| `RenameRepository` | `Operation` | async | `POST …/{repository=**}:rename` |
| `ListReferrers` | `ListReferrersResponse` | sync | `GET …/{repository=**}/referrers` |

Форма выдержана: чтение синхронно, **любая** мутация возвращает `Operation` (ban #9).
Метаданные операций — `Create/Update/DeleteRegistryMetadata`,
`Create/Update/DeleteRepositoryMetadata`, `DeleteTagMetadata`, `RenameRepositoryMetadata`.

> [!important] Порядок объявления RPC в этом service ЗНАЧИМ — не пересортировывать
> `{repository=**}`-маршруты Get/Update/DeleteRepository ловят всё, включая
> `…/tags`, `…/referrers` и `:rename`. Край пробует хендлеры в порядке, обратном
> регистрации, а регистрирует их в порядке объявления RPC — значит объявленный
> **позже** пробуется **раньше**. Поэтому catch-all'ы стоят в файле **выше**
> вложенных маршрутов, и именно поэтому алфавитная или CRUD-сортировка этого
> блока сломала бы REST-роутинг. Предупреждение стоит и в самом proto.

## Идентификаторы

- `Registry.id` — префикс **`reg`**, неизменяем, глобально уникален (ban #15).
- `Operation.id` реестра — префикс **`rop`**, намеренно отличный от `reg`: край
  маршрутизирует `OperationService.Get` к сервису по первым трём символам, и
  совпадение с префиксом ресурса лишило бы его дискриминатора.
- `Repository` и `Tag` собственного идентификатора **не имеют**: натуральный ключ —
  `(registry_id, name)` и `(registry_id, repository, tag)`. Адресация в pull-пути —
  `<домен>/<registryId>/<repo>:<tag>`, то есть по неизменяемому `reg`-id, а не по
  имени реестра (имя меняется свободно и в путь не попадает).

## Кто и как авторизуется

Записи в каталоге прав стоят **не у всех** методов, и это осознанно, а не пробел:

- **Реестр как объект** — обычный per-RPC Check на краю: `v_get` / `v_update` /
  `v_delete` / `v_list` на `registry_registry:<id>`, создание — `editor` на
  родительском проекте (объекта реестра ещё нет). `Update` и `Delete` несут
  `hide_existence`: отказ приходит той же формой, что настоящее отсутствие.
- **`List`** объявлен `<exempt>` — единого объекта, про который можно задать один
  вопрос, у списка нет. Отбор идёт **по данным**: страница читается курсором из своей
  БД, затем по каждой строке задаётся вопрос модели прав. Проверка формата страницы
  (`page_size`, `page_token`) идёт **до** отбора, поэтому мусорный курсор получает один
  и тот же ответ у любого вызывающего. Аутентификация при `<exempt>` не снимается.
- **Все девять repository-методов** объявлены `<exempt>` по той же причине, но более
  жёсткой: объект прав здесь **составной** — `registry_repository:<registryId>/<repo>`,
  а извлекатель области на краю берёт ровно одно поле верхнего уровня и такую пару
  выразить не может. Проверку делает сервис, на составном объекте.

> [!important] «В proto exempt» ≠ «без авторизации»
> Ровно та же тонкость, что у [[vpc-network-service]], и здесь она касается **десяти
> из пятнадцати** методов. `<exempt>` говорит лишь о том, что решение принимает не
> край. Утверждать по одному proto «этот метод не авторизован» — ошибка чтения.

**Повышение видимости до публичной — отдельный уровень.** Любой путь, которым
принципал сам приводит репозиторий к `PUBLIC` (создание с явной публичностью,
переключение у существующего, смена умолчания реестра), требует уровня администратора
реестра и отвечает честным `PERMISSION_DENIED` — не скрытым отсутствием: вызывающий на
этот момент уже прошёл предыдущий гейт, и прятать от него объект незачем.
Умолчание — `PRIVATE`. Смена умолчания у реестра **не перекрашивает** уже существующие
репозитории. Ребро для анонимного чтения — [[edges/registry-to-iam-anon-public]].

**Кэш вердиктов.** Сервис кэширует только положительные ответы модели, ключ —
(субъект, отношение, тип объекта, id объекта), срок жизни задан одной ручкой на весь
процесс. Отрицательный ответ и ошибку хранилища прав не кэширует никогда; ошибка —
fail-closed (`UNAVAILABLE`), не «разрешено». Срок жизни кэша и есть окно, в течение
которого отозванное право ещё действует: registry на оповещения об инвалидации не
подписан.

## Три поверхности, которые легко перепутать

| Поверхность | Что делает | Где |
|---|---|---|
| `RegistryService` (эта записка) | CRUD реестров, репозиториев, тегов; метаданные | gRPC **:9090** → REST края |
| [[registry-internal-registry-service]] | сборка мусора, инфра-статистика | gRPC **:9091**, только внутрикластерно |
| OCI Distribution (data-plane) | `docker login` / `push` / `pull`, манифесты и блобы | **отдельный** HTTP-листенер |

Data-plane — не третий gRPC-метод и не часть этого контракта: собственный листенер,
собственный порядок аутентификации по Bearer, собственный отказ. Удаления образа там
нет вовсе — единственный разрушающий путь к содержимому лежит через `DeleteTag`
здесь. Подробности — [[edges/registry-dataplane-public-tls]] и
[[edges/registry-to-iam-jwks-fetch]].

## Что стоит знать до правки

- **Блобы и манифесты в БД не лежат.** `Repository` и `Tag` — это склейка durable-слоя
  намерения арендатора (описание, метки, публичность), который живёт в БД сервиса, и
  read-only проекции из движка хранения. Отсюда несимметричность: репозиторий с
  durable-слоем переживает опустошение, а заведённый первым же push'ем — исчезает
  вместе с последним тегом.
- **`DELETING` у реестра терминален** (forward-only): возврата в `ACTIVE` нет. Иначе
  частичный UNIQUE по `(проект, имя)` столкнулся бы с повторным созданием реестра под
  тем же именем.
- **Неизменяемы после создания**: `id`, `project_id`, `region_id`, `placement_type`.
  Они внесены в известный набор маски как жёстко-неизменяемые — то есть названные в
  `update_mask` дают конвенционный текст про неизменяемость, а не общий «неизвестное
  поле» (порядок проверок по `api-conventions.md`).
- **`name` репозитория правится только через `RenameRepository`**, не через `Update`.
  Жизненный цикл репозитория — системное поле и в маску не принимается.
- **`ListReferrers` не листается вовсе**: у запроса нет ни `page_size`, ни
  `page_token` — набор для одного subject ограничен по построению. Subject без
  референтов отдаёт пустой список, а не 404.
- **Registry всегда `REGIONAL`** (anycast), зоны не несёт → из зональной проверки
  когерентности исключён by construction. Существование региона проверяется у владельца
  ([[edges/registry-to-geo-region-validate]]), не выводится из имени.

## Соседи по рантайму

`registry → geo` (существование региона), `registry → iam` (per-RPC Check, существование
проекта, регистрация владельца, публичные ключи для data-plane). Обратно registry не
зовут — ацикличность держится.

## См. также

[[registry-internal-registry-service]] · [[resources/registry-repository]] ·
[[edges/registry-to-iam-fga-register]] · [[edges/registry-to-iam-anon-public]] ·
[[edges/registry-to-geo-region-validate]] · [[edges/registry-dataplane-public-tls]] ·
[[edges/compute-to-registry-image-resolve]] · [[KAC/RG-1-registry-repository-overlay]] ·
[[rpc/operation-service]]

#rpc #kacho-registry #registry
