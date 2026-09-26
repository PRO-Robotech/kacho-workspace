---
name: rule-testing
description: "Тестирование (строгий TDD)"
---

**Архив** (доводы, замеры, снятые редакции): `.claude/backup/testing.md`

# Тестирование (строгий TDD)

## Части этого правила

| файл | предмет |
|---|---|
| `.claude/rules/testing-verdict.md` | чтение вердикта прогона: текст отказа, недействительный прогон, самоистекающие пробы, слепой разборщик |
| `.claude/rules/testing-newman.md` | сквозные пробы newman: край, свод классов и флоу кейса, eventual-consistency, поллер, параллельный прогон |
| `.claude/rules/testing-load.md` | замер под нагрузкой: что делает числа недействительными |

## E2E НИКОГДА не пропускаются — только честные тесты (директива владельца 2026-07-29)

e2e-no-skip-ever · НИКОГДА не пропускай, не маскируй, не ослабляй; зелёное добывай фиксом продукта или фикстуры · assert-suites-green.sh; TestSkippedVerdictDoesNotPassAsGreen · red: кейс исключён из набора, ослаблен assert, зелёное получено сужением вопроса
e2e-ban-mask-whitelist · запрещены в прогонщике и в гейте · TestEveryGateSkipIsDeclaredInTheLedger; TestRunnerStemSetInjectionWrittenListIsFound · red: в прогонщике или гейте есть выписанный список исключаемых кейсов
e2e-ban-skip-comment-assert · запрещены · git grep -n 'pm.test.skip' tests/newman → 0 · red: в кейсе стоит skip либо assert закомментирован
e2e-ban-exit-code-loss · не теряй: запрещены · true`, `cmd · red: tee, вердикт с последнего звена | TestPipefailVerdictNeverComesFromAPipe; TestExitCodeReadGateFindsTheDefectiveForms | вердикт взят из трубы или из шага, следующего за прогоном
e2e-ban-mutually-exclusive-assert · запрещено принимать взаимоисключающие исходы · TestResponseCodeFormCorpusIsHonoredByEveryNewmanGenerator · red: oneOf([200,400]) в кейсе, чей заголовок обещает отказ
e2e-fixture-step-must-assert · утверждай статус И захват id; поллер несёт идентификаторы фикстуры · TestNewmanPrecondMark_ProvenByInjection; TestCapturedVarGateSilentOnLawfulSameShape · red: if (!lastOpError); шаг захватил id без assert; кейс падает на три шага позже
third-category-not-pass · считай третьей категорией: не вычитай из вердикта и не объясняй · TestThirdCategorySignalReachesTheSummary · red: в итоге «отказов 0» без числа исполненного
e2e-missing-dep-own-job · дай ему свою job/волну, создающую условие; не можешь — запиши открытый долг с числом · TestActorExemptionRequiresAScarceRunnerThatExists · red: кейс замаскирован «здесь его не запустить», суита объявлена зелёной
e2e-red-means-investigate-product · разбирай продукт; маску не возвращай даже временно · TestEveryGateSkipIsDeclaredInTheLedger · red: запись «известное красное» живёт дольше своего фикса
e2e-verdict-by-numbers · называй числами: коллекций с отчётом из скольких · запросов · утверждений · упавших · без ответа · пустых отчётов · assert-suites-green.sh:387 · red: суита без отчётов названа зелёной
exclusion-self-expires · обязан истекать сам: запись без предмета — находка · TestPostureRelaxationExpiresWhenItsSubjectIsGone · red: гейт зелёный на записи, которой нечего исключать

## Test-first — обязательно (ban #12)

test-first-red-before-code · напиши и ПРОГОНИ до кода; подтверди причину падения; реализатор — Go unit/integration, newman-кейс края — тестировщик (testing-newman.md#edge-author-black-box) · пара RED→GREEN в отчёте PR · red: тест написан после кода, хотя зелёный
chunk-all-reds-first · напиши ВСЕ падающие тесты первыми, получи RED по всем, чини по одному · ЗАВЕСТИ chunk-all-reds-first · red: первый фикс сделан раньше последнего RED
report-red-green-pair · покажи пару RED→GREEN в PR/отчёте · ЗАВЕСТИ report-red-green-pair · red: готовность заявлена без пары прогонов
new-rpc-integration-test · в том же PR — integration_test.go на testcontainers Postgres, включая concurrent-race для CAS/UNIQUE/EXCLUDE · git diff PR: новый RPC → новый *integration_test.go · red: PR добавляет RPC без integration-теста
new-rpc-newman-case · новый RPC или HTTP-путь края — в том же PR newman-кейс tests/newman/cases/*.py, ≥1 happy и ≥1 negative; пишет тестировщик по заказу автора (testing-newman.md#edge-author-black-box) · ЗАВЕСТИ new-rpc-newman-case (кандидат — coverage.py маршрут→кейс) · red: путь на крае есть, кейса нет
no-tests-no-excuse · запрещено как обоснование отсутствия тестов; reviewer отклоняет PR без тестов · TestDeferralGateCatchesAMarkerInProductionCode · red: в PR стоит обещание вместо теста
tests-followup-issue-form · форма `Tests-followup: #<N>` на открытый issue, привязанный к эпику ДО merge · tools/knownfailingsubject · red: ссылка на issue, заведённый после merge

## Test-only PR (ban #13)

no-todo-skip-in-tests · запрещены так же строго, как в проде · TestDeferralGateCatchesAMarkerInProductionCode · red: маркер отсрочки в tests/
tdd-red-case-links-issue-no-skip · пометь `# verifies <issue-url>` и НЕ ставь skip · tools/knownfailingsubject · red: кейс отключён вместо пометки
known-failing-declared · объяви в RESULTS.md «Known failing — product bugs» + trail в vault · tools/knownfailingsubject · red: красный кейс не объявлен и читается как регрессия
test-only-pr-no-prod-code · трогай только tests/ и docs/; любой internal/cmd/migrations-фикс — отдельный PR со своим issue · ЗАВЕСТИ test-only-pr-no-prod-code · red: в test-only PR правлен internal/

## Пирамида и инфраструктура

unit-mock-ports-no-sleep · мокай port-интерфейсы (repomock/kachomock); LRO дожидайся детерминированно AwaitOpDone · TestWaitOrderGateRedOnSleepLoopWait · red: time.Sleep вместо AwaitOpDone
usecase-needs-postgres-is-leak · считай утечкой adapter в use-case и чини слой · TestUseCaseLayerHasOneLayout · red: usecase_test.go поднимает контейнер
integration-covers-sql-races · покрой CRUD, EXCLUDE/FK/UNIQUE, outbox-транзакционность, CAS/OCC/SKIP-LOCKED гонки на testcontainers Postgres 16 · TestNoPackageStartsAContainerPerTest · red: миграция или CAS-путь без гоночного теста
e2e-http-through-gateway-only · ходи только HTTP через край (testing-newman.md#edge-is-newman) · TestNewmanConsumersReachTheSpineThroughTheSuiteBinding · red: кейс зовёт сервис напрямую
newman-case-workflow · прогони validate-cases.py, затем gen.py · validate-cases.py в ci.yaml; gen.py перед прогоном (newman-e2e.sh, newman-parallel.sh) · red: коллекция правлена руками
ryw-retry-first-own-read · оборачивай клиентским bounded-retry: retry_until_authorized / retry_until_present · TestOwnFreshReadWrapPredicateWiredInEveryNewmanGenerator · red: кейс падает на 403/404 своего же созданного ресурса
ryw-retry-bounded-budget · держи конечным (~10s) и fail-open: по исчерпании падает реальный assert · TestOwnFreshReadWrapPredicateWiredInEveryNewmanGenerator · red: retry без предела либо проглатывающий отказ
ryw-retry-never-on-negatives · НИКОГДА не ставь на негатив, cross-account, absent-id, lst-excludes, sync-4xx, давно существующий ресурс · TestDeleteRetryWindowGate_SilentWhenStepDeclares404AsItsOutcome · red: обёрнут negative-шаг — реальный deny замаскирован
authz-first-negative-tolerance · толерируй oneOf([400,403,404]) — assert_absent_id_rejected / assert_unscoped_rejected · TestResponseCodeFormCorpusIsHonoredByEveryNewmanGenerator · red: STRICT-403 негатив ложно падает на authz-first отказе
malformed-id-not-weakened · НЕ ослабляй: они доходят до backend (400/404) · TestResponseCodeFormCorpusIsHonoredByEveryNewmanGenerator · red: в такой негатив добавлен 403
product-bug-go-fix-not-tolerance · чини Go-фиксом с RED-lock, а не толерантностью утверждения · ЗАВЕСТИ product-bug-go-fix-not-tolerance · red: в кейс добавлен лишний допустимый код вместо фикса
per-service-fixture-isolation · держи свой account + home/cross проекты (setup.sh), scope через existingProjectId; shared-account только у authz-deny matrix · TestNewmanConsumersReachTheSpineThroughTheSuiteBinding · red: два suite делят account — grant течёт в чужие ожидания
run-idempotency-runid-suffix · вшей {{runId}} в имя, в том числе в max-len BVA · TestFixtureNamesObeyTheCanonWhereTheServiceMigrated · red: 409 AlreadyExists на повторном прогоне
fixture-cleanup-mandatory · убирай за собой · TestSeededParentChildrenAreReclaimedBySuites; TestNestedReclaimGateRedsOnSeededParentLeak · red: пул растёт, list-контракты плывут
final-verification-before-merge · go test ./... -race + golangci-lint run + govulncheck + newman гонит конвейер GitHub на PR сборки в ветку волны — раз на сведение и раз на пересведение; локально — быстрое своих пакетов (`code-first-no-wait`) и непокрытое конвейером, тяжёлое — слотом (`testing-verdict.md#busy-machine-step-zero`) · `.github/workflows/ci.yaml` на PR сборки · red: вливание без одного из четырёх; прогон на задаче; `-race` или полный набор исполнителем локально
code-first-no-wait · исполнитель пишет код строгим TDD, локально гоняет только быстрое по своим пакетам — unit без `-race`, vet, gofmt, свои пробы — и сдаёт коммитом в ветку задачи, затем берёт следующую задачу пачки: ревью и прогонов не ждёт, их даёт сборка (решение владельца 2026-09-24 «приоритет написания кода») · вниманием исполнителя; возврат называет sha сдачи и взятую следующую задачу · red: исполнитель ждёт вердикта или ревью задачи; `-race`, линт монорепо или стенд в цикле TDD

## План опыта задачи-проверки (решение владельца 2026-09-24)

exp-plan-parallel · задаче, чей предмет — проба, гейт, страж или инвариант безопасности, `check-verifier` составляет план опыта ПАРАЛЛЕЛЬНО коду: инъекции (одно-фактный дефект → какая проба обязана покраснеть), законные близнецы, слепые зоны класса; прочим задачам плана нет; инвариант безопасности — заводимый или меняемый контроль (проверка прав, граница слушателя, отзыв), а аннотация прав и строка каталога нового RPC по действующему правилу (`api-gateway-registrar`, `proto-sync`) — применение, его держит гейт каталога прав · ЗАВЕСТИ exp-plan-parallel · red: план заказан задаче не-проверке; код ждёт плана
exp-plan-self-run · план, пришедший до сдачи, прогони сам: исход по каждому пункту с командой; пришедший после — гонит `check-verifier` на сборке, сдача его не ждёт · ЗАВЕСТИ exp-plan-self-run · red: сдача без исхода по пункту плана из входа; «план прогнан» без команд
exp-plan-acceptance · приёмка на сборке повторяет план и ищет вне его · `check-verifier` §3 · red: вердикт — пересказ исходов автора, опытов вне плана ноль
exp-plan-old-hole-own-task · дыру, которую правка не вносила, заводи сразу отдельной задачей, в полосе не чини · `git-issues.md#gi-find-own-issue` · red: полоса разрослась прежней дырой; дыра названа и не заведена

## Regression-lock security/leak-фиксов

regression-lock-at-observable · локай НАБЛЮДАЕМОЕ поведение, не только gRPC-код; видимое через край — и newman-кейсом (testing-newman.md#flow-bug-regression) · regression-тест в том же PR · red: рефактор возвращает баг, suite остаётся зелёным
error-leak-assert-message-text · assert Message()=="internal error" либо NotContains(msg,<raw>) · internal/repohygiene/sqlstatehome_test.go (смежный) · red: тест проверяет только codes.Internal
pii-assert-log-both-paths · assert NotContains(logBuf,<email/token>) на success- И error-пути · ЗАВЕСТИ pii-assert-log-both-paths · red: проверен только успешный путь
apiconv-assert-exact-text · assert точный текст, усечение и код · TestErrorMappersTailReturnsAFixedText · red: проверен только код
security-fix-test-same-pr · несёт behaviour-level regression-тест в ТОМ ЖЕ PR; RPC без функционального теста — добери handler-level unit, путь края — и newman-кейс тестировщика (testing-newman.md#flow-bug-regression) · ЗАВЕСТИ security-fix-test-same-pr · red: фикс без теста либо тест только code-level
concurrency-fix-race-deterministic · тест под -race, детерминированно (blocker держит слот, Stop→Wait завершается) · TestWaitOrderGateRedOnSleepLoopWait · red: time.Sleep в тесте гонки

## Гейт на класс: измерить по дереву, доказать инъекцией, снабдить проверкой предпосылки

fix-class-not-instance · измерь механически по всему дереву (запрос по синтаксису/AST), назови число, почини все вхождения · ЗАВЕСТИ fix-class-not-instance · red: починено там, где нашли; число не названо
gate-proven-by-injection-both-ways · докажи инъекцией в обе стороны: дефект → краснеет и называет координату; законный близнец той же формы → молчит · *_injection_test.go рядом с гейтом · red: у гейта нет пробы на законный близнец
primacy-judged-by-position-not-only-text · «текст первичен» — ДВА утверждения, и оба судятся врозь: дословность блока и его ПОЗИЦИЯ среди разделов. Цитата, уехавшая в середину файла, остаётся дословной и первичной быть перестаёт · scripts/tooling-gate/check-11-owner-escalation-list-is-closed.sh (ось C: пять литералов + обход заголовков, первый нумерованный обязан быть `## 0.`) · red: гейт зелен на блоке, перенесённом вниз без правки текста
recognizer-built-from-class-not-form-list · распознаватель строй ОТ КЛАССА; перечисляешь формы — выведи их обходом дерева и назови, чем обход ограничен · там же (обход видит только `^## <число>.` вне оград кода; порядок — по положению в файле, не по значению номера) · red: перечень арм, и мимо него проходит форма, которой в перечне не было
injection-drops-only-its-subject · роняй ТОЛЬКО проверяемое; прогонов три — контроль, инъекция нового, инъекция старого · TestAxisSixAndAxisTwoRedSeparately · red: инъекция «завести ещё один элемент»; красное пришло от соседа
anchor-judges-substance-not-key · якорем на норму бери ДОСЛОВНЫЙ фрагмент императива на строке самой нормы, а не её идентификатор: id ничего не утверждает и переживает выворачивание тела наизнанку · scripts/tooling-gate/check-11-owner-escalation-list-is-closed.sh (функция `norm`: ключ и существо на одной строке) · red: гейт зелен на теле, разрешающем обратное, при сохранённом ключе
pressure-clause-anchored-with-its-limiter · клаузулу, создающую давление, и её ограничитель закрепляй ОДНИМ вызовом и в одном файле; якорь на одну сторону без другой — дефект · scripts/tooling-gate/check-11-owner-escalation-list-is-closed.sh (функция `pair` принимает обе стороны, пар ноль — код 2) · red: клаузула «ищи обход» под якорем, оговорка «среди безопасных способов» — ничем
injection-inverts-body-not-renames-key · инъекция в норму выворачивает ТЕЛО при сохранённом ключе; переименование ключа — тавтология на строке, которую вписал сам автор предиката · scripts/tooling-gate/inject.sh (пробы check-11: дефект и близнец — обе полная переписка строки, отличие одно — дословное существо) · red: проба зовётся «норма снята», а роняет собственный литерал предиката
presence-predicate-is-monotone · предикат на ПРИСУТСТВИИ монотонен по дописыванию: ловит снятие нормы и слеп к ослаблению — всякое ослабление есть ДОБАВЛЕНИЕ; охраняемый раздел суди отпечатком целиком · tooling-gate check-11 ось D, ведомость owner-escalation-fingerprint.txt · red: в раздел дописана оговорка, гейт зелен
ledger-sanction-names-its-fingerprint · строку узаконивания привязывай к узаконенному: основание на ПРИСУТСТВИИ переживает любой новый отпечаток · tooling-gate check-11 ось D · red: отпечаток обновлён, основание прежнее, гейт зелен
probe-must-be-read-by-its-subject · постусловие пробы — не «песочница изменилась», а «проверка это ПРОЧИТАЛА»: вывод на правленой копии обязан отличаться от контрольного на ней же · scripts/rules-gate/measure-monotonicity.sh · red: проба легла мимо предмета, замер объявил проверку монотонной
gate-checks-its-premise · несёт проверку СВОЕЙ предпосылки и падает на её отказе · TestUseCaseLayoutPremiseHolds; TestConsoleMutationGatePremiseIsChecked · red: факт о дереве изменился, запрет стал ложью молча
census-separate-from-findings · печатай перепись отдельно: «ноль находок» отличимо от «ноль прочитанных файлов» · TestEmptyTreeYieldsZeroCensusNotSilentGreen; TestEmptyWalkIsNotAVerdict · red: гейт зелен на пустом обходе
premise-rechecked-on-wider-population · перепроверь ПРЕДПОСЫЛКУ, а не только новые элементы · ЗАВЕСТИ premise-rechecked-on-wider-population · red: новые элементы стали нарушителями, ничего не нарушив

### Гейт читает исполняемую часть, а не текст

gate-reads-code-not-text · различай код, строковый литерал и комментарий; предпочитай AST тексту · TestPhantomIdGateReadsCodeNotComment; TestPipefailCheckReadsCodeNotProse · red: слово найдено в комментарии, объясняющем снятую защиту

exemption-expires-with-subject · истекает сам: запись, которой нечего исключать, — находка · TestSkipIsNotPassInjection_ExemptionWithNothingToExcludeIsFound · red: запись переживает свой предмет
reference-impl-must-name-artifact · назови файл и имя теста, который свойство держит · git grep -c 'func Test<имя>' · red: звание есть, артефакта нет
test-title-wider-than-body · закрепляй гейтом по дереву, не прямым вызовом проверки · ЗАВЕСТИ test-title-wider-than-body · red: тело зовёт проверку напрямую — заголовок шире тела
double-must-honor-real-contract · выполняй контракт настоящего ТЕМ ЖЕ кодом, не своей копией · TestModuleMockFactoryResolvesItsDoubleStatically · red: дублёр глотает ввод, на котором настоящий отказывает
fake-structurally-unable-to-be-green · сделай структурно неспособной дать зелёное; провязку доказывай тем, что её позвали · TestInjectedBothFormsBlindRecogniserIsNotGreen · red: заглушка сочиняет отчёт «1 утверждение, 0 упавших»
injection-not-reading-proves-holder · проверяй инъекцией, не прочтением; опровергнутую записывай рядом с тестом · ЗАВЕСТИ injection-not-reading-proves-holder · red: вывод сделан чтением кода

### Распознаватель обязан знать ВСЕ законные формы записи предмета (выведено 2026-08-24)

recognizer-knows-all-lawful-forms · назови КАЖДУЮ законную форму записи и докажи инъекцией по каждой · TestConsoleProbeTypeCoverageKnowsEveryLegalPatternForm · red: форма вне наблюдения: ни красного, ни зелёного — молчание
blind-zone-measured-by-census · сравни осмотренное и найденное: перепись выросла при прежней полосе = была слепая зона · internal/repohygiene/removedpathcensus_injection_test.go · red: перепись не изменилась — расширение холостое
form-list-derived-by-walk · выводи тем же обходом дерева, что и перепись, а не по памяти · ЗАВЕСТИ form-list-derived-by-walk · red: список форм составлен по памяти

restructured-gate-reinjected · прогони инъекцию ЗАНОВО тем же дефектом · повторный *_injection_test.go · red: сверены только числа переписи и зелёное на чистом дереве
finding-text-is-part-of-property · проверяй инъекцией не только «покраснел», но и ЧТО напечатал — причину, не симптом · ЗАВЕСТИ finding-text-is-part-of-property · red: находка называет «процесс не завершился успехом»
subject-removal-audit-by-sign · разбери проверки по ЗНАКУ: негативная замолкает молча, её инъекция остаётся зелёной · ЗАВЕСТИ subject-removal-audit-by-sign · red: ветвь и счётчик целы, вход больше не представим
subject-removal-two-outcomes · исходов два: снять вместе с предметом ОДНИМ изменением либо перевести на производимый деревом признак + инъекция · TestGateCarrierRemoval_ControlIntactCorpusIsSilent · red: «оставить как есть»
header-fixed-in-same-change · правь ТЕМ ЖЕ изменением, что снятую ветвь · TestGeneratorHeaderDocstringReaderTakesTheWholeLiteral · red: заголовок перечисляет снятое свойство

## Подпорка ЗЕЛЕНИТ вердикт — и потому её реже заводят предметом (решение владельца 2026-08-22)

prop-value-named-by-measurement · называй замером, а не наугад · TestCiRelaxationSaysWhyItIsThere · red: число без предиката, «поставил побольше»
prop-has-subject-issue · заводи предмет: issue с причиной и предикатом снятия · TestCiRelaxationSaysWhyItIsThere · red: послабление без номера рядом
prop-removed-with-cause · снимай вместе с причиной · TestPostureRelaxationExpiresWhenItsSubjectIsGone · red: задача закрыта, послабление осталось
prop-against-growth-needs-subject · спроси, от чего защищает: от роста — это отсрочка с известной датой отказа, предмет обязателен · TestCiRelaxationSaysWhyItIsThere · red: поднят предел там, где растёт потребление

## Четыре класса проверок, найденные за эпик identity (2026-08-23)

positive-control-needs-nonempty · требуй НЕПУСТОГО предмета; счёт строк разметки не годится · TestEdgeCatalogBlockStorageGate_FindsAnEmptyPositiveControl · red: «флажков нет» зеленеет там, где нет ничего
selfcheck-on-synthetic-not-live-entry · строй на синтетике в t.TempDir(), не на живой записи его ведомости · TestBakedLedgerInjection_EntryWithoutSubjectIsFound · red: ведомость опустела — самопроверка покраснела
empty-ledger-must-pass · обязан проходить · TestBakedLedgerInjection_AnEmptyLedgerIsTheGoalNotAFailure · red: соблазн вернуть запись ради зелёного
ledger-pair-second-half · заведи обе: запись без предмета — находка, запись С предметом — молчание · TestBakedLedgerInjection_EntryWithASubjectIsSilent · red: пара односторонняя
shared-source-instead-of-reading-text · заведи общий источник, импортируемый обеими сторонами, вместо чтения чужого исходника · TestPostureVocabularyHasASingleSource · red: гейт заводился ради одной копии предиката и добывает его чтением текста
local-run-says-how-many-executed · «отказов 0» — не вердикт, пока не сказано, сколько исполнилось · scripts/hooks · red: «отказов 0, НЕ выполнено 6» прочитано как зелёное
console-packages-need-npm-ci · ставь npm ci --prefix <пакет> до прогона; MODULE_NOT_FOUND — не красный вердикт · scripts/hooks · red: каждая отправка молча недопроверяет

## Семь красных прогонов

env-value-asked-not-written · спрашивай у самой полосы, не выписывай литералом · TestQuotaShowPosture_HardcodedDeclaredIsAFinding · red: рядом с литералом комментарий «объявлено посадкой»
ledger-exact-not-ceiling · записывай точным числом по факту, не потолком · TestBaselineHoldsAnExactCountNotACeiling; TestBeyondGoInjection_LedgerCeilingIsAFinding · red: ведомость прощает 42 при 36 находках

## Предикат по ДВУЯЗЫЧНОМУ корпусу, ищущий на одном языке, недобирает МОЛЧА (выведено 2026-08-23)

bilingual-predicate · ищи на обоих языках либо по координате, от языка не зависящей · ЗАВЕСТИ bilingual-predicate · red: числа разошлись — предикат меряет язык
bilingual-second-run-before-naming-number · прогони предикат со вторым языком; разошлось — смени единицу счёта · ЗАВЕСТИ bilingual-second-run-before-naming-number · red: число названо по одному языку
predicate-answers-what-doc-refutes · отвечай на «что этот документ опровергает», не «где встречается слово»; перебор так же негоден, как недобор · ЗАВЕСТИ predicate-answers-what-doc-refutes · red: расширили поиск и назвали большее число починкой

