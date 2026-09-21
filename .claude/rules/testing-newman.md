---
name: rule-testing-newman
description: "Сквозные пробы newman: eventual-consistency и параллельный прогон"
---

**Архив** — доводы, замеры, снятые редакции; **НЕ действующая норма**, цитировать как норму нельзя: `.claude/backup/testing-newman.md`

# Сквозные пробы newman: eventual-consistency и параллельный прогон

## Толерантность к EC без маскировки: фикстуры и общий принцип

robust-ryw-not-masking · будь robust к read-your-writes окну (Kachō eventually-consistent), но НИКОГДА не маскируй реальный дефект · ЗАВЕСТИ robust-ryw-not-masking · red: retry/tolerance добавлен ради снятия красноты EC без диагноза причины — дефект спрятан за «flaky»
fixture-seed-assert-op-error · поллься до done, assert !op.error, ТОЛЬКО потом извлекай metadata.<res>Id · TestPhantomIdGateRedOnInjectedDefect · red: фантомный id несозданного ресурса уехал в env
fixture-self-seed-per-case · предпочти self-seed свежего ресурса per-case (discover_zone, create_suite_project) вместо shared-литерала env-var · TestFixtureNamesObeyTheCanonWhereTheServiceMigrated · red: кейс идёт по shared-ресурсу, который мог async-упасть

## op-poll с РЕАЛЬНОЙ inter-poll задержкой (выведено из owner-tuple раундов)

poll-busywait-before-setnextrequest · ставь busy-wait прямо перед ним: const _x=Date.now(); while(Date.now()-_x<N) void 0; · ГЕЙТА НЕТ — кандидат: while (Date.now() - _ в 4 строках выше · red: петля на 30 итераций покрывает 0.15s вместо секунд
poll-delay-scaled-from-cap · размеряй от cap петли: clamp(30000/cap, 100..500)ms; budget покрывает async-хвост ~15s · тот же grep-гейт · red: фиксированные 500ms при POLL_CAP=300 дают 150s worst-case
poll-grep-gate · заведи grep-гейт: у каждого setNextRequest есть while (Date.now() - _ в 4 строках выше · ЗАВЕСТИ poll-grep-gate · red: 51 петля в 26 файлах без ожидания

## Serialised suite (`--jobs 1`) для pool-contended ресурсов

pool-contended-serial-jobs1 · дай больший пул (seed-CIDR), либо --jobs 1, либо pool-independent ресурс (INTERNAL) · serial-collections.txt · red: could not allocate → phantom-ресурс → каскад
pool-recycle-on-delete · проверь recycle-on-delete: не возвращает адрес на Delete — это product-баг · integration-тест Delete→повторный Create · red: пул истощается прогонами

## Параллельный newman — слоёная parallel-safety (выведено из e2e-newman стабилизации 2026-07, serial 90мин→parallel ~35мин)

layer1-grant-throughput-share-lock · иди ReconcileObjectForward с SHARE-advisory-lock, не EXCLUSIVE · integration-тест на concurrent creates · red: full ReconcileObject сериализует и дрейнит под параллелью
layer2-create-vs-update-discriminator · различай: нет existing-members ⇒ create→forward; есть ⇒ update→full с delete-stale · integration-тест на ИСХОД отзыва, не на факт вызова · red: аддитивный путь на правке — снятие права не применяется
layer3-iam-own-wave · гони отдельной волной PHASE2_SERVICES=iam без конкурирующей leaf-нагрузки · newman-parallel.sh · red: get-confirms 404, revoke-not-sticking под конкуренцией
layer4a-never-granted-subject · держи выделенный НИКОГДА не грантованный jwtPureNoBindings · сверка субъекта по setup.sh · red: shared no-binding субъект грантят — течёт через account→project containment
layer4b-disjoint-cidr-serial-tail · нарежь disjoint CIDR-блоки, contended-коллекции вынеси в serial-tail (serial-collections.txt) · TestCarveBandGateRedOnSharedBand · red: zone-collapse и общий CIDR рвут параллельный прогон
layer4c-fresh-private-account · заводи fresh per-run private account: ProjectService.List отдаёт члену ВСЕ проекты аккаунта · TestNewmanConsumersReachTheSpineThroughTheSuiteBinding · red: by-label narrowing бьётся visibility floor
layer5-collision-before-blaming-ec · проверь shared-resource collision CIDR/pool/name ПРЕЖДЕ eventual consistency; чини run-random энтропией обоих октетов, не retry · TestCarveBandGateRedOnSharedBand · red: seq рестартит с 1 в каждом newman-процессе при общем октете
layer6-preclean-retry-403 · ретрай DELETE на 403 до успеха, не fire-forget · TestDeleteRetryWindowGate_FailsOnAssert200WithoutWaiting404 · red: teardown принял transient 403 → binding ACTIVE → ALREADY_EXISTS
layer6-retry-create-message-discriminated · различай phantom-id и peer-RYW: retry_create_until_present message-discriminated (400/404 + /not found/; валидационные 400 проходят сквозь) · TestPhantomIdGateAttributesPollByOperationVariable · red: retry поверх валидационного 400
layer7-ordering-tolerance-negatives · толерируй 400/403/404, never 200; scope-deny пинуй отдельным precond'ом · TestResponseCodeFormCorpusIsHonoredByEveryNewmanGenerator · red: STRICT-403 ложно падает на hide-existence 400
