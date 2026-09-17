# CI-DT-1 — маршрут исполнения принятого замысла

**Цель:** привести текущие пояснения к проверяемой форме подписки и сохранить
программу, кроме двух принятых диагностических строк.

**Архитектура:** canonical proto принадлежит Kachō, generated Go — corelib.
Независимый integration-tester предъявляет RED до изменения source; worker
получает отдельный root transition. Проверка программы и генерации связывается
с точными Git SHA. Релиз, consumer pin, convergence и landing ведёт root.

**Стек:** Go testing, Go parser/scanner, protobuf descriptors, штатные плагины
из `proto/buf.gen.yaml`, Git и Change Graph records.

**Контракт:** `docs/specs/sub-phase-CI-DT-1-doc-truth-acceptance.md` и
`docs/specs/sub-phase-CI-DT-1-doc-truth-design.md`; отпечатки и внешние события
находятся в `change.yaml`. Это writing-plans handoff после APPROVED design.
Таблица задаёт работы и зависимости; их живой статус принадлежит #2696/#2591/#2592.

## Общие границы

- База Kachō: `b5fa093341f1fdbe96adfc6a9555482690968253`; corelib:
  `34bc8104a832b67e53c868646ab2b1e0ac4c8562`, исходная версия `v1.8.0`.
- В трёх Go test-файлах меняются только комментарии. В
  `internal/repohygiene/subscriptionformshape.go` дополнительно разрешены только
  строковые leaves двух Reason из CI-DT-03/04. Kind, условия, динамические
  подстановки, AST-форма выражений и существующие assertions сохраняются.
- Новый test-only файл — `internal/repohygiene/subscriptionreason_test.go`,
  единственный новый top-level holder — `TestSubscriptionShapeReasonContract`.
- Датированные WATCH и #1439, в том числе исторический опыт ослепления ветви,
  не переписываются. Runtime validation в этот поток не входит.
- Все Go-прогоны выполняются с `GOWORK=off`; временная оснастка находится вне
  Git, дочерние Git-команды не наследуют `GIT_*`. У каждого прогона сохраняются
  command, cwd, входные SHA, stdout/stderr, rc, имена RUN/PASS/FAIL/SKIP.
- Whole-tree exporter не применяется к текущему corelib. Генерация производится
  отдельно приёмом emitStubs из D5, только для `corelib/subscription`.
- До root readback TASKS_READY допускается только planning. После readback —
  diagnostic test-only RED. Реализация открывается отдельным root transition
  по принятому независимому RED, не существованием этого документа.

## Exact-set приёмки и работы

| Сценарий | Работа и владелец | Предмет и проверяемый выход | Зависимость |
|---|---|---|---|
| CI-DT-01 | DT-01, worker; go-style-reviewer | Комментарии `internal/repohygiene/grpcmountparity_test.go` и `catalogreachability_test.go` ссылаются на действующих census producers; исторические наблюдения сохранены | Принятый RED и root transition |
| CI-DT-02 | DT-02, worker; go-style-reviewer | Шапка `internal/repohygiene/subscriptionformshape.go` утверждает только две объявленные альтернативы и предел анализа экземпляров | Принятый RED и root transition |
| CI-DT-03 | DT-03, integration-tester → worker | Настоящий `shapeAudit` на форме без обёртки `oneof carrier`: exact Reason из приёмки, Kind `carrier-not-a-choice`, координата события; baseline RED → candidate GREEN | TASKS_READY readback; source после RED |
| CI-DT-04 | DT-04, integration-tester → worker | Та же форма с единственной третьей ветвью `string state_summary = 12`: exact Reason из приёмки, тот же Kind/координата; baseline RED → candidate GREEN | TASKS_READY readback; source после RED |
| CI-DT-05 | DT-05, integration-tester | Законная форма без findings; существующий отказ на пустом/непрочитанном входе; отдельный реальный protobuf опыт различает форму и незаданный экземпляр | До RED проверены предпосылки и lawful twin |
| CI-DT-06 | DT-06, worker; go-style-reviewer | Комментарий `requireKindSaying` в `subscriptionformshape_injection_test.go` ссылается на единицы и команды в canonical header; прежние проверки обеих ветвей сохранены | Принятый RED и root transition |
| CI-DT-07 | DT-07, independent verifier; go-style-reviewer | Строгие Go token/AST comparison, exact approved Reason leaves, birth lawful/one-token-defect/empty; непустой exact-set существующей selection и неизменная история | Baseline + candidate Git SHA и собственный verifier digest |
| CI-DT-08 | DT-08, worker; proto-api-reviewer | Только carrier comment в `proto/corelib/subscription/subscription.proto`; поля, номера, типы, oneof, options и descriptor прежние | Принятый RED и root transition |
| CI-DT-09 | DT-09, worker + independent verifier + root | Штатная генерация четырёх файлов, только комментарий `api/corelib/subscription/subscription.pb.go` отличается; затем release, проверенный archive, consumer pin и повтор при `GOWORK=off` | Canonical proto SHA → generated SHA → опубликованная версия → Kachō pin |

## Порядок и команды

1. Integration-tester работает в собственном Kachō worktree от базы. До нового
   holder получает существующий список и JSON-прогон из корня Kachō:

   ```sh
   GOWORK=off go test ./internal/repohygiene -list '^Test(SubscriptionFormShape|SubscriptionShape|GRPCMountParity|CatalogReachability)'
   GOWORK=off go test ./internal/repohygiene -run '^Test(SubscriptionFormShape|SubscriptionShape|GRPCMountParity|CatalogReachability)' -count=1 -json -timeout=5m
   ```

   Поимённое объявленное множество сверяется с исполненным. Авторский baseline
   не является независимым результатом. Ноль тестов, SKIP или отказ окружения
   не открывают следующую фазу.

2. Tester добавляет только holder из DT-03/04/05. Он использует
   `baseShapeForm`, `shapeAudit`, `shapeStandLedger`, `shapeStandAbsent`;
   `shapeAudit` возвращает реальные `SubscriptionShapeFinding` и census.
   Lawful twin исполняется перед каждой одно-фактной мутацией. Для дефектов
   утверждаются exact Reason/Kind/File/Line; ожидаемый baseline RED ограничен
   Reason. Снятие обёртки и добавление ветви проверяются как отдельные изменения
   исходной Event-части; изменённое и законное сообщения целиком сохраняются
   в evidence. Точные expected строки берутся из принятой приёмки, не из
   испытуемого. Из корня Kachō:

   ```sh
   GOWORK=off go test ./internal/repohygiene -run '^TestSubscriptionShapeReasonContract$' -count=1 -json -timeout=5m
   ```

   В test-only commit нет source. Root принимает RED по сырым результатам,
   lawful twin и координатам, затем отдельно передаёт source worker.

3. Worker исполняет DT-01/02/06/08 и две строки DT-03/04 по D1–D5, сохраняя
   точную карту разрешённых файлов. Независимый тест приходит отдельным
   commit. Worker не ослабляет его и существующие assertions.

4. Verifier исполняет DT-07 собственным одноразовым Go comparator. Обе стороны
   читаются из Git на exact SHA; три comment-only файла сравниваются целиком
   без комментариев. В анализаторе нормализуются только проверенные старые и
   новые string leaves двух согласованных Reason в их точных AST coordinates.
   Все остальные токены, expression tree и literals сравниваются буквально.
   Перед candidate сравнениями отдельные lawful comment edit, одно-token
   программный дефект и пустой/непрочитанный ввод доказывают три исхода мерки.
   Source, digest и полный transcript сохраняются вместе.

5. Для DT-09 генератор и verifier каждый используют отдельный staging вне Git:
   точный Kachō source SHA; неизменённый префикс `proto/buf.gen.yaml` до
   `inputs:`, input directory `corelib/subscription`, module-pinned `go tool buf`
   из D5. Baseline обязан воспроизвести четыре файла corelib; candidate обязан
   воспроизвести тот же состав. Кроме `subscription.pb.go`, байт-идентичны
   `subscription_service.pb.go`, `subscription_service.pb.gw.go` и
   `subscription_service_grpc.pb.go`. В изменённом файле одинаковы Go program
   tokens/AST и raw descriptor; proto semantic descriptor без source info
   также одинаков. Полный старый exporter этим не чинится.

6. Root переносит только проверенный generated diff, выпускает corelib и
   передаёт реальную версию для Kachō pin. Verifier повторно получает
   опубликованный module archive, сверяет payload с принятым generated SHA,
   подтверждает выбранную module version и повторяет оба прогона из шага 1/2
   при `GOWORK=off`. Версия до публикации не подставляется предположением.

7. Go/proto reviewers выносят post-diff verdict на exact content, convergence
   проверяет все применимые holders, root выполняет landing. Проверка main
   по каждому repo и отдельный предикат каждого issue предшествуют closure.
   Ни локальный GREEN, ни planning commit не означают поставку.

## Свидетельства и границы вывода

`holders.yaml` задаёт canonical evidence coordinates. Локальный рабочий audit
tester используется до переноса долговечных records и не заменяет их.
Пустой запуск, ошибка подготовки и mismatch множества тестов сохраняются как
отдельные исходы. Формат не допускает перенос author baseline в независимый
GREEN. Порядок работ исполнен только после соответствующих external records;
этот маршрут не является журналом статусов.
