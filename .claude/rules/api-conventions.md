---
name: rule-api-conventions
description: "Конвенции API Kachō"
---

**Архив:** `.claude/backup/api-conventions.md`

## Статус конвенции

api-preamble · конвенции продукта нормативны, не подражание чужим облакам; менять только осознанно · ЗАВЕСТИ · red: конвенция взята подражанием чужому облаку, а не решением

## Форма ресурса — flat message + Operations

api-flat-message · плоский message, domain-поля верхним уровнем; без spec/status/metadata/resourceVersion/generation/finalizers · TestApiSurfaceInjection_RealTreeIsSilent · red: K8s-энвелоп в контракте
api-service-template · Get/List — sync, Create/Update/Delete — Operation; доп. действия — свой RPC с :verb · TestSLP_OperationsLaneProducersAreCountedFromTheTree · red: sync-мутация
api-operation-shape · id, description, created_at, done, metadata:Any, oneof result{google.rpc.Status\ · Any}; клиент поллит OperationService.Get до done · red: TestOperationHandlerHasASingleSource | своя форма операции в домене

## Подписки на операции не существует

api-no-operation-subscription · только полл Get(id); подписки на операции нет; «без поллинга» = долгий Get с серверным сроком · TestSubscriptionFormIsDeclaredOnce · red: server-stream в операционном контракте
api-subscription-single-form · одна форма, объявлена однажды: corelib.subscription.InternalSubscriptionService/Subscribe · TestSubscriptionServerIsSingularAndLivesInTheFoundation · red: второй контракт или сервер потока
api-subscription-axes · глагол один на всех владельцев · фильтр — три иммутабельных оси конъюнкцией (виды · проект · идентификаторы) · возобновление позицией или якорем · сужение пообъектное на каждой строке (`scope_filtered`) · TestSubscriptionShapeAxisLedgerCanFail · red: один вопрос доступа при открытии
api-sub-no-name-filter · ни по имени, ни по меткам: событие несёт полное состояние · TestSubscriptionShapeAbsentAxisCanFail · red: фильтр по мутабельному name
api-sub-singularity-predicate · git grep -h 'returns (stream' -- proto → 1 · TestSubscriptionFormIsDeclaredOnce · red: второй stream в контрактах
api-polling-not-revoked · опрос остаётся штатным путём, не отзывается: подписка — второй путь, не замена · ЗАВЕСТИ · red: опрос снят как «заменённый подпиской»
api-ban-must-expire · называет, чем истечёт при появлении предмета · TestClientDocsDoNotDenyTheSubscriptionTheTreeHas · red: «такого механизма нет» после его появления
api-operation-done · = ресурс закоммичен, и только это; запрещено гейтить на видимость downstream (FGA-tuple, зеркало, drain outbox) · TestPublishedResourceIdIsGuardedByOperationOutcome · red: confirm-барьер рождает phantom-ресурс

## Naming / формат

api-json-camel-dup · JSON края — camelCase (`00-kacho-core.md#naming-json-camel`) · ЗАВЕСТИ · red: snake_case в теле REST-ответа
api-rest-paths · /<service>/v1/<resource>`, suffix-action через `:verb · TestDocsPagesAreReachableFromTheMenu · red: свой путь ресурса
api-standard-methods · то же, что `api-service-template` · ЗАВЕСТИ · red: Create/Update/Delete отвечает ресурсом вместо Operation
api-timestamp-truncate · .Truncate(time.Second) на каждом ресурсе И каждой под-записи · TestOperationTimestampsAreTruncatedEverywhere · red: микросекунды БД на wire
api-id-newid · corelib:ids.NewID(<prefix>) — префикс + 17 crockford-base32, тип читается по префиксу · TestCt2DocsIdForm · red: свой генератор id
api-id-addressing-dup · адресация — только по `id` (`00-kacho-core.md#ban15-id-addressing`), в URL, ссылках и authz-target · ЗАВЕСТИ · red: слаг или `name` в URL либо в authz-target
api-hyphen-prefix · форма `<prefix>-<crockford>`; каталог префиксов один — `ids.KnownHyphenPrefixes()` + KACHO_EXTRA_RESOURCE_ID_HYPHEN_PREFIXES; legacy-форма принимается аддитивно · TestCt2IdCanonHyphenMinting · red: свой список префиксов в сервисе
api-gotcha-truncate · то же, что `api-timestamp-truncate` · ЗАВЕСТИ · red: микросекунды из БД доехали до клиента

## Имя ресурса: одна форма, пустого не бывает (решение владельца 2026-08-18)

api-name-one-form · одна форма на всё дерево — DNS label RFC 1123 `^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$`, валидатор один · TestResourceNameFormIsDeclaredOnce, TestDeclaredNameFormMatchesTheEnforcedOne · red: второй валидатор «как общий, но ещё…»
api-name-never-empty · не существует: сервер проставляет производное от `id`; правка на пустое → INVALID_ARGUMENT · TestNameFormInjection_EmptyWalkIsNotSilentSuccess · red: строка с name = ''
api-name-signs · второй валидатор · строка с name='' · частичный UNIQUE WHERE name<>'' · умолчание со счётчиком/случайностью/проверкой-перед-вставкой · «invalid name» без поля и правила · TestNameFormDBCoverage_FailsOnInjectedDefect · red: любой из пяти
api-name-rationale · имя проставляет сервер, не требуя от клиента (breaking change; адресация по id — ban #15), от id, а не «первое свободное» (check-then-act — ban #10); форма — RFC 1123 DNS label, не переизобретается · ЗАВЕСТИ · red: имя требуют от клиента либо выбирают «первое свободное»
api-name-holder · утверждает обе стороны каждой оси: цифра первой принимается; заглавная, подчёркивание, точка, пустая, 64 символа отвергаются с именем поля · TestIntegration_NameForm · red: односторонняя проба

## Error-format

api-error-grpc-status · gRPC `status.Error(code,message)`; REST — {code,message,details}+google.rpc.Status · TestNoCaseAssertsAStatusTheEdgeCannotProduce · red: своя форма ошибки
api-error-codes-vocab · INVALID_ARGUMENT формат · NOT_FOUND нет · FAILED_PRECONDITION состояние · ALREADY_EXISTS UNIQUE · UNAVAILABLE peer (fail-closed мутации) · INTERNAL фиксированный текст без pgx/SQL · TestCheckViolationTone · red: SQL в сообщении клиенту
api-error-tone · часть контракта: `"<Resource> %s not found"`, `"<field> is immutable after <Resource>.Create"`; меняется только тикетом · TestOperationNotFoundHasOneProducer, TestOperationLaneMessageIsAssertedVerbatim · red: свой текст того же отказа
api-malformed-id-sync · corevalidate.ResourceID` первым стейтментом RPC → INVALID_ARGUMENT `invalid <res> id '<X>' · TestPhantomIdGateAttributesPollByOperationVariable · red: malformed уехал в repo.Get и вернул NOT_FOUND
### Gotcha'и (частые нарушения конвенций)

api-gotcha-malformed · то же, что `api-malformed-id-sync` · ЗАВЕСТИ · red: malformed-id уехал в repo.Get и вернул NotFound
api-gotcha-deferrable-fk · 23503 приходит из `tx.Commit()`: маршрутизируй commit-ошибку constraint-aware маппером с owner-id hint · — (КАНДИДАТ НА ГЕЙТ: маршрутизация commit-ошибки) · red: 23503 в INTERNAL вместо FailedPrecondition

### gRPC-код → HTTP-статус: таблица края, а не догадка кейса (обязательно)

api-http-status-table · у края нет своего WithErrorHandler, статус даёт `runtime.HTTPStatusFromCode`; FAILED_PRECONDITION = 400, не 412; 412 краем не производится вовсе · TestEdgeOwnStatusesStillHaveAProducer, TestNoCaseAssertsAStatusTheEdgeCannotProduce · red: кейс ждёт 412 или oneOf([400,412])
api-case-asserts-pair · утверждает ПАРУ: HTTP-статус и `code` из google.rpc.Status · TestFormParityRedsWhenTheCodeSetIsNotAnchoredToTheResponseCode · red: только статус или только код
api-no-oneof-mixing · не заводится ради удобства; исключение одно — authz-first 403\ · internal/repohygiene (form parity) · red: 404, разные линии со своими производителями | TestFormParityRedsWhenNegationIsReadAsAcceptance | oneOf по неопределённости отображения
api-table-edit-is-contract · правится тем же коммитом, что заведение WithErrorHandler · ЗАВЕСТИ · red: два места об одном отображении
### By-lane code-split — NOT_FOUND vs FAILED_PRECONDITION по линии резолва id (обязательно)

api-bylane-header · код "id well-formed, но не резолвится" зависит от линии резолва, а не от ресурса · ЗАВЕСТИ · red: код отказа выбран по ресурсу, а не по линии резолва
api-lane-direct-read · NOT_FOUND "<Resource> <id> not found" · TestOperationNotFoundDiscriminatorKnowsEveryLegalForm · red: FAILED_PRECONDITION на своём ресурсе
api-lane-peer-validate · нет или не то состояние у владельца → FAILED_PRECONDITION; владелец недоступен → UNAVAILABLE · TestHideExistenceParityResolvesByPackage · red: NOT_FOUND на чужой ресурс
api-format-check-own-only · только own-owned id; чужой id — existence-only peer-validate · TestProtoPrefixInjection_WrongPrefixIsFound · red: prefix-проверка чужого id
api-b4-recorded-exceptions · только записанное решением (docs/architecture сервиса + ссылка из правила) и в трёх границах: family-agnostic каталог · общий артефакт corelib · тип решает владелец · вниманием (запись в docs/architecture сервиса) · red: молчаливая проверка чужого id
api-resourceid-empty · несёт свой required-check → INVALID_ARGUMENT `"<field>: required"`, потому что `corevalidate.ResourceID` пустую строку пропускает · — (КАНДИДАТ НА ГЕЙТ: обязательное поле-ссылка без required-check) · red: "subnet  not found" с вырезанным id
api-reason-token · различается машинно по `reason` в rpc.Status.details: INVALID_RESOURCE_ID · RESOURCE_NOT_FOUND · PEER_RESOURCE_MISSING · PEER_RESOURCE_STATE · PEER_UNAVAILABLE; domain=`<service>.kacho.cloud`, metadata={resource_type,resource_id} · TestInjection_EmptyReasonIsAFinding · red: клиент парсит прозу message
api-reason-both-sides · утверждает И reason-token, И code, на обеих сторонах: владелец direct, потребитель peer · TestListReadRelationParity · red: assert только кода

## Принято-и-проигнорировано — ЗАПРЕЩЕНО (решение владельца 2026-07-28)

api-accepted-ignored · обязано иметь читателя в прод-коде своего сервиса · TestEveryDescriptorFieldHasAReader · red: геттера поля нет в не-тестовом дереве
api-outcome-implement · поле читается и меняет поведение · internal/repohygiene (descriptor field reader) · red: поле принято и не меняет ничего
api-outcome-reject · INVALID_ARGUMENT с именем поля, синхронно, первым стейтментом · TestClientTruthRefusalFieldName · red: тихий успех
api-outcome-remove · удалить из proto с `reserved` номера И имени, объявив ломающее изменение в коммите · TestClientDocsContractDrift · red: номер или имя переиспользованы
api-silent-accept-not-outcome · не исход · TestEveryDescriptorFieldHasAReader · red: успех на неприменённом параметре
api-examples-carry-outcome · каждый пункт несёт исход · ЗАВЕСТИ · red: безысходный пример читается как открытый дефект
api-default-outcome-remove · по умолчанию снять с контракта; подсистема заводится своим доменом, а не полем в чужом сообщении · ЗАВЕСТИ · red: поле «на будущее»

## update_mask discipline

api-mask-unknown · INVALID_ARGUMENT через `corevalidate.UpdateMask` с known-set · TestUpdateMaskKnownSetKnowsBothFormsOfAField · red: неизвестное поле применено
api-mask-immutable · INVALID_ARGUMENT "<field> is immutable after <R>.Create" · TestUpdateMaskFormParityGateCanFailAndCanStayQuiet · red: generic «unknown field»
api-mask-empty-full-patch · full-object PATCH: все mutable применяются, immutable из тела игнорируются · ЗАВЕСТИ · red: пустая маска трактуется как «ничего»
api-mask-mutable · применяется и валидируется по правилам Create · ЗАВЕСТИ · red: обход валидации через Update
api-mask-parity · одна на все ресурсы всех сервисов · TestUpdateMaskFormParityGateCanFailAndCanStayQuiet · red: своя семантика маски в сервисе
api-gotcha-immutable-first · immutable-switch ДО corevalidate.UpdateMask · TestUpdateMaskKnownSetKnowsBothFormsOfAField · red: immutable отвергнут как «unknown field»

## Reference-типы

api-ref-header · три семантики ссылки — три типа; переименование landed-типов запрещено, disambiguation — именами, не relocation · ЗАВЕСТИ · red: три семантики ссылки сведены к одному типу либо landed-тип переименован
api-ref-referrer · reference.Referrer{type,id,name°}, graceful-dangling: референт удалён → DETACHED, не паника; name° — output-only зеркало · TestDeletionRefusalGateFailsWhenTheLaneRidesAForeignSentinel · red: паника на удалённом референте
api-ref-resourceref · iam.v1.ResourceRef{type,id}` из закрытого FGA-словаря, БЕЗ `name · TestClientTruthRefusalFieldName · red: name в authz-таргете
api-ref-ocireferrer · OciReferrer/ArtifactRef в registry-домене · ЗАВЕСТИ · red: мёртвый скелет типа вперёд своего домена
api-ref-choice · dependency-handle → Referrer · authz-target → ResourceRef · OCI → OciReferrer; переименование landed-типов запрещено · — (КАНДИДАТ НА ГЕЙТ: overload одного типа в двух ролях) · red: один id в разных ролях одним типом

## Пустое значение обязано означать «пусто» — иначе оно лжёт

api-empty-means-empty · означает факт о ресурсе, а не умолчание · ЗАВЕСТИ · red: «порядок какой получился», «это чтение поле не заполняет»
api-repeated-order · ровно два состояния: упорядоченное (ORDER BY по колонке ПОРЯДКА, проба на ≥3 элементах) либо набор (сказано в комментарии поля) · — (КАНДИДАТ НА ГЕЙТ: 218 repeated-полей без объявленного порядка) · red: третье состояние
api-repeated-order-sign · ORDER BY created_at, id на строках одной транзакции: порядок решает крокфордов id · ЗАВЕСТИ · red: «стабильная сортировка», проверенная одним элементом
api-repeated-order-holder · у вызывающего — модель без индексов (SetNestedAttribute) + проба на переставленный ответ; у владельца — integration-проба на ≥3 элементах · ЗАВЕСТИ · red: сверка по индексу
api-projection-says · исходов три: заполнить · вынести поле из проекции контрактом · назвать в комментарии поля и документации ресурса · — (КАНДИДАТ НА ГЕЙТ: Get/List parity по полям одного message) · red: Get отдаёт массив, List — `[]` при одном message
api-projection-holder · читает один ресурс обоими путями и требует совпадения по объявленным полям · ЗАВЕСТИ · red: «лёгкий список» неотличим от потери данных
api-field-two-questions · в комментарии контракта письменно: значим ли порядок и какие чтения поле заполняют · — (КАНДИДАТ НА ГЕЙТ: комментарий контракта у repeated-поля) · red: ответ «неважно»

## Pagination / filter

api-pagination-cursor · cursor `(created_at, id)` ORDER BY ASC; `page_token` — opaque base64 {created_at,id} · TestPageCursorFormIsDeclaredOnce, TestEveryCursorPageReadGetsItsOrderFromAnIndex · red: offset или голый номер курсором
api-pagesize · corevalidate.PageSize: 0→50, max 1000; вне [0..1000] и мусорный токен → INVALID_ARGUMENT, не clamp · TestPaginationValidatorNamesHaveSubject · red: clamp вместо отказа
api-filter-whitelist · corelib/filter.Parse с whitelist полей · ЗАВЕСТИ · red: свободный предикат от клиента
api-pagination-before-shortcircuit · порядок: ValidatePagination(page_token,page_size) → listauthz-resolve → empty-grant short-circuit → repo · TestEmptyPageNeverPrecedesPaginationValidation · red: 200 {[]} на мусорный токен при пустом гранте
api-guard-same-function · стоит в ТОЙ ЖЕ функции, которая замыкается · TestEmptyPageNeverPrecedesPaginationValidation · red: guard в хендлере, замыкание в use-case
api-cursor-codec-single · зовёт тот же разбор page_token/page_size, что путь чтения · TestPageCursorFormIsDeclaredOnce · red: второй кодек, согласный с первым на валидном входе
api-regression-two-levels · парная проба use-case-уровня (один мусорный курсор у названного вызывающего и у замыкающегося) + положительный контроль, плюс tree-wide AST-гейт · TestEmptyPageNeverPrecedesPaginationValidation · red: одна сторона
api-unit-not-regression · регрессией на порядок не является · ЗАВЕСТИ · red: заголовок про порядок без вызывающего и без замыкания

## Неисполнимая возможность

api-unimplementable-header · исполнима хотя бы одним входом · — (КАНДИДАТ НА ГЕЙТ: пересечение required-домена и «assigned on insert») · red: поле требуют, а запись присланное отвергает
api-field-one-owner · проверка входа принимает её незаданной: 0 и пустая строка = «ещё не назначено»; отвергается только названное неверно · ЗАВЕСТИ · red: required на поле, которое назначает INSERT
api-unimplementable-predicate · пересечение git grep 'must not be supplied\ · is assigned on' -- */repo/*` и `git grep 'is required\ · red: must be positive' -- */domain/* по одному полю; один пример → перебрать весь вход глагола | ГЕЙТА НЕТ | проверка одного поля
api-unimplementable-holder · несёт сценарий, ВЫЗЫВАЮЩИЙ его минимально-законным входом · ЗАВЕСТИ · red: сценарий «создан ли ресурс» зелен при неработающем глаголе

## Поле контракта не выходит наружу, пока КРАЙ не пересобран (выведено 2026-08-13)

api-edge-rebuild · край перекатывается вместе с сервисом · .github/workflows (единое дерево сборки) · red: поле есть у сервиса и нет в теле ответа клиенту
api-written-not-read · проверяется вся цепочка: контракт → домен → запись → чтение → транспорт · TestEveryDescriptorFieldHasAReader · red: столбец пишут, а проекция чтения не выбирает
