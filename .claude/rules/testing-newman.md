---
name: rule-testing-newman
description: "Сквозные пробы newman: край чёрным ящиком, свод классов, флоу, eventual-consistency, параллельный прогон"
---

**Архив:** `.claude/backup/testing-newman.md`

## Край проверяет newman, автор — тестировщик чёрного ящика

Решение владельца 2026-09-23, дословно: (1) «добавь в рулы что проверка края всегда достигается через newman тесты. Считаем, что ньюман пишут тестировщики, которые воспринимают систему как блекбокс и пытаются найти корнер кейсы, тк именно так с краем работают конечные потребители.» (2) «так же ньюман тесты отражают корректность реализованных интерфейсов с реально с тем что отдают. Получается такая двойная проверка» — «так же в правила добавить». (3) «так же надо понимать что тесты могут быть составные тк некоторые ресурсы нельзя создать без другого ресурса. Например  нельзя создать адрес без подсети, подсеть без сети и тп» (4) «так же разные методы CRUD, валидации и тп. На основе всего чем в классической разработке занимались тестировщики нужно сделать агрегат опыта используя ньюман и описать флоу учитывая что рулы мы пишем на грани емкости по кол-ву символов и эффективности в качестве кода»

edge-is-newman · поведение края утверждай newman-кейсом; край — всё, с чем работает потребитель: gateway kacho, публичные пути kaname с `/iam/v1/authorize`, `/iam/v1/token`, поток `gateway/internal/subscriptionstream` (тело — до закрытия по `streamBudget`); HTTP-путь без proto — новый RPC (testing.md#new-rpc-newman-case); консоль — playwright · ЗАВЕСТИ new-rpc-newman-case · red: путь края покрыт только Go-пробой
edge-internal-consequence · внутренний слушатель — не край; его следствие, видимое через край, утверждай newman, создав условие средствами потребителя или админ-проекции (`{{internalBaseUrl}}`), иначе — Go integration с причиной в шапке · ЗАВЕСТИ · red: следствие видно через край, проба только Go и без причины
edge-author-black-box · кейс края пишет тестировщик — `integration-tester` до реализации, `qa-test-engineer` после выкатки и на баг; автор предмета его заказывает; вход — приёмка, контракт, публичная документация, адрес края, провенанс стенда, тронутые методы полными путями, план опыта; кода предмета во входе нет, негатив — из контракта · вниманием диспетчера: dispatcher.md §3 «Край» · red: ожидание списано с реализации — кейс зелёный на своём дефекте; кейс написан автором предмета
edge-double-check · утверждай обе стороны: исход по приёмке И ответ, равный интерфейсу, — статус и код (e2e-flow.md#assert-status-and-code); ключи тела — ровно `json_name` сообщения, типы и enum — из контракта; id, время, `reason` и текст — по `api-conventions.md`, без текста драйвера; `content-type`; метод, тип тела и `Accept` вне контракта — исход библиотеки (e2e-flow.md#status-set-computed) · ЗАВЕСТИ (сверка тела с дескриптором `buf build proto`) · red: ответ сверен выборочными полями — лишнее, внутреннее или переименованное поле проходит
edge-composite-chain · родителей заводи краем по зависимости (сеть → подсеть → адрес), звено утверждает исход операции и захват id; сноси в обратном порядке и чтением докажи отсутствие остатка, и после отказа посреди цепочки; негативы звена — родитель несуществующий, чужой, удаляемый, в другом проекте или аккаунте; удаление родителя с детьми — по контракту, без остатка · ЗАВЕСТИ (уборка стеком в kacholib) · red: снос оставляет сирот; ребро края не пройдено ни одним кейсом

## Свод классов: что утверждает каждый

qa-classes-per-method · методу края — каждый применимый класс свода, неприменимый — в шапке набора с причиной; позитив — круг create→get→list→update→get→delete→get 404, звено сверяет тело с прежним; техника — `testing-product-coach` ч. III · ЗАВЕСТИ qa-class-census (перепись «метод+путь × classes») · red: метод прожил выкатку с одним happy и одним negative; «кейсов N» без разреза по классам
qa-class-label · метка `classes` — из словаря CRUD, VAL, NEG, BVA, IDM, CONC, CONF, STATE, AUTHZ, PAGE, FILTER, SEC (`docs/TAXONOMY.md` compute); синонимы nlb (IDEM = IDM, AZD = AUTHZ, LSG — PAGE либо FILTER) сводит перепись, AUTHN законен; метка обязывает к утверждению вида: CONF — edge-double-check, VAL — имя поля в отказе, AUTHZ — субъект и исход · ЗАВЕСТИ qa-class-census (validate-cases.py словарь не судит) · red: метка вне словаря и синонимов либо без утверждения своего вида
qa-create · (CRUD, VAL, NEG) минимум и полный набор полей; дубль уникального → ALREADY_EXISTS; нет обязательного → INVALID_ARGUMENT с именем поля; необязательное применено либо отвергнуто с именем поля (api-conventions.md#api-accepted-ignored); свой `id` в Create — форма и дубль; ключ вне контракта не шлётся (TestNewmanCollectionsSendNoUnknownRequestFields); get после операции равен телу, repeated — на ≥3 элементах · ЗАВЕСТИ qa-class-census · red: поле принято и проигнорировано
qa-get · (NEG, CONF) есть → ресурс; нет → NOT_FOUND дословно; кривой id — testing.md#malformed-id-not-weakened; чужой — security-hardening.md#hard-hide-existence-byte-identical · ЗАВЕСТИ qa-class-census · red: чужой ресурс отличим от несуществующего
qa-list · (PAGE, FILTER) пусто; страницы (и по `pageSize` 1) не пересекаются, покрывают всё, чужого нет; границы и мусорный токен — api-conventions.md#api-pagesize; чужой курсор — 200 и только своё, протухший — продолжение без повтора; фильтр верный и кривой; элемент равен get по объявленным полям · ЗАВЕСТИ qa-class-census · red: элемент повторён или потерян между страницами
qa-update · (STATE, VAL) маска неизвестная, с output-only и с неизменяемым полем (api-conventions.md#api-mask-unknown, api-conventions.md#api-mask-immutable); пустая — полный PATCH; no-op; поле вне маски не тронуто (get после) · ЗАВЕСТИ qa-class-census · red: неизменяемое поле в маске принято
qa-delete · (CRUD, NEG) повтор → NOT_FOUND; get после → NOT_FOUND, list без него; с детьми — edge-composite-chain · ЗАВЕСТИ qa-class-census · red: удалённый виден в list
qa-state · (STATE) действие из недопустимого состояния — отказ кодом по таблице края (e2e-flow.md#status-set-computed); допустимый переход — кейс · ЗАВЕСТИ qa-class-census · red: переход из запрещённого состояния принят
qa-operation · (NEG, CONF) ошибка внутри операции — кодом и текстом, id не захвачен (e2e-flow.md#assert-operation-outcome); чужая операция неотличима от несуществующей · ЗАВЕСТИ qa-class-census · red: чужая операция читается
qa-validation · (VAL, BVA) классы и границы поля (min−1, min, max, max+1, 0, отрицательное, пусто, переполнение), и у вложенного поля, и у элемента repeated; ловушки края: JSON-тип, формат CIDR, IP, имени, null против отсутствия, неизвестный enum, юникод, пробелы, регистр; недопустимое → INVALID_ARGUMENT с именем поля, допустимое — близнец на границе; условия — таблицей решений, сочетания — попарно · ЗАВЕСТИ qa-class-census · red: граница проверена с одной стороны
qa-access · (AUTHZ, для 401 — AUTHN) токена нет, кривой, истёкший, отозванный, чужой аудитории → 401; матрица verb×role×scope (data-integrity.md#authz-edge-matrix); чужой арендатор — security-hardening.md#hard-hide-existence-byte-identical; эскалация через поле тела; Internal краем не отдаётся · ЗАВЕСТИ qa-class-census · red: отказ проверен одним субъектом
qa-repeat-race · (IDM, CONC) повтор мутации — исход по контракту; N параллельных за уникальное имя — один успех, прочие ALREADY_EXISTS; параллельные правки разных полей без версии — обе в get либо проигравшая отвергнута конфликтом (data-integrity.md#db-xmin-occ); без etag в контракте правка по версии — неприменима, в шапке набора · ЗАВЕСТИ qa-class-census · red: гонка дала два ресурса с одним именем либо потеряла правку
qa-hostile-input · (SEC) строки-инъекции, обход пути (`..`, кодированный `/`), сверхразмер тела → 4xx без утечки текста · ЗАВЕСТИ qa-class-census · red: 500 либо текст драйвера в ответе
qa-rate · (SEC) окно темпа из контракта (kaname: вход, второй фактор; kacho: потолок потоков) — сверх окна 429 с `reason` и обещанным `Retry-After` в секундах; после окна проходит · ЗАВЕСТИ qa-class-census · red: окно не отпускает либо обещанного `Retry-After` нет

## Флоу кейса края

flow-red-by-acceptance · до реализации `integration-tester` пишет по APPROVED приёмке красный кейс на каждый сценарий края, классы — из свода; вход — путь и отпечаток приёмки, ID сценариев, адрес края · `landing-reviewer` на сыром красном · red: кейс края написан после кода и сразу зелёный
flow-after-deploy · после выкатки, тронувшей край, при провенансе «сходится» `qa-test-engineer`: первым smoke — happy каждого тронутого пути; затем классы свода и хартия (цель, область, срок, объём «пути × классы, запросов N» отдельно от находок); найденное — кейсом либо задачей · вниманием диспетчера · red: выкатка закрыта без прогона тронутого пути; хартия «находок 0» без объёма
flow-bug-regression · баг, видимый через край (и находка аудита), — красный кейс `qa-test-engineer` `# verifies <issue>` до фикса (testing.md#tdd-red-case-links-issue-no-skip); фикс его зеленит, не правя; Go RED-lock его не заменяет · пометка — tools/knownfailingsubject; наличие кейса — вниманием `landing-reviewer` · red: фикс влит, кейса-замка края нет
flow-handoff · сдача — `cases/*.py` с `classes` и ID сценария либо `# verifies` → validate-cases.py → gen.py; перепись CASES-INDEX; RESULTS «исполнено N из M»; новая коллекция kaname — строка PRODUCER_LEDGER; новый набор — e2e-flow.md#new-suite-four-things · validate-cases.py (ci.yaml, обход `services/*`); newman-suite-debt.py (kaname) · red: кейс в дереве, в CASES-INDEX нет; набор вне обхода валидатора
flow-acceptance · вердикт прогона — `landing-reviewer` по числам; кейс, не падавший ни разу, и правка kacholib или генератора — работа-проверка: `check-verifier` ломает утверждаемое, кейс краснеет с координатой · вниманием диспетчера: dispatcher.md §5 · red: кейс, не падавший ни разу, принят зелёным
flow-flaky-is-defect · разный исход кейса на одной ревизии и стенде — дефект кейса либо продукта, разбор причины; карантин, пропуск одиночного отказа и повтор до зелёного запрещены; сбой среды — недействителен весь прогон (testing-verdict.md#exhausted-run-is-third-category) · вниманием `landing-reviewer` · red: кейс в карантине либо перезапущен до зелёного

## Толерантность к EC без маскировки: фикстуры и общий принцип

robust-ryw-not-masking · будь robust к read-your-writes окну (Kachō eventually-consistent), но НИКОГДА не маскируй дефект · ЗАВЕСТИ · red: retry/tolerance ради снятия красноты EC без диагноза — дефект спрятан за «flaky»
fixture-seed-assert-op-error · поллься до done, assert !op.error, ТОЛЬКО потом извлекай metadata.<res>Id · TestPhantomIdGateRedOnInjectedDefect · red: фантомный id несозданного ресурса уехал в env
fixture-self-seed-per-case · self-seed свежего ресурса per-case (discover_zone, create_suite_project) вместо shared-литерала env-var · TestFixtureNamesObeyTheCanonWhereTheServiceMigrated · red: кейс идёт по shared-ресурсу, который мог async-упасть

## op-poll с РЕАЛЬНОЙ inter-poll задержкой

poll-busywait-before-setnextrequest · ставь busy-wait прямо перед ним: const _x=Date.now(); while(Date.now()-_x<N) void 0; · ГЕЙТА НЕТ — кандидат: while (Date.now() - _ в 4 строках выше · red: петля на 30 итераций покрывает 0.15s вместо секунд
poll-delay-scaled-from-cap · от cap петли: clamp(30000/cap, 100..500)ms; budget покрывает async-хвост ~15s · тот же grep-гейт · red: фиксированные 500ms при POLL_CAP=300 дают 150s worst-case
poll-grep-gate · заведи grep-гейт: у каждого setNextRequest есть while (Date.now() - _ в 4 строках выше · ЗАВЕСТИ · red: 51 петля в 26 файлах без ожидания

## Serialised suite (`--jobs 1`) для pool-contended ресурсов

pool-contended-serial-jobs1 · больший пул (seed-CIDR), либо --jobs 1, либо pool-independent ресурс (INTERNAL) · serial-collections.txt · red: could not allocate → phantom-ресурс → каскад
pool-recycle-on-delete · recycle-on-delete: адрес не возвращён на Delete — product-баг · integration-тест Delete→повторный Create · red: пул истощается прогонами

## Параллельный newman — слоёная parallel-safety

layer1-grant-throughput-share-lock · иди ReconcileObjectForward с SHARE-advisory-lock, не EXCLUSIVE · integration-тест на concurrent creates · red: full ReconcileObject сериализует и дрейнит под параллелью
layer2-create-vs-update-discriminator · нет existing-members ⇒ create→forward; есть ⇒ update→full с delete-stale · integration-тест на ИСХОД отзыва, не на факт вызова · red: аддитивный путь на правке — снятие права не применяется
layer3-iam-own-wave · отдельной волной PHASE2_SERVICES=iam без конкурирующей leaf-нагрузки · newman-parallel.sh · red: get-confirms 404, revoke-not-sticking под конкуренцией
layer4a-never-granted-subject · выделенный, НИКОГДА не грантованный jwtPureNoBindings · сверка субъекта по setup.sh · red: shared no-binding субъект грантят — течёт через account→project containment
layer4b-disjoint-cidr-serial-tail · disjoint CIDR-блоки, contended-коллекции — в serial-tail (serial-collections.txt) · TestCarveBandGateRedOnSharedBand · red: zone-collapse и общий CIDR рвут параллельный прогон
layer4c-fresh-private-account · fresh per-run private account: ProjectService.List отдаёт члену ВСЕ проекты аккаунта · TestNewmanConsumersReachTheSpineThroughTheSuiteBinding · red: by-label narrowing бьётся visibility floor
layer5-collision-before-blaming-ec · shared-resource collision CIDR/pool/name — ПРЕЖДЕ eventual consistency; чинит run-random энтропия обоих октетов, не retry · TestCarveBandGateRedOnSharedBand · red: seq рестартит с 1 в каждом newman-процессе при общем октете
layer6-preclean-retry-403 · ретрай DELETE на 403 до успеха, не fire-forget · TestDeleteRetryWindowGate_FailsOnAssert200WithoutWaiting404 · red: teardown принял transient 403 → binding ACTIVE → ALREADY_EXISTS
layer6-retry-create-message-discriminated · phantom-id отличай от peer-RYW: retry_create_until_present по тексту (400/404 + /not found/; валидационные 400 — сквозь) · TestPhantomIdGateAttributesPollByOperationVariable · red: retry поверх валидационного 400
layer7-ordering-tolerance-negatives · толерируй 400/403/404, никогда 200; scope-deny пинуй отдельным precond · TestResponseCodeFormCorpusIsHonoredByEveryNewmanGenerator · red: STRICT-403 ложно падает на hide-existence 400
