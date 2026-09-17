# CI-PY-1 — предлагаемый порядок исполнения

> Маршрут после DESIGN_APPROVED, 2026-09-17. Живое состояние — issues #2281/#2629/#2705.

1. Независимый acceptance-reviewer рассматривает точный SHA-256 приёмки.
2. Независимый class-exposure-analyst записывает initial analysis на одобренный
   SHA; пересверяет каждый класс по SHA замысла.
3. Design-reviewer выносит отдельный вердикт, включая D4 минимального транспорта
   и D6 итогового CI; затем маршрут передаётся integration-tester.
4. Integration-tester создаёт сценарии, доказывает исправность оснастки, запускает
   полный положительный baseline и снимает честный RED по недостающему поведению.
5. Исполнитель чинит общий Python→selftest→Make→ci-local/CI поток. Ни один
   зависимый issue не объявляется завершённым по одной ветви producer.
6. Независимая проверка снимает три реальных исхода по каждой границе и counts;
   сохраняет stdout/stderr, rc, версии и exact content. Проверка охвата читает
   структурный workflow и отказывает на пустой популяции.
7. Профильные review, convergence, landing с content binding и main verification.
   Только после этого root публикует closure evidence трём задачам.

Рёбра задач: #2629 producer+selftest и #2281 CI semantics образуют общий компонент;
#2705 зависит от него и сохранения категории через Make. Приёмка/review —
подготавливаемые фазы, а не внешний BLOCKED. Owner запрета на этот flow не найдено.

## Передача на независимый первый RED

Integration-tester: `/root/ci_verdict_audit`, отдельная линия
`lane/ci-python-tests-20260917`; автор реализации `/root/hygiene_audit` пишет
только после принятого RED в `lane/ci-python-20260917`. Root переносит test commit
в worker и контролирует переход. Автор не меняет чужие тесты под реализацию.

Файл holder: `tools/pythonprobes/outcomes_test.go`. Три именованных родителя:
`TestPythonOutcomesProducer` (CI-PY-01..08), `TestPythonOutcomesChain`
(CI-PY-09..12), `TestPythonOutcomesCallers` (CI-PY-13). Точные команды —
holders.yaml; согласованные routine CLI/JSON имена — transport-interface.md.
Ноль RUN по selector — отсутствие holder, не успешная проверка.

Фикстура использует собственные временные каталоги вне git, снимает весь GIT_*
контекст и задаёт GOWORK=off. Pytest отсутствует только у испытуемого; harness
работоспособен. Положительный helm-путь использует требуемую pinned версию,
реальные yq/make и собственные материализованные зависимости. Чужие kind-стенды
не являются предпосылкой этого scoped потока и не используются.

RED capture связывает каждый ID, условие, observed/expected, real CLI, stdout/stderr,
rc и счётчики. Отдельно показывает: полную законную форму; genuine finding;
отсутствие pytest; mixed finding+unmet; GREEN prerequisite перед поздней ошибкой
Make; старую/чужую запись. Три CI-шага двух концептуальных цепочек проверяются
каждый по своей фактической координате.

Маршрут принят root orchestration после independent review и согласования имён
с integration-tester. TASKS_READY допускает создание проб; IMPLEMENTING требует
отдельного RED_PROVEN и переноса первого test commit. Этим текстом RED не заявлен.


## Уточнение бюджета держателя 2026-09-17

Независимый integration-tester измерил полный положительный helm baseline:
455 секунд, 5/5 проверок, код 0 и чистое дерево. Callers повторяет два настоящих
YAML Make-пути и прямой Python, поэтому timeout этого родителя увеличен
с 10 до 15 минут; Chain остаётся 30 минут. Наблюдаемый контракт и approved
отпечатки не меняются. CI11 читает настоящий gate-self-test outcome для
границы manifest, ожидаемый producer задан вызывающим явно.


## Ограниченный переход producer, 2026-09-17T11:00:07Z

[Внешнее событие](https://github.com/PRO-Robotech/kacho/issues/2629#issuecomment-5713242735)
подтверждает независимый RED CI-PY-01..08 на test-only commit
8cc171365e676f07005bfdde9b97d85d0eaa2452: 17 реальных вызовов и восемь
сценариев, исправные положительные близнецы, 0 SKIP. Reviewer /root/e2e_audit
подтвердил точный manifest d41b0152a6421514b35fc6fe26da44f4fb629427f5d37d3e8ccc22fc5e3619fd.

Root открыл только D1–D3: run-python-probes.py и минимальные stdlib schema/writer
для результата producer. Test commit перенесён в отдельный worker. Чужой holder
не меняется под реализацию. Reader CLI, общий selftest-runner, Make, ci-local,
workflow и решения D4–D7 остаются TESTS_PENDING до своего RED. Общий lifecycle
сохраняет TASKS_READY: частичный RED не становится полным RED всего потока.


## Независимый GREEN producer, 2026-09-17T11:10:31Z

[Внешнее событие](https://github.com/PRO-Robotech/kacho/issues/2629#issuecomment-5713374865)
фиксирует независимую post-diff проверку CI-PY-01..08 / D1–D3 на source commit
78025a3d10a7ea4eaf86ce4797026e0f76396edc. Reviewer /root/e2e_audit прочитал оба
изменённых файла, сверил неизменность holder с test-only 8cc1713 и повторил
14 RUN / 14 PASS / 0 FAIL / 0 SKIP, включая 17 реальных producer/self-test
процессов. Отдельный запуск текущего дерева исполнил 40 проб: 34 pytest и
6 script-main из 8 файлов, без failed/skipped/unmet.

Вердикт APPROVED_SCOPED_GREEN ограничен producer и его self-test. Он не
разрешает расширять реализацию на D4–D7 до их независимого RED, не подтверждает
полную цепочку, convergence, main delivery или closure трёх issues. Общий
lifecycle остаётся TASKS_READY; прежний RED-переход сохранён как история.


## Уточнение обязательного длинного прогона, 2026-09-17

Независимая routine revalidation сохранена в
[routine/execution-route-20260917/record.json](routine/execution-route-20260917/record.json):
subject 00f1c9bde19ef48308274c85940ae267f4e0af6220456233b7d6e3f681ce23e3,
review /root/e2e_audit 432485e133b807a7a207068c1a27c88ff4f20fcd8bbdb59d980abb8eefc67429.
Callers измерен в 733.9 секунды, положительный helm baseline — 465.8 секунды;
прежние бюджеты Chain 30m / Callers 15m не являются достаточным планом доставки.
Эти исторические записи выше сохранены, текущий маршрут уточнён ниже.

Producer остаётся в обычном unit составе. Chain и Callers переходят под
положительный integration build tag; exact tag/test commit закрепляет
integration-tester при delivery. Tester закрепил тег `ci_integration`; команда
`GOWORK=off go test -tags=ci_integration ./tools/pythonprobes
-run '^TestPythonOutcomes' -count=1 -json -timeout=90m`
выбирает семейство трёх parents, сохраняя пять прежних unit parents отдельно.
Общий entrypoint запускает три родительских теста и
13 сценариев с JSONL, таймаут пакета 90m; внутренние бюджеты: Producer 8m,
Chain 55m, Callers 22m, внешнее задание CI 100m. Это capacity policy, не обещание
будущего времени. Неполный вывод, missing/skip/unfinished не дают GREEN.

Entry point обязателен из make test, ci-local all, отдельной именованной
ci-local group и CI с финальным required verdict. ci-local go сохраняет unit
scope; внутренний ci-local helm не вызывает outer integration lane, чтобы
fixture не запускала сама себя. Существующие build-tag compile/reach/selection
guards сохраняются. Exact executable и evidence bindings должны появиться
вместе с test-only delivery и source wiring, до заявления полной готовности.

Root разрешил tester только placement/budget и исправление holder; source
D4–D7 по-прежнему требует принятого semantic RED. Approved acceptance/design
не меняются, глобальный lifecycle не повышается. [Внешнее событие](https://github.com/PRO-Robotech/kacho/issues/2629#issuecomment-5713801664)
подтверждено API readback и SHA тела; оно принимает план размещения и бюджета,
а не D4–D7 source authorization или уже состоявшийся GREEN.
