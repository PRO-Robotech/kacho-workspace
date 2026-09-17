# CI-DT-1: отдельное предложение scope для #2590

**Статус: DRAFT, source и holders не разрешены.** Это новый ограниченный
subject review по [kacho#2590](https://github.com/PRO-Robotech/kacho/issues/2590),
по форме отдельного addendum #2711. Принятые acceptance/design, exact-set
CI-DT-01..09, holders и review history CI-DT-1 не изменяются; прежние approvals
не распространяются на этот текст.

## Предмет и проверенные основания

Текущий дом — **PRO-Robotech/corelib**, `migratorcli/notice_test.go` на main
`34bc8104a832b67e53c868646ab2b1e0ac4c8562`. Fresh GitHub main ref совпал с этим
SHA. Весь файл имеет SHA-256
`90a9ddd66f9d2aa0bb992010cd4101b769c433f46de7cb37e2229db0e5bb6ee8`;
это digest **всего файла**, не header. Issue открыт, comments 0 при чтении
2026-09-17; описание issue привязано к прежнему Kachō `pkg/migratorcli` и не
переопределяет нынешний home.

Здесь различаются три утверждения:

1. Шесть локальных notice-проб передают `pgconn.Notice` приёмнику напрямую,
   проверяют форму, перепись, предел и два отказа `OpenDB` без живой БД.
2. Corelib `migratorcli/noticethreshold_integration_test.go` применяет
   **синтетическую** двухшаговую цепочку к настоящему Postgres. Это проверка
   порога сессии с законным близнецом, не накат настоящих миграций платформы.
3. `internal/migratorapply` находится в Kachō и остаётся отдельным владельцем
   проверок миграций платформы. Его историческая цель `PG_OUTSIDE_SELECTION`
   не переносится в описание текущего corelib CI.

Нынешний producer отбора corelib — `.github/scripts/run-integration.sh`.
Он читает `TestImports` **и** `XTestImports`, отбирает импорт `corelib/pgtest`
либо `testcontainers`, затем вызывает `go test -race -count=1 -p 1` без
`-short`. Job `integration` в `.github/workflows/ci.yml` вызывает этот script.
`migratorcli/testmain_pgtest_test.go` подключает `pgtest.Run` с ленивым Postgres.
Все эти файлы прочитаны на указанном main; их hashes связаны с baseline record.

Root preflight на `2161e76ea36b0c3249ac274e698d22e27bd5fec8` измерил 76 пакетов,
14 отобранных, включая migratorcli; шесть notice-проб дали 6 RUN / 6 PASS /
0 FAIL / 0 SKIP под `-short`. Notice file и три route-source файла совпадают
с нынешним main по bytes/hash. Это **атрибутированное root измерение**, не
собственный повтор автора; DB integration этим прогоном **не выполнялась**.
Counts не становятся постоянным ожиданием общей selection: на новой ревизии
tester получает новый полный census и требует фактического включения пакета.

Старая шапка утверждает, что интеграционную пробу пакета некому выполнять.
Её отрицательный baseline — противоречие прочитанным producer/CI/TestMain и
непустому actual selection. Это семантическая находка, не искусственно
объявленный машинный RED и не дефект доставки уведомлений.

## Единственная разрешаемая область

Предлагается заменить **только** абзац строк 6–12 текущего файла: byte interval
`[162, 964)` в UTF-8 baseline, начиная с `// Живой базы здесь нет` и заканчивая
`// test-pg-outside-selection.\n`. Old paragraph SHA-256:
`2417bb6f6a4f2428aeaaa8af6bdc46ed6f7c22fc921f65099147ce15501d6d02`.
Byte coordinates относятся только к baseline с названным full-file digest;
одних номеров строк недостаточно для применения.

Новый абзац предлагается дословно:

```go
// Здесь без живой базы проверяются форма доставки через NoticeRelay, перепись
// и предел сообщений. Уровень и текст передаются приёмнику напрямую; эти пробы
// не доказывают доставку уведомления от настоящего сервера.
//
// Интеграционные пробы пакета в `noticethreshold_integration_test.go` применяют
// синтетическую цепочку миграций к настоящему Postgres и проверяют порог сессии.
// `.github/scripts/run-integration.sh` выбирает пакет по импорту `corelib/pgtest`
// либо `testcontainers` в TestImports/XTestImports и запускает его без `-short`.
// Скрипт вызывает job `integration` в `.github/workflows/ci.yml`; TestMain из
// `testmain_pgtest_test.go` через pgtest.Run поднимает Postgres лениво.
//
// Проверки настоящих миграций платформы принадлежат Kachō (`internal/migratorapply`).
// Их исполнение и результат этот файл не утверждает.
```

New paragraph SHA-256:
`3991e2b2d542252bf02ecc28c01e9dbbb11ed6bdf6be80d84c827b19c2d80599`.
Ожидаемый full-file SHA после ровно этой замены:
`bd223ac51e5416a5f9bf2ea0edd6d9d215115434fd6b9fa0e0a9c547fbbd0e3e`.
Hashes рассчитаны in-memory; product source этим предложением не записан.

Copyright/license, название файла, следующий абзац про пары отрицаний и
положительных контролей и **все остальные bytes** сохраняются дословно.
В частности неизменны все комментарии при пробах, imports, program literals,
assertions, test names, directives и всё начиная с `package migratorcli_test`.
Никаких Reason/AST/token исключений или whitelist, как у другого предмета
CI-DT-1, здесь нет. Baseline/region/new bytes и prefix/suffix digests заданы
в [issue-2590-baseline.json](issue-2590-baseline.json).

## Предлагаемые критерии и держатели

| ID | Given / When | Then |
|---|---|---|
| CI-DT-A2-01 | Reviewer читает exact baseline и текущие corelib producer/CI/TestMain; сравнивает proposed paragraph | Новый текст описывает локальную форму, нынешний integration route и синтетическую цепочку честно; отсутствие исполнителя снято; scope реальных platform migrations не присвоен |
| CI-DT-A2-02 | Независимый verifier читает baseline/candidate по exact Git SHA | Candidate равен baseline после единственной literal replacement; prefix/suffix byte-identical; полный Go token stream и position-free AST без comments совпадают без whitelist; directives неизменны; input непуст, parse завершён, declarations ненулевые |
| CI-DT-A2-03 | Из обоих exact checkouts исполняются все шесть существующих notice-проб | Имена объявленных/RUN/PASS равны точному набору ниже и друг другу; 0 FAIL / 0 SKIP; assertions и программа прежние; short selection не выдаётся за DB integration |
| CI-DT-A2-04 | Изменение прошло independent review и доставляется общей библиотекой | Exact corelib main content содержит принятую шапку; local commit не выдаётся за main/release/pin. При выпуске агрегата фиксируются tag/main/archive identity и consumer pins отдельно, без приписывания runtime эффекта правке комментария |

До исходной правки tester предъявляет lawful control ровно с proposed paragraph
и отрицательные single-fact controls: один program token; дополнительный
комментарий вне allowed region; сохранённая старая шапка; пустой, непрочитанный
и не содержащий declarations input. Полностью сломанный comparator/harness —
NOT_EXECUTED, не RED исходника. Сам comparator, его digest, raw stdout/stderr,
rc и точный input corpus сохраняются независимо. Автор addendum его не пишет.

Шесть имён:

- `TestNoticeReachesTheOperatorWithItsLevelAndText`
- `TestLevelIsTakenUnlocalised`
- `TestCensusIsPrintedEvenWhenNothingWasSaid`
- `TestCensusCountsWhatItPrintedAndWhatItDropped`
- `TestOpenDBRefusesToRunWithoutAPlaceToDeliver`
- `TestOpenDBRefusesADriverThatCannotDeliver`

Из корня отдельного corelib checkout, с `GOWORK=off`, внешним TMPDIR и
очищенным Git environment:

```sh
go test ./migratorcli -short -list '^(TestNoticeReachesTheOperatorWithItsLevelAndText|TestLevelIsTakenUnlocalised|TestCensusIsPrintedEvenWhenNothingWasSaid|TestCensusCountsWhatItPrintedAndWhatItDropped|TestOpenDBRefusesToRunWithoutAPlaceToDeliver|TestOpenDBRefusesADriverThatCannotDeliver)$' -count=1
go test ./migratorcli -short -run '^(TestNoticeReachesTheOperatorWithItsLevelAndText|TestLevelIsTakenUnlocalised|TestCensusIsPrintedEvenWhenNothingWasSaid|TestCensusCountsWhatItPrintedAndWhatItDropped|TestOpenDBRefusesToRunWithoutAPlaceToDeliver|TestOpenDBRefusesADriverThatCannotDeliver)$' -count=1 -json -timeout=2m
```

Для actual selection verifier запускает `go list` с ровно теми TestImports/
XTestImports, что читает script, сохраняет полный output и свой filtered set.
Положительный факт — пакет включён; ноль прочитанных либо ошибка listing
запрещают утверждение об отборе. Вызов полного `run-integration.sh` с Postgres
не нужен, чтобы доказать comment-only preservation; если его запускает общий
CI, outcome связывается с actual SHA отдельно. Наличие caller не равно
доказанному успешному живому DB прогону.

## Роли, переходы и граница поставки

1. Независимый reviewer принимает или отклоняет этот exact subject и A2-01..04.
   Tester в своём контуре делает comparator controls и baseline captures;
   root читает их и создаёт отдельный source transition на exact addendum hash.
   Нынешний файл сам себя не одобряет.
2. Source worker после transition меняет только указанный абзац corelib.
   При исходном digest, отличном от baseline, не применяется fuzzy replacement:
   требуется новая проверка subject. Соседние устаревшие комментарии, программное
   поведение, integration script/CI/TestMain и существующие тесты не меняются.
3. Independent verifier подтверждает A2-02/03 и semantic review A2-01; root
   оформляет candidate outcome отдельно от source-author сообщения. Нового
   постоянного text-matching теста над шапкой это addendum не заказывает.
4. Corelib изменения доставляются через protected PR/main. Если правка входит
   в общий выпуск CI-DT/corelib, используются утверждённый producer и его
   release/archive/pin proofs; новый tag/pin здесь не выдумывается. Комментарий
   в `_test.go` не меняет runtime consumer, поэтому download/version proof
   нельзя называть новым runtime GREEN. Закрытие #2590 требует independent
   exact-content review и подтверждённый main commit/связь с агрегатом.

Issue отсутствует в нынешнем legacy registry. Как у #2711, новый ограниченный
addendum имеет собственный exact hash; old policy census, accepted subjects
и история review не переписываются. Никакая CI-DT-A2 запись не расширяет
задним числом уже одобренный exact-set CI-DT-01..09.

Сейчас source, holders и independent GREEN отсутствуют; root preflight
удостоверяет только явно названные baseline наблюдения. Полного закрытия
класса устаревших комментариев в corelib этот узкий предмет не обещает.
