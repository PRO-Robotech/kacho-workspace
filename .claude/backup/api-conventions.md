# Архив: api-conventions.md

Снято 2026-09-20. Норма живёт в `.claude/rules/api-conventions.md`.
Здесь: классы C (процесс вокруг кода) и D (замеры, доводы, отменённое, пересказы),
КРОМЕ записей, несущих названный гейт, — те остались нормами в корпусе.

## api-historical-measures

> [!note] Расхождение, из которого выведено — измерено, а не предположено
> На `origin/main` валидаторов имени было **четыре**, и они разошлись по трём осям:
> `Name` не допускал ни заглавных, ни подчёркивания; `NameVPC` допускал оба; `NameCompute` —
> подчёркивание; `NameGateway` — ни того, ни другого. Пустую строку допускали **все четыре**,
> кроме базового. Следствие в хранилище: среди уникальных индексов имени полных было **5**,
> у них пустое имя занимало слот, у частичных — нет. Наблюдаемо для арендатора: вторая сеть
> с пустым именем в проекте получала `409`, вторая подсеть — нет. Предмет и предикат
> снятия — задача продукта #715.

## api-resource-structure

## Структура ресурсов — проектируем удобно

Состав ресурсов/методов проектируем в чистой форме под задачу, не копируя ничей
чужой API: `NetworkInterface` — first-class ресурс VPC (ENI-подобная модель, NIC
отдельно от Instance); `AddressPool` — admin-only ресурс (Internal*); oneof/replace-
семантика там, где удобнее (напр. AddressPool split v4/v6, KAC-71). Осознанные
дизайн-решения документируй в `docs/architecture/` соответствующего сервиса.

## api-flat-message / api-service-template — примеры формы (protobuf)

```protobuf
message Instance {
  string id = 1;
  string project_id = 2;
  google.protobuf.Timestamp created_at = 3;
  string name = 4;
  string description = 5;
  map<string,string> labels = 6;
  string zone_id = 7;
  Status status = 10;        // enum, не nested message
  // ...domain-specific поля плоско
}
```
```protobuf
service InstanceService {
  rpc Get(GetInstanceRequest) returns (Instance);                  // sync
  rpc List(ListInstancesRequest) returns (ListInstancesResponse);  // sync
  rpc Create(CreateInstanceRequest) returns (operation.Operation); // async
  rpc Update(UpdateInstanceRequest) returns (operation.Operation); // async
  rpc Delete(DeleteInstanceRequest) returns (operation.Operation); // async
}
```

## api-subscription-axes / api-ban-must-expire — врезка целиком (замеры, класс)

> [!important] А вот подписка на изменения РЕСУРСОВ существует
> Платформа несёт **единую форму подписки** на изменения ресурсов, объявленную **однажды** —
> `proto/corelib/subscription/subscription_service.proto`, сервер `corelib/subscription/`
> в единственном экземпляре:
>
> | ось | что несёт |
> |---|---|
> | глагол | **один** на всех владельцев: `InternalSubscriptionService/Subscribe`, server-stream |
> | фильтр | три **иммутабельных** оси конъюнкцией: виды · проект · идентификаторы |
> | возобновление | непрозрачная позиция либо якорь (начало · текущий конец) |
> | сужение | пообъектное на **каждой отдаваемой строке** (`scope_filtered`), не один вопрос при открытии |
>
> **Единственность держится предикатом:** `git grep -h 'returns (stream' -- proto` → **1**
> (замер по стволу продукта `a9cc0391f`, 2026-08-29).
>
> **Проекция потока в браузер — в стволе продукта её ещё нет**: каталога проекции у края на
> `a9cc0391f` нет ни одним файлом (предикат в дереве продукта:
> `git ls-tree -r origin/main --name-only | grep -c subscriptionstream` → 0; сам путь здесь
> намеренно не пишется координатой — цитата мёртвого адреса читается проверкой свежести как
> живое утверждение). Контракт и сервер — факт ствола, край — нет.
>
> **Класс, ради которого врезка оставлена:** утверждение «такого механизма нет» **пережило
> свой предмет** и продолжало грузиться в окно целиком — до 2026-09-17 `@import`-ом в каждую
> сессию, с 2026-09-17 предзагрузкой тем агентам, за кем правило закреплено
> (`.claude/rules/MANIFEST.md`): адрес сузился, срок жизни ложного утверждения — нет. Тот же класс нашёлся
> тогда же в клиентской документации — четырьмя страницами. Заводя запрет, спроси, чем он
> **истечёт**, когда предмет появится.

## api-operation-done — элаборация и инцидент

(а) переопределяет контракт Operation (ban #9 — предмет = «создать Network», не «распространить
FGA-tuple»); (б) на fail-closed рождает **phantom-ресурс** (row закоммичен, имя занято UNIQUE,
но op=ERROR → клиент видит fail → retry ловит `AlreadyExists` → get воспринимает как 404); (в)
конвертирует ограниченный read-after-write лаг в неограниченный hard-fail под нагрузкой на
downstream. Kachō **eventually-consistent by design** (async Operation, polling, replica isolation):
side-effect материализуется в ограниченном окне (at-least-once outbox+drainer+reconciler), а
«создал→сразу мутирую» обеспечивается **bounded client-retry** на кратком 403/404-окне, НЕ серверным
confirm-барьером. Инцидент owner-tuple-opgate (2026-07): confirm-gate на видимость owner-tuple
удалён по system-design-review как ban #9-нарушение (см. `data-integrity.md` cross-domain authz).

## api-id-newid — алиасы фундамента

(Фундамент — отдельный репозиторий `PRO-Robotech/corelib`; прежние имена `kacho-corelib` и
каталог `pkg/` монорепо в старых записках означают его же.)

## api-hyphen-prefix — нюансы миграции

Router `corevalidate.ResourceID` классифицирует **обе** формы **аддитивно** (legacy-приём не
отзывается): крокфорд-тело дефиса не содержит → дефис = однозначный дискриминатор новой формы.
**`NewID`-генерация ещё НЕ мигрирована** (эмитит legacy 3-char) — Phase-0-фундамент только учит
router принимать hyphen **вперёд** миграции сервисов. (going-forward, B3)

## api-http-status-table — таблица, 412-объяснение, применение, замер

| gRPC-код | HTTP | gRPC-код | HTTP |
|---|---:|---|---:|
| `OK` | 200 | `RESOURCE_EXHAUSTED` | 429 |
| `INVALID_ARGUMENT` | **400** | `FAILED_PRECONDITION` | **400** |
| `OUT_OF_RANGE` | 400 | `ABORTED` | 409 |
| `NOT_FOUND` | 404 | `ALREADY_EXISTS` | 409 |
| `PERMISSION_DENIED` | 403 | `UNIMPLEMENTED` | 501 |
| `UNAUTHENTICATED` | 401 | `UNAVAILABLE` | 503 |
| `DEADLINE_EXCEEDED` | 504 | `INTERNAL`/`UNKNOWN`/`DATA_LOSS` | 500 |
| `CANCELED` | 499 | | |

**`FAILED_PRECONDITION` — это 400, а НЕ 412.** Совпадение имён («precondition»)
обманчиво, и библиотека оговаривает это своим комментарием в самой ветке: `412
Precondition Failed` — про условные заголовки запроса (`If-Match`, `If-None-Match`),
а не про состояние ресурса. **412 не производится краем ни для одного кода**, значит
у кейса, ожидающего 412, нет производителя, а у толерантности `oneOf([400, 412])` —
предмета: она перечисляет исход, которого не бывает.

> Выведено 2026-08-04 из двух упавших утверждений (`IAM-USR-BLK-NEG-PENDING`,
> `IAM-USR-UBK-NEG-PENDING`): сервер был прав — `FAILED_PRECONDITION` + текст
> `"... is not active"`, — а кейс ждал 412. Перепись по дереву показала, что
> предметом были не два кейса: 13 строк документации iam объявляли
> `FAILED_PRECONDITION → 412` таблицами ошибок, и ни одна не могла покраснеть.

## api-b4-recorded-exceptions — записанные исключения (nlb, iam)

> [!note] Задокументированное исключение: синтаксический gate на чужой ссылке (nlb VIP-источники)
> Consumer **вправе** прогнать чужой id через `corevalidate.ResourceID` перед peer-validate, но
> **только** если это записано как решение (запись в `docs/architecture/` сервиса + ссылка отсюда) и
> соблюдены все три границы: (а) **никакого утверждения о типе** — `corevalidate.ResourceID`
> **family-agnostic по контракту** (`expectedPrefix` не читается, см. её godoc), проверяет лишь
> членство первого сегмента в **платформенном** каталоге `ids.KnownPrefixes()`/`KnownHyphenPrefixes()`
> + config-extras, поэтому id с чужим для этого поля префиксом **проходит** к владельцу; (б) каталог —
> **общий corelib-артефакт**, а не копия приватного словаря владельца, поэтому предмет запрета
> («владелец сменил prefix → consumer отвергает валидный id») отсутствует by construction; (в)
> существование/тип/ownership/placement по-прежнему решает **только** владелец, а нерезолвящийся
> чужой id отвечает полосой peer-validate, **никогда** own-полосой `NOT_FOUND`.
> Мотив — что видит вызывающий: явно-не-id получает **терминальный** `INVALID_ARGUMENT
> "invalid <res> id '<X>'"` вместо retryable `UNAVAILABLE` («повтори позже» на ввод, который
> валидным не станет никогда) и вместо ложного `"<res> <X> not found"` — контракт-тона
> **отсутствия ресурса** на строку, которая ресурсом быть не может. Landed:
> nlb `v4Source/v6Source.subnetId`/`.addressId`
> (`services/nlb/docs/engineering/architecture/08-known-divergences.md` §«Формат чужого id (VIP-источники)»);
> прочие чужие id nlb (`projectId`/`regionId`/`securityGroupIds`/instance/nic) — existence-only.
> **Молчаливое** отступление (проверка есть, записи нет) остаётся нарушением B4.
>
> **Второе записанное отступление — iam, СВОИ идентификаторы (2026-08-31, задача продукта
> #1767).** Сервис судит свои id **префикс-строгой** проверкой, а не family-agnostic: **51**
> вызов в 48 файлах. Отвергнуто **замером**: проверки различаются по трём осям, решающая —
> **пустая строка**, платформенная её **пропускает**, поэтому замена завела бы отказ с
> вырезанным id (`"Account  not found"`) сразу в 51 место — тот самый дефект, который эта же
> конвенция называет ниже. Довод взят из границ исключения выше: тип решает **только
> владелец**, а владелец здесь iam. Чужие id сервис не судит **вовсе** (0 из 51).
> Запись — страница продукта в `kaname`, `docs/content/`;
> предикат пересмотра **внешний**: перевод любого из семи префиксов на дефисную форму
> (строгая пинит длину) либо объявление family-agnostic обязательной и для владельца.

## api-reason-both-sides — замер split по обеим сторонам

Split энфорсится **на обеих сторонах**: geo Region/Zone.Get **direct** → `RESOURCE_NOT_FOUND`/NOT_FOUND
(GEO-1-34/35); consumer (vpc/compute/nlb), валидируя `zoneId`/`regionId` **peer** через geo, на geo-miss
маппит в `PEER_RESOURCE_MISSING`/FAILED_PRECONDITION.

## api-examples-carry-outcome — примеры исходов и перемер эфемерного lifecycle

Выведено из семи мест за одну развёртку (2026-07-27/28): `dns_record_specs`
у адреса (домена DNS в сервисе нет вовсе — **снят с контракта**, номер и имя
зарезервированы), легаси-поля создания машины (при том что док сервиса **заявлял
отказ** — **сняты**: в `CreateInstanceRequest` их номера и имена стоят в `reserved`;
число «шесть» — из той развёртки, здесь не перемерялось), `order_by` в семи
списочных запросах (**снят**), зоны типа диска (**реализованы**), эфемерный жизненный
цикл репозитория (**отвергается явно** — исход 2).

> [!note] Пример «эфемерный жизненный цикл репозитория» пережил свой предмет — перемерено 2026-08-08
> Дерево (`project/kacho` @ `6b1293713`): вход отвергается синхронно, до любой записи —
> `services/registry/internal/apps/kacho/api/registry/create_repository.go:66`
> (`validateRepoLifecycle`, принимаются только омит и `DURABLE`); уже сохранённые строки
> нормализованы миграцией
> `services/registry/internal/migrations/0012_repository_lifecycle_durable_normalize.sql`.
> Предикат: `git grep -n -i lifecycle -- services/registry/internal/apps/kacho/api/registry/create_repository.go`
> и `git ls-files services/registry/internal/migrations | grep lifecycle`.
>
> Пять из семи исходы несли, два — нет, и именно безысходные читались как
> открытые (устаревший пример грузится агенту целиком вместе с правилом). Закрывая такое
> поле, правь и то место, которое им иллюстрировалось.

## api-ref-resourceref / api-ref-ocireferrer — детали редизайна

`iam.v1.ResourceRef` живёт в `authorize_service.proto` (пакет `kacho.cloud.iam.v1`);
переиспользуется `AccessBinding.target` **в том же пакете** через import — БЕЗ relocation
(F8 iam-редизайн добавляет поле; wire/Go-тип `iamv1.ResourceRef` уже доступен, buf-clean).
`OciReferrer`/`ArtifactRef` сейчас — `Referrer` в пакете `kacho.cloud.registry.v1` (FQN
отличается от generic — коллизии нет, только читаемостная неоднозначность). Каноничный
rename → `OciReferrer` вводится в **REG-2** (buf-breaking, registry-домен) — Phase-0 НЕ
добавляет мёртвый скелет (LEAN, ban #11).

## api-repeated-order-sign — замер nlb TargetGroup.targets (A)

**Что ломается у вызывающего.** Клиент, ведущий состояние (Terraform, консоль,
синхронизатор), сверяет **по индексу**. Ответ, переставивший два элемента, читается как
«элемент 1 изменил адрес, элемент 2 изменил вес» — клиент откатывает то, что сам только что
записал, либо останавливается с ошибкой о собственной несогласованности.
Наблюдалось: `nlb` `TargetGroup.targets`, две цели одним запросом — ответ вернул их в
обратном порядке (`services/nlb/internal/repo/kacho/pg/target_group_repo.go`, чтение
целей упорядочено по времени создания и идентификатору). Перечня по дереву **нет**:
`repeated`-полей в контрактах **218** (предикат: `grep -rho '^\s*repeated ' proto/kacho
--include=*.proto | wc -l`), сплошная разметка — отдельная работа.

## api-projection-holder — замер nlb TargetGroup.targets (B)

Наблюдалось: тот же `nlb` `TargetGroup.targets` — одиночное чтение подгружает цели
inline, списочное не подгружает вовсе.

## api-field-two-questions — как применять при заведении поля

Заводя `repeated`-поле или новую проекцию, ответь письменно на два вопроса и положи ответ
в комментарий контракта: значим ли порядок и какие чтения это поле заполняют. Ответ
«неважно» означает «набор» и «все» — и это тоже надо написать, иначе следующий вызывающий
примет умолчание за обещание.

## api-regression-two-levels — замер покрытия по сервисам

Замер 2026-08-07 по дереву `main` (ориентир, не гейт): пообъектную пробу
`TestListPaginationFormatCheckedBeforeIdentityShortCircuit` несут vpc — **7** файлов и
iam — **6**; у geo, compute, storage, nlb, registry — **0**. Свойство дерева держит AST-гейт,
а не перечень per-service юнитов и не звание эталона: звание ничего не роняет.

## api-unimplementable-holder — замеры (административный глагол, копирование)

У одного административного глагола таких величин оказалось **три** — идентификатор, номер
ревизии и состояние, — и каждая требовалась от вызывающего, тогда как вставка назначает их
сама и присланное отвергает явно. Исполнимого входа не существовало **ни для одной**. Рядом,
у двух глаголов копирования, был тот же класс с другой стороны: непосредственного родителя
копии **записывала вставка**, но этот вид происхождения не признавали ни проверка домена, ни
контракт, ни путь чтения, — и оба глагола не работали с момента заведения. Почему это не
видно в обзоре изменения: код собирается; обе проверки по отдельности защитимы; тип поля
ничего не запрещает.

## api-written-not-read — третий признак того же семейства

> [!note] Третий признак того же семейства: значение, которое ПИШУТ и не ЧИТАЮТ
> Столбец, который вставка заполняет, а проекция чтения не выбирает, невидим отовсюду: его
> нет ни в ответе, ни в объекте в памяти. Проверять надо **всю цепочку** — контракт, домен,
> запись, чтение, транспорт, — а не то место, где значение появляется. В этой сессии цепочка
> обрывалась на контракте у одного ресурса и на чтении у другого, при том что три независимые
> поверхности (провайдер инфраструктуры, сквозной кейс и сам столбец) исходили из того, что
> поле есть.

## Снято 2026-09-26 (ws#780): сжатие корпуса под потолок check-06 на сведении волны 0 с 771

Сведённое дерево `778` × `771` дало 221 997 знаков при потолке 200 000 (решение владельца
2026-09-19); потолок не поднимался. Ниже — ПРЕЖНИЕ редакции строк, сжатых этим изменением,
дословно: доводы, замеры и пересказы канона уходят сюда, норма (id · императив · держатель ·
red) осталась в корпусе под тем же id.

**api-standard-methods** — прежняя редакция:

api-standard-methods · Get/List — sync, Create/Update/Delete — Operation; доп. действия — отдельный RPC с :verb · ЗАВЕСТИ api-standard-methods · red: Create/Update/Delete отвечает ресурсом вместо Operation

**api-gotcha-truncate** — прежняя редакция:

api-gotcha-truncate · .Truncate(time.Second) на КАЖДОМ ресурсе И под-записи; микросекунды БД не текут на wire · ЗАВЕСТИ api-gotcha-truncate · red: микросекунды из БД доехали до клиента

**api-gotcha-malformed** — прежняя редакция:

api-gotcha-malformed · corevalidate.ResourceID первым стейтментом RPC → InvalidArgument; без format-check malformed-id уезжает в repo.Get → NotFound (неверно) · ЗАВЕСТИ api-gotcha-malformed · red: malformed-id уехал в repo.Get и вернул NotFound

**api-id-addressing-dup** — прежняя редакция:

api-id-addressing-dup · адресация только по `id` (ban #15): immutable, глобально-уникален, идёт в URL/ссылки/authz-target; `name` косметический, в URL никогда; слаг в URL вместо id запрещён · ЗАВЕСТИ api-id-addressing-dup · red: слаг или `name` в URL либо в authz-target

**api-json-camel-dup** — прежняя редакция:

api-json-camel-dup · JSON (REST через api-gateway) — camelCase: `<resource>Id`, `projectId`, `createdAt` · ЗАВЕСТИ api-json-camel-dup · red: snake_case в теле REST-ответа

**api-name-rationale** — прежняя редакция:

api-name-rationale · сервер проставляет имя вместо требования (breaking change, адресация по id — ban #15); имя от id, не «первое свободное» — иначе check-then-act (ban #10); форма — чужой RFC 1123 DNS label, не переизобретается · ЗАВЕСТИ api-name-rationale · red: имя требуют от клиента либо выбирают «первое свободное»

(второй проход того же сжатия)

**api-subscription-axes** — прежняя редакция:

api-subscription-axes · глагол один на всех владельцев · фильтр три иммутабельных оси конъюнкцией (виды · проект · идентификаторы) · возобновление позицией или якорем · сужение пообъектное на каждой строке (`scope_filtered`) · TestSubscriptionShapeAxisLedgerCanFail · red: один вопрос доступа при открытии

(второй проход того же сжатия)

**абзац** — прежняя редакция:

## Пустое значение обязано означать «пусто» — иначе оно лжёт (обязательно, выведено 2026-08-12)
