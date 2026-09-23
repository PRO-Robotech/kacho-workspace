---
name: rule-e2e-flow
description: "Сквозные пробы: newman (API) и playwright (браузер) — единый флоу"
---

**Архив** (доводы, замеры, снятые редакции): `.claude/backup/e2e-flow.md`

# Сквозные пробы: newman (API) и playwright (браузер) — единый флоу

## §1. Вердикт: исходов ТРИ, и считаются они по числам

verdict-three-outcomes · считай три: зелёный · красный · «не выполнилось»; третий не вычитается и не зачитывается в успех · assert-suites-green.sh`, `aggregate-shard-verdicts.py · red: «suite passed» при нуле исполненных коллекций
missing-report-is-failure · считай провалом · assert-console-probes-verdict.py, shard-verdict.py (missing) · red: отчёт не создан, шаг зелёный
all-declared-executed · исполняй всё: число проб в отчёте сверяй с числом объявлений · exec-coverage.py`, `assert-console-probes-verdict.py · red: проба выпала из набора вместе со своим утверждением
four-request-outcomes · считай раздельно четыре: упавшее утверждение · запрос без ответа · упавший скрипт · отчёт с нулём утверждений · assert-suites-green.sh` + `shard-verdict.py · red: одна цифра «failed»
counts-from-stats · бери из `run.stats`, перечень упавшего — из `run.failures`; `run.executions` для счёта не используй · assert-report-readers-use-the-summary.py · red: обход `executions[]` с суммированием

### Послабление выдаётся под ДОКАЗАТЕЛЬСТВО — и форм доказательства бывает несколько

proof-forms-all-known · знай ВСЕ формы доказательства чужого отказа · precondition_mark_test.py`, `precondition_outcome_test.py · red: печатает «доказательства нет», а доказательство стоит в том же выводе выше
proof-two-signs · требуй ДВУХ признаков сразу: фразы о недостижимости И сетевой причины в том же выводе · tests/newman/scripts/precondition_mark_test.py · red: одной фразы хватило — опечатка в адресе прошла за внешний отказ
classifier-separate-file · держи отдельным файлом; инъекция перечисляет обе стороны каждой оси, включая ту, где послабление НЕ выдаётся · precondition_mark_test.py · red: различение проверяется только подъёмом стенда

## §2. Маски, пропуски и вычеты — запрещены (директива владельца 2026-07-29)

ban-mask · запрещены · assert-suites-green.sh (вычета нет by construction) · red: вычет перед решением
ban-skip · запрещены · assert-console-probes-verdict.py · red: test.skip`, `pm.test.skip`, assert под `//
ban-setnextrequest-null · запрещён · exec-coverage.py §STATIC BANS · red: урон невидим вердикту по утверждениям
ban-bail · запрещён · exec-coverage.py (перепись исполненного) · red: остаток набора становится «не выполнилось», поданным как красное
ban-silent-known-red · называй числом, поимённо и с предикатом снятия в `docs/RESULTS.md` набора · docs/RESULTS.md набора · red: молчаливый вычет «известного красного»
exemption-self-expires · обязано истекать само · ciexemptionexpiry_test.go · red: запись, которой больше нечего исключать

## §3. Что именно утверждает кейс

assert-status-and-code · утверждай ПАРУ: HTTP-статус и gRPC-код · httpstatusproducer_test.go · red: oneOf с кодом, которого край произвести не может
ban-mutually-exclusive-oneof · запрещены в обе стороны · ЗАВЕСТИ ban-mutually-exclusive-oneof · red: метка обещает отказ, принимается 200; обещает успех, принимается 4xx
read-both-lanes · прочитай обе · ЗАВЕСТИ read-both-lanes · red: за двухполосным `oneOf` идёт опрос `/operations/{{имя}}` без проверки непустоты
assert-operation-outcome · утверждай ИСХОД операции · ЗАВЕСТИ assert-operation-outcome · red: done принят за успех; id чеканится до асинхронного отказа
negative-with-positive-control · ставь в паре с положительным контролем · ЗАВЕСТИ negative-with-positive-control · red: файл, где все утверждения ждут 4xx
status-set-computed · вычисляй вызовом библиотеки, не выписывай (край без `WithErrorHandler`: FAILED_PRECONDITION → 400) · httpstatusproducer_test.go · red: допуск на 412/422 — исход, которого не бывает, и он не краснеет никогда
symmetric-predicate · делай симметричным по обоим направлениям и перемеряй класс общей меркой · ЗАВЕСТИ symmetric-predicate · red: «было 20, стало 0» верно для предиката и неверно для класса

## Ожидание условия, не паузы

wait-condition-not-time · ждём УСЛОВИЕ: retry_until_authorized/retry_until_present, expect.poll/toBeVisible · newmanfreshreadwrap_test.go · red: sleep`, `waitForTimeout
real-pause-between-polls · ставь настоящую паузу (busy-wait перед `setNextRequest`) · ЗАВЕСТИ real-pause-between-polls · red: 30 итераций покрывают 0.15 с вместо секунд
retry-only-first-fresh-read · ставь только на первый доступ к своему свежему ресурсу · newmanfreshreadwrap_test.go · red: retry на negative, cross-account, absent-id
no-whole-probe-retry · не бывает: ни `retries` в playwright, ни перезапуска суиты · ЗАВЕСТИ no-whole-probe-retry · red: повтор скрывает гонку, ради которой проба написана
only-materialization-wait · одно: окно материализации прав (`Operation.done` = durability, не видимость owner-tuple) · ЗАВЕСТИ only-materialization-wait · red: любое другое ожидание — маска

## §5. Фикстура, данные, изоляция

probe-brings-own · приносит своё и убирает за собой · ЗАВЕСТИ probe-brings-own · red: общий арендатор: вердикт — функция порядка прогонов
fixture-not-lenient · не снисходительнее продукта · ЗАВЕСТИ fixture-not-lenient · red: дублёр глотает вход, на котором настоящий отвечает отказом
fixture-cheap-subject-real · заводи там, где дешевле (краем); через интерфейс — только когда сама форма создания и есть предмет · ЗАВЕСТИ fixture-cheap-subject-real · red: проба про диалог удаления начинается с формы создания
setup-step-asserts-itself · утверждает свой исход · ЗАВЕСТИ setup-step-asserts-itself · red: падение называет виновником следующий шаг
fixture-value-distinguishable · делай отличимым от настоящего · newmanfixturenameform_test.go · red: правдоподобный литерал прячет дефект, который сам и кормит
other-fixture-is-other · обязана быть другой · ЗАВЕСТИ other-fixture-is-other · red: existingRegionAltId == existingRegionId
names-carry-runid · несут {{runId}} · newmanfixturenameform_test.go · red: повторный прогон ловит 409 AlreadyExists
fixture-helper-verified-read · доводит асинхронную мутацию до проверенного ЧТЕНИЕМ ресурса и в тексте отказа отличает условие от предмета · ЗАВЕСТИ fixture-helper-verified-read · red: отказ обвиняет невиновный шаг
catalog-values-from-edge · спрашивай у края · ЗАВЕСТИ catalog-values-from-edge · red: вписанный литерал разошёлся с посадкой стенда молча
no-reassert-unit-property · сквозной пробой не переутверждай; ответ выкаченного края модульная не видит — его сверка с интерфейсом не переутверждение (testing-newman.md#edge-double-check) · ЗАВЕСТИ no-reassert-unit-property · red: два места об одном предмете разошлись молча

## §6. Стенд, условие прогона, конвейер

precondition-not-verdict · не вердикт: отдельный шаг, отдельное сообщение · шаг «адрес консоли разрешается» в console-e2e.yml · red: стенд не поднялся, шаг зелёный либо красный как тест
step-timeout · несёт свой timeout-minutes · console-e2e.yml · red: зависание съедает джобу, вердикта нет ни у одной пробы
teardown-always · под if: always() · console-e2e.yml · red: обрыв по пределу оставляет кластер поднятым
suite-two-consequences · заводи оба следствия: шаг-гейт и путь артефактов · check-newman-suite-gates.py · red: набор исполняется, краснота не валит job, отчёты не сохраняются
shard-coverage · ровно у одного шарда; сумма равна числу коллекций дерева · assert-shard-coverage.py · red: коллекция есть, её не берёт никто
stand-provenance-before · спрашивай ПЕРЕД прогоном и печатай в отчёт · make stand-provenance (deploy/), остаток — долг D5 · red: «против чего гоняли» восстанавливается допросом после истолкования вердикта

## Перенос между newman и playwright без объявленного различия

family-transfer · переноси в другую, пока не доказано обратное; различие законно только если названо в таблице §7 · ЗАВЕСТИ family-transfer · red: необъявленное различие семей

## §7а. ДОМ пробы — репозиторий её ПРЕДМЕТА, а не тот, через чей край она ходит (решение владельца 2026-09-12)

probe-home-by-subject · живёт в репозитории продукта, чьи СУЩНОСТИ утверждает; адрес, по которому ходит, дома не определяет · ЗАВЕСТИ probe-home-by-subject · red: проба службы в наборе платформы
probe-home-table · сущности службы → репозиторий службы, её край — собственный REST-фронт · связка службы с чужим доменом → репозиторий платформы, край · ресурсы службы в наборе платформы → снимается · предикат по REST-путям · red: коллекция, чей единственный домен — чужая служба
platform-no-reassert · не переутверждает сущности службы; исключение узко — проверить, что созданы нужные платформе ресурсы (фикстура, не предмет) · предикат по REST-путям · red: коллекция платформы с одиноким iam
probe-home-predicate · проверяй предикатом по REST-путям в объявлении кейса: в наборе службы находка — любой чужой домен, в наборе платформы — одинокий домен службы · ЗАВЕСТИ probe-home-predicate · red: правило без держателя
edge-adds-three · не переносится вместе с пробой: анти-BOLA даёт отказ раньше (толерантность 403 · ЗАВЕСТИ edge-adds-three · red: 404) · сокрытие существования — побайтово равный «не найдено» · таблица «внутренний тип → форма ответа владельца» | сверка производителя | переадресованная проба покраснела и это списали на поломку
move-three-outcomes · исходов три: переутвердить по фактическому производителю · оставить платформе, расщепив коллекцию · снять вместе с предметом · ЗАВЕСТИ move-three-outcomes · red: «ослабить, чтобы прошло»
holding-claim-home · вправе назвать дом приставкой `owner/name:`; резолвится в названном доме по идентичности рабочей копии · scripts/docs-gate/check-03-holding-claim-resolves.py ([VOID] в проход не засчитывается) · red: координата, пережившая своё дерево

## §8. Порядок работ

case-is-tree-artifact · артефакт дерева: правь источник (`cases/*.py`, `specs/*.spec.ts`), не сгенерированное · gen.py / typecheck · red: правка коллекции
order-validate-then-gen · прогони `validate-cases.py` (где есть) → `gen.py` либо typecheck · services/*/tests/newman/scripts/validate-cases.py · red: сгенерированное разошлось с источником
new-suite-four-things · заводи все четыре: шаг-гейт с каталогом · путь отчётов в артефактах · назначение шарду · CASES-INDEX.md · check-newman-suite-gates.py`, `assert-shard-coverage.py · red: набор исполняется и никого не роняет
remove-probe-with-subject · снимай вместе с предметом · ЗАВЕСТИ remove-probe-with-subject · red: проба утверждает несуществующее либо не может упасть

## Долг без держателя

debt-d5-provenance · завести: ревизия спрашивается до прогона (`make stand-provenance` по образу ЗАПУЩЕННОГО контейнера) и попадает в отчёт автоматически · deploy/ (make stand-provenance) · red: стенд исполняет две чужие ревизии сразу
debt-d9-third-family · либо в прогон с гейтом, либо снять · deploy/e2e/0.1/*.sh (8 файлов) · red: никем не запускается
debt-named-by-number · стоит в таблице долга и НЕ действует; называй числом и предикатом · ЗАВЕСТИ debt-named-by-number · red: ссылка на неё как на правило

## Внешние практики: взятое и отвергнутое

fixture-factory-reads-error · фабрика обязана читать `error`, не только id: id чеканится до асинхронного отказа · ЗАВЕСТИ fixture-factory-reads-error · red: фабрика возвращает id и не проверяет `error` — асинхронный отказ уходит непрочитанным
rej-pact · отвергнуто: предмет закрыт дешевле `buf breaking` + гейтами каталога + reason-token · buf breaking, internal/repohygiene/catalog*.go · red: третий механизм об одном предмете

## §11. Каскад от общей фикстуры: пять падений с ОДНИМ текстом — это один дефект

cascade-same-text · сначала сверь ТЕКСТЫ отказа: дословно совпадающий у нескольких проб — одна причина в общей фикстуре · ЗАВЕСТИ cascade-same-text · red: чинят пробы поимённо вместо фикстуры
n-of-m-first · читай сперва «исполнено N из M», потом перечень упавших · exec-coverage.py · red: 5 из 66: о шестидесяти одной пробе не известно ничего
early-stop-not-mask · маской не является, не трогай · ЗАВЕСТИ early-stop-not-mask · red: шестьдесят одно падение по чужой причине
fixed-said-by-number · говори числом и только про исполненное, называя оставшееся неизвестным · tests/newman/scripts/exec-coverage.py · red: «все пробы проходят» при пяти исполненных

### Проба, чей предмет исчез, ЗАМЕНЯЕТСЯ, а не ослабляется

probe-replaced-not-weakened · исходов три: утверждать новое свойство того же предмета · снять вместе с предметом · остаться с записанным предикатом истечения · ЗАВЕСТИ probe-replaced-not-weakened · red: ослабление («уберём этот assert»)

