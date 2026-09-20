# CI-EBT-1 — план исполнения принятого замысла

> Для исполнителей: применять `superpowers:executing-plans` к отдельным заданиям
> ниже в уже назначенных root ролях. Новая делегация и переход к исходнику требуют
> соответствующего разрешения root; этот документ их не заменяет.

**Цель:** публичный gate исключающих build tags сообщает доказанный дефект,
полную успешную проверку либо невыполненное предусловие, сохраняя настоящий
текст компилятора и точный объём выполненной работы.

**Архитектура:** существующий gate Kacho сначала полностью загружает каждую
проверяемую конфигурацию настоящим Go, затем вызывает vet. Baseline failure
делает проверку неполной; tagged compiler failure становится находкой только
после успешной загрузки и подтверждения исходной координаты. Один итоговый JSON
связывает результат с census. Существующий Go testing и CI-маршрут сохраняются.

**Стек:** Go testing, `go list -e -json -deps -test`, `go vet`, Git index,
стандартные Go JSON/context/exec, Linux FIFO для отдельного контрола отмены.

**Спецификация:** acceptance SHA256
`5bdaa5bdcac65a23cf109c95a5fb602cdff8f25db9ee2fb157fd0f7acef3f27a`;
design revision 2 SHA256
`884130123e104a474f58ea0bbba694fd36a62ef65811d7e32e2cce775a1ae429`.
Canonical paths и остальные отпечатки находятся в `change.yaml`.
Это handoff skill `writing-plans` после внешнего design approval
[#2672#5719256839](https://github.com/PRO-Robotech/kacho/issues/2672#issuecomment-5719256839).
Он предъявляется root для проверки; до readback нет TASKS_READY, T1 или source
authorization. Старый DRAFT tasks сохранён как `history/tasks-e7214a79.txt`.

## Общие границы

- База предмета: Kacho `b5fa093341f1fdbe96adfc6a9555482690968253`.
  Tester и worker получают отдельные worktrees; точную новую базу при переносе
  на aggregate root называет явно и проверяет сохранность предмета.
- Будущий worker меняет только `internal/repohygiene/excludingbuildtag_test.go`.
  Holder авторизуется отдельно в единственном новом файле
  `internal/repohygiene/excludingbuildtag_outcomes_test.go`.
- `excludingbuildtag_injection_test.go`, остальные helpers, treecorpus, pins,
  workflows и Makefile неизменны. Старые четыре инъекции не подгоняются.
- Корпус остаётся индексным. GoFilesRead увеличивается после успешного чтения
  содержимого, до parse; историческое len(index) не доказывает чтение.
- Внешний GOWORK gate не исправляет. GOWORK=off в командах ниже задаёт только
  запуск holder из Kacho. Дочерняя CI-EBT-07 получает свой настоящий foreign
  workspace; её env-снимок явно доказывает это различие.
- Fake Go, поддельный положительный compiler/load result, SKIP, тестовое
  сокращение production deadline и tagged memoization не допускаются.
- До каждого прогона и после него фиксируются исходник/holder SHA, точный argv,
  cwd, инструмент/version/SHA, явно изменённые env values, оба потока, rc и
  RUN/PASS/FAIL/SKIP. Приватные значения среды не записываются.
- Ошибка подготовки, нулевое выполненное множество либо missing capability
  остаются NOT_EXECUTED. Они не заменяют семантический RED на годном входе.
- Шаги подготовки рассчитаны на короткие изменения с отдельной проверкой.
  Реальный public deadline control оплачивает полные 120 секунд; его нельзя
  сокращать ради длительности плана. Один полный holder имеет внешний бюджет
  10 минут и отдельно сохраняет фактическую длительность.

## Карта файлов и результатов

| Координата | Владелец и действие | Наблюдаемый результат |
|---|---|---|
| `internal/repohygiene/excludingbuildtag_outcomes_test.go` | Независимый integration-tester; создать после T1 authorization | Actual public binary, 11 сценариев, отдельные DC-контроли, fixture и capture census |
| `internal/repohygiene/excludingbuildtag_test.go` | Source worker; изменить после принятого независимого RED | Loader/command result, причины неполноты, свёртка, один JSON; прежние selection/predicate |
| `internal/repohygiene/excludingbuildtag_injection_test.go` | Tester/verifier; только исполнить и сверить bytes | Четыре прежних инъекции и их настоящие lawful/defect controls |
| `scenario-matrix.json` и `interface.md` этого пакета | Все роли; читать неизменными | Источник точных ожиданий; нет oracle, извлечённого из candidate |
| `diagnostic-controls-revision2.md` | Tester/verifier; читать неизменным | Точный предел доказательства DC-01/02/03 |
| Внешний собственный evidence-каталог | Автор каждого прогона | Captures, hashes, input deltas, process identities и cleanup; путь связывается в manifest |
| `change.yaml`, `holders.yaml`, `route.md`, новые records/evidence | Canonical recorder после фактического события | Hash-bound переход; старые payload не переписываются |

## Exact-set и census

R/C/P/L/V/F/N означают соответственно go_files_read, candidate_files,
packages_checked, load_runs, vet_runs, findings, not_executed. Таблица ниже
повторяет immutable `scenario-matrix.json`, а не результат будущего прогона.

| ID | Предмет пары | Итог | R/C/P/L/V/F/N |
|---|---|---|---|
| CI-EBT-01 | Один тег исключает определение и пользователя | CLEAN | 3/2/1/3/3/0/0 |
| CI-EBT-02 | У пользователя удалена только исключающая шапка | FINDING | 3/1/1/2/2/1/0 |
| CI-EBT-03 | Удалён единственный Go member из непустого индекса | NOT_EXECUTED | 0/0/0/0/0/0/1 |
| CI-EBT-04 | Один tracked Go file без действующей шапки | CLEAN | 1/0/0/0/0/0/0 |
| CI-EBT-05 | Настоящий платформенный тег вместо пользовательского | CLEAN | 3/0/0/0/0/0/0 |
| CI-EBT-06 | Только return expression заменено неизвестным символом | NOT_EXECUTED | 3/2/1/1/1/0/1 |
| CI-EBT-07 | Только GOWORK указывает настоящий nonmember workspace | NOT_EXECUTED | 3/2/1/1/0/0/1 |
| CI-EBT-08 | Удалён только внешний replacement-root tagged dependency | NOT_EXECUTED | 4/2/1/3/1/0/2 |
| CI-EBT-09 | Из собственного PATH удалён Go, Git сохранён | NOT_EXECUTED | 1/0/0/0/0/0/1 |
| CI-EBT-10 | Два отдельно доказанных изменения в разных пакетах | NOT_EXECUTED | 6/3/2/3/3/1/1 |
| CI-EBT-11 | Working file удалён при неизменном индексе | NOT_EXECUTED | 0/0/0/0/0/0/1 |

Положительные восстановления выполняются на том же fixture-root: 03/11 дают
один прочитанный файл и остальные нули; 06/07/09 возвращают 01; lawful 08 имеет
4/2/1/3/3/0/0. Для 10 отдельно восстановить baseline второго пакета:
6/3/2/5/5/1/0, затем исключающую шапку первого: 6/4/2/6/6/0/0.
P считает уникальные начатые baseline packages; L/V — реально стартовавшие
процессы. N дедуплицируется по (phase, pkg, file, tag): baseline/global один раз,
tagged по каждому кандидату. Два кандидата с одним тегом сохраняют два вызова.

## T0 — проверить передачу плана

Владелец root; вход — этот план и четыре внешних contract events.

- [ ] Сверить exact bytes acceptance, design revision 2, interface, scope,
  matrix, DC revision 2 с `change.yaml`; события initial/revalidation связывают
  именно эти subjects. Старые DRAFT headings являются неизменной историей.
- [ ] Проверить покрытие 11 IDs и отдельные пределы DC-01/02/03, карту файлов и
  отсутствие holder/source edits в planning commit.
- [ ] Записать фактический readback handoff с SHA этого `tasks.md`. Только после
  этого recorder отражает TASKS_READY; root отдельно называет T1 tester и базу.
- [ ] Передавать tester реальные operational fixtures как предпосылки, не как
  его RED. Сохранять первую single-write FIFO попытку NOT_PROVED.

Выход T0 — проверенный handoff и отдельное разрешение test-only; исходник закрыт.

## T1 — доказать предпосылки и получить независимый RED

Владелец integration-tester, отличный от будущего source worker.

- [ ] Зафиксировать source SHA, старые два gate/test файла и exact список тестов.
  Из корня выделенного Kacho worktree выполнить существующий маршрут:

  ```sh
  GOWORK=off go test ./internal/repohygiene -list '^TestExcludingBuildTag' -count=1
  GOWORK=off go test ./internal/repohygiene -run '^TestExcludingBuildTag(Gate|LeavesThePackageBuildable)' -count=1 -json -timeout=10m
  ```

  Ожидаются четыре старые инъекции и один публичный tree gate, SKIP=0. Если
  baseline не исполнился, сохранить причину и не заменять её новым RED.
- [ ] В новом holder получать путь собственного compiled test binary через
  `os.Executable`; запускать его из fixture-root с точным дочерним селектором
  `-test.run=^TestExcludingBuildTagLeavesThePackageBuildable$ -test.v -test.count=1`.
  Дочерний запуск не включает holder. Сохранить compiler binary SHA и Git index.
- [ ] Создать минимальные настоящие Git/Go fixtures; до public assertions
  выполнить прямые реальные load/vet controls. Пакеты не требуют сети.
  Для CI-EBT-08 replacement существует в положительной стороне и отсутствует
  только в отрицательной; исходные файлы и индекс при этом одинаковы.
- [ ] Для каждой пары сохранить snapshot до/после и вычисленную дельту, затем
  lawful → mutation → restored на одном корне. CI-EBT-10 честно называет две
  композиционные дельты, а не выдаёт их за одну.
- [ ] Исполнить все 11 IDs через actual public gate; проверить полный поток,
  nonzero refusal, настоящие причины/координаты и exact census. Новый результат
  обязан быть единственным JSON с восемью полями; неизвестные/пропущенные поля,
  bool или дробные counters — отказ holder. Эталон положительного JSON для 01:

  ```json
  {"status":"CLEAN","go_files_read":3,"candidate_files":2,"packages_checked":1,"vet_runs":3,"load_runs":3,"findings":0,"not_executed":0}
  ```

- [ ] До freeze согласовать с root/worker только routine coordinates чистых
  loader decoder, compiler classifier и общего command runner в том же
  разрешённом source-файле. Сохранить точные signatures и selector mapping в
  test-only handoff. Это не изменение accepted semantics или авторство worker
  над assertions. Отсутствующий callable seam отдельно NOT_EXECUTED; его
  отсутствие не объявляется семантическим RED.
- [ ] Добавить DC-01 controls: настоящий compiler output от 02 — положительный
  вход classifier; только изменённый префикс и отдельно пустой output при том же
  failed process status — отрицательные входы NOT_EXECUTED. Положительный исход
  нельзя получить подделанным Go или stub. Изменённые bytes помечаются decoder
  input, отдельно от actual command captures.
- [ ] Добавить DC-02 controls: полный реальный loader JSON от 01 — положительный
  вход decoder; отдельно пустой поток, непустой trailing suffix, один Error при
  rc0 — NOT_EXECUTED. Прямая настоящая loader failure с source-coordinate в
  07/08 остаётся обязательной; regex в output не подменяет проверку стадии.
- [ ] Добавить DC-03: настоящий Go и собственный FIFO, повторный writer с одним
  документом и EOF на каждое чтение. Подтвердить lawful completion прежде
  отсутствующего writer. Runner-control вправе передать короткий context и
  доказать child cleanup; отдельный public control проверяет настоящий
  production 120-second deadline без env override. Сохранять PID identity,
  факт блокировки, status/reason и отсутствие собственных потомков после cancel.
  Lawful восстановление обязательно; first-attempt fixture failure не RED.
- [ ] Выполнить будущую точную группу после появления нового holder:

  ```sh
  GOWORK=off go test ./internal/repohygiene -run '^TestExcludingBuildTagOutcomes$' -count=1 -json -timeout=10m
  ```

  Parent включает 11 именованных CI-EBT случаев и отдельные DC-подгруппы. Это
  плановая команда, не утверждение о существовании нового теста на main.
- [ ] Зафиксировать test-only commit. Отдельно перечислить semantic failures,
  capability/fixture refusals и уже зелёные regressions. Ожидаемый main RED —
  скрытые baseline failures 06/07, неверные findings на loader failure 08,
  потеря причины неполноты при сохранённой находке 10. Не объявлять отсутствие
  новой JSON-строки достаточным доказательством этих дефектов.
- [ ] Передать root immutable holder/source/capture manifest. Root читает
  assertions, повторяет фактический RED и только затем публикует точный scope T2.
  Непроверенные DC-ветви не получают authorization из одного 11-case RED.

## T2 — реализовать разрешённый scope

Владелец отдельный source worker; вход — frozen holder и root source event.
Все действия только в `excludingbuildtag_test.go`, старые тесты неизменны.

- [ ] Ввести представление результата настоящей команды: argv/cwd, started,
  stdout/stderr, завершение/ошибка/отмена. Общий runner применяет context и
  deadline 120 секунд к load/vet, 30 секунд к dist; counters увеличиваются
  только после успешного Start. Не переписывать GOWORK и не подменять Go.
- [ ] Реализовать полный loader decoder по согласованной routine signature:
  читать поток до EOF, требовать >=1 object, отвергать trailing/malformed,
  Error, DepsErrors, Incomplete и неуспешный процесс. Сохранить набор реальных
  загруженных исходных Go-файлов для проверки compiler-coordinate.
- [ ] Сохранить сигнатуру `auditExcludingBuildTags(root) (findings, census, error)`.
  Typed error хранит частичные невыполненные проверки с полной identity;
  успешное ReadFile, начатый baseline и стартованные процессы дают разные
  счётчики. Ошибки независимого пакета не стирают ранее доказанные findings.
- [ ] Перед baseline vet выполнить baseline load; при отказе записать
  NOT_EXECUTED с полным cause и продолжить независимые пакеты. После успешного
  baseline выполнять tagged load/vet по каждому прежнему кандидату.
- [ ] Классифицировать tagged vet только после успешного load: положительный
  compiler profile с разрешимой source/line/column даёт finding; unknown,
  mixed, signal, timeout и невозможность запуска дают NOT_EXECUTED. Нельзя
  hardcode имя synthetic symbol или считать любое ненулевое завершение finding.
- [ ] Сначала вывести человеческие записи и ровно один закрытый JSON, затем
  завершить публичный тест: N>0 → NOT_EXECUTED/FAIL; иначе F>0 → FINDING/FAIL;
  иначе R>0 → CLEAN/PASS; пустой корпус создаёт corpus NOT_EXECUTED. Не менять
  общий TestMain, не использовать SKIP и не возвращать синтетический rc3.
- [ ] Повторять только относящуюся к изменению frozen группу до исправления
  конкретных failures. После стабильного candidate один раз выполнить полный
  новый holder, старые четыре инъекции и real-tree gate; сохранить точные
  исходные и конечные hashes. Commit содержит только разрешённый source path.

## T3 — независимый GREEN и проверка полноты

Владелец независимый verifier/root, source worker не утверждает свою работу.

- [ ] Прочитать весь candidate diff и сравнить frozen holder/старые tests byte
  for byte. Проверить, что scope, counters, deadlines и per-candidate calls
  соответствуют принятым subjects, а не просто совпали с тестом.
- [ ] Получить frozen candidate в отдельном дереве и выполнить обе команды
  нового holder и старых тестов из T1. На них сверить exact names, 11 IDs,
  DC-подгруппы, реальные процессы и SKIP=0; нулевой запуск не GREEN.
- [ ] Отдельно сверить public production deadline, PID cleanup, все positive
  restoration pairs и partial findings при общем NOT_EXECUTED. Operational
  FIFO proof не подставляется вместо исполнения candidate runner.
- [ ] Проверить complete manifest: каждый actual stream существует и его SHA
  совпадает; modified decoder inputs явно отделены от Go output. Повторный
  source/holder hash после прогонов равен начальному. Все own commands завершены.
- [ ] Root публикует настоящий scoped GREEN и читает событие обратно. Recorder
  связывает точный source, holder и review. Полнота acceptance/DC и конечного
  состава required holders определяется по выполненному exact-set, не по rc0.

## T4 — доставка и predicate issue

Владелец root с post-diff/convergence/landing reviewers по действующей policy.

- [ ] Перенести только проверенные source/test commits; при конфликте не
  менять assertions молча. Проверить exact resulting content и применимые
  проверки aggregate, включая прежний путь unit → Go JSON verdict collector.
- [ ] Получить требуемые post-diff/review/landing records, выполнить защищённую
  доставку и сверить фактический main SHA с проверенным предметом.
- [ ] На доставленном main повторить применимые exact selectors из T1, сверить
  ненулевой census и отсутствие SKIP. CI-EBT-01/04/05 молчат по существу,
  02 называет истинную координату, 03/06–11 не дают GREEN при неполноте.
- [ ] Только после evidence main и полного predicate #2672 готовить closure.
  Owner END #2682 остаётся вне scope: массового исправления GOWORK нет.

## Проверка самой передачи

Этот план не изменяет accepted subjects, не создаёт executable holder и не
выдаёт авторский review за независимый. Его checksum связывается в отдельном
handoff record вместе с четырьмя внешними событиями. Root readback этого exact
плана предшествует TASKS_READY. Принятые contract/design events разрешают
подготовку плана; будущие test/source/landing events фиксируются отдельно.
