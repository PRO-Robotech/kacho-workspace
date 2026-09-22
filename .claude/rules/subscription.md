---
name: rule-subscription
description: "Поток изменений ресурсов: что берут готовым, а что заводят сами"
---

**Архив**: `.claude/backup/subscription.md`

# Поток изменений ресурсов: что берут готовым, а что заводят сами

## Четыре решения

sub-form-singularity · одна на всех владельцев, в `proto/corelib/subscription/`; своей не заводи · subscriptionformsingularity · red: git grep -h 'returns (stream' -- proto | wc -l > 1
sub-server-singularity · один, в `corelib/subscription/`; владелец поднимает, не пишет · subscriptionserversingularity · red: второй сервер потока в дереве
sub-consumer-opens · открывает ПОТРЕБИТЕЛЬ (край); владелец о подписчиках не знает · ребро потребитель→владелец в polyrepo.md · red: владелец зовёт потребителя (цикл в графе)
sub-poll-not-retired · не отзывается: подписка — второй путь, для операций опрос единственный · api-conventions.md §подписок на операции нет · red: опрос снят вслед за подпиской

## Откуда берут готовое — перечень, а не поиск

sub-take-contract · бери контракт из `proto/corelib/subscription/` (2 файла), свой не заводи · ЗАВЕСТИ sub-take-contract · red: свой контракт подписки рядом с corelib-овым
sub-take-server · бери сервер потока из `corelib/subscription/`, владелец поднимает — не пишет · ЗАВЕСТИ sub-take-server · red: свой сервер потока вместо corelib-ового
sub-channel-reader · бери внутри сервера фундамента · subscriptionchannelreader · red: свой `LISTEN`/`NOTIFY` у владельца
sub-gateway-projection · бери gateway/internal/subscriptionstream/ · ЗАВЕСТИ sub-gateway-projection · red: вторая проекция
sub-console-client · бери ui-future/shared/src/lib/subscription/ (hub.ts, use-resource-stream.ts) + hooks/use-stream-coverage.ts · ЗАВЕСТИ sub-console-client · red: свой клиент потока в модуле
sub-kind-vocabulary · правь только ui-future/shared/src/lib/subscription/subjects.ts · subscriptionkindvocabulary · red: вторая точка правки написания вида
sub-tenant-page · дополняй gateway/docs/content/api/subscription.mdx · subscriptionownerdocs_test.go · red: вторая страница
sub-package-no-version · corelib.subscription, без сегмента версии · subscriptionformshape · red: доменная версия в имени пакета

## Что заводит САМ владелец — ровно три вещи

sub-journal-table · заводи таблицу `<svc>_outbox` в своей БД миграцией · outboxpendingindexperservice_test.go · red: журнал в чужой схеме или без частичного индекса
sub-write-same-tx · пиши в ТОЙ ЖЕ транзакции, что ресурсная строка · journalwriteforms + integration-проба на откат · red: событие есть при откате мутации
sub-own-journal-file · отдаёт журнал, ворота проекта и состояние предмета; сервер поднимается одной строкой композиционного корня · subscriptionserversingularity · red: своя механика вместо журнала
sub-predicate-two-trees · обходи ОБА дерева (`kacho` `services/**`, `kaname` корень) · grep -l 'subscription.NewServer' по обоим · red: «шестого нет» = «я туда не смотрел»
sub-sixth-owner-axis · заводит своего производителя снятия: оболочка события несёт один якорь project_id · ось якоря — corelib#5 · red: снятие судится по пустому якорю

## Состояние: «его нет» — ПЕРВОКЛАССНЫЙ случай, а не пустое поле

sub-state-unavailable · скажи словом в state_unavailable, не присылай пустое state · subscriptionstatelabels` + `subscriptionstatedocs_test.go · red: state нулевой длины: «состояния нет» неотличимо от «состояние пустое»
sub-refetch-not-apply · ПЕРЕЧИТЫВАЙ по событию, не применяй состояние из него · invalidateQueries` в `hub.ts · red: два источника одного состояния, мерцание строки

## Фильтр подписки

sub-filter-three-axes · три оси — виды · проект · идентификаторы, конъюнкцией, все иммутабельные · ЗАВЕСТИ sub-filter-three-axes · red: мутабельная ось в фильтре
sub-no-name-filter · не заводи: имя — мутабельный ярлык (ban #15) · ЗАВЕСТИ sub-no-name-filter · red: подписка молча перестала матчить после переименования
sub-no-label-filter · оставь клиенту: событие несёт полное состояние, не дельту · ЗАВЕСТИ sub-no-label-filter · red: серверный фильтр по меткам: «вышел из выборки» и «удалён» неразличимы

## Как это провязывается в консоли — и почему GET-запросы остаются

sub-stream-kills-timer · снимает ТАЙМЕР, а не запрос: `refetchInterval: streamed ? false : N`, событие гасит кэш → один GET · use-stream-coverage.ts · red: на покоящейся странице запросы идут периодически; либо оба механизма разом
sub-no-journal-poll-forever · оставляй на опросе навсегда и скажи это словами в коде · hub.covers() · red: умолчание вместо утверждения
sub-coverage-from-producer · выводи у производителя (`knownKinds` первым кадром, `hub.covers()`), не выписывай перечнем · subscriptionkindvocabulary · red: выписанный перечень разошёлся с владельцем молча

## Край: перечень владельцев ЗАКРЫТ, пустой означает «никого»

sub-owners-knob-closed · перечень закрыт; пустое значение — отказ «владелец не объявлен» (501) · ЗАВЕСТИ sub-owners-knob-closed · red: пустое открывает поток ко всем
sub-empty-list-semantics · СУЖАЮЩИЙ значит «не сужаем», РАЗРЕШАЮЩИЙ значит «никого» · ЗАВЕСТИ sub-empty-list-semantics · red: семантика выбрана по аналогии, а не по тому, что ручка перечисляет
sub-two-dictionaries · скажи, из какого словаря берутся имена (имя proto-пакета ≠ имя каталога сервиса) · комментарий ручки + bootgateknobproducer_test.go · red: «неизвестный владелец» у клиента, отказ старта края у оператора

## Гейты

sub-gates-print-scope · печатай объём осмотренного и падай на пустом обходе · internal/repohygiene/*_injection_test.go · red: зелёный при нулевом обходе
gate-form-singularity · одно · subscriptionformsingularity · red: второе объявление
gate-server-singularity · один, и он в фундаменте · subscriptionserversingularity · red: сервер у владельца
gate-channel-reader · ни один владелец не заводит своего · subscriptionchannelreader · red: свой читатель канала
gate-kind-vocabulary · берётся у производителя · subscriptionkindvocabulary · red: выписанный литерал вида
gate-form-shape · читается одним разбором контракта · subscriptionformshape · red: форма, не поддающаяся одному разбору
gate-form-reach · доезжает до сервера · subscriptionformreach · red: объявление, не дошедшее до сервера
gate-journal-write-forms · знает ВСЕ формы записи · journalwriteforms · red: неизвестная разбору форма записи
gate-journal-cursor · не берётся по голому номеру · journalcursorupperbound · red: курсор по голому id
gate-state-labels · несёт метки · subscriptionstatelabels · red: состояние без меток
gate-judges-ast-node · опознавай предмет узлом синтаксического разбора, а не словом · internal/repohygiene/subscriptionchannelreader.go · red: имя типа, комментарий и текст ошибки прошли за предмет (17 файлов при одном операторе)

## Как это ТЕСТИРУЮТ

sub-owner-test-transaction · утверждай ТРАНЗАКЦИЮ: откат мутации не оставляет события · integration-проба · red: утверждение «событие эмитировано»
sub-tree-property-by-gate · держи гейтом дерева · subscriptionformsingularity · red: проба сервиса, зелёная при любом числе форм
sub-e2e-observable · утверждай наблюдаемое: изменение другим клиентом видно без перезагрузки и без опроса · строка без метки уходит из суженного списка · возобновление с позиции не теряет и не повторяет · ui-future/e2e/specs/subscription-* · red: проба утверждает вызов, а не наблюдаемое
sub-read-body-not-code · читай ТЕЛО ответа, а не код · subscription-stream-reachable · red: край отвечает 200 HTML на неизвестный путь — код меряет не тот производитель
sub-uncovered-named · называй числом и счётчиком · ЗАВЕСТИ sub-uncovered-named · red: остаток, оставленный молча

## Заводишь новый сервис с подпиской — порядок

sub-new-service-order · 1 миграция `<svc>_outbox` · 2 запись в writer-TX мутации · 3 `internal/subscriptionjournal/journal.go` · 4 поднять сервер фундамента на внутреннем слушателе · 5 объявить владельца краю · 6 дописать `subjects.ts` · 7 ребро в `polyrepo.md` · 8 дополнить страницу арендатора · 9 пробы: интеграционная на транзакцию + сквозная на наблюдаемое · internal/repohygiene/subscription*.go, journal*.go · red: пропущенный шаг
sub-internal-listener · поднимай на ВНУТРЕННЕМ слушателе, имя службы с префиксом Internal · ban #6: метод не попадает во внешний маршрутизатор by construction · red: поток на публичном слушателе

## Урок эпика

sub-epic-lesson · молчаливый дефект (зелёный, но неверный) опаснее красного: проверяй травмой настоящего входа и своди волну до отправки · ЗАВЕСТИ sub-epic-lesson · red: волна отправлена без сведения, зелёная на подставном входе
