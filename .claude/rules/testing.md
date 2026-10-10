---
name: rule-testing
description: "Тестирование (строгий TDD)"
---

**Архив:** `.claude/backup/testing.md`

## Части этого правила

| файл | предмет |
|---|---|
| `.claude/rules/testing-verdict.md` | чтение вердикта: текст отказа, недействительный прогон, слепой разборщик |
| `.claude/rules/testing-newman.md` | newman: край, свод классов, флоу кейса, EC, поллер, параллельный прогон |
| `.claude/rules/testing-load.md` | замер под нагрузкой: что делает числа недействительными |

## E2E НИКОГДА не пропускаются — только честные тесты (директива владельца 2026-07-29)

e2e-no-skip-ever · НИКОГДА не пропускай, не маскируй, не ослабляй; зелёное — фиксом продукта или фикстуры · assert-suites-green.sh; TestSkippedVerdictDoesNotPassAsGreen · red: кейс исключён, assert ослаблен, вопрос сужен
e2e-ban-mask-whitelist · запрещены в прогонщике и в гейте · TestEveryGateSkipIsDeclaredInTheLedger; TestRunnerStemSetInjectionWrittenListIsFound · red: выписанный список исключаемых кейсов
e2e-ban-skip-comment-assert · запрещены · git grep -n 'pm.test.skip' tests/newman → 0 · red: в кейсе стоит skip либо assert закомментирован
e2e-ban-exit-code-loss · код возврата не теряй: вердикт — не из трубы и не из шага после прогона · TestPipefailVerdictNeverComesFromAPipe; TestExitCodeReadGateFindsTheDefectiveForms · red: tee либо `|| true` за прогоном
e2e-ban-mutually-exclusive-assert · запрещено принимать взаимоисключающие исходы · TestResponseCodeFormCorpusIsHonoredByEveryNewmanGenerator · red: oneOf([200,400]) в кейсе отказа
e2e-fixture-step-must-assert · статус И захват id утверждай; поллер несёт идентификаторы фикстуры · TestNewmanPrecondMark_ProvenByInjection; TestCapturedVarGateSilentOnLawfulSameShape · red: if (!lastOpError); id захвачен без assert
third-category-not-pass · считай третьей категорией: не вычитай из вердикта и не объясняй · TestThirdCategorySignalReachesTheSummary · red: в итоге «отказов 0» без числа исполненного
e2e-missing-dep-own-job · своя job/волна, создающая условие; нельзя — открытый долг с числом · TestActorExemptionRequiresAScarceRunnerThatExists · red: кейс замаскирован «здесь не запустить»
e2e-red-means-investigate-product · разбирай продукт; маску не возвращай даже временно · TestEveryGateSkipIsDeclaredInTheLedger · red: «известное красное» пережило фикс
e2e-verdict-by-numbers · называй числами: коллекций с отчётом из скольких · запросов · утверждений · упавших · без ответа · пустых отчётов · assert-suites-green.sh:387 · red: суита без отчётов названа зелёной
exclusion-self-expires · обязан истекать сам: запись без предмета — находка · TestPostureRelaxationExpiresWhenItsSubjectIsGone · red: гейт зелен на записи без предмета

## Test-first — обязательно (ban #12)

test-first-red-before-code · напиши и ПРОГОНИ до кода, подтверди причину падения; реализатор — Go unit/integration, кейс края — тестировщик · пара RED→GREEN в отчёте PR · red: тест написан после кода, хотя зелёный
chunk-all-reds-first · напиши ВСЕ падающие тесты первыми, получи RED по всем, чини по одному · ЗАВЕСТИ · red: первый фикс сделан раньше последнего RED
report-red-green-pair · покажи пару RED→GREEN в PR/отчёте · ЗАВЕСТИ · red: готовность заявлена без пары прогонов
new-rpc-integration-test · в том же PR — integration_test.go на testcontainers Postgres с concurrent-race для CAS/UNIQUE/EXCLUDE · git diff PR: новый RPC → новый *integration_test.go · red: RPC без integration-теста
new-rpc-newman-case · новый RPC или путь края — в том же PR newman-кейс тестировщика, ≥1 happy и ≥1 negative (testing-newman.md#edge-author-black-box) · ЗАВЕСТИ (coverage.py маршрут→кейс) · red: путь на крае без кейса
no-tests-no-excuse · не обоснование отсутствия тестов; PR без тестов отклоняется · TestDeferralGateCatchesAMarkerInProductionCode · red: в PR стоит обещание вместо теста
tests-followup-issue-form · форма `Tests-followup: #<N>` на открытый issue, привязанный к эпику ДО merge · tools/knownfailingsubject · red: ссылка на issue, заведённый после merge

## Test-only PR (ban #13)

no-todo-skip-in-tests · запрещены так же строго, как в проде · TestDeferralGateCatchesAMarkerInProductionCode · red: маркер отсрочки в tests/
tdd-red-case-links-issue-no-skip · пометь `# verifies <issue-url>` и НЕ ставь skip · tools/knownfailingsubject · red: кейс отключён вместо пометки
known-failing-declared · объяви в RESULTS.md «Known failing — product bugs» + trail в vault · tools/knownfailingsubject · red: красный кейс не объявлен
test-only-pr-no-prod-code · трогай только tests/ и docs/; любой internal/cmd/migrations-фикс — отдельный PR со своим issue · ЗАВЕСТИ · red: в test-only PR правлен internal/

## Пирамида и инфраструктура

unit-mock-ports-no-sleep · моки port-интерфейсов (repomock/kachomock); LRO — детерминированно AwaitOpDone · TestWaitOrderGateRedOnSleepLoopWait · red: time.Sleep вместо AwaitOpDone
usecase-needs-postgres-is-leak · утечка adapter в use-case — чинится слой · TestUseCaseLayerHasOneLayout · red: usecase_test.go поднимает контейнер
integration-covers-sql-races · CRUD, EXCLUDE/FK/UNIQUE, outbox-транзакционность, гонки CAS/OCC/SKIP-LOCKED — на testcontainers Postgres 16 · TestNoPackageStartsAContainerPerTest · red: миграция или CAS-путь без гоночного теста
e2e-http-through-gateway-only · ходи только HTTP через край (testing-newman.md#edge-is-newman) · TestNewmanConsumersReachTheSpineThroughTheSuiteBinding · red: кейс зовёт сервис напрямую
newman-case-workflow · прогони validate-cases.py, затем gen.py · validate-cases.py в ci.yaml; gen.py перед прогоном (newman-e2e.sh, newman-parallel.sh) · red: коллекция правлена руками
ryw-retry-first-own-read · клиентский bounded-retry: retry_until_authorized / retry_until_present · TestOwnFreshReadWrapPredicateWiredInEveryNewmanGenerator · red: кейс падает на 403/404 своего же созданного ресурса
ryw-retry-bounded-budget · конечный (~10s) и fail-open: по исчерпании падает реальный assert · TestOwnFreshReadWrapPredicateWiredInEveryNewmanGenerator · red: retry без предела либо проглатывающий отказ
ryw-retry-never-on-negatives · НИКОГДА — на негатив, cross-account, absent-id, lst-excludes, sync-4xx, давно существующий ресурс · TestDeleteRetryWindowGate_SilentWhenStepDeclares404AsItsOutcome · red: обёрнут negative-шаг
authz-first-negative-tolerance · oneOf([400,403,404]) — assert_absent_id_rejected / assert_unscoped_rejected · TestResponseCodeFormCorpusIsHonoredByEveryNewmanGenerator · red: STRICT-403 негатив ложно падает на authz-first отказе
malformed-id-not-weakened · НЕ ослабляй: они доходят до backend (400/404) · TestResponseCodeFormCorpusIsHonoredByEveryNewmanGenerator · red: в такой негатив добавлен 403
product-bug-go-fix-not-tolerance · Go-фикс с RED-lock, а не толерантность утверждения · ЗАВЕСТИ · red: в кейс добавлен лишний допустимый код вместо фикса
per-service-fixture-isolation · свой account и home/cross проекты (setup.sh), scope через existingProjectId; shared-account — только у authz-deny matrix · TestNewmanConsumersReachTheSpineThroughTheSuiteBinding · red: два suite делят account
run-idempotency-runid-suffix · {{runId}} в имени, и в max-len BVA · TestFixtureNamesObeyTheCanonWhereTheServiceMigrated · red: 409 AlreadyExists на повторном прогоне
final-verification-before-merge · go test -race, golangci-lint, govulncheck, newman гонит конвейер PR сборки; локально — быстрое своих пакетов, тяжёлое — слотом · `.github/workflows/ci.yaml` · red: вливание без одного из четырёх
code-first-no-wait · исполнитель пишет TDD, локально — быстрое своих пакетов (unit без `-race`, vet, gofmt), сдаёт коммитом и берёт следующую, не ждёт ревью и прогонов (владелец 2026-09-24) · вниманием · red: ждёт вердикта; `-race` или стенд в цикле TDD

## Прогон не оставляет следов (владелец 2026-10-07: «все тесты должны быть так, что бы не оставляли мусор»)

no-residue · снимай ВСЁ созданное и на падении, уборку заводи ДО создания (t.Cleanup/defer, trap EXIT): копии, TMPDIR, контейнеры/тома/сети testcontainers (ryuk off — лишь на эфемерном исполнителе), kind · scripts/residue-census/census.sh · red: уборка в конце тела; след после обрыва
no-residue-cluster · внешний кластер — своё пространство имён прогона, снимается trap'ом и на падении, PVC и LB с ним · census.sh, RESIDUE_KUBE=1 · red: ns, PV или LB после прогона
fixture-cleanup-mandatory · стенд: учётки и посев снимает тот же прогон, либо прогон в своём пространстве · TestSeededParentChildrenAreReclaimedBySuites; TestNestedReclaimGateRedsOnSeededParentLeak · red: пул растёт, list-контракты плывут
no-residue-census · приёмка — `census.sh snapshot` до и после, `compare` → 0; исключение — отчёт красного под `--keep`, ≤ 7 суток · residue-census/inject.sh · red: «убрал» без переписи; VOID-ось названа чистой; отчёт без срока
no-residue-found-is-task · набор без уборки — задача P2 владельцу набора; копии снимает git-operator через `worktree remove` · ЗАВЕСТИ · red: чужая уборка мимоходом; rm -rf копии

## План опыта задачи-проверки (решение владельца 2026-09-24)

exp-plan-parallel · задаче-проверке (проба, гейт, страж, инвариант безопасности) `check-verifier` пишет план опыта ПАРАЛЛЕЛЬНО коду: инъекции, близнецы, слепые зоны · ЗАВЕСТИ · red: план задаче не-проверке; код ждёт плана
exp-plan-self-run · план, пришедший до сдачи, прогони сам — исход по каждому пункту с командой; пришедший после гонит `check-verifier` на сборке · ЗАВЕСТИ · red: пункт плана без исхода; «прогнан» без команд
exp-plan-acceptance · приёмка на сборке повторяет план и ищет вне его · `check-verifier` §3 · red: вердикт — пересказ исходов автора, опытов вне плана ноль
exp-plan-old-hole-own-task · дыру, которую правка не вносила, в полосе не чини · `git-issues.md#gi-find-own-issue` · red: полоса разрослась прежней дырой

## Regression-lock security/leak-фиксов

regression-lock-at-observable · локай НАБЛЮДАЕМОЕ поведение, не только gRPC-код; видимое через край — и newman-кейсом · regression-тест в том же PR · red: рефактор вернул баг, suite зелёный
error-leak-assert-message-text · assert Message()=="internal error" либо NotContains(msg,<raw>) · internal/repohygiene/sqlstatehome_test.go (смежный) · red: тест проверяет только codes.Internal
pii-assert-log-both-paths · assert NotContains(logBuf,<email/token>) на success- И error-пути · ЗАВЕСТИ · red: проверен только успешный путь
apiconv-assert-exact-text · assert точный текст, усечение и код · TestErrorMappersTailReturnsAFixedText · red: проверен только код
security-fix-test-same-pr · behaviour-level regression-тест — в ТОМ ЖЕ PR; handler-level unit, путь края — и кейс тестировщика (testing-newman.md#flow-bug-regression) · ЗАВЕСТИ · red: фикс без теста либо тест только code-level
concurrency-fix-race-deterministic · тест под -race, детерминированно (blocker держит слот, Stop→Wait завершается) · TestWaitOrderGateRedOnSleepLoopWait · red: time.Sleep в тесте гонки

## Гейт на класс: измерить по дереву, доказать инъекцией, снабдить проверкой предпосылки

fix-class-not-instance · измерь по всему дереву (запрос по синтаксису/AST), назови число, почини все вхождения · ЗАВЕСТИ · red: починено там, где нашли; число не названо
gate-proven-by-injection-both-ways · инъекция в обе стороны: дефект → краснеет и называет координату; законный близнец той же формы → молчит · *_injection_test.go рядом с гейтом · red: у гейта нет пробы на законный близнец
primacy-judged-by-position-not-only-text · «текст первичен» — два утверждения врозь: дословность блока и его ПОЗИЦИЯ; уехавшая вниз цитата дословна, но не первична · tooling-gate check-11, ось C · red: гейт зелен на блоке, перенесённом вниз
recognizer-built-from-class-not-form-list · распознаватель — ОТ КЛАССА; перечень форм выводи обходом дерева и называй границу обхода · tooling-gate check-11, ось C · red: мимо перечня прошла форма, которой в нём не было
injection-drops-only-its-subject · роняй ТОЛЬКО проверяемое; прогонов три — контроль, инъекция нового, инъекция старого · TestAxisSixAndAxisTwoRedSeparately · red: красное пришло от соседа
anchor-judges-substance-not-key · якорь нормы — ДОСЛОВНЫЙ фрагмент её императива, а не id: id переживает выворачивание тела · tooling-gate check-11, `norm` · red: гейт зелен на теле, разрешающем обратное, при сохранённом ключе
pressure-clause-anchored-with-its-limiter · клаузулу давления и её ограничитель закрепляй ОДНИМ вызовом в одном файле · tooling-gate check-11, функция `pair` (пар ноль — код 2) · red: «ищи обход» под якорем, «среди безопасных способов» — ничем
injection-inverts-body-not-renames-key · инъекция в норму выворачивает ТЕЛО при сохранённом ключе; переименование ключа — тавтология · tooling-gate inject.sh, пробы check-11 · red: проба «норма снята» роняет собственный литерал предиката
presence-predicate-is-monotone · предикат ПРИСУТСТВИЯ слеп к ослаблению-дописыванию; охраняемый раздел суди отпечатком целиком · tooling-gate check-11 ось D, owner-escalation-fingerprint.txt · red: в раздел дописана оговорка, гейт зелен
ledger-sanction-names-its-fingerprint · строку узаконивания привязывай к узаконенному: основание на ПРИСУТСТВИИ переживает любой новый отпечаток · tooling-gate check-11 ось D · red: отпечаток обновлён, основание прежнее, гейт зелен
probe-must-be-read-by-its-subject · постусловие пробы — «проверка это ПРОЧИТАЛА»: вывод на правленой копии отличен от контрольного · rules-gate measure-monotonicity.sh · red: проба мимо предмета
gate-checks-its-premise · несёт проверку СВОЕЙ предпосылки и падает на её отказе · TestUseCaseLayoutPremiseHolds; TestConsoleMutationGatePremiseIsChecked · red: запрет стал ложью молча
census-separate-from-findings · перепись отдельно: «ноль находок» отличимо от «ноль прочитанных файлов» · TestEmptyTreeYieldsZeroCensusNotSilentGreen; TestEmptyWalkIsNotAVerdict · red: гейт зелен на пустом обходе
premise-rechecked-on-wider-population · перепроверь ПРЕДПОСЫЛКУ, а не только новые элементы · ЗАВЕСТИ · red: новые элементы стали нарушителями, ничего не нарушив

### Гейт читает исполняемую часть, а не текст

gate-reads-code-not-text · различай код, строковый литерал и комментарий; предпочитай AST тексту · TestPhantomIdGateReadsCodeNotComment; TestPipefailCheckReadsCodeNotProse · red: слово найдено в комментарии

exemption-expires-with-subject · истекает сам: запись, которой нечего исключать, — находка · TestSkipIsNotPassInjection_ExemptionWithNothingToExcludeIsFound · red: запись переживает свой предмет
reference-impl-must-name-artifact · назови файл и имя теста, который свойство держит · git grep -c 'func Test<имя>' · red: звание есть, артефакта нет
test-title-wider-than-body · закрепляй гейтом по дереву, не прямым вызовом проверки · ЗАВЕСТИ · red: тело зовёт проверку напрямую
double-must-honor-real-contract · выполняй контракт настоящего ТЕМ ЖЕ кодом, не своей копией · TestModuleMockFactoryResolvesItsDoubleStatically · red: дублёр глотает то, на чём настоящий отказывает
fake-structurally-unable-to-be-green · сделай структурно неспособной дать зелёное; провязку доказывай тем, что её позвали · TestInjectedBothFormsBlindRecogniserIsNotGreen · red: заглушка сочиняет отчёт
injection-not-reading-proves-holder · проверяй инъекцией, не прочтением; опровергнутую записывай рядом с тестом · ЗАВЕСТИ · red: вывод сделан чтением кода

### Распознаватель обязан знать ВСЕ законные формы записи предмета (выведено 2026-08-24)

recognizer-knows-all-lawful-forms · назови КАЖДУЮ законную форму записи и докажи инъекцией по каждой · TestConsoleProbeTypeCoverageKnowsEveryLegalPatternForm · red: форма вне наблюдения — молчание
blind-zone-measured-by-census · сравни осмотренное и найденное: перепись выросла при прежней полосе = была слепая зона · internal/repohygiene/removedpathcensus_injection_test.go · red: расширение холостое
form-list-derived-by-walk · выводи тем же обходом дерева, что и перепись, а не по памяти · ЗАВЕСТИ · red: список форм составлен по памяти

restructured-gate-reinjected · прогони инъекцию ЗАНОВО тем же дефектом · повторный *_injection_test.go · red: сверены лишь числа переписи
finding-text-is-part-of-property · проверяй инъекцией не только «покраснел», но и ЧТО напечатал — причину, не симптом · ЗАВЕСТИ · red: находка называет «процесс не завершился успехом»
subject-removal-audit-by-sign · разбери проверки по ЗНАКУ: негативная замолкает молча, её инъекция остаётся зелёной · ЗАВЕСТИ · red: вход больше не представим
subject-removal-two-outcomes · исходов два: снять вместе с предметом ОДНИМ изменением либо перевести на производимый деревом признак + инъекция · TestGateCarrierRemoval_ControlIntactCorpusIsSilent · red: «оставить как есть»
header-fixed-in-same-change · правь ТЕМ ЖЕ изменением, что снятую ветвь · TestGeneratorHeaderDocstringReaderTakesTheWholeLiteral · red: заголовок перечисляет снятое свойство

## Подпорка ЗЕЛЕНИТ вердикт — и потому её реже заводят предметом (решение владельца 2026-08-22)

prop-value-named-by-measurement · называй замером, а не наугад · TestCiRelaxationSaysWhyItIsThere · red: число без предиката, «поставил побольше»
prop-has-subject-issue · заводи предмет: issue с причиной и предикатом снятия · TestCiRelaxationSaysWhyItIsThere · red: послабление без номера рядом
prop-removed-with-cause · снимай вместе с причиной · TestPostureRelaxationExpiresWhenItsSubjectIsGone · red: задача закрыта, послабление осталось
prop-against-growth-needs-subject · от роста — отсрочка с известной датой отказа, предмет обязателен · TestCiRelaxationSaysWhyItIsThere · red: поднят предел там, где растёт потребление

## Четыре класса проверок, найденные за эпик identity (2026-08-23)

positive-control-needs-nonempty · требуй НЕПУСТОГО предмета; счёт строк разметки не годится · TestEdgeCatalogBlockStorageGate_FindsAnEmptyPositiveControl · red: «флажков нет» зеленеет там, где нет ничего
selfcheck-on-synthetic-not-live-entry · строй на синтетике в t.TempDir(), не на живой записи его ведомости · TestBakedLedgerInjection_EntryWithoutSubjectIsFound · red: ведомость опустела — самопроверка покраснела
empty-ledger-must-pass · обязан проходить (то же, что `testing-verdict.md#probe-passes-on-empty-ledger`) · TestBakedLedgerInjection_AnEmptyLedgerIsTheGoalNotAFailure · red: соблазн вернуть запись ради зелёного
ledger-pair-second-half · заведи обе: запись без предмета — находка, запись С предметом — молчание · TestBakedLedgerInjection_EntryWithASubjectIsSilent · red: пара односторонняя
shared-source-instead-of-reading-text · общий источник, импортируемый обеими сторонами, — вместо чтения чужого исходника · TestPostureVocabularyHasASingleSource · red: гейт добывает чужой предикат чтением текста
local-run-says-how-many-executed · «отказов 0» — не вердикт, пока не сказано, сколько исполнилось · scripts/hooks · red: «отказов 0, НЕ выполнено 6» прочитано как зелёное
console-packages-need-npm-ci · ставь зависимости консоли как `ui.yml` до прогона; MODULE_NOT_FOUND — не красный вердикт · scripts/hooks · red: каждая отправка молча недопроверяет

## Семь красных прогонов

env-value-asked-not-written · спрашивай у самой полосы, не выписывай литералом · TestQuotaShowPosture_HardcodedDeclaredIsAFinding · red: литерал с комментарием «объявлено посадкой»
ledger-exact-not-ceiling · записывай точным числом по факту, не потолком · TestBaselineHoldsAnExactCountNotACeiling; TestBeyondGoInjection_LedgerCeilingIsAFinding · red: ведомость прощает 42 при 36 находках

## Предикат по ДВУЯЗЫЧНОМУ корпусу, ищущий на одном языке, недобирает МОЛЧА (выведено 2026-08-23)

bilingual-predicate · ищи на обоих языках либо по координате, от языка не зависящей · ЗАВЕСТИ · red: числа разошлись — предикат меряет язык
bilingual-second-run-before-naming-number · прогони предикат со вторым языком; разошлось — смени единицу счёта · ЗАВЕСТИ · red: число названо по одному языку
predicate-answers-what-doc-refutes · отвечай на «что этот документ опровергает», не «где встречается слово»; перебор так же негоден, как недобор · ЗАВЕСТИ · red: большее число названо починкой

