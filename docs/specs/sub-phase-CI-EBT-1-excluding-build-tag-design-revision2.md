# CI-EBT-1 — ограниченный замысел, revision 2

Статус: DRAFT revision 2 для заключительного design review. Приёмка отдельно APPROVED событием #2672#5718888294; design approval ещё отсутствует. Автор не выдаёт независимый APPROVED. Предмет — docs/specs/sub-phase-CI-EBT-1-excluding-build-tag-acceptance.md; точные 11 ID — docs/changes/ci-excluding-build-tag/scenario-matrix.json. Изменений продукта пока нет.

## Действующая цепочка

Kacho b5fa: `.github/workflows/ci.yaml:378` → `make test-unit SHARD=...` → Makefile:489–506, `go test ... -race -short -count=1 ... -json` → internal/repohygiene → `TestExcludingBuildTagLeavesThePackageBuildable`, excludingbuildtag_test.go:373 → `repoRoot` license_test.go:59 (по cwd до go.mod) → `auditExcludingBuildTags`:258 → corelib v1.8.0 `treecorpus.UnderWithSuffix` (git-индекс) → headerBuildConstraint/inDefaultBuild/excludedByTag → ленивый `go tool dist list` → baseline `go vet` один раз на пакет → tagged `go vet` по кандидату → находки и census → Go testing → существующий go-test-verdict.py. Новый CI маршрут не нужен.

Сейчас `vetWithTags`:236–246 возвращает только `(текст, bool)`; `audit...`:330–356 теряет текст baseline через `_ = out`, продолжает и возвращает nil error. Любой tagged failure записывается находкой, включая failure загрузчика. Пустоту Go-корпуса проверяет публичный тест:383–385, а не helper. Прежний auditSynthExcluding утверждает факт вызова vet, но не успешность baseline:84–94.

## Минимальный радиус

Единственный изменяемый файл действующего gate: `internal/repohygiene/excludingbuildtag_test.go`. Он хранит production-логику этого CI gate, хотя расширение файла `_test.go`. Здесь же отдельное представление результата внешней команды, невыполненной проверки, итоговая свёртка и печать.

Новый независимый holder после отдельного разрешения: `internal/repohygiene/excludingbuildtag_outcomes_test.go`. Он запускает уже скомпилированный test binary с точным селектором публичного gate и cwd отдельного git-модуля. Это конструктивно проверено данной операционной диагностикой. Дочерний селектор не включает holder, рекурсии нет. Existing excludingbuildtag_injection_test.go, helpers, treecorpus, Go module pins, Makefile, workflows, общий verdict collector сохраняются. Его auditSynthExcluding уже печатает err через Fatal, поэтому новый информативный error доезжает без правки старой пробы.

## Представления и свёртка

Сохранить сигнатуру `auditExcludingBuildTags(root) (findings, census, error)`. Невыполненные проверки накапливать в типизированном error с координатами и причинами; не возвращать раньше завершения независимых пакетов. Уже доказанные findings не стирать. В публичном тесте сначала вывести census/найденное/невыполненное, затем завершить согласно свёртке. Прежние старые поля census сохраняются; новые счётчики отражают реально стартовавшие load/vet-процессы и число невыполненных проверок по полной identity (phase, pkg, file, tag), не число строк вывода. Неуспешный exec.Start не увеличивает process counters. Baseline/global считаются один раз, tagged — по кандидату; прежняя повторяемость tagged вызовов не оптимизируется. GoFilesRead на полном корпусе прежний, а при частичном отказе исправляется на фактическое успешное чтение содержимого: increment после успешного ReadFile, до результата parse. Исторический len(index) назван отдельно в evidence и не объявляется полным чтением.

Одна заключительная строка имеет фиксированный префикс `excluding-build-tag-result: ` и JSON с полями `status`, `go_files_read`, `candidate_files`, `packages_checked`, `vet_runs`, `load_runs`, `findings`, `not_executed`. Все счётчики — целые >=0, статус ровно CLEAN/FINDING/NOT_EXECUTED. Ни одна из ветвей не формирует синтетический успешный результат. Для fatal before-census также выводится частичная перепись и NOT_EXECUTED. CLEAN тогда и только тогда, когда GoFilesRead>0, not_executed=0 и findings=0. При not_executed>0 общий статус NOT_EXECUTED независимо от числа findings; иначе findings>0 означает FINDING.

Это локальный протокол одного gate и его holder; go-test-verdict.py получает обычные PASS/FAIL Go testing. Для NOT_EXECUTED публичный тест падает с явной причиной; менять ExitCode всего пакета или использовать t.Skip запрещено.

## Предусловие компиляторного исхода

Для каждой реально проверяемой конфигурации сохранить настоящий argv/cwd, результат запуска, полный stdout/stderr и причину процесса. Не подменять Go и не исправлять за вызывающего GOWORK. Для baseline/tagged загрузки использовать настоящий `go list -e -json -deps -test` с тем же пакетом/тегом и той же средой. Это новый внешний вызов внутри того же gate, учитываемый отдельно. Полностью разобрать поток JSON-объектов; отсутствие объектов, malformed/trailing output, ненулевой процесс, Error, непустой DepsErrors либо Incomplete — неполнота, даже если `go list -e` вернул 0. Не проверять условие одним grep.

Профиль подтверждён 12 живыми capture: lawful/undefined имеют полный load, GOWORK/replacement-missing имеют объявленные ошибки. После полного baseline-load выполнить текущий настоящий vet. Неуспешный baseline всегда означает NOT_EXECUTED для этого gate — даже когда обычный компилятор сообщил реальную ошибку в исходнике: дефект не приписывается исключающему тегу.

После успешного baseline выполнить полный tagged-load и только затем tagged-vet. CLEAN tagged-конфигурации требует успешного процесса. FINDING требует реально завершившегося неуспешного vet с положительно распознанной компиляторной диагностикой, относящейся к одному из загруженных исходных Go-файлов. Минимальный поддержанный профиль текущего Go — диагностическая строка `vet: <source>:<line>:<column>: <message>` после заголовков `# ...`; source обязан разрешаться в загруженный пакет, line/column положительные. Нельзя распознавать FINDING только по rc, слову `error`, имени тега или наличию двоеточий. Пример настоящего профиля сохранён в evidence/diagnostic-b5fa/captures/defect-vet-json/stderr.txt и defect-tagged/stderr.txt пакета. Полный текст всегда сохраняется, символ не hardcode.

Неизвестный/смешанный диагностический формат, output без подтверждённого компиляторного предмета, запуск не состоялся, сигнал/таймаут — NOT_EXECUTED с причиной. Это консервативный отказ, не разрешение считать неизвестное CLEAN или скрыть его в finding. Профиль не утверждает универсальный parser всех будущих версий Go; смена формы видна как невыполненный gate. Будущий holder должен отдельно держать обычную настоящую компиляторную координату и настоящий loader failure, включая loader-сообщение с source:line:column, чтобы первая подходящая под regex строка не заменила проверку стадии.

Внешние вызовы имеют конечный deadline. Предлагаемая операционная политика — 120 секунд на каждый go list/vet, 30 секунд на go tool dist list; это заявленный запас, не вывод о производительности всего дерева. В этой диагностике tiny-calls укладывались в доли секунды, main не имеет кандидатов. Таймаут никогда не считается FINDING. Пределы и окончательный command profile входят в independent design review до holder; производственные default timeout/CI budget не меняются.

## Независимый держатель и порядок

До фиксации oracle подтвердить binary provenance, git-index fixture bytes, прямые baseline/tagged Go controls. Пары использует один и тот же корень и снимок; разница вычисляется до запуска: одна шапка, одно выражение, один env value, доступность одного dependency-root или одного indexed-file. Различающиеся имена временных каталогов не выдаются за однофактное доказательство. Диагностические input-копии этого исследования не переименовываются задним числом в holder.

В holder — конечные 11 сценариев, включая композиционный CI-EBT-10, где две независимые дельты названы честно. Сохраняются старые 4 теста. Новое утверждение читает полный фактический вывод публичного gate и точные счётчики; шаблон сообщения в исходнике или helper-результат сам по себе не доказывает достижимость публичного отказа.

До worker: независимый RED на baseline failures/неверной классификации загрузки, freeze SHA, root replay. После worker: тот же frozen holder + старые 4 + публичный real-tree gate; compiler/environment поток не пропал, SKIP=0. Существующие public empty/defect проверки уже зелёные на main и должны остаться регрессиями, а не быть объявлены новым найденным дефектом.

## Экспозиция классов для review

1. Внешний go list: rc0 с Error — CI-EBT-07/08. 2. Обычная сборка: потеря текста/предусловия — 06/07. 3. Tagged-команда: loader вместо compiler — 02/08. 4. Пустой корпус против пустой ведомости — 03/04. 5. Платформа/шапка — 04/05 и старые holders. 6. Частичная свёртка — 10. 7. Ошибки исполнения/чтения — 09/11. 8. Public reachability — дочерний public binary во всех сценариях. 9. Новый JSON-итог — ровно одна строка, точные счётчики и NOT_EXECUTED при неполноте. 10. Unknown-format/deadline — явный отказ, отдельный диагностический контроль до разрешения source; нельзя выдумать GREEN по отсутствию известных слов.

Документ не даёт решения о closure, merge, полном CI или исторической причине исходного запуска. Независимое утверждение дизайна и перечня классов остаётся следующим шагом.

## Отдельная полнота диагностического профиля

CI-EBT-01–11 не объявляют покрытие неизвестного формата ответа, malformed JSON-потока загрузчика или deadline. Точные дополнительные контроли описаны отдельно в docs/changes/ci-excluding-build-tag/diagnostic-controls-revision2.md. Исполняемые holder-контроли ещё не написаны и не разрешены. Root отдельно прочитал механизм DC-01/02 и независимо повторил конструкцию DC-03 с настоящим Go и повторными чтениями FIFO; точный root review 85a1899eff9f36cdbbfdf95a996452e9dd37b39ab31ffcedd5e5d3d3b07ab160 связан в evidence/dc03-constructibility/root/root-review.txt пакета. Закрыта только конструктивность OS-level входа: она не доказывает будущий NOT_EXECUTED runner или публичный production deadline. Применение согласованного runner, полный parser и публичная достижимость остаются обязательными заданиями будущего независимого holder. Эти контроли не подделывают executable Go и не подменяют реальный compiler proof.

## Точное множество сценариев замысла

CI-EBT-01, CI-EBT-02, CI-EBT-03, CI-EBT-04, CI-EBT-05, CI-EBT-06, CI-EBT-07, CI-EBT-08, CI-EBT-09, CI-EBT-10, CI-EBT-11. Каждый ID связан с тем же ID в acceptance, tasks, holders.yaml и scenario-matrix.json; равное количество с другими членами не допускается.

## История этой ревизии

Исходный DRAFT design SHA256 65c258c8a81a4c0b337aaf6cc6150a7286bfdaf78adbcc8abec444c6f564ea2e
и исходное diagnostic-controls-proposal.md сохранены побайтно. Эта новая ревизия
связывает фактическое закрытие конструктивной предпосылки и не меняет 11 сценариев,
interface/counters, source scope, production budgets или границы DC-01/02.
Первая неудачная one-write FIFO попытка остаётся историческим NOT_PROVED.
Повторяемый lawful writer выдаёт один правильный документ с EOF каждому открытию;
на Go 1.26.8 измерены два чтения по 46 байт и два EOF. Нельзя заменить его одним
write и считать зависший положительный вход RED продукта. Root replay дал 8
actual Go calls: 6 законных завершений и 2 отмены; все собственные процессы удалены.
Результаты отмены получены операционным parent, не ещё отсутствующим gate runner.
