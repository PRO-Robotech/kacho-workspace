---
name: rule-security
description: "Безопасность: Internal-vs-external + инфра-чувствительные данные"
---

**Архив** — доводы, замеры, снятые редакции; **НЕ действующая норма**, цитировать как норму нельзя: `.claude/backup/security.md`

# Безопасность: Internal-vs-external + инфра-чувствительные данные

## AuthN+AuthZ ВЕЗДЕ — инвариант; AuthN/AuthZ (текущее состояние)

sec-both-listeners-same-rules · требовать authN+authZ на каждом запросе, internal не освобождён · deploy/scripts/assert-production-posture.sh · red: листенер без authN или authZ
sec-transport-mtls-or-tlsjwt · только mTLS (svc→svc) или TLS+JWT (user→edge); plaintext/insecure-gRPC запрещён, :9091 тоже · assert-production-posture.sh · red: insecure-gRPC на любом порту
sec-per-rpc-check-both-listeners · включать authz-Check на ОБОИХ листенерах; internal с одним mTLS — баг · assert-production-posture.sh authz_check · red: internal-листенер без authzIntr.Unary()
sec-internal-annotations-enforced · нести permission/required_relation и энфорсить их · TestAnnotationLaneInjection_UnannotatedMethodIsAFinding · red: аннотация есть, Check её не читает
sec-read-viewer-mutation-admin · read гейтить viewer-tier (system_viewer), мутации — admin-tier · TestMembershipReadIsGatedByTheTierRelationNotTheVerbOne · red: мутация на viewer-полосе
sec-internal-trusted-assumption-banned · не считать internal-периметр доверенным: «internal = trusted, mTLS достаточно» — запрещённое допущение (defense-in-depth против lateral movement) · ЗАВЕСТИ sec-internal-trusted-assumption-banned · red: код снимает Check на internal, ссылаясь на «доверенный периметр»
sec-forwarded-trust-aware-extract · извлекать личность только trust-aware парой (CertIdentityExtract→TrustedPrincipalExtract) на ОБОИХ листенерах · TestRawTrustedForwarderCircleIsReadInExactlyOnePlacePerService · red: безусловное чтение заголовка личности
sec-forwarder-allowlist-nonempty · задавать непустым списком SAN из конфигурации; пустой = «не сужаем» · TestEveryServiceDeclaringTheCircleRefusesToStartUnnarrowed · red: пустой круг в боевом профиле
sec-forwarder-bootguard-empty-circle · отказывать в старте при пустом круге отправителей · TestEveryServiceDeclaringTheCircleRefusesToStartUnnarrowed · red: сервис поднялся с пустым кругом
sec-forwarder-in-selfreport-and-gate · нести trusted_forwarders и ОЦЕНИВАТЬ его в гейте, а не печатать · assert-production-posture.sh · red: измерение печатается без вердикта
**Пустой список — это «не сужаем», а НЕ «запрещаем» (non-negotiable).**
sec-identity-not-bound-to-cert · не верить заголовкам без verified-cert отправителя; сначала trust-aware пара, потом сужение · TestRawTrustedForwarderCircleIsReadInExactlyOnePlacePerService · red: заголовок личности читается до проверки пира
sec-one-predicate-three-readers · читать РОВНО в одном месте на сервис; guard, самоотчёт и транспорт зовут один предикат · TestRawTrustedForwarderCircleIsReadInExactlyOnePlacePerService · red: guard считает элементы строки, транспорт — записи
sec-circle-pinned-by-import-graph · выводить из графа импортов фактических отправителей · git grep импортов транспортного клиента · red: круг сужен до одного шлюза «наверное»
sec-exception-iam-jwks · единственное authN-исключение; на wire только публичный материал · TestProviderSurfaceInjection_OurOwnKeySetPathIsSilent · red: исключение расширено на другой путь или листенер
sec-exception-geo-public-read · снят ТОЛЬКО authZ project-scope (permission="<exempt>"); authN обязателен, anonymous ⇒ UNAUTHENTICATED · TestAnnotationLaneInjection_ExemptNamingARelationIsAFinding · red: exempt-запись с relation, или anonymous 200

## Internal-vs-external (ban #6)

sec-ban6-internal-not-on-external · не публиковать на external TLS endpoint; REST-проброс только на cluster-internal · deploy/scripts/assert-ban6-external-isolation.py · red: Internal-метод резолвится на :8443
sec-one-issuance-listener · не заводить второй слушатель об одном предмете; вид выдачи задаёт форма запроса · TestCompositionRootsRaiseNoNonGRPCListenerOfTheirOwn · red: свой listen в композиционном корне
sec-issuance-path-not-elsewhere · не монтировать ни на внутреннем, ни на JWKS-, ни на метрик-слушателе; чужой метод ⇒ отказ с перечнем допустимых · TestEdgeMetricsRouteIsMountedOnTheDiagnosticSurfaceOnly · red: тот же путь отвечает на втором слушателе
sec-authn-failures-byte-identical · делать побайтово одинаковыми · ЗАВЕСТИ sec-authn-failures-byte-identical · red: различимый текст отказа
sec-issuance-four-knobs-bootguard · при незаданном значении ОТКАЗЫВАТЬ В ПУСКЕ, не подставлять разумное · TestEveryAuthzWindowKnobIsDeclared · red: старт с незаданной величиной
sec-no-silent-default-for-guarded-knob · запретить молчаливое умолчание в загрузчике; ненулевое умолчание = страж по ней мёртв · TestSpecWiringRedOnAQuietConstantInEveryPostureField · red: defaults.go задаёт значение, которое судит страж
sec-admin-ui-rpc-internal-only · добавлять только в Internal*-сервис и регистрировать *InternalAddr-блоком в restmux/mux.go · deploy/scripts/assert-ban6-external-isolation.py · red: admin-метод в публичном сервисе

## Инфра-чувствительные данные — ТОЛЬКО в Internal*-API

sec-infra-data-internal-only · отдавать ТОЛЬКО на :9091 · гейт: поля этого словаря отсутствуют в публичных message · red: инфра-поле в публичном ответе
sec-public-surface-intent-and-result · ограничивать id, name/labels, привязками, tenant-адресом, status · гейт публичных message против словаря инфра-полей · red: «как разложено по железу» в публичном ответе
sec-two-projections · заводить две проекции — публичный lean-message и internal full · гейт: internal-поле не заполняется в публичном ответе · red: одно message на обе поверхности

## Get/List: проверка прав постранично

sec-public-list-through-listauthz · фильтровать выдачу через listauthz · make -C services/<svc> audit-list-filter · red: листинг без фильтра
sec-page-then-check · Get — только прямая per-object проверка; List — курсор по своей БД + batch-check id страницы (≤100); предел перечисления не поднимать · TestListNarrowingHasExactlyOneImplementation · red: перечисление разрешённых объектов вместо проверки страницы
sec-time-budget-per-request · исполнять партии параллельно в бюджете ЗАПРОСА; page_size ради бюджета не сужать · нагрузочная проба page_size=1000 в срок · red: UNAVAILABLE на положительном пути
sec-pagetoken-may-encode-closed-row · допускать кодирование недоступной вызывающему строки (id+timestamp) и ДОКУМЕНТИРОВАТЬ размен · ЗАВЕСТИ sec-pagetoken-may-encode-closed-row · red: скрытый размен или пропуск строк

## Production-mode — ОБЯЗАТЕЛЕН ВЕЗДЕ, включая dev/локальный стенд (выведено из production-mode валидации 2026-07-21)

sec-production-posture-everywhere · поднимать в боевой посадке; dev-insecure — только в in-process фикстурах · make -C deploy assert-production-posture · red: mode=dev на поднятом стенде
sec-bootguard-fail-closed-axes · отказывать в старте при sslmode=disable, mTLS off на живом ребре, authz-интерсепторе вне цепочки, breakglass on · TestServiceDeclaringPostureKnobsHasABootGuard · red: сервис объявил посадочные ручки без стража
sec-posture-judged-by-common-descriptor · доводить до общего дескриптора corelib/servicecontract в композиционном корне; своя проверка — только по оси, которой у общего нет · TestPostureReachGateRedWhenKnobsNeverReachTheDescriptor · red: ручки объявлены, до дескриптора не доходят
sec-authmode-declared-never-read · обязана МЕНЯТЬ исход старта, а не только существовать; сервис без production-guard не мёржится · TestRefusalReachRedWhenTheProviderIsNeverCalled · red: ручка читается и отделывается WARN
sec-dev-stand-in-production-mode · поднимать в боевой посадке: authMode=production + mTLS через cert-manager + sslmode=require + RS256; эталон values.dev-prod.yaml · make dev-prod-up · red: dev-insecure overlay на поднятом стенде
sec-posture-regression-assertions · утверждать anonymous⇒403, forged HS256⇒403 (не 200), pg_stat_ssl=true на всех PG · deploy/scripts/assert-production-posture.sh · red: зелёный без этих трёх утверждений
sec-chart-config-checksum · нести checksum/config (sha256 рендера configmap) в spec.template.metadata.annotations · deploy/tests/helm/config-rollout-binding-test.sh · red: envFrom без checksum/config
sec-gate-reads-process-and-db · сверять посадку, объявленную процессом при старте, и шифрование со стороны БД (pg_stat_ssl); ConfigMap доказательством не считать · deploy/scripts/assert-production-posture.sh · red: гейт читает манифест вместо процесса
sec-ready-is-not-posture · не выводить из Ready-пода · assert-production-posture отдельно от assert-rollout-ready · red: «все поды Ready» как доказательство посадки
sec-gate-proven-on-reproduced-defect · доказывать инъекцией: красный на воспроизведённом дефекте, зелёный после фикса · deploy/scripts/run-injection-proofs.sh · red: гейт без инъекционной пробы
sec-values-prod-must-boot · проверять helm install + rollout-ready в production-mode, не только helm template · .github/workflows/production-posture.yml · red: зелёный helm template как доказательство
sec-chart-carries-guard-knobs · нести first-class блок под каждое production-требование своих boot-guard · TestModuleKnowsNoEdgeFallsOnTheChartKnob · red: требование стража без ручки в чарте
sec-iam-single-hydra-facade · только через iam (JWKS-proxy :9097, UserTokenService/SAKeyService.Issue, /iam/token); допустим лишь финальный OAuth2 client_assertion→JWT · TestProviderSurfaceIsBoundedByTheLedger · red: новое место или новая просьба к поставщику вне ведомости
sec-e2e-uses-real-issuance · авторизоваться RS256 через iam-unified issuance · .github/workflows/e2e-newman.yml · red: HS256-stand-in в прогоне против боевой посадки
