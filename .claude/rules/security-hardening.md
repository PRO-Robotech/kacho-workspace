---
name: rule-security-hardening
description: "Безопасность: hardening-классы, которые уже стоили нам дефекта"
---

**Архив** — доводы, замеры, снятые редакции; **НЕ действующая норма**, цитировать как норму нельзя: `.claude/backup/security-hardening.md`

# Безопасность: hardening-классы, которые уже стоили нам дефекта

## Hardening-инварианты (выведены из audit-раундов — не повторять эти классы)

hard-no-err-echo · возвращать фиксированный opaque-текст; err.Error() в codes.Internal запрещён на ОБОИХ листенерах · TestErrorMappersTailReturnsAFixedText · red: status.Error(codes.Internal, err.Error())
hard-regression-asserts-message · утверждать текст сообщения, не только код · TestStatusTailGateCatchesAnEchoedError · red: assert только на codes.*
hard-no-pii-in-logs · не писать email/phone/token/личные данные end-user; коррелировать по external_id; исключение — единичный operational-config · ЗАВЕСТИ hard-no-pii-in-logs · red: PII в аргументе log.Info/Error
hard-pii-regression-test · нести тест NotContains(log, <PII>) · go test · red: нет утверждения о содержимом лога
hard-scope-extractor-object-scoped · нести scope_extractor (object_type + from_request_field) в permission-catalog · TestAnnotationLaneInjection_PermissionWithoutRelationIsAFinding · red: запись каталога с permission без relation/scope
hard-catalog-complete · иметь запись на каждый выставленный RPC; отсутствие ⇒ AUTHZ_DENIED · TestCatalogReachability_EveryRowResolvesToAServedMethod · red: смонтированный метод без записи
hard-catalog-copies-byte-identical · генерировать из proto (make permission-catalog); копии iam-seed и gateway-middleware — побайтово равны · make -C gateway permission-catalog-check · red: staleness или дрейф копий
hard-catalog-generator-anchor · генератор каталога привязан к proto-дереву — перецентрализовал дерево, чини генератор тем же коммитом · internal/repohygiene/cataloganchorcoordinate_injection_test.go (TestCatalogAnchorCoordinateNamesSomethingThatExists) · red: координата якоря называет путь, которого в дереве нет
hard-misleading-security-comment · отражать реальное поведение кода · гейт правдивости комментария у отказов hide-existence · red: коммент «403», код отдаёт 404
hard-hide-existence-byte-identical · делать дословно равным miss-тексту владельца ("<Resource> <id> not found") · TestHideExistenceFormats_MatchTheGateway · red: текст из внутреннего имени типа/таблицы или без id
hard-hide-existence-table-complete · покрывать каждый hide-existence ресурс; запись без достижимого типа — находка · TestHideExistenceTablesCarryNoUnreachableType · red: непокрытый ресурс отвечает своей формой
hard-hide-existence-test-asserts-message · проба локает текст deny и текст miss ПОБАЙТНО, а не «содержит» · internal/repohygiene/hideexistenceparity_test.go (TestHideExistenceFormats_MatchTheGateway) · red: тексты разошлись с краем, а проба зелёная
hard-format-before-authz · валидировать page_size/page_token/формат id (⇒InvalidArgument) ДО authz-short-circuit; порядок format→authz→repo · TestEmptyPageNeverPrecedesPaginationValidation · red: пустой грант замыкает раньше проверки формата
hard-check-in-same-function · нести проверку формата в себе, не в репозитории · TestEmptyPageNeverPrecedesPaginationValidation · red: «валидирует репозиторий» при замыкании до репозитория
hard-gate-not-reference-title · держать AST-гейтом, обходящим дерево по синтаксическому признаку, а не званием «эталонного» сервиса · TestEmptyPageNeverPrecedesPaginationValidation · red: ссылка на эталон вместо гейта
hard-misconfig-is-not-outage · классифицировать: 404/405/не-JSON/HTML = НАСТРОЙКА (громко, не Warn), сеть/таймаут/5xx = сбой · tools/softopengate TestSoftOpenPassesAreObservable · red: тихий Warn на доказанной неправильной настройке
hard-soft-pass-counted · нести читаемый счётчик, не только лог · tools/softopengate TestSoftOpenPassesAreObservable · red: проход только логируется
hard-zero-refusals-visible · делать наблюдаемым число своих отказов; ноль за всю жизнь — сигнал · tools/softopengate/gate_test.go · red: контроль без счётчика отказов
hard-no-derived-security-address · задавать явно в каждом профиле; вывод из базового URL соседа запрещён; boot-guard отказывает при включённом контроле без адреса · TestEdgeAddressInjectionChartWaitsForEdgeRedsOnlyTheAddressLane · red: умолчание «base URL соседа + путь»
hard-declarative-values-test · читать объявления values, не отрендеренный шаблон · gateway/deploy/token_shape_test.go · red: проба на рендере, которую можно пропустить

## Контроль, действующий на ВЫДАЧЕ, но не на ПРЕДЪЯВЛЕНИИ (выведено 2026-08-21)

hard-revocation-reader-on-request-path · иметь читателя на пути запроса; читатель только в местах выдачи отзыв не исполняет · TestEdgeRevocationLaneHasAReaderOnTheRequestPath · red: все вызывающие читателя стоят в чеканке/обновлении
hard-revocation-census-predicate · перечислять вызывающих читателя по точкам жизненного цикла удостоверения · TestEdgeRevocationGate_FindsADeadReader · red: ни одного вызывающего на предъявлении
hard-revocation-antidote-cache-fail-closed · ставить на путь запроса с коротким объявленным кешем и fail-closed · TestEveryVerdictCacheProcessDeclaresItsOwnKnob · red: кеш вердикта без объявленной ручки окна
hard-short-lived-by-decision · объявлять решением (политикой), а не получать следствием выбранного из удобства срока · TestRevocationWindowIsDeclaredPolicy · red: срок в коде без объявленной политики окна

## Части, исправные по отдельности, не сходятся в целое

hard-parts-must-converge · проверять, про один ли предмет они говорят; исправность части ничего не доказывает о целом · ЗАВЕСТИ hard-parts-must-converge · red: две пробы по половине
hard-probe-through-both-sides · держать пробой сквозь обе (записали отзыв → предъявили удостоверение → получили отказ) · ЗАВЕСТИ hard-probe-through-both-sides · red: две пробы, каждая про свою половину

## Отношение, выполнимое подстановочным знаком, не сужает НИЧЕГО (выведено 2026-07-28)

hard-wildcard-relation-not-authz · не нести отношение, выполнимое wildcard-tuple; такая проверка отвечает «да» каждому аутентифицированному · TestMRR_RedOnAWildcardSatisfiableRelation · red: required_relation, выполнимый user:*
hard-directory-only-for-wildcard · допускать только для глобального справочника (регионы, зоны, типы дисков/машин); RPC об объектах с владельцами — нет · TestMRR_RedOnAWildcardSatisfiableRelation · red: справочное отношение на RPC об индивидуальном объекте
hard-ask-which-tuples-satisfy · перед объявлением RPC с cluster-scoped отношением спроси, КАКИЕ tuple его выполняют · internal/repohygiene/membershipreadrelation_injection_test.go (TestMRR_RedOnAWildcardSatisfiableRelation) · red: отношение выполняется подстановочным знаком и не сужает ничего
hard-authorize-at-data-scopefiltered · авторизовать на уровне данных и помечать ScopeFiltered; boot-guard не стартует без работающего фильтра · TestScopeFilteredRowsBelongToADomainThatEnforcesThem · red: ScopeFiltered-запись в домене без энфорсмента
hard-empty-subject-rejected · отсекать безусловно, независимо от подключённости фильтра; ошибка фильтра ⇒ fail-closed · TestNoBlindPrincipalAbsenceAssertions · red: filter==nil + пустой субъект проходит
hard-catalog-tells-truth-about-band · объявлять ту полосу, которую исполняет код; каждая wildcard-выполнимая запись несёт явное обоснование «это справочник» · TestMRR_ComparisonOfTwoDeclarationsIsLive · red: запись объявляет одно, код делает другое
hard-narrow-before-removing · сначала выразить ограничение в модели/данных, потом снимать · ЗАВЕСТИ hard-narrow-before-removing · red: обратный порядок

## Авторизация живёт в МОДЕЛИ, а не в самодельных проверках (директива владельца 2026-07-27)

hard-no-hand-rolled-authz · принимать моделью прав (каталог + per-object Check); хардкод-условие в Go запрещено · ЗАВЕСТИ hard-no-hand-rolled-authz · red: самодельная проверка поверх работающего Check
hard-policy-as-relation · выражать глаголом от отношения владельца в модели · ЗАВЕСТИ hard-policy-as-relation · red: условие в Go вместо отношения
hard-machine-gets-grant · давать узкий грант на конкретные объекты/тип, не бланкетный админ; принципал первоклассный · ЗАВЕСТИ hard-machine-gets-grant · red: роль-на-всё для машины
hard-async-carries-initiator · нести личность инициатора, захваченную в момент запроса · ЗАВЕСТИ hard-async-carries-initiator · red: воркер под своей учёткой
hard-no-token-impersonation · не держать токен человека; делегирование — отдельный протокол (согласие, область, срок) · ЗАВЕСТИ hard-no-token-impersonation · red: user-токен в окружении воркера
hard-audit-writes-both · нести и актора, и от чьего имени действовали · ЗАВЕСТИ hard-audit-writes-both · red: одно поле принципала
hard-establish-before-removing-guard · перед снятием самодельной проверки установи ПО КАЖДОМУ месту, что добавляет модель · ЗАВЕСТИ hard-establish-before-removing-guard · red: проверка снята по одному месту, а покрытие модели по остальным не установлено

## Три уровня супер-доступа — КАСКАДОМ, ниже — плоско по выдаче

hard-cloud-admin-cascade · разрешать каскадом на всё · internal/repohygiene/quotasurfacecensus_injection_test.go · red: глаголы без наследования от кластера
hard-bootstrap-account-cascade · разрешать каскадом в пределах облака · internal/repohygiene/quotasurfacecensus_injection_test.go · red: отсутствие наследования у бутстрапа
hard-account-admin-cascade · разрешать каскадом внутри аккаунта; новые права после его уволнения навешивает только администратор облака · internal/repohygiene/quotasurfacecensus_injection_test.go · red: плоские глаголы на уровне аккаунта
hard-below-is-flat · оставлять плоским per-object, материализуемым реконсайлером из AccessBinding · internal/repohygiene/catalogreachability_test.go · red: каскад ниже аккаунта
hard-owner-structural-on-own-account · быть структурным источником глаголов на своём объекте аккаунта; удаление так же надёжно, как создание · обход модели: глаголы account читают owner · red: право удаления приезжает материализацией
hard-account-admin-not-on-account-itself · не получать право на сам объект аккаунта; тенантность сносят владелец и облако · internal/repohygiene/quotasurfacecensus_injection_test.go · red: admin аккаунта в usersets самого account
hard-cascade-only-top-three · заводить только для облака, бутстрапа и аккаунта; проект и ниже — нет · ЗАВЕСТИ hard-cascade-only-top-three · red: каскад на уровне проекта
hard-establish-relation-before-adding · установить фактическое отношение прежде добавления вывода · ЗАВЕСТИ hard-establish-relation-before-adding · red: отношение изобретено ради синтаксиса
hard-model-canonical-and-drift-gate · держать каноничной в одном файле, конфигмап чарта генерировать из него, гейт дрейфа — зелёный · координата в тексте УСТАРЕЛА: proto/kacho/cloud/iam/v1/ в дереве нет (kacho#2616, канон в PRO-Robotech/kaname) · red: две правки в двух местах
hard-regression-observable-level · утверждать на наблюдаемом уровне: администратор облака снимает чужую выдачу, обычный тенант — нет · ЗАВЕСТИ hard-regression-observable-level · red: проба на уровне tuple вместо API

## Контроль, у которого нет МЕХАНИЗМА исполниться (выведено 2026-08-23, эпик identity)

hard-control-carries-address-and-credential · объявлять пару: адрес соседа И удостоверение к нему; половина пары отвергается · TestEdgeRevocationGate_FindsAMissingDeclaration · red: профиль называет службу и не объявляет удостоверение
hard-two-column-profile-census · сверять две колонки: сколько называют зависимость и сколько объявляют удостоверение к ней · TestEdgeRevocationGate_FindsAMissingDeclaration · red: первое число больше второго
hard-asymmetry-with-peer-consumer · превращать в замер сравнением с соседом-потребителем той же службы · ЗАВЕСТИ hard-asymmetry-with-peer-consumer · red: вывод без сравнения
hard-substring-probe-needs-boundary · привязывать к границе имени, не к подстроке · run-injection-proofs.sh с инъекцией ..._XX · red: зелёная проба при переименованной ручке
hard-declarative-probe-and-bootguard-pair · объявления держатся декларативной пробой плюс boot-guard на НЕПОЛНОЙ паре · gateway/deploy/token_shape_test.go (TestEdgeRevocationGate_FindsAMissingDeclaration) · red: половина пары объявлена, посадка стартует
hard-missing-knob-vs-unseeded · спросить, существует ли ручка: нет ручки ⇒ дефект продукта на все профили; есть, но не задана ⇒ чинится посевом · ЗАВЕСТИ hard-missing-knob-vs-unseeded · red: дефект кода чинят посевом
